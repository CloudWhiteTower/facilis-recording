// Keep the system font and its accessibility scaling. Only the semantic size,
// line height and emphasis are shared, so pages do not acquire separate fonts.
export enum TextRole {
  TICK,
  CAPTION,
  METADATA,
  BODY,
  TITLE,
  TIMER,
  HERO,
  HERO_WIDE,
  HERO_COMPACT
}

export class VisualTheme {
  static readonly BODY_SIZE: number = 16;
  static readonly ICON_TOOL: number = 20;
  static readonly ICON_TAB: number = 24;
  static readonly ICON_PRIMARY: number = 28;
  static readonly ICON_SECONDARY: number = 24;
  static readonly ICON_SMALL: number = 12;
  static readonly ICON_EMPTY: number = 44;
  static readonly CONTROL_HEIGHT: number = 44;
  static readonly ACTION_HEIGHT: number = 56;
  static readonly INPUT_HEIGHT: number = 48;
  static readonly PRIMARY_BUTTON: number = 72;
  static readonly SECONDARY_BUTTON: number = 56;
  static readonly PRIMARY_PLATE: number = 96;
  static readonly CONTROL_SLOT: number = 112;
  static readonly COMPACT_CONTROL_SLOT: number = 104;

  static text(role: TextRole, emphasized: boolean = false, tabular: boolean = false): TextStyleModifier {
    return new TextStyleModifier(role, emphasized, tabular);
  }
}

export class TextStyleModifier implements AttributeModifier<TextAttribute> {
  private role: TextRole;
  private emphasized: boolean;
  private tabular: boolean;

  constructor(role: TextRole, emphasized: boolean, tabular: boolean) {
    this.role = role;
    this.emphasized = emphasized;
    this.tabular = tabular;
  }

  applyNormalAttribute(component: TextAttribute): void {
    let size = VisualTheme.BODY_SIZE;
    let lineHeight = 24;
    let emphasized = this.emphasized;
    switch (this.role) {
      case TextRole.TICK: size = 10; lineHeight = 14; break;
      case TextRole.CAPTION: size = 12; lineHeight = 16; break;
      case TextRole.METADATA: size = 13; lineHeight = 20; break;
      case TextRole.TITLE: size = 20; lineHeight = 28; emphasized = true; break;
      case TextRole.TIMER: size = 18; lineHeight = 24; emphasized = true; break;
      case TextRole.HERO: size = 28; lineHeight = 36; emphasized = true; break;
      case TextRole.HERO_WIDE: size = 32; lineHeight = 40; emphasized = true; break;
      case TextRole.HERO_COMPACT: size = 22; lineHeight = 30; emphasized = true; break;
    }
    component.fontSize(`${size}fp`).lineHeight(`${lineHeight}fp`)
      .fontWeight(emphasized ? FontWeight.Medium : FontWeight.Regular)
      .fontFeature(this.tabular ? '"tnum" 1' : 'normal');
  }
}
