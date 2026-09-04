import { common } from '@kit.AbilityKit';
import { LiveWaveform } from '../components/LiveWaveform';
import { RecordingConfig, RecordingFormat, RecordingSnapshot, RecordingState } from '../models/RecordingTypes';
import { PermissionService } from '../services/PermissionService';
import { RecordingService } from '../services/RecordingService';
import { FileSizeUtils } from '../utils/FileSizeUtils';
import { NavigationStore } from '../utils/NavigationStore';
import { ResponsiveLayout } from '../utils/ResponsiveLayout';
import { HarmonyPalette, HarmonyTheme, ThemeMode, ThemeStore } from '../utils/HarmonyTheme';
import { TimeUtils } from '../utils/TimeUtils';

@Component
struct RecordingQualitySheet {
  @Link selectedFormat: RecordingFormat;
  @Link selectedSampleRate: number;
  @Link selectedWavBitDepth: number;
  @Link selectedAacBitrate: number;
  @Prop themeMode: number = ThemeMode.LIGHT;

  build() {
    Column({ space: 0 }) {
      Text('录音质量')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().textPrimary)
        .padding({ left: 8, bottom: 14 })
      this.formatSetting()
      Divider().color(this.palette().divider).margin({ left: 8, right: 8 })
      this.sampleRateSetting()
      Divider().color(this.palette().divider).margin({ left: 8, right: 8 })
      this.encodingSetting()
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 10, bottom: 30 })
    .backgroundColor(this.palette().surface)
  }

  @Builder
  private formatSetting() {
    Column({ space: 3 }) {
      Text('格式')
        .width('100%')
        .fontSize(12)
        .fontColor(this.palette().textSecondary)
        .padding({ left: 10 })
      Select([
        { value: 'WAV' },
        { value: 'M4A' }
      ])
        .selected(this.selectedFormat === RecordingFormat.WAV ? 0 : 1)
        .value(this.selectedFormat === RecordingFormat.WAV ? 'WAV' : 'M4A')
        .width('100%')
        .height(42)
        .font({ size: 17, weight: FontWeight.Medium })
        .fontColor(this.palette().textPrimary)
        .backgroundColor('#00000000')
        .selectedOptionBgColor(this.palette().primarySubtle)
        .selectedOptionFontColor(this.palette().primary)
        .optionBgColor(this.palette().surface)
        .optionFontColor(this.palette().textPrimary)
        .menuBackgroundColor(this.palette().surface)
        .showDefaultSelectedIcon(true)
        .onSelect((index: number): void => {
          this.selectedFormat = index === 0 ? RecordingFormat.WAV : RecordingFormat.M4A;
        })
    }
    .width('100%')
    .height(72)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private sampleRateSetting() {
    Column({ space: 3 }) {
      Text('采样率')
        .width('100%')
        .fontSize(12)
        .fontColor(this.palette().textSecondary)
        .padding({ left: 10 })
      Select([
        { value: '44.1 kHz' },
        { value: '48 kHz' }
      ])
        .selected(this.selectedSampleRate === 44100 ? 0 : 1)
        .value(this.selectedSampleRate === 44100 ? '44.1 kHz' : '48 kHz')
        .width('100%')
        .height(42)
        .font({ size: 17, weight: FontWeight.Medium })
        .fontColor(this.palette().textPrimary)
        .backgroundColor('#00000000')
        .selectedOptionBgColor(this.palette().primarySubtle)
        .selectedOptionFontColor(this.palette().primary)
        .optionBgColor(this.palette().surface)
        .optionFontColor(this.palette().textPrimary)
        .menuBackgroundColor(this.palette().surface)
        .showDefaultSelectedIcon(true)
        .onSelect((index: number): void => {
          this.selectedSampleRate = index === 0 ? 44100 : 48000;
        })
    }
    .width('100%')
    .height(72)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private encodingSetting() {
    Column({ space: 3 }) {
      Text(this.selectedFormat === RecordingFormat.WAV ? '位深' : '码率')
        .width('100%')
        .fontSize(12)
        .fontColor(this.palette().textSecondary)
        .padding({ left: 10 })
      if (this.selectedFormat === RecordingFormat.WAV) {
        Select([
          { value: '16 bit' },
          { value: '24 bit' }
        ])
          .selected(this.selectedWavBitDepth === 16 ? 0 : 1)
          .value(`${this.selectedWavBitDepth} bit`)
          .width('100%')
          .height(42)
          .font({ size: 17, weight: FontWeight.Medium })
          .fontColor(this.palette().textPrimary)
          .backgroundColor('#00000000')
          .selectedOptionBgColor(this.palette().primarySubtle)
          .selectedOptionFontColor(this.palette().primary)
          .optionBgColor(this.palette().surface)
          .optionFontColor(this.palette().textPrimary)
          .menuBackgroundColor(this.palette().surface)
          .showDefaultSelectedIcon(true)
          .onSelect((index: number): void => {
            this.selectedWavBitDepth = index === 0 ? 16 : 24;
          })
      } else {
        Select([
          { value: '128 kbps' },
          { value: '256 kbps' }
        ])
          .selected(this.selectedAacBitrate === 128000 ? 0 : 1)
          .value(`${this.selectedAacBitrate / 1000} kbps`)
          .width('100%')
          .height(42)
          .font({ size: 17, weight: FontWeight.Medium })
          .fontColor(this.palette().textPrimary)
          .backgroundColor('#00000000')
          .selectedOptionBgColor(this.palette().primarySubtle)
          .selectedOptionFontColor(this.palette().primary)
          .optionBgColor(this.palette().surface)
          .optionFontColor(this.palette().textPrimary)
          .menuBackgroundColor(this.palette().surface)
          .showDefaultSelectedIcon(true)
          .onSelect((index: number): void => {
            this.selectedAacBitrate = index === 0 ? 128000 : 256000;
          })
      }
    }
    .width('100%')
    .height(72)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
  }

  private palette(): HarmonyPalette {
    return HarmonyTheme.palette(this.themeMode);
  }
}

@Component
export struct RecorderPage {
  @State private recordingState: RecordingState = RecordingState.IDLE;
  @State private durationMs: number = 0;
  @State private fileSizeBytes: number = 0;
  @State private waveform: number[] = [];
  @State private selectedFormat: RecordingFormat = RecordingFormat.WAV;
  @State private selectedSampleRate: number = 48000;
  @State private selectedWavBitDepth: number = 16;
  @State private selectedAacBitrate: number = 128000;
  @State private notice: string = '';
  @State private isWorking: boolean = false;
  @State private isWide: boolean = false;
  @State private showFormatSheet: boolean = false;
  @StorageLink(ThemeStore.MODE_KEY) private themeMode: number = ThemeMode.LIGHT;
  private readonly recordingService: RecordingService = RecordingService.getInstance();

  aboutToAppear(): void {
    this.syncNavigationRecordingState(this.recordingService.getState());
    this.recordingService.setObserver((snapshot: RecordingSnapshot): void => {
      this.recordingState = snapshot.state;
      this.durationMs = snapshot.durationMs;
      this.fileSizeBytes = snapshot.sizeBytes;
      this.waveform = snapshot.waveform;
      this.syncNavigationRecordingState(snapshot.state);
      if (snapshot.message.length > 0) {
        this.notice = snapshot.message;
      }
    });
  }

  aboutToDisappear(): void {
    this.recordingService.setObserver(undefined);
  }

  build() {
    Column({ space: 0 }) {
      this.pageHeader()

      Column({ space: this.isWide ? 22 : 14 }) {
        this.recordingMonitor()
        this.recordingFooter()
        if (this.notice.length > 0) {
          Text(this.notice)
            .fontSize(13)
            .fontColor(this.palette().danger)
            .textAlign(TextAlign.Center)
            .width(this.monitorWidth())
            .maxLines(2)
        }
      }
      .width(ResponsiveLayout.contentWidth(this.isWide))
      .layoutWeight(1)
      .padding({
        left: ResponsiveLayout.horizontalPadding(this.isWide),
        right: ResponsiveLayout.horizontalPadding(this.isWide),
        top: 8,
        bottom: 8
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ top: this.isWide ? 24 : 14 })
    .backgroundColor(this.palette().pageBackground)
    .onAreaChange((oldValue: Area, newValue: Area): void => {
      this.isWide = ResponsiveLayout.isWide(newValue.width);
    })
  }

  @Builder
  private pageHeader() {
    Row() {
      Text('录制')
        .fontSize(this.isWide ? 30 : 26)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().textPrimary)
    }
    .width(ResponsiveLayout.contentWidth(this.isWide))
    .padding({
      left: ResponsiveLayout.horizontalPadding(this.isWide),
      right: ResponsiveLayout.horizontalPadding(this.isWide)
    })
  }

  @Builder
  private recordingMonitor() {
    Column({ space: this.isWide ? 20 : 14 }) {
      Text(TimeUtils.formatDuration(this.durationMs))
        .fontSize(this.isWide ? 24 : 20)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette().textPrimary)
        .letterSpacing(1)

      LiveWaveform({
        values: this.waveform,
        active: this.recordingState === RecordingState.RECORDING,
        themeMode: this.themeMode,
        renderHeight: this.isWide ? 220 : 148
      })

      Row({ space: 0 }) {
        this.formatSelector()
        Divider()
          .vertical(true)
          .height(30)
          .color(this.palette().divider)
        this.fileSizeMeta()
      }
      .width('100%')
      .height(56)
      .backgroundColor(this.palette().surfaceSubtle)
      .borderRadius(18)
    }
    .width(this.monitorWidth())
    .padding({
      left: this.isWide ? 36 : 20,
      right: this.isWide ? 36 : 20,
      top: this.isWide ? 26 : 20,
      bottom: this.isWide ? 22 : 16
    })
    .backgroundColor(this.palette().surface)
    .borderRadius(this.isWide ? 28 : 24)
  }

  @Builder
  private formatSelector() {
    Button() {
      Column({ space: 3 }) {
        Text('格式')
          .fontSize(10)
          .fontColor(this.palette().textTertiary)
        Row({ space: 5 }) {
          Text(this.compactFormatLabel())
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().textPrimary)
            .maxLines(1)
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(13)
            .fontColor([this.palette().primary])
        }
      }
      .alignItems(HorizontalAlign.Center)
    }
    .layoutWeight(1)
    .height(56)
    .backgroundColor('#00000000')
    .borderRadius(18)
    .enabled(!this.hasActiveRecording())
    .accessibilityText(`调整录音质量，当前${this.accessibleQualityLabel()}`)
    .onClick((): void => {
      this.showFormatSheet = true;
    })
    .bindSheet($$this.showFormatSheet, this.recordingSettingsSheet(), {
      height: SheetSize.MEDIUM,
      preferType: SheetType.BOTTOM,
      dragBar: true,
      showClose: false,
      backgroundColor: this.palette().surface
    })
  }

  @Builder
  private fileSizeMeta() {
    Column({ space: 3 }) {
      Text('大小')
        .fontSize(10)
        .fontColor(this.palette().textTertiary)
      Text(FileSizeUtils.format(this.fileSizeBytes))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette().textPrimary)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private recordingSettingsSheet() {
    RecordingQualitySheet({
      selectedFormat: $selectedFormat,
      selectedSampleRate: $selectedSampleRate,
      selectedWavBitDepth: $selectedWavBitDepth,
      selectedAacBitrate: $selectedAacBitrate,
      themeMode: this.themeMode
    })
  }

  @Builder
  private recordingFooter() {
    if (this.hasActiveRecording()) {
      Row({ space: 0 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(24)
            .fontColor([this.palette().danger])
        }
          .width(58)
          .height(58)
          .backgroundColor(this.palette().dangerSubtle)
          .borderRadius(29)
          .enabled(!this.isWorking)
          .accessibilityText('删除本次录音')
          .onClick((): void => {
            this.confirmDiscardRecording();
          })
        Blank().layoutWeight(1)
        Button() {
          if (this.recordingState === RecordingState.RECORDING) {
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
          .backgroundColor(this.palette().recording)
          .borderRadius(36)
          .enabled(!this.isWorking)
          .accessibilityText(this.recordingState === RecordingState.RECORDING ? '暂停录音' : '继续录音')
          .onClick((): void => {
            this.togglePause();
          })
        Blank().layoutWeight(1)
        Button() {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(25)
            .fontColor([this.palette().primary])
        }
          .width(58)
          .height(58)
          .backgroundColor(this.palette().primarySubtle)
          .borderRadius(29)
          .enabled(!this.isWorking)
          .accessibilityText('保存录音')
          .onClick((): void => {
            this.stopRecording();
          })
      }
      .width(this.controlWidth())
      .padding({ top: 2, bottom: this.isWide ? 8 : 2 })
      .alignItems(VerticalAlign.Center)
    } else {
      Button() {
        SymbolGlyph($r('sys.symbol.mic_fill'))
          .fontSize(30)
          .fontColor([this.palette().onPrimary])
      }
      .width(this.isWide ? 92 : 86)
      .height(this.isWide ? 92 : 86)
      .backgroundColor(this.palette().recording)
      .borderRadius(this.isWide ? 46 : 43)
      .enabled(!this.isWorking)
      .accessibilityText('开始录音')
      .onClick((): void => {
        this.startRecording();
      })
    }
  }

  private confirmDiscardRecording(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '删除本次录音？',
      message: '本次录音不会保存。',
      buttons: [
        { text: '取消', color: this.palette().textSecondary },
        { text: '删除', color: this.palette().danger }
      ]
    }).then((result): void => {
      if (result.index === 1) {
        this.discardRecording();
      }
    }).catch((error: Error): void => {
      this.notice = '无法打开确认窗口';
    });
  }

  private async discardRecording(): Promise<void> {
    this.isWorking = true;
    try {
      await this.recordingService.discard();
      this.notice = '';
    } catch (error) {
      this.notice = '删除录音失败';
    } finally {
      this.isWorking = false;
    }
  }

  private async startRecording(): Promise<void> {
    this.isWorking = true;
    this.notice = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const granted = await PermissionService.ensureMicrophonePermission(context);
      if (!granted) {
        this.notice = '需要麦克风权限';
        return;
      }
      await this.recordingService.start(context, this.currentConfig());
    } catch (error) {
      this.notice = '无法开始录音';
    } finally {
      this.isWorking = false;
    }
  }

  private async togglePause(): Promise<void> {
    this.isWorking = true;
    try {
      if (this.recordingState === RecordingState.RECORDING) {
        await this.recordingService.pause();
      } else {
        await this.recordingService.resume();
      }
    } catch (error) {
      this.notice = '无法切换录音状态';
    } finally {
      this.isWorking = false;
    }
  }

  private async stopRecording(): Promise<void> {
    this.isWorking = true;
    try {
      const saved = await this.recordingService.stop();
      if (saved !== undefined) {
        this.notice = '';
      }
    } catch (error) {
      this.notice = '保存录音失败';
    } finally {
      this.isWorking = false;
    }
  }

  private currentConfig(): RecordingConfig {
    if (this.selectedFormat === RecordingFormat.WAV) {
      return RecordingConfig.wav(this.selectedSampleRate, this.selectedWavBitDepth);
    }
    return RecordingConfig.aac(this.selectedAacBitrate, this.selectedSampleRate);
  }

  private hasActiveRecording(): boolean {
    return this.recordingState === RecordingState.RECORDING || this.recordingState === RecordingState.PAUSED;
  }

  private syncNavigationRecordingState(state: RecordingState): void {
    NavigationStore.setRecordingActive(state === RecordingState.RECORDING || state === RecordingState.PAUSED);
  }

  private compactFormatLabel(): string {
    return this.selectedFormat === RecordingFormat.WAV ? `WAV · ${this.selectedWavBitDepth} bit` :
      `M4A · ${this.selectedAacBitrate / 1000} kbps`;
  }

  private encodingDetailLabel(): string {
    return this.selectedFormat === RecordingFormat.WAV ? `${this.selectedWavBitDepth} bit` :
      `${this.selectedAacBitrate / 1000} kbps`;
  }

  private sampleRateLabel(): string {
    return this.selectedSampleRate === 44100 ? '44.1 kHz' : '48 kHz';
  }

  private accessibleQualityLabel(): string {
    return `${this.compactFormatLabel()}，${this.sampleRateLabel()}，单声道`;
  }

  private monitorWidth(): Length {
    return this.isWide ? 680 : '100%';
  }

  private controlWidth(): Length {
    return this.isWide ? 420 : '100%';
  }

  private palette(): HarmonyPalette {
    return HarmonyTheme.palette(this.themeMode);
  }
}
