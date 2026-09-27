import { describe, expect, it } from '@ohos/hypium';
import { MotionFrameClock, WaveformMotion, WaveformScroll } from '../main/ets/utils/WaveformMotion';
import { WaveformCurve } from '../main/ets/utils/WaveformCurve';
import { WaveformUtils } from '../main/ets/utils/WaveformUtils';

export default function waveformMotionTest() {
  describe('waveformMotionTest', () => {
    it('uses monotonic nanoseconds and ignores time spent paused or hidden', 0, () => {
      const clock = new MotionFrameClock();
      expect(clock.next(1000000000)).assertEqual(0);
      expect(clock.next(1016000000)).assertEqual(16);
      expect(clock.next(1015000000)).assertEqual(0);
      expect(clock.next(Number.NaN)).assertEqual(0);
      expect(clock.next(1032000000)).assertEqual(16);
      clock.reset();
      expect(clock.next(60000000000)).assertEqual(0);
      expect(clock.next(60016000000)).assertEqual(16);
      expect(clock.next(61000000000)).assertEqual(50);
    });

    it('uses the actual WAV and M4A cadence instead of finishing M4A in 90 ms', 0, () => {
      const wav = new WaveformScroll();
      const m4a = new WaveformScroll();
      wav.offer([0.5]);
      m4a.offer([0.5]);
      wav.advance(90, 90);
      m4a.advance(90, 120);
      expect(wav.scrollPhase).assertEqual(1);
      expect(m4a.scrollPhase).assertEqual(0.75);
      m4a.advance(30, 120);
      expect(m4a.scrollPhase).assertEqual(1);
      expect(WaveformMotion.scrollPhase(60, 120)).assertEqual(0.5);
    });

    it('does not rewind half a column when the next measured sample arrives early', 0, () => {
      const scroll = new WaveformScroll();
      scroll.reset([0.01]);
      scroll.offer([0.01, 0.8]);
      scroll.advance(45, 90);
      const before = WaveformCurve.points(scroll.values, 320, 170, scroll.scrollPhase);
      scroll.offer([0.01, 0.8, 0.1]);
      const after = WaveformCurve.points(scroll.values, 320, 170, scroll.scrollPhase);
      expect(scroll.scrollPhase).assertEqual(0.5);
      expect(after[after.length - 2].x).assertEqual(before[before.length - 2].x);
      expect(after[after.length - 2].y).assertEqual(before[before.length - 2].y);
      scroll.advance(45, 90);
      const handoff = WaveformCurve.points(scroll.values, 320, 170, scroll.scrollPhase);
      expect(scroll.values.length).assertEqual(3);
      expect(scroll.scrollPhase).assertEqual(0);
      expect(handoff[handoff.length - 2].x).assertEqual(317);
    });

    it('keeps pending measured peaks and carries frame time through a handoff', 0, () => {
      const scroll = new WaveformScroll();
      scroll.offer([0.1]);
      scroll.advance(80, 90);
      scroll.offer([0.1, 1]);
      scroll.advance(20, 90);
      expect(scroll.values[1]).assertEqual(1);
      expect(Math.abs(scroll.scrollPhase - 10 / 90) < 0.000001).assertTrue();
      scroll.offer([0.1, 1, 0.01]);
      scroll.advance(170, 90);
      expect(scroll.values[0]).assertEqual(0.1);
      expect(scroll.values[1]).assertEqual(1);
      expect(scroll.values[2]).assertEqual(0.01);
      expect(scroll.scrollPhase).assertEqual(1);
    });

    it('does not replay unchanged snapshots or move on the first resumed frame', 0, () => {
      const scroll = new WaveformScroll();
      scroll.offer([0.1, 0.5]);
      scroll.advance(30, 90);
      expect(scroll.offer([0.1, 0.5])).assertFalse();
      expect(scroll.advance(0, 90)).assertFalse();
      expect(scroll.scrollPhase).assertEqual(1 / 3);
      expect(scroll.values[1]).assertEqual(0.5);
    });

    it('shows current measured values statically in reduced motion without changing source data', 0, () => {
      const scroll = new WaveformScroll();
      const source = [0, 1, 0.1];
      scroll.offer([0.1]);
      scroll.offer(source);
      scroll.reset(source);
      expect(scroll.scrollPhase).assertEqual(1);
      expect(scroll.advance(16, 90)).assertFalse();
      expect(scroll.values[1]).assertEqual(1);
      source[1] = 0.5;
      expect(scroll.values[1]).assertEqual(1);
      expect(source.length).assertEqual(3);
    });

    it('bounds stale display frames and reaches the newest measured history after a long UI stall', 0, () => {
      const scroll = new WaveformScroll();
      const source: number[] = [];
      let history: number[] = [];
      for (let index = 1; index <= 1000; index++) {
        const measured = index / 1000;
        source.push(measured);
        history = WaveformUtils.appendSample(history, measured);
        scroll.offer(history);
      }
      for (let frame = 0; frame < 10; frame++) {
        scroll.advance(90, 90);
        expect(scroll.values.every((value: number): boolean => source.includes(value))).assertTrue();
      }
      expect(scroll.values.length).assertEqual(WaveformUtils.MAX_SAMPLES);
      expect(scroll.values[scroll.values.length - 1]).assertEqual(1);
      expect(scroll.values.every((value: number, index: number): boolean => value === history[index])).assertTrue();
      expect(scroll.scrollPhase).assertEqual(1);
      expect(source.length).assertEqual(1000);
      expect(source[0]).assertEqual(0.001);
      expect(source[999]).assertEqual(1);
    });
  });
}
