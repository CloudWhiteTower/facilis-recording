import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import codec from 'libfacilis_flac.so';
import { RecordingConfig, RecordingFormat, RecordingInfo } from '../models/RecordingTypes';
import { RecordingRepository } from '../repository/RecordingRepository';

export class AudioConversionService {
  private static busy: boolean = false;
  private static sequence: number = 0;
  private handle: number = 0;
  private cancelled: boolean = false;
  private lastProgress: number = -1;

  cancel(): void {
    this.cancelled = true;
    if (this.handle > 0) {
      try {
        codec.conversionCancel(this.handle);
      } catch (error) {
        // Cancellation can race native completion/release. The flag still
        // prevents publication even when the handle has already disappeared.
        console.error(`Cancel conversion failed: ${String(error)}`);
      }
    }
  }

  async convert(context: common.Context, recording: RecordingInfo, target: RecordingFormat,
    bitrate: number, onProgress: (progress: number) => void): Promise<RecordingInfo | undefined> {
    if (AudioConversionService.busy) {
      throw new Error('已有格式转换正在进行，请稍后再试。');
    }
    AudioConversionService.busy = true;
    this.cancelled = false;
    this.lastProgress = -1;
    let source: fileIo.File | undefined = undefined;
    let output: fileIo.File | undefined = undefined;
    let temporaryPath = '';
    let timer: number = -1;
    try {
      const verified = RecordingRepository.inspectRecording(context, recording);
      if (target !== RecordingFormat.WAV && target !== RecordingFormat.FLAC && target !== RecordingFormat.M4A) {
        throw new Error('不支持此目标音频格式。');
      }
      if (verified.config.channels !== 1 ||
        (verified.config.sampleRate !== 44100 && verified.config.sampleRate !== 48000)) {
        throw new Error('当前转换支持 44.1 / 48 kHz 单声道录音。');
      }
      // AAC is compressed and legitimately reports bitDepth 0. Unknown PCM
      // depth must not silently select a 16-bit conversion and lose precision.
      if (verified.config.format !== RecordingFormat.M4A &&
        verified.config.bitDepth !== 16 && verified.config.bitDepth !== 24) {
        throw new Error('无法确认源录音位深，不能安全转换。');
      }
      if (target === RecordingFormat.M4A && bitrate !== 128000 && bitrate !== 256000) {
        throw new Error('AAC 转换仅支持 128 或 256 kbps。');
      }
      if (target === RecordingFormat.FLAC && verified.config.bitDepth > 16) {
        throw new Error('当前 FLAC 编码支持 16 bit。为保留精度，请将此录音保存为 WAV。');
      }
      if (target === verified.config.format && target !== RecordingFormat.M4A) {
        throw new Error('录音已是此格式，可直接保存原始文件。');
      }
      const depth = target === RecordingFormat.WAV && verified.config.bitDepth === 24 ? 24 : 16;
      temporaryPath = `${context.cacheDir}/conversion_${Date.now()}_${++AudioConversionService.sequence}.${target}`;
      source = fileIo.openSync(verified.filePath, fileIo.OpenMode.READ_ONLY);
      output = fileIo.openSync(temporaryPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE |
        fileIo.OpenMode.TRUNC);
      this.reportProgress(onProgress, 0);
      if (this.cancelled) { return undefined; }
      this.handle = await codec.conversionCreate(source.fd, fileIo.statSync(source.fd).size,
        output.fd, target, bitrate, depth);
      if (this.cancelled) {
        this.cancel();
        return undefined;
      }
      timer = setInterval((): void => {
        if (this.handle > 0 && !this.cancelled) {
          try {
            const progress = codec.conversionProgress(this.handle);
            if (Number.isFinite(progress)) {
              this.reportProgress(onProgress, Math.max(0, Math.min(0.99, progress)));
            }
          } catch (error) {
            console.error(`Read conversion progress failed: ${String(error)}`);
          }
        }
      }, 250);
      const result = await codec.conversionRun(this.handle);
      clearInterval(timer);
      timer = -1;
      if (this.cancelled) { return undefined; }
      if (result.channels !== 1 || result.sampleRate !== verified.config.sampleRate ||
        (target !== RecordingFormat.M4A && result.bitDepth !== depth)) {
        throw new Error('转换输出的音频参数与请求不一致，未保存。');
      }
      await codec.conversionRelease(this.handle);
      this.handle = 0;
      if (this.cancelled) { return undefined; }
      await fileIo.fsync(output.fd);
      if (this.cancelled) { return undefined; }
      fileIo.closeSync(output);
      output = undefined;
      const config = new RecordingConfig(target, result.sampleRate, result.bitDepth,
        result.bitrate, result.channels);
      let stem = recording.displayName.substring(0, 60);
      const last = stem.charCodeAt(stem.length - 1);
      if (last >= 0xD800 && last <= 0xDBFF) { stem = stem.substring(0, stem.length - 1); }
      const converted = RecordingRepository.importCompletedFile(context, temporaryPath, config,
        `${stem}_${target.toUpperCase()}`);
      temporaryPath = '';
      this.reportProgress(onProgress, 1);
      return converted;
    } catch (error) {
      if (this.cancelled) { return undefined; }
      throw new Error((error as Error).message || String(error));
    } finally {
      if (timer >= 0) { clearInterval(timer); }
      if (this.handle > 0) {
        try { await codec.conversionRelease(this.handle); } catch (error) {
          console.error(`Release conversion failed: ${String(error)}`);
        }
        this.handle = 0;
      }
      for (const file of [source, output]) {
        if (file !== undefined) {
          try { fileIo.closeSync(file); } catch (error) { console.error(String(error)); }
        }
      }
      if (temporaryPath.length > 0) {
        try { fileIo.unlinkSync(temporaryPath); } catch (error) {
          console.error(`Clean conversion temporary file: ${String(error)}`);
        }
      }
      AudioConversionService.busy = false;
    }
  }

  private reportProgress(onProgress: (progress: number) => void, progress: number): void {
    const next = Math.max(this.lastProgress, Math.floor(progress * 1000) / 1000);
    if (next === this.lastProgress) { return; }
    this.lastProgress = next;
    try {
      onProgress(next);
    } catch (error) {
      // A detached UI callback must not turn a committed import into a reported
      // conversion failure or interrupt native/file cleanup.
      console.error(`Report conversion progress failed: ${String(error)}`);
    }
  }
}
