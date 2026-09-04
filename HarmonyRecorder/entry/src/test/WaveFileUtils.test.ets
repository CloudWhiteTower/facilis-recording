import { describe, expect, it } from '@ohos/hypium';
import { RecordingConfig } from '../main/ets/models/RecordingTypes';
import { WaveFileUtils } from '../main/ets/utils/WaveFileUtils';

export default function waveFileUtilsTest() {
  describe('waveFileUtilsTest', () => {
    it('writes a canonical 48 kHz 16-bit mono PCM WAV header', 0, () => {
      const header = WaveFileUtils.createPcmHeader(RecordingConfig.wav(), 96000);
      const view = new DataView(header);
      expect(header.byteLength).assertEqual(44);
      expect(view.getUint8(0)).assertEqual(0x52);
      expect(view.getUint8(1)).assertEqual(0x49);
      expect(view.getUint8(2)).assertEqual(0x46);
      expect(view.getUint8(3)).assertEqual(0x46);
      expect(view.getUint32(4, true)).assertEqual(96036);
      expect(view.getUint16(20, true)).assertEqual(1);
      expect(view.getUint16(22, true)).assertEqual(1);
      expect(view.getUint32(24, true)).assertEqual(48000);
      expect(view.getUint32(28, true)).assertEqual(96000);
      expect(view.getUint16(32, true)).assertEqual(2);
      expect(view.getUint16(34, true)).assertEqual(16);
      expect(view.getUint32(40, true)).assertEqual(96000);
    });

    it('calculates PCM duration from written data bytes', 0, () => {
      expect(WaveFileUtils.calculateDurationMs(96000, RecordingConfig.wav())).assertEqual(1000);
      expect(WaveFileUtils.calculateDurationMs(0, RecordingConfig.wav())).assertEqual(0);
    });

    it('writes selectable 44.1 kHz 24-bit PCM metadata', 0, () => {
      const header = WaveFileUtils.createPcmHeader(RecordingConfig.wav(44100, 24), 132300);
      const view = new DataView(header);
      expect(view.getUint32(24, true)).assertEqual(44100);
      expect(view.getUint32(28, true)).assertEqual(132300);
      expect(view.getUint16(32, true)).assertEqual(3);
      expect(view.getUint16(34, true)).assertEqual(24);
      expect(WaveFileUtils.calculateDurationMs(132300, RecordingConfig.wav(44100, 24))).assertEqual(1000);
    });
  });
}
