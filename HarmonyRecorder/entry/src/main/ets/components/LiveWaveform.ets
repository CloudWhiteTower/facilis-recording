import { RecordingState } from '../models/RecordingTypes';
import { HarmonyPalette, HarmonyTheme, ThemeMode } from '../utils/HarmonyTheme';
import { WaveformUtils } from '../utils/WaveformUtils';
import { WaveformMotion, WaveformScroll } from '../utils/WaveformMotion';
import { WaveformCurve, WaveformGeometry, WaveSegment } from '../utils/WaveformCurve';
import { NavigationStore } from '../utils/NavigationStore';
import { CanvasFrameDriver } from '../utils/CanvasFrameDriver';
import { MotionTheme } from '../utils/MotionTheme';

@Component
export struct LiveWaveform {
  @Prop @Watch('onSamplesChanged') values: number[] = [];
  @Prop @Watch('onStateChanged') recordingState: RecordingState = RecordingState.IDLE;
  @Prop @Watch('onVisibilityChanged') isVisible: boolean = true;
  @Prop sampleIntervalMs: number = WaveformMotion.SAMPLE_INTERVAL_MS;
  @Prop @Watch('requestDraw') accentColor: string = '#C85A10';
  @Prop @Watch('requestDraw') dbFloor: number = -48;
  @Prop @Watch('requestDraw') dbCeiling: number = 0;
  @StorageLink(NavigationStore.FOREGROUND_KEY) @Watch('onVisibilityChanged') private foreground: boolean = true;
  @StorageLink(MotionTheme.REDUCE_KEY) @Watch('onVisibilityChanged') private reduceMotion: boolean = false;
  @Prop @Watch('requestDraw') themeMode: number = ThemeMode.LIGHT;
  @Prop @Watch('requestDraw') renderHeight: number = 88;
  private readonly contextSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.contextSettings);
  private canvasWidth: number = 0;
  private canvasReady: boolean = false;
  private areaVisible: boolean = true;
  private previousState: RecordingState = RecordingState.IDLE;
  private readonly frames: CanvasFrameDriver = new CanvasFrameDriver();
  private readonly scroll: WaveformScroll = new WaveformScroll();
  private readonly geometry: WaveformGeometry = new WaveformGeometry();
  private strokeGradient: CanvasGradient | undefined = undefined;
  private fillGradient: CanvasGradient | undefined = undefined;
  private gradientKey: string = '';

  aboutToAppear(): void {
    this.scroll.reset(this.values);
  }

  aboutToDisappear(): void {
    this.frames.release();
    this.canvasReady = false;
  }

  build() {
    Row({ space: 10 }) {
      Stack() {
        Canvas(this.context)
          .width('100%')
          .height(this.renderHeight)
          .onReady((): void => {
            this.canvasReady = true;
            this.gradientKey = '';
            this.onStateChanged();
          })
          .onAreaChange((oldValue: Area, newValue: Area): void => {
            const width = Number(newValue.width);
            if (Number.isFinite(width) && Math.abs(width - this.canvasWidth) >= 1) {
              this.canvasWidth = width;
              this.requestDraw();
            }
          })
          .onVisibleAreaChange([0, 1], (visible: boolean, ratio: number): void => {
            this.areaVisible = visible && ratio > 0;
            this.onVisibilityChanged();
          })
      }
      .layoutWeight(1)
      .height(this.renderHeight)

      this.levelScale()
    }
    .width('100%')
    .height(this.renderHeight)
    .alignItems(VerticalAlign.Bottom)
  }

  private requestDraw(): void {
    if (this.isVisible && this.foreground && this.areaVisible) {
      this.drawWaveform();
    }
  }

  private onSamplesChanged(): void {
    if (this.recordingState !== RecordingState.RECORDING) {
      return;
    }
    if (this.reduceMotion || !this.isVisible || !this.foreground || !this.areaVisible) {
      // Static mode still follows measured samples; there is no synthetic motion.
      this.scroll.reset(this.values);
      this.requestDraw();
      return;
    }
    this.scroll.offer(this.values);
  }

  private onStateChanged(): void {
    if (this.recordingState === RecordingState.RECORDING) {
      if (this.previousState !== RecordingState.PAUSED && this.previousState !== RecordingState.RECORDING) {
        this.scroll.reset(this.values);
      }
    } else if (!WaveformMotion.showsHistory(this.recordingState)) {
      this.scroll.reset([]);
    }
    this.previousState = this.recordingState;
    this.onVisibilityChanged();
  }

  private onVisibilityChanged(): void {
    if (this.reduceMotion && this.recordingState === RecordingState.RECORDING) {
      this.scroll.reset(this.values);
    }
    this.requestDraw();
    if (this.canvasReady && WaveformMotion.shouldAnimate(this.recordingState,
      this.isVisible && this.areaVisible, this.foreground, this.reduceMotion)) {
      this.frames.start(this.getUIContext(), (deltaMs: number): void => {
        if (this.scroll.advance(deltaMs, this.sampleIntervalMs)) {
          this.drawWaveform();
        }
      });
    } else {
      this.frames.stop();
    }
  }

  private drawWaveform(): void {
    if (!this.canvasReady || this.canvasWidth <= 0 || this.renderHeight <= 0) {
      return;
    }
    const width = this.canvasWidth;
    const height = this.renderHeight;
    this.context.clearRect(0, 0, width, height);
    this.drawBaseline(width, height);
    if (!WaveformMotion.showsHistory(this.recordingState)) {
      return;
    }
    this.drawGuides(width, height);

    this.geometry.update(this.scroll.values, width, height, this.dbFloor, this.dbCeiling);
    const points = this.geometry.points;
    const segments = this.geometry.segments;
    const shift = this.geometry.scrollOffset(this.scroll.scrollPhase);
    if (segments.length === 0) {
      return;
    }
    this.updateGradients(width);
    const fill = this.fillGradient;
    const stroke = this.strokeGradient;
    if (fill === undefined || stroke === undefined) { return; }
    this.context.save();
    this.context.beginPath();
    this.context.rect(0, 0, width - 3, height);
    this.context.clip();
    this.traceCurve(segments, shift);
    this.context.lineTo(points[points.length - 1].x + shift, height - 3);
    this.context.lineTo(points[0].x + shift, height - 3);
    this.context.closePath();
    this.context.fillStyle = fill;
    this.context.fill();

    this.traceCurve(segments, shift);
    this.context.strokeStyle = stroke;
    this.context.lineWidth = 1.8;
    this.context.lineCap = 'round';
    this.context.lineJoin = 'round';
    this.context.shadowBlur = 0;
    this.context.stroke();
    if (this.recordingState === RecordingState.RECORDING) {
      this.context.beginPath();
      this.context.rect(width * (1 - WaveformUtils.LIVE_FRACTION), 0, width, height);
      this.context.clip();
      this.traceCurve(segments, shift);
      this.context.shadowColor = this.waveColor(0.38);
      this.context.shadowBlur = 6;
      this.context.stroke();
    }
    this.context.restore();
    if (this.recordingState === RecordingState.RECORDING) {
      this.drawLiveHead(segments[segments.length - 1], shift);
    }
  }

  private updateGradients(width: number): void {
    const key = `${width}:${this.recordingState}:${this.accentColor}:${this.themeMode}`;
    if (this.gradientKey === key && this.strokeGradient !== undefined && this.fillGradient !== undefined) { return; }
    const gradient = this.context.createLinearGradient(0, 0, width, 0);
    if (this.recordingState === RecordingState.PAUSED) {
      gradient.addColorStop(0, this.waveColor(0));
      gradient.addColorStop(WaveformUtils.FADE_FRACTION, this.pausedWaveColor(0.46));
      gradient.addColorStop(1, this.pausedWaveColor(0.62));
    } else {
      gradient.addColorStop(0, this.waveColor(0));
      gradient.addColorStop(WaveformUtils.FADE_FRACTION, this.waveColor(0.68));
      gradient.addColorStop(1 - WaveformUtils.LIVE_FRACTION, this.waveColor(0.86));
      gradient.addColorStop(1, this.waveColor(1));
    }

    const fill = this.context.createLinearGradient(0, 0, width, 0);
    fill.addColorStop(0, this.waveColor(0));
    fill.addColorStop(WaveformUtils.FADE_FRACTION, this.waveColor(0.035));
    fill.addColorStop(1, this.recordingState === RecordingState.PAUSED ?
      this.pausedWaveColor(0.065) : this.waveColor(0.14));
    this.strokeGradient = gradient;
    this.fillGradient = fill;
    this.gradientKey = key;
  }

  private traceCurve(segments: WaveSegment[], shift: number): void {
    this.context.beginPath();
    this.context.moveTo(segments[0].start.x + shift, segments[0].start.y);
    for (const segment of segments) {
      this.context.bezierCurveTo(segment.first.x + shift, segment.first.y,
        segment.second.x + shift, segment.second.y, segment.end.x + shift, segment.end.y);
    }
  }

  private drawGuides(width: number, height: number): void {
    this.context.lineWidth = 0.6;
    this.context.strokeStyle = this.guideColor();
    this.context.shadowBlur = 0;
    const marks: number[] = WaveformUtils.decibelMarks(this.dbFloor, this.dbCeiling);
    for (let index = 0; index < marks.length; index++) {
      const y = 3 + WaveformUtils.decibelY(marks[index], height - 6, this.dbFloor, this.dbCeiling);
      this.context.beginPath();
      this.context.moveTo(0, y);
      this.context.lineTo(width, y);
      this.context.stroke();
    }
  }

  private drawBaseline(width: number, height: number): void {
    this.context.globalAlpha = this.recordingState === RecordingState.IDLE ? 0.72 : 0.42;
    this.context.strokeStyle = this.recordingState === RecordingState.RECORDING ? this.waveColor(0.72) :
      this.pausedWaveColor(0.62);
    this.context.lineWidth = this.recordingState === RecordingState.IDLE ? 1.2 : 0.8;
    this.context.beginPath();
    this.context.moveTo(3, height - 3);
    this.context.lineTo(width - 3, height - 3);
    this.context.stroke();
    this.context.globalAlpha = 1;
  }

  private drawLiveHead(segment: WaveSegment, shift: number): void {
    const head = WaveformCurve.at(segment, this.scroll.scrollPhase);
    this.context.fillStyle = this.waveColor(1);
    this.context.shadowColor = this.waveColor(0.72);
    this.context.shadowBlur = 12;
    this.context.beginPath();
    this.context.arc(head.x + shift, head.y, 2.4, 0, Math.PI * 2);
    this.context.fill();
    this.context.shadowBlur = 0;
  }

  private waveColor(alpha: number): string {
    const color = this.accentColor.replace('#', '');
    return `rgba(${parseInt(color.substring(0, 2), 16)}, ${parseInt(color.substring(2, 4), 16)}, ` +
      `${parseInt(color.substring(4, 6), 16)}, ${alpha})`;
  }

  private pausedWaveColor(alpha: number): string {
    return this.themeMode === ThemeMode.DARK ? `rgba(197, 161, 124, ${alpha})` :
      `rgba(169, 138, 108, ${alpha})`;
  }

  private guideColor(): string {
    return this.themeMode === ThemeMode.DARK ? 'rgba(255, 221, 193, 0.12)' : 'rgba(91, 57, 31, 0.10)';
  }

  @Builder
  private levelScale() {
    Column({ space: 0 }) {
      ForEach(WaveformUtils.decibelMarks(this.dbFloor, this.dbCeiling), (mark: number, index: number) => {
        this.levelMark(`${Math.round(mark)}${index === 4 ? ' dB' : ''}`)
      }, (mark: number): string => `${mark}`)
    }
    .width(42)
    .height(this.renderHeight)
    .alignItems(HorizontalAlign.End)
    .justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder
  private levelMark(label: string) {
    Text(label)
      .fontSize(10)
      .fontColor(this.palette().textTertiary)
  }

  private palette(): HarmonyPalette {
    return HarmonyTheme.palette(this.themeMode);
  }
}
