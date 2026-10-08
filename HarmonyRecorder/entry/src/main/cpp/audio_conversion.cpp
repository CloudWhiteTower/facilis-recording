#include "audio_conversion.h"
#include "pcm_conversion.h"
#include <multimedia/native_audio_channel_layout.h>
#include <multimedia/player_framework/native_avbuffer.h>
#include <multimedia/player_framework/native_avcodec_audiocodec.h>
#include <multimedia/player_framework/native_avcodec_base.h>
#include <multimedia/player_framework/native_avdemuxer.h>
#include <multimedia/player_framework/native_avformat.h>
#include <multimedia/player_framework/native_avmuxer.h>
#include <multimedia/player_framework/native_avsource.h>

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <cstring>
#include <fcntl.h>
#include <functional>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <unordered_map>
#include <unistd.h>

namespace {
using facilis::ReadLe;
using facilis::WriteLe;
using Format = std::unique_ptr<OH_AVFormat, decltype(&OH_AVFormat_Destroy)>;
using Buffer = std::unique_ptr<OH_AVBuffer, decltype(&OH_AVBuffer_Destroy)>;
using Clock = std::chrono::steady_clock;
constexpr int64_t WAIT_US = 20000;
constexpr auto STALL_LIMIT = std::chrono::seconds(5);
constexpr size_t CHUNK_SAMPLES = 32768;
constexpr size_t CODEC_BATCH_FRAMES = 8;

void Need(bool value, const char *message)
{
    if (!value) { throw std::runtime_error(message); }
}

void Check(OH_AVErrCode value, const char *operation)
{
    if (value != AV_ERR_OK) {
        throw std::runtime_error(std::string(operation) + " failed (AVCodec " + std::to_string(value) + ")");
    }
}

void ReadAt(int fd, uint8_t *data, size_t size, int64_t offset)
{
    size_t done = 0;
    while (done < size) {
        const auto count = pread(fd, data + done, size - done, offset + static_cast<int64_t>(done));
        if (count < 0 && errno == EINTR) { continue; }
        Need(count > 0, "Audio input is truncated or cannot be read");
        done += static_cast<size_t>(count);
    }
}

void WriteAt(int fd, const uint8_t *data, size_t size, int64_t offset)
{
    size_t done = 0;
    while (done < size) {
        const auto count = pwrite(fd, data + done, size - done, offset + static_cast<int64_t>(done));
        if (count < 0 && errno == EINTR) { continue; }
        Need(count > 0, "Audio output write failed; check free storage space");
        done += static_cast<size_t>(count);
    }
}

struct Conversion {
    napi_env owner = nullptr;
    std::mutex runMutex;
    std::atomic<bool> cancelled{false};
    std::atomic<double> progress{0};
    int input = -1;
    int output = -1;
    int64_t inputSize = 0;
    std::string target;
    int32_t targetDepth = 16;
    int32_t bitrate = 0;
    int32_t rate = 0;
    int32_t channels = 1;
    uint64_t samples = 0;
    int64_t sizeBytes = 0;
    bool started = false;

