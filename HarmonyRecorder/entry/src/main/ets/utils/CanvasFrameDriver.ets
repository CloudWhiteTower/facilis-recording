import { displaySync } from '@kit.ArkGraphics2D';
import { UIContext } from '@kit.ArkUI';
import { MotionFrameClock, WaveformMotion } from './WaveformMotion';

// Lazily subscribed, UI-scoped VSync for the recording Canvas components.
export class CanvasFrameDriver {
  private sync: displaySync.DisplaySync | undefined = undefined;
  private consumer: ((deltaMs: number) => void) | undefined = undefined;
  private active: boolean = false;
  private readonly clock: MotionFrameClock = new MotionFrameClock();

  start(context: UIContext, consumer: (deltaMs: number) => void): void {
    this.consumer = consumer;
    if (this.active) {
      return;
    }
    if (this.sync === undefined) {
      const sync = displaySync.create();
      sync.setExpectedFrameRateRange({
        min: WaveformMotion.MIN_FRAME_RATE,
        max: WaveformMotion.EXPECTED_FRAME_RATE,
        expected: WaveformMotion.EXPECTED_FRAME_RATE
      });
      sync.on('frame', (info: displaySync.IntervalInfo): void => {
        if (this.active && this.consumer !== undefined) {
          this.consumer(this.clock.next(info.timestamp));
        }
      });
      this.sync = sync;
    }
    this.clock.reset();
    context.runScopedTask((): void => {
      this.sync?.start();
    });
    this.active = true;
  }

  stop(): void {
    if (this.active) {
      this.active = false;
      this.sync?.stop();
    }
    this.clock.reset();
    this.consumer = undefined;
  }

  release(): void {
    this.stop();
    this.sync?.off('frame');
    this.sync = undefined;
  }
}
