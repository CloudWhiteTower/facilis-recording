import { common } from '@kit.AbilityKit';
import { curves } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { LiveWaveform } from '../components/LiveWaveform';
import { StageEdgeLight } from '../components/StageEdgeLight';
import { RecordingConfig, RecordingFormat, RecordingSnapshot, RecordingState } from '../models/RecordingTypes';
import { PermissionService } from '../services/PermissionService';
import { RecordingService } from '../services/RecordingService';
import { FileSizeUtils } from '../utils/FileSizeUtils';
import { HarmonyPalette, HarmonyTheme, HarmonyTokens, ThemeMode, ThemeStore } from '../utils/HarmonyTheme';
import { MaterialRole, MaterialTheme } from '../utils/MaterialTheme';
import { NavigationStore } from '../utils/NavigationStore';
import { ResponsiveLayout } from '../utils/ResponsiveLayout';
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
        .fontColor(HarmonyTokens.textPrimary())
        .padding({ left: 8, bottom: 14 })
      this.formatSetting()
      Divider().color(HarmonyTokens.divider()).margin({ left: 8, right: 8 })
      this.sampleRateSetting()
      Divider().color(HarmonyTokens.divider()).margin({ left: 8, right: 8 })
      this.encodingSetting()
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 10, bottom: 30 })
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private formatSetting() {
    Column({ space: 3 }) {
      Text('格式')
        .width('100%')
        .fontSize(12)
        .fontColor(HarmonyTokens.textSecondary())
        .padding({ left: 10 })
      Select([{ value: 'WAV' }, { value: 'M4A' }])
        .selected(this.selectedFormat === RecordingFormat.WAV ? 0 : 1)
        .value(this.selectedFormat === RecordingFormat.WAV ? 'WAV' : 'M4A')
        .width('100%')
        .height(44)
        .font({ size: 17, weight: FontWeight.Medium })
        .fontColor(HarmonyTokens.textPrimary())
        .backgroundColor(Color.Transparent)
        .selectedOptionBgColor(HarmonyTokens.primarySubtle())
        .selectedOptionFontColor(HarmonyTokens.primary())
        .optionBgColor(Color.Transparent)
        .optionFontColor(HarmonyTokens.textPrimary())
        .menuBackgroundColor(HarmonyTokens.glassSurface())
        .menuBackgroundBlurStyle(BlurStyle.COMPONENT_THICK)
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
        .fontColor(HarmonyTokens.textSecondary())
        .padding({ left: 10 })
      Select([{ value: '44.1 kHz' }, { value: '48 kHz' }])
        .selected(this.selectedSampleRate === 44100 ? 0 : 1)
        .value(this.selectedSampleRate === 44100 ? '44.1 kHz' : '48 kHz')
        .width('100%')
        .height(44)
        .font({ size: 17, weight: FontWeight.Medium })
        .fontColor(HarmonyTokens.textPrimary())
        .backgroundColor(Color.Transparent)
        .selectedOptionBgColor(HarmonyTokens.primarySubtle())
        .selectedOptionFontColor(HarmonyTokens.primary())
        .optionBgColor(Color.Transparent)
        .optionFontColor(HarmonyTokens.textPrimary())
        .menuBackgroundColor(HarmonyTokens.glassSurface())
        .menuBackgroundBlurStyle(BlurStyle.COMPONENT_THICK)
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
        .fontColor(HarmonyTokens.textSecondary())
        .padding({ left: 10 })
      if (this.selectedFormat === RecordingFormat.WAV) {
        Select([{ value: '16 bit' }, { value: '24 bit' }])
          .selected(this.selectedWavBitDepth === 16 ? 0 : 1)
          .value(`${this.selectedWavBitDepth} bit`)
          .width('100%')
          .height(44)
          .font({ size: 17, weight: FontWeight.Medium })
          .fontColor(HarmonyTokens.textPrimary())
          .backgroundColor(Color.Transparent)
          .selectedOptionBgColor(HarmonyTokens.primarySubtle())
          .selectedOptionFontColor(HarmonyTokens.primary())
          .optionBgColor(Color.Transparent)
          .optionFontColor(HarmonyTokens.textPrimary())
          .menuBackgroundColor(HarmonyTokens.glassSurface())
          .menuBackgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .showDefaultSelectedIcon(true)
          .onSelect((index: number): void => {
            this.selectedWavBitDepth = index === 0 ? 16 : 24;
          })
      } else {
        Select([{ value: '128 kbps' }, { value: '256 kbps' }])
          .selected(this.selectedAacBitrate === 128000 ? 0 : 1)
          .value(`${this.selectedAacBitrate / 1000} kbps`)
          .width('100%')
          .height(44)
          .font({ size: 17, weight: FontWeight.Medium })
          .fontColor(HarmonyTokens.textPrimary())
          .backgroundColor(Color.Transparent)
          .selectedOptionBgColor(HarmonyTokens.primarySubtle())
          .selectedOptionFontColor(HarmonyTokens.primary())
          .optionBgColor(Color.Transparent)
          .optionFontColor(HarmonyTokens.textPrimary())
          .menuBackgroundColor(HarmonyTokens.glassSurface())
          .menuBackgroundBlurStyle(BlurStyle.COMPONENT_THICK)
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
}

@Component
export struct RecorderPage {
  @Prop isVisible: boolean = true;
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
  @State private stageHeight: number = 0;
  @State private showFormatSheet: boolean = false;
  @State private recordPressed: boolean = false;
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
    HdsNavigation() {
      if (this.isWide) {
        Row({ space: 24 }) {
          Column() {
            this.recordingStage()
          }
          .layoutWeight(1)
          Column() {
            Blank().layoutWeight(1)
            this.recordingFooter()
            if (this.notice.length > 0) {
              this.noticeText()
            }
            Blank().layoutWeight(1)
          }
          .width(224)
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        .width(ResponsiveLayout.contentWidth(true))
        .constraintSize({ maxWidth: 1100 })
        .height('100%')
        .padding({ left: 24, right: 24, top: 16, bottom: 104 })
        .alignItems(VerticalAlign.Center)
      } else {
        Column({ space: 16 }) {
          Blank().layoutWeight(1)
          this.recordingStage()
          this.recordingFooter()
          if (this.notice.length > 0) {
            this.noticeText()
          }
          Blank().layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 104 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .titleBar({
      content: {
        title: { mainTitle: '录音' }
      },
      style: {
        scrollEffectOpts: { enableScrollEffect: false },
        systemMaterialEffect: MaterialTheme.resolve(MaterialRole.NAVIGATION)
      },
      enableComponentSafeArea: true
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .backgroundColor(HarmonyTokens.pageBackground())
    .onAreaChange((oldValue: Area, newValue: Area): void => {
      this.isWide = ResponsiveLayout.isWide(newValue.width);
    })
  }

  @Builder
  private noticeText() {
    Text(this.notice)
      .fontSize(12)
      .fontColor(HarmonyTokens.danger())
      .textAlign(TextAlign.Center)
      .width('100%')
      .maxLines(2)
  }

  @Builder
  private recordingStage() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: this.isWide ? 20 : 14 }) {
        Row({ space: 8 }) {
          if (this.recordingState === RecordingState.RECORDING) {
            Circle().width(7).height(7).fill(HarmonyTokens.primary())
          } else if (this.recordingState === RecordingState.PAUSED) {
            SymbolGlyph($r('sys.symbol.pause_fill'))
              .fontSize(12)
              .fontColor([HarmonyTokens.waveformIdle()])
          }
          Text(TimeUtils.formatDuration(this.durationMs))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(HarmonyTokens.textPrimary())
            .letterSpacing(0.6)
        }
        .height(24)

        LiveWaveform({
          values: this.waveform,
          recordingState: this.recordingState,
          themeMode: this.themeMode,
          accentColor: this.palette().primary,
          isVisible: this.isVisible,
          renderHeight: this.isWide ? 220 : 170
        })

        Row({ space: 0 }) {
          this.formatSelector()
          Divider()
            .vertical(true)
            .height(28)
            .color(HarmonyTokens.divider())
          this.fileSizeMeta()
        }
        .width('100%')
        .height(52)
      }
      .width('100%')
      .padding({
        left: this.isWide ? 32 : 18,
        right: this.isWide ? 32 : 18,
        top: this.isWide ? 24 : 18,
        bottom: this.isWide ? 22 : 16
      })
      .attributeModifier(MaterialTheme.surface(MaterialRole.STAGE, this.themeMode))
      .borderRadius(28)
      .onAreaChange((oldArea: Area, area: Area): void => {
        this.stageHeight = Number(area.height);
      })

      StageEdgeLight({
        recordingState: this.recordingState,
        isVisible: this.isVisible,
        accentColor: this.palette().primary,
        themeMode: this.themeMode
      })
        .width('100%')
        .height(this.stageHeight)
        .position({ x: 0, y: 0 })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .radialGradient({
      center: ['18%', '12%'],
      radius: '110%',
      colors: [[HarmonyTokens.primarySubtle(), 0], [HarmonyTokens.pageBackground(), 0.88]]
    })
    .borderRadius(28)
    .clip(true)
  }

  @Builder
  private formatSelector() {
    Button() {
      Row({ space: 6 }) {
          Text(this.compactFormatLabel())
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(HarmonyTokens.textPrimary())
            .maxLines(1)
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(12)
            .fontColor([HarmonyTokens.primary()])
      }
    }
    .layoutWeight(1)
    .height(52)
    .backgroundColor(Color.Transparent)
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
      backgroundColor: HarmonyTokens.glassSurface(),
      blurStyle: BlurStyle.COMPONENT_THICK
    })
  }

  @Builder
  private fileSizeMeta() {
    Column({ space: 2 }) {
      Text(FileSizeUtils.format(this.fileSizeBytes))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(HarmonyTokens.textPrimary())
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
      Row({ space: 8 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(22)
            .fontColor([HarmonyTokens.danger()])
        }
        .width(56)
        .height(56)
        .backgroundColor(HarmonyTokens.dangerSubtle())
        .borderRadius(28)
        .enabled(!this.isWorking)
        .accessibilityText('删除本次录音')
        .onClick((): void => {
          this.confirmDiscardRecording();
        })

        Button({ type: ButtonType.Circle }) {
          if (this.recordingState === RecordingState.RECORDING) {
            SymbolGlyph($r('sys.symbol.pause_fill'))
              .fontSize(27)
              .fontColor([HarmonyTokens.onPrimary()])
          } else {
            SymbolGlyph($r('sys.symbol.play_fill'))
              .fontSize(27)
              .fontColor([HarmonyTokens.onPrimary()])
          }
        }
        .width(68)
        .height(68)
        .backgroundColor(HarmonyTokens.primary())
        .linearGradient({ angle: 155, colors: [[HarmonyTokens.controlLight(), 0],
          [HarmonyTokens.primary(), 0.64]] })
        .border({ width: 0.75, color: HarmonyTokens.glassHighlight() })
        .borderRadius(34)
        .clip(true)
        .enabled(!this.isWorking)
        .accessibilityText(this.recordingState === RecordingState.RECORDING ? '暂停录音' : '继续录音')
        .onClick((): void => {
          this.togglePause();
        })

        Button() {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(23)
            .fontColor([HarmonyTokens.primary()])
        }
        .width(56)
        .height(56)
        .backgroundColor(HarmonyTokens.primarySubtle())
        .borderRadius(28)
        .enabled(!this.isWorking)
        .accessibilityText('保存录音')
        .onClick((): void => {
          this.stopRecording();
        })
      }
      .width(this.isWide ? 220 : 224)
      .height(84)
      .padding({ left: 10, right: 10 })
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
      .attributeModifier(MaterialTheme.surface(MaterialRole.CONTROL, this.themeMode))
      .borderRadius(42)
    } else {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(this.isWide ? 110 : 104)
          .height(this.isWide ? 110 : 104)
          .attributeModifier(MaterialTheme.surface(MaterialRole.CONTROL, this.themeMode))
          .borderRadius(55)
          .hitTestBehavior(HitTestMode.None)
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.mic_fill'))
            .fontSize(30)
            .fontColor([HarmonyTokens.onPrimary()])
        }
        .width(this.isWide ? 88 : 82)
        .height(this.isWide ? 88 : 82)
        .backgroundColor(HarmonyTokens.primary())
        .radialGradient({
          center: this.recordPressed ? ['50%', '50%'] : ['30%', '15%'],
          radius: '110%',
          colors: [[HarmonyTokens.controlLight(), 0], [HarmonyTokens.primary(), 0.70]]
        })
        .borderRadius(this.isWide ? 44 : 41)
        .clip(true)
        .border({ width: 1, color: HarmonyTokens.glassHighlight() })
        .scale({ x: this.recordPressed ? 0.92 : 1, y: this.recordPressed ? 0.92 : 1 })
        .animation({ curve: curves.springMotion(0.32, 0.78, 0.18) })
        .enabled(!this.isWorking)
        .accessibilityText('开始录音')
        .onTouch((event: TouchEvent): void => {
          this.recordPressed = event.type === TouchType.Down;
        })
        .onClick((): void => {
          this.startRecording();
        })
      }
      .width(148)
      .height(112)
    }
  }

  private confirmDiscardRecording(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '删除本次录音？',
      message: '本次录音不会保存。',
      buttons: [
        { text: '取消', color: HarmonyTokens.textSecondary() },
        { text: '删除', color: HarmonyTokens.danger() }
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
      this.recordPressed = false;
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

  private sampleRateLabel(): string {
    return this.selectedSampleRate === 44100 ? '44.1 kHz' : '48 kHz';
  }

  private accessibleQualityLabel(): string {
    return `${this.compactFormatLabel()}，${this.sampleRateLabel()}，单声道`;
  }

  private palette(): HarmonyPalette {
    return HarmonyTheme.palette(this.themeMode);
  }
}
