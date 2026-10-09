import { fileIo } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { RecordingInfo } from '../models/RecordingTypes';
import { RecordingRepository } from '../repository/RecordingRepository';

export type PlaybackObserver = (isReady: boolean, isPlaying: boolean, positionMs: number,
  durationMs: number, message: string) => void;

export class PlaybackService {
  private static readonly PREPARE_TIMEOUT_MS: number = 15000;
  private static readonly SEEK_TIMEOUT_MS: number = 8000;
  private static readonly CONTROL_TIMEOUT_MS: number = 8000;
  private player: media.AVPlayer | undefined = undefined;
  private sourceFile: fileIo.File | undefined = undefined;
  private observer: PlaybackObserver | undefined = undefined;
  private isReady: boolean = false;
  private isPlaying: boolean = false;
  private positionMs: number = 0;
  private durationMs: number = 0;
  private readyResolve: (() => void) | undefined = undefined;
  private readyReject: ((reason: Error) => void) | undefined = undefined;
  private generation: number = 0;
  private pendingRelease: Promise<void> = Promise.resolve();
  private message: string = '';
  private controlPending: boolean = false;
  private seeking: boolean = false;
  private queuedSeek: number | undefined = undefined;
  private pendingSeek: Promise<boolean> | undefined = undefined;
  private seekResolve: ((success: boolean) => void) | undefined = undefined;
  private prepareTimer: number = -1;
  private seekTimer: number = -1;

  setObserver(observer: PlaybackObserver | undefined): void {
    this.observer = observer;
    this.notify();
  }

