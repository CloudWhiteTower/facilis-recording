import { describe, expect, it } from '@ohos/hypium';
import { RecordingConfig } from '../main/ets/models/RecordingTypes';

export default function recordingConfigTest() {
  describe('recordingConfigTest', () => {
    it('creates the default WAV demo configuration', 0, () => {
      const config = RecordingConfig.wav();
      expect(config.extension).assertEqual('wav');
      expect(config.formatLabel).assertEqual('WAV');
      expect(config.qualityLabel).assertEqual('48 kHz / 16 bit / Mono');
      expect(config.compactLabel).assertEqual('WAV · 16 bit');
    });

    it('maps selectable WAV sample rates and bit depths', 0, () => {
      const config = RecordingConfig.wav(44100, 24);
      expect(config.sampleRateLabel).assertEqual('44.1 kHz');
      expect(config.encodingDetailLabel).assertEqual('24 bit');
      expect(config.qualityLabel).assertEqual('44.1 kHz / 24 bit / Mono');
    });

    it('maps AAC bitrates to the expected quality labels', 0, () => {
      expect(RecordingConfig.aac(128000).extension).assertEqual('m4a');
      expect(RecordingConfig.aac(128000).formatLabel).assertEqual('M4A');
      expect(RecordingConfig.aac(128000).qualityLabel).assertEqual('Standard · 128 kbps · 48 kHz · Mono');
      expect(RecordingConfig.aac(256000, 44100).qualityLabel).assertEqual('High · 256 kbps · 44.1 kHz · Mono');
      expect(RecordingConfig.aac(256000).compactLabel).assertEqual('M4A · 256 kbps');
    });

    it('selects FLAC as a separate lossless 16-bit format', 0, () => {
      const config = RecordingConfig.flac(44100);
      expect(config.extension).assertEqual('flac');
      expect(config.formatLabel).assertEqual('FLAC');
      expect(config.bitDepth).assertEqual(16);
      expect(config.bitrate).assertEqual(0);
      expect(config.qualityLabel).assertEqual('44.1 kHz / 16 bit / Mono');
      expect(config.compactLabel).assertEqual('FLAC · 16 bit');
    });
  });
}
