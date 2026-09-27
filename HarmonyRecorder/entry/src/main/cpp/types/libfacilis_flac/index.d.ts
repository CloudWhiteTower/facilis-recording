/** Native FLAC encoding uses mono, signed 16-bit little-endian PCM at 44.1/48 kHz.
 * Keep fd open with READ_WRITE until release completes. Calls for one handle must
 * be awaited in order. finish drains every sample and writes exact STREAMINFO
 * counts (MD5 is zero, meaning unknown); it rejects an empty PCM stream.
 * release only frees resources and never closes the caller's fd.
 */
export const create: (fd: number, sampleRate: number, channels: number) => Promise<number>;
export const write: (handle: number, pcm16: ArrayBuffer) => Promise<void>;
export const finish: (handle: number) => Promise<void>;
export const release: (handle: number) => Promise<void>;

export interface ConversionResult {
  sampleRate: number;
  channels: number;
  bitDepth: number;
  bitrate: number;
  durationMs: number;
  sizeBytes: number;
}

/** Bounded native conversion. Caller owns both fds until release settles.
 * Progress/cancel are non-blocking; run and release must be awaited in order.
 */
export const conversionCreate: (sourceFd: number, sourceSize: number, targetFd: number,
  targetFormat: string, bitrate: number, targetBitDepth: number) => Promise<number>;
export const conversionRun: (handle: number) => Promise<ConversionResult>;
export const conversionProgress: (handle: number) => number;
export const conversionCancel: (handle: number) => void;
export const conversionRelease: (handle: number) => Promise<void>;