  async load(recording: RecordingInfo, context: common.Context): Promise<RecordingInfo | undefined> {
    // Claim the load before awaiting cleanup so a later exit can cancel even
    // the first microtask, before a file or native player has been opened.
    const generation = ++this.generation;
    await this.releaseResources();
    if (generation !== this.generation) {
      return;
    }
    try {
      const inspected = RecordingRepository.inspectRecording(context, recording);
      this.sourceFile = fileIo.openSync(inspected.filePath, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(this.sourceFile.fd);
      if (stat.size <= 0) {
        throw new Error('录音文件为空');
      }
      const readiness = new Promise<void>((resolve: () => void, reject: (reason: Error) => void): void => {
        this.readyResolve = resolve;
        this.readyReject = reject;
      });
      const descriptor: media.AVFileDescriptor = {
        fd: this.sourceFile.fd,
        offset: 0,
        length: stat.size
      };
      const timer = setTimeout((): void => {
        if (this.prepareTimer === timer) {
          this.rejectPreparation(generation, new Error('播放器准备超时，请重新打开录音后重试'));
        }
      }, PlaybackService.PREPARE_TIMEOUT_MS);
      this.prepareTimer = timer;
      // Do not await an unbounded native factory. The readiness promise owns
      // both factory and prepare deadlines; late factories retain a cleanup path.
      this.createPlayerForLoad(generation, descriptor);
      await readiness;
      return generation === this.generation && this.isReady ? inspected : undefined;
    } catch (error) {
      if (generation !== this.generation) {
        return;
      }
      await this.releaseResources();
      if (generation !== this.generation) {
        return;
      }
      const message = `无法打开录音：${this.errorDetail(error as BusinessError)}`;
      this.notify(message);
      throw new Error(message);
    }
  }

  private async createPlayerForLoad(generation: number, descriptor: media.AVFileDescriptor): Promise<void> {
    try {
      const player = await media.createAVPlayer();
      if (generation !== this.generation || this.readyReject === undefined) {
        // Cancellation/timeout may already have closed the source. Never bind
        // that old descriptor or publish this result into a replacement load.
        await this.disposeResources(player, undefined, Promise.resolve());
        return;
      }
      this.player = player;
      this.registerListeners(player, generation);
      player.fdSrc = descriptor;
    } catch (error) {
      this.rejectPreparation(generation, error as Error);
    }
  }

  private rejectPreparation(generation: number, error: Error): void {
    if (generation !== this.generation || this.readyReject === undefined) {
      return;
    }
    const reject = this.readyReject;
    this.readyResolve = undefined;
    this.readyReject = undefined;
    this.clearPrepareTimer();
    reject(error);
    // Detach now, before a late prepared/error callback can revive this player.
    // The existing cleanup chain retains its FD until native release finishes.
    this.releaseResources(error.message);
  }

  private clearPrepareTimer(): void {
    if (this.prepareTimer >= 0) {
      clearTimeout(this.prepareTimer);
      this.prepareTimer = -1;
    }
  }

  async toggle(): Promise<void> {
    const player = this.player;
    const generation = this.generation;
    if (player === undefined || !this.isReady || this.controlPending) {
      return;
    }
    this.controlPending = true;
    this.notify('');
    try {
      if (player.state === 'playing') {
        await this.withControlDeadline(player.pause(), player, generation);
        return;
      }
      const pendingSeek = player.state === 'completed' ? this.seek(0) : this.pendingSeek;
      if (pendingSeek !== undefined && !(await pendingSeek)) {
        return;
      }
      if (!this.isCurrent(player, generation)) {
        return;
      }
      await this.withControlDeadline(player.play(), player, generation);
    } catch (error) {
      if (!this.isCurrent(player, generation)) {
        return;
      }
      const message = `播放控制失败：${this.errorDetail(error as BusinessError)}`;
      this.notify(message);
      throw new Error(message);
    } finally {
      if (generation === this.generation) {
        this.controlPending = false;
      }
    }
  }

  private async withControlDeadline(operation: Promise<void>, player: media.AVPlayer,
    generation: number): Promise<void> {
    let timer = -1;
    try {
      await Promise.race([operation, new Promise<void>((resolve: () => void, reject: (error: Error) => void): void => {
        timer = setTimeout((): void => {
          const message = '播放控制超时，请重新打开录音后重试';
          reject(new Error(message));
          if (this.isCurrent(player, generation)) {
            // Detach before a late native play/pause completion can revive this
            // instance or leave every subsequent button press blocked.
            this.releaseResources(message);
          }
        }, PlaybackService.CONTROL_TIMEOUT_MS);
      })]);
    } finally {
      if (timer >= 0) { clearTimeout(timer); }
    }
  }

  seek(positionMs: number): Promise<boolean> {
    const player = this.player;
    if (player === undefined || !this.isReady || !Number.isFinite(positionMs)) {
      return Promise.resolve(false);
    }
    const target = Math.max(0, Math.min(Math.floor(positionMs), this.durationMs));
    this.message = '';
    this.positionMs = target;
    if (this.seeking) {
      // Native seek is asynchronous. Keep only the newest requested position,
      // rather than issuing overlapping seeks with indistinguishable callbacks.
      this.queuedSeek = target;
      this.notify();
      return this.pendingSeek || Promise.resolve(false);
    }
    const pendingSeek = new Promise<boolean>((resolve: (success: boolean) => void): void => {
      this.seekResolve = resolve;
    });
    this.pendingSeek = pendingSeek;
    this.issueSeek(player, target);
    return pendingSeek;
  }

  private issueSeek(player: media.AVPlayer, target: number): void {
    this.clearSeekTimer();
    this.seeking = true;
    const generation = this.generation;
    const timer = setTimeout((): void => {
      if (this.seekTimer !== timer || !this.isCurrent(player, generation) || !this.seeking) {
        return;
      }
      // seekDone has no request ID. Reusing this native instance after a
      // timeout could mistake its late callback for a retry's completion.
      this.releaseResources('跳转播放超时，请重新打开录音后重试');
    }, PlaybackService.SEEK_TIMEOUT_MS);
    this.seekTimer = timer;
    try {
      player.seek(target, media.SeekMode.SEEK_PREV_SYNC);
      this.notify();
    } catch (error) {
      this.finishSeek(false);
      this.notify(`跳转播放失败：${this.errorDetail(error as BusinessError)}`);
    }
  }

  private finishSeek(success: boolean): void {
    this.clearSeekTimer();
    const resolve = this.seekResolve;
    this.seeking = false;
    this.queuedSeek = undefined;
    this.pendingSeek = undefined;
    this.seekResolve = undefined;
    if (resolve !== undefined) {
      resolve(success);
    }
  }

  private clearSeekTimer(): void {
    if (this.seekTimer >= 0) {
      clearTimeout(this.seekTimer);
      this.seekTimer = -1;
    }
  }

  async release(): Promise<void> {
    ++this.generation;
    await this.releaseResources();
  }

  private async releaseResources(message: string = ''): Promise<void> {
    this.clearPrepareTimer();
    // Detach synchronously. Awaiting a native release must never leave it able
    // to clear a newer load's fields or close the newer load's descriptor.
    const player = this.player;
    const sourceFile = this.sourceFile;
    const cancelledLoad = this.readyResolve;
    this.player = undefined;
    this.sourceFile = undefined;
    this.readyResolve = undefined;
    this.readyReject = undefined;
    this.controlPending = false;
    this.finishSeek(false);
    this.isReady = false;
    this.isPlaying = false;
    this.positionMs = 0;
    this.durationMs = 0;
    if (cancelledLoad !== undefined) {
      // Cancellation is a silent completion, rather than an opening error on
      // an already closed page. It must still settle the pending load promise.
      cancelledLoad();
    }
    this.notify(message);
    const cleanup = this.disposeResources(player, sourceFile, this.pendingRelease);
    this.pendingRelease = cleanup;
    await cleanup;
  }

  private async disposeResources(player: media.AVPlayer | undefined, sourceFile: fileIo.File | undefined,
    previousRelease: Promise<void>): Promise<void> {
    await previousRelease;
    if (player !== undefined) {
      try {
        await player.release();
      } catch (error) {
        console.error(`Release AVPlayer failed: ${String(error)}`);
      }
    }
    if (sourceFile !== undefined) {
      try {
        fileIo.closeSync(sourceFile);
      } catch (error) {
        console.error(`Close playback file failed: ${String(error)}`);
      }
    }
  }

  private isCurrent(player: media.AVPlayer, generation: number): boolean {
    return this.player === player && this.generation === generation;
  }

  private registerListeners(player: media.AVPlayer, generation: number): void {
    player.on('stateChange', (state: media.AVPlayerState): void => {
      this.handleStateChange(player, generation, state);
    });
    player.on('timeUpdate', (positionMs: number): void => {
      if (!this.isCurrent(player, generation) || this.seeking || !Number.isFinite(positionMs) || positionMs < 0) {
        return;
      }
      this.positionMs = Math.min(positionMs, this.durationMs);
      this.notify();
    });
    player.on('durationUpdate', (durationMs: number): void => {
      if (!this.isCurrent(player, generation) || !Number.isFinite(durationMs) || durationMs <= 0) {
        return;
      }
      this.durationMs = durationMs;
      this.notify();
    });
    player.on('seekDone', (positionMs: number): void => {
      if (!this.isCurrent(player, generation) || !this.seeking) {
        return;
      }
      const next = this.queuedSeek;
      this.queuedSeek = undefined;
      if (next !== undefined) {
        this.issueSeek(player, next);
        return;
      }
      this.finishSeek(true);
      if (Number.isFinite(positionMs) && positionMs >= 0) {
        this.positionMs = Math.min(positionMs, this.durationMs);
      }
      this.notify();
    });
    player.on('audioInterrupt', (event: audio.InterruptEvent): void => {
      if (!this.isCurrent(player, generation)) {
        return;
      }
      if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE ||
        event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
        this.isPlaying = false;
        this.notify('播放已被其他音频打断，可点击播放继续');
        if (event.forceType === audio.InterruptForceType.INTERRUPT_SHARE && player.state === 'playing') {
          this.pauseForInterruption(player, generation);
        }
      }
    });
    player.on('audioOutputDeviceChangeWithInfo', (event: audio.AudioStreamDeviceChangeInfo): void => {
      if (!this.isCurrent(player, generation)) {
        return;
      }
      if (event.changeReason === audio.AudioStreamDeviceChangeReason.REASON_OLD_DEVICE_UNAVAILABLE) {
        this.notify('音频输出设备已断开，播放已暂停');
        this.pauseForInterruption(player, generation);
      }
    });
    player.on('error', (error): void => {
      if (!this.isCurrent(player, generation)) {
        return;
      }
      const message = `播放失败：${this.errorDetail(error)}`;
      if (this.readyReject !== undefined) {
        this.rejectPreparation(generation, new Error(message));
      } else {
        // A runtime decode/output error invalidates the prepared state. Keep
        // the reason visible while closing the native player and its source.
        this.releaseResources(message);
      }
      this.notify(message);
    });
  }

