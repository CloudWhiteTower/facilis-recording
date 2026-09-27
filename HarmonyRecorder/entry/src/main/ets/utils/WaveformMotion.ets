import { RecordingState } from '../models/RecordingTypes';

// Pure lifecycle policy, shared by Canvas scheduling and unit tests.
export class WaveformMotion {
  static readonly EXPECTED_FRAME_RATE: number = 60;
  static readonly MIN_FRAME_RATE: number = 30;
  static readonly SAMPLE_INTERVAL_MS: number = 90;

  static shouldAnimate(state: RecordingState, visible: boolean, foreground: boolean,
    reduceMotion: boolean = false): boolean {
    return state === RecordingState.RECORDING && visible && foreground && !reduceMotion;
  }

  static showsHistory(state: RecordingState): boolean {
    return state === RecordingState.RECORDING || state === RecordingState.PAUSED;
  }

  static scrollPhase(elapsedMs: number, sampleIntervalMs: number = WaveformMotion.SAMPLE_INTERVAL_MS): number {
    const interval = Number.isFinite(sampleIntervalMs) && sampleIntervalMs > 0 ?
      sampleIntervalMs : WaveformMotion.SAMPLE_INTERVAL_MS;
    return Math.max(0, Math.min(1, Number.isFinite(elapsedMs) ? elapsedMs / interval : 0));
  }
}

// DisplaySync timestamps are monotonic nanoseconds, not wall-clock milliseconds.
// Reset on every start so time spent paused or offscreen is never replayed.
export class MotionFrameClock {
  private previousTimestampNs: number = 0;

  reset(): void {
    this.previousTimestampNs = 0;
  }

  next(timestampNs: number): number {
    if (!Number.isFinite(timestampNs) || timestampNs <= 0) {
      return 0;
    }
    const previous = this.previousTimestampNs;
    if (timestampNs <= previous) {
      return 0;
    }
    this.previousTimestampNs = timestampNs;
    if (previous <= 0) {
      return 0;
    }
    return Math.min(50, (timestampNs - previous) / 1000000);
  }
}

// Queue measured snapshots until the preceding column has finished scrolling.
// Handoffs happen at phase 1 -> 0, keeping the shared history at the same x.
export class WaveformScroll {
  private static readonly MAX_PENDING_SNAPSHOTS: number = 8;
  private displayed: number[] = [];
  private received: number[] = [];
  private pending: number[][] = [];
  private phase: number = 1;

  get values(): number[] {
    return this.displayed;
  }

  get scrollPhase(): number {
    return this.phase;
  }

  reset(values: number[]): void {
    this.displayed = values.slice();
    this.received = values.slice();
    this.pending = [];
    this.phase = 1;
  }

  offer(values: number[]): boolean {
    if (values.length === this.received.length &&
      values.every((value: number, index: number): boolean => value === this.received[index])) {
      return false;
    }
    this.received = values.slice();
    if (this.phase >= 1 && this.pending.length === 0) {
      this.displayed = this.received;
      this.phase = 0;
    } else {
      // Every snapshot already contains the measured rolling history. Under
      // sustained low FPS, skip stale display frames instead of accumulating
      // latency; neither source samples nor the audio recording are changed.
      if (this.pending.length >= WaveformScroll.MAX_PENDING_SNAPSHOTS) {
        this.pending.shift();
      }
      this.pending.push(this.received);
    }
    return true;
  }

  advance(deltaMs: number, sampleIntervalMs: number): boolean {
    if (!Number.isFinite(deltaMs) || deltaMs <= 0 || (this.phase >= 1 && this.pending.length === 0)) {
      return false;
    }
    const interval = Number.isFinite(sampleIntervalMs) && sampleIntervalMs > 0 ?
      sampleIntervalMs : WaveformMotion.SAMPLE_INTERVAL_MS;
    // A delayed UI catches up with the bounded, current measured history.
    let distance = deltaMs / interval * Math.max(1, Math.min(4, this.pending.length));
    while (distance > 0) {
      const step = Math.min(distance, 1 - this.phase);
      this.phase += step;
      if (1 - this.phase < 0.000001) {
        this.phase = 1;
      }
      distance -= step;
      if (this.phase < 1 || this.pending.length === 0) {
        break;
      }
      const next = this.pending.shift();
      if (next !== undefined) {
        this.displayed = next;
        this.phase = 0;
      }
    }
    return true;
  }
}
