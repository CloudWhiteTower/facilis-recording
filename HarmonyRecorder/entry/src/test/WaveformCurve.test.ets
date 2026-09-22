import { describe, expect, it } from '@ohos/hypium';
import { WaveformCurve } from '../main/ets/utils/WaveformCurve';

export default function waveformCurveTest() {
  describe('waveformCurveTest', () => {
    it('keeps silence on the baseline and clips long histories to a finite window', 0, () => {
      const silence = WaveformCurve.points([], 320, 170, 1);
      expect(silence.every(point => point.y === 167)).assertTrue();
      const history: number[] = [];
      for (let index = 0; index < 2000; index++) {
        history.push(index < 1999 ? 1 : 0.1);
      }
      const points = WaveformCurve.points(history, 320, 170, 1);
      expect(points.length <= 180).assertTrue();
      expect(points[points.length - 1].x).assertEqual(317);
      expect(points.every(point => Number.isFinite(point.y) && point.y >= 3 && point.y <= 167)).assertTrue();
    });
    it('interpolates measured extrema without creating extra amplitude peaks', 0, () => {
      const signals: number[][] = [[0, 1, 0], [0.001, 0.01, 0.1, 1], [1, 0.4, 0.01, 0],
        [0.1, 0.1, 0.1], [0, 1, 0.001, 0.9, 0.002]];
      for (const signal of signals) {
        const segments = WaveformCurve.segments(WaveformCurve.points(signal, 320, 170, 1));
        for (const segment of segments) {
          for (let step = 0; step <= 20; step++) {
            const point = WaveformCurve.at(segment, step / 20);
            expect(point.y >= Math.min(segment.start.y, segment.end.y) - 0.000001).assertTrue();
            expect(point.y <= Math.max(segment.start.y, segment.end.y) + 0.000001).assertTrue();
          }
        }
      }
    });
    it('keeps the live dot on the curve at the right viewport edge during scrolling', 0, () => {
      for (const phase of [0, 0.25, 0.5, 0.75, 1]) {
        const segments = WaveformCurve.segments(WaveformCurve.points([0.01, 0.8], 320, 170, phase));
        const head = WaveformCurve.at(segments[segments.length - 1], phase);
        expect(Math.abs(head.x - 317) < 0.000001).assertTrue();
        expect(head.y >= 3 && head.y <= 167).assertTrue();
      }
    });
  });
}