  private async handleStateChange(player: media.AVPlayer, generation: number,
    state: media.AVPlayerState): Promise<void> {
    if (!this.isCurrent(player, generation)) {
      return;
    }
    try {
      if (state === 'initialized') {
        player.audioRendererInfo = { usage: audio.StreamUsage.STREAM_USAGE_MUSIC, rendererFlags: 0 };
        await player.prepare();
        return;
      }
      if (state === 'prepared') {
        player.audioInterruptMode = audio.InterruptMode.INDEPENDENT_MODE;
        player.setVolume(1);
        this.isReady = true;
        this.durationMs = Math.max(0, player.duration);
        this.message = '';
        this.clearPrepareTimer();
        if (this.readyResolve !== undefined) {
          this.readyResolve();
          this.readyResolve = undefined;
          this.readyReject = undefined;
        }
      }
      this.isPlaying = state === 'playing';
      if (state === 'playing') {
        this.message = '';
      }
      if (state === 'error' || state === 'stopped' || state === 'released') {
        this.isReady = false;
      }
      if (state === 'completed' && !this.seeking) {
        this.positionMs = this.durationMs;
      }
      this.notify();
    } catch (error) {
      if (!this.isCurrent(player, generation)) {
        return;
      }
      const message = `准备播放器失败：${this.errorDetail(error as BusinessError)}`;
      if (this.readyReject !== undefined) {
        this.rejectPreparation(generation, new Error(message));
      }
      this.notify(message);
    }
  }

  private async pauseForInterruption(player: media.AVPlayer, generation: number): Promise<void> {
    if (player.state !== 'playing') {
      return;
    }
    try {
      await player.pause();
    } catch (error) {
      if (this.isCurrent(player, generation)) {
        this.notify(`暂停播放失败：${this.errorDetail(error as BusinessError)}`);
      }
    }
  }

  private errorDetail(error: BusinessError): string {
    const detail = error.message || String(error);
    return typeof error.code === 'number' ? `${detail}（错误码 ${error.code}）` : detail;
  }

  private notify(message?: string): void {
    if (message !== undefined) {
      this.message = message;
    }
    if (this.observer !== undefined) {
      try {
        this.observer(this.isReady, this.isPlaying, this.positionMs, this.durationMs, this.message);
      } catch (error) {
        console.error(`Playback observer failed: ${String(error)}`);
      }
    }
  }
}
