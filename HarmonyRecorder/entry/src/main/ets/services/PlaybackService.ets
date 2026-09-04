import { fileIo } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { RecordingInfo } from '../models/RecordingTypes';

export type PlaybackObserver = (isReady: boolean, isPlaying: boolean, positionMs: number,
  durationMs: number, message: string) => void;

export class PlaybackService {
  private player: media.AVPlayer | undefined = undefined;
  private sourceFile: fileIo.File | undefined = undefined;
  private observer: PlaybackObserver | undefined = undefined;
  private isReady: boolean = false;
  private isPlaying: boolean = false;
  private positionMs: number = 0;
  private durationMs: number = 0;
  private readyResolve: (() => void) | undefined = undefined;
  private readyReject: ((reason: Error) => void) | undefined = undefined;

  setObserver(observer: PlaybackObserver | undefined): void {
    this.observer = observer;
    this.notify('');
  }

  async load(recording: RecordingInfo): Promise<void> {
    await this.release();
    try {
      this.sourceFile = fileIo.openSync(recording.filePath, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(recording.filePath);
      this.player = await media.createAVPlayer();
      this.registerListeners(this.player);
      const readiness = new Promise<void>((resolve: () => void, reject: (reason: Error) => void): void => {
        this.readyResolve = resolve;
        this.readyReject = reject;
      });
      const descriptor: media.AVFileDescriptor = {
        fd: this.sourceFile.fd,
        offset: 0,
        length: stat.size
      };
      this.player.fdSrc = descriptor;
      await readiness;
    } catch (error) {
      await this.release();
      const message = `无法打开录音：${String(error)}`;
      this.notify(message);
      throw new Error(message);
    }
  }

  async toggle(): Promise<void> {
    const player = this.player;
    if (player === undefined || !this.isReady) {
      return;
    }
    try {
      if (player.state === 'playing') {
        await player.pause();
        return;
      }
      if (player.state === 'completed') {
        player.seek(0, media.SeekMode.SEEK_PREV_SYNC);
      }
      await player.play();
    } catch (error) {
      const message = `播放控制失败：${String(error)}`;
      this.notify(message);
      throw new Error(message);
    }
  }

  seek(positionMs: number): void {
    const player = this.player;
    if (player === undefined || !this.isReady) {
      return;
    }
    const target = Math.max(0, Math.min(Math.floor(positionMs), this.durationMs));
    try {
      player.seek(target, media.SeekMode.SEEK_PREV_SYNC);
      this.positionMs = target;
      this.notify('');
    } catch (error) {
      this.notify(`跳转播放失败：${String(error)}`);
    }
  }

  async release(): Promise<void> {
    this.readyResolve = undefined;
    this.readyReject = undefined;
    if (this.player !== undefined) {
      try {
        await this.player.release();
      } catch (error) {
        console.error(`Release AVPlayer failed: ${String(error)}`);
      }
      this.player = undefined;
    }
    if (this.sourceFile !== undefined) {
      try {
        fileIo.closeSync(this.sourceFile);
      } catch (error) {
        console.error(`Close playback file failed: ${String(error)}`);
      }
      this.sourceFile = undefined;
    }
    this.isReady = false;
    this.isPlaying = false;
    this.positionMs = 0;
    this.durationMs = 0;
    this.notify('');
  }

  private registerListeners(player: media.AVPlayer): void {
    player.on('stateChange', (state: media.AVPlayerState): void => {
      this.handleStateChange(state);
    });
    player.on('timeUpdate', (positionMs: number): void => {
      this.positionMs = positionMs;
      this.notify('');
    });
    player.on('durationUpdate', (durationMs: number): void => {
      this.durationMs = durationMs;
      this.notify('');
    });
    player.on('error', (error): void => {
      const message = `播放失败：${error.code}`;
      if (this.readyReject !== undefined) {
        this.readyReject(new Error(message));
        this.readyReject = undefined;
        this.readyResolve = undefined;
      }
      this.notify(message);
    });
  }

  private async handleStateChange(state: media.AVPlayerState): Promise<void> {
    if (this.player === undefined) {
      return;
    }
    try {
      if (state === 'initialized') {
        await this.player.prepare();
        return;
      }
      if (state === 'prepared') {
        this.isReady = true;
        this.durationMs = this.player.duration;
        if (this.readyResolve !== undefined) {
          this.readyResolve();
          this.readyResolve = undefined;
          this.readyReject = undefined;
        }
      }
      this.isPlaying = state === 'playing';
      if (state === 'completed') {
        this.positionMs = this.durationMs;
      }
      this.notify('');
    } catch (error) {
      const message = `准备播放器失败：${String(error)}`;
      if (this.readyReject !== undefined) {
        this.readyReject(new Error(message));
        this.readyReject = undefined;
        this.readyResolve = undefined;
      }
      this.notify(message);
    }
  }

  private notify(message: string): void {
    if (this.observer !== undefined) {
      this.observer(this.isReady, this.isPlaying, this.positionMs, this.durationMs, message);
    }
  }
}
