import { common } from '@kit.AbilityKit';
import { AppPage, NavigationStore } from '../utils/NavigationStore';
import { HarmonyPalette, HarmonyTheme, ThemeMode, ThemeStore } from '../utils/HarmonyTheme';
import { PlayerPage } from './PlayerPage';
import { RecorderPage } from './RecorderPage';
import { RecordingsPage } from './RecordingsPage';
import { SettingsPage } from './SettingsPage';

@Entry
@Component
struct Index {
  @StorageLink(NavigationStore.PAGE_KEY) private currentPage: number = AppPage.RECORDER;
  @StorageLink(NavigationStore.ACTIVE_RECORDING_KEY) private isRecordingActive: boolean = false;
  @StorageLink(ThemeStore.MODE_KEY) @Watch('onThemeModeChange') private themeMode: number = ThemeMode.LIGHT;

  aboutToAppear(): void {
    ThemeStore.initialize();
    NavigationStore.initialize();
    this.applyThemeMode();
  }

  build() {
    Column() {
      if (this.currentPage === AppPage.PLAYER) {
        PlayerPage();
      } else {
        if (this.currentPage === AppPage.RECORDER) {
          RecorderPage();
        } else if (this.currentPage === AppPage.RECORDINGS) {
          RecordingsPage();
        } else {
          SettingsPage();
        }
        this.bottomNavigation()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(HarmonyTheme.palette(this.themeMode).pageBackground)
  }

  @Builder
  private bottomNavigation() {
    Row({ space: 0 }) {
      this.navigationItem($r('sys.symbol.mic_fill'), '录制', AppPage.RECORDER)
      this.navigationItem($r('sys.symbol.list_bullet'), '资料库', AppPage.RECORDINGS)
      this.navigationItem($r('sys.symbol.gearshape'), '设置', AppPage.SETTINGS)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 4, bottom: 8 })
    .backgroundColor(this.palette().surface)
    .border({ width: { top: 1 }, color: this.palette().divider })
  }

  @Builder
  private navigationItem(symbol: Resource, title: string, page: AppPage) {
    Button() {
      Column({ space: 4 }) {
        SymbolGlyph(symbol)
          .fontSize(24)
          .fontColor([this.currentPage === page ? this.palette().primary : this.palette().textSecondary])
        if (this.currentPage === page) {
          Column()
            .width(18)
            .height(3)
            .borderRadius(2)
            .backgroundColor(this.palette().primary)
        } else {
          Blank().height(3)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .layoutWeight(1)
    .height(52)
    .backgroundColor('#00000000')
    .borderRadius(16)
    .enabled(this.canOpen(page))
    .accessibilityText(title)
    .opacity(this.canOpen(page) ? 1 : 0.38)
    .onClick((): void => {
      if (this.canOpen(page)) {
        NavigationStore.open(page);
      }
    })
  }

  private canOpen(page: AppPage): boolean {
    return page === AppPage.RECORDER || !this.isRecordingActive;
  }

  private onThemeModeChange(): void {
    this.applyThemeMode();
  }

  private applyThemeMode(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ThemeStore.applySystemMode(context, this.themeMode);
  }

  private palette(): HarmonyPalette {
    return HarmonyTheme.palette(this.themeMode);
  }
}