    ~Conversion()
    {
        if (input >= 0) { close(input); }
        if (output >= 0) { close(output); }
    }
    void CheckCancelled() const { Need(!cancelled.load(), "Conversion cancelled"); }
    void ValidateAudio() const
    {
        Need(rate == 44100 || rate == 48000, "Conversion supports 44.1 or 48 kHz recordings; resampling is unavailable");
        Need(channels == 1, "Conversion currently preserves mono recordings only; downmixing is unavailable");
    }
};

class WavWriter final : public NativePcmWriter {
public:
    WavWriter(int fd, int rate, int depth) : fd_(fd), rate_(rate), depth_(depth) {}
    void Write(const uint8_t *pcm, size_t size) override
    {
        Need(size % (depth_ / 8) == 0, "WAV output must contain complete PCM samples");
        Need(bytes_ + size <= 0xfffffffeULL - 36, "WAV output exceeds the RIFF 4 GiB limit");
        WriteAt(fd_, pcm, size, static_cast<int64_t>(44 + bytes_));
        bytes_ += size;
    }
    void Finish() override
    {
        Need(bytes_ > 0, "Converted audio contains no samples");
        const uint8_t pad = 0;
        if (bytes_ % 2 != 0) { WriteAt(fd_, &pad, 1, static_cast<int64_t>(44 + bytes_)); }
        uint8_t header[44]{};
        std::memcpy(header, "RIFF", 4);
        WriteLe(header + 4, static_cast<uint32_t>(36 + bytes_ + bytes_ % 2), 4);
        std::memcpy(header + 8, "WAVEfmt ", 8);
        WriteLe(header + 16, 16, 4);
        WriteLe(header + 20, 1, 2);
        WriteLe(header + 22, 1, 2);
        WriteLe(header + 24, static_cast<uint32_t>(rate_), 4);
        WriteLe(header + 28, static_cast<uint32_t>(rate_ * depth_ / 8), 4);
        WriteLe(header + 32, static_cast<uint32_t>(depth_ / 8), 2);
        WriteLe(header + 34, static_cast<uint32_t>(depth_), 2);
        std::memcpy(header + 36, "data", 4);
        WriteLe(header + 40, static_cast<uint32_t>(bytes_), 4);
        WriteAt(fd_, header, sizeof(header), 0);
        Need(ftruncate(fd_, static_cast<off_t>(44 + bytes_ + bytes_ % 2)) == 0, "Finalize WAV length failed");
    }
private:
    int fd_;
    int rate_;
    int depth_;
    uint64_t bytes_ = 0;
};

// AAC receives float PCM for 24-bit sources, avoiding an intermediate 16-bit truncation.
class AacWriter final : public NativePcmWriter {
public:
    AacWriter(Conversion &job, bool floatInput) : job_(job), floatInput_(floatInput),
        frameBytes_(1024 * (floatInput ? 4 : 2))
    {
        try {
            codec_ = OH_AudioCodec_CreateByMime(OH_AVCODEC_MIMETYPE_AUDIO_AAC, true);
            Need(codec_ != nullptr, "This device does not provide an AAC encoder");
            muxer_ = OH_AVMuxer_Create(job.output, AV_OUTPUT_FORMAT_M4A);
            Need(muxer_ != nullptr, "This device does not provide an M4A muxer");
            Format format(OH_AVFormat_Create(), OH_AVFormat_Destroy);
            Need(format != nullptr, "Could not allocate AAC format");
            SetAudio(format.get());
            Need(OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_ENABLE_SYNC_MODE, 1), "Set AAC sync mode failed");
            Check(OH_AudioCodec_Configure(codec_, format.get()), "Configure AAC encoder");
            Check(OH_AudioCodec_Prepare(codec_), "Prepare AAC encoder");
            Check(OH_AudioCodec_Start(codec_), "Start AAC encoder");
            codecStarted_ = true;
            pending_.reserve(frameBytes_);
        } catch (...) { Close(); throw; }
    }
    ~AacWriter() override { Close(); }
    void Write(const uint8_t *pcm, size_t size) override
    {
        Need(size % (floatInput_ ? 4 : 2) == 0, "AAC input ends in a partial PCM sample");
        if (size == 0) { return; }
        Need(pcm != nullptr, "AAC input has no data address");
        size_t offset = 0;
        if (!pending_.empty()) {
            const auto count = std::min(frameBytes_ - pending_.size(), size);
            pending_.insert(pending_.end(), pcm, pcm + count);
            offset += count;
            if (pending_.size() == frameBytes_) { Push(pending_.data(), pending_.size(), false); pending_.clear(); }
        }
        // Full frames can go straight into the codec. Only the incomplete tail
        // needs an owned copy that survives the caller's buffer lifetime.
        while (size - offset >= frameBytes_) {
            Push(pcm + offset, frameBytes_, false);
            offset += frameBytes_;
        }
        pending_.insert(pending_.end(), pcm + offset, pcm + size);
    }
    void Finish() override
    {
        if (!pending_.empty()) { Push(pending_.data(), pending_.size(), false); pending_.clear(); }
        Need(samples_ > 0, "Converted audio contains no samples");
        Push(nullptr, 0, true);
        Drain(true);
        Need(muxerStarted_ && encodedFrames_ > 0, "AAC encoder produced no audio frames");
        Check(OH_AVMuxer_Stop(muxer_), "Finalize M4A");
        muxerStarted_ = false;
        Check(OH_AudioCodec_Stop(codec_), "Stop AAC encoder");
        codecStarted_ = false;
    }
private:
    Conversion &job_;
    bool floatInput_;
    size_t frameBytes_;
    OH_AVCodec *codec_ = nullptr;
    OH_AVMuxer *muxer_ = nullptr;
    int32_t track_ = -1;
    bool codecStarted_ = false;
    bool muxerStarted_ = false;
    bool eos_ = false;
    uint64_t samples_ = 0;
    uint64_t encodedFrames_ = 0;
    std::vector<uint8_t> pending_;

