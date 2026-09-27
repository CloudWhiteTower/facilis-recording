import { describe, expect, it } from '@ohos/hypium';
import { RecordingConfig } from '../main/ets/models/RecordingTypes';
import { WaveFileUtils } from '../main/ets/utils/WaveFileUtils';
import { PcmStreamUtils, PcmWriteCursor } from '../main/ets/utils/PcmStreamUtils';

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

    it('includes odd 24-bit payload padding only in the RIFF size', 0, () => {
      const view = new DataView(WaveFileUtils.createPcmHeader(RecordingConfig.wav(48000, 24), 303));
      expect(view.getUint32(4, true)).assertEqual(340);
      expect(view.getUint32(40, true)).assertEqual(303);
      expect(WaveFileUtils.paddingBytes(303)).assertEqual(1);
    });

    it('rejects incomplete samples and RIFF overflow before encoding a header', 0, () => {
      for (const bytes of [1, -2, Number.POSITIVE_INFINITY, WaveFileUtils.MAX_DATA_LENGTH + 2]) {
        let rejected = false;
        try { WaveFileUtils.createPcmHeader(RecordingConfig.wav(), bytes); } catch (error) { rejected = true; }
        expect(rejected).assertTrue();
      }
      for (const depth of [16, 24]) {
        const config = RecordingConfig.wav(48000, depth);
        const maximum = WaveFileUtils.maximumDataLength(config);
        const header = new DataView(WaveFileUtils.createPcmHeader(config, maximum));
        expect(header.getUint32(40, true)).assertEqual(maximum);
        expect(header.getUint32(4, true) <= 0xFFFFFFFF).assertTrue();
        expect(maximum % (depth / 8)).assertEqual(0);
      }
    });

    it('tracks partial writes and rejects zero or invalid write progress', 0, () => {
      const cursor = new PcmWriteCursor(13);
      cursor.advance(3);
      cursor.advance(7);
      expect(cursor.offset).assertEqual(10);
      expect(cursor.remaining).assertEqual(3);
      for (const count of [0, -1, 4, Number.NaN]) {
        let rejected = false;
        try { cursor.advance(count); } catch (error) { rejected = true; }
        expect(rejected).assertTrue();
        expect(cursor.remaining).assertEqual(3);
      }
      cursor.advance(3);
      expect(cursor.remaining).assertEqual(0);
    });

    it('bounds queued PCM by bytes and packet count, and derives duration from actual samples', 0, () => {
      const config = RecordingConfig.wav();
      expect(PcmStreamUtils.durationMs(7200 * 96000, config)).assertEqual(7200000);
      let countRejected = false;
      try { PcmStreamUtils.validatePacket(config, 0, 64, 0, 2); } catch (error) { countRejected = true; }
      expect(countRejected).assertTrue();
      let bytesRejected = false;
      try {
        PcmStreamUtils.validatePacket(config, 0, 0, PcmStreamUtils.MAX_PENDING_BYTES, 2);
      } catch (error) { bytesRejected = true; }
      expect(bytesRejected).assertTrue();
      PcmStreamUtils.validatePacket(config, 0, 63, PcmStreamUtils.MAX_PENDING_BYTES - 2, 2);
    });
  });
}
