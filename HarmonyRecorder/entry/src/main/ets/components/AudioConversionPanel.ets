import { common } from '@kit.AbilityKit';
import { TextRole, VisualTheme } from '../utils/VisualTheme';
import { RecordingFormat, RecordingInfo } from '../models/RecordingTypes';
import { AudioConversionService } from '../services/AudioConversionService';
import { HarmonyTokens, ThemeMode, ThemeStore } from '../utils/HarmonyTheme';
import { MotionTheme } from '../utils/MotionTheme';
import { PressFeedback } from '../utils/PressFeedback';

@Component
export struct AudioConversionPanel {
  @Prop recording: RecordingInfo = RecordingInfo.placeholder();
  onRunning: (running: boolean) => void = (): void => {};
  onComplete: (recording: RecordingInfo) => void = (): void => {};
  onBack: () => void = (): void => {};
  @State private target: RecordingFormat = RecordingFormat.WAV;
  @State private bitrate: number = 256000;
  @State private running: boolean = false;
  @State private cancelling: boolean = false;
  @State private progress: number = 0;
  @State private message: string = '';
  @StorageLink(ThemeStore.MODE_KEY) private themeMode: number = ThemeMode.LIGHT;
  @StorageLink(MotionTheme.REDUCE_KEY) private reduceMotion: boolean = false;
  private readonly service: AudioConversionService = new AudioConversionService();
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.disposed = false;
    this.target = this.recording.config.format === RecordingFormat.WAV && this.recording.config.bitDepth <= 16 ?
      RecordingFormat.FLAC : RecordingFormat.WAV;
    if (this.recording.config.format === RecordingFormat.WAV && this.recording.config.bitDepth > 16) {
      this.target = RecordingFormat.M4A;
    }
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.service.cancel();
  }

  build() {
    Column({ space: 16 }) {
      Text('转换格式')
        .width('100%').attributeModifier(VisualTheme.text(TextRole.TITLE, true)).fontColor(HarmonyTokens.textPrimary())
        .padding({ left: 8, bottom: 8 })
      Text(`原始录音：${this.recording.config.compactLabel} · ${this.recording.config.sampleRateLabel}`)
        .width('100%').attributeModifier(VisualTheme.text(TextRole.METADATA)).fontColor(HarmonyTokens.textSecondary())
      Row({ space: 8 }) {
        this.formatButton(RecordingFormat.WAV)
        this.formatButton(RecordingFormat.FLAC)
        this.formatButton(RecordingFormat.M4A)
      }.width('100%')
      if (this.target === RecordingFormat.M4A) {
        Row({ space: 8 }) {
          this.bitrateButton(128000, '128 kbps')
          this.bitrateButton(256000, '256 kbps')
        }.width('100%')
      }
      Text(this.explanation())
        .width('100%').attributeModifier(VisualTheme.text(TextRole.METADATA)).fontColor(HarmonyTokens.textSecondary())
      if (this.recording.config.bitDepth > 16) {
        Text('当前 FLAC 转换支持 16 bit；此录音可直接保存原始 WAV，保留 24 bit 精度。')
          .width('100%').attributeModifier(VisualTheme.text(TextRole.CAPTION)).fontColor(HarmonyTokens.textSecondary())
      }
      if (this.running) {
        Progress({ value: Math.round(this.progress * 100), total: 100, type: ProgressType.Linear })
          .width('100%').color(HarmonyTokens.primary())
        Text(this.cancelling ? '正在取消…' : `正在转换 ${Math.floor(this.progress * 100)}%`)
          .attributeModifier(VisualTheme.text(TextRole.METADATA)).fontColor(HarmonyTokens.textSecondary())
      }
      if (this.message.length > 0) {
        Text(this.message).width('100%').attributeModifier(VisualTheme.text(TextRole.METADATA)).fontColor(HarmonyTokens.danger())
      }
      Row({ space: 10 }) {
        Button(this.running ? '取消转换' : '返回')
          .layoutWeight(1).height(VisualTheme.CONTROL_HEIGHT).fontSize(VisualTheme.BODY_SIZE).fontWeight(FontWeight.Medium).fontColor(HarmonyTokens.textPrimary())
          .backgroundColor(HarmonyTokens.surfaceSubtle())
          .enabled(!this.cancelling)
          .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
          .onClick((): void => {
            if (this.running) {
              this.cancelling = true;
              this.service.cancel();
            } else { this.onBack(); }
          })
        Button('开始转换')
          .id('audio-conversion-start')
          .layoutWeight(1).height(VisualTheme.CONTROL_HEIGHT).fontSize(VisualTheme.BODY_SIZE).fontWeight(FontWeight.Medium).fontColor(HarmonyTokens.onPrimary())
          .backgroundColor(HarmonyTokens.primary()).enabled(!this.running)
          .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion, true))
          .onClick((): void => { this.convert(); })
      }.width('100%')
    }.width('100%')
  }

  @Builder
  private formatButton(format: RecordingFormat) {
    Button(format.toUpperCase())
      .id(`audio-conversion-${format}`)
      .layoutWeight(1).height(VisualTheme.CONTROL_HEIGHT).fontSize(VisualTheme.BODY_SIZE).fontWeight(FontWeight.Medium)
      .backgroundColor(this.target === format ? HarmonyTokens.primary() : HarmonyTokens.surfaceSubtle())
      .fontColor(this.target === format ? HarmonyTokens.onPrimary() : HarmonyTokens.textPrimary())
      .enabled(!this.running && !(format === RecordingFormat.FLAC && this.recording.config.bitDepth > 16) &&
        !(format === this.recording.config.format && format !== RecordingFormat.M4A))
      .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion, this.target === format))
      .onClick((): void => { this.target = format; this.message = ''; })
  }

  @Builder
  private bitrateButton(value: number, label: string) {
    Button(label).layoutWeight(1).height(VisualTheme.CONTROL_HEIGHT).fontSize(VisualTheme.BODY_SIZE).fontWeight(FontWeight.Medium)
      .backgroundColor(this.bitrate === value ? HarmonyTokens.primarySubtle() : HarmonyTokens.surfaceSubtle())
      .fontColor(HarmonyTokens.textPrimary()).enabled(!this.running)
      .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
      .onClick((): void => { this.bitrate = value; })
  }

  private explanation(): string {
    if (this.target === RecordingFormat.M4A) {
      return 'M4A 使用 AAC 有损压缩以减小体积。重复转码不会提升音质。完成后添加新录音，保留原件。';
    }
    if (this.recording.config.format === RecordingFormat.M4A) {
      return '将 AAC 解码为 PCM 后保存；不能恢复有损压缩时丢失的信息，文件可能更大。完成后保留原件。';
    }
    return 'WAV 与 FLAC 之间保留采样率和 PCM 样点，不改变音量。完成后添加新录音，保留原件。';
  }

  private async convert(): Promise<void> {
    if (this.running) { return; }
    this.running = true;
    this.cancelling = false;
    this.message = '';
    this.onRunning(true);
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result = await this.service.convert(context, this.recording, this.target, this.bitrate,
        (value: number): void => { if (!this.disposed) { this.progress = value; } });
      if (!this.disposed) {
        if (result !== undefined) { this.onComplete(result); } else { this.message = '已取消转换，原件已保留。'; }
      }
    } catch (error) {
      if (!this.disposed) { this.message = (error as Error).message || '转换失败，原件已保留。'; }
    } finally {
      if (!this.disposed) { this.running = false; this.cancelling = false; }
      this.onRunning(false);
    }
  }
}
