import { common } from '@kit.AbilityKit';
import { DividerMode, HdsNavigation, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { HarmonyPalette, HarmonyTheme, HarmonyTokens, ThemeMode, ThemeStore } from '../utils/HarmonyTheme';
import { MaterialRole, MaterialTheme } from '../utils/MaterialTheme';
import { AppPage, NavigationStore } from '../utils/NavigationStore';
import { PlayerPage } from './PlayerPage';
import { RecorderPage } from './RecorderPage';
import { RecordingsPage } from './RecordingsPage';
import { SettingsPage } from './SettingsPage';

@Entry
@Component
struct Index {
  @StorageLink(NavigationStore.PAGE_KEY) @Watch('onPageChanged') private currentPage: number = AppPage.RECORDER;
  @StorageLink(NavigationStore.ACTIVE_RECORDING_KEY) private isRecordingActive: boolean = false;
  @StorageLink(ThemeStore.MODE_KEY) @Watch('onThemeModeChange') private themeMode: number = ThemeMode.LIGHT;
  private readonly tabsController: HdsTabsController = new HdsTabsController();
  private readonly pageStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    ThemeStore.initialize();
    NavigationStore.initialize();
    this.applyThemeMode();
  }

  build() {
    HdsNavigation(this.pageStack) {
        HdsTabs({
          barPosition: BarPosition.End,
          index: this.selectedTabIndex(),
          controller: this.tabsController
        }) {
          TabContent() {
            RecorderPage({ isVisible: this.currentPage === AppPage.RECORDER })
          }
          .tabBar(this.tabBarItem($r('sys.symbol.mic_fill'), '录制', AppPage.RECORDER))

          TabContent() {
            RecordingsPage({ isVisible: this.currentPage === AppPage.RECORDINGS })
          }
          .tabBar(this.tabBarItem($r('sys.symbol.list_bullet'), '资料库', AppPage.RECORDINGS))

          TabContent() {
            SettingsPage()
          }
          .tabBar(this.tabBarItem($r('sys.symbol.gearshape'), '设置', AppPage.SETTINGS))
        }
        .width('100%')
        .height('100%')
        .vertical(false)
        .barPosition(BarPosition.End)
        .scrollable(false)
        .barOverlap(true)
        .barHeight(64)
        .animationDuration(280)
        .divider({ mode: DividerMode.NONE })
        .barFloatingStyle({
          barWidth: {
            smallWidth: 248,
            mediumWidth: 300,
            largeWidth: 360
          },
          barBottomMargin: 16,
          gradientMask: {
            maskColor: HarmonyTokens.pageBackground(),
            maskHeight: 108
          },
          lightColor: HarmonyTokens.primaryGlow(),
          systemMaterialEffect: MaterialTheme.resolve(MaterialRole.NAVIGATION),
          thermoCtrl: true,
          barOpacity: 0.96
        })
        .onContentWillChange((currentIndex: number, comingIndex: number): boolean => {
          return !this.isRecordingActive || comingIndex === 0;
        })
        .onChange((index: number): void => {
          if (this.currentPage !== AppPage.PLAYER) {
            NavigationStore.open(this.pageForTab(index));
          }
        })
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.destination)
    .width('100%')
    .height('100%')
    .backgroundColor(HarmonyTokens.pageBackground())
  }

  @Builder
  private destination(name: string) {
    if (name === 'player') {
      PlayerPage()
    }
  }

  private onPageChanged(): void {
    if (this.currentPage === AppPage.PLAYER) {
      if (this.pageStack.size() === 0) {
        this.pageStack.pushPathByName('player', undefined);
      }
    } else if (this.pageStack.size() > 0) {
      this.pageStack.pop();
    }
  }

  @Builder
  private tabBarItem(symbol: Resource, title: string, page: AppPage) {
    Column() {
      Stack() {
        if (this.currentPage === page) {
          Column()
            .width(52)
            .height(44)
            .borderRadius(19)
            .backgroundColor(HarmonyTokens.primarySubtle())
        }
        SymbolGlyph(symbol)
          .fontSize(24)
          .fontColor([this.currentPage === page ? HarmonyTokens.primary() : HarmonyTokens.textSecondary()])
      }
      .width(64)
      .height(44)
      .alignContent(Alignment.Center)
    }
    .width(76)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .opacity(this.canOpen(page) ? 1 : 0.36)
    .accessibilityText(title)
  }

  private selectedTabIndex(): number {
    if (this.currentPage === AppPage.RECORDINGS || this.currentPage === AppPage.PLAYER) {
      return 1;
    }
    if (this.currentPage === AppPage.SETTINGS) {
      return 2;
    }
    return 0;
  }

  private pageForTab(index: number): AppPage {
    if (index === 1) {
      return AppPage.RECORDINGS;
    }
    if (index === 2) {
      return AppPage.SETTINGS;
    }
    return AppPage.RECORDER;
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
