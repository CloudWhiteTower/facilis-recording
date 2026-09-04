import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { RecordingConfig, RecordingFormat, RecordingInfo } from '../models/RecordingTypes';
import { TimeUtils } from '../utils/TimeUtils';
import { WaveFileUtils } from '../utils/WaveFileUtils';

export class RecordingRepository {
  private static readonly RECORDINGS_DIRECTORY: string = 'recordings';
  private static readonly RECENTLY_DELETED_DIRECTORY: string = 'recently_deleted';
  private static readonly EXPORTS_DIRECTORY: string = 'exports';
  private static readonly INDEX_FILE: string = 'recordings.index';
  private static readonly TRASH_INDEX_FILE: string = 'recently_deleted.index';

  static createNewRecording(context: common.Context, config: RecordingConfig): RecordingInfo {
    const directory = RecordingRepository.ensureRecordingsDirectory(context);
    const createdAt = Date.now();
    const fileName = RecordingRepository.createUniqueRecordingFileName(directory, config.extension, createdAt);
    return new RecordingInfo(fileName, `${directory}/${fileName}`, config, 0, createdAt);
  }

  static list(context: common.Context): RecordingInfo[] {
    const directory = RecordingRepository.ensureRecordingsDirectory(context);
    return RecordingRepository.listDirectory(directory, RecordingRepository.INDEX_FILE, false);
  }

  static listRecentlyDeleted(context: common.Context): RecordingInfo[] {
    const directory = RecordingRepository.ensureRecentlyDeletedDirectory(context);
    return RecordingRepository.listDirectory(directory, RecordingRepository.TRASH_INDEX_FILE, true);
  }

  static getRecentlyDeletedCount(context: common.Context): number {
    return RecordingRepository.listRecentlyDeleted(context).length;
  }

  static save(context: common.Context, recording: RecordingInfo): void {
    const directory = RecordingRepository.ensureRecordingsDirectory(context);
    const recordings = RecordingRepository.list(context).filter((item: RecordingInfo): boolean => item.id !== recording.id);
    recordings.push(recording);
    RecordingRepository.writeIndex(directory, RecordingRepository.INDEX_FILE, recordings);
  }

  static rename(context: common.Context, recording: RecordingInfo, requestedName: string): RecordingInfo {
    if (recording.isInRecentlyDeleted) {
      throw new Error('Recently deleted recordings must be restored before they can be renamed.');
    }
    const directory = RecordingRepository.ensureRecordingsDirectory(context);
    const recordings = RecordingRepository.list(context);
    const existing = RecordingRepository.findById(recordings, recording.id);
    if (existing === undefined || !RecordingRepository.isExistingFile(existing.filePath)) {
      throw new Error('The recording is no longer available.');
    }
    const displayName = RecordingRepository.normalizeDisplayName(requestedName, existing.extension);
    const desiredFileName = `${displayName}.${existing.extension}`;
    const fileName = RecordingRepository.createAvailableFileName(directory, desiredFileName);
    const filePath = `${directory}/${fileName}`;
    fileIo.renameSync(existing.filePath, filePath);

    const renamed = new RecordingInfo(fileName, filePath, existing.config, existing.durationMs, existing.createdAt,
      RecordingRepository.readFileSize(filePath), 0, '');
    const updated = recordings.filter((item: RecordingInfo): boolean => item.id !== existing.id);
    updated.push(renamed);
    RecordingRepository.writeIndex(directory, RecordingRepository.INDEX_FILE, updated);
    return renamed;
  }

  static moveToRecentlyDeleted(context: common.Context, recording: RecordingInfo): RecordingInfo {
    const recordingsDirectory = RecordingRepository.ensureRecordingsDirectory(context);
    const recordings = RecordingRepository.list(context);
    const existing = RecordingRepository.findById(recordings, recording.id);
    if (existing === undefined || !RecordingRepository.isExistingFile(existing.filePath)) {
      throw new Error('The recording is no longer available.');
    }
    const recentlyDeletedDirectory = RecordingRepository.ensureRecentlyDeletedDirectory(context);
    const recentlyDeleted = RecordingRepository.listRecentlyDeleted(context);
    const fileName = RecordingRepository.createAvailableFileName(recentlyDeletedDirectory, existing.fileName);
    const filePath = `${recentlyDeletedDirectory}/${fileName}`;
    fileIo.renameSync(existing.filePath, filePath);

    const moved = new RecordingInfo(fileName, filePath, existing.config, existing.durationMs, existing.createdAt,
      RecordingRepository.readFileSize(filePath), Date.now(), existing.fileName);
    const active = recordings.filter((item: RecordingInfo): boolean => item.id !== existing.id);
    recentlyDeleted.push(moved);
    RecordingRepository.writeIndex(recordingsDirectory, RecordingRepository.INDEX_FILE, active);
    RecordingRepository.writeIndex(recentlyDeletedDirectory, RecordingRepository.TRASH_INDEX_FILE, recentlyDeleted);
    return moved;
  }

