import { hdsEffect } from '@kit.UIDesignKit';
import { ThemeMode } from './HarmonyTheme';

// API 20 HDS pressShadow works on ordinary Buttons, including gradient buttons.
// It is separate from API 26 uiMaterial and does not require a moving point light.
export class PressFeedback {
  static button(themeMode: number, reduced: boolean, emphasized: boolean = false,
    baseScale: number = 1): ButtonPressModifier {
    return new ButtonPressModifier(themeMode, reduced, emphasized, baseScale);
  }
}

export class ButtonPressModifier implements AttributeModifier<ButtonAttribute> {
  private themeMode: number;
  private reduced: boolean;
  private emphasized: boolean;
  private baseScale: number;

  constructor(themeMode: number, reduced: boolean, emphasized: boolean, baseScale: number) {
    this.themeMode = themeMode;
    this.reduced = reduced;
    this.emphasized = emphasized;
    this.baseScale = baseScale;
  }

  applyNormalAttribute(button: ButtonAttribute): void {
    button.stateEffect(false)
      .visualEffect(new hdsEffect.HdsEffectBuilder().pressShadow(hdsEffect.PressShadowType.NONE).buildEffect())
      .scale({ x: this.baseScale, y: this.baseScale })
      .shadow({ radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 });
  }

  applyPressedAttribute(button: ButtonAttribute): void {
    const scale = this.baseScale * (this.reduced ? 1 : this.emphasized ? 0.94 : 0.97);
    button.visualEffect(new hdsEffect.HdsEffectBuilder()
      .pressShadow(hdsEffect.PressShadowType.BLEND_WHITE).buildEffect())
      .scale({ x: scale, y: scale })
      .shadow({
        radius: this.emphasized ? 16 : 8,
        color: this.themeMode === ThemeMode.DARK ? '#66FFB457' : '#40C85A10',
        offsetX: 0,
        offsetY: 0
      });
  }

  applyDisabledAttribute(button: ButtonAttribute): void {
    // Disabled beats pressed, including a button disabled while a request starts.
    this.applyNormalAttribute(button);
  }
}