    void Close() noexcept
    {
        if (codec_) {
            if (codecStarted_) { OH_AudioCodec_Stop(codec_); }
            OH_AudioCodec_Destroy(codec_); codec_ = nullptr;
        }
        if (muxer_) {
            if (muxerStarted_) { OH_AVMuxer_Stop(muxer_); }
            OH_AVMuxer_Destroy(muxer_); muxer_ = nullptr;
        }
    }
    void SetAudio(OH_AVFormat *format)
    {
        Need(OH_AVFormat_SetStringValue(format, OH_MD_KEY_CODEC_MIME, OH_AVCODEC_MIMETYPE_AUDIO_AAC) &&
            OH_AVFormat_SetIntValue(format, OH_MD_KEY_AUD_SAMPLE_RATE, job_.rate) &&
            OH_AVFormat_SetIntValue(format, OH_MD_KEY_AUD_CHANNEL_COUNT, 1) &&
            OH_AVFormat_SetIntValue(format, OH_MD_KEY_AUDIO_SAMPLE_FORMAT, floatInput_ ? SAMPLE_F32LE : SAMPLE_S16LE) &&
            OH_AVFormat_SetLongValue(format, OH_MD_KEY_CHANNEL_LAYOUT, CH_LAYOUT_MONO) &&
            OH_AVFormat_SetLongValue(format, OH_MD_KEY_BITRATE, job_.bitrate) &&
            OH_AVFormat_SetIntValue(format, OH_MD_KEY_PROFILE, AAC_PROFILE_LC), "Set AAC parameters failed");
    }
    void StartMuxer()
    {
        if (muxerStarted_) { return; }
        Format format(OH_AudioCodec_GetOutputDescription(codec_), OH_AVFormat_Destroy);
        Need(format != nullptr, "AAC output format is unavailable");
        SetAudio(format.get());
        // AAC encoder emits ADTS. The platform M4A muxer consumes it and writes ASC.
        Check(OH_AVMuxer_AddTrack(muxer_, &track_, format.get()), "Add M4A audio track");
        Check(OH_AVMuxer_Start(muxer_), "Start M4A muxer");
        muxerStarted_ = true;
    }
    void Push(const uint8_t *data, size_t size, bool eos)
    {
        const auto deadline = Clock::now() + STALL_LIMIT;
        uint32_t index = 0;
        for (;;) {
            job_.CheckCancelled();
            const auto result = OH_AudioCodec_QueryInputBuffer(codec_, &index, WAIT_US);
            if (result == AV_ERR_OK) { break; }
            Check(result == AV_ERR_TRY_AGAIN_LATER ? AV_ERR_OK : result, "Query AAC input");
            Drain(false);
            Need(Clock::now() < deadline, "AAC encoder input timed out");
        }
        auto *buffer = OH_AudioCodec_GetInputBuffer(codec_, index);
        Need(buffer != nullptr && OH_AVBuffer_GetCapacity(buffer) >= static_cast<int32_t>(size), "AAC input buffer is too small");
        if (size) {
            auto *address = OH_AVBuffer_GetAddr(buffer);
            Need(address != nullptr, "AAC input has no data address");
            std::memcpy(address, data, size);
        }
        OH_AVCodecBufferAttr attr{};
        attr.pts = static_cast<int64_t>(samples_ * 1000000 / job_.rate);
        attr.size = static_cast<int32_t>(size);
        attr.flags = eos ? AVCODEC_BUFFER_FLAGS_EOS : AVCODEC_BUFFER_FLAGS_NONE;
        Check(OH_AVBuffer_SetBufferAttr(buffer, &attr), "Set AAC input attributes");
        Check(OH_AudioCodec_PushInputBuffer(codec_, index), "Push AAC PCM");
        samples_ += size / (floatInput_ ? 4 : 2);
        Drain(false);
    }
    void Drain(bool untilEos)
    {
        auto deadline = Clock::now() + STALL_LIMIT;
        while (!eos_) {
            job_.CheckCancelled();
            Need(Clock::now() < deadline, "AAC encoder output timed out");
            uint32_t index = 0;
            const auto result = OH_AudioCodec_QueryOutputBuffer(codec_, &index, untilEos ? WAIT_US : 0);
            if (result == AV_ERR_TRY_AGAIN_LATER) {
                if (!untilEos) { return; }
                Need(Clock::now() < deadline, "AAC encoder output timed out"); continue;
            }
            if (result == AV_ERR_STREAM_CHANGED) {
                Need(Clock::now() < deadline, "AAC output format repeatedly changed"); continue;
            }
            Check(result, "Query AAC output");
            bool receivedData = false;
            try {
                auto *buffer = OH_AudioCodec_GetOutputBuffer(codec_, index);
                Need(buffer != nullptr, "AAC output buffer is unavailable");
                OH_AVCodecBufferAttr attr{};
                Check(OH_AVBuffer_GetBufferAttr(buffer, &attr), "Read AAC output attributes");
                eos_ = (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0;
                // EOS may retain the previous payload. It is only an end marker.
                if (!eos_ && attr.size > 0) {
                    Need(attr.offset >= 0 && static_cast<int64_t>(attr.offset) + attr.size <= OH_AVBuffer_GetCapacity(buffer),
                        "Invalid AAC output buffer");
                    StartMuxer();
                    Check(OH_AVMuxer_WriteSampleBuffer(muxer_, static_cast<uint32_t>(track_), buffer), "Write AAC frame");
                    if (!(attr.flags & AVCODEC_BUFFER_FLAGS_CODEC_DATA)) { ++encodedFrames_; }
                    receivedData = true;
                }
            } catch (...) { OH_AudioCodec_FreeOutputBuffer(codec_, index); throw; }
            Check(OH_AudioCodec_FreeOutputBuffer(codec_, index), "Release AAC output");
            if (receivedData) { deadline = Clock::now() + STALL_LIMIT; }
        }
    }
};

std::unique_ptr<NativePcmWriter> MakeWriter(Conversion &job, bool floatInput)
{
    if (job.target == "flac") {
        return CreateFlacPcm16Writer(job.output, job.rate, [&job]() { job.CheckCancelled(); });
    }
    if (job.target == "wav") { return std::make_unique<WavWriter>(job.output, job.rate, job.targetDepth); }
    return std::make_unique<AacWriter>(job, floatInput);
}

facilis::PcmFormat PcmFormatFor(int format)
{
    if (format == SAMPLE_S16LE) { return facilis::PcmFormat::S16LE; }
    if (format == SAMPLE_S24LE) { return facilis::PcmFormat::S24LE; }
    if (format == SAMPLE_S32LE) { return facilis::PcmFormat::S32LE; }
    Need(format == SAMPLE_F32LE, "Unsupported decoded PCM representation");
    return facilis::PcmFormat::F32LE;
}

void WritePcm(NativePcmWriter &writer, const uint8_t *input, size_t bytes, int sourceFormat,
    int targetFormat, std::vector<uint8_t> &scratch)
{
    if (sourceFormat == targetFormat) { writer.Write(input, bytes); return; }
    facilis::RepackPcm(input, bytes, PcmFormatFor(sourceFormat), PcmFormatFor(targetFormat), scratch);
    writer.Write(scratch);
}

void ConvertWav(Conversion &job)
{
    uint8_t header[12];
    ReadAt(job.input, header, sizeof(header), 0);
    const int64_t riffEnd = static_cast<int64_t>(ReadLe(header + 4, 4)) + 8;
    Need(riffEnd <= job.inputSize && riffEnd >= 12, "WAV RIFF size is invalid");
    int64_t dataOffset = -1;
    uint32_t dataSize = 0;
    int depth = 0;
    bool foundFormat = false;
    uint32_t chunks = 0;
    for (int64_t offset = 12; offset + 8 <= riffEnd;) {
        job.CheckCancelled();
        Need(++chunks <= 100000, "WAV contains too many metadata chunks");
        uint8_t chunk[8];
        ReadAt(job.input, chunk, sizeof(chunk), offset);
        const uint32_t length = ReadLe(chunk + 4, 4);
        Need(offset + 8 + length <= riffEnd, "WAV chunk exceeds the file length");
        if (std::memcmp(chunk, "fmt ", 4) == 0) {
            Need(!foundFormat && length >= 16, "WAV has an invalid format chunk");
            uint8_t format[16];
            ReadAt(job.input, format, sizeof(format), offset + 8);
            Need(ReadLe(format, 2) == 1, "Conversion supports uncompressed integer PCM WAV only");
            job.channels = static_cast<int>(ReadLe(format + 2, 2));
            job.rate = static_cast<int>(ReadLe(format + 4, 4));
            depth = static_cast<int>(ReadLe(format + 14, 2));
            Need(depth == 16 || depth == 24, "WAV must contain 16-bit or 24-bit PCM");
            Need(ReadLe(format + 12, 2) == static_cast<uint32_t>(job.channels * depth / 8), "WAV block alignment is invalid");
            job.ValidateAudio(); foundFormat = true;
        } else if (std::memcmp(chunk, "data", 4) == 0) {
            Need(dataOffset < 0, "Multiple WAV data chunks are not supported");
            dataOffset = offset + 8; dataSize = length;
        }
        offset += 8 + static_cast<int64_t>(length) + length % 2;
    }
    Need(foundFormat && dataOffset >= 0 && dataSize > 0, "WAV contains no PCM audio");
    Need(dataSize % (depth / 8) == 0, "WAV has a partial PCM sample");
    Need(!(depth == 24 && job.target != "m4a" && job.targetDepth < 24),
        "24-bit to 16-bit conversion requires an explicit dithering policy and is not supported");
    const int sourceFormat = depth == 24 ? SAMPLE_S24LE : SAMPLE_S16LE;
    const int targetFormat = job.target == "m4a" && depth == 24 ? SAMPLE_F32LE :
        (job.target != "m4a" && job.targetDepth == 24 ? SAMPLE_S24LE : SAMPLE_S16LE);
    auto writer = MakeWriter(job, targetFormat == SAMPLE_F32LE);
    std::vector<uint8_t> input(CHUNK_SAMPLES * (depth / 8));
    std::vector<uint8_t> scratch;
    uint64_t done = 0;
    while (done < dataSize) {
        job.CheckCancelled();
        const size_t count = static_cast<size_t>(std::min<uint64_t>(input.size(), dataSize - done));
        ReadAt(job.input, input.data(), count, dataOffset + static_cast<int64_t>(done));
        WritePcm(*writer, input.data(), count, sourceFormat, targetFormat, scratch);
        done += count;
        job.samples += count / (depth / 8);
        job.progress.store(0.97 * static_cast<double>(done) / dataSize);
    }
    job.CheckCancelled(); writer->Finish();
}

class Decoder {
public:
    explicit Decoder(Conversion &job) : job_(job) {}
    ~Decoder()
    {
        if (codec_) { if (started_) { OH_AudioCodec_Stop(codec_); } OH_AudioCodec_Destroy(codec_); }
        if (demuxer_) { OH_AVDemuxer_Destroy(demuxer_); }
        if (source_) { OH_AVSource_Destroy(source_); }
    }
    void Run()
    {
        source_ = OH_AVSource_CreateWithFD(job_.input, 0, job_.inputSize);
        Need(source_ != nullptr, "Audio container cannot be opened by the system demuxer");
        Format sourceFormat(OH_AVSource_GetSourceFormat(source_), OH_AVFormat_Destroy);
        int32_t tracks = 0;
        Need(sourceFormat && OH_AVFormat_GetIntValue(sourceFormat.get(), OH_MD_KEY_TRACK_COUNT, &tracks) && tracks > 0,
            "Audio source has no media tracks");
        OH_AVFormat_GetLongValue(sourceFormat.get(), OH_MD_KEY_DURATION, &durationUs_);
        Format audio(nullptr, OH_AVFormat_Destroy);
        for (int32_t i = 0; i < tracks; ++i) {
            Format candidate(OH_AVSource_GetTrackFormat(source_, static_cast<uint32_t>(i)), OH_AVFormat_Destroy);
            int32_t type = -1;
            if (candidate && OH_AVFormat_GetIntValue(candidate.get(), OH_MD_KEY_TRACK_TYPE, &type) && type == MEDIA_TYPE_AUD) {
                Need(!audio, "Conversion supports one audio track only");
                audio = std::move(candidate); track_ = static_cast<uint32_t>(i);
            }
        }
        Need(audio != nullptr, "Source has no audio track");
        const char *mime = nullptr;
        Need(OH_AVFormat_GetStringValue(audio.get(), OH_MD_KEY_CODEC_MIME, &mime) && mime,
            "Audio codec information is missing");
        const std::string mimeString(mime);
        Need(mimeString == OH_AVCODEC_MIMETYPE_AUDIO_AAC || mimeString == OH_AVCODEC_MIMETYPE_AUDIO_FLAC,
            "Conversion supports AAC M4A, FLAC and PCM WAV recordings only");
        Need(OH_AVFormat_GetIntValue(audio.get(), OH_MD_KEY_AUD_SAMPLE_RATE, &job_.rate) &&
            OH_AVFormat_GetIntValue(audio.get(), OH_MD_KEY_AUD_CHANNEL_COUNT, &job_.channels), "Audio format is missing");
        job_.ValidateAudio();
        // A 24-bit FLAC source must not be silently reduced to 16-bit PCM.
        if (mimeString == OH_AVCODEC_MIMETYPE_AUDIO_FLAC) { CheckFlacDepth(); }
        pcmFormat_ = job_.targetDepth == 24 && job_.target != "m4a" ? SAMPLE_S32LE :
            (job_.target == "m4a" ? SAMPLE_F32LE : SAMPLE_S16LE);
        Need(OH_AVFormat_SetIntValue(audio.get(), OH_MD_KEY_AUDIO_SAMPLE_FORMAT, pcmFormat_) &&
            OH_AVFormat_SetIntValue(audio.get(), OH_MD_KEY_ENABLE_SYNC_MODE, 1), "Set decoder PCM format failed");
        // Keep demuxer codec_config and sample metadata, including AAC priming information.
        codec_ = OH_AudioCodec_CreateByMime(mimeString.c_str(), false);
        Need(codec_ != nullptr, "The device does not provide the required audio decoder");
        Check(OH_AudioCodec_Configure(codec_, audio.get()), "Configure audio decoder");
        Check(OH_AudioCodec_Prepare(codec_), "Prepare audio decoder");
        demuxer_ = OH_AVDemuxer_CreateWithSource(source_);
        Need(demuxer_ != nullptr, "Cannot create audio demuxer");
        Check(OH_AVDemuxer_SelectTrackByID(demuxer_, track_), "Select audio track");
        Check(OH_AudioCodec_Start(codec_), "Start audio decoder"); started_ = true;
        writer_ = MakeWriter(job_, pcmFormat_ == SAMPLE_F32LE);
        Buffer demuxBuffer(OH_AVBuffer_Create(64 * 1024), OH_AVBuffer_Destroy);
        Need(demuxBuffer != nullptr, "Could not allocate demuxer sample buffer");
        auto deadline = Clock::now() + STALL_LIMIT;
        bool inputEos = false;
        bool outputEos = false;
        while (!outputEos) {
            job_.CheckCancelled();
            Need(Clock::now() < deadline, "Audio decoding stalled");
            bool moved = false;
            // Keep the codec fed and drain all immediately available output.
            // Blocking once per compressed frame unnecessarily serializes a
            // file conversion around the decoder's scheduling latency.
            for (size_t frame = 0; frame < CODEC_BATCH_FRAMES && !inputEos; ++frame) {
                if (!SupplyInput(demuxBuffer.get(), inputEos)) { break; }
                moved = true;
            }
            for (size_t frame = 0; frame < CODEC_BATCH_FRAMES && !outputEos; ++frame) {
                if (!DrainOutput(0, outputEos, moved)) { break; }
            }
            // When neither end progresses, block briefly instead of busy
            // spinning; cancellation and the five-second stall limit remain.
            if (!moved && !outputEos) { DrainOutput(WAIT_US, outputEos, moved); }
            if (moved) { deadline = Clock::now() + STALL_LIMIT; }
            Need(Clock::now() < deadline, "Audio decoding stalled");
        }
        if (job_.samples == 0) {
            throw std::runtime_error("Decoded audio contains no samples (input=" + std::to_string(inputFrames_) +
                ", output=" + std::to_string(outputBuffers_) + ", lastSize=" + std::to_string(lastOutputSize_) +
                ", lastFlags=" + std::to_string(lastOutputFlags_) + ")");
        }
        job_.CheckCancelled(); writer_->Finish(); writer_.reset();
        Check(OH_AudioCodec_Stop(codec_), "Stop audio decoder"); started_ = false;
    }
private:
    Conversion &job_;
    OH_AVSource *source_ = nullptr;
    OH_AVDemuxer *demuxer_ = nullptr;
    OH_AVCodec *codec_ = nullptr;
    bool started_ = false;
    uint32_t track_ = 0;
    int64_t durationUs_ = 0;
    int pcmFormat_ = SAMPLE_S16LE;
    uint64_t inputFrames_ = 0;
    uint64_t outputBuffers_ = 0;
    int32_t lastOutputSize_ = 0;
    uint32_t lastOutputFlags_ = 0;
    std::unique_ptr<NativePcmWriter> writer_;
    std::vector<uint8_t> pcmScratch_;
    bool SupplyInput(OH_AVBuffer *demuxBuffer, bool &inputEos)
    {
        job_.CheckCancelled();
        uint32_t index = 0;
        const auto result = OH_AudioCodec_QueryInputBuffer(codec_, &index, 0);
        if (result == AV_ERR_TRY_AGAIN_LATER) { return false; }
        Check(result, "Query decoder input");
        auto *buffer = OH_AudioCodec_GetInputBuffer(codec_, index);
        Need(buffer != nullptr, "Decoder input buffer is unavailable");
        OH_AVCodecBufferAttr attr{};
        Check(OH_AVBuffer_SetBufferAttr(demuxBuffer, &attr), "Reset demuxer attributes");
        Check(OH_AVDemuxer_ReadSampleBuffer(demuxer_, track_, demuxBuffer), "Read encoded audio frame");
        Check(OH_AVBuffer_GetBufferAttr(demuxBuffer, &attr), "Read demuxer frame attributes");
        inputEos = (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0;
        if (inputEos) { attr.size = 0; attr.offset = 0; attr.flags = AVCODEC_BUFFER_FLAGS_EOS; }
        else {
            Need(attr.size > 0 && attr.offset >= 0 && static_cast<int64_t>(attr.offset) + attr.size <=
                OH_AVBuffer_GetCapacity(demuxBuffer), "Demuxer produced invalid sample bounds");
            Need(attr.size <= OH_AVBuffer_GetCapacity(buffer), "Encoded frame exceeds decoder input capacity");
            const auto *from = OH_AVBuffer_GetAddr(demuxBuffer);
            auto *to = OH_AVBuffer_GetAddr(buffer);
            Need(from && to, "Audio sample buffer has no address");
            std::memcpy(to, from + attr.offset, static_cast<size_t>(attr.size));
            attr.offset = 0;
            ++inputFrames_;
        }
        // Preserve sample metadata, including AAC priming information.
        Format parameters(OH_AVBuffer_GetParameter(demuxBuffer), OH_AVFormat_Destroy);
        if (parameters) { Check(OH_AVBuffer_SetParameter(buffer, parameters.get()), "Copy demuxer sample metadata"); }
        Check(OH_AVBuffer_SetBufferAttr(buffer, &attr), "Set decoder input attributes");
        Check(OH_AudioCodec_PushInputBuffer(codec_, index), "Push encoded audio frame");
        return true;
    }
    bool DrainOutput(int64_t waitUs, bool &outputEos, bool &moved)
    {
        job_.CheckCancelled();
        uint32_t index = 0;
        const auto result = OH_AudioCodec_QueryOutputBuffer(codec_, &index, waitUs);
        if (result == AV_ERR_TRY_AGAIN_LATER) { return false; }
        if (result == AV_ERR_STREAM_CHANGED) { ReadOutputFormat(); return true; }
        Check(result, "Query decoder output");
        const auto previousSamples = job_.samples;
        try { outputEos = Consume(index); }
        catch (...) { OH_AudioCodec_FreeOutputBuffer(codec_, index); throw; }
        Check(OH_AudioCodec_FreeOutputBuffer(codec_, index), "Release decoded PCM");
        moved = moved || outputEos || job_.samples > previousSamples;
        // Report PCM actually consumed rather than compressed frames merely
        // queued: the progress bar follows work completed by the whole pipeline.
        if (durationUs_ > 0) {
            const double progress = std::min(0.97, static_cast<double>(job_.samples) * 1000000.0 /
                (static_cast<double>(job_.rate) * durationUs_) * 0.97);
            job_.progress.store(std::max(job_.progress.load(), progress));
        }
        return true;
    }
    void CheckFlacDepth()
    {
        uint8_t info[42];
        Need(job_.inputSize >= static_cast<int64_t>(sizeof(info)), "FLAC STREAMINFO is missing");
        ReadAt(job_.input, info, sizeof(info), 0);
        Need(std::memcmp(info, "fLaC", 4) == 0 && (info[4] & 0x7f) == 0 && info[5] == 0 && info[6] == 0 && info[7] == 34,
            "FLAC STREAMINFO is invalid");
        const int depth = (((info[20] & 1) << 4) | (info[21] >> 4)) + 1;
        Need(depth == 16 || depth == 24, "FLAC source must use 16-bit or 24-bit samples");
        Need(!(depth == 24 && job_.target != "m4a" && job_.targetDepth < 24),
            "24-bit to 16-bit conversion requires an explicit dithering policy and is not supported");
    }
    void ReadOutputFormat()
    {
        Format format(OH_AudioCodec_GetOutputDescription(codec_), OH_AVFormat_Destroy);
        Need(format != nullptr, "Decoder output format is unavailable");
        int32_t rate = 0, channels = 0, sampleFormat = INVALID_WIDTH;
        Need(OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_AUD_SAMPLE_RATE, &rate) &&
            OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_AUD_CHANNEL_COUNT, &channels) &&
            OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_AUDIO_SAMPLE_FORMAT, &sampleFormat),
            "Decoder output format is incomplete");
        Need(rate == job_.rate && channels == job_.channels, "Decoder changed the source rate or channel count");
        Need(sampleFormat == pcmFormat_, "Decoder did not honor the requested PCM format");
    }
    bool Consume(uint32_t index)
    {
        auto *buffer = OH_AudioCodec_GetOutputBuffer(codec_, index);
        Need(buffer != nullptr, "Decoded PCM buffer is unavailable");
        OH_AVCodecBufferAttr attr{};
        Check(OH_AVBuffer_GetBufferAttr(buffer, &attr), "Read decoded PCM attributes");
        ++outputBuffers_; lastOutputSize_ = attr.size; lastOutputFlags_ = attr.flags;
        if (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) { return true; }
        // Audio decoder output is PCM. CODEC_DATA may be propagated from a
        // compressed input; unlike an encoder output it is not a header to drop.
        if (attr.size == 0) { return false; }
        Need(attr.offset >= 0 && attr.size > 0 && static_cast<int64_t>(attr.offset) + attr.size <= OH_AVBuffer_GetCapacity(buffer),
            "Decoded PCM buffer bounds are invalid");
        auto *data = OH_AVBuffer_GetAddr(buffer);
        Need(data != nullptr, "Decoded PCM has no data address");
        const int outputFormat = job_.targetDepth == 24 && job_.target != "m4a" ? SAMPLE_S24LE : pcmFormat_;
        WritePcm(*writer_, data + attr.offset, static_cast<size_t>(attr.size), pcmFormat_, outputFormat, pcmScratch_);
        job_.samples += static_cast<uint64_t>(attr.size) / (pcmFormat_ == SAMPLE_S16LE ? 2 : 4);
        return false;
    }
};

