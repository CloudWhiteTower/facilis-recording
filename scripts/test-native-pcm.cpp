// Compile and execute the production PCM helper without an OS codec or audio
// device. This validates representation precision, not microphone/AAC quality.
#include "../HarmonyRecorder/entry/src/main/cpp/pcm_conversion.h"
#include <iostream>
#include <string>

using facilis::PcmFormat;
using facilis::RepackPcm;
using Bytes = std::vector<uint8_t>;

void Require(bool condition, const char *message)
{
    if (!condition) { throw std::runtime_error(message); }
}

template<class Action>
void Reject(Action action, const char *message)
{
    try { action(); } catch (const std::runtime_error &) { return; }
    throw std::runtime_error(message);
}

void AllIntegerSamples(int bits)
{
    const size_t width = bits / 8;
    const uint32_t total = uint32_t{1} << bits;
    constexpr size_t CHUNK = 32768;
    Bytes original(CHUNK * width), floats, roundTrip, wide;
    for (uint32_t first = 0; first < total; first += CHUNK) {
        const size_t samples = std::min<size_t>(CHUNK, total - first);
        original.resize(samples * width);
        for (size_t i = 0; i < samples; ++i) {
            const auto raw = first + static_cast<uint32_t>(i);
            for (size_t byte = 0; byte < width; ++byte) {
                original[i * width + byte] = (raw >> (8 * byte)) & 0xff;
            }
        }
        const auto format = bits == 24 ? PcmFormat::S24LE : PcmFormat::S16LE;
        RepackPcm(original.data(), original.size(), format, PcmFormat::F32LE, floats);
        RepackPcm(floats.data(), floats.size(), PcmFormat::F32LE, format, roundTrip);
        Require(roundTrip == original, "integer/float round trip changed a sample");
        RepackPcm(original.data(), original.size(), format, PcmFormat::S32LE, wide);
        RepackPcm(wide.data(), wide.size(), PcmFormat::S32LE, format, roundTrip);
        Require(roundTrip == original, "integer/S32 round trip changed a sample");
    }
    std::cout << "PASS all " << total << " signed " << bits
        << "-bit values round trip exactly through F32 and S32\n";
}

int32_t SignedSample(const Bytes &bytes, size_t index, size_t width)
{
    uint32_t raw = 0;
    for (size_t i = 0; i < width; ++i) { raw += uint32_t(bytes[index * width + i]) << (8 * i); }
    const int64_t value = raw >= (uint32_t{1} << (width * 8 - 1)) ?
        int64_t(raw) - (int64_t{1} << (width * 8)) : raw;
    return static_cast<int32_t>(value);
}

void RoundingAndClipping()
{
    const int32_t source[] = {INT32_MIN, INT32_MIN + 1, -257, -256, -129, -128, -127,
        -1, 0, 1, 127, 128, 129, 255, 256, 257, INT32_MAX};
    const int32_t expected[] = {-8388608, -8388608, -1, -1, -1, -1, 0,
        0, 0, 0, 0, 1, 1, 1, 1, 1, 8388607};
    Bytes converted;
    RepackPcm(reinterpret_cast<const uint8_t *>(source), sizeof(source), PcmFormat::S32LE,
        PcmFormat::S24LE, converted);
    for (size_t i = 0; i < sizeof(source) / sizeof(source[0]); ++i) {
        Require(SignedSample(converted, i, 3) == expected[i], "S32/S24 signed rounding or clipping error");
    }
    const float floats[] = {-2, -1, -1.0f / 32768, -0.5f / 32768, 0,
        0.5f / 32768, 1.0f / 32768, 1, 2};
    const int32_t expected16[] = {-32768, -32768, -1, -1, 0, 1, 1, 32767, 32767};
    RepackPcm(reinterpret_cast<const uint8_t *>(floats), sizeof(floats), PcmFormat::F32LE,
        PcmFormat::S16LE, converted);
    for (size_t i = 0; i < sizeof(floats) / sizeof(floats[0]); ++i) {
        Require(SignedSample(converted, i, 2) == expected16[i], "float/S16 signed rounding or clipping error");
    }
    std::cout << "PASS full-scale clipping and signed half-step rounding\n";
}

void InvalidInput()
{
    Bytes output;
    const uint8_t sample[4] = {};
    Reject([&] { RepackPcm(sample, 2, PcmFormat::S24LE, PcmFormat::F32LE, output); }, "partial sample accepted");
    Reject([&] { RepackPcm(sample, 4, static_cast<PcmFormat>(99), PcmFormat::S16LE, output); }, "invalid format accepted");
    for (float value : {std::numeric_limits<float>::quiet_NaN(),
        std::numeric_limits<float>::infinity(), -std::numeric_limits<float>::infinity()}) {
        Reject([&] { RepackPcm(reinterpret_cast<uint8_t *>(&value), sizeof(value), PcmFormat::F32LE,
            PcmFormat::S24LE, output); }, "non-finite sample accepted");
    }
    Reject([&] { RepackPcm(nullptr, std::numeric_limits<size_t>::max() - 1,
        PcmFormat::S16LE, PcmFormat::F32LE, output); }, "output length overflow accepted");
    RepackPcm(nullptr, 0, PcmFormat::S24LE, PcmFormat::F32LE, output);
    Require(output.empty(), "empty input produced samples");
    std::cout << "PASS partial samples, non-finite values, invalid formats, overflow and empty input\n";
}

void ChunkBoundaries()
{
    Bytes input, output, restored;
    for (size_t samples : {1, 15, 16, 17, 1023, 1024, 1025, 32767, 32768, 32769}) {
        input.resize(samples * 3);
        uint32_t seed = 0x1248;
        for (auto &byte : input) {
            seed = seed * 1664525U + 1013904223U;
            byte = seed >> 24;
        }
        RepackPcm(input.data(), input.size(), PcmFormat::S24LE, PcmFormat::F32LE, output);
        Require(output.size() == samples * 4, "chunk changed sample count");
        RepackPcm(output.data(), output.size(), PcmFormat::F32LE, PcmFormat::S24LE, restored);
        Require(input == restored, "chunk tail lost a sample");
    }
    const size_t capacity = output.capacity();
    RepackPcm(input.data(), 3, PcmFormat::S24LE, PcmFormat::F32LE, output);
    Require(output.capacity() == capacity && output.size() == 4, "scratch buffer was not reused");
    std::cout << "PASS frame/chunk tails and scratch-buffer reuse\n";
}

int main()
{
    try {
        AllIntegerSamples(16);
        AllIntegerSamples(24);
        RoundingAndClipping();
        InvalidInput();
        ChunkBoundaries();
        std::cout << "Native PCM host checks: 5 passed; device codecs and acoustic quality remain separate.\n";
        return 0;
    } catch (const std::exception &error) {
        std::cerr << "FAIL " << error.what() << '\n';
        return 1;
    }
}
