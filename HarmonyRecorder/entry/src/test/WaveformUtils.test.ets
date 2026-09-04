import { describe, expect, it } from '@ohos/hypium';
import { WaveformUtils } from '../main/ets/utils/WaveformUtils';

export default function waveformUtilsTest() {
  describe('waveformUtilsTest', () => {
    it('extracts a normalized peak from signed 16-bit PCM', 0, () => {
      const buffer = new ArrayBuffer(8);
      const view = new DataView(buffer);
      view.setInt16(0, 0, true);
      view.setInt16(2, -8192, true);
      view.setInt16(4, 16384, true);
      view.setInt16(6, -32768, true);
      expect(WaveformUtils.calculatePeakFromPcm16(buffer)).assertEqual(1);
    });

    it('uses RMS for the rolling WAV envelope instead of a transient peak', 0, () => {
      const buffer = new ArrayBuffer(8);
      const view = new DataView(buffer);
      view.setInt16(0, 16384, true);
      view.setInt16(2, -16384, true);
      view.setInt16(4, 16384, true);
      view.setInt16(6, -16384, true);
      expect(WaveformUtils.calculateRmsFromPcm16(buffer)).assertEqual(0.5);
    });

    it('uses the selected 24-bit PCM format for the rolling WAV envelope', 0, () => {
      const buffer = new ArrayBuffer(12);
      const view = new DataView(buffer);
      const positive = 4194304;
      const negative = 0xC00000;
      for (let offset = 0; offset < 6; offset += 3) {
        view.setUint8(offset, positive & 0xFF);
        view.setUint8(offset + 1, (positive >> 8) & 0xFF);
        view.setUint8(offset + 2, (positive >> 16) & 0xFF);
      }
      for (let offset = 6; offset < 12; offset += 3) {
        view.setUint8(offset, negative & 0xFF);
        view.setUint8(offset + 1, (negative >> 8) & 0xFF);
        view.setUint8(offset + 2, (negative >> 16) & 0xFF);
      }
      expect(WaveformUtils.calculateRmsFromPcm(buffer, 24)).assertEqual(0.5);
    });

    it('keeps waveform history within a fixed capacity', 0, () => {
      let samples: number[] = [];
      samples = WaveformUtils.appendSample(samples, 0.1, 3);
      samples = WaveformUtils.appendSample(samples, 0.2, 3);
      samples = WaveformUtils.appendSample(samples, 0.3, 3);
      samples = WaveformUtils.appendSample(samples, 0.4, 3);
      expect(samples.length).assertEqual(3);
      expect(samples[0]).assertEqual(0.2);
      expect(samples[2]).assertEqual(0.4);
    });

    it('normalizes AVRecorder amplitude values for the shared waveform', 0, () => {
      expect(WaveformUtils.normalizeAmplitude(0)).assertEqual(0);
      expect(WaveformUtils.normalizeAmplitude(0.25)).assertEqual(0.25);
      expect(WaveformUtils.normalizeAmplitude(16384)).assertEqual(0.5);
      expect(WaveformUtils.normalizeAmplitude(32768)).assertEqual(1);
    });

    it('keeps ordinary sound below the waveform ceiling on the dB display scale', 0, () => {
      expect(WaveformUtils.DISPLAY_FLOOR_DECIBELS).assertEqual(-48);
      expect(WaveformUtils.linearToDecibels(1)).assertEqual(0);
      expect(WaveformUtils.linearToDecibels(0)).assertEqual(-60);
      expect(WaveformUtils.displayHeight(0.05) < 1).assertTrue();
      expect(WaveformUtils.displayHeight(1)).assertEqual(1);
    });
  });
}
