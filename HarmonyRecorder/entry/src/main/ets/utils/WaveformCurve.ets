import { WaveformUtils } from './WaveformUtils';

export interface WavePoint {
  x: number;
  y: number;
}

export interface WaveSegment {
  start: WavePoint;
  first: WavePoint;
  second: WavePoint;
  end: WavePoint;
}

// Monotone cubic interpolation preserves measured peaks without spline overshoot.
// This is an amplitude envelope, not a reconstruction of the audio PCM signal.
export class WaveformCurve {
  static points(samples: number[], width: number, height: number, phase: number,
    floor: number = -48, ceiling: number = 0): WavePoint[] {
    const window = WaveformUtils.samplesForWidth(samples, width);
    const plotWidth = Math.max(0, Number.isFinite(width) ? width - 6 : 0);
    const plotHeight = Math.max(0, Number.isFinite(height) ? height - 6 : 0);
    const slot = plotWidth / Math.max(1, window.length - 1);
    const scroll = Number.isFinite(phase) ? Math.max(0, Math.min(1, phase)) : 1;
    return window.map((sample: number, index: number): WavePoint => ({
      x: 3 + (index + 1 - scroll) * slot,
      y: 3 + WaveformUtils.decibelY(WaveformUtils.linearToDecibels(sample), plotHeight, floor, ceiling)
    }));
  }

  static segments(points: WavePoint[]): WaveSegment[] {
    const slopes: number[] = points.map((): number => 0);
    for (let index = 1; index < points.length - 1; index++) {
      const before = points[index].y - points[index - 1].y;
      const after = points[index + 1].y - points[index].y;
      if (before * after > 0) {
        slopes[index] = 2 * before * after / (before + after);
      }
    }
    const result: WaveSegment[] = [];
    for (let index = 0; index + 1 < points.length; index++) {
      const start = points[index];
      const end = points[index + 1];
      const third = (end.x - start.x) / 3;
      result.push({
        start: start,
        first: { x: start.x + third, y: start.y + slopes[index] / 3 },
        second: { x: end.x - third, y: end.y - slopes[index + 1] / 3 },
        end: end
      });
    }
    return result;
  }

  static at(segment: WaveSegment, position: number): WavePoint {
    const t = Math.max(0, Math.min(1, Number.isFinite(position) ? position : 0));
    const u = 1 - t;
    return {
      x: u * u * u * segment.start.x + 3 * u * u * t * segment.first.x +
        3 * u * t * t * segment.second.x + t * t * t * segment.end.x,
      y: u * u * u * segment.start.y + 3 * u * u * t * segment.first.y +
        3 * u * t * t * segment.second.y + t * t * t * segment.end.y
    };
  }
}
