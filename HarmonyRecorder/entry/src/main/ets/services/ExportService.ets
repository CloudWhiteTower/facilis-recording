import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { RecordingFormat, RecordingInfo } from '../models/RecordingTypes';
import { RecordingRepository } from '../repository/RecordingRepository';
import { WaveFileUtils } from '../utils/WaveFileUtils';

export class ExportedAudio {
  public readonly fileName: string;
  public readonly filePath: string;
  public readonly sizeBytes: number;

  constructor(fileName: string, filePath: string, sizeBytes: number) {
    this.fileName = fileName;
    this.filePath = filePath;
    this.sizeBytes = sizeBytes;
  }
}

export class ExportService {
  private static readonly COPY_BUFFER_BYTES: number = 64 * 1024;

  static exportWavAsPcm(context: common.Context, recording: RecordingInfo): ExportedAudio {
    if (recording.config.format !== RecordingFormat.WAV) {
      throw new Error('当前仅支持将 WAV 录音导出为原始 PCM。');
    }
    let sourceSize = 0;
    let source: fileIo.File | undefined = undefined;
    let output: fileIo.File | undefined = undefined;
    try {
      sourceSize = fileIo.statSync(recording.filePath).size;
      if (sourceSize <= WaveFileUtils.HEADER_LENGTH) {
        throw new Error('WAV 文件中没有可导出的 PCM 音频数据。');
      }
      const directory = RecordingRepository.getExportsDirectory(context);
      const fileName = `${recording.displayName}_PCM_${Date.now()}.pcm`;
      const filePath = `${directory}/${fileName}`;
      source = fileIo.openSync(recording.filePath, fileIo.OpenMode.READ_ONLY);
      output = fileIo.openSync(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      const buffer = new ArrayBuffer(ExportService.COPY_BUFFER_BYTES);
      let sourceOffset = WaveFileUtils.HEADER_LENGTH;
      let outputOffset = 0;
      while (sourceOffset < sourceSize) {
        const remaining = sourceSize - sourceOffset;
        const readLength = Math.min(buffer.byteLength, remaining);
        const actualRead = fileIo.readSync(source.fd, buffer, { offset: sourceOffset, length: readLength });
        if (actualRead <= 0) {
          break;
        }
        const actualWritten = fileIo.writeSync(output.fd, buffer, { offset: outputOffset, length: actualRead });
        sourceOffset += actualRead;
        outputOffset += actualWritten;
        if (actualWritten !== actualRead) {
          throw new Error('PCM 导出未能完整写入。');
        }
      }
      fileIo.fsyncSync(output.fd);
      return new ExportedAudio(fileName, filePath, outputOffset);
    } catch (error) {
      throw new Error(`导出 PCM 失败：${String(error)}`);
    } finally {
      if (source !== undefined) {
        try {
          fileIo.closeSync(source);
        } catch (error) {
          console.error(`Close PCM source failed: ${String(error)}`);
        }
      }
      if (output !== undefined) {
        try {
          fileIo.closeSync(output);
        } catch (error) {
          console.error(`Close PCM output failed: ${String(error)}`);
        }
      }
    }
  }
}
