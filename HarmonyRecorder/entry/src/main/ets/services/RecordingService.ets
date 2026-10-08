import { common } from '@kit.AbilityKit';
import { audio } from '@kit.AudioKit';
import { fileIo } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { systemDateTime } from '@kit.BasicServicesKit';
import flac from 'libfacilis_flac.so';
import { RecordingConfig, RecordingFormat, RecordingInfo, RecordingSnapshot, RecordingState } from '../models/RecordingTypes';
import { RecordingRepository } from '../repository/RecordingRepository';
import { WaveFileUtils } from '../utils/WaveFileUtils';
import { WaveformUtils } from '../utils/WaveformUtils';
import { PcmStreamUtils, PcmWriteCursor } from '../utils/PcmStreamUtils';
import { BackgroundRecordingTask } from './BackgroundRecordingTask';

export type RecordingObserver = (snapshot: RecordingSnapshot) => void;

export class RecordingService {
  private static readonly PCM_STALL_TIMEOUT_MS: number = 5000;
  private static readonly WAV_CHECKPOINT_SECONDS: number = 5;
  private static instance: RecordingService | undefined = undefined;
  private state: RecordingState = RecordingState.IDLE;
  private durationMs: number = 0;
  private accumulatedDurationMs: number = 0;
  private segmentStartedAt: number = 0;
  private timerId: number = -1;
  private observer: RecordingObserver | undefined = undefined;
  private context: common.Context | undefined = undefined;
  private activeRecording: RecordingInfo | undefined = undefined;
  private activeConfig: RecordingConfig | undefined = undefined;
  private operationBusy: boolean = false;
  private pendingStopReason: string = '';
  private readonly backgroundTask: BackgroundRecordingTask = new BackgroundRecordingTask();

  private avRecorder: media.AVRecorder | undefined = undefined;
  private avFile: fileIo.File | undefined = undefined;
  private amplitudeTimerId: number = -1;
  private amplitudeReadPromise: Promise<void> | undefined = undefined;
  private amplitudeGeneration: number = 0;

  private pcmCapturer: audio.AudioCapturer | undefined = undefined;
  private pcmFile: fileIo.File | undefined = undefined;
  private pcmDataBytes: number = 0;
  private pcmPendingBytes: number = 0;
  private pcmReadCallback: ((buffer: ArrayBuffer) => void) | undefined = undefined;
  private pcmWriteQueue: Array<ArrayBuffer> = [];
  private pcmWritePromise: Promise<void> | undefined = undefined;
  private pcmWriteFailure: string = '';
  private pcmCheckpointBytes: number = 0;
  private lastPcmPacketAt: number = 0;
  private flacHandle: number = -1;
  private liveSizeBytes: number = 0;
  private waveformSamples: number[] = [];
  private lastWaveformSampleAt: number = 0;
  private readonly waveformSampleIntervalMs: number = 90;

  static getInstance(): RecordingService {
    if (RecordingService.instance === undefined) {
      RecordingService.instance = new RecordingService();
    }
    return RecordingService.instance;
  }

  setObserver(observer: RecordingObserver | undefined): void {
    this.observer = observer;
    this.notify('');
  }

  getState(): RecordingState { return this.state; }
  getDuration(): number { return this.getCurrentDuration(); }

  async start(context: common.Context, config: RecordingConfig): Promise<void> {
    this.beginOperation();
    try {
      if (this.state === RecordingState.RECORDING || this.state === RecordingState.PAUSED) {
        throw new Error('A recording is already in progress.');
      }
      if (this.pcmCapturer !== undefined || this.avRecorder !== undefined) {
        await this.releaseResources();
        if (this.pcmCapturer !== undefined || this.avRecorder !== undefined) {
          throw new Error('上次录音资源尚未释放，无法开启新的麦克风采集。');
        }
      }
      // Retry a previously failed task cancellation before opening another microphone.
      await this.backgroundTask.stop();
      this.context = context;
      this.activeConfig = config;
      this.activeRecording = RecordingRepository.createNewRecording(context, config);
      this.durationMs = 0;
      this.accumulatedDurationMs = 0;
      this.segmentStartedAt = 0;
      this.liveSizeBytes = 0;
      this.waveformSamples = [];
      this.lastWaveformSampleAt = 0;
      this.pendingStopReason = '';
      this.pcmDataBytes = 0;
      this.pcmPendingBytes = 0;
      this.pcmWriteFailure = '';
      this.pcmWriteQueue = [];
      try {
        if (config.format === RecordingFormat.M4A) {
          await this.startM4a(config);
        } else {
          await this.startPcm(config);
        }
        this.state = RecordingState.RECORDING;
        this.segmentStartedAt = this.monotonicNow();
        this.startDurationTimer();
        try {
          await this.startBackgroundTask();
        } catch (error) {
          this.pendingStopReason = String(error);
          await this.finishRecording();
          throw new Error(`后台录音任务开启失败，录音已停止：${String(error)}`);
        }
        this.notify('');
      } catch (error) {
        const failed = this.activeRecording;
        await this.releaseResources();
        if (failed !== undefined && this.pcmDataBytes === 0) {
          this.discardEmptyFile(failed);
        }
        this.clearActiveRecording(RecordingState.IDLE);
        const message = `无法开始录音：${String(error)}`;
        this.notify(message);
        throw new Error(message);
      }
    } finally {
      this.endOperation();
    }
  }

