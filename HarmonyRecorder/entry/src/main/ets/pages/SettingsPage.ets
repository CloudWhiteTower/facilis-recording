import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { common } from '@kit.AbilityKit';
import { ExportService, PcmShareCleanupInfo, PcmShareCleanupResult } from '../services/ExportService';
import { PermissionService } from '../services/PermissionService';
import { TextRole, VisualTheme } from '../utils/VisualTheme';
import { HarmonyPalette, HarmonyTheme, HarmonyTokens, ThemeMode, ThemeStore } from '../utils/HarmonyTheme';
import { MaterialRole, MaterialTheme } from '../utils/MaterialTheme';
import { MotionTheme } from '../utils/MotionTheme';
import { PressFeedback } from '../utils/PressFeedback';
import { ResponsiveLayout } from '../utils/ResponsiveLayout';
import { FileSizeUtils } from '../utils/FileSizeUtils';
import { PrivacyNotice, PrivacySection } from '../utils/PrivacyNotice';
import { AppPage, NavigationStore } from '../utils/NavigationStore';

@Component
export struct SettingsPage {
  @State private isWide: boolean = false;
  @State private isLandscape: boolean = false;
  @State private availableWidth: number = 360;
  @State private availableHeight: number = 640;
  @State private showPrivacy: boolean = false;
  @State private isPrivacyClosing: boolean = false;
  @State private isWorking: boolean = false;
  @State private notice: string = '';
  @StorageLink(NavigationStore.PAGE_KEY) @Watch('onPageChanged') private currentPage: number = AppPage.RECORDER;
  @StorageLink(ThemeStore.MODE_KEY) private themeMode: number = ThemeMode.LIGHT;
  @StorageLink(MotionTheme.REDUCE_KEY) private reduceMotion: boolean = false;
  private disposed: boolean = false;
  private lifecycleGeneration: number = 0;

  aboutToAppear(): void {
    this.disposed = false;
    this.isWorking = false;
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.lifecycleGeneration += 1;
    this.showPrivacy = false;
  }

