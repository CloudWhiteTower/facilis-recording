#include <napi/native_api.h>
#include <multimedia/native_audio_channel_layout.h>
#include <multimedia/player_framework/native_avbuffer.h>
#include <multimedia/player_framework/native_avcodec_audiocodec.h>
#include <multimedia/player_framework/native_avcodec_base.h>
#include <multimedia/player_framework/native_avformat.h>
#include <multimedia/player_framework/native_avmuxer.h>
#include "audio_conversion.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fcntl.h>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <unistd.h>
#include <vector>

namespace {
constexpr size_t SAMPLES_PER_FRAME = 4608; // Official FLAC frame size for both 44100 and 48000 Hz.
constexpr size_t BYTES_PER_SAMPLE = 2;
constexpr size_t FRAME_BYTES = SAMPLES_PER_FRAME * BYTES_PER_SAMPLE;
constexpr size_t STREAMINFO_BYTES = 34;
constexpr uint64_t MAX_FLAC_SAMPLES = (uint64_t{1} << 36) - 1;
constexpr size_t MAX_WRITE_BYTES = 8 * 1024 * 1024;
constexpr int64_t QUERY_TIMEOUT_US = 20000;
constexpr auto CODEC_TIMEOUT = std::chrono::seconds(5);
using Clock = std::chrono::steady_clock;
using FormatPtr = std::unique_ptr<OH_AVFormat, decltype(&OH_AVFormat_Destroy)>;
using BufferPtr = std::unique_ptr<OH_AVBuffer, decltype(&OH_AVBuffer_Destroy)>;

void Check(OH_AVErrCode result, const char *operation)
{
    if (result != AV_ERR_OK) {
        throw std::runtime_error(std::string(operation) + " failed (AVCodec " + std::to_string(result) + ")");
    }
}

void Require(bool condition, const char *message)
{
    if (!condition) {
        throw std::runtime_error(message);
    }
}

class FlacSession : public NativePcmWriter {
public:
    std::mutex mutex;

    explicit FlacSession(int32_t sampleRate) : sampleRate_(sampleRate) {}
    ~FlacSession() { Close(); }

