import { fileIo } from '@kit.CoreFileKit';
import { RecordingConfig, RecordingFormat } from '../models/RecordingTypes';

export class AudioFileMetadata {
  readonly config: RecordingConfig;
  readonly durationMs: number;
  readonly dataOffset: number;
  readonly dataLength: number;

  constructor(config: RecordingConfig, durationMs: number, dataOffset: number = 0, dataLength: number = 0) {
    this.config = config;
    this.durationMs = durationMs;
    this.dataOffset = dataOffset;
    this.dataLength = dataLength;
  }
}

class AudioBox {
  readonly type: number;
  readonly start: number;
  readonly end: number;
  constructor(type: number, start: number, end: number) {
    this.type = type;
    this.start = start;
    this.end = end;
  }
}

// Inspect container metadata only. This is not a decoder or a proof that every compressed frame is valid.
// Reads are bounded: PCM payload and MP4 mdat are skipped, never loaded into memory.
export class AudioFileUtils {
  static read(filePath: string, extension: string): AudioFileMetadata | undefined {
    const size = fileIo.statSync(filePath).size;
    const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
    try {
      if (extension.toLowerCase() === 'wav') {
        return AudioFileUtils.readWave(file.fd, size);
      }
      if (extension.toLowerCase() === 'flac') {
        return AudioFileUtils.readFlac(file.fd, size);
      }
      if (extension.toLowerCase() === 'm4a') {
        return AudioFileUtils.readM4a(file.fd, size);
      }
      return undefined;
    } finally {
      fileIo.closeSync(file);
    }
  }

  private static bytes(fd: number, offset: number, length: number): ArrayBuffer | undefined {
    const buffer = new ArrayBuffer(length);
    const view = new Uint8Array(buffer);
    let completed = 0;
    while (completed < length) {
      const part = new ArrayBuffer(length - completed);
      const count = fileIo.readSync(fd, part, { offset: offset + completed, length: part.byteLength });
      if (count <= 0) {
        return undefined;
      }
      view.set(new Uint8Array(part, 0, count), completed);
      completed += count;
    }
    return buffer;
  }

  private static readWave(fd: number, size: number): AudioFileMetadata | undefined {
    const header = AudioFileUtils.bytes(fd, 0, 12);
    if (header === undefined) { return undefined; }
    const riff = new DataView(header);
    const end = riff.getUint32(4, true) + 8;
    if (riff.getUint32(0, false) !== 0x52494646 || riff.getUint32(8, false) !== 0x57415645 ||
      end > size || end < 12) { return undefined; }
    let config: RecordingConfig | undefined = undefined;
    let dataOffset = 0;
    let dataLength = 0;
    let cursor = 12;
    let chunks = 0;
    while (cursor + 8 <= end && chunks++ < 1024) {
      const chunk = AudioFileUtils.bytes(fd, cursor, 8);
      if (chunk === undefined) { return undefined; }
      const view = new DataView(chunk);
      const length = view.getUint32(4, true);
      const next = cursor + 8 + length + (length % 2);
      if (next > end) { return undefined; }
      if (view.getUint32(0, false) === 0x666D7420) {
        if (length < 16 || config !== undefined) { return undefined; }
        const bytes = AudioFileUtils.bytes(fd, cursor + 8, 16);
        if (bytes === undefined) { return undefined; }
        const fmt = new DataView(bytes);
        const channels = fmt.getUint16(2, true);
        const rate = fmt.getUint32(4, true);
        const bits = fmt.getUint16(14, true);
        const alignment = channels * bits / 8;
        if (fmt.getUint16(0, true) !== 1 || channels < 1 || channels > 32 || rate < 1 ||
          ![8, 16, 24, 32].includes(bits) || fmt.getUint16(12, true) !== alignment ||
          fmt.getUint32(8, true) !== rate * alignment) { return undefined; }
        config = new RecordingConfig(RecordingFormat.WAV, rate, bits, 0, channels);
      } else if (view.getUint32(0, false) === 0x64617461) {
        if (dataOffset > 0) { return undefined; }
        dataOffset = cursor + 8;
        dataLength = length;
      }
      cursor = next;
    }
    if (cursor !== end || config === undefined || dataLength <= 0 ||
      dataLength % (config.channels * config.bitDepth / 8) !== 0) { return undefined; }
    return new AudioFileMetadata(config,
      Math.floor(dataLength * 1000 / (config.sampleRate * config.channels * config.bitDepth / 8)),
      dataOffset, dataLength);
  }

