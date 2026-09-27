export class WaveformUtils {
  static readonly MAX_SAMPLES: number = 180;
  static readonly MIN_VISIBLE_SAMPLES: number = 96;
  static readonly MAX_VISIBLE_SAMPLES: number = 180;
  static readonly FADE_FRACTION: number = 0.15;
  static readonly LIVE_FRACTION: number = 0.20;
  static readonly FLOOR_DECIBELS: number = -60;
  static readonly DISPLAY_FLOOR_DECIBELS: number = -48;
  private static readonly PCM16_MAX_AMPLITUDE: number = 32768;
  private static readonly PCM24_MAX_AMPLITUDE: number = 8388608;

  static calculatePeakFromPcm16(buffer: ArrayBuffer): number {
    if (buffer.byteLength < 2) {
      return 0;
    }
    const view = new DataView(buffer);
    let peak = 0;
    for (let offset = 0; offset + 1 < buffer.byteLength; offset += 2) {
      const sample = view.getInt16(offset, true);
      const absolute = sample === -32768 ? 32768 : Math.abs(sample);
      if (absolute > peak) {
        peak = absolute;
      }
    }
    return Math.min(1, peak / WaveformUtils.PCM16_MAX_AMPLITUDE);
  }

  static calculateRmsFromPcm16(buffer: ArrayBuffer): number {
    if (buffer.byteLength < 2) {
      return 0;
    }
    const view = new DataView(buffer);
    let sumOfSquares = 0;
    let sampleCount = 0;
    for (let offset = 0; offset + 1 < buffer.byteLength; offset += 2) {
      const normalized = view.getInt16(offset, true) / WaveformUtils.PCM16_MAX_AMPLITUDE;
      sumOfSquares += normalized * normalized;
      sampleCount += 1;
    }
    if (sampleCount === 0) {
      return 0;
    }
    return Math.min(1, Math.sqrt(sumOfSquares / sampleCount));
  }

  static calculateRmsFromPcm(buffer: ArrayBuffer, bitDepth: number): number {
    if (bitDepth === 24) {
      return WaveformUtils.calculateRmsFromPcm24(buffer);
    }
    return WaveformUtils.calculateRmsFromPcm16(buffer);
  }

  static calculateRmsFromPcm24(buffer: ArrayBuffer): number {
    if (buffer.byteLength < 3) {
      return 0;
    }
    const view = new DataView(buffer);
    let sumOfSquares = 0;
    let sampleCount = 0;
    for (let offset = 0; offset + 2 < buffer.byteLength; offset += 3) {
      const unsigned = view.getUint8(offset) |
        (view.getUint8(offset + 1) << 8) |
        (view.getUint8(offset + 2) << 16);
      const sample = unsigned >= 0x800000 ? unsigned - 0x1000000 : unsigned;
      const normalized = sample / WaveformUtils.PCM24_MAX_AMPLITUDE;
      sumOfSquares += normalized * normalized;
      sampleCount += 1;
    }
    if (sampleCount === 0) {
      return 0;
    }
    return Math.min(1, Math.sqrt(sumOfSquares / sampleCount));
  }

  static normalizeAmplitude(amplitude: number): number {
    if (!Number.isFinite(amplitude) || amplitude <= 0) {
      return 0;
    }
    if (amplitude <= 1) {
      return amplitude;
    }
    return Math.min(1, amplitude / WaveformUtils.PCM16_MAX_AMPLITUDE);
  }

  static appendSample(samples: number[], sample: number, limit: number = WaveformUtils.MAX_SAMPLES): number[] {
    const normalized = Math.max(0, Math.min(1, Number.isFinite(sample) ? sample : 0));
    const safeLimit = Math.max(1, Math.floor(limit));
    const next: number[] = [];
    const start = Math.max(0, samples.length - safeLimit + 1);
    for (let index = start; index < samples.length; index++) {
      next.push(samples[index]);
    }
    next.push(normalized);
    return next;
  }

  static linearToDecibels(sample: number): number {
    const normalized = Math.max(0, Math.min(1, Number.isFinite(sample) ? sample : 0));
    if (normalized <= 0) {
      return WaveformUtils.FLOOR_DECIBELS;
    }
    const decibels = 20 * Math.log(normalized) / Math.LN10;
    return Math.max(WaveformUtils.FLOOR_DECIBELS, Math.min(0, decibels));
  }

  static displayHeight(sample: number, minimum: number = 0.035): number {
    const decibels = WaveformUtils.linearToDecibels(sample);
    const normalized = Math.max(0, Math.min(1,
      (decibels - WaveformUtils.DISPLAY_FLOOR_DECIBELS) / -WaveformUtils.DISPLAY_FLOOR_DECIBELS));
    return Math.max(minimum, normalized);
  }

  static visibleSampleCount(width: number): number {
    const safeWidth = Number.isFinite(width) ? Math.max(0, width) : 0;
    const estimated = Math.floor(safeWidth / 3.2);
    return Math.max(WaveformUtils.MIN_VISIBLE_SAMPLES,
      Math.min(WaveformUtils.MAX_VISIBLE_SAMPLES, estimated));
  }

  static samplesForWidth(samples: number[], width: number): number[] {
    const count = WaveformUtils.visibleSampleCount(width);
    const result: number[] = [];
    const start = Math.max(0, samples.length - count);
    for (let index = start; index < samples.length; index++) {
      result.push(Math.max(0, Math.min(1, Number.isFinite(samples[index]) ? samples[index] : 0)));
    }
    while (result.length < count) {
      result.unshift(0);
    }
    return result;
  }

  static fadeOpacity(index: number, count: number): number {
    if (count <= 1) {
      return 1;
    }
    const fadeEnd = Math.max(1, Math.floor(count * WaveformUtils.FADE_FRACTION));
    if (index >= fadeEnd) {
      return 1;
    }
    return Math.max(0, Math.min(1, index / fadeEnd));
  }

  static liveBlend(index: number, count: number): number {
    if (count <= 1) {
      return 1;
    }
    const liveStart = count - Math.max(1, Math.floor(count * WaveformUtils.LIVE_FRACTION));
    if (index <= liveStart) {
      return 0;
    }
    return Math.max(0, Math.min(1, (index - liveStart) / Math.max(1, count - 1 - liveStart)));
  }

  static decibelY(decibels: number, height: number, floor: number = -48, ceiling: number = 0): number {
    const safeCeiling = Number.isFinite(ceiling) ? ceiling : 0;
    const safeFloor = Number.isFinite(floor) && floor < safeCeiling ? floor : safeCeiling - 48;
    const clamped = Math.max(safeFloor, Math.min(safeCeiling,
      Number.isFinite(decibels) ? decibels : safeFloor));
    return (safeCeiling - clamped) / (safeCeiling - safeFloor) *
      (Number.isFinite(height) ? Math.max(0, height) : 0);
  }

  static decibelMarks(floor: number = -48, ceiling: number = 0): number[] {
    const safeCeiling = Number.isFinite(ceiling) ? ceiling : 0;
    const safeFloor = Number.isFinite(floor) && floor < safeCeiling ? floor : safeCeiling - 48;
    const marks: number[] = [];
    for (let index = 0; index < 5; index++) {
      marks.push(safeCeiling - (safeCeiling - safeFloor) * index / 4);
    }
    return marks;
  }
}
