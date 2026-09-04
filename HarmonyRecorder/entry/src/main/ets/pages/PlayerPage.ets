import { common } from '@kit.AbilityKit';
import { RecordingFormat, RecordingInfo } from '../models/RecordingTypes';
import { RecordingRepository } from '../repository/RecordingRepository';
import { ExportService } from '../services/ExportService';
import { PlaybackService } from '../services/PlaybackService';
import { ShareService } from '../services/ShareService';
import { FileSizeUtils } from '../utils/FileSizeUtils';
import { HarmonyPalette, HarmonyTheme, ThemeMode, ThemeStore } from '../utils/HarmonyTheme';
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
    Column({ space: 0 }) {
      this.pageHeader()

      Scroll() {
        Column({ space: this.isWide ? 30 : 24 }) {
          Blank().height(this.isWide ? 24 : 10)
          this.recordingOverview()
          Divider().color(this.palette().divider)
          this.playbackTimeline()
          if (this.isRenaming) {
            Divider().color(this.palette().divider)
            this.renameEditor()
          }
          Blank().height(12)
        }
        .width(ResponsiveLayout.contentWidth(this.isWide))
        .padding({
          left: ResponsiveLayout.horizontalPadding(this.isWide),
          right: ResponsiveLayout.horizontalPadding(this.isWide),
          bottom: 18
        })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      this.playerBar()
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.isWide ? 30 : 18 })
    .backgroundColor(this.palette().pageBackground)
    .onAreaChange((oldValue: Area, newValue: Area): void => {
      this.isWide = ResponsiveLayout.isWide(newValue.width);
    })
  }

  @Builder
  private pageHeader() {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(21)
          .fontColor([this.palette().primary])
      }
        .width(40)
        .height(40)
        .backgroundColor('#00000000')
        .borderRadius(20)
        .accessibilityText('返回资料库')
        .onClick((): void => {
          this.backToList();
        })
      Text('播放')
        .fontSize(this.isWide ? 30 : 26)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().textPrimary)
        .layoutWeight(1)
      Button() {
        SymbolGlyph($r('sys.symbol.ellipsis_circle'))
          .fontSize(23)
          .fontColor([this.palette().primary])
      }
        .id('recording_actions')
        .width(40)
        .height(40)
        .backgroundColor('#00000000')
        .borderRadius(20)
        .enabled(this.recording.filePath.length > 0 && !this.isWorking)
        .accessibilityText('更多录音操作')
        .onClick((): void => {
          this.showActionSheet = true;
        })
        .bindSheet($$this.showActionSheet, this.actionsSheet(), {
          height: SheetSize.MEDIUM,
          preferType: SheetType.BOTTOM,
          dragBar: true,
          title: { title: '录音操作' },
          backgroundColor: this.palette().surface
        })
    }
    .width(ResponsiveLayout.contentWidth(this.isWide))
    .padding({
      left: ResponsiveLayout.horizontalPadding(this.isWide),
      right: ResponsiveLayout.horizontalPadding(this.isWide)
    })
  }

  @Builder
  private recordingOverview() {
    Column({ space: 10 }) {
      Text(this.displayName)
        .fontSize(this.isWide ? 32 : 27)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette().textPrimary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row({ space: 10 }) {
        Text(this.recording.config.format === RecordingFormat.WAV ? 'WAV' : 'M4A')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().primary)
        Text(this.qualityTitle())
          .fontSize(14)
          .fontColor(this.palette().textSecondary)
      }
      Text(`${TimeUtils.formatDateTime(this.recording.createdAt)} · ${FileSizeUtils.format(this.recording.sizeBytes)}`)
        .fontSize(13)
        .fontColor(this.palette().textTertiary)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private playbackTimeline() {
    Column({ space: 12 }) {
      if (this.status.length > 0) {
        Text(this.status)
          .fontSize(13)
          .fontColor(this.palette().textSecondary)
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
        .blockColor(this.palette().primary)
        .trackColor(this.palette().divider)
        .selectedColor(this.palette().primary)
        .onChange((value: number): void => {
          this.positionMs = Math.floor(value);
          this.playbackService.seek(this.positionMs);
        })

      Row() {
        Text(TimeUtils.formatDuration(this.positionMs))
          .fontSize(13)
          .fontColor(this.palette().textSecondary)
        Blank()
        Text(TimeUtils.formatDuration(this.durationMs))
          .fontSize(13)
          .fontColor(this.palette().textSecondary)
      }
      .width('100%')
    }
    .width(this.contentFocusWidth())
  }

  @Builder
  private renameEditor() {
    Column({ space: 12 }) {
      Text('重命名')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette().textPrimary)
      TextInput({ text: this.renameValue, placeholder: '录音名称' })
        .width('100%')
        .height(46)
        .fontSize(16)
        .backgroundColor(this.palette().surfaceSubtle)
        .border({ width: 1, color: this.palette().primaryBorder })
        .borderRadius(12)
        .onChange((value: string): void => {
          this.renameValue = value;
        })
      Row({ space: 10 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([this.palette().textSecondary])
        }
          .layoutWeight(1)
          .height(40)
          .backgroundColor(this.palette().surfaceSubtle)
          .borderRadius(20)
          .accessibilityText('取消重命名')
          .onClick((): void => {
            this.isRenaming = false;
          })
        Button() {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(20)
            .fontColor([this.palette().onPrimary])
        }
          .layoutWeight(1)
          .height(40)
          .backgroundColor(this.palette().primary)
          .borderRadius(20)
          .enabled(!this.isWorking)
          .accessibilityText('保存名称')
          .onClick((): void => {
            this.saveRename();
          })
      }
      .width('100%')
    }
    .width(this.contentFocusWidth())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private playerBar() {
    Column() {
      Button() {
        if (this.isPlaying) {
          SymbolGlyph($r('sys.symbol.pause_fill'))
            .fontSize(28)
            .fontColor([this.palette().onPrimary])
        } else {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(28)
            .fontColor([this.palette().onPrimary])
        }
      }
      .width(72)
      .height(72)
      .backgroundColor(this.palette().primary)
      .borderRadius(36)
      .enabled(this.isReady)
      .accessibilityText(this.isPlaying ? '暂停播放' : '播放录音')
      .onClick((): void => {
        this.togglePlayback();
      })
    }
    .width('100%')
    .padding({ top: 16, bottom: this.isWide ? 26 : 18 })
    .backgroundColor(this.palette().surface)
    .border({ width: { top: 1 }, color: this.palette().divider })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private actionsSheet() {
    Column({ space: 6 }) {
      Button('分享原始文件')
        .width('100%')
        .height(52)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette().textPrimary)
        .backgroundColor('#00000000')
        .borderRadius(14)
        .onClick((): void => {
          this.showActionSheet = false;
          this.shareOriginal();
        })
      Button('重命名')
        .width('100%')
        .height(52)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette().textPrimary)
        .backgroundColor('#00000000')
        .borderRadius(14)
        .onClick((): void => {
          this.renameValue = this.recording.displayName;
          this.isRenaming = true;
          this.showActionSheet = false;
        })

      if (this.recording.config.format === RecordingFormat.WAV) {
        Button('导出 PCM')
          .width('100%')
          .height(52)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .backgroundColor('#00000000')
          .borderRadius(14)
          .onClick((): void => {
            this.showActionSheet = false;
            this.exportPcmAndShare();
          })
      }

      Divider().color(this.palette().divider)
      Button('移至最近删除')
        .width('100%')
        .height(52)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette().danger)
        .backgroundColor('#00000000')
        .borderRadius(14)
        .enabled(!this.isWorking)
        .onClick((): void => {
          this.showActionSheet = false;
          this.confirmMoveToTrash();
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 10, bottom: 30 })
    .backgroundColor(this.palette().surface)
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
        { text: '取消', color: this.palette().textSecondary },
        { text: '移至最近删除', color: this.palette().danger }
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
    return this.isWide ? 560 : '100%';
  }

  private palette(): HarmonyPalette {
    return HarmonyTheme.palette(this.themeMode);
  }

  private async backToList(): Promise<void> {
    await this.playbackService.release();
    NavigationStore.open(AppPage.RECORDINGS);
  }
}