  static restore(context: common.Context, recording: RecordingInfo): RecordingInfo {
    const recentlyDeletedDirectory = RecordingRepository.ensureRecentlyDeletedDirectory(context);
    const recentlyDeleted = RecordingRepository.listRecentlyDeleted(context);
    const existing = RecordingRepository.findById(recentlyDeleted, recording.id);
    if (existing === undefined || !RecordingRepository.isExistingFile(existing.filePath)) {
      throw new Error('The deleted recording is no longer available.');
    }
    const recordingsDirectory = RecordingRepository.ensureRecordingsDirectory(context);
    const recordings = RecordingRepository.list(context);
    const preferredName = existing.originalFileName.length > 0 ? existing.originalFileName : existing.fileName;
    const fileName = RecordingRepository.createAvailableFileName(recordingsDirectory, preferredName);
    const filePath = `${recordingsDirectory}/${fileName}`;
    fileIo.renameSync(existing.filePath, filePath);

    const restored = new RecordingInfo(fileName, filePath, existing.config, existing.durationMs, existing.createdAt,
      RecordingRepository.readFileSize(filePath));
    const remaining = recentlyDeleted.filter((item: RecordingInfo): boolean => item.id !== existing.id);
    recordings.push(restored);
    RecordingRepository.writeIndex(recentlyDeletedDirectory, RecordingRepository.TRASH_INDEX_FILE, remaining);
    RecordingRepository.writeIndex(recordingsDirectory, RecordingRepository.INDEX_FILE, recordings);
    return restored;
  }

  static permanentlyDelete(context: common.Context, recording: RecordingInfo): void {
    const directory = RecordingRepository.ensureRecentlyDeletedDirectory(context);
    const recentlyDeleted = RecordingRepository.listRecentlyDeleted(context);
    const existing = RecordingRepository.findById(recentlyDeleted, recording.id);
    if (existing === undefined) {
      return;
    }
    if (RecordingRepository.isExistingFile(existing.filePath)) {
      fileIo.unlinkSync(existing.filePath);
    }
    const remaining = recentlyDeleted.filter((item: RecordingInfo): boolean => item.id !== existing.id);
    RecordingRepository.writeIndex(directory, RecordingRepository.TRASH_INDEX_FILE, remaining);
  }

  static discardTemporary(recording: RecordingInfo): void {
    if (recording.filePath.length > 0 && RecordingRepository.isExistingFile(recording.filePath)) {
      fileIo.unlinkSync(recording.filePath);
    }
  }

  static getExportsDirectory(context: common.Context): string {
    return RecordingRepository.ensureChildDirectory(context, RecordingRepository.EXPORTS_DIRECTORY);
  }

  static normalizeDisplayName(value: string, extension: string): string {
    let normalized = value.trim();
    const extensionSuffix = `.${extension.toLowerCase()}`;
    if (normalized.toLowerCase().endsWith(extensionSuffix)) {
      normalized = normalized.substring(0, normalized.length - extensionSuffix.length).trim();
    }
    if (normalized.length === 0) {
      throw new Error('录音名称不能为空。');
    }
    if (normalized.length > 80) {
      throw new Error('录音名称不能超过 80 个字符。');
    }
    const forbidden: string[] = ['/', '\\', ':', '*', '?', '"', '<', '>', '|'];
    for (let index = 0; index < forbidden.length; index++) {
      if (normalized.indexOf(forbidden[index]) >= 0) {
        throw new Error('录音名称不能包含文件路径或保留字符。');
      }
    }
    return normalized;
  }