void RunConversion(Conversion &job)
{
    job.CheckCancelled();
    Need(!job.started, "Conversion has already started; create a new conversion to retry");
    job.started = true;
    uint8_t signature[12];
    Need(job.inputSize >= static_cast<int64_t>(sizeof(signature)), "Audio input is too short");
    ReadAt(job.input, signature, sizeof(signature), 0);
    if (std::memcmp(signature, "RIFF", 4) == 0 && std::memcmp(signature + 8, "WAVE", 4) == 0) { ConvertWav(job); }
    else { Decoder decoder(job); decoder.Run(); }
    job.CheckCancelled();
    Need(fsync(job.output) == 0, "Flush converted audio failed");
    struct stat result{};
    Need(fstat(job.output, &result) == 0 && result.st_size > 0, "Converted output is empty");
    job.sizeBytes = result.st_size;
    job.progress.store(1);
}

std::mutex conversionsMutex;
std::unordered_map<int64_t, std::shared_ptr<Conversion>> conversions;
std::atomic<int64_t> nextConversion{1};

std::shared_ptr<Conversion> Find(napi_env env, int64_t handle, bool optional = false)
{
    std::lock_guard<std::mutex> lock(conversionsMutex);
    auto found = conversions.find(handle);
    if (found == conversions.end() || found->second->owner != env) {
        Need(optional, "Conversion handle is invalid or has been released"); return nullptr;
    }
    return found->second;
}