    void Open(int32_t fd)
    {
        const int flags = fcntl(fd, F_GETFL);
        Require(flags >= 0 && (flags & O_ACCMODE) == O_RDWR,
            "FLAC output fd must remain open with READ_WRITE permission");
        Require(lseek(fd, 0, SEEK_CUR) >= 0, "FLAC output fd must be seekable");
        codec_ = OH_AudioCodec_CreateByMime(OH_AVCODEC_MIMETYPE_AUDIO_FLAC, true);
        Require(codec_ != nullptr, "This device does not provide a FLAC encoder");
        muxer_ = OH_AVMuxer_Create(fd, AV_OUTPUT_FORMAT_FLAC);
        Require(muxer_ != nullptr, "This device cannot create a FLAC muxer");
        FormatPtr format(OH_AVFormat_Create(), OH_AVFormat_Destroy);
        Require(format != nullptr, "Could not allocate FLAC encoder format");
        Require(OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_AUD_SAMPLE_RATE, sampleRate_) &&
            OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_AUD_CHANNEL_COUNT, 1) &&
            OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_AUDIO_SAMPLE_FORMAT, SAMPLE_S16LE) &&
            OH_AVFormat_SetLongValue(format.get(), OH_MD_KEY_CHANNEL_LAYOUT, CH_LAYOUT_MONO) &&
            OH_AVFormat_SetLongValue(format.get(), OH_MD_KEY_BITRATE,
                static_cast<int64_t>(sampleRate_) * 16) &&
            OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_COMPLIANCE_LEVEL, 0) &&
            OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_ENABLE_SYNC_MODE, 1),
            "Could not set FLAC encoder format");
        Check(OH_AudioCodec_Configure(codec_, format.get()), "Configure FLAC encoder");
        Check(OH_AudioCodec_Prepare(codec_), "Prepare FLAC encoder");
        Check(OH_AudioCodec_Start(codec_), "Start FLAC encoder");
        codecStarted_ = true;
        pending_.reserve(FRAME_BYTES);
    }

    void Write(const std::vector<uint8_t> &pcm)
    {
        EnsureWritable();
        size_t offset = 0;
        // Keep at most one partial frame between calls. Never pad or discard source samples.
        if (!pending_.empty()) {
            const size_t count = std::min(FRAME_BYTES - pending_.size(), pcm.size());
            pending_.insert(pending_.end(), pcm.begin(), pcm.begin() + count);
            offset = count;
            if (pending_.size() == FRAME_BYTES) {
                Push(pending_.data(), pending_.size(), false);
                pending_.clear();
            }
        }
        while (pcm.size() - offset >= FRAME_BYTES) {
            Push(pcm.data() + offset, FRAME_BYTES, false);
            offset += FRAME_BYTES;
        }
        pending_.insert(pending_.end(), pcm.begin() + offset, pcm.end());
        Drain(false);
    }

    void Finish()
    {
        if (finished_) {
            return;
        }
        EnsureWritable();
        const uint64_t totalSamples = samplesSubmitted_ + pending_.size() / BYTES_PER_SAMPLE;
        Require(totalSamples > 0, "Cannot finish a FLAC recording without PCM samples");
        Require(totalSamples <= MAX_FLAC_SAMPLES, "FLAC recording exceeds the 36-bit sample-count limit");
        if (!pending_.empty()) {
            Push(pending_.data(), pending_.size(), false);
            pending_.clear();
        }
        Push(nullptr, 0, true);
        Drain(true);
        EnsureMuxerStarted();
        WriteFinalStreamInfo();
        Check(OH_AVMuxer_Stop(muxer_), "Finalize FLAC file");
        muxerStarted_ = false;
        Check(OH_AudioCodec_Stop(codec_), "Stop FLAC encoder");
        codecStarted_ = false;
        finished_ = true;
    }

    void MarkFailed(const std::string &message) { failure_ = message; }

    void Close() noexcept
    {
        // release is also the abort path. ArkTS owns and closes fd only after this completes.
        if (codec_ != nullptr) {
            if (codecStarted_) {
                OH_AudioCodec_Stop(codec_);
            }
            OH_AudioCodec_Destroy(codec_);
            codec_ = nullptr;
            codecStarted_ = false;
        }
        if (muxer_ != nullptr) {
            if (muxerStarted_) {
                OH_AVMuxer_Stop(muxer_);
            }
            OH_AVMuxer_Destroy(muxer_);
            muxer_ = nullptr;
            muxerStarted_ = false;
        }
        pending_.clear();
    }