  private static listDirectory(directory: string, indexFileName: string, isRecentlyDeleted: boolean): RecordingInfo[] {
    const fromIndex = RecordingRepository.readIndex(directory, indexFileName);
    const existing: RecordingInfo[] = [];
    for (let index = 0; index < fromIndex.length; index++) {
      const item = fromIndex[index];
      if (RecordingRepository.isExistingFile(item.filePath)) {
        item.sizeBytes = RecordingRepository.readFileSize(item.filePath);
        existing.push(item);
      }
    }

    const knownIds: string[] = existing.map((item: RecordingInfo): string => item.id);
    const scanned = RecordingRepository.scanRecordings(directory, isRecentlyDeleted);
    for (let index = 0; index < scanned.length; index++) {
      const item = scanned[index];
      if (knownIds.indexOf(item.id) < 0) {
        existing.push(item);
      }
    }

    existing.sort((left: RecordingInfo, right: RecordingInfo): number => {
      const leftTime = isRecentlyDeleted ? left.deletedAt : left.createdAt;
      const rightTime = isRecentlyDeleted ? right.deletedAt : right.createdAt;
      return rightTime - leftTime;
    });
    RecordingRepository.writeIndex(directory, indexFileName, existing);
    return existing;
  }

  private static ensureRecordingsDirectory(context: common.Context): string {
    return RecordingRepository.ensureChildDirectory(context, RecordingRepository.RECORDINGS_DIRECTORY);
  }

  private static ensureRecentlyDeletedDirectory(context: common.Context): string {
    const recordingsDirectory = RecordingRepository.ensureRecordingsDirectory(context);
    return RecordingRepository.ensureDirectory(`${recordingsDirectory}/${RecordingRepository.RECENTLY_DELETED_DIRECTORY}`);
  }

  private static ensureChildDirectory(context: common.Context, directoryName: string): string {
    return RecordingRepository.ensureDirectory(`${context.filesDir}/${directoryName}`);
  }

  private static ensureDirectory(directory: string): string {
    try {
      const stat = fileIo.statSync(directory);
      if (stat.isDirectory()) {
        return directory;
      }
    } catch (error) {
      try {
        fileIo.mkdirSync(directory, true);
        return directory;
      } catch (mkdirError) {
        throw new Error(`Unable to create recording directory: ${String(mkdirError)}`);
      }
    }
    throw new Error('The recording path exists but is not a directory.');
  }

  private static scanRecordings(directory: string, isRecentlyDeleted: boolean): RecordingInfo[] {
    const recordings: RecordingInfo[] = [];
    let fileNames: string[] = [];
    try {
      fileNames = fileIo.listFileSync(directory);
    } catch (error) {
      return recordings;
    }
    for (let index = 0; index < fileNames.length; index++) {
      const fileName = fileNames[index];
      const extensionIndex = fileName.lastIndexOf('.');
      if (extensionIndex < 0) {
        continue;
      }
      const extension = fileName.substring(extensionIndex + 1).toLowerCase();
      if (extension !== 'wav' && extension !== 'm4a') {
        continue;
      }
      const format = extension === RecordingFormat.WAV ? RecordingFormat.WAV : RecordingFormat.M4A;
      const config = format === RecordingFormat.WAV ? RecordingConfig.wav() : RecordingConfig.aac(128000);
      const filePath = `${directory}/${fileName}`;
      const createdAt = TimeUtils.parseTimestampFromFileName(fileName);
      const durationMs = RecordingRepository.estimateWavDuration(filePath, config);
      const deletedAt = isRecentlyDeleted ? Math.max(createdAt, Date.now()) : 0;
      recordings.push(new RecordingInfo(fileName, filePath, config, durationMs, createdAt,
        RecordingRepository.readFileSize(filePath), deletedAt, isRecentlyDeleted ? fileName : ''));
    }
    return recordings;
  }

  private static estimateWavDuration(filePath: string, config: RecordingConfig): number {
    if (config.format !== RecordingFormat.WAV) {
      return 0;
    }
    const fileSize = RecordingRepository.readFileSize(filePath);
    return WaveFileUtils.calculateDurationMs(Math.max(0, fileSize - WaveFileUtils.HEADER_LENGTH), config);
  }

  private static isExistingFile(path: string): boolean {
    try {
      return fileIo.statSync(path).isFile();
    } catch (error) {
      return false;
    }
  }

  private static readFileSize(path: string): number {
    try {
      return fileIo.statSync(path).size;
    } catch (error) {
      return 0;
    }
  }

  private static createUniqueRecordingFileName(directory: string, extension: string, timestamp: number): string {
    return RecordingRepository.createAvailableFileName(directory, TimeUtils.createRecordingFileName(extension, timestamp));
  }

