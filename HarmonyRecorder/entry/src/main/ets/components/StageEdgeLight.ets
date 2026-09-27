import { RecordingState } from '../models/RecordingTypes';
import { NavigationStore } from '../utils/NavigationStore';
import { WaveformMotion } from '../utils/WaveformMotion';
import { ThemeMode } from '../utils/HarmonyTheme';
import { CanvasFrameDriver } from '../utils/CanvasFrameDriver';
import { MotionTheme } from '../utils/MotionTheme';

// One edge stroke, no blur or shadow. Never runs outside foreground recording.
@Component
export struct StageEdgeLight {
  @Prop @Watch('syncMotion') recordingState: RecordingState = RecordingState.IDLE;
  @Prop @Watch('syncMotion') isVisible: boolean = true;
  @Prop @Watch('syncMotion') accentColor: string = '#C85A10';
  @Prop @Watch('syncMotion') themeMode: number = ThemeMode.LIGHT;
  @StorageLink(NavigationStore.FOREGROUND_KEY) @Watch('syncMotion') private foreground: boolean = true;
  @StorageLink(MotionTheme.REDUCE_KEY) @Watch('syncMotion') private reduceMotion: boolean = false;
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private readonly frames: CanvasFrameDriver = new CanvasFrameDriver();
  private widthVp: number = 0;
  private heightVp: number = 0;
  private ready: boolean = false;
  private areaVisible: boolean = true;
  private elapsedMs: number = 0;

  aboutToDisappear(): void {
    this.frames.release();
    this.ready = false;
  }

  build() {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
      .onReady((): void => {
        this.ready = true;
        this.syncMotion();
      })
      .onAreaChange((oldArea: Area, area: Area): void => {
        this.widthVp = Number(area.width);
        this.heightVp = Number(area.height);
        this.syncMotion();
      })
      .onVisibleAreaChange([0, 1], (visible: boolean, ratio: number): void => {
        this.areaVisible = visible && ratio > 0;
        this.syncMotion();
      })
  }

  private syncMotion(): void {
    if (!this.ready) {
      this.frames.stop();
      return;
    }
    if (!this.isVisible || !this.foreground || !this.areaVisible) {
      this.frames.stop();
      return;
    }
    if (!WaveformMotion.showsHistory(this.recordingState)) {
      this.elapsedMs = 0;
    }
    this.draw();
    if (WaveformMotion.shouldAnimate(this.recordingState, this.isVisible && this.areaVisible,
      this.foreground, this.reduceMotion)) {
      this.frames.start(this.getUIContext(), (deltaMs: number): void => {
        if (deltaMs > 0) {
          this.elapsedMs = (this.elapsedMs + deltaMs) % 6000;
          this.draw();
        }
      });
    } else {
      this.frames.stop();
    }
  }

  private draw(): void {
    const w = this.widthVp;
    const h = this.heightVp;
    if (w <= 0 || h <= 0 || !Number.isFinite(w) || !Number.isFinite(h)) {
      return;
    }
    const ctx = this.context;
    const active = this.recordingState === RecordingState.RECORDING;
    const angle = WaveformMotion.showsHistory(this.recordingState) ?
      this.elapsedMs / 6000 * Math.PI * 2 - Math.PI * 0.65 : -Math.PI * 0.65;
    const dx = Math.cos(angle) * w / 2;
    const dy = Math.sin(angle) * h / 2;
    const gradient = ctx.createLinearGradient(w / 2 - dx, h / 2 - dy, w / 2 + dx, h / 2 + dy);
    gradient.addColorStop(0, 'rgba(0, 0, 0, 0)');
    gradient.addColorStop(0.62, 'rgba(0, 0, 0, 0)');
    gradient.addColorStop(1, active ? this.accentColor :
      (this.themeMode === ThemeMode.DARK ? '#FFEAD7' : '#FFFFFF'));
    ctx.clearRect(0, 0, w, h);
    ctx.globalAlpha = active ? 0.68 : (this.themeMode === ThemeMode.DARK ? 0.24 : 0.88);
    ctx.strokeStyle = gradient;
    ctx.lineWidth = 1.2;
    const inset = 1;
    const r = Math.min(28, w / 2, h / 2) - inset;
    ctx.beginPath();
    ctx.moveTo(r + inset, inset);
    ctx.lineTo(w - r - inset, inset);
    ctx.arcTo(w - inset, inset, w - inset, r + inset, r);
    ctx.lineTo(w - inset, h - r - inset);
    ctx.arcTo(w - inset, h - inset, w - r - inset, h - inset, r);
    ctx.lineTo(r + inset, h - inset);
    ctx.arcTo(inset, h - inset, inset, h - r - inset, r);
    ctx.lineTo(inset, r + inset);
    ctx.arcTo(inset, inset, r + inset, inset, r);
    ctx.closePath();
    ctx.stroke();
  }
}