private:
    OH_AVCodec *codec_ = nullptr;
    OH_AVMuxer *muxer_ = nullptr;
    int32_t sampleRate_;
    int32_t track_ = -1;
    bool codecStarted_ = false;
    bool muxerStarted_ = false;
    bool finished_ = false;
    bool outputEos_ = false;
    uint64_t samplesSubmitted_ = 0;
    uint16_t maximumBlockSamples_ = 0;
    uint32_t minimumFrameBytes_ = 0;
    uint32_t maximumFrameBytes_ = 0;
    std::vector<uint8_t> pending_;
    std::string failure_;

    void EnsureWritable()
    {
        Require(failure_.empty(), failure_.c_str());
        Require(codec_ != nullptr && codecStarted_ && !finished_, "FLAC session is already finished or released");
    }

    void EnsureMuxerStarted()
    {
        if (muxerStarted_) {
            return;
        }
        FormatPtr format(OH_AudioCodec_GetOutputDescription(codec_), OH_AVFormat_Destroy);
        Require(format != nullptr, "FLAC output format is unavailable");
        // Keep encoder codec_config, and explicitly provide every required FLAC muxer field.
        Require(OH_AVFormat_SetStringValue(format.get(), OH_MD_KEY_CODEC_MIME, OH_AVCODEC_MIMETYPE_AUDIO_FLAC) &&
            OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_AUD_SAMPLE_RATE, sampleRate_) &&
            OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_AUD_CHANNEL_COUNT, 1) &&
            OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_AUDIO_SAMPLE_FORMAT, SAMPLE_S16LE) &&
            OH_AVFormat_SetLongValue(format.get(), OH_MD_KEY_CHANNEL_LAYOUT, CH_LAYOUT_MONO),
            "Could not set FLAC track format");
        Check(OH_AVMuxer_AddTrack(muxer_, &track_, format.get()), "Add FLAC audio track");
        Require(track_ >= 0, "FLAC muxer returned an invalid track");
        Check(OH_AVMuxer_Start(muxer_), "Start FLAC muxer");
        muxerStarted_ = true;
    }

    static void StoreBigEndian(uint8_t *destination, uint64_t value, size_t bytes)
    {
        for (size_t index = 0; index < bytes; ++index) {
            destination[bytes - 1 - index] = static_cast<uint8_t>(value & 0xff);
            value >>= 8;
        }
    }

    void WriteFinalStreamInfo()
    {
        Require(minimumFrameBytes_ > 0 && maximumFrameBytes_ <= 0xffffff,
            "FLAC encoder did not produce valid audio frames");
        BufferPtr buffer(OH_AVBuffer_Create(STREAMINFO_BYTES), OH_AVBuffer_Destroy);
        Require(buffer != nullptr, "Could not allocate final FLAC codec data");
        uint8_t *info = OH_AVBuffer_GetAddr(buffer.get());
        Require(info != nullptr, "FLAC codec-data buffer has no address");
        std::memset(info, 0, STREAMINFO_BYTES);

        // RFC 9639 section 8.2: block-size bounds are at least 16, even for a
        // one-sample last block. All non-final input blocks here contain 4608
        // samples. A stream consisting only of a short last block uses its
        // actual size as the bound, clamped to the format's legal minimum.
        const uint16_t blockBound = std::max<uint16_t>(16, maximumBlockSamples_);
        StoreBigEndian(info, blockBound, 2);
        StoreBigEndian(info + 2, blockBound, 2);
        StoreBigEndian(info + 4, minimumFrameBytes_, 3);
        StoreBigEndian(info + 7, maximumFrameBytes_, 3);
        const uint64_t audioFields = (static_cast<uint64_t>(sampleRate_) << 44) |
            (uint64_t{15} << 36) | samplesSubmitted_; // Mono, 16 bits, exact sample count.
        StoreBigEndian(info + 10, audioFields, 8);
        // The final 16 MD5 bytes stay zero: RFC 9639 explicitly defines this
        // as unknown. Do not claim an input checksum that was not computed.

        OH_AVCodecBufferAttr attr{};
        attr.pts = static_cast<int64_t>(samplesSubmitted_ * 1000000 / sampleRate_);
        attr.size = STREAMINFO_BYTES;
        attr.flags = AVCODEC_BUFFER_FLAGS_CODEC_DATA;
        Check(OH_AVBuffer_SetBufferAttr(buffer.get(), &attr), "Set final FLAC codec data");
        // The platform's fallback statistics skip encoded packets <16 bytes,
        // which includes tiny tails and constant/silent frames. Supplying the
        // final STREAMINFO through the official codec-data path makes muxer
        // Stop retain accurate counts without changing encoded audio or the fd.
        Check(OH_AVMuxer_WriteSampleBuffer(muxer_, static_cast<uint32_t>(track_), buffer.get()),
            "Write final FLAC stream information");
    }

    void Push(const uint8_t *data, size_t size, bool eos)
    {
        const auto deadline = Clock::now() + CODEC_TIMEOUT;
        uint32_t index = 0;
        for (;;) {
            const auto result = OH_AudioCodec_QueryInputBuffer(codec_, &index, QUERY_TIMEOUT_US);
            if (result == AV_ERR_OK) {
                break;
            }
            Check(result == AV_ERR_TRY_AGAIN_LATER ? AV_ERR_OK : result, "Query FLAC input buffer");
            Drain(false); // Free output buffers before retrying a full input queue.
            Require(Clock::now() < deadline, "FLAC encoder input timed out");
        }
        OH_AVBuffer *buffer = OH_AudioCodec_GetInputBuffer(codec_, index);
        Require(buffer != nullptr, "FLAC encoder input buffer is unavailable");
        Require(OH_AVBuffer_GetCapacity(buffer) >= static_cast<int32_t>(size), "FLAC input buffer is too small");
        if (size > 0) {
            uint8_t *address = OH_AVBuffer_GetAddr(buffer);
            Require(address != nullptr, "FLAC input buffer has no data address");
            std::memcpy(address, data, size);
        }
        OH_AVCodecBufferAttr attr{};
        attr.pts = static_cast<int64_t>(samplesSubmitted_ * 1000000 / sampleRate_);
        attr.size = static_cast<int32_t>(size);
        attr.flags = eos ? AVCODEC_BUFFER_FLAGS_EOS : AVCODEC_BUFFER_FLAGS_NONE;
        Check(OH_AVBuffer_SetBufferAttr(buffer, &attr), "Set FLAC input attributes");
        Check(OH_AudioCodec_PushInputBuffer(codec_, index), "Push FLAC PCM");
        samplesSubmitted_ += size / BYTES_PER_SAMPLE;
        maximumBlockSamples_ = std::max(maximumBlockSamples_, static_cast<uint16_t>(size / BYTES_PER_SAMPLE));
        Drain(false);
    }

    void Drain(bool untilEos)
    {
        auto deadline = Clock::now() + CODEC_TIMEOUT;
        while (!outputEos_) {
            Require(Clock::now() < deadline, "FLAC encoder output timed out");
            uint32_t index = 0;
            const auto result = OH_AudioCodec_QueryOutputBuffer(codec_, &index, untilEos ? QUERY_TIMEOUT_US : 0);
            if (result == AV_ERR_TRY_AGAIN_LATER) {
                if (!untilEos) {
                    return;
                }
                Require(Clock::now() < deadline, "FLAC encoder output timed out while finishing");
                continue;
            }
            if (result == AV_ERR_STREAM_CHANGED) {
                // This is a format notification, not an output-buffer index to release.
                FormatPtr changed(OH_AudioCodec_GetOutputDescription(codec_), OH_AVFormat_Destroy);
                Require(changed != nullptr, "Changed FLAC output format is unavailable");
                Require(Clock::now() < deadline, "FLAC encoder repeatedly changed output format");
                continue;
            }
            Check(result, "Query FLAC output buffer");
            bool receivedData = false;
            try {
                OH_AVBuffer *buffer = OH_AudioCodec_GetOutputBuffer(codec_, index);
                Require(buffer != nullptr, "FLAC encoder output buffer is unavailable");
                OH_AVCodecBufferAttr attr{};
                Check(OH_AVBuffer_GetBufferAttr(buffer, &attr), "Get FLAC output attributes");
                const bool eos = (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0;
                Require(eos || attr.size >= 0, "FLAC encoder produced a negative output size");
                // AudioCodec emits the final PCM frame before a separate EOS marker.
                // Its recycled EOS buffer can retain the previous frame's size/data:
                // writing that payload duplicates tiny recordings (e.g. 137 samples).
                // Follow the official synchronous encoding flow: EOS is never muxed.
                if (!eos && attr.size > 0) {
                    Require(attr.offset >= 0 && static_cast<int64_t>(attr.offset) + attr.size <=
                        OH_AVBuffer_GetCapacity(buffer), "FLAC encoder produced an invalid output buffer");
                    EnsureMuxerStarted();
                    // The FLAC muxer consumes CODEC_DATA to update STREAMINFO (including MD5).
                    // Preserve every non-EOS codec-data buffer as well as audio frames.
                    Check(OH_AVMuxer_WriteSampleBuffer(muxer_, static_cast<uint32_t>(track_), buffer),
                        "Write FLAC encoded sample");
                    receivedData = true;
                    if (!(attr.flags == AVCODEC_BUFFER_FLAGS_CODEC_DATA && attr.size == STREAMINFO_BYTES)) {
                        const auto frameBytes = static_cast<uint32_t>(attr.size);
                        minimumFrameBytes_ = minimumFrameBytes_ == 0 ? frameBytes :
                            std::min(minimumFrameBytes_, frameBytes);
                        maximumFrameBytes_ = std::max(maximumFrameBytes_, frameBytes);
                    }
                }
                outputEos_ = eos;
            } catch (...) {
                OH_AudioCodec_FreeOutputBuffer(codec_, index);
                throw;
            }
            Check(OH_AudioCodec_FreeOutputBuffer(codec_, index), "Release FLAC output buffer");
            if (receivedData) { deadline = Clock::now() + CODEC_TIMEOUT; }
        }
    }
};