  async pause(): Promise<void> {
    this.beginOperation();
    try {
      if (this.state !== RecordingState.RECORDING || this.activeConfig === undefined) {
        return;
      }
      try {
        if (this.activeConfig.format !== RecordingFormat.M4A) {
          await this.disposePcmCapturer(true);
          await this.flushPcmWrites();
          await this.checkpointWav(this.activeConfig, true);
        } else if (this.avRecorder !== undefined) {
          await this.stopAmplitudePolling();
          await this.avRecorder.pause();
        }
        this.accumulatedDurationMs = this.getCurrentDuration();
        this.durationMs = this.accumulatedDurationMs;
        this.segmentStartedAt = 0;
        this.stopDurationTimer();
        this.state = RecordingState.PAUSED;
        const cleanupWarning = await this.stopBackgroundTask();
        this.notify(cleanupWarning);
      } catch (error) {
        this.requestStop(`暂停录音失败，已停止采集：${String(error)}`);
        throw new Error(String(error));
      }
    } finally {
      this.endOperation();
    }
  }

  async resume(): Promise<void> {
    this.beginOperation();
    try {
      if (this.state !== RecordingState.PAUSED || this.activeConfig === undefined) {
        return;
      }
      try {
        if (this.activeConfig.format !== RecordingFormat.M4A) {
          await this.createAndStartPcmCapturer(this.activeConfig);
        } else if (this.avRecorder !== undefined) {
          await this.avRecorder.resume();
          this.startAmplitudePolling();
        }
        this.segmentStartedAt = this.monotonicNow();
        this.state = RecordingState.RECORDING;
        try {
          await this.startBackgroundTask();
        } catch (error) {
          // A failed background lease must not leave a microphone recording.
          if (this.activeConfig.format !== RecordingFormat.M4A) {
            await this.disposePcmCapturer(true);
            await this.flushPcmWrites();
          } else if (this.avRecorder !== undefined) {
            await this.stopAmplitudePolling();
            await this.avRecorder.pause();
          }
          this.accumulatedDurationMs = this.getCurrentDuration();
          this.durationMs = this.accumulatedDurationMs;
          this.segmentStartedAt = 0;
          this.state = RecordingState.PAUSED;
          await this.stopBackgroundTask();
          throw new Error(`后台任务开启失败，录音保持暂停：${String(error)}`);
        }
        this.startDurationTimer();
        this.notify('');
      } catch (error) {
        if (this.state !== RecordingState.PAUSED || this.pcmCapturer !== undefined) {
          this.requestStop(`继续录音失败，已停止采集：${String(error)}`);
        }
        this.notify(String(error));
        throw new Error(String(error));
      }
    } finally {
      this.endOperation();
    }
  }

  async stop(): Promise<RecordingInfo | undefined> {
    this.beginOperation();
    try {
      return await this.finishRecording();
    } finally {
      this.endOperation();
    }
  }

