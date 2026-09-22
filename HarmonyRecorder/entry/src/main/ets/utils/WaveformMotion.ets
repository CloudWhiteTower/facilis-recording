import { RecordingState } from '../models/RecordingTypes';

// Pure lifecycle policy, shared by Canvas scheduling and unit tests.
export class WaveformMotion {
  static readonly FRAME_INTERVAL_MS: number = 1000 / 30;
  static readonly SAMPLE_INTERVAL_MS: number = 90;

  static shouldAnimate(state: RecordingState, visible: boolean, foreground: boolean): boolean {
    return state === RecordingState.RECORDING && visible && foreground;
  }

  static showsHistory(state: RecordingState): boolean {
    return state === RecordingState.RECORDING || state === RecordingState.PAUSED;
  }

  static scrollPhase(elapsedMs: number): number {
    return Math.max(0, Math.min(1, elapsedMs / WaveformMotion.SAMPLE_INTERVAL_MS));
  }
}
