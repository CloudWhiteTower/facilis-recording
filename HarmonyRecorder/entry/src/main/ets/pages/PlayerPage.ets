import { common } from '@kit.AbilityKit';
import { TextRole, VisualTheme } from '../utils/VisualTheme';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  HdsNavDestination,
  HdsNavigationMenuItemOptions,
  HdsNavDestinationTitleMode
} from '@kit.UIDesignKit';
import { RecordingFormat, RecordingInfo } from '../models/RecordingTypes';
import { AudioConversionPanel } from '../components/AudioConversionPanel';
import { RecordingRepository } from '../repository/RecordingRepository';
import { ExportService } from '../services/ExportService';
import { PlaybackService } from '../services/PlaybackService';
import { ShareService } from '../services/ShareService';
import { FileSizeUtils } from '../utils/FileSizeUtils';
import { HarmonyPalette, HarmonyTheme, HarmonyTokens, ThemeMode, ThemeStore } from '../utils/HarmonyTheme';
import { MaterialRole, MaterialTheme } from '../utils/MaterialTheme';
import { MotionTheme } from '../utils/MotionTheme';
import { PressFeedback } from '../utils/PressFeedback';
import { AppPage, NavigationStore, RecordingSelectionStore } from '../utils/NavigationStore';
import { ResponsiveLayout } from '../utils/ResponsiveLayout';
import { TimeUtils } from '../utils/TimeUtils';

@Component
export struct PlayerPage {
  @State private isReady: boolean = false;
  @State private isPlaying: boolean = false;
  @State private positionMs: number = 0;
  @State private durationMs: number = 0;
  @State private status: string = '';
  @State private displayName: string = '';
  @State private isWide: boolean = false;
  @State private isSplitLayout: boolean = false;
  @State private isCompactLandscape: boolean = false;
  @State private availableWidth: number = 360;
  @State private availableHeight: number = 640;
  @State private isRenaming: boolean = false;
  @State private renameValue: string = '';
  @State private isWorking: boolean = false;
  @State private isConfirming: boolean = false;
  @State private isPreparing: boolean = false;
  @State private showActionSheet: boolean = false;
  @State private showingConversion: boolean = false;
  @StorageLink(ThemeStore.MODE_KEY) private themeMode: number = ThemeMode.LIGHT;
  @StorageLink(MotionTheme.REDUCE_KEY) private reduceMotion: boolean = false;
  @State private recording: RecordingInfo = RecordingInfo.placeholder();
  private readonly playbackService: PlaybackService = new PlaybackService();
  private isScrubbing: boolean = false;
  private seekTargetMs: number = 0;
  private seekGuardUntilMs: number = 0;
  private pendingTrashConfirmation: boolean = false;

  aboutToAppear(): void {
    this.recording = RecordingSelectionStore.getSelected();
    this.displayName = this.recording.displayName;
    this.playbackService.setObserver((isReady: boolean, isPlaying: boolean, positionMs: number,
      durationMs: number, message: string): void => {
      this.isReady = isReady;
      const isNewMessage = message.length > 0 && message !== this.status;
      if (!isReady || isNewMessage) {
        this.isScrubbing = false;
        this.seekGuardUntilMs = 0;
      }
      if (this.isPlaying !== isPlaying) {
        this.getUIContext().animateTo(MotionTheme.state(), (): void => {
          this.isPlaying = isPlaying;
        });
      }
      // Do not let player ticks pull the thumb away from the user's drag preview.
      // PlaybackService suppresses stale native ticks until seekDone confirms
      // the latest requested position, including slow seeks and repeated drags.
      if (!this.isScrubbing || !isReady || isNewMessage) {
        this.positionMs = positionMs;
      }
      if (durationMs > 0) {
        this.durationMs = durationMs;
      }
      if (message.length > 0) {
        this.status = message;
      } else if (!isReady && (this.isPreparing || this.status.length === 0)) {
        this.status = '正在准备';
      } else if (this.isPreparing) {
        this.status = '';
      }
    });
    if (this.recording.filePath.length === 0) {
      this.status = '未选择录音';
    } else {
      this.preparePlayback();
    }
  }