int64_t Integer(napi_env env, napi_value value, int64_t minimum, int64_t maximum, const char *message)
{
    double number = 0;
    Need(napi_get_value_double(env, value, &number) == napi_ok && std::isfinite(number) &&
        std::floor(number) == number && number >= minimum && number <= maximum, message);
    return static_cast<int64_t>(number);
}

int64_t Handle(napi_env env, napi_callback_info info)
{
    size_t count = 1;
    napi_value value{};
    Need(napi_get_cb_info(env, info, &count, &value, nullptr, nullptr) == napi_ok && count == 1,
        "Conversion operation requires a handle");
    return Integer(env, value, 1, 9007199254740991LL, "Invalid conversion handle");
}

enum class Action { CREATE, RUN, RELEASE };
struct Call {
    napi_env env = nullptr;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    Action action;
    int64_t handle = 0;
    int sourceFd = -1;
    int targetFd = -1;
    std::shared_ptr<Conversion> job;
    std::string error;
};

void CreateJob(Call &call)
{
    auto &job = *call.job;
    struct stat source{}, target{};
    Need(fstat(call.sourceFd, &source) == 0 && S_ISREG(source.st_mode) && source.st_size == job.inputSize && job.inputSize > 0,
        "Source fd must be a complete regular audio file");
    Need(fstat(call.targetFd, &target) == 0 && S_ISREG(target.st_mode) && target.st_size == 0,
        "Target fd must be a new empty temporary file");
    Need(source.st_dev != target.st_dev || source.st_ino != target.st_ino, "Source and target must be different files");
    const int inputFlags = fcntl(call.sourceFd, F_GETFL);
    const int outputFlags = fcntl(call.targetFd, F_GETFL);
    Need(inputFlags >= 0 && (inputFlags & O_ACCMODE) != O_WRONLY, "Source fd is not readable");
    Need(outputFlags >= 0 && (outputFlags & O_ACCMODE) == O_RDWR && !(outputFlags & O_APPEND),
        "Target fd must be READ_WRITE without append mode");
    job.input = fcntl(call.sourceFd, F_DUPFD_CLOEXEC, 0);
    Need(job.input >= 0, "Could not retain source fd");
    job.output = fcntl(call.targetFd, F_DUPFD_CLOEXEC, 0);
    Need(job.output >= 0, "Could not retain target fd");
    Need(lseek(job.output, 0, SEEK_SET) == 0, "Target file must be seekable");
    call.handle = nextConversion.fetch_add(1);
    std::lock_guard<std::mutex> lock(conversionsMutex);
    Need(conversions.size() < 2, "Too many conversions; finish or cancel the current conversion first");
    conversions.emplace(call.handle, call.job);
}

