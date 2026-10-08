export class ResponsiveLayout {
  static readonly WIDE_BREAKPOINT: number = 600;

  static isWide(width: Length): boolean {
    return typeof width === 'number' && Number.isFinite(width) && width >= ResponsiveLayout.WIDE_BREAKPOINT;
  }

  static usesSplitLayout(width: number, height: number): boolean {
    // A wide portrait tablet keeps the same vertical composition as a phone.
    return ResponsiveLayout.isWide(width) && Number.isFinite(height) && height > 0 && width > height;
  }

  static recorderWaveformHeight(height: number, split: boolean, hasNotice: boolean = false): number {
    const available = Number.isFinite(height) && height > 0 ? height : 640;
    return Math.max(64, Math.min(split ? 220 : 170,
      Math.floor(available - ResponsiveLayout.recorderFixedHeight(split, hasNotice))));
  }

  static recorderContentHeight(height: number, split: boolean, hasNotice: boolean = false): number {
    const available = Number.isFinite(height) && height > 0 ? height : 640;
    return Math.max(available, ResponsiveLayout.recorderFixedHeight(split, hasNotice) + 64);
  }

  private static recorderFixedHeight(split: boolean, hasNotice: boolean): number {
    // Stage: timer 24 + metadata 52 + two gaps 28 + insets 34 = 138 vp.
    // Reserve 104 vp for the floating tab bar in either orientation.
    // In a row, the 112 vp controls plus a notice fit beside the stage.
    return split ? 138 + 16 + 104 : 138 + 16 + 112 + 8 + 104 + (hasNotice ? 80 : 0);
  }

  static horizontalPadding(isWide: boolean): number {
    return isWide ? 24 : 16;
  }

  static contentWidth(isWide: boolean): Length {
    return '100%';
  }
}
