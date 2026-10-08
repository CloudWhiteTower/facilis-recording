#ifndef FACILIS_AUDIO_CONVERSION_H
#define FACILIS_AUDIO_CONVERSION_H

#include <napi/native_api.h>
#include <cstdint>
#include <cstddef>
#include <functional>
#include <memory>
#include <vector>

// The recorder and converter use the same tested FLAC framing and STREAMINFO path.
class NativePcmWriter {
public:
    virtual ~NativePcmWriter() = default;
    virtual void Write(const uint8_t *pcm, size_t size) = 0;
    void Write(const std::vector<uint8_t> &pcm) { Write(pcm.data(), pcm.size()); }
    virtual void Finish() = 0;
};

std::unique_ptr<NativePcmWriter> CreateFlacPcm16Writer(int32_t fd, int32_t sampleRate,
    std::function<void()> checkCancelled = {});
void RegisterAudioConversion(napi_env env, napi_value exports);

#endif