  aboutToDisappear(): void {
    this.isScrubbing = false;
    this.seekGuardUntilMs = 0;
    this.playbackService.setObserver(undefined);
    this.playbackService.release();
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Scroll() {
          Column() {
            if (this.isSplitLayout) {
              Row({ space: this.isCompactLandscape ? 24 : 40 }) {
                Column() {
                  this.recordingOverview()
                }
                .layoutWeight(1)
                Column({ space: this.isCompactLandscape ? 16 : 28 }) {
                  this.playbackTimeline()
                  this.playerBar()
                }
                .layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ top: this.isCompactLandscape ? 12 : 36, bottom: this.isCompactLandscape ? 12 : 36 })
            } else {
              Column({ space: 24 }) {
                Blank().height(12)
                this.recordingOverview()
                Divider().color(HarmonyTokens.divider())
                this.playbackTimeline()
                Blank().height(156)
              }
              .width('100%')
            }
          }
          .width(ResponsiveLayout.contentWidth(this.isWide))
          .constraintSize({ maxWidth: this.isSplitLayout ? 1120 : 720 })
          .padding({
            left: ResponsiveLayout.horizontalPadding(this.isWide),
            right: ResponsiveLayout.horizontalPadding(this.isWide)
          })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)

        if (!this.isSplitLayout) {
          this.playerBar()
        }
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .titleBar({
      content: {
        title: { mainTitle: '播放' },
        backIcon: {
          icon: $r('sys.symbol.chevron_left'),
          label: '返回资料库',
          action: (): void => {
            this.backToList();
          }
        },
        menu: {
          value: this.playerMenu(),
          maxCount: 1
        }
      },
      style: {
        scrollEffectOpts: { enableScrollEffect: false },
        systemMaterialEffect: MaterialTheme.resolve(MaterialRole.NAVIGATION)
      },
      enableComponentSafeArea: true
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .onBackPressed((): boolean => {
      this.backToList();
      return true;
    })
    .onWillDisappear((): void => {
      NavigationStore.open(AppPage.RECORDINGS);
    })
    .hideBackButton(false)
    .backgroundColor(HarmonyTokens.pageBackground())
    .onAreaChange((oldValue: Area, newValue: Area): void => {
      this.isWide = ResponsiveLayout.isWide(newValue.width);
      const width = Number(newValue.width);
      const height = Number(newValue.height);
      if (Number.isFinite(width) && width > 0 && Math.abs(width - this.availableWidth) >= 1) {
        this.availableWidth = width;
      }
      if (Number.isFinite(height) && height > 0 && Math.abs(height - this.availableHeight) >= 1) {
        this.availableHeight = height;
      }
      this.isSplitLayout = ResponsiveLayout.usesSplitLayout(this.availableWidth, this.availableHeight);
      this.isCompactLandscape = this.isSplitLayout && this.availableHeight < 520;
    })
    .bindSheet($$this.showActionSheet, this.actionsSheet(), {
      height: this.isWide ? Math.min(560, Math.max(180, this.availableHeight - 80)) : SheetSize.LARGE,
      width: this.isWide ? Math.min(560, this.availableWidth - 48) : '100%',
      preferType: this.isWide ? SheetType.CENTER : SheetType.BOTTOM,
      dragBar: true,
      showClose: false,
      backgroundColor: HarmonyTokens.glassSurface(),
      blurStyle: BlurStyle.COMPONENT_THICK,
      onDisappear: (): void => {
        this.onActionsSheetDismissed();
      }
    })
  }

  private playerMenu(): HdsNavigationMenuItemOptions[] {
    return [{
      content: {
        icon: $r('sys.symbol.ellipsis_circle'),
        label: '更多录音操作',
        isEnabled: this.recording.filePath.length > 0 && !this.isWorking && !this.isConfirming && !this.isPreparing,
        componentId: 'recording_actions',
        action: (): void => {
          if (!this.isWorking && !this.isConfirming && !this.isPreparing) {
            this.showActionSheet = true;
          }
        }
      }
    }];
  }

  @Builder
  private recordingOverview() {
    Column({ space: this.isCompactLandscape ? 8 : 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(this.isCompactLandscape ? 100 : this.isSplitLayout ? 180 : 150)
          .height(this.isCompactLandscape ? 100 : this.isSplitLayout ? 180 : 150)
          .fill(HarmonyTokens.primaryGlow())
          .blur(38)
          .opacity(0.42)
        Column()
          .width(this.isCompactLandscape ? 72 : this.isSplitLayout ? 116 : 96)
          .height(this.isCompactLandscape ? 72 : this.isSplitLayout ? 116 : 96)
          .attributeModifier(MaterialTheme.surface(MaterialRole.CONTROL, this.themeMode))
          .borderRadius(this.isCompactLandscape ? 36 : this.isSplitLayout ? 58 : 48)
        SymbolGlyph($r('sys.symbol.waveform'))
          .fontSize(this.isCompactLandscape ? 32 : this.isSplitLayout ? 48 : 40)
          .fontColor([HarmonyTokens.primary()])
      }
      .width('100%')
      .height(this.isCompactLandscape ? 88 : this.isSplitLayout ? 164 : 136)

      Text(this.displayName)
        .attributeModifier(VisualTheme.text(this.isCompactLandscape ? TextRole.HERO_COMPACT :
          this.isSplitLayout ? TextRole.HERO_WIDE : TextRole.HERO))
        .fontColor(HarmonyTokens.textPrimary())
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row({ space: 10 }) {
        Text(this.recording.config.formatLabel)
          .attributeModifier(VisualTheme.text(TextRole.METADATA, true))
          .fontColor(HarmonyTokens.primary())
        Text(this.qualityTitle())
          .attributeModifier(VisualTheme.text(TextRole.METADATA))
          .fontColor(HarmonyTokens.textSecondary())
      }
      Text(`${TimeUtils.formatDateTime(this.recording.createdAt)} · ${FileSizeUtils.format(this.recording.sizeBytes)}`)
        .attributeModifier(VisualTheme.text(TextRole.METADATA))
        .fontColor(HarmonyTokens.textTertiary())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .id('player-overview')
  }

  @Builder
  private playbackTimeline() {
    Column({ space: 12 }) {
      if (this.status.length > 0) {
        Text(this.status)
          .attributeModifier(VisualTheme.text(TextRole.METADATA))
          .fontColor(HarmonyTokens.textSecondary())
          .width('100%')
          .textAlign(TextAlign.Center)
          .transition(MotionTheme.appear(this.reduceMotion))
      }
      if (!this.isReady && !this.isPreparing && this.recording.filePath.length > 0) {
        Button('重新打开录音')
          .height(VisualTheme.CONTROL_HEIGHT)
          .fontSize(VisualTheme.BODY_SIZE)
          .enabled(!this.isWorking && !this.isConfirming)
          .onClick((): void => {
            this.preparePlayback();
          })
      }

      Slider({
        value: this.positionMs,
        min: 0,
        max: Math.max(this.durationMs, 1),
        step: 100,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .blockColor(HarmonyTokens.primary())
        .trackColor(HarmonyTokens.divider())
        .selectedColor(HarmonyTokens.primary())
        .enabled(this.isReady && !this.isWorking && !this.isConfirming)
        .onChange((value: number, mode: SliderChangeMode): void => {
          this.onSeekChange(value, mode);
        })

      Row() {
        Text(TimeUtils.formatDuration(this.positionMs))
          .attributeModifier(VisualTheme.text(TextRole.METADATA, false, true))
          .fontColor(HarmonyTokens.textSecondary())
        Blank()
        Text(TimeUtils.formatDuration(this.durationMs))
          .attributeModifier(VisualTheme.text(TextRole.METADATA, false, true))
          .fontColor(HarmonyTokens.textSecondary())
      }
      .width('100%')
    }
    .width(this.contentFocusWidth())
    .id('player-timeline')
  }

  @Builder
  private playerBar() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        Blank()
      }
      .width(VisualTheme.PRIMARY_PLATE)
      .height(VisualTheme.PRIMARY_PLATE)
      .attributeModifier(MaterialTheme.surface(MaterialRole.CONTROL, this.themeMode))
      .borderRadius(VisualTheme.PRIMARY_PLATE / 2)

      Button() {
        Stack({ alignContent: Alignment.Center }) {
          if (this.isPlaying) {
            SymbolGlyph($r('sys.symbol.pause_fill'))
              .fontSize(VisualTheme.ICON_PRIMARY)
              .fontColor([HarmonyTokens.onPrimary()])
              .transition(MotionTheme.appear(this.reduceMotion))
          } else {
            SymbolGlyph($r('sys.symbol.play_fill'))
              .fontSize(VisualTheme.ICON_PRIMARY)
              .fontColor([HarmonyTokens.onPrimary()])
              .transition(MotionTheme.appear(this.reduceMotion))
          }
        }
        .width(32)
        .height(32)
      }
      .width(VisualTheme.PRIMARY_BUTTON)
      .height(VisualTheme.PRIMARY_BUTTON)
      .backgroundColor(HarmonyTokens.primary())
      .borderRadius(VisualTheme.PRIMARY_BUTTON / 2)
      .enabled(this.isReady && !this.isWorking && !this.isConfirming)
      .animation(undefined)
      .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion, true))
      .animation(MotionTheme.press(this.reduceMotion))
      .accessibilityText(this.isPlaying ? '暂停播放' : '播放录音')
      .id('player-toggle')
      .onClick((): void => {
        this.togglePlayback();
      })
    }
    .width(148)
    .height(this.isCompactLandscape ? VisualTheme.COMPACT_CONTROL_SLOT : VisualTheme.CONTROL_SLOT)
    .margin({ bottom: this.isSplitLayout ? 0 : 20 })
    .id('player-controls')
  }

  @Builder
  private actionsSheet() {
    Scroll() {
      Column({ space: 10 }) {
        if (this.showingConversion) {
          AudioConversionPanel({
            recording: this.recording,
            onRunning: (running: boolean): void => { this.isWorking = running; },
            onBack: (): void => { this.showingConversion = false; },
            onComplete: (converted: RecordingInfo): void => {
              this.status = `已添加 ${converted.fileName}，原件已保留`;
              this.showActionSheet = false;
            }
          })
        } else {
        Text(this.isRenaming ? '重命名' : this.recording.displayName)
          .width('100%')
          .attributeModifier(VisualTheme.text(TextRole.TITLE, true))
          .fontColor(HarmonyTokens.textPrimary())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 8, bottom: 8 })

        if (this.isRenaming) {
          TextInput({ text: this.renameValue, placeholder: '录音名称' })
            .width('100%')
            .height(VisualTheme.INPUT_HEIGHT)
            .fontSize(VisualTheme.BODY_SIZE)
            .fontColor(HarmonyTokens.textPrimary())
            .placeholderColor(HarmonyTokens.textTertiary())
            .backgroundColor(HarmonyTokens.surfaceSubtle())
            .border({ width: 1, color: HarmonyTokens.primaryBorder() })
            .borderRadius(16)
            .defaultFocus(true)
            .maxLength(80)
            .transition(MotionTheme.appear(this.reduceMotion))
            .onChange((value: string): void => {
              this.renameValue = value;
            })
          Row({ space: 10 }) {
            this.sheetIconButton($r('sys.symbol.xmark'), '取消重命名', false, (): void => {
              this.getUIContext().animateTo(MotionTheme.content(), (): void => {
                this.isRenaming = false;
              });
            })
            this.sheetIconButton($r('sys.symbol.checkmark'), '保存名称', true, (): void => {
              this.saveRename();
            })
          }
          .width('100%')
          .transition(MotionTheme.appear(this.reduceMotion))
        } else {
          this.actionRow($r('sys.symbol.arrow_down'), '保存到文件', false, (): void => {
            this.saveToDevice();
          })
          this.actionRow($r('sys.symbol.waveform'), '转换格式', false, (): void => {
            this.openConversion();
          })
          this.actionRow($r('sys.symbol.share'), '分享原始文件', false, (): void => {
            this.showActionSheet = false;
            this.shareOriginal();
          })
          this.actionRow($r('sys.symbol.square_and_pencil'), '重命名', false, (): void => {
            this.renameValue = this.recording.displayName;
            this.getUIContext().animateTo(MotionTheme.content(), (): void => {
              this.isRenaming = true;
            });
          })
          if (this.recording.config.format === RecordingFormat.WAV) {
            this.actionRow($r('sys.symbol.waveform'), '导出原始 PCM（无文件头）', false, (): void => {
              this.showActionSheet = false;
              this.exportPcmAndShare();
            })
          }
          Divider().color(HarmonyTokens.divider())
          this.actionRow($r('sys.symbol.trash'), '移至最近删除', true, (): void => {
            this.requestMoveToTrash();
          })
        }
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 10, bottom: 30 })
      .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Auto)
  }

  @Builder
  private actionRow(symbol: Resource, title: string, danger: boolean, action: () => void) {
    Button() {
      Row({ space: 14 }) {
        SymbolGlyph(symbol)
          .fontSize(VisualTheme.ICON_TOOL)
          .fontColor([danger ? HarmonyTokens.danger() : HarmonyTokens.primary()])
        Text(title)
          .attributeModifier(VisualTheme.text(TextRole.BODY))
          .fontColor(danger ? HarmonyTokens.danger() : HarmonyTokens.textPrimary())
        Blank()
      }
      .width('100%')
    }
    .width('100%')
    .height(VisualTheme.ACTION_HEIGHT)
    .padding({ left: 16, right: 16 })
    .backgroundColor(danger ? HarmonyTokens.dangerSubtle() : HarmonyTokens.surfaceSubtle())
    .borderRadius(16)
    .enabled(!this.isWorking && !this.isConfirming)
    .animation(undefined)
    .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
    .animation(MotionTheme.press(this.reduceMotion))
    .transition(MotionTheme.appear(this.reduceMotion))
    .onClick(action)
  }

  @Builder
  private sheetIconButton(symbol: Resource, label: string, primary: boolean, action: () => void) {
    Button() {
      SymbolGlyph(symbol)
        .fontSize(VisualTheme.ICON_TOOL)
        .fontColor([primary ? HarmonyTokens.onPrimary() : HarmonyTokens.textSecondary()])
    }
    .layoutWeight(1)
    .height(VisualTheme.CONTROL_HEIGHT)
    .backgroundColor(primary ? HarmonyTokens.primary() : HarmonyTokens.surfaceSubtle())
    .borderRadius(18)
    .enabled(!this.isWorking && !this.isConfirming)
    .animation(undefined)
    .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion, primary))
    .animation(MotionTheme.press(this.reduceMotion))
    .accessibilityText(label)
    .onClick(action)
  }

  private onSeekChange(value: number, mode: SliderChangeMode): void {
    if (!this.isReady || this.isWorking || this.isConfirming || !Number.isFinite(value)) {
      return;
    }
    this.positionMs = Math.max(0, Math.min(Math.floor(value), this.durationMs));
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.isScrubbing = true;
      return;
    }
    if (mode === SliderChangeMode.Click || (mode === SliderChangeMode.End && this.isScrubbing)) {
      this.isScrubbing = false;
      this.status = '';
      this.seekTargetMs = this.positionMs;
      this.seekGuardUntilMs = 0;
      // Seeking stays outside animation closures and happens once per completed gesture.
      this.playbackService.seek(this.positionMs);
    }
  }

  private async preparePlayback(): Promise<void> {
    this.isPreparing = true;
    this.durationMs = this.recording.durationMs;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const inspected = await this.playbackService.load(this.recording, context);
      if (inspected !== undefined) {
        this.recording = inspected;
        this.displayName = inspected.displayName;
        RecordingSelectionStore.select(inspected);
      }
    } catch (error) {
      this.status = (error as Error).message || '无法打开录音';
    } finally {
      this.isPreparing = false;
    }
  }

  private async togglePlayback(): Promise<void> {
    if (this.isWorking || this.isConfirming) {
      return;
    }
    this.status = '';
    try {
      await this.playbackService.toggle();
    } catch (error) {
      this.status = (error as Error).message || '播放控制失败';
    }
  }

  private async shareOriginal(): Promise<void> {
    if (this.isWorking || this.isConfirming) {
      return;
    }
    this.isWorking = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await ShareService.shareRecording(context, this.recording, 'recording_actions');
      this.status = '';
    } catch (error) {
      this.status = '无法打开分享面板';
    } finally {
      this.isWorking = false;
    }
  }

  private async openConversion(): Promise<void> {
    if (this.isWorking || this.isConfirming) { return; }
    try {
      if (this.isPlaying) { await this.playbackService.toggle(); }
      this.showingConversion = true;
    } catch (error) {
      this.status = (error as Error).message || '无法暂停播放';
    }
  }

  private async saveToDevice(): Promise<void> {
    if (this.isWorking || this.isConfirming) { return; }
    this.isWorking = true;
    this.showActionSheet = false;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const destination = await ExportService.saveToDevice(context, this.recording);
      this.status = destination === undefined ? '' : '已保存到所选位置，原始录音已保留';
    } catch (error) {
      this.status = (error as Error).message || '保存到文件失败';
    } finally { this.isWorking = false; }
  }

  private async exportPcmAndShare(): Promise<void> {
    if (this.isWorking || this.isConfirming) {
      return;
    }
    this.isWorking = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const exported = await ExportService.exportWavAsPcm(context, this.recording);
      await ShareService.shareAudioFile(context, exported.filePath, exported.fileName, 'recording_actions');
      this.status = `已导出 ${FileSizeUtils.format(exported.sizeBytes)} PCM`;
    } catch (error) {
      this.status = (error as Error).message || '导出 PCM 失败';
    } finally {
      this.isWorking = false;
    }
  }

  private saveRename(): void {
    if (this.isWorking || this.isConfirming) {
      return;
    }
    this.isWorking = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.recording = RecordingRepository.rename(context, this.recording, this.renameValue);
      RecordingSelectionStore.select(this.recording);
      this.displayName = this.recording.displayName;
      this.isRenaming = false;
      this.showActionSheet = false;
      this.status = '';
    } catch (error) {
      this.status = '重命名失败';
    } finally {
      this.isWorking = false;
    }
  }

  private requestMoveToTrash(): void {
    if (this.isWorking || this.isConfirming || this.isPreparing) {
      return;
    }
    this.pendingTrashConfirmation = true;
    this.isConfirming = true;
    this.showActionSheet = false;
  }

  private onActionsSheetDismissed(): void {
    this.isRenaming = false;
    this.showingConversion = false;
    if (this.pendingTrashConfirmation) {
      this.pendingTrashConfirmation = false;
      this.isConfirming = false;
      this.confirmMoveToTrash();
    }
  }

  private async confirmMoveToTrash(): Promise<void> {
    if (this.isWorking || this.isConfirming) {
      return;
    }
    this.isConfirming = true;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '移至最近删除？',
        message: '录音会从资料库移走，但可在最近删除中恢复。',
        buttons: [
          { text: '取消', color: HarmonyTokens.textSecondary() },
          { text: '移至最近删除', color: HarmonyTokens.danger() }
        ]
      });
      this.isConfirming = false;
      if (result.index === 1) {
        await this.moveToTrash();
      }
    } catch (error) {
      // The native prompt API rejects with Error('cancel') for Back and mask dismissal.
      const dialogError = error as BusinessError;
      if (dialogError.message !== 'cancel') {
        console.error(`Player confirmation failed: code=${dialogError.code}, message=${dialogError.message}`);
        this.status = '无法打开确认窗口';
      }
    } finally {
      this.isConfirming = false;
    }
  }

  private async moveToTrash(): Promise<void> {
    if (this.isWorking || this.isConfirming || this.isPreparing) {
      return;
    }
    this.isWorking = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.isScrubbing = false;
      this.seekGuardUntilMs = 0;
      // Finish closing the AVPlayer and its source handle before moving the file.
      await this.playbackService.release();
      RecordingRepository.moveToRecentlyDeleted(context, this.recording);
      NavigationStore.open(AppPage.RECORDINGS);
    } catch (error) {
      // Reopen the original when rollback made it available, allowing playback and retry after a failure.
      await this.preparePlayback();
      this.status = this.isReady ? '移至最近删除失败，可重试' : '移至最近删除失败，录音暂时无法打开';
    } finally {
      this.isWorking = false;
    }
  }

  private qualityTitle(): string {
    if (this.recording.config.format !== RecordingFormat.M4A) {
      return `${this.recording.config.sampleRateLabel} · ${this.recording.config.bitDepth} bit · 单声道`;
    }
    return `AAC · ${this.recording.config.bitrate / 1000} kbps · ${this.recording.config.sampleRateLabel} · 单声道`;
  }

  private contentFocusWidth(): Length {
    return '100%';
  }

  private palette(): HarmonyPalette {
    return HarmonyTheme.palette(this.themeMode);
  }

  private async backToList(): Promise<void> {
    if (this.isWorking || this.isConfirming) {
      return;
    }
    this.isWorking = true;
    try {
      await this.playbackService.release();
      NavigationStore.open(AppPage.RECORDINGS);
    } finally {
      this.isWorking = false;
    }
  }
}
