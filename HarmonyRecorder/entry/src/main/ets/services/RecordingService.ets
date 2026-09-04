import { common } from '@kit.AbilityKit';
import { audio } from '@kit.AudioKit';
import { fileIo } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { RecordingConfig, RecordingFormat, RecordingInfo, RecordingSnapshot, RecordingState } from '../models/RecordingTypes';
import { RecordingRepository } from '../repository/RecordingRepository';
import { WaveFileUtils } from '../utils/WaveFileUtils';
import { WaveformUtils } from '../utils/WaveformUtils';

export type RecordingObserver = (snapshot: RecordingSnapshot) => void;

export class RecordingService {
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

  private avRecorder: media.AVRecorder | undefined = undefined;
  private avFile: fileIo.File | undefined = undefined;
  private m4aAmplitudeTimerId: number = -1;
  private m4aAmplitudeReadPromise: Promise<void> | undefined = undefined;
  private m4aAmplitudeGeneration: number = 0;

  private wavCapturer: audio.AudioCapturer | undefined = undefined;
  private wavFile: fileIo.File | undefined = undefined;
  private wavDataBytes: number = 0;
  private wavReadCallback: ((buffer: ArrayBuffer) => void) | undefined = undefined;
  private liveSizeBytes: number = 0;
  private waveformSamples: number[] = [];
  private lastWaveformSampleAt: number = 0;
  private wavWriteQueue: Array<ArrayBuffer> = [];
  private wavWritePromise: Promise<void> | undefined = undefined;
  private wavWriteFailure: string = '';
  private readonly maxPendingWavPackets: number = 64;
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

  getState(): RecordingState {
    return this.state;
  }

  getDuration(): number {
    return this.getCurrentDuration();
  }

  async start(context: common.Context, config: RecordingConfig): Promise<void> {
    if (this.state === RecordingState.RECORDING || this.state === RecordingState.PAUSED) {
      throw new Error('A recording is already in progress.');
    }
    this.context = context;
    this.activeConfig = config;
    this.activeRecording = RecordingRepository.createNewRecording(context, config);
    this.durationMs = 0;
    this.accumulatedDurationMs = 0;
    this.segmentStartedAt = 0;
    this.liveSizeBytes = 0;
    this.waveformSamples = [];
    this.lastWaveformSampleAt = 0;

    try {
      if (config.format === RecordingFormat.WAV) {
        await this.startWav(config);
      } else {
        await this.startM4a(config);
      }
      this.state = RecordingState.RECORDING;
      this.segmentStartedAt = Date.now();
      this.startDurationTimer();
      this.notify('');
    } catch (error) {
      await this.releaseResources();
      this.resetToIdle();
      const message = `无法开始录音：${String(error)}`;
      this.notify(message);
      throw new Error(message);
    }
  }

  async pause(): Promise<void> {
    if (this.state !== RecordingState.RECORDING || this.activeConfig === undefined) {
      return;
    }
    try {
      if (this.activeConfig.format === RecordingFormat.WAV) {
        await this.pauseWav();
      } else if (this.avRecorder !== undefined) {
        await this.stopM4aAmplitudePolling();
        try {
          await this.avRecorder.pause();
        } catch (error) {
          this.startM4aAmplitudePolling();
          throw new Error(String(error));
        }
      }
    } catch (error) {
      const message = `暂停录音失败：${String(error)}`;
      this.notify(message);
      throw new Error(message);
    }
    this.accumulatedDurationMs = this.getCurrentDuration();
    this.durationMs = this.accumulatedDurationMs;
    this.segmentStartedAt = 0;
    this.stopDurationTimer();
    this.state = RecordingState.PAUSED;
    this.notify('');
  }

  async resume(): Promise<void> {
    if (this.state !== RecordingState.PAUSED || this.activeConfig === undefined) {
      return;
    }
    try {
      if (this.activeConfig.format === RecordingFormat.WAV) {
        await this.resumeWav(this.activeConfig);
      } else if (this.avRecorder !== undefined) {
        await this.avRecorder.resume();
        this.startM4aAmplitudePolling();
      }
    } catch (error) {
      const message = `继续录音失败：${String(error)}`;
      this.notify(message);
      throw new Error(message);
    }
    this.segmentStartedAt = Date.now();
    this.state = RecordingState.RECORDING;
    this.startDurationTimer();
    this.notify('');
  }