  private static readFlac(fd: number, size: number): AudioFileMetadata | undefined {
    const bytes = AudioFileUtils.bytes(fd, 0, 42);
    if (bytes === undefined) { return undefined; }
    const data = new DataView(bytes);
    if (data.getUint32(0, false) !== 0x664C6143 || (data.getUint8(4) & 127) !== 0 ||
      data.getUint32(4, false) % 0x1000000 !== 34) { return undefined; }
    const rate = data.getUint8(18) * 4096 + data.getUint8(19) * 16 + (data.getUint8(20) >> 4);
    const channels = ((data.getUint8(20) >> 1) & 7) + 1;
    const bits = ((data.getUint8(20) & 1) * 16 + (data.getUint8(21) >> 4)) + 1;
    const samples = (data.getUint8(21) & 15) * 4294967296 + data.getUint32(22, false);
    if (rate < 1 || bits < 4 || bits > 32 || samples <= 0) { return undefined; }
    let cursor = 4;
    for (let blocks = 0; blocks < 1024; blocks++) {
      const bytes = AudioFileUtils.bytes(fd, cursor, 4);
      if (bytes === undefined) { return undefined; }
      const block = new DataView(bytes);
      const length = block.getUint32(0, false) % 0x1000000;
      cursor += 4 + length;
      if (cursor > size) { return undefined; }
      if ((block.getUint8(0) & 128) !== 0) {
        const frame = AudioFileUtils.bytes(fd, cursor, 2);
        if (frame === undefined) { return undefined; }
        const sync = new DataView(frame);
        if (sync.getUint8(0) !== 255 || (sync.getUint8(1) & 254) !== 248) { return undefined; }
        return new AudioFileMetadata(new RecordingConfig(RecordingFormat.FLAC, rate, bits, 0, channels),
          Math.floor(samples * 1000 / rate));
      }
    }
    return undefined;
  }

  private static boxes(fd: number, start: number, end: number): AudioBox[] {
    const result: AudioBox[] = [];
    let cursor = start;
    while (cursor + 8 <= end && result.length < 4096) {
      const bytes = AudioFileUtils.bytes(fd, cursor, 8);
      if (bytes === undefined) { return []; }
      const header = new DataView(bytes);
      let length = header.getUint32(0, false);
      let headerLength = 8;
      if (length === 1) {
        const extended = AudioFileUtils.bytes(fd, cursor + 8, 8);
        if (extended === undefined) { return []; }
        const wide = new DataView(extended);
        length = wide.getUint32(0, false) * 4294967296 + wide.getUint32(4, false);
        headerLength = 16;
      } else if (length === 0) {
        length = end - cursor;
      }
      if (!Number.isSafeInteger(length) || length < headerLength || cursor + length > end) { return []; }
      result.push(new AudioBox(header.getUint32(4, false), cursor + headerLength, cursor + length));
      cursor += length;
    }
    return cursor === end ? result : [];
  }

  private static box(boxes: AudioBox[], type: number): AudioBox | undefined {
    return boxes.find((item: AudioBox): boolean => item.type === type);
  }