struct SessionEntry {
    napi_env owner;
    std::shared_ptr<FlacSession> session;
};
std::mutex sessionsMutex;
std::unordered_map<int64_t, SessionEntry> sessions;
std::atomic<int64_t> nextHandle{1};

enum class Operation { CREATE, WRITE, FINISH, RELEASE };
struct AsyncCall {
    napi_env env = nullptr;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    Operation operation;
    int64_t handle = 0;
    int32_t fd = -1;
    int32_t sampleRate = 0;
    std::vector<uint8_t> pcm;
    std::string error;
};

void Execute(napi_env, void *data)
{
    auto &call = *static_cast<AsyncCall *>(data);
    try {
        if (call.operation == Operation::CREATE) {
            auto session = std::make_shared<FlacSession>(call.sampleRate);
            session->Open(call.fd);
            call.handle = nextHandle.fetch_add(1);
            std::lock_guard<std::mutex> lock(sessionsMutex);
            sessions.emplace(call.handle, SessionEntry{call.env, std::move(session)});
            return;
        }
        std::shared_ptr<FlacSession> session;
        {
            std::lock_guard<std::mutex> lock(sessionsMutex);
            auto found = sessions.find(call.handle);
            if (found == sessions.end() || found->second.owner != call.env) {
                Require(call.operation == Operation::RELEASE, "FLAC session handle is invalid");
                return; // release is idempotent.
            }
            session = found->second.session;
            if (call.operation == Operation::RELEASE) {
                sessions.erase(found);
            }
        }
        std::lock_guard<std::mutex> lock(session->mutex);
        try {
            if (call.operation == Operation::WRITE) {
                session->Write(call.pcm);
            } else if (call.operation == Operation::FINISH) {
                session->Finish();
            } else {
                session->Close();
            }
        } catch (const std::exception &error) {
            session->MarkFailed(error.what());
            throw;
        }
    } catch (const std::exception &error) {
        call.error = error.what();
    } catch (...) {
        call.error = "Unknown native FLAC failure";
    }
}