  async stop(): Promise<RecordingInfo | undefined> {
    if ((this.state !== RecordingState.RECORDING && this.state !== RecordingState.PAUSED) ||
      this.activeRecording === undefined || this.activeConfig === undefined || this.context === undefined) {
      return undefined;
    }
    const completedRecording = this.activeRecording;
    completedRecording.durationMs = this.getCurrentDuration();
    this.durationMs = completedRecording.durationMs;
    this.stopDurationTimer();

    try {
      if (this.activeConfig.format === RecordingFormat.WAV) {
        await this.stopWav(this.activeConfig);
      } else {
        await this.stopM4a();
      }
      completedRecording.sizeBytes = this.getCurrentFileSize();
      RecordingRepository.save(this.context, completedRecording);
      this.state = RecordingState.STOPPED;
      this.activeRecording = undefined;
      this.activeConfig = undefined;
      this.context = undefined;
      this.segmentStartedAt = 0;
      this.accumulatedDurationMs = 0;
      this.notify('');
      return completedRecording;
    } catch (error) {
      await this.releaseResources();
      this.resetToIdle();
      const message = `保存录音失败：${String(error)}`;
      this.notify(message);
      throw new Error(message);
    }
  }

  async discard(): Promise<void> {
    if ((this.state !== RecordingState.RECORDING && this.state !== RecordingState.PAUSED) ||
      this.activeRecording === undefined) {
      return;
    }
    const discardedRecording = this.activeRecording;
    this.stopDurationTimer();
    try {
      await this.releaseResources();
      RecordingRepository.discardTemporary(discardedRecording);
      this.resetToIdle();
      this.notify('');
    } catch (error) {
      this.resetToIdle();
      const message = `删除录音失败：${String(error)}`;
      this.notify(message);
      throw new Error(message);
    }
  }

  async release(): Promise<void> {
    this.stopDurationTimer();
    await this.releaseResources();
    this.resetToIdle();
    this.notify('');
  }

