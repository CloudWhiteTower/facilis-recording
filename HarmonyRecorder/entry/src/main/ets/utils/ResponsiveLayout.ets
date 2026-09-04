export class ResponsiveLayout {
  static readonly WIDE_BREAKPOINT: number = 600;

  static isWide(width: Length): boolean {
    return typeof width === 'number' && Number.isFinite(width) && width >= ResponsiveLayout.WIDE_BREAKPOINT;
  }

  static horizontalPadding(isWide: boolean): number {
    return isWide ? 40 : 20;
  }

  static contentWidth(isWide: boolean): Length {
    return isWide ? 880 : '100%';
  }
}
