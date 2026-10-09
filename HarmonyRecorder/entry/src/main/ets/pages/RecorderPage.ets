import { common } from '@kit.AbilityKit';
import { TextRole, VisualTheme } from '../utils/VisualTheme';
import { HdsNavigation } from '@kit.UIDesignKit';
import { LiveWaveform } from '../components/LiveWaveform';
import { StageEdgeLight } from '../components/StageEdgeLight';
import { RecordingConfig, RecordingFormat, RecordingSnapshot, RecordingState } from '../models/RecordingTypes';
import { PermissionService } from '../services/PermissionService';
import { RecordingService } from '../services/RecordingService';
import { FileSizeUtils } from '../utils/FileSizeUtils';
import { HarmonyPalette, HarmonyTheme, HarmonyTokens, ThemeMode, ThemeStore } from '../utils/HarmonyTheme';
import { MaterialRole, MaterialTheme } from '../utils/MaterialTheme';
import { MotionTheme } from '../utils/MotionTheme';
import { NavigationStore } from '../utils/NavigationStore';
import { PressFeedback } from '../utils/PressFeedback';
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
    Scroll() {
      Column({ space: 0 }) {
        Text('录音质量')
          .width('100%')
          .attributeModifier(VisualTheme.text(TextRole.TITLE, true))
          .fontColor(HarmonyTokens.textPrimary())
          .padding({ left: 8, bottom: 8 })
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
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .clip(true)
    .id('recording-quality-sheet')
  }

  @Builder
  private formatSetting() {
    Column({ space: 3 }) {
      Text('格式')
        .width('100%')
        .attributeModifier(VisualTheme.text(TextRole.CAPTION))
        .fontColor(HarmonyTokens.textSecondary())
        .padding({ left: 10 })
      Select([{ value: 'WAV' }, { value: 'M4A' }, { value: 'FLAC' }])
        .selected(this.selectedFormat === RecordingFormat.WAV ? 0 :
          this.selectedFormat === RecordingFormat.M4A ? 1 : 2)
        .value(this.selectedFormat.toUpperCase())
        .width('100%')
        .height(VisualTheme.CONTROL_HEIGHT)
        .font({ size: VisualTheme.BODY_SIZE, weight: FontWeight.Medium })
        .optionFont({ size: VisualTheme.BODY_SIZE, weight: FontWeight.Medium })
        .selectedOptionFont({ size: VisualTheme.BODY_SIZE, weight: FontWeight.Medium })
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
          this.selectedFormat = index === 0 ? RecordingFormat.WAV :
            index === 1 ? RecordingFormat.M4A : RecordingFormat.FLAC;
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
        .attributeModifier(VisualTheme.text(TextRole.CAPTION))
        .fontColor(HarmonyTokens.textSecondary())
        .padding({ left: 10 })
      Select([{ value: '44.1 kHz' }, { value: '48 kHz' }])
        .selected(this.selectedSampleRate === 44100 ? 0 : 1)
        .value(this.selectedSampleRate === 44100 ? '44.1 kHz' : '48 kHz')
        .width('100%')
        .height(VisualTheme.CONTROL_HEIGHT)
        .font({ size: VisualTheme.BODY_SIZE, weight: FontWeight.Medium })
        .optionFont({ size: VisualTheme.BODY_SIZE, weight: FontWeight.Medium })
        .selectedOptionFont({ size: VisualTheme.BODY_SIZE, weight: FontWeight.Medium })
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
      Text(this.selectedFormat === RecordingFormat.M4A ? '码率' : '位深')
        .width('100%')
        .attributeModifier(VisualTheme.text(TextRole.CAPTION))
        .fontColor(HarmonyTokens.textSecondary())
        .padding({ left: 10 })
      if (this.selectedFormat === RecordingFormat.WAV) {
        Select([{ value: '16 bit' }, { value: '24 bit' }])
          .selected(this.selectedWavBitDepth === 16 ? 0 : 1)
          .value(`${this.selectedWavBitDepth} bit`)
          .width('100%')
          .height(VisualTheme.CONTROL_HEIGHT)
          .font({ size: VisualTheme.BODY_SIZE, weight: FontWeight.Medium })
          .optionFont({ size: VisualTheme.BODY_SIZE, weight: FontWeight.Medium })
          .selectedOptionFont({ size: VisualTheme.BODY_SIZE, weight: FontWeight.Medium })
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
      } else if (this.selectedFormat === RecordingFormat.FLAC) {
        Text('16 bit · 无损压缩')
          .attributeModifier(VisualTheme.text(TextRole.BODY, true))
          .fontColor(HarmonyTokens.textPrimary())
          .height(VisualTheme.CONTROL_HEIGHT)
          .padding({ left: 10 })
      } else {
        Select([{ value: '128 kbps' }, { value: '256 kbps' }])
          .selected(this.selectedAacBitrate === 128000 ? 0 : 1)
          .value(`${this.selectedAacBitrate / 1000} kbps`)
          .width('100%')
          .height(VisualTheme.CONTROL_HEIGHT)
          .font({ size: VisualTheme.BODY_SIZE, weight: FontWeight.Medium })
          .optionFont({ size: VisualTheme.BODY_SIZE, weight: FontWeight.Medium })
          .selectedOptionFont({ size: VisualTheme.BODY_SIZE, weight: FontWeight.Medium })
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
  @State private isSplitLayout: boolean = false;
  @State private availableWidth: number = 360;
  @State private contentHeight: number = 640;
  @State private stageHeight: number = 0;
  @State private showFormatSheet: boolean = false;
  private discardDialogOpen: boolean = false;
  @StorageLink(ThemeStore.MODE_KEY) private themeMode: number = ThemeMode.LIGHT;
  @StorageLink(MotionTheme.REDUCE_KEY) private reduceMotion: boolean = false;
  private readonly recordingService: RecordingService = RecordingService.getInstance();

  aboutToAppear(): void {
    this.syncNavigationRecordingState(this.recordingService.getState());
    this.recordingService.setObserver((snapshot: RecordingSnapshot): void => {
      this.getUIContext().runScopedTask((): void => {
        // Animate the control-state boundary once, never every audio update.
        if (this.recordingState !== snapshot.state) {
          this.getUIContext().animateTo(MotionTheme.state(), (): void => {
            this.recordingState = snapshot.state;
          });
          this.syncNavigationRecordingState(snapshot.state);
        }
        const displayDuration = Math.floor(snapshot.durationMs / 1000) * 1000;
        if (this.durationMs !== displayDuration) {
          this.durationMs = displayDuration;
        }
        if (FileSizeUtils.format(this.fileSizeBytes) !== FileSizeUtils.format(snapshot.sizeBytes)) {
          this.fileSizeBytes = snapshot.sizeBytes;
        }
        if (snapshot.waveform.length !== this.waveform.length ||
          snapshot.waveform.some((value: number, index: number): boolean => value !== this.waveform[index])) {
          this.waveform = snapshot.waveform;
        }
        if (snapshot.message.length > 0) {
          this.notice = snapshot.message;
        }
      });
    });
  }

  aboutToDisappear(): void {
    this.recordingService.setObserver(undefined);
  }

  build() {
    HdsNavigation() {
      Scroll() {
        Column() {
          if (this.isSplitLayout) {
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
            .height(ResponsiveLayout.recorderContentHeight(this.contentHeight, true, this.notice.length > 0))
            .padding({ left: 24, right: 24, top: 16, bottom: 104 })
            .alignItems(VerticalAlign.Center)
          } else {
            Column({ space: 16 }) {
              this.recordingStage()
              this.recordingFooter()
              if (this.notice.length > 0) {
                this.noticeText()
              }
            }
            .width('100%')
            .constraintSize({ maxWidth: 720 })
            .height(ResponsiveLayout.recorderContentHeight(this.contentHeight, false, this.notice.length > 0))
            .padding({ left: 16, right: 16, top: 8, bottom: 104 })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .onAreaChange((oldArea: Area, area: Area): void => {
        const width = Number(area.width);
        const height = Number(area.height);
        if (Number.isFinite(width) && width > 0 && Math.abs(width - this.availableWidth) >= 1) {
          this.availableWidth = width;
          this.isWide = ResponsiveLayout.isWide(width);
        }
        if (Number.isFinite(height) && height > 0 && Math.abs(height - this.contentHeight) >= 1) {
          this.contentHeight = height;
        }
        this.isSplitLayout = ResponsiveLayout.usesSplitLayout(this.availableWidth, this.contentHeight);
      })
    }
    .width('100%')
    .height('100%')
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .hideBackButton(true)
    .backgroundColor(HarmonyTokens.pageBackground())
  }

  @Builder
  private noticeText() {
    Text(this.notice)
      .attributeModifier(VisualTheme.text(TextRole.CAPTION))
      .fontColor(HarmonyTokens.danger())
      .textAlign(TextAlign.Center)
      .width('100%')
      .maxLines(4)
      .transition(MotionTheme.appear(this.reduceMotion))
  }

  @Builder
  private recordingStage() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 14 }) {
        Row({ space: 8 }) {
          Stack({ alignContent: Alignment.Center }) {
            if (this.recordingState === RecordingState.RECORDING) {
              Circle().width(7).height(7).fill(HarmonyTokens.primary())
                .transition(MotionTheme.appear(this.reduceMotion))
            } else if (this.recordingState === RecordingState.PAUSED) {
              SymbolGlyph($r('sys.symbol.pause_fill'))
                .fontSize(VisualTheme.ICON_SMALL)
                .fontColor([HarmonyTokens.waveformIdle()])
                .transition(MotionTheme.appear(this.reduceMotion))
            }
          }
          .width(12)
          .height(16)
          Text(TimeUtils.formatDuration(this.durationMs))
            .attributeModifier(VisualTheme.text(TextRole.TIMER, true, true))
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
          sampleIntervalMs: this.selectedFormat === RecordingFormat.M4A ? 120 : 90,
          renderHeight: ResponsiveLayout.recorderWaveformHeight(this.contentHeight, this.isSplitLayout,
            this.notice.length > 0)
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
        left: 18,
        right: 18,
        top: 18,
        bottom: 16
      })
      .attributeModifier(MaterialTheme.surface(MaterialRole.STAGE, this.themeMode))
      .borderRadius(28)
      .onAreaChange((oldArea: Area, area: Area): void => {
        const height = Number(area.height);
        if (Number.isFinite(height) && Math.abs(height - this.stageHeight) >= 1) {
          this.stageHeight = height;
        }
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
    .id('recording-stage')
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
            .attributeModifier(VisualTheme.text(TextRole.METADATA, true))
            .fontColor(HarmonyTokens.textPrimary())
            .maxLines(1)
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(VisualTheme.ICON_SMALL)
            .fontColor([HarmonyTokens.primary()])
            .animation(undefined)
            .rotate({ angle: this.showFormatSheet && !this.reduceMotion ? 180 : 0 })
            .animation(MotionTheme.state(this.reduceMotion))
      }
    }
    .layoutWeight(1)
    .height(52)
    .backgroundColor(Color.Transparent)
    .borderRadius(18)
    .enabled(!this.hasActiveRecording())
    .animation(undefined)
    .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
    .animation(MotionTheme.press(this.reduceMotion))
    .accessibilityText(`调整录音质量，当前${this.accessibleQualityLabel()}`)
    .id('record-quality')
    .onClick((): void => {
      this.showFormatSheet = true;
    })
    .bindSheet($$this.showFormatSheet, this.recordingSettingsSheet(), {
      height: this.isWide ? Math.min(560, Math.max(180, this.contentHeight - 80)) : SheetSize.MEDIUM,
      width: this.isWide ? Math.min(560, this.availableWidth - 48) : '100%',
      preferType: this.isWide ? SheetType.CENTER : SheetType.BOTTOM,
      mode: SheetMode.OVERLAY,
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
        .attributeModifier(VisualTheme.text(TextRole.METADATA, true, true))
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
    // Stable layout slot: start/stop no longer shifts the stage and its Canvas.
    Stack({ alignContent: Alignment.Center }) {
      if (this.hasActiveRecording()) {
        Row({ space: 8 }) {
          Button() {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(VisualTheme.ICON_SECONDARY)
              .fontColor([HarmonyTokens.danger()])
          }
          .width(VisualTheme.SECONDARY_BUTTON)
          .height(VisualTheme.SECONDARY_BUTTON)
          .backgroundColor(HarmonyTokens.dangerSubtle())
          .borderRadius(28)
          .enabled(!this.isWorking)
          .animation(undefined)
          .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
          .animation(MotionTheme.press(this.reduceMotion))
          .accessibilityText('删除本次录音')
          .id('record-discard')
          .onClick((): void => {
            this.confirmDiscardRecording();
          })

          Button({ type: ButtonType.Circle }) {
            if (this.recordingState === RecordingState.RECORDING) {
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
          .width(VisualTheme.PRIMARY_BUTTON)
          .height(VisualTheme.PRIMARY_BUTTON)
          .backgroundColor(HarmonyTokens.primary())
          .linearGradient({ angle: 155, colors: [[HarmonyTokens.controlLight(), 0],
            [HarmonyTokens.primary(), 0.64]] })
          .border({ width: 0.75, color: HarmonyTokens.glassHighlight() })
          .borderRadius(VisualTheme.PRIMARY_BUTTON / 2)
          .clip(true)
          .enabled(!this.isWorking)
          .animation(undefined)
          .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion, true))
          .animation(MotionTheme.press(this.reduceMotion))
          .accessibilityText(this.recordingState === RecordingState.RECORDING ? '暂停录音' : '继续录音')
          .id('record-pause')
          .onClick((): void => {
            this.togglePause();
          })

          Button() {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(VisualTheme.ICON_SECONDARY)
              .fontColor([HarmonyTokens.primary()])
          }
          .width(VisualTheme.SECONDARY_BUTTON)
          .height(VisualTheme.SECONDARY_BUTTON)
          .backgroundColor(HarmonyTokens.primarySubtle())
          .borderRadius(28)
          .enabled(!this.isWorking)
          .animation(undefined)
          .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
          .animation(MotionTheme.press(this.reduceMotion))
          .accessibilityText('保存录音')
          .id('record-save')
          .onClick((): void => {
            this.stopRecording();
          })
        }
        .width(224)
        .height(84)
        .padding({ left: 10, right: 10 })
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)
        .attributeModifier(MaterialTheme.surface(MaterialRole.CONTROL, this.themeMode))
        .borderRadius(42)
        .transition(MotionTheme.appear(this.reduceMotion))
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(VisualTheme.PRIMARY_PLATE)
            .height(VisualTheme.PRIMARY_PLATE)
            .attributeModifier(MaterialTheme.surface(MaterialRole.CONTROL, this.themeMode))
            .borderRadius(VisualTheme.PRIMARY_PLATE / 2)
            .hitTestBehavior(HitTestMode.None)
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.mic_fill'))
              .fontSize(VisualTheme.ICON_PRIMARY)
              .fontColor([HarmonyTokens.onPrimary()])
          }
          .width(VisualTheme.PRIMARY_BUTTON)
          .height(VisualTheme.PRIMARY_BUTTON)
          .backgroundColor(HarmonyTokens.primary())
          .radialGradient({
            center: ['30%', '15%'],
            radius: '110%',
            colors: [[HarmonyTokens.controlLight(), 0], [HarmonyTokens.primary(), 0.70]]
          })
          .borderRadius(VisualTheme.PRIMARY_BUTTON / 2)
          .clip(true)
          .border({ width: 1, color: HarmonyTokens.glassHighlight() })
          .animation(undefined)
          .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion, true))
          .animation(MotionTheme.press(this.reduceMotion))
          .enabled(!this.isWorking)
          .accessibilityText('开始录音')
          .id('record-start')
          .onClick((): void => {
            this.startRecording();
          })
        }
        .width(148)
        .height(VisualTheme.CONTROL_SLOT)
        .transition(MotionTheme.appear(this.reduceMotion))
      }
    }
    .width(224)
    .height(VisualTheme.CONTROL_SLOT)
    .id('record-controls')
  }

  private confirmDiscardRecording(): void {
    if (this.isWorking || this.discardDialogOpen) {
      return;
    }
    this.discardDialogOpen = true;
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
      if (error.message !== 'cancel') {
        console.error(`Open discard confirmation failed: ${String(error)}`);
        this.notice = '无法打开确认窗口';
      }
    }).finally((): void => {
      this.discardDialogOpen = false;
    });
  }

  private async discardRecording(): Promise<void> {
    if (this.isWorking) {
      return;
    }
    this.isWorking = true;
    try {
      await this.recordingService.discard();
      this.notice = '';
    } catch (error) {
      this.notice = String(error);
    } finally {
      this.isWorking = false;
    }
  }

  private async startRecording(): Promise<void> {
    if (this.isWorking) {
      return;
    }
    this.isWorking = true;
    this.notice = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const granted = await PermissionService.ensureMicrophonePermission(context);
      if (!granted) {
        this.notice = PermissionService.MICROPHONE_DENIED_NOTICE;
        return;
      }
      await this.recordingService.start(context, this.currentConfig());
    } catch (error) {
      this.notice = `无法开始录音：${String(error)}`;
    } finally {
      this.isWorking = false;
    }
  }

  private async togglePause(): Promise<void> {
    if (this.isWorking) {
      return;
    }
    this.isWorking = true;
    this.notice = '';
    try {
      if (this.recordingState === RecordingState.RECORDING) {
        await this.recordingService.pause();
      } else {
        await this.recordingService.resume();
      }
    } catch (error) {
      this.notice = String(error);
    } finally {
      this.isWorking = false;
    }
  }

  private async stopRecording(): Promise<void> {
    if (this.isWorking) {
      return;
    }
    this.isWorking = true;
    this.notice = '';
    try {
      await this.recordingService.stop();
    } catch (error) {
      this.notice = String(error);
    } finally {
      this.isWorking = false;
    }
  }

  private currentConfig(): RecordingConfig {
    if (this.selectedFormat === RecordingFormat.WAV) {
      return RecordingConfig.wav(this.selectedSampleRate, this.selectedWavBitDepth);
    }
    if (this.selectedFormat === RecordingFormat.FLAC) {
      return RecordingConfig.flac(this.selectedSampleRate);
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
    return this.currentConfig().compactLabel;
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
