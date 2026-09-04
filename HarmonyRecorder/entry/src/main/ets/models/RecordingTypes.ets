export enum RecordingFormat {
  WAV = 'wav',
  M4A = 'm4a'
}

export enum RecordingState {
  IDLE = 'IDLE',
  RECORDING = 'RECORDING',
  PAUSED = 'PAUSED',
  STOPPED = 'STOPPED'
}

export class RecordingConfig {
  public readonly format: RecordingFormat;
  public readonly sampleRate: number;
  public readonly bitDepth: number;
  public readonly bitrate: number;
  public readonly channels: number;

  constructor(format: RecordingFormat, sampleRate: number, bitDepth: number, bitrate: number, channels: number) {
    this.format = format;
    this.sampleRate = sampleRate;
    this.bitDepth = bitDepth;
    this.bitrate = bitrate;
    this.channels = channels;
  }

  static wav(sampleRate: number = 48000, bitDepth: number = 16): RecordingConfig {
    return new RecordingConfig(RecordingFormat.WAV, sampleRate, bitDepth, 0, 1);
  }

  static aac(bitrate: number, sampleRate: number = 48000): RecordingConfig {
    return new RecordingConfig(RecordingFormat.M4A, sampleRate, 0, bitrate, 1);
  }

  get extension(): string {
    return this.format === RecordingFormat.WAV ? 'wav' : 'm4a';
  }

  get formatLabel(): string {
    return this.format === RecordingFormat.WAV ? 'WAV' : 'M4A';
  }

  get sampleRateLabel(): string {
    return this.sampleRate === 44100 ? '44.1 kHz' : `${this.sampleRate / 1000} kHz`;
  }

  get encodingDetailLabel(): string {
    return this.format === RecordingFormat.WAV ? `${this.bitDepth} bit` : `${this.bitrate / 1000} kbps`;
  }

  get compactLabel(): string {
    return `${this.formatLabel} · ${this.encodingDetailLabel}`;
  }

  get qualityLabel(): string {
    if (this.format === RecordingFormat.WAV) {
      return `${this.sampleRateLabel} / ${this.bitDepth} bit / Mono`;
    }
    const quality = this.bitrate >= 256000 ? 'High' : 'Standard';
    return `${quality} · ${this.bitrate / 1000} kbps · ${this.sampleRateLabel} · Mono`;
  }
}

export class RecordingInfo {
  public id: string;
  public fileName: string;
  public filePath: string;
  public readonly config: RecordingConfig;
  public durationMs: number;
  public readonly createdAt: number;
  public sizeBytes: number;
  public deletedAt: number;
  public originalFileName: string;

  constructor(fileName: string, filePath: string, config: RecordingConfig, durationMs: number, createdAt: number,
    sizeBytes: number = 0, deletedAt: number = 0, originalFileName: string = '') {
    this.id = fileName;
    this.fileName = fileName;
    this.filePath = filePath;
    this.config = config;
    this.durationMs = durationMs;
    this.createdAt = createdAt;
    this.sizeBytes = sizeBytes;
    this.deletedAt = deletedAt;
    this.originalFileName = originalFileName;
  }

  get displayName(): string {
    const extensionIndex = this.fileName.lastIndexOf('.');
    return extensionIndex > 0 ? this.fileName.substring(0, extensionIndex) : this.fileName;
  }

  get extension(): string {
    const extensionIndex = this.fileName.lastIndexOf('.');
    return extensionIndex > 0 ? this.fileName.substring(extensionIndex + 1).toLowerCase() : this.config.extension;
  }

  get isInRecentlyDeleted(): boolean {
    return this.deletedAt > 0;
  }

  static placeholder(): RecordingInfo {
    return new RecordingInfo('', '', RecordingConfig.wav(), 0, 0);
  }
}

export class RecordingSnapshot {
  public readonly state: RecordingState;
  public readonly durationMs: number;
  public readonly sizeBytes: number;
  public readonly waveform: number[];
  public readonly message: string;

  constructor(state: RecordingState, durationMs: number, sizeBytes: number, waveform: number[], message: string) {
    this.state = state;
    this.durationMs = durationMs;
    this.sizeBytes = sizeBytes;
    this.waveform = waveform;
    this.message = message;
  }
}