  private static readM4a(fd: number, size: number): AudioFileMetadata | undefined {
    const top = AudioFileUtils.boxes(fd, 0, size);
    const ftyp = AudioFileUtils.box(top, 0x66747970);
    const moov = AudioFileUtils.box(top, 0x6D6F6F76);
    const mdat = AudioFileUtils.box(top, 0x6D646174);
    if (ftyp === undefined || ftyp.end - ftyp.start < 8 || moov === undefined ||
      mdat === undefined || mdat.end <= mdat.start) { return undefined; }
    for (const track of AudioFileUtils.boxes(fd, moov.start, moov.end)) {
      if (track.type !== 0x7472616B) { continue; }
      const mdia = AudioFileUtils.box(AudioFileUtils.boxes(fd, track.start, track.end), 0x6D646961);
      if (mdia === undefined) { continue; }
      const media = AudioFileUtils.boxes(fd, mdia.start, mdia.end);
      const hdlr = AudioFileUtils.box(media, 0x68646C72);
      const mdhd = AudioFileUtils.box(media, 0x6D646864);
      const minf = AudioFileUtils.box(media, 0x6D696E66);
      if (hdlr === undefined || hdlr.end - hdlr.start < 12 || mdhd === undefined || minf === undefined) { continue; }
      const handler = AudioFileUtils.bytes(fd, hdlr.start, 12);
      if (handler === undefined || new DataView(handler).getUint32(8, false) !== 0x736F756E) { continue; }
      const header = AudioFileUtils.bytes(fd, mdhd.start, Math.min(32, mdhd.end - mdhd.start));
      if (header === undefined || header.byteLength < 20) { continue; }
      const time = new DataView(header);
      const version = time.getUint8(0);
      if (version > 1 || (version === 1 && header.byteLength < 32)) { continue; }
      const scale = time.getUint32(version === 1 ? 20 : 12, false);
      const duration = version === 1 ? time.getUint32(24, false) * 4294967296 + time.getUint32(28, false) :
        time.getUint32(16, false);
      if (scale <= 0 || duration <= 0 || !Number.isSafeInteger(duration) ||
        (version === 0 && duration === 0xFFFFFFFF)) { continue; }
      const stbl = AudioFileUtils.box(AudioFileUtils.boxes(fd, minf.start, minf.end), 0x7374626C);
      if (stbl === undefined) { continue; }
      const stsd = AudioFileUtils.box(AudioFileUtils.boxes(fd, stbl.start, stbl.end), 0x73747364);
      if (stsd === undefined || stsd.end - stsd.start < 8) { continue; }
      const mp4a = AudioFileUtils.box(AudioFileUtils.boxes(fd, stsd.start + 8, stsd.end), 0x6D703461);
      if (mp4a === undefined || mp4a.end - mp4a.start < 28) { continue; }
      const entry = AudioFileUtils.bytes(fd, mp4a.start, 28);
      if (entry === undefined) { continue; }
      const description = new DataView(entry);
      // Version-zero ISO mp4a sample entries are the form emitted by this app's system muxer.
      if (description.getUint16(8, false) !== 0) { continue; }
      let channels = description.getUint16(16, false);
      let rate = description.getUint32(24, false) / 65536;
      let bitrate = 0;
      const extensions = AudioFileUtils.boxes(fd, mp4a.start + 28, mp4a.end);
      const btrt = AudioFileUtils.box(extensions, 0x62747274);
      if (btrt !== undefined && btrt.end - btrt.start >= 12) {
        const value = AudioFileUtils.bytes(fd, btrt.start, 12);
        if (value !== undefined) { bitrate = new DataView(value).getUint32(8, false); }
      }
      const esds = AudioFileUtils.box(extensions, 0x65736473);
      if (esds !== undefined && esds.end - esds.start <= 4096) {
        const value = AudioFileUtils.bytes(fd, esds.start, esds.end - esds.start);
        if (value !== undefined) {
          const codec = AudioFileUtils.aacDescriptor(new Uint8Array(value));
          if (codec !== undefined) {
            rate = codec.sampleRate;
            channels = codec.channels;
            bitrate = codec.bitrate > 0 ? codec.bitrate : bitrate;
          }
        }
      }
      if (rate <= 0 || !Number.isInteger(rate) || channels < 1 || channels > 8) { continue; }
      return new AudioFileMetadata(new RecordingConfig(RecordingFormat.M4A, rate, 0, bitrate, channels),
        Math.floor(duration * 1000 / scale));
    }
    return undefined;
  }

  private static aacDescriptor(bytes: Uint8Array): RecordingConfig | undefined {
    let cursor = 4;
    let bitrate = 0;
    for (let descriptors = 0; cursor + 2 <= bytes.length && descriptors < 16; descriptors++) {
      const tag = bytes[cursor++];
      let length = 0;
      let finished = false;
      for (let count = 0; count < 4 && cursor < bytes.length; count++) {
        const next = bytes[cursor++];
        length = length * 128 + (next & 127);
        if ((next & 128) === 0) { finished = true; break; }
      }
      const end = cursor + length;
      if (!finished || end > bytes.length) { return undefined; }
      if (tag === 3) {
        if (length < 3) { return undefined; }
        const flags = bytes[cursor + 2];
        cursor += 3;
        if ((flags & 128) !== 0) { cursor += 2; }
        if ((flags & 64) !== 0) { cursor += 1 + bytes[cursor]; }
        if ((flags & 32) !== 0) { cursor += 2; }
      } else if (tag === 4) {
        if (length < 13 || bytes[cursor] !== 0x40) { return undefined; }
        bitrate = bytes[cursor + 9] * 16777216 + bytes[cursor + 10] * 65536 +
          bytes[cursor + 11] * 256 + bytes[cursor + 12];
        cursor += 13;
      } else if (tag === 5) {
        if (length < 2) { return undefined; }
        const objectType = bytes[cursor] >> 3;
        const frequencyIndex = ((bytes[cursor] & 7) << 1) | (bytes[cursor + 1] >> 7);
        const rates: number[] = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350];
        const channelConfig = (bytes[cursor + 1] >> 3) & 15;
        if (objectType !== 2 || frequencyIndex >= rates.length || channelConfig < 1 || channelConfig > 7) {
          return undefined;
        }
        return new RecordingConfig(RecordingFormat.M4A, rates[frequencyIndex], 0, bitrate,
          channelConfig === 7 ? 8 : channelConfig);
      } else {
        cursor = end;
      }
      if (cursor > end) { return undefined; }
    }
    return undefined;
  }
}
