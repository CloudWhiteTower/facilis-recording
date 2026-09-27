import { describe, expect, it } from '@ohos/hypium';
import { RecordingConfig, RecordingFormat } from '../main/ets/models/RecordingTypes';
import { RecordingRepository } from '../main/ets/repository/RecordingRepository';
import { WaveFileUtils } from '../main/ets/utils/WaveFileUtils';

function flacStreamInfo(sampleRate: number, bitDepth: number, totalSamples: number): ArrayBuffer {
  const buffer = new ArrayBuffer(42);
  const data = new DataView(buffer);
  data.setUint32(0, 0x664C6143, false);
  data.setUint32(4, 0x80000022, false);
  data.setUint8(18, Math.floor(sampleRate / 4096));
  data.setUint8(19, Math.floor(sampleRate / 16) & 255);
  data.setUint8(20, ((sampleRate & 15) << 4) | ((bitDepth - 1) >> 4));
  data.setUint8(21, (((bitDepth - 1) & 15) << 4) | Math.floor(totalSamples / 4294967296));
  data.setUint32(22, totalSamples % 4294967296, false);
  return buffer;
}

export default function recordingMetadataTest() {
  describe('recordingMetadataTest', () => {
    it('recovers WAV duration and quality from the actual 44.1 kHz 24-bit header', 0, () => {
      const header = WaveFileUtils.createPcmHeader(RecordingConfig.wav(44100, 24), 132300);
      const metadata = RecordingRepository.parseAudioMetadata(header, 'wav', 132344);
      expect(metadata !== undefined).assertTrue();
      if (metadata !== undefined) {
        expect(metadata.config.sampleRate).assertEqual(44100);
        expect(metadata.config.bitDepth).assertEqual(24);
        expect(metadata.durationMs).assertEqual(1000);
      }
    });

    it('uses FLAC STREAMINFO sample count rather than compressed byte size', 0, () => {
      const header = flacStreamInfo(48000, 24, 96000);
      const metadata = RecordingRepository.parseAudioMetadata(header, 'flac', 10000);
      expect(metadata !== undefined).assertTrue();
      if (metadata !== undefined) {
        expect(metadata.config.format).assertEqual(RecordingFormat.FLAC);
        expect(metadata.config.sampleRate).assertEqual(48000);
        expect(metadata.config.bitDepth).assertEqual(24);
        expect(metadata.config.channels).assertEqual(1);
        expect(metadata.durationMs).assertEqual(2000);
      }
    });

    it('preserves all 36 FLAC sample-count bits', 0, () => {
      const samples = 4294967296 + 48000;
      const metadata = RecordingRepository.parseAudioMetadata(flacStreamInfo(48000, 16, samples), 'flac', 42);
      expect(metadata !== undefined).assertTrue();
      if (metadata !== undefined) {
        expect(metadata.durationMs).assertEqual(Math.floor(samples * 1000 / 48000));
      }
    });

    it('rejects a WAV renamed to flac and truncated FLAC metadata', 0, () => {
      const wav = WaveFileUtils.createPcmHeader(RecordingConfig.wav(), 96000);
      expect(RecordingRepository.parseAudioMetadata(wav, 'flac', 96044) === undefined).assertTrue();
      expect(RecordingRepository.parseAudioMetadata(flacStreamInfo(48000, 16, 48000).slice(0, 30),
        'flac', 30) === undefined).assertTrue();
    });

    it('rejects index-breaking newline characters in names', 0, () => {
      let rejected = false;
      try {
        RecordingRepository.normalizeDisplayName('first\nsecond.wav', 'wav');
      } catch (error) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });
  });
}
