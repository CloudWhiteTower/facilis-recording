import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { RecordingFormat, RecordingInfo } from '../models/RecordingTypes';
import { RecordingRepository } from '../repository/RecordingRepository';
import { AudioFileUtils } from '../utils/AudioFileUtils';

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
  private static exportSequence: number = 0;

  static async saveToDevice(context: common.UIAbilityContext, recording: RecordingInfo): Promise<string | undefined> {
    // Original-byte backup remains available for a damaged file. Decoding/conversion uses inspectRecording instead.
    const sourcePath = RecordingRepository.validateRecordingPath(context, recording);
    const sourceSize = (await fileIo.stat(sourcePath)).size;
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [recording.fileName];
    options.fileSuffixChoices = [`${recording.extension.toUpperCase()}|.${recording.extension}`];
    const ownsNewDestination = canIUse('SystemCapability.FileManagement.UserFileService.FolderSelection');
    if (ownsNewDestination) {
      // API 23+: retain create/delete permission for cleanup if a new destination cannot be completely written.
      options.autoCreateEmptyFile = false;
    }
    let destinations: string[];
    try {
      destinations = await new picker.DocumentViewPicker(context).save(options);
    } catch (error) {
      if ((error as BusinessError).message === 'cancel') { return undefined; }
      throw new Error((error as Error).message || String(error));
    }
    if (destinations.length === 0) { return undefined; }
    const destination = destinations[0];
    if (destination === fileUri.getUriFromPath(sourcePath) || destination === sourcePath) {
      throw new Error('保存位置不能覆盖应用中的原始录音。');
    }
    let removeOnFailure = false;
    let source: fileIo.File | undefined = undefined;
    let output: fileIo.File | undefined = undefined;
    try {
      source = await fileIo.open(sourcePath, fileIo.OpenMode.READ_ONLY);
      if (ownsNewDestination) { removeOnFailure = !(await fileIo.access(destination)); }
      output = await fileIo.open(destination, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      await ExportService.copyRange(source.fd, output.fd, 0, sourceSize);
      await fileIo.fsync(output.fd);
      await fileIo.close(output);
      output = undefined;
      return destination;
    } catch (error) {
      await ExportService.closeQuietly(output);
      output = undefined;
      if (removeOnFailure) { await ExportService.removeQuietly(destination); }
      throw new Error(`保存到设备失败，应用内原录音已保留：${String(error)}`);
    } finally {
      await ExportService.closeQuietly(source);
      await ExportService.closeQuietly(output);
    }
  }

  static async exportWavAsPcm(context: common.Context, recording: RecordingInfo): Promise<ExportedAudio> {
    const verified = RecordingRepository.inspectRecording(context, recording);
    if (verified.config.format !== RecordingFormat.WAV) {
      throw new Error('当前仅支持将 WAV 录音导出为原始 PCM。');
    }
    const metadata = AudioFileUtils.read(verified.filePath, verified.extension);
    if (metadata === undefined || metadata.dataLength <= 0) {
      throw new Error('WAV 文件中没有完整的 PCM 音频数据。');
    }
    const directory = RecordingRepository.getExportsDirectory(context);
    ExportService.exportSequence += 1;
    // Keep the generated suffix within common 255-byte filename limits even after a long Chinese rename.
    let stem = verified.displayName.substring(0, 60);
    const last = stem.charCodeAt(stem.length - 1);
    if (last >= 0xD800 && last <= 0xDBFF) { stem = stem.substring(0, stem.length - 1); }
    const fileName = `${stem}_PCM_${Date.now()}_${ExportService.exportSequence}.pcm`;
    const filePath = `${directory}/${fileName}`;
    const temporaryPath = `${filePath}.tmp`;
    let source: fileIo.File | undefined = undefined;
    let output: fileIo.File | undefined = undefined;
    let ownsTemporary = false;
    try {
      if (await fileIo.access(filePath) || await fileIo.access(temporaryPath)) {
        throw new Error('导出文件名已存在，请重试。');
      }
      source = await fileIo.open(verified.filePath, fileIo.OpenMode.READ_ONLY);
      output = await fileIo.open(temporaryPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      ownsTemporary = true;
      await ExportService.copyRange(source.fd, output.fd, metadata.dataOffset, metadata.dataLength);
      await fileIo.fsync(output.fd);
      await fileIo.close(output);
      output = undefined;
      await fileIo.rename(temporaryPath, filePath);
      return new ExportedAudio(fileName, filePath, metadata.dataLength);
    } catch (error) {
      await ExportService.closeQuietly(output);
      output = undefined;
      if (ownsTemporary) { await ExportService.removeQuietly(temporaryPath); }
      throw new Error(`导出 PCM 失败：${String(error)}`);
    } finally {
      await ExportService.closeQuietly(source);
      await ExportService.closeQuietly(output);
    }
  }

  private static async copyRange(source: number, output: number, sourceOffset: number, length: number): Promise<void> {
    let copied = 0;
    while (copied < length) {
      const buffer = new ArrayBuffer(Math.min(ExportService.COPY_BUFFER_BYTES, length - copied));
      const read = await fileIo.read(source, buffer, { offset: sourceOffset + copied, length: buffer.byteLength });
      if (read <= 0 || read > buffer.byteLength) {
        throw new Error('源录音提前结束，未能完整复制。');
      }
      let written = 0;
      while (written < read) {
        const count = await fileIo.write(output, buffer.slice(written, read), { offset: copied + written });
        if (count <= 0 || count > read - written) {
          throw new Error('目标文件写入没有完成。');
        }
        written += count;
      }
      copied += read;
    }
  }

  private static async closeQuietly(file: fileIo.File | undefined): Promise<void> {
    if (file === undefined) { return; }
    try { await fileIo.close(file); } catch (error) { console.error(`Close exported audio failed: ${String(error)}`); }
  }

  private static async removeQuietly(path: string): Promise<void> {
    try {
      if (await fileIo.access(path)) { await fileIo.unlink(path); }
    } catch (error) { console.error(`Clean incomplete export failed: ${String(error)}`); }
  }
}
