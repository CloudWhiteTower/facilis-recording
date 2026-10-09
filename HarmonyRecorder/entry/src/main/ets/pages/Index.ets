import { common } from '@kit.AbilityKit';
import { VisualTheme } from '../utils/VisualTheme';
import { accessibility } from '@kit.AccessibilityKit';
import { DividerMode, HdsNavigation, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { HarmonyPalette, HarmonyTheme, HarmonyTokens, ThemeMode, ThemeStore } from '../utils/HarmonyTheme';
import { MaterialRole, MaterialTheme } from '../utils/MaterialTheme';
import { MotionTheme } from '../utils/MotionTheme';
import { PressFeedback } from '../utils/PressFeedback';
import { AppPage, NavigationStore } from '../utils/NavigationStore';
import { ResponsiveLayout } from '../utils/ResponsiveLayout';
import { ExportService } from '../services/ExportService';
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
  @StorageLink(MotionTheme.REDUCE_KEY) private reduceMotion: boolean = false;
  @State private highlightedTab: number = 0;
  @State private availableWidth: number = 360;
  @State private isLandscape: boolean = false;
  private readonly tabsController: HdsTabsController = new HdsTabsController();
  private readonly pageStack: NavPathStack = new NavPathStack();
  private motionObserverRegistered: boolean = false;
  private pcmShareCacheChecked: boolean = false;
  private readonly onReduceMotionChanged = (reduced: boolean): void => {
    this.getUIContext().runScopedTask((): void => {
      this.reduceMotion = reduced;
    });
  };

  aboutToAppear(): void {
    ThemeStore.initialize();
    NavigationStore.initialize();
    this.highlightedTab = this.selectedTabIndex();
    try {
      this.reduceMotion = accessibility.isAnimationReduceEnabledSync();
      accessibility.onAnimationReduceStateChange(this.onReduceMotionChanged);
      this.motionObserverRegistered = true;
    } catch (error) {
      console.warn(`Read reduced motion preference failed: ${String(error)}`);
    }
    this.applyThemeMode();
    if (!this.pcmShareCacheChecked) {
      this.pcmShareCacheChecked = true;
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      // Detached once per UI lifetime; switching tabs never repeats directory I/O.
      ExportService.prunePcmShareCache(context).catch((error: Error): void => {
        console.error(`Prune expired PCM share cache failed: ${error.message}`);
      });
    }
  }

  aboutToDisappear(): void {
    if (this.motionObserverRegistered) {
      try {
        accessibility.offAnimationReduceStateChange(this.onReduceMotionChanged);
      } catch (error) {
        console.warn(`Remove reduced motion observer failed: ${String(error)}`);
      } finally {
        this.motionObserverRegistered = false;
      }
    }
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
        .scrollable(!this.isRecordingActive)
        .id('primary-tabs')
        .barOverlap(true)
        .barHeight(64)
        .animationDuration(this.reduceMotion ? 0 : MotionTheme.TAB_DURATION_MS)
        .divider({ mode: DividerMode.NONE })
        .barFloatingStyle({
          barWidth: {
            smallWidth: Math.min(248, Math.max(180, this.availableWidth - 32)),
            mediumWidth: Math.min(this.isLandscape ? 300 : 248, Math.max(180, this.availableWidth - 48)),
            largeWidth: Math.min(this.isLandscape ? 360 : 248, Math.max(180, this.availableWidth - 64))
          },
          barBottomMargin: 16,
          gradientMask: {
            maskColor: this.palette().pageBackground,
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
        .onAnimationStart((index: number, targetIndex: number, event: TabsAnimationEvent): void => {
          // A separate visual index responds immediately without interrupting
          // the system's content transition by changing its bound index.
          this.highlightedTab = targetIndex;
        })
        .onChange((index: number): void => {
          this.highlightedTab = index;
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
    .onAreaChange((oldArea: Area, area: Area): void => {
      const width = Number(area.width);
      if (Number.isFinite(width) && width > 0 && Math.abs(width - this.availableWidth) >= 1) {
        this.availableWidth = width;
      }
      const height = Number(area.height);
      if (Number.isFinite(width) && width > 0 && Number.isFinite(height) && height > 0) {
        this.isLandscape = ResponsiveLayout.usesSplitLayout(width, height);
      }
    })
  }

  @Builder
  private destination(name: string) {
    if (name === 'player') {
      PlayerPage()
    }
  }

  private onPageChanged(): void {
    this.highlightedTab = this.selectedTabIndex();
    if (this.currentPage === AppPage.PLAYER) {
      if (this.pageStack.size() === 0) {
        this.pageStack.pushPathByName('player', undefined, !this.reduceMotion);
      }
    } else if (this.pageStack.size() > 0) {
      this.pageStack.pop(!this.reduceMotion);
    }
  }

  @Builder
  private tabBarItem(symbol: Resource, title: string, page: AppPage) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Stack() {
        Column()
          .width(52)
          .height(VisualTheme.CONTROL_HEIGHT)
          .borderRadius(19)
          .backgroundColor(HarmonyTokens.primarySubtle())
          .animation(undefined)
          .opacity(this.isTabHighlighted(page) ? 1 : 0)
          .scale({ x: this.isTabHighlighted(page) ? 1 : 0.82, y: this.isTabHighlighted(page) ? 1 : 0.82 })
          .animation(MotionTheme.state(this.reduceMotion))
          .hitTestBehavior(HitTestMode.None)
        SymbolGlyph(symbol)
          .fontSize(VisualTheme.ICON_TAB)
          .fontColor([this.isTabHighlighted(page) ? HarmonyTokens.primary() : HarmonyTokens.textSecondary()])
          .animation(MotionTheme.content(this.reduceMotion))
      }
      .width(64)
      .height(VisualTheme.CONTROL_HEIGHT)
      .alignContent(Alignment.Center)
    }
    .width(Math.min(76, Math.max(48, (this.availableWidth - 48) / 3)))
    .height(56)
    .padding(0)
    .borderRadius(24)
    .backgroundColor(Color.Transparent)
    .enabled(this.canOpen(page))
    .animation(undefined)
    .opacity(this.canOpen(page) ? 1 : 0.36)
    .animation(MotionTheme.content(this.reduceMotion))
    .animation(undefined)
    .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
    .animation(MotionTheme.press(this.reduceMotion))
    .accessibilityText(title)
    .id(`tab-${page}`)
    .onClick((): void => {
      if (this.canOpen(page)) {
        this.tabsController.changeIndex(page === AppPage.SETTINGS ? 2 : page === AppPage.RECORDINGS ? 1 : 0);
      }
    })
  }

  private isTabHighlighted(page: AppPage): boolean {
    return this.pageForTab(this.highlightedTab) === page;
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