void Execute(napi_env, void *data)
{
    auto &call = *static_cast<Call *>(data);
    try {
        if (call.action == Action::CREATE) { CreateJob(call); return; }
        call.job = Find(call.env, call.handle, call.action == Action::RELEASE);
        if (!call.job) { return; }
        if (call.action == Action::RELEASE) { call.job->cancelled.store(true); }
        std::lock_guard<std::mutex> operation(call.job->runMutex);
        if (call.action == Action::RUN) { RunConversion(*call.job); }
        else {
            std::lock_guard<std::mutex> lock(conversionsMutex);
            conversions.erase(call.handle);
            // Close only our duplicated descriptors, after the running codec has stopped.
            if (call.job->input >= 0) { close(call.job->input); call.job->input = -1; }
            if (call.job->output >= 0) { close(call.job->output); call.job->output = -1; }
        }
    } catch (const std::exception &error) { call.error = error.what(); }
    catch (...) { call.error = "Unknown native audio conversion failure"; }
}

void Reject(napi_env env, napi_deferred deferred, const std::string &message)
{
    napi_value text{}, error{}, code{};
    const char *errorCode = message == "Conversion cancelled" ? "CANCELLED" : "AUDIO_CONVERSION_FAILED";
    napi_create_string_utf8(env, message.c_str(), message.size(), &text);
    napi_create_string_utf8(env, errorCode, NAPI_AUTO_LENGTH, &code);
    napi_create_error(env, code, text, &error);
    napi_reject_deferred(env, deferred, error);
}