  private async finishRecording(): Promise<RecordingInfo | undefined> {
    if (this.activeRecording === undefined || this.activeConfig === undefined || this.context === undefined) {
      return undefined;
    }
    const recording = this.activeRecording;
    const config = this.activeConfig;
    const context = this.context;
    this.durationMs = this.getCurrentDuration();
    this.stopDurationTimer();
    try {
      if (config.format === RecordingFormat.M4A) {
        await this.stopM4a();
      } else {
        await this.finishPcm(config);
        this.durationMs = PcmStreamUtils.durationMs(this.pcmDataBytes, config);
      }
      const cleanupWarning = await this.stopBackgroundTask();
      recording.durationMs = this.durationMs;
      recording.sizeBytes = fileIo.statSync(recording.filePath).size;
      this.liveSizeBytes = recording.sizeBytes;
      if (config.format !== RecordingFormat.M4A && this.pcmDataBytes === 0) {
        this.discardEmptyFile(recording);
        throw new Error('没有可保存的音频样点。');
      }
      const verified = RecordingRepository.save(context, recording);
      this.durationMs = verified.durationMs;
      this.liveSizeBytes = verified.sizeBytes;
      const warning = this.pendingStopReason || this.pcmWriteFailure || cleanupWarning;
      this.clearActiveRecording(RecordingState.STOPPED);
      this.notify(warning.length > 0 ? `录音已停止并保存可用部分。${warning}` : '');
      return verified;
    } catch (error) {
      await this.releaseResources();
      // Preserve nonempty files for recovery instead of deleting captured audio.
      if (config.format !== RecordingFormat.M4A && this.pcmDataBytes === 0) {
        this.discardEmptyFile(recording);
      }
      this.clearActiveRecording(RecordingState.STOPPED);
      const message = `保存录音失败，已停止采集：${String(error)}`;
      this.notify(message);
      throw new Error(message);
    }
  }

  async discard(): Promise<void> {
    this.beginOperation();
    try {
      const recording = this.activeRecording;
      if (recording === undefined) {
        return;
      }
      await this.releaseResources();
      RecordingRepository.discardTemporary(recording);
      this.clearActiveRecording(RecordingState.IDLE);
      this.durationMs = 0;
      this.liveSizeBytes = 0;
      this.waveformSamples = [];
      this.notify('');
    } catch (error) {
      // Capture is already released even if removing the file fails. Keep the
      // file available for recovery, but never leave an active recording UI.
      this.clearActiveRecording(RecordingState.STOPPED);
      const message = `删除录音失败，已停止采集：${String(error)}`;
      this.notify(message);
      throw new Error(message);
    } finally {
      this.endOperation();
    }
  }

  async release(): Promise<void> {
    this.beginOperation();
    try {
      if (this.activeRecording !== undefined) {
        await this.finishRecording();
      } else {
        await this.releaseResources();
      }
    } finally {
      this.endOperation();
    }
  }

  private beginOperation(): void {
    if (this.operationBusy) {
      throw new Error('录音状态正在切换，请稍后重试。');
    }
    this.operationBusy = true;
  }

  private endOperation(): void {
    this.operationBusy = false;
    if (this.pendingStopReason.length > 0 && this.activeRecording !== undefined) {
      this.stop().catch((error: Error): void => { console.error(error.message); });
    }
  }

  private requestStop(message: string): void {
    if (this.activeRecording === undefined) {
      return;
    }
    if (this.pendingStopReason.length === 0) {
      this.pendingStopReason = message;
    }
    this.notify(message);
    if (!this.operationBusy) {
      this.stop().catch((error: Error): void => { console.error(error.message); });
    }
  }

  private async startBackgroundTask(): Promise<void> {
    if (this.context === undefined) {
      throw new Error('Missing recording context.');
    }
    await this.backgroundTask.start(this.context, (): void => {
      this.requestStop('系统已结束后台录音任务。');
    });
  }

  private async stopBackgroundTask(): Promise<string> {
    try {
      await this.backgroundTask.stop();
      return '';
    } catch (error) {
      return String(error);
    }
  }

