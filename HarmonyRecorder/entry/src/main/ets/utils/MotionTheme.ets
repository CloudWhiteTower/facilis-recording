import { curves } from '@kit.ArkUI';

// Short, interruptible system animations. Audio clocks and Canvas frames do not
// run through animateTo; this policy only covers user-driven UI state changes.
export class MotionTheme {
  static readonly REDUCE_KEY: string = 'harmony_recorder_reduce_motion';
  static readonly TAB_DURATION_MS: number = 280;

  static reduced(): boolean {
    return AppStorage.get<boolean>(MotionTheme.REDUCE_KEY) ?? false;
  }

  static press(reduced: boolean = MotionTheme.reduced()): AnimateParam {
    return reduced ? { duration: 0, curve: Curve.Linear } : {
      curve: curves.responsiveSpringMotion(0.24, 0.9, 0.12),
      expectedFrameRateRange: { min: 30, max: 120, expected: 120 }
    };
  }

  static state(reduced: boolean = MotionTheme.reduced()): AnimateParam {
    return reduced ? { duration: 0, curve: Curve.Linear } : {
      curve: curves.springMotion(0.32, 0.9, 0.12),
      expectedFrameRateRange: { min: 30, max: 120, expected: 120 }
    };
  }

  static content(reduced: boolean = MotionTheme.reduced()): AnimateParam {
    return {
      duration: reduced ? 0 : 180,
      curve: Curve.EaseOut,
      expectedFrameRateRange: { min: 30, max: 120, expected: 120 }
    };
  }

  static appear(reduced: boolean = MotionTheme.reduced()): TransitionEffect {
    if (reduced) {
      return TransitionEffect.OPACITY.animation({ duration: 0 });
    }
    return TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 6 })).animation(MotionTheme.content(reduced)),
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -3 }))
        .animation({ duration: 120, curve: Curve.EaseOut })
    );
  }
}