  private static createAvailableFileName(directory: string, desiredFileName: string): string {
    if (!RecordingRepository.isExistingFile(`${directory}/${desiredFileName}`)) {
      return desiredFileName;
    }
    const extensionIndex = desiredFileName.lastIndexOf('.');
    const baseName = extensionIndex > 0 ? desiredFileName.substring(0, extensionIndex) : desiredFileName;
    const extension = extensionIndex > 0 ? desiredFileName.substring(extensionIndex) : '';
    let duplicateIndex = 1;
    let candidate = `${baseName}_${duplicateIndex}${extension}`;
    while (RecordingRepository.isExistingFile(`${directory}/${candidate}`)) {
      duplicateIndex += 1;
      candidate = `${baseName}_${duplicateIndex}${extension}`;
    }
    return candidate;
  }

  private static readIndex(directory: string, indexFileName: string): RecordingInfo[] {
    const indexPath = `${directory}/${indexFileName}`;
    let content = '';
    try {
      content = fileIo.readTextSync(indexPath);
    } catch (error) {
      return [];
    }
    const recordings: RecordingInfo[] = [];
    const lines = content.split('\n');
    for (let index = 0; index < lines.length; index++) {
      const item = RecordingRepository.parseLine(directory, lines[index]);
      if (item !== undefined) {
        recordings.push(item);
      }
    }
    return recordings;
  }

  private static writeIndex(directory: string, indexFileName: string, recordings: RecordingInfo[]): void {
    recordings.sort((left: RecordingInfo, right: RecordingInfo): number => {
      const leftTime = left.isInRecentlyDeleted ? left.deletedAt : left.createdAt;
      const rightTime = right.isInRecentlyDeleted ? right.deletedAt : right.createdAt;
      return rightTime - leftTime;
    });
    const content = recordings.map((item: RecordingInfo): string => RecordingRepository.serialize(item)).join('\n');
    const indexPath = `${directory}/${indexFileName}`;
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(indexPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, content);
      fileIo.fsyncSync(file.fd);
    } catch (error) {
      throw new Error(`Unable to write recording index: ${String(error)}`);
    } finally {
      if (file !== undefined) {
        try {
          fileIo.closeSync(file);
        } catch (error) {
          console.error(`Close recording index failed: ${String(error)}`);
        }
      }
    }
  }

  private static serialize(recording: RecordingInfo): string {
    const config = recording.config;
    return [
      recording.fileName,
      config.format,
      config.sampleRate.toString(),
      config.bitDepth.toString(),
      config.bitrate.toString(),
      config.channels.toString(),
      recording.durationMs.toString(),
      recording.createdAt.toString(),
      recording.sizeBytes.toString(),
      recording.deletedAt.toString(),
      recording.originalFileName
    ].join('|');
  }

  private static parseLine(directory: string, line: string): RecordingInfo | undefined {
    const parts = line.split('|');
    if (parts.length < 8 || parts.length > 11 || parts[0].length === 0) {
      return undefined;
    }
    const format = parts[1] === RecordingFormat.M4A ? RecordingFormat.M4A : RecordingFormat.WAV;
    const config = new RecordingConfig(format, Number(parts[2]), Number(parts[3]), Number(parts[4]), Number(parts[5]));
    const durationMs = Number(parts[6]);
    const createdAt = Number(parts[7]);
    const sizeBytes = parts.length >= 9 ? Number(parts[8]) : 0;
    const deletedAt = parts.length >= 10 ? Number(parts[9]) : 0;
    const originalFileName = parts.length >= 11 ? parts[10] : '';
    if (isNaN(config.sampleRate) || isNaN(config.bitDepth) || isNaN(config.bitrate) || isNaN(config.channels) ||
      isNaN(durationMs) || isNaN(createdAt) || isNaN(sizeBytes) || isNaN(deletedAt)) {
      return undefined;
    }
    return new RecordingInfo(parts[0], `${directory}/${parts[0]}`, config, durationMs, createdAt,
      Math.max(0, sizeBytes), Math.max(0, deletedAt), originalFileName);
  }

  private static findById(recordings: RecordingInfo[], id: string): RecordingInfo | undefined {
    for (let index = 0; index < recordings.length; index++) {
      if (recordings[index].id === id) {
        return recordings[index];
      }
    }
    return undefined;
  }
}
