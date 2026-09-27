import { RecordingConfig, RecordingFormat } from '../models/RecordingTypes';

export class WaveFileUtils {
  static readonly HEADER_LENGTH: number = 44;
  // RIFF chunk sizes include the even-byte pad but the data chunk length does not.
  static readonly MAX_DATA_LENGTH: number = 0xFFFFFFFE - 36;

  static createPcmHeader(config: RecordingConfig, dataLength: number): ArrayBuffer {
    WaveFileUtils.validatePcmConfig(config);
    const normalizedDataLength = WaveFileUtils.normalizeDataLength(dataLength);
    if (normalizedDataLength % (config.channels * config.bitDepth / 8) !== 0) {
      throw new Error('WAV data must contain complete PCM samples.');
    }
    const header = new ArrayBuffer(WaveFileUtils.HEADER_LENGTH);
    const view = new DataView(header);
    const bytesPerSample = config.bitDepth / 8;
    const byteRate = config.sampleRate * config.channels * bytesPerSample;
    const blockAlign = config.channels * bytesPerSample;

    WaveFileUtils.writeFourCc(view, 0, 'RIFF');
    view.setUint32(4, 36 + normalizedDataLength + WaveFileUtils.paddingBytes(normalizedDataLength), true);
    WaveFileUtils.writeFourCc(view, 8, 'WAVE');
    WaveFileUtils.writeFourCc(view, 12, 'fmt ');
    view.setUint32(16, 16, true);
    view.setUint16(20, 1, true);
    view.setUint16(22, config.channels, true);
    view.setUint32(24, config.sampleRate, true);
    view.setUint32(28, byteRate, true);
    view.setUint16(32, blockAlign, true);
    view.setUint16(34, config.bitDepth, true);
    WaveFileUtils.writeFourCc(view, 36, 'data');
    view.setUint32(40, normalizedDataLength, true);
    return header;
  }

  static calculateDurationMs(dataLength: number, config: RecordingConfig): number {
    WaveFileUtils.validatePcmConfig(config);
    if (!isFinite(dataLength) || dataLength <= 0) {
      return 0;
    }
    const bytesPerSecond = config.sampleRate * config.channels * (config.bitDepth / 8);
    return Math.floor(Math.floor(dataLength) * 1000 / bytesPerSecond);
  }

  static paddingBytes(dataLength: number): number {
    return dataLength % 2;
  }

  static maximumDataLength(config: RecordingConfig): number {
    WaveFileUtils.validatePcmConfig(config);
    const blockAlign = config.channels * config.bitDepth / 8;
    return Math.floor(WaveFileUtils.MAX_DATA_LENGTH / blockAlign) * blockAlign;
  }

  private static normalizeDataLength(dataLength: number): number {
    if (!Number.isSafeInteger(dataLength) || dataLength < 0) {
      throw new Error('WAV data length must be a finite non-negative integer.');
    }
    const normalized = Math.floor(dataLength);
    if (normalized > WaveFileUtils.MAX_DATA_LENGTH) {
      throw new Error('WAV data exceeds the RIFF 4 GiB limit.');
    }
    return normalized;
  }

  private static validatePcmConfig(config: RecordingConfig): void {
    if (config.format !== RecordingFormat.WAV ||
      (config.sampleRate !== 44100 && config.sampleRate !== 48000) || config.channels !== 1 ||
      (config.bitDepth !== 16 && config.bitDepth !== 24)) {
      throw new Error('A valid PCM WAV recording configuration is required.');
    }
  }

  private static writeFourCc(view: DataView, offset: number, value: string): void {
    for (let index = 0; index < 4; index++) {
      view.setUint8(offset + index, value.charCodeAt(index));
    }
  }
}
