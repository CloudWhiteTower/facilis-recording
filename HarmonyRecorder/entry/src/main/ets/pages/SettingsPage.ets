import { common } from '@kit.AbilityKit';
import { curves } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { HarmonyPalette, HarmonyTheme, HarmonyTokens, ThemeMode, ThemeStore } from '../utils/HarmonyTheme';
import { MaterialRole, MaterialTheme } from '../utils/MaterialTheme';
import { ResponsiveLayout } from '../utils/ResponsiveLayout';

@Component
export struct SettingsPage {
  @State private isWide: boolean = false;
  @StorageLink(ThemeStore.MODE_KEY) private themeMode: number = ThemeMode.LIGHT;

  build() {
    HdsNavigation() {
      Column({ space: 12 }) {
        Text('外观')
          .width('100%')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(HarmonyTokens.textTertiary())
          .padding({ left: 4 })

        Row({ space: 12 }) {
          this.appearanceChoice(
            $r('sys.symbol.sun_max'),
            $r('sys.symbol.sun_max_fill'),
            '浅色',
            ThemeMode.LIGHT
          )
          this.appearanceChoice(
            $r('sys.symbol.moon'),
            $r('sys.symbol.moon_fill'),
            '深色',
            ThemeMode.DARK
          )
        }
        .width('100%')
        .padding(8)
        .attributeModifier(MaterialTheme.surface(MaterialRole.CONTROL, this.themeMode))
        .borderRadius(28)

        Blank().layoutWeight(1)
        Blank().height(104)
      }
      .width(ResponsiveLayout.contentWidth(this.isWide))
      .constraintSize({ maxWidth: 920 })
      .height('100%')
      .padding({
        left: ResponsiveLayout.horizontalPadding(this.isWide),
        right: ResponsiveLayout.horizontalPadding(this.isWide),
        top: 16
      })
    }
    .width('100%')
    .height('100%')
    .titleBar({
      content: {
        title: {
          mainTitle: '设置',
          subTitle: 'Facilis Recording'
        }
      },
      style: {
        scrollEffectOpts: { enableScrollEffect: false },
        systemMaterialEffect: MaterialTheme.resolve(MaterialRole.NAVIGATION)
      },
      enableComponentSafeArea: true
    })
    .titleMode(HdsNavigationTitleMode.FULL)
    .hideBackButton(true)
    .backgroundColor(HarmonyTokens.pageBackground())
    .onAreaChange((oldValue: Area, newValue: Area): void => {
      this.isWide = ResponsiveLayout.isWide(newValue.width);
    })
  }

  @Builder
  private appearanceChoice(symbol: Resource, selectedSymbol: Resource, title: string, mode: ThemeMode) {
    Button() {
      Column({ space: 8 }) {
        SymbolGlyph(this.themeMode === mode ? selectedSymbol : symbol)
          .fontSize(28)
          .fontColor([this.themeMode === mode ? HarmonyTokens.primary() : HarmonyTokens.textSecondary()])
        Text(title)
          .fontSize(13)
          .fontWeight(this.themeMode === mode ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.themeMode === mode ? HarmonyTokens.primary() : HarmonyTokens.textSecondary())
      }
    }
    .layoutWeight(1)
    .height(92)
    .backgroundColor(this.themeMode === mode ? HarmonyTokens.primarySubtle() : Color.Transparent)
    .borderRadius(22)
    .border({
      width: this.themeMode === mode ? 1 : 0,
      color: this.themeMode === mode ? HarmonyTokens.primaryBorder() : Color.Transparent
    })
    .scale({ x: this.themeMode === mode ? 1 : 0.96, y: this.themeMode === mode ? 1 : 0.96 })
    .animation({ curve: curves.springMotion(0.34, 0.82, 0.18) })
    .accessibilityText(`${title}模式`)
    .accessibilityChecked(this.themeMode === mode)
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
