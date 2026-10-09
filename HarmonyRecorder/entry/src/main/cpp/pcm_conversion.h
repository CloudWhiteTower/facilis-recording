#ifndef FACILIS_PCM_CONVERSION_H
#define FACILIS_PCM_CONVERSION_H

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <stdexcept>
#include <vector>

namespace facilis {
enum class PcmFormat { S16LE, S24LE, S32LE, F32LE };

inline uint32_t ReadLe(const uint8_t *data, size_t size)
{
    uint32_t value = 0;
    for (size_t i = 0; i < size; ++i) { value |= static_cast<uint32_t>(data[i]) << (8 * i); }
    return value;
}

inline void WriteLe(uint8_t *data, uint32_t value, size_t size)
{
    for (size_t i = 0; i < size; ++i) { data[i] = static_cast<uint8_t>(value >> (8 * i)); }
}

inline size_t PcmWidth(PcmFormat format)
{
    switch (format) {
        case PcmFormat::S16LE: return 2;
        case PcmFormat::S24LE: return 3;
        case PcmFormat::S32LE:
        case PcmFormat::F32LE: return 4;
    }
    throw std::runtime_error("Unsupported decoded PCM representation");
}

// Change the representation only: preserve sample order, rate and channels.
// A binary32 float exactly represents normalized signed 16/24-bit PCM samples.
inline void RepackPcm(const uint8_t *input, size_t bytes, PcmFormat source, PcmFormat target,
    std::vector<uint8_t> &output)
{
    const size_t inputWidth = PcmWidth(source);
    const size_t outputWidth = PcmWidth(target);
    if (bytes % inputWidth != 0) { throw std::runtime_error("Decoded audio ends in a partial PCM sample"); }
    const size_t samples = bytes / inputWidth;
    if (samples > std::numeric_limits<size_t>::max() / outputWidth) {
        throw std::runtime_error("Decoded PCM buffer is too large");
    }
    output.resize(samples * outputWidth);
    for (size_t i = 0; i < samples; ++i) {
        double value;
        if (source == PcmFormat::F32LE) {
            float sample;
            std::memcpy(&sample, input + i * inputWidth, sizeof(sample));
            if (!std::isfinite(sample)) { throw std::runtime_error("Decoder produced a non-finite audio sample"); }
            value = sample;
        } else {
            const uint32_t raw = ReadLe(input + i * inputWidth, inputWidth);
            const int bits = static_cast<int>(inputWidth * 8);
            const int64_t signedValue = (raw & (uint32_t{1} << (bits - 1))) ?
                static_cast<int64_t>(raw) - (int64_t{1} << bits) : raw;
            value = static_cast<double>(signedValue) / static_cast<double>(int64_t{1} << (bits - 1));
        }
        if (target == PcmFormat::F32LE) {
            const float sample = static_cast<float>(value);
            std::memcpy(output.data() + i * outputWidth, &sample, sizeof(sample));
        } else {
            const int bits = static_cast<int>(outputWidth * 8);
            const int64_t scale = int64_t{1} << (bits - 1);
            const double clamped = std::max(-1.0, std::min(1.0, value));
            const int64_t sample = std::max(-scale, std::min(scale - 1, static_cast<int64_t>(std::llround(clamped * scale))));
            WriteLe(output.data() + i * outputWidth, static_cast<uint32_t>(sample), outputWidth);
        }
    }
}
} // namespace facilis
#endif