void Number(napi_env env, napi_value object, const char *name, double value)
{
    napi_value result{};
    napi_create_double(env, value, &result);
    napi_set_named_property(env, object, name, result);
}

void Complete(napi_env env, napi_status status, void *data)
{
    std::unique_ptr<Call> call(static_cast<Call *>(data));
    if (status != napi_ok && call->error.empty()) { call->error = "Conversion cancelled"; }
    if (!call->error.empty()) { Reject(env, call->deferred, call->error); }
    else {
        napi_value result{};
        if (call->action == Action::CREATE) { napi_create_int64(env, call->handle, &result); }
        else if (call->action == Action::RUN) {
            const auto &job = *call->job;
            napi_create_object(env, &result);
            Number(env, result, "sampleRate", job.rate);
            Number(env, result, "channels", job.channels);
            Number(env, result, "bitDepth", job.target == "m4a" ? 0 : job.targetDepth);
            Number(env, result, "bitrate", job.target == "m4a" ? job.bitrate : 0);
            Number(env, result, "durationMs", std::floor(static_cast<double>(job.samples) * 1000 / job.rate));
            Number(env, result, "sizeBytes", static_cast<double>(job.sizeBytes));
        } else { napi_get_undefined(env, &result); }
        napi_resolve_deferred(env, call->deferred, result);
    }
    napi_delete_async_work(env, call->work);
}

