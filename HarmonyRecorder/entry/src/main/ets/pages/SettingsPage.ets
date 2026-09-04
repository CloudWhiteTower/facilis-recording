import { common } from '@kit.AbilityKit';
import { HarmonyPalette, HarmonyTheme, ThemeMode, ThemeStore } from '../utils/HarmonyTheme';
import { ResponsiveLayout } from '../utils/ResponsiveLayout';

@Component
export struct SettingsPage {
  @State private isWide: boolean = false;
  @StorageLink(ThemeStore.MODE_KEY) private themeMode: number = ThemeMode.LIGHT;

  build() {
    Column({ space: 0 }) {
      Row() {
        Text('设置')
          .fontSize(this.isWide ? 30 : 26)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().textPrimary)
      }
      .width(ResponsiveLayout.contentWidth(this.isWide))
      .padding({
        left: ResponsiveLayout.horizontalPadding(this.isWide),
        right: ResponsiveLayout.horizontalPadding(this.isWide),
        top: this.isWide ? 30 : 18,
        bottom: 18
      })

      Column({ space: 12 }) {
        Text('外观')
          .width('100%')
          .fontSize(13)
          .fontColor(this.palette().textTertiary)
          .padding({ left: 4, bottom: 4 })
        Row({ space: 16 }) {
          this.appearanceChoice($r('sys.symbol.sun_max'), $r('sys.symbol.sun_max_fill'), '浅色模式', ThemeMode.LIGHT)
          this.appearanceChoice($r('sys.symbol.moon'), $r('sys.symbol.moon_fill'), '深色模式', ThemeMode.DARK)
        }
        .width('100%')
      }
      .width(ResponsiveLayout.contentWidth(this.isWide))
      .layoutWeight(1)
      .padding({
        left: ResponsiveLayout.horizontalPadding(this.isWide),
        right: ResponsiveLayout.horizontalPadding(this.isWide),
        bottom: 24
      })
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(this.palette().pageBackground)
    .onAreaChange((oldValue: Area, newValue: Area): void => {
      this.isWide = ResponsiveLayout.isWide(newValue.width);
    })
  }

  @Builder
  private appearanceChoice(symbol: Resource, selectedSymbol: Resource, title: string, mode: ThemeMode) {
    Button() {
      if (this.themeMode === mode) {
        SymbolGlyph(selectedSymbol)
          .fontSize(27)
          .fontColor([this.palette().primary])
      } else {
        SymbolGlyph(symbol)
          .fontSize(27)
          .fontColor([this.palette().textSecondary])
      }
    }
    .width(72)
    .height(56)
    .backgroundColor(this.themeMode === mode ? this.palette().primarySubtle : this.palette().surface)
    .borderRadius(18)
    .border({
      width: this.themeMode === mode ? 2 : 1,
      color: this.themeMode === mode ? this.palette().primaryBorder : this.palette().divider
    })
    .accessibilityText(title)
    .onClick((): void => {
      ThemeStore.setMode(mode);
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ThemeStore.applySystemMode(context, mode);
    })
  }

  private palette(): HarmonyPalette {
    return HarmonyTheme.palette(this.themeMode);
  }
}