  private async startM4a(config: RecordingConfig): Promise<void> {
    if (this.activeRecording === undefined) {
      throw new Error('Missing output file.');
    }
    this.avFile = fileIo.openSync(this.activeRecording.filePath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    const recorder = await media.createAVRecorder();
    this.avRecorder = recorder;
    recorder.on('error', (error): void => {
      if (this.avRecorder === recorder) {
        this.requestStop(`录音器错误：${error.code}`);
      }
    });
    await recorder.prepare({
      audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
      profile: {
        audioBitrate: config.bitrate,
        audioChannels: config.channels,
        audioCodec: media.CodecMimeType.AUDIO_AAC,
        aacProfile: media.AacProfile.AAC_LC,
        audioSampleRate: config.sampleRate,
        fileFormat: media.ContainerFormatType.CFT_MPEG_4A
      },
      url: `fd://${this.avFile.fd}`
    });
    await recorder.start();
    this.startAmplitudePolling();
  }

  private async stopM4a(): Promise<void> {
    await this.stopAmplitudePolling();
    const recorder = this.avRecorder;
    this.avRecorder = undefined;
    let failure = '';
    if (recorder !== undefined) {
      try { await recorder.stop(); } catch (error) { failure = String(error); }
      try { await recorder.release(); } catch (error) {
        this.avRecorder = recorder;
        failure = failure || String(error);
      }
    }
    if (this.avFile !== undefined) {
      try { fileIo.fsyncSync(this.avFile.fd); } catch (error) { failure = failure || String(error); }
      if (this.avRecorder === undefined) { this.closeAvFile(); }
    }
    if (failure.length > 0) {
      throw new Error(failure);
    }
  }

  private async startPcm(config: RecordingConfig): Promise<void> {
    PcmStreamUtils.blockAlign(config);
    if (this.activeRecording === undefined) {
      throw new Error('Missing output file.');
    }
    this.pcmFile = fileIo.openSync(this.activeRecording.filePath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    this.pcmDataBytes = 0;
    this.pcmPendingBytes = 0;
    this.pcmWriteQueue = [];
    this.pcmWritePromise = undefined;
    this.pcmWriteFailure = '';
    this.pcmCheckpointBytes = 0;
    if (config.format === RecordingFormat.FLAC) {
      this.flacHandle = await flac.create(this.pcmFile.fd, config.sampleRate, config.channels);
    } else {
      this.writeFullySync(this.pcmFile.fd, WaveFileUtils.createPcmHeader(config, 0));
      this.liveSizeBytes = WaveFileUtils.HEADER_LENGTH;
    }
    await this.createAndStartPcmCapturer(config);
  }

  private async createAndStartPcmCapturer(config: RecordingConfig): Promise<void> {
    if (this.pcmFile === undefined || this.pcmWriteFailure.length > 0) {
      throw new Error('PCM output file is unavailable.');
    }
    const expected: audio.AudioStreamInfo = {
      samplingRate: config.sampleRate === 44100 ? audio.AudioSamplingRate.SAMPLE_RATE_44100 :
        audio.AudioSamplingRate.SAMPLE_RATE_48000,
      channels: audio.AudioChannel.CHANNEL_1,
      sampleFormat: config.bitDepth === 24 ? audio.AudioSampleFormat.SAMPLE_FORMAT_S24LE :
        audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
      encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
    };
    const capturer = await audio.createAudioCapturer({
      streamInfo: expected,
      capturerInfo: { source: audio.SourceType.SOURCE_TYPE_MIC, capturerFlags: 0 }
    });
    // Retain ownership before querying so every failure still releases the handle.
    // PCM headers and native encoders must describe the stream we actually receive,
    // including when a new capturer is created after pause or an input-route change.
    this.pcmCapturer = capturer;
    const actual = await capturer.getStreamInfo();
    if (actual.samplingRate !== expected.samplingRate || actual.channels !== expected.channels ||
      actual.sampleFormat !== expected.sampleFormat || actual.encodingType !== expected.encodingType) {
      throw new Error('当前音频输入不支持所选录音质量，请切换采样率或位深后重试。');
    }
    this.lastPcmPacketAt = this.monotonicNow();
    const callback = (buffer: ArrayBuffer): void => {
      if (this.pcmCapturer !== capturer || this.pcmFile === undefined ||
        this.pendingStopReason.length > 0 || this.pcmWriteFailure.length > 0 || buffer.byteLength === 0) {
        return;
      }
      this.enqueuePcmPacket(buffer, config);
      const now = this.monotonicNow();
      this.lastPcmPacketAt = now;
      if (now - this.lastWaveformSampleAt >= this.waveformSampleIntervalMs) {
        this.lastWaveformSampleAt = now;
        this.waveformSamples = WaveformUtils.appendSample(this.waveformSamples,
          WaveformUtils.calculateRmsFromPcm(buffer, config.bitDepth));
        this.notify('');
      }
    };
    this.pcmReadCallback = callback;
    capturer.on('readData', callback);
    capturer.on('audioInterrupt', (event: audio.InterruptEvent): void => {
      if (this.pcmCapturer === capturer && event.hintType !== audio.InterruptHint.INTERRUPT_HINT_NONE &&
        event.hintType !== audio.InterruptHint.INTERRUPT_HINT_RESUME) {
        this.requestStop('麦克风录音被系统或其他应用中断。');
      }
    });
    await capturer.start();
  }

  private async disposePcmCapturer(stopBeforeRelease: boolean): Promise<void> {
    const capturer = this.pcmCapturer;
    if (capturer === undefined) {
      return;
    }
    let failure = '';
    if (stopBeforeRelease) {
      try { await capturer.stop(); } catch (error) { failure = String(error); }
    }
    this.pcmCapturer = undefined;
    if (this.pcmReadCallback !== undefined) {
      try { capturer.off('readData', this.pcmReadCallback); } catch (error) { console.warn(String(error)); }
    }
    this.pcmReadCallback = undefined;
    try { capturer.off('audioInterrupt'); } catch (error) { console.warn(String(error)); }
    try { await capturer.release(); } catch (error) {
      // Keep the handle so error cleanup can retry instead of losing a live
      // capturer when both stop and release fail.
      this.pcmCapturer = capturer;
      failure = failure || String(error);
    }
    if (failure.length > 0) {
      throw new Error(`停止音频采集失败：${failure}`);
    }
  }

  private enqueuePcmPacket(buffer: ArrayBuffer, config: RecordingConfig): void {
    try {
      PcmStreamUtils.validatePacket(config, this.pcmDataBytes + this.pcmPendingBytes,
        this.pcmWriteQueue.length + (this.pcmWritePromise === undefined ? 0 : 1),
        this.pcmPendingBytes, buffer.byteLength);
    } catch (error) {
      this.requestStop(String(error));
      return;
    }
    this.pcmWriteQueue.push(buffer.slice(0));
    this.pcmPendingBytes += buffer.byteLength;
    if (this.pcmWritePromise === undefined) {
      const pending = this.drainPcmWriteQueue(config);
      this.pcmWritePromise = pending;
      // Publish before clearing: even a synchronous seek error must not leave
      // an already-settled Promise installed forever in flushPcmWrites.
      pending.then((): void => {
        if (this.pcmWritePromise === pending) { this.pcmWritePromise = undefined; }
      });
    }
  }

  private async drainPcmWriteQueue(config: RecordingConfig): Promise<void> {
    try {
      while (this.pcmWriteQueue.length > 0 && this.pcmFile !== undefined && this.pcmWriteFailure.length === 0) {
        const packet = PcmStreamUtils.takeWriteBatch(this.pcmWriteQueue);
        if (packet === undefined) { continue; }
        if (config.format === RecordingFormat.FLAC) {
          await flac.write(this.flacHandle, packet);
          this.pcmDataBytes += packet.byteLength;
          this.pcmPendingBytes -= packet.byteLength;
        } else {
          const cursor = new PcmWriteCursor(packet.byteLength);
          fileIo.lseek(this.pcmFile.fd, WaveFileUtils.HEADER_LENGTH + this.pcmDataBytes, fileIo.WhenceType.SEEK_SET);
          while (cursor.remaining > 0) {
            const suffix = cursor.offset === 0 ? packet : packet.slice(cursor.offset);
            const count = await fileIo.write(this.pcmFile.fd, suffix);
            cursor.advance(count);
            this.pcmDataBytes += count;
            this.pcmPendingBytes -= count;
          }
          await this.checkpointWav(config);
        }
      }
    } catch (error) {
      this.pcmWriteFailure = `音频写入失败：${String(error)}`;
      this.pcmWriteQueue = [];
      this.pcmPendingBytes = 0;
      this.requestStop(this.pcmWriteFailure);
    }
  }

  private async flushPcmWrites(): Promise<void> {
    while (this.pcmWritePromise !== undefined) {
      await this.pcmWritePromise;
    }
  }

  private async checkpointWav(config: RecordingConfig, force: boolean = false): Promise<void> {
    const file = this.pcmFile;
    if (config.format !== RecordingFormat.WAV || file === undefined) { return; }
    const align = PcmStreamUtils.blockAlign(config);
    // An even-byte, complete-sample prefix is readable without inserting a
    // RIFF pad into the ongoing stream (especially 24-bit mono recordings).
    const prefix = Math.floor(this.pcmDataBytes / (align * 2)) * align * 2;
    if (prefix <= this.pcmCheckpointBytes || (!force &&
      prefix - this.pcmCheckpointBytes < config.sampleRate * align * RecordingService.WAV_CHECKPOINT_SECONDS)) {
      return;
    }
    const header = WaveFileUtils.createPcmHeader(config, prefix);
    const cursor = new PcmWriteCursor(header.byteLength);
    while (cursor.remaining > 0) {
      const count = await fileIo.write(file.fd, cursor.offset === 0 ? header : header.slice(cursor.offset),
        { offset: cursor.offset });
      cursor.advance(count);
    }
    await fileIo.fsync(file.fd);
    this.pcmCheckpointBytes = prefix;
  }

  private async finishPcm(config: RecordingConfig): Promise<void> {
    try {
      await this.disposePcmCapturer(true);
    } catch (error) {
      this.pendingStopReason = this.pendingStopReason || String(error);
      if (this.pcmCapturer !== undefined) { throw new Error(String(error)); }
    }
    await this.flushPcmWrites();
    const output = this.pcmFile;
    if (output === undefined) { throw new Error('PCM output file is unavailable.'); }
    if (config.format === RecordingFormat.FLAC) {
      // The native encoder flushes its final partial frame and EOS before muxer stop.
      await flac.finish(this.flacHandle);
      await flac.release(this.flacHandle);
      this.flacHandle = -1;
    } else {
      const align = PcmStreamUtils.blockAlign(config);
      this.pcmDataBytes = Math.floor(this.pcmDataBytes / align) * align;
      const end = WaveFileUtils.HEADER_LENGTH + this.pcmDataBytes;
      fileIo.truncateSync(output.fd, end);
      fileIo.lseek(output.fd, end, fileIo.WhenceType.SEEK_SET);
      if (WaveFileUtils.paddingBytes(this.pcmDataBytes) > 0) {
        this.writeFullySync(output.fd, new ArrayBuffer(1));
      }
      fileIo.lseek(output.fd, 0, fileIo.WhenceType.SEEK_SET);
      this.writeFullySync(output.fd, WaveFileUtils.createPcmHeader(config, this.pcmDataBytes));
    }
    await fileIo.fsync(output.fd);
    fileIo.closeSync(output);
    this.pcmFile = undefined;
  }

  private writeFullySync(fd: number, buffer: ArrayBuffer): void {
    const cursor = new PcmWriteCursor(buffer.byteLength);
    while (cursor.remaining > 0) {
      cursor.advance(fileIo.writeSync(fd, cursor.offset === 0 ? buffer : buffer.slice(cursor.offset)));
    }
  }

  private async releaseResources(): Promise<void> {
    this.stopDurationTimer();
    await this.stopAmplitudePolling();
    const recorder = this.avRecorder;
    this.avRecorder = undefined;
    if (recorder !== undefined) {
      try { await recorder.release(); } catch (error) {
        this.avRecorder = recorder;
        console.error(String(error));
      }
    }
    if (this.avRecorder === undefined) { this.closeAvFile(); }
    try { await this.disposePcmCapturer(true); } catch (error) { console.error(String(error)); }
    await this.flushPcmWrites();
    if (this.flacHandle >= 0) {
      try { await flac.release(this.flacHandle); } catch (error) { console.error(String(error)); }
      this.flacHandle = -1;
    }
    if (this.pcmFile !== undefined && this.pcmCapturer === undefined) {
      try { fileIo.closeSync(this.pcmFile); } catch (error) { console.error(String(error)); }
      this.pcmFile = undefined;
    }
    this.pcmWriteQueue = [];
    this.pcmPendingBytes = 0;
    await this.stopBackgroundTask();
  }

  private closeAvFile(): void {
    if (this.avFile !== undefined) {
      try { fileIo.closeSync(this.avFile); } catch (error) { console.error(String(error)); }
      this.avFile = undefined;
    }
  }

  private discardEmptyFile(recording: RecordingInfo): void {
    try { RecordingRepository.discardTemporary(recording); } catch (error) { console.warn(String(error)); }
  }

  private clearActiveRecording(state: RecordingState): void {
    if (this.activeRecording !== undefined) {
      RecordingRepository.releaseTemporaryReservation(this.activeRecording);
    }
    this.state = state;
    this.activeRecording = undefined;
    this.activeConfig = undefined;
    this.context = undefined;
    this.segmentStartedAt = 0;
    this.accumulatedDurationMs = 0;
    this.pendingStopReason = '';
  }

  private startAmplitudePolling(): void {
    this.stopAmplitudeTimer();
    this.amplitudeGeneration += 1;
    this.readAmplitude();
    this.amplitudeTimerId = setInterval((): void => { this.readAmplitude(); }, 120);
  }

  private stopAmplitudeTimer(): void {
    if (this.amplitudeTimerId >= 0) {
      clearInterval(this.amplitudeTimerId);
      this.amplitudeTimerId = -1;
    }
  }

  private async stopAmplitudePolling(): Promise<void> {
    this.stopAmplitudeTimer();
    this.amplitudeGeneration += 1;
    const pending = this.amplitudeReadPromise;
    if (pending !== undefined) { await pending; }
    if (this.amplitudeReadPromise === pending) { this.amplitudeReadPromise = undefined; }
  }

  private readAmplitude(): void {
    if (this.amplitudeReadPromise !== undefined || this.avRecorder === undefined) { return; }
    const pending = this.readAmplitudeOnce(this.avRecorder, this.amplitudeGeneration);
    this.amplitudeReadPromise = pending;
    pending.then((): void => {
      if (this.amplitudeReadPromise === pending) { this.amplitudeReadPromise = undefined; }
    });
  }

  private async readAmplitudeOnce(recorder: media.AVRecorder, generation: number): Promise<void> {
    try {
      const amplitude = await recorder.getAudioCapturerMaxAmplitude();
      if (this.avRecorder !== recorder || this.amplitudeGeneration !== generation) { return; }
      this.waveformSamples = WaveformUtils.appendSample(this.waveformSamples, WaveformUtils.normalizeAmplitude(amplitude));
      this.notify('');
    } catch (error) {
      // A pending amplitude read may overlap pause/stop; the recorder error event owns failures.
    }
  }

  private monotonicNow(): number {
    return systemDateTime.getUptime(systemDateTime.TimeType.STARTUP, false);
  }

  private getCurrentDuration(): number {
    if (this.activeConfig !== undefined && this.activeConfig.format !== RecordingFormat.M4A) {
      return PcmStreamUtils.durationMs(this.pcmDataBytes + this.pcmPendingBytes, this.activeConfig);
    }
    if (this.state === RecordingState.RECORDING && this.segmentStartedAt > 0) {
      return this.accumulatedDurationMs + Math.max(0, this.monotonicNow() - this.segmentStartedAt);
    }
    return this.durationMs;
  }

  private startDurationTimer(): void {
    this.stopDurationTimer();
    this.timerId = setInterval((): void => {
      if (this.state === RecordingState.RECORDING && this.activeConfig !== undefined &&
        this.activeConfig.format !== RecordingFormat.M4A &&
        this.monotonicNow() - this.lastPcmPacketAt >= RecordingService.PCM_STALL_TIMEOUT_MS) {
        this.requestStop('音频采集长时间未返回数据，已停止并保存可用部分。');
        return;
      }
      this.durationMs = this.getCurrentDuration();
      this.liveSizeBytes = this.getCurrentFileSize(true);
      this.notify('');
    }, 250);
  }

  private stopDurationTimer(): void {
    if (this.timerId >= 0) { clearInterval(this.timerId); this.timerId = -1; }
  }

  private notify(message: string): void {
    if (this.observer !== undefined) {
      try {
        this.observer(new RecordingSnapshot(this.state, this.getCurrentDuration(), this.getCurrentFileSize(),
          this.waveformSamples, message));
      } catch (error) {
        // UI teardown or a failing listener cannot interrupt the microphone
        // callback, lose accepted PCM, or turn a saved take into a failure.
        console.error(`Recording observer failed: ${String(error)}`);
      }
    }
  }

  private getCurrentFileSize(refresh: boolean = false): number {
    if (this.activeConfig !== undefined && this.activeConfig.format === RecordingFormat.WAV) {
      return WaveFileUtils.HEADER_LENGTH + this.pcmDataBytes;
    }
    if (refresh && this.activeRecording !== undefined) {
      try { this.liveSizeBytes = fileIo.statSync(this.activeRecording.filePath).size; } catch (error) {
        // The encoder may create its header only after its first encoded frame.
      }
    }
    return this.liveSizeBytes;
  }
}
