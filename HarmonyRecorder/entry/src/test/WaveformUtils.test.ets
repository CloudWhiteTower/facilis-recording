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

    it('adapts the visible rolling window between 96 and 180 columns', 0, () => {
      expect(WaveformUtils.visibleSampleCount(200)).assertEqual(96);
      expect(WaveformUtils.visibleSampleCount(480)).assertEqual(150);
      expect(WaveformUtils.visibleSampleCount(900)).assertEqual(180);
    });

    it('keeps only the newest samples and pads an empty leading window', 0, () => {
      const samples: number[] = [];
      for (let index = 0; index < 200; index++) {
        samples.push(index / 200);
      }
      const visible = WaveformUtils.samplesForWidth(samples, 320);
      expect(visible.length).assertEqual(100);
      expect(visible[0] > 0).assertTrue();
      expect(visible[visible.length - 1]).assertEqual(199 / 200);
      const padded = WaveformUtils.samplesForWidth([0.5], 200);
      expect(padded.length).assertEqual(96);
      expect(padded[0]).assertEqual(0);
      expect(padded[95]).assertEqual(0.5);
    });

    it('maps the fade, live gradient, and dB guide regions deterministically', 0, () => {
      expect(WaveformUtils.fadeOpacity(0, 100)).assertEqual(0);
      expect(WaveformUtils.fadeOpacity(15, 100)).assertEqual(1);
      expect(WaveformUtils.liveBlend(79, 100)).assertEqual(0);
      expect(WaveformUtils.liveBlend(99, 100)).assertEqual(1);
      expect(WaveformUtils.decibelY(0, 120)).assertEqual(0);
      expect(WaveformUtils.decibelY(-24, 120)).assertEqual(60);
      expect(WaveformUtils.decibelY(-48, 120)).assertEqual(120);
    });

    it('aligns real amplitudes with the linear dB ruler', 0, () => {
      expect(Math.abs(WaveformUtils.displayHeight(Math.pow(10, -24 / 20), 0) - 0.5) < 0.000001).assertTrue();
      expect(Math.abs(WaveformUtils.displayHeight(Math.pow(10, -12 / 20), 0) - 0.75) < 0.000001).assertTrue();
      expect(WaveformUtils.displayHeight(0, 0)).assertEqual(0);
      expect(WaveformUtils.decibelY(-12, 120, -24, 0)).assertEqual(60);
    });

    it('sanitizes nonfinite values without changing the recording samples', 0, () => {
      const source: number[] = [Number.NaN, Number.POSITIVE_INFINITY, -1, 2];
      const visible = WaveformUtils.samplesForWidth(source, 0);
      expect(visible[92]).assertEqual(0);
      expect(visible[93]).assertEqual(0);
      expect(visible[94]).assertEqual(0);
      expect(visible[95]).assertEqual(1);
      expect(source.length).assertEqual(4);
      expect(WaveformUtils.decibelY(Number.NaN, 120)).assertEqual(120);
    });

    it('uses the same custom dB range for guide positions and labels', 0, () => {
      const marks = WaveformUtils.decibelMarks(-24, 0);
      expect(marks.length).assertEqual(5);
      expect(marks[1]).assertEqual(-6);
      expect(marks[4]).assertEqual(-24);
      expect(WaveformUtils.decibelY(marks[2], 100, -24, 0)).assertEqual(50);
      expect(WaveformUtils.decibelMarks(Number.NaN, Number.NaN)[4]).assertEqual(-48);
    });
  });
}