  private async startM4a(config: RecordingConfig): Promise<void> {
    if (this.activeRecording === undefined) {
      throw new Error('Missing output file.');
    }
    try {
      const outputFile = fileIo.openSync(this.activeRecording.filePath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      this.avFile = outputFile;
      const recorder = await media.createAVRecorder();
      this.avRecorder = recorder;
      recorder.on('error', (error) => {
        this.notify(`录音器错误：${error.code}`);
      });
      const profile: media.AVRecorderProfile = {
        audioBitrate: config.bitrate,
        audioChannels: config.channels,
        audioCodec: media.CodecMimeType.AUDIO_AAC,
        aacProfile: media.AacProfile.AAC_LC,
        audioSampleRate: config.sampleRate,
        fileFormat: media.ContainerFormatType.CFT_MPEG_4A
      };
      const recorderConfig: media.AVRecorderConfig = {
        audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
        profile: profile,
        url: `fd://${outputFile.fd}`
      };
      await recorder.prepare(recorderConfig);
      await recorder.start();
      this.startM4aAmplitudePolling();
    } catch (error) {
      throw new Error(`无法初始化 M4A 录音器：${String(error)}`);
    }
  }

  private async stopM4a(): Promise<void> {
    let failure = '';
    await this.stopM4aAmplitudePolling();
    const recorder = this.avRecorder;
    if (recorder !== undefined) {
      try {
        await recorder.stop();
      } catch (error) {
        failure = `停止 M4A 录音器失败：${String(error)}`;
      }
      try {
        await recorder.release();
      } catch (error) {
        if (failure.length === 0) {
          failure = `释放 M4A 录音器失败：${String(error)}`;
        }
      }
      this.avRecorder = undefined;
    }
    this.closeAvFile();
    if (failure.length > 0) {
      throw new Error(failure);
    }
  }

  private async startWav(config: RecordingConfig): Promise<void> {
    if (this.activeRecording === undefined) {
      throw new Error('Missing output file.');
    }
    try {
      const outputFile = fileIo.openSync(this.activeRecording.filePath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      this.wavFile = outputFile;
      this.wavDataBytes = 0;
      this.wavWriteQueue = [];
      this.wavWritePromise = undefined;
      this.wavWriteFailure = '';
      const header = WaveFileUtils.createPcmHeader(config, 0);
      fileIo.writeSync(outputFile.fd, header);
      this.liveSizeBytes = WaveFileUtils.HEADER_LENGTH;
      await this.createAndStartWavCapturer(config);
    } catch (error) {
      throw new Error(`无法初始化 WAV 录音器：${String(error)}`);
    }
  }

  private async resumeWav(config: RecordingConfig): Promise<void> {
    if (this.wavFile === undefined) {
      throw new Error('WAV output file is unavailable.');
    }
    await this.createAndStartWavCapturer(config);
  }

  private async createAndStartWavCapturer(config: RecordingConfig): Promise<void> {
    const streamInfo: audio.AudioStreamInfo = {
      samplingRate: config.sampleRate === 44100 ? audio.AudioSamplingRate.SAMPLE_RATE_44100 :
        audio.AudioSamplingRate.SAMPLE_RATE_48000,
      channels: audio.AudioChannel.CHANNEL_1,
      sampleFormat: config.bitDepth === 24 ? audio.AudioSampleFormat.SAMPLE_FORMAT_S24LE :
        audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
      encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
    };
    const capturerInfo: audio.AudioCapturerInfo = {
      source: audio.SourceType.SOURCE_TYPE_MIC,
      capturerFlags: 0
    };
    const capturerOptions: audio.AudioCapturerOptions = {
      streamInfo: streamInfo,
      capturerInfo: capturerInfo
    };
    try {
      const capturer = await audio.createAudioCapturer(capturerOptions);
      this.wavCapturer = capturer;
      const callback = (buffer: ArrayBuffer): void => {
        if (this.wavFile === undefined || this.wavWriteFailure.length > 0 || buffer.byteLength === 0) {
          return;
        }
        const now = Date.now();
        if (now - this.lastWaveformSampleAt >= this.waveformSampleIntervalMs) {
          this.lastWaveformSampleAt = now;
          this.waveformSamples = WaveformUtils.appendSample(this.waveformSamples,
            WaveformUtils.calculateRmsFromPcm(buffer, config.bitDepth));
          this.notify('');
        }
        this.enqueueWavPacket(buffer.slice(0));
      };
      this.wavReadCallback = callback;
      capturer.on('readData', callback);
      await capturer.start();
    } catch (error) {
      throw new Error(`无法启动 WAV 音频采集：${String(error)}`);
    }
  }

  private async pauseWav(): Promise<void> {
    await this.disposeWavCapturer(true);
  }

  private async stopWav(config: RecordingConfig): Promise<void> {
    try {
      await this.disposeWavCapturer(true);
      await this.flushWavWrites();
      if (this.wavFile !== undefined) {
        const outputFile = this.wavFile;
        const header = WaveFileUtils.createPcmHeader(config, this.wavDataBytes);
        fileIo.writeSync(outputFile.fd, header, { offset: 0, length: header.byteLength });
        fileIo.fsyncSync(outputFile.fd);
        fileIo.closeSync(outputFile);
        this.wavFile = undefined;
      }
    } catch (error) {
      throw new Error(`保存 WAV 文件失败：${String(error)}`);
    } finally {
      this.wavReadCallback = undefined;
    }
  }

  private async disposeWavCapturer(stopBeforeRelease: boolean): Promise<void> {
    if (this.wavCapturer === undefined) {
      return;
    }
    const capturer = this.wavCapturer;
    this.wavCapturer = undefined;
    const callback = this.wavReadCallback;
    this.wavReadCallback = undefined;
    if (callback !== undefined) {
      try {
        capturer.off('readData', callback);
      } catch (error) {
        console.error(`Remove WAV data callback failed: ${String(error)}`);
      }
    }
    let failure = '';
    if (stopBeforeRelease) {
      try {
        await capturer.stop();
      } catch (error) {
        failure = `停止 WAV 音频采集失败：${String(error)}`;
      }
    }
    try {
      await capturer.release();
    } catch (error) {
      if (failure.length === 0) {
        failure = `释放 WAV 音频采集失败：${String(error)}`;
      }
    }
    if (failure.length > 0) {
      throw new Error(failure);
    }
  }

  private async releaseResources(): Promise<void> {
    await this.stopM4aAmplitudePolling();
    if (this.avRecorder !== undefined) {
      try {
        await this.avRecorder.release();
      } catch (error) {
        console.error(`Release AVRecorder failed: ${String(error)}`);
      }
      this.avRecorder = undefined;
    }
    this.closeAvFile();
    if (this.wavCapturer !== undefined) {
      try {
        await this.disposeWavCapturer(false);
      } catch (error) {
        console.error(`Release AudioCapturer failed: ${String(error)}`);
      }
    }
    try {
      await this.flushWavWrites();
    } catch (error) {
      console.error(`Flush WAV data failed: ${String(error)}`);
    }
    if (this.wavFile !== undefined) {
      try {
        fileIo.closeSync(this.wavFile);
      } catch (error) {
        console.error(`Close WAV file failed: ${String(error)}`);
      }
      this.wavFile = undefined;
    }
    this.wavReadCallback = undefined;
    this.wavWriteQueue = [];
    this.wavWritePromise = undefined;
    this.wavWriteFailure = '';
  }

  private closeAvFile(): void {
    if (this.avFile === undefined) {
      return;
    }
    try {
      fileIo.closeSync(this.avFile);
    } catch (error) {
      console.error(`Close M4A file failed: ${String(error)}`);
    }
    this.avFile = undefined;
  }

  private startM4aAmplitudePolling(): void {
    this.stopM4aAmplitudeTimer();
    this.m4aAmplitudeGeneration += 1;
    this.readM4aAmplitude();
    this.m4aAmplitudeTimerId = setInterval((): void => {
      this.readM4aAmplitude();
    }, 120);
  }

  private stopM4aAmplitudeTimer(): void {
    if (this.m4aAmplitudeTimerId >= 0) {
      clearInterval(this.m4aAmplitudeTimerId);
      this.m4aAmplitudeTimerId = -1;
    }
  }

  private async stopM4aAmplitudePolling(): Promise<void> {
    this.stopM4aAmplitudeTimer();
    this.m4aAmplitudeGeneration += 1;
    const pending = this.m4aAmplitudeReadPromise;
    if (pending !== undefined) {
      await pending;
    }
    if (this.m4aAmplitudeReadPromise === pending) {
      this.m4aAmplitudeReadPromise = undefined;
    }
  }

  private readM4aAmplitude(): void {
    if (this.m4aAmplitudeReadPromise !== undefined || this.avRecorder === undefined) {
      return;
    }
    const recorder = this.avRecorder;
    const generation = this.m4aAmplitudeGeneration;
    const pending = this.readM4aAmplitudeOnce(recorder, generation);
    this.m4aAmplitudeReadPromise = pending;
    pending.then((): void => {
      if (this.m4aAmplitudeReadPromise === pending) {
        this.m4aAmplitudeReadPromise = undefined;
      }
    });
  }

  private async readM4aAmplitudeOnce(recorder: media.AVRecorder, generation: number): Promise<void> {
    try {
      const amplitude = await recorder.getAudioCapturerMaxAmplitude();
      if (this.avRecorder !== recorder || this.m4aAmplitudeGeneration !== generation ||
        this.activeConfig === undefined || this.activeConfig.format !== RecordingFormat.M4A) {
        return;
      }
      this.waveformSamples = WaveformUtils.appendSample(this.waveformSamples,
        WaveformUtils.normalizeAmplitude(amplitude));
      this.notify('');
    } catch (error) {
      // The recorder may transition to pause or stop while a read is in flight.
    }
  }

  private getCurrentDuration(): number {
    if (this.state === RecordingState.RECORDING && this.segmentStartedAt > 0) {
      return this.accumulatedDurationMs + Date.now() - this.segmentStartedAt;
    }
    return this.durationMs;
  }

  private startDurationTimer(): void {
    this.stopDurationTimer();
    this.timerId = setInterval((): void => {
      this.durationMs = this.getCurrentDuration();
      this.liveSizeBytes = this.getCurrentFileSize();
      this.notify('');
    }, 250);
  }

  private stopDurationTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private resetToIdle(): void {
    this.state = RecordingState.IDLE;
    this.durationMs = 0;
    this.accumulatedDurationMs = 0;
    this.segmentStartedAt = 0;
    this.context = undefined;
    this.activeRecording = undefined;
    this.activeConfig = undefined;
    this.liveSizeBytes = 0;
    this.waveformSamples = [];
    this.lastWaveformSampleAt = 0;
    this.stopM4aAmplitudeTimer();
    this.m4aAmplitudeReadPromise = undefined;
    this.m4aAmplitudeGeneration += 1;
    this.wavWriteQueue = [];
    this.wavWritePromise = undefined;
    this.wavWriteFailure = '';
  }

  private enqueueWavPacket(packet: ArrayBuffer): void {
    if (this.wavWriteQueue.length >= this.maxPendingWavPackets) {
      this.wavWriteFailure = 'WAV 文件写入速度不足，录制未能完整保存。';
      this.notify(this.wavWriteFailure);
      return;
    }
    this.wavWriteQueue.push(packet);
    if (this.wavWritePromise === undefined) {
      this.wavWritePromise = this.drainWavWriteQueue();
    }
  }

  private async drainWavWriteQueue(): Promise<void> {
    try {
      while (this.wavWriteQueue.length > 0 && this.wavFile !== undefined && this.wavWriteFailure.length === 0) {
        const packet = this.wavWriteQueue.shift();
        if (packet === undefined) {
          continue;
        }
        const writeLength = await fileIo.write(this.wavFile.fd, packet, {
          offset: WaveFileUtils.HEADER_LENGTH + this.wavDataBytes,
          length: packet.byteLength
        });
        this.wavDataBytes += writeLength;
        this.liveSizeBytes = WaveFileUtils.HEADER_LENGTH + this.wavDataBytes;
      }
    } catch (error) {
      this.wavWriteFailure = `WAV 数据写入失败：${String(error)}`;
      this.wavWriteQueue = [];
      this.notify(this.wavWriteFailure);
    } finally {
      this.wavWritePromise = undefined;
      if (this.wavWriteQueue.length > 0 && this.wavFile !== undefined && this.wavWriteFailure.length === 0) {
        this.wavWritePromise = this.drainWavWriteQueue();
      }
    }
  }

  private async flushWavWrites(): Promise<void> {
    while (this.wavWritePromise !== undefined) {
      await this.wavWritePromise;
    }
    if (this.wavWriteQueue.length > 0 && this.wavFile !== undefined && this.wavWriteFailure.length === 0) {
      this.wavWritePromise = this.drainWavWriteQueue();
      await this.flushWavWrites();
    }
    if (this.wavWriteFailure.length > 0) {
      throw new Error(this.wavWriteFailure);
    }
  }

  private notify(message: string): void {
    if (this.observer !== undefined) {
      this.observer(new RecordingSnapshot(this.state, this.getCurrentDuration(), this.getCurrentFileSize(),
        this.waveformSamples.slice(), message));
    }
  }

  private getCurrentFileSize(): number {
    if (this.activeConfig !== undefined && this.activeConfig.format === RecordingFormat.WAV) {
      return WaveFileUtils.HEADER_LENGTH + this.wavDataBytes;
    }
    if (this.activeRecording !== undefined) {
      try {
        this.liveSizeBytes = fileIo.statSync(this.activeRecording.filePath).size;
      } catch (error) {
        // The encoder can create the target file lazily. Keep the last known size until it becomes visible.
      }
    }
    return this.liveSizeBytes;
  }
}