void Reject(napi_env env, napi_deferred deferred, const std::string &message)
{
    napi_value text = nullptr;
    napi_value error = nullptr;
    napi_create_string_utf8(env, message.c_str(), message.size(), &text);
    napi_create_error(env, nullptr, text, &error);
    napi_reject_deferred(env, deferred, error);
}

void Complete(napi_env env, napi_status status, void *data)
{
    std::unique_ptr<AsyncCall> call(static_cast<AsyncCall *>(data));
    if (status != napi_ok && call->error.empty()) {
        call->error = "Native FLAC task was cancelled";
    }
    if (!call->error.empty()) {
        Reject(env, call->deferred, call->error);
    } else {
        napi_value result = nullptr;
        if (call->operation == Operation::CREATE) {
            napi_create_int64(env, call->handle, &result);
        } else {
            napi_get_undefined(env, &result);
        }
        napi_resolve_deferred(env, call->deferred, result);
    }
    napi_delete_async_work(env, call->work);
}

int64_t Integer(napi_env env, napi_value value, int64_t min, int64_t max, const char *message)
{
    double result = 0;
    Require(napi_get_value_double(env, value, &result) == napi_ok && std::isfinite(result) &&
        result == std::floor(result) && result >= min && result <= max, message);
    return static_cast<int64_t>(result);
}

