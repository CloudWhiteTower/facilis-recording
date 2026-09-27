import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { HarmonyPalette, HarmonyTheme, HarmonyTokens, ThemeMode, ThemeStore } from '../utils/HarmonyTheme';
import { MaterialRole, MaterialTheme } from '../utils/MaterialTheme';
import { MotionTheme } from '../utils/MotionTheme';
import { PressFeedback } from '../utils/PressFeedback';
import { ResponsiveLayout } from '../utils/ResponsiveLayout';

@Component
export struct SettingsPage {
  @State private isWide: boolean = false;
  @StorageLink(ThemeStore.MODE_KEY) private themeMode: number = ThemeMode.LIGHT;
  @StorageLink(MotionTheme.REDUCE_KEY) private reduceMotion: boolean = false;

  build() {
    HdsNavigation() {
      Scroll() {
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

        }
        .width(ResponsiveLayout.contentWidth(this.isWide))
        .constraintSize({ maxWidth: 720 })
        .padding({
          left: ResponsiveLayout.horizontalPadding(this.isWide),
          right: ResponsiveLayout.horizontalPadding(this.isWide),
          top: 16,
          bottom: 120
        })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
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
    .mode(NavigationMode.Stack)
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
    .animation(MotionTheme.content(this.reduceMotion))
    .animation(undefined)
    .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion, false,
      this.themeMode === mode ? 1 : 0.96))
    .animation(MotionTheme.press(this.reduceMotion))
    .accessibilityText(`${title}模式`)
    .accessibilityChecked(this.themeMode === mode)
    .onClick((): void => {
      if (this.themeMode !== mode) {
        // Index owns application/window configuration; avoid applying it twice.
        ThemeStore.setMode(mode);
      }
    })
  }

  private palette(): HarmonyPalette {
    return HarmonyTheme.palette(this.themeMode);
  }
}