napi_value Queue(napi_env env, napi_callback_info info, Action action)
{
    auto call = std::make_unique<Call>();
    call->env = env; call->action = action;
    napi_value promise{};
    if (napi_create_promise(env, &call->deferred, &promise) != napi_ok) {
        napi_throw_error(env, nullptr, "Cannot create conversion Promise"); return nullptr;
    }
    try {
        if (action == Action::CREATE) {
            size_t count = 6;
            napi_value args[6]{};
            Need(napi_get_cb_info(env, info, &count, args, nullptr, nullptr) == napi_ok && count == 6,
                "conversionCreate requires source fd, size, target fd, format, bitrate and bit depth");
            call->job = std::make_shared<Conversion>();
            auto &job = *call->job;
            job.owner = env;
            call->sourceFd = static_cast<int>(Integer(env, args[0], 0, INT32_MAX, "Invalid source fd"));
            job.inputSize = Integer(env, args[1], 1, 9007199254740991LL, "Invalid source file length");
            call->targetFd = static_cast<int>(Integer(env, args[2], 0, INT32_MAX, "Invalid target fd"));
            char format[16]{};
            size_t length = 0;
            Need(napi_get_value_string_utf8(env, args[3], format, sizeof(format), &length) == napi_ok,
                "Target format must be wav, flac or m4a");
            job.target.assign(format, length);
            Need(job.target == "wav" || job.target == "flac" || job.target == "m4a", "Unsupported target audio format");
            job.bitrate = static_cast<int>(Integer(env, args[4], 0, 512000, "Invalid target AAC bitrate"));
            job.targetDepth = static_cast<int>(Integer(env, args[5], 16, 24, "Target bit depth must be 16 or 24"));
            Need(job.targetDepth == 16 || job.targetDepth == 24, "Target bit depth must be 16 or 24");
            Need(job.target != "flac" || job.targetDepth == 16, "FLAC output currently supports 16-bit PCM only");
            Need(job.target != "m4a" || job.bitrate == 128000 || job.bitrate == 256000,
                "M4A output supports AAC-LC at 128 or 256 kbps");
        } else {
            call->handle = Handle(env, info);
            if (action == Action::RELEASE) {
                auto job = Find(env, call->handle, true);
                if (job) { job->cancelled.store(true); }
            }
        }
        napi_value name{};
        Need(napi_create_string_utf8(env, "FacilisAudioConversion", NAPI_AUTO_LENGTH, &name) == napi_ok &&
            napi_create_async_work(env, nullptr, name, Execute, Complete, call.get(), &call->work) == napi_ok,
            "Could not create conversion worker");
        if (napi_queue_async_work(env, call->work) != napi_ok) {
            napi_delete_async_work(env, call->work); call->work = nullptr;
            throw std::runtime_error("Could not queue conversion worker");
        }
        call.release();
    } catch (const std::exception &error) { Reject(env, call->deferred, error.what()); }
    return promise;
}

napi_value Create(napi_env env, napi_callback_info info) { return Queue(env, info, Action::CREATE); }
napi_value Run(napi_env env, napi_callback_info info) { return Queue(env, info, Action::RUN); }
napi_value Release(napi_env env, napi_callback_info info) { return Queue(env, info, Action::RELEASE); }
napi_value Progress(napi_env env, napi_callback_info info)
{
    try {
        auto job = Find(env, Handle(env, info));
        napi_value value{}; napi_create_double(env, job->progress.load(), &value); return value;
    } catch (const std::exception &error) { napi_throw_error(env, nullptr, error.what()); return nullptr; }
}
napi_value Cancel(napi_env env, napi_callback_info info)
{
    try {
        auto job = Find(env, Handle(env, info), true);
        if (job) { job->cancelled.store(true); }
        napi_value value{}; napi_get_undefined(env, &value); return value;
    } catch (const std::exception &error) { napi_throw_error(env, nullptr, error.what()); return nullptr; }
}

void Cleanup(void *data)
{
    const auto env = static_cast<napi_env>(data);
    std::vector<std::shared_ptr<Conversion>> remaining;
    {
        std::lock_guard<std::mutex> lock(conversionsMutex);
        for (auto entry = conversions.begin(); entry != conversions.end();) {
            if (entry->second->owner == env) {
                entry->second->cancelled.store(true);
                remaining.push_back(entry->second);
                entry = conversions.erase(entry);
            } else { ++entry; }
        }
    }
    for (auto &job : remaining) { std::lock_guard<std::mutex> wait(job->runMutex); }
}
} // namespace

void RegisterAudioConversion(napi_env env, napi_value exports)
{
    const napi_property_descriptor properties[] = {
        {"conversionCreate", nullptr, Create, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"conversionRun", nullptr, Run, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"conversionProgress", nullptr, Progress, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"conversionCancel", nullptr, Cancel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"conversionRelease", nullptr, Release, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    napi_add_env_cleanup_hook(env, Cleanup, env);
}