  build() {
    HdsNavigation() {
      Scroll() {
        Column({ space: 12 }) {
          Text('外观')
            .width('100%')
            .attributeModifier(VisualTheme.text(TextRole.METADATA, true))
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
          .id('settings-appearance')

          Text('隐私与数据')
            .width('100%')
            .attributeModifier(VisualTheme.text(TextRole.METADATA, true))
            .fontColor(HarmonyTokens.textTertiary())
            .padding({ left: 4, top: 12 })

          Column({ space: 4 }) {
            this.settingAction($r('sys.symbol.lock_shield'), '隐私说明', 'settings-privacy', (): void => {
              this.notice = '';
              this.showPrivacy = true;
            })
            this.settingAction($r('sys.symbol.mic'), '麦克风权限', 'settings-microphone', (): void => {
              this.requestMicrophonePermission();
            })
            this.settingAction($r('sys.symbol.trash'), '清理分享副本', 'settings-clear-pcm', (): void => {
              this.confirmClearPcmCopies();
            })
          }
          .width('100%')
          .padding(8)
          .attributeModifier(MaterialTheme.surface(MaterialRole.CONTROL, this.themeMode))
          .borderRadius(28)

          if (this.notice.length > 0) {
            Text(this.notice)
              .width('100%')
              .attributeModifier(VisualTheme.text(TextRole.METADATA))
              .fontColor(HarmonyTokens.textSecondary())
              .padding({ left: 4, right: 4 })
              .id('settings-notice')
          }
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
      .clip(true)
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
    .titleMode(this.isLandscape ? HdsNavigationTitleMode.MINI : HdsNavigationTitleMode.FULL)
    .hideBackButton(true)
    .backgroundColor(HarmonyTokens.pageBackground())
    .onAreaChange((oldValue: Area, newValue: Area): void => {
      const width = Number(newValue.width);
      const height = Number(newValue.height);
      this.isWide = ResponsiveLayout.isWide(width);
      this.isLandscape = ResponsiveLayout.usesSplitLayout(width, height);
      if (Number.isFinite(width) && width > 0) { this.availableWidth = width; }
      if (Number.isFinite(height) && height > 0) { this.availableHeight = height; }
    })
    .bindSheet($$this.showPrivacy, this.privacySheet(), {
      height: this.isWide ? Math.min(680, Math.max(180, this.availableHeight - 80)) : SheetSize.LARGE,
      width: this.isWide ? Math.min(640, this.availableWidth - 48) : '100%',
      preferType: this.isWide ? SheetType.CENTER : SheetType.BOTTOM,
      mode: SheetMode.OVERLAY,
      dragBar: true,
      showClose: true,
      backgroundColor: HarmonyTokens.surface(),
      onDisappear: (): void => {
        this.showPrivacy = false;
        this.isPrivacyClosing = false;
      },
      onWillDismiss: (action: DismissSheetAction): void => {
        this.isPrivacyClosing = true;
        action.dismiss();
      }
    })
  }

  @Builder
  private settingAction(symbol: Resource, title: string, componentId: string, action: () => void) {
    Button() {
      Row({ space: 12 }) {
        SymbolGlyph(symbol)
          .fontSize(VisualTheme.ICON_SECONDARY)
          .fontColor([HarmonyTokens.primary()])
        Text(title)
          .layoutWeight(1)
          .attributeModifier(VisualTheme.text(TextRole.BODY))
          .fontColor(HarmonyTokens.textPrimary())
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(VisualTheme.ICON_SMALL)
          .fontColor([HarmonyTokens.textTertiary()])
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
    }
    .width('100%')
    .height(VisualTheme.ACTION_HEIGHT)
    .backgroundColor(Color.Transparent)
    .borderRadius(20)
    .enabled(!this.isWorking && !this.isPrivacyClosing)
    .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
    .accessibilityText(title)
    .id(componentId)
    .onClick(action)
  }

  @Builder
  private privacySheet() {
    Column({ space: 16 }) {
      Text('隐私与本地数据')
        .width('100%')
        .attributeModifier(VisualTheme.text(TextRole.TITLE, true))
        .fontColor(HarmonyTokens.textPrimary())
        .padding({ right: 36 })
      Scroll() {
        Column({ space: 20 }) {
          ForEach(PrivacyNotice.SECTIONS, (section: PrivacySection): void => {
            Column({ space: 8 }) {
              Text(section.title)
                .width('100%')
                .attributeModifier(VisualTheme.text(TextRole.BODY, true))
                .fontColor(HarmonyTokens.textPrimary())
              Text(section.content)
                .width('100%')
                .attributeModifier(VisualTheme.text(TextRole.BODY))
                .fontColor(HarmonyTokens.textSecondary())
            }
            .width('100%')
          }, (section: PrivacySection): string => section.title)
        }
        .width('100%')
        .padding({ bottom: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 24, bottom: 16 })
    .id('settings-privacy-sheet')
  }

  private onPageChanged(): void {
    if (this.currentPage !== AppPage.SETTINGS && this.showPrivacy) {
      this.isPrivacyClosing = true;
      this.showPrivacy = false;
    }
  }

  private isCurrentAction(generation: number): boolean {
    return !this.disposed && this.lifecycleGeneration === generation;
  }

  private async requestMicrophonePermission(): Promise<void> {
    if (this.isWorking || this.showPrivacy) { return; }
    this.isWorking = true;
    const generation = this.lifecycleGeneration;
    this.notice = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const granted = await PermissionService.requestMicrophonePermissionSettings(context);
      if (this.isCurrentAction(generation)) {
        this.notice = granted ? '麦克风权限已开启' : '麦克风权限未开启，已有录音仍可使用';
      }
    } catch (error) {
      console.error(`Open microphone permission settings failed: ${String(error)}`);
      if (this.isCurrentAction(generation)) {
        this.notice = '请在系统“设置 > 应用和元服务 > Facilis Recording > 权限”中调整麦克风权限。';
      }
    } finally {
      if (this.isCurrentAction(generation)) { this.isWorking = false; }
    }
  }

  private async confirmClearPcmCopies(): Promise<void> {
    if (this.isWorking || this.showPrivacy) { return; }
    this.isWorking = true;
    const generation = this.lifecycleGeneration;
    this.notice = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const info = await ExportService.getPcmShareCleanupInfo(context);
      if (!this.isCurrentAction(generation) || this.currentPage !== AppPage.SETTINGS) { return; }
      if (info.fileCount === 0) {
        this.notice = this.noCleanupNotice(info);
        return;
      }
      let message = `可清理 ${info.fileCount} 份 PCM 分享副本（${FileSizeUtils.format(info.sizeBytes)}）。不会删除资料库、最近删除或已保存到设备的文件。`;
      if (info.protectedFileCount > 0) {
        message += `\n另有 ${info.protectedFileCount} 份处于分享保留期，将保留。`;
      }
      if (info.failedCount > 0) { message += `\n${info.failedCount} 份无法检查，将保留。`; }
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '清理分享副本？',
        message,
        buttons: [
          { text: '取消', color: HarmonyTokens.textSecondary() },
          { text: '清理', color: HarmonyTokens.primary() }
        ]
      });
      if (result.index !== 1 || !this.isCurrentAction(generation)) { return; }
      const cleared = await ExportService.clearPcmShareCopies(context);
      if (this.isCurrentAction(generation)) { this.notice = this.cleanupResultNotice(cleared); }
    } catch (error) {
      const dialogError = error as Error;
      if (dialogError.message !== 'cancel') {
        console.error(`Clean PCM share copies failed: ${String(error)}`);
        if (this.isCurrentAction(generation)) { this.notice = '无法完成清理，未删除的副本已保留，请重试。'; }
      }
    } finally {
      if (this.isCurrentAction(generation)) { this.isWorking = false; }
    }
  }

  private noCleanupNotice(info: PcmShareCleanupInfo): string {
    let message = '暂无可清理的分享副本';
    if (info.protectedFileCount > 0) {
      message += `；${info.protectedFileCount} 份处于分享保留期，请在生成 24 小时后再试`;
    }
    if (info.failedCount > 0) { message += `；${info.failedCount} 份无法检查，已保留`; }
    return message;
  }

  private cleanupResultNotice(result: PcmShareCleanupResult): string {
    let message = `已清理 ${result.removedCount} 份分享副本（${FileSizeUtils.format(result.removedBytes)}），录音已保留`;
    if (result.failedCount > 0) { message += `；${result.failedCount} 份未能清理`; }
    if (result.protectedFileCount > 0) { message += `；${result.protectedFileCount} 份仍在分享保留期内`; }
    return message;
  }

  @Builder
  private appearanceChoice(symbol: Resource, selectedSymbol: Resource, title: string, mode: ThemeMode) {
    Button() {
      Column({ space: 8 }) {
        SymbolGlyph(this.themeMode === mode ? selectedSymbol : symbol)
          .fontSize(VisualTheme.ICON_PRIMARY)
          .fontColor([this.themeMode === mode ? HarmonyTokens.primary() : HarmonyTokens.textSecondary()])
        Text(title)
          .attributeModifier(VisualTheme.text(TextRole.METADATA, this.themeMode === mode))
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
