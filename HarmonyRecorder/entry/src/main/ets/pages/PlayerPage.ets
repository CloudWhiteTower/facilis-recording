import { common } from '@kit.AbilityKit';
import {
  HdsNavDestination,
  HdsNavigationMenuItemOptions,
  HdsNavDestinationTitleMode
} from '@kit.UIDesignKit';
import { RecordingFormat, RecordingInfo } from '../models/RecordingTypes';
import { RecordingRepository } from '../repository/RecordingRepository';
import { ExportService } from '../services/ExportService';
import { PlaybackService } from '../services/PlaybackService';
import { ShareService } from '../services/ShareService';
import { FileSizeUtils } from '../utils/FileSizeUtils';
import { HarmonyPalette, HarmonyTheme, HarmonyTokens, ThemeMode, ThemeStore } from '../utils/HarmonyTheme';
import { MaterialRole, MaterialTheme } from '../utils/MaterialTheme';
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
  @State private isRenaming: boolean = false;
  @State private renameValue: string = '';
  @State private isWorking: boolean = false;
  @State private showActionSheet: boolean = false;
  @StorageLink(ThemeStore.MODE_KEY) private themeMode: number = ThemeMode.LIGHT;
  private recording: RecordingInfo = RecordingInfo.placeholder();
  private readonly playbackService: PlaybackService = new PlaybackService();

  aboutToAppear(): void {
    this.recording = RecordingSelectionStore.getSelected();
    this.displayName = this.recording.displayName;
    this.playbackService.setObserver((isReady: boolean, isPlaying: boolean, positionMs: number,
      durationMs: number, message: string): void => {
      this.isReady = isReady;
      this.isPlaying = isPlaying;
      this.positionMs = positionMs;
      if (durationMs > 0) {
        this.durationMs = durationMs;
      }
      if (message.length > 0) {
        this.status = message;
      } else if (!isReady) {
        this.status = '正在准备';
      } else {
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
    this.playbackService.setObserver(undefined);
    this.playbackService.release();
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Scroll() {
          Column({ space: this.isWide ? 30 : 24 }) {
            Blank().height(this.isWide ? 24 : 12)
            this.recordingOverview()
            Divider().color(HarmonyTokens.divider())
            this.playbackTimeline()
            Blank().height(132)
          }
          .width(ResponsiveLayout.contentWidth(this.isWide))
          .constraintSize({ maxWidth: 920 })
          .padding({
            left: ResponsiveLayout.horizontalPadding(this.isWide),
            right: ResponsiveLayout.horizontalPadding(this.isWide)
          })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)

        this.playerBar()
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
    })
    .bindSheet($$this.showActionSheet, this.actionsSheet(), {
      height: SheetSize.MEDIUM,
      preferType: SheetType.BOTTOM,
      dragBar: true,
      showClose: false,
      backgroundColor: HarmonyTokens.glassSurface(),
      blurStyle: BlurStyle.COMPONENT_THICK,
      onDisappear: (): void => {
        this.isRenaming = false;
      }
    })
  }

  private playerMenu(): HdsNavigationMenuItemOptions[] {
    return [{
      content: {
        icon: $r('sys.symbol.ellipsis_circle'),
        label: '更多录音操作',
        isEnabled: this.recording.filePath.length > 0 && !this.isWorking,
        componentId: 'recording_actions',
        action: (): void => {
          this.showActionSheet = true;
        }
      }
    }];
  }

  @Builder
  private recordingOverview() {
    Column({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(this.isWide ? 180 : 150)
          .height(this.isWide ? 180 : 150)
          .fill(HarmonyTokens.primaryGlow())
          .blur(38)
          .opacity(0.42)
        Column()
          .width(this.isWide ? 116 : 96)
          .height(this.isWide ? 116 : 96)
          .attributeModifier(MaterialTheme.surface(MaterialRole.CONTROL, this.themeMode))
          .borderRadius(this.isWide ? 58 : 48)
        SymbolGlyph($r('sys.symbol.waveform'))
          .fontSize(this.isWide ? 48 : 40)
          .fontColor([HarmonyTokens.primary()])
      }
      .width('100%')
      .height(this.isWide ? 164 : 136)

      Text(this.displayName)
        .fontSize(this.isWide ? 32 : 27)
        .fontWeight(FontWeight.Medium)
        .fontColor(HarmonyTokens.textPrimary())
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row({ space: 10 }) {
        Text(this.recording.config.format === RecordingFormat.WAV ? 'WAV' : 'M4A')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(HarmonyTokens.primary())
        Text(this.qualityTitle())
          .fontSize(14)
          .fontColor(HarmonyTokens.textSecondary())
      }
      Text(`${TimeUtils.formatDateTime(this.recording.createdAt)} · ${FileSizeUtils.format(this.recording.sizeBytes)}`)
        .fontSize(13)
        .fontColor(HarmonyTokens.textTertiary())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private playbackTimeline() {
    Column({ space: 12 }) {
      if (this.status.length > 0) {
        Text(this.status)
          .fontSize(13)
          .fontColor(HarmonyTokens.textSecondary())
          .width('100%')
          .textAlign(TextAlign.Center)
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
        .onChange((value: number): void => {
          this.positionMs = Math.floor(value);
          this.playbackService.seek(this.positionMs);
        })

      Row() {
        Text(TimeUtils.formatDuration(this.positionMs))
          .fontSize(13)
          .fontColor(HarmonyTokens.textSecondary())
        Blank()
        Text(TimeUtils.formatDuration(this.durationMs))
          .fontSize(13)
          .fontColor(HarmonyTokens.textSecondary())
      }
      .width('100%')
    }
    .width(this.contentFocusWidth())
  }

  @Builder
  private playerBar() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        Blank()
      }
      .width(98)
      .height(92)
      .attributeModifier(MaterialTheme.surface(MaterialRole.CONTROL, this.themeMode))
      .borderRadius(46)

      Button() {
        if (this.isPlaying) {
          SymbolGlyph($r('sys.symbol.pause_fill'))
            .fontSize(28)
            .fontColor([HarmonyTokens.onPrimary()])
        } else {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(28)
            .fontColor([HarmonyTokens.onPrimary()])
        }
      }
      .width(72)
      .height(72)
      .backgroundColor(HarmonyTokens.primary())
      .borderRadius(36)
      .enabled(this.isReady)
      .accessibilityText(this.isPlaying ? '暂停播放' : '播放录音')
      .onClick((): void => {
        this.togglePlayback();
      })
    }
    .width(148)
    .height(116)
    .margin({ bottom: this.isWide ? 30 : 20 })
  }

  @Builder
  private actionsSheet() {
    Column({ space: 10 }) {
      Text(this.isRenaming ? '重命名' : this.recording.displayName)
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(HarmonyTokens.textPrimary())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 8, bottom: 8 })

      if (this.isRenaming) {
        TextInput({ text: this.renameValue, placeholder: '录音名称' })
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontColor(HarmonyTokens.textPrimary())
          .placeholderColor(HarmonyTokens.textTertiary())
          .backgroundColor(HarmonyTokens.surfaceSubtle())
          .border({ width: 1, color: HarmonyTokens.primaryBorder() })
          .borderRadius(16)
          .defaultFocus(true)
          .maxLength(80)
          .onChange((value: string): void => {
            this.renameValue = value;
          })
        Row({ space: 10 }) {
          this.sheetIconButton($r('sys.symbol.xmark'), '取消重命名', false, (): void => {
            this.isRenaming = false;
          })
          this.sheetIconButton($r('sys.symbol.checkmark'), '保存名称', true, (): void => {
            this.saveRename();
          })
        }
        .width('100%')
      } else {
        this.actionRow($r('sys.symbol.share'), '分享原始文件', false, (): void => {
          this.showActionSheet = false;
          this.shareOriginal();
        })
        this.actionRow($r('sys.symbol.square_and_pencil'), '重命名', false, (): void => {
          this.renameValue = this.recording.displayName;
          this.isRenaming = true;
        })
        if (this.recording.config.format === RecordingFormat.WAV) {
          this.actionRow($r('sys.symbol.waveform'), '导出 PCM', false, (): void => {
            this.showActionSheet = false;
            this.exportPcmAndShare();
          })
        }
        Divider().color(HarmonyTokens.divider())
        this.actionRow($r('sys.symbol.trash'), '移至最近删除', true, (): void => {
          this.showActionSheet = false;
          this.confirmMoveToTrash();
        })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 10, bottom: 30 })
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private actionRow(symbol: Resource, title: string, danger: boolean, action: () => void) {
    Button() {
      Row({ space: 14 }) {
        SymbolGlyph(symbol)
          .fontSize(21)
          .fontColor([danger ? HarmonyTokens.danger() : HarmonyTokens.primary()])
        Text(title)
          .fontSize(16)
          .fontColor(danger ? HarmonyTokens.danger() : HarmonyTokens.textPrimary())
        Blank()
      }
      .width('100%')
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .backgroundColor(danger ? HarmonyTokens.dangerSubtle() : HarmonyTokens.surfaceSubtle())
    .borderRadius(16)
    .enabled(!this.isWorking)
    .onClick(action)
  }

  @Builder
  private sheetIconButton(symbol: Resource, label: string, primary: boolean, action: () => void) {
    Button() {
      SymbolGlyph(symbol)
        .fontSize(20)
        .fontColor([primary ? HarmonyTokens.onPrimary() : HarmonyTokens.textSecondary()])
    }
    .layoutWeight(1)
    .height(44)
    .backgroundColor(primary ? HarmonyTokens.primary() : HarmonyTokens.surfaceSubtle())
    .borderRadius(18)
    .enabled(!this.isWorking)
    .accessibilityText(label)
    .onClick(action)
  }

  private async preparePlayback(): Promise<void> {
    this.durationMs = this.recording.durationMs;
    try {
      await this.playbackService.load(this.recording);
    } catch (error) {
      this.status = '无法打开录音';
    }
  }

  private async togglePlayback(): Promise<void> {
    try {
      await this.playbackService.toggle();
    } catch (error) {
      this.status = '播放控制失败';
    }
  }

  private async shareOriginal(): Promise<void> {
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

  private async exportPcmAndShare(): Promise<void> {
    this.isWorking = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const exported = ExportService.exportWavAsPcm(context, this.recording);
      await ShareService.shareAudioFile(context, exported.filePath, exported.fileName, 'recording_actions');
      this.status = `已导出 ${FileSizeUtils.format(exported.sizeBytes)} PCM`;
    } catch (error) {
      this.status = '导出 PCM 失败';
    } finally {
      this.isWorking = false;
    }
  }

  private saveRename(): void {
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

  private confirmMoveToTrash(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '移至最近删除？',
      message: '录音会从资料库移走，但可在最近删除中恢复。',
      buttons: [
        { text: '取消', color: HarmonyTokens.textSecondary() },
        { text: '移至最近删除', color: HarmonyTokens.danger() }
      ]
    }).then((result): void => {
      if (result.index === 1) {
        this.moveToTrash();
      }
    }).catch((error: Error): void => {
      this.status = '无法打开确认窗口';
    });
  }

  private moveToTrash(): void {
    this.isWorking = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      RecordingRepository.moveToRecentlyDeleted(context, this.recording);
      NavigationStore.open(AppPage.RECORDINGS);
    } catch (error) {
      this.status = '移至最近删除失败';
    } finally {
      this.isWorking = false;
    }
  }

  private qualityTitle(): string {
    if (this.recording.config.format === RecordingFormat.WAV) {
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
    await this.playbackService.release();
    NavigationStore.open(AppPage.RECORDINGS);
  }
}