napi_value Queue(napi_env env, napi_callback_info info, Operation operation)
{
    auto call = std::make_unique<AsyncCall>();
    call->env = env;
    call->operation = operation;
    napi_value promise = nullptr;
    if (napi_create_promise(env, &call->deferred, &promise) != napi_ok) {
        napi_throw_error(env, nullptr, "Could not create native FLAC Promise");
        return nullptr;
    }
    try {
        size_t argc = 3;
        napi_value args[3]{};
        Require(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) == napi_ok,
            "Could not read FLAC arguments");
        if (operation == Operation::CREATE) {
            Require(argc == 3, "FLAC create requires fd, sampleRate and channels");
            call->fd = static_cast<int32_t>(Integer(env, args[0], 0, INT32_MAX, "Invalid FLAC output fd"));
            call->sampleRate = static_cast<int32_t>(Integer(env, args[1], 44100, 48000, "Invalid FLAC sample rate"));
            Require(call->sampleRate == 44100 || call->sampleRate == 48000, "FLAC supports 44100 or 48000 Hz");
            Integer(env, args[2], 1, 1, "FLAC currently supports mono PCM only");
        } else {
            Require(argc >= (operation == Operation::WRITE ? 2 : 1), "FLAC operation requires a session handle");
            call->handle = Integer(env, args[0], 1, 9007199254740991LL, "Invalid FLAC session handle");
            if (operation == Operation::WRITE) {
                void *address = nullptr;
                size_t size = 0;
                Require(napi_get_arraybuffer_info(env, args[1], &address, &size) == napi_ok,
                    "FLAC write requires an ArrayBuffer");
                Require(size <= MAX_WRITE_BYTES && size % BYTES_PER_SAMPLE == 0,
                    "FLAC PCM must contain complete 16-bit samples and be at most 8 MiB per write");
                if (size > 0) {
                    Require(address != nullptr, "FLAC PCM ArrayBuffer is detached");
                    // Copy while on the ArkTS thread: the asynchronous worker never reads movable JS storage.
                    const auto *bytes = static_cast<const uint8_t *>(address);
                    call->pcm.assign(bytes, bytes + size);
                }
            }
        }
        napi_value resource = nullptr;
        Require(napi_create_string_utf8(env, "FacilisFlac", NAPI_AUTO_LENGTH, &resource) == napi_ok &&
            napi_create_async_work(env, nullptr, resource, Execute, Complete, call.get(), &call->work) == napi_ok,
            "Could not create native FLAC task");
        if (napi_queue_async_work(env, call->work) != napi_ok) {
            napi_delete_async_work(env, call->work);
            call->work = nullptr;
            throw std::runtime_error("Could not queue native FLAC task");
        }
        call.release();
    } catch (const std::exception &error) {
        Reject(env, call->deferred, error.what());
    }
    return promise;
}

napi_value Create(napi_env env, napi_callback_info info) { return Queue(env, info, Operation::CREATE); }
napi_value Write(napi_env env, napi_callback_info info) { return Queue(env, info, Operation::WRITE); }
napi_value Finish(napi_env env, napi_callback_info info) { return Queue(env, info, Operation::FINISH); }
napi_value Release(napi_env env, napi_callback_info info) { return Queue(env, info, Operation::RELEASE); }

void Cleanup(void *data)
{
    auto env = static_cast<napi_env>(data);
    std::vector<std::shared_ptr<FlacSession>> abandoned;
    {
        std::lock_guard<std::mutex> lock(sessionsMutex);
        for (auto entry = sessions.begin(); entry != sessions.end();) {
            if (entry->second.owner == env) {
                abandoned.push_back(entry->second.session);
                entry = sessions.erase(entry);
            } else {
                ++entry;
            }
        }
    }
    for (auto &session : abandoned) {
        std::lock_guard<std::mutex> lock(session->mutex);
        session->Close();
    }
}

napi_value Init(napi_env env, napi_value exports)
{
    const napi_property_descriptor properties[] = {
        {"create", nullptr, Create, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"write", nullptr, Write, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"finish", nullptr, Finish, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"release", nullptr, Release, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    napi_add_env_cleanup_hook(env, Cleanup, env);
    RegisterAudioConversion(env, exports);
    return exports;
}

napi_module module = {1, 0, nullptr, Init, "facilis_flac", nullptr, {0}};
} // namespace

std::unique_ptr<NativePcmWriter> CreateFlacPcm16Writer(int32_t fd, int32_t sampleRate)
{
    auto session = std::make_unique<FlacSession>(sampleRate);
    session->Open(fd);
    return session;
}

extern "C" __attribute__((constructor)) void RegisterFacilisFlac()
{
    napi_module_register(&module);
}
