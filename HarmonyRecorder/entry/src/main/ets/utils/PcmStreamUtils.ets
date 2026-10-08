import { RecordingConfig, RecordingFormat } from '../models/RecordingTypes';
import { WaveFileUtils } from './WaveFileUtils';

// File writes may succeed with fewer bytes than requested. Never count or skip
// an unwritten suffix, and treat zero progress as an error rather than looping.
export class PcmWriteCursor {
  private written: number = 0;
  private readonly length: number;

  constructor(length: number) {
    if (!Number.isSafeInteger(length) || length < 0) {
      throw new Error('Invalid write buffer length.');
    }
    this.length = length;
  }

  get offset(): number { return this.written; }
  get remaining(): number { return this.length - this.written; }

  advance(count: number): void {
    if (!Number.isSafeInteger(count) || count <= 0 || count > this.remaining) {
      throw new Error('Audio file write made no valid progress.');
    }
    this.written += count;
  }
}

export class PcmStreamUtils {
  static readonly MAX_PENDING_PACKETS: number = 64;
  static readonly MAX_PENDING_BYTES: number = 2 * 1024 * 1024;
  static readonly WRITE_BATCH_BYTES: number = 64 * 1024;

  // Coalesce an already queued burst without delaying newly captured audio.
  // The native bridge/file writer receives fewer jobs when storage is busy.
  static takeWriteBatch(queue: Array<ArrayBuffer>): ArrayBuffer | undefined {
    const first = queue.shift();
    if (first === undefined || queue.length === 0 || first.byteLength >= PcmStreamUtils.WRITE_BATCH_BYTES) {
      return first;
    }
    let length = first.byteLength;
    let count = 0;
    while (count < queue.length && length + queue[count].byteLength <= PcmStreamUtils.WRITE_BATCH_BYTES) {
      length += queue[count].byteLength;
      count += 1;
    }
    if (count === 0) { return first; }
    const combined = new Uint8Array(length);
    combined.set(new Uint8Array(first));
    let offset = first.byteLength;
    for (let index = 0; index < count; index++) {
      combined.set(new Uint8Array(queue[index]), offset);
      offset += queue[index].byteLength;
    }
    queue.splice(0, count);
    return combined.buffer;
  }

  static blockAlign(config: RecordingConfig): number {
    if ((config.format !== RecordingFormat.WAV && config.format !== RecordingFormat.FLAC) ||
      (config.sampleRate !== 44100 && config.sampleRate !== 48000) || config.channels !== 1 ||
      (config.bitDepth !== 16 && config.bitDepth !== 24) ||
      (config.format === RecordingFormat.FLAC && config.bitDepth !== 16)) {
      throw new Error('Unsupported PCM recording configuration.');
    }
    return config.channels * config.bitDepth / 8;
  }

  static validatePacket(config: RecordingConfig, acceptedBytes: number, queuedPackets: number,
    pendingBytes: number, packetBytes: number): void {
    const align = PcmStreamUtils.blockAlign(config);
    if (!Number.isSafeInteger(packetBytes) || packetBytes <= 0 || packetBytes % align !== 0) {
      throw new Error('音频采集返回了不完整的 PCM 样点。');
    }
    if (queuedPackets >= PcmStreamUtils.MAX_PENDING_PACKETS ||
      pendingBytes + packetBytes > PcmStreamUtils.MAX_PENDING_BYTES) {
      throw new Error('存储写入速度不足，已停止录音并保存可用部分。');
    }
    if (config.format === RecordingFormat.WAV &&
      acceptedBytes + packetBytes > WaveFileUtils.maximumDataLength(config)) {
      throw new Error('WAV 已达到 RIFF 文件大小上限，已停止并保存录音。');
    }
  }

  static durationMs(dataBytes: number, config: RecordingConfig): number {
    const align = PcmStreamUtils.blockAlign(config);
    return Math.floor(Math.floor(Math.max(0, dataBytes) / align) * 1000 / config.sampleRate);
  }
}
