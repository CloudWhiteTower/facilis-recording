import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { RecordingConfig, RecordingFormat, RecordingInfo } from '../models/RecordingTypes';
import { TimeUtils } from '../utils/TimeUtils';
import { WaveFileUtils } from '../utils/WaveFileUtils';
import { AudioFileUtils } from '../utils/AudioFileUtils';

export enum RecordingBatchAction {
  MOVE_TO_TRASH = 'move',
  RESTORE = 'restore',
  PERMANENTLY_DELETE = 'delete'
}

export class RecordingBatchResult {
  readonly completedIds: string[] = [];
  readonly failedIds: string[] = [];
}

export class RecordingFileMetadata {
  readonly config: RecordingConfig;
  readonly durationMs: number;

  constructor(config: RecordingConfig, durationMs: number) {
    this.config = config;
    this.durationMs = durationMs;
  }
}

class RecordingLibrarySnapshot {
  active: RecordingInfo[];
  trash: RecordingInfo[];
  revision: number;

  constructor(active: RecordingInfo[], trash: RecordingInfo[], revision: number) {
    this.active = active;
    this.trash = trash;
    this.revision = revision;
  }
}

export class RecordingRepository {
  private static readonly RECORDINGS_DIRECTORY: string = 'recordings';
  private static readonly RECENTLY_DELETED_DIRECTORY: string = 'recently_deleted';
  private static readonly EXPORTS_DIRECTORY: string = 'exports';
  private static readonly INDEX_FILE: string = 'recordings.index';
  private static readonly TRASH_INDEX_FILE: string = 'recently_deleted.index';
  private static readonly TRANSACTION_FILE: string = 'recordings.transaction';
  private static readonly reservedPaths: Set<string> = new Set<string>();
  private static readonly unreadableCounts: Map<string, number> = new Map<string, number>();
  private static revision: number = 0;

  static createNewRecording(context: common.Context, config: RecordingConfig): RecordingInfo {
    const directory = RecordingRepository.ensureRecordingsDirectory(context);
    const createdAt = Date.now();
    const fileName = RecordingRepository.createUniqueRecordingFileName(directory, config.extension, createdAt);
    RecordingRepository.reservedPaths.add(`${directory}/${fileName}`);
    return new RecordingInfo(fileName, `${directory}/${fileName}`, config, 0, createdAt);
  }

  static list(context: common.Context): RecordingInfo[] {
    RecordingRepository.recoverTransaction(context);
    const directory = RecordingRepository.ensureRecordingsDirectory(context);
    return RecordingRepository.listDirectory(directory, RecordingRepository.INDEX_FILE, false);
  }

  static listRecentlyDeleted(context: common.Context): RecordingInfo[] {
    RecordingRepository.recoverTransaction(context);
    const directory = RecordingRepository.ensureRecentlyDeletedDirectory(context);
    return RecordingRepository.listDirectory(directory, RecordingRepository.TRASH_INDEX_FILE, true);
  }

  static getRecentlyDeletedCount(context: common.Context): number {
    return RecordingRepository.listRecentlyDeleted(context).length;
  }

  static save(context: common.Context, recording: RecordingInfo): RecordingInfo {
    const directory = RecordingRepository.ensureRecordingsDirectory(context);
    if (recording.isInRecentlyDeleted) {
      throw new Error('最近删除中的录音必须先恢复。');
    }
    const verified = RecordingRepository.inspectRecording(context, recording);
    const recordings = RecordingRepository.list(context).filter((item: RecordingInfo): boolean => item.id !== recording.id);
    recordings.push(verified);
    RecordingRepository.writeIndex(directory, RecordingRepository.INDEX_FILE, recordings);
    RecordingRepository.reservedPaths.delete(recording.filePath);
    return verified;
  }

  static inspectRecording(context: common.Context, recording: RecordingInfo): RecordingInfo {
    RecordingRepository.validateRecordingPath(context, recording);
    const metadata = AudioFileUtils.read(recording.filePath, recording.extension);
    if (metadata === undefined) {
      throw new Error('录音文件不完整、已损坏或格式不受支持；原文件已保留。');
    }
    return new RecordingInfo(recording.fileName, recording.filePath, metadata.config, metadata.durationMs,
      recording.createdAt, RecordingRepository.readFileSize(recording.filePath), recording.deletedAt,
      recording.originalFileName);
  }

  static validateRecordingPath(context: common.Context, recording: RecordingInfo): string {
    const directory = recording.isInRecentlyDeleted ? RecordingRepository.ensureRecentlyDeletedDirectory(context) :
      RecordingRepository.ensureRecordingsDirectory(context);
    if (!RecordingRepository.isSafeFileName(recording.fileName) || recording.id !== recording.fileName ||
      !['wav', 'm4a', 'flac'].includes(recording.extension) ||
      recording.filePath !== `${directory}/${recording.fileName}` || !RecordingRepository.isExistingFile(recording.filePath)) {
      throw new Error('录音文件已移动或不存在，请重新进入资料库。');
    }
    return recording.filePath;
  }

  // Call after list()/listRecentlyDeleted(). No second directory scan is needed for a UI warning.
  static getUnreadableCount(context: common.Context, recentlyDeleted: boolean = false): number {
    const directory = `${context.filesDir}/${RecordingRepository.RECORDINGS_DIRECTORY}` +
      (recentlyDeleted ? `/${RecordingRepository.RECENTLY_DELETED_DIRECTORY}` : '');
    return RecordingRepository.unreadableCounts.get(directory) ?? 0;
  }

  static importCompletedFile(context: common.Context, temporaryPath: string, config: RecordingConfig,
    displayName: string = ''): RecordingInfo {
    if (!temporaryPath.startsWith(`${context.cacheDir}/`) || temporaryPath.includes('\\') ||
      temporaryPath.split('/').some((part: string): boolean => part === '..' || part === '.')) {
      throw new Error('只能登记本应用缓存目录中的已完成音频。');
    }
    const metadata = AudioFileUtils.read(temporaryPath, config.extension);
    if (metadata === undefined) {
      throw new Error('转换后的音频文件未完成或不受支持，未加入资料库。');
    }
    const directory = RecordingRepository.ensureRecordingsDirectory(context);
    const createdAt = Date.now();
    const desired = displayName.length > 0 ?
      `${RecordingRepository.normalizeDisplayName(displayName, config.extension)}.${config.extension}` :
      TimeUtils.createRecordingFileName(config.extension, createdAt);
    const fileName = RecordingRepository.createAvailableFileName(directory, desired);
    const target = `${directory}/${fileName}`;
    RecordingRepository.reservedPaths.add(target);
    let moved = false;
    try {
      fileIo.renameSync(temporaryPath, target);
      moved = true;
      return RecordingRepository.save(context, new RecordingInfo(fileName, target, metadata.config,
        metadata.durationMs, createdAt, RecordingRepository.readFileSize(target)));
    } catch (error) {
      if (moved) {
        // A failed registration leaves the completed source available for retry.
        fileIo.renameSync(target, temporaryPath);
      }
      throw new Error((error as Error).message || String(error));
    } finally {
      RecordingRepository.reservedPaths.delete(target);
    }
  }

  static rename(context: common.Context, recording: RecordingInfo, requestedName: string): RecordingInfo {
    if (recording.isInRecentlyDeleted) {
      throw new Error('Recently deleted recordings must be restored before they can be renamed.');
    }
    const directory = RecordingRepository.ensureRecordingsDirectory(context);
    const recordings = RecordingRepository.list(context);
    const existing = RecordingRepository.findById(recordings, recording.id);
    if (existing === undefined || existing.filePath !== recording.filePath || existing.createdAt !== recording.createdAt ||
      !RecordingRepository.isExistingFile(existing.filePath)) {
      throw new Error('The recording is no longer available.');
    }
    const displayName = RecordingRepository.normalizeDisplayName(requestedName, existing.extension);
    const desiredFileName = `${displayName}.${existing.extension}`;
    if (desiredFileName === existing.fileName) {
      return existing;
    }
    const fileName = RecordingRepository.createAvailableFileName(directory, desiredFileName);
    const filePath = `${directory}/${fileName}`;
    const renamed = new RecordingInfo(fileName, filePath, existing.config, existing.durationMs, existing.createdAt,
      existing.sizeBytes, 0, '');
    const updated = recordings.filter((item: RecordingInfo): boolean => item.id !== existing.id);
    updated.push(renamed);
    RecordingRepository.commitTransfer(context, 'rename', existing, renamed, updated, []);
    return renamed;
  }

  static moveToRecentlyDeleted(context: common.Context, recording: RecordingInfo): RecordingInfo {
    return RecordingRepository.moveWithSnapshot(context, recording, RecordingRepository.librarySnapshot(context));
  }

  private static moveWithSnapshot(context: common.Context, recording: RecordingInfo,
    snapshot: RecordingLibrarySnapshot): RecordingInfo {
    if (recording.isInRecentlyDeleted) {
      throw new Error('The recording is already in recently deleted.');
    }
    const recordings = snapshot.active;
    const existing = RecordingRepository.findById(recordings, recording.id);
    if (existing === undefined || existing.filePath !== recording.filePath || existing.createdAt !== recording.createdAt ||
      !RecordingRepository.isExistingFile(existing.filePath)) {
      throw new Error('The recording is no longer available.');
    }
    const recentlyDeletedDirectory = RecordingRepository.ensureRecentlyDeletedDirectory(context);
    const recentlyDeleted = snapshot.trash;
    const fileName = RecordingRepository.createAvailableFileName(recentlyDeletedDirectory, existing.fileName);
    const filePath = `${recentlyDeletedDirectory}/${fileName}`;
    const moved = new RecordingInfo(fileName, filePath, existing.config, existing.durationMs, existing.createdAt,
      existing.sizeBytes, Date.now(), existing.fileName);
    const active = recordings.filter((item: RecordingInfo): boolean => item.id !== existing.id);
    const trash = recentlyDeleted.concat([moved]);
    RecordingRepository.commitTransfer(context, 'move', existing, moved, active, trash);
    snapshot.active = active;
    snapshot.trash = trash;
    snapshot.revision = RecordingRepository.revision;
    return moved;
  }

  static restore(context: common.Context, recording: RecordingInfo): RecordingInfo {
    return RecordingRepository.restoreWithSnapshot(context, recording, RecordingRepository.librarySnapshot(context));
  }

  private static restoreWithSnapshot(context: common.Context, recording: RecordingInfo,
    snapshot: RecordingLibrarySnapshot): RecordingInfo {
    if (!recording.isInRecentlyDeleted) {
      throw new Error('The recording is not in recently deleted.');
    }
    const recentlyDeleted = snapshot.trash;
    const existing = RecordingRepository.findById(recentlyDeleted, recording.id);
    if (existing === undefined || existing.filePath !== recording.filePath || existing.createdAt !== recording.createdAt ||
      !RecordingRepository.isExistingFile(existing.filePath)) {
      throw new Error('The deleted recording is no longer available.');
    }
    const recordingsDirectory = RecordingRepository.ensureRecordingsDirectory(context);
    const recordings = snapshot.active;
    const preferredName = existing.originalFileName.length > 0 ? existing.originalFileName : existing.fileName;
    const fileName = RecordingRepository.createAvailableFileName(recordingsDirectory, preferredName);
    const filePath = `${recordingsDirectory}/${fileName}`;
    const restored = new RecordingInfo(fileName, filePath, existing.config, existing.durationMs, existing.createdAt,
      existing.sizeBytes);
    const remaining = recentlyDeleted.filter((item: RecordingInfo): boolean => item.id !== existing.id);
    const active = recordings.concat([restored]);
    RecordingRepository.commitTransfer(context, 'restore', existing, restored, active, remaining);
    snapshot.active = active;
    snapshot.trash = remaining;
    snapshot.revision = RecordingRepository.revision;
    return restored;
  }

  static permanentlyDelete(context: common.Context, recording: RecordingInfo): void {
    RecordingRepository.deleteWithSnapshot(context, recording, RecordingRepository.librarySnapshot(context));
  }

  private static deleteWithSnapshot(context: common.Context, recording: RecordingInfo,
    snapshot: RecordingLibrarySnapshot): void {
    if (!recording.isInRecentlyDeleted) {
      throw new Error('Only recently deleted recordings can be permanently removed.');
    }
    const directory = RecordingRepository.ensureRecentlyDeletedDirectory(context);
    const recentlyDeleted = snapshot.trash;
    const existing = RecordingRepository.findById(recentlyDeleted, recording.id);
    if (existing === undefined) {
      // An unindexed file with an unreadable header can be absent from the scan but still occupy disk.
      // Only a missing path is an idempotent success; never claim that existing bytes were removed.
      const expectedPath = `${directory}/${recording.fileName}`;
      if (!RecordingRepository.isSafeFileName(recording.fileName) || recording.filePath !== expectedPath ||
        fileIo.accessSync(expectedPath)) {
        throw new Error('The selected recording cannot be safely matched to a stored file.');
      }
      return;
    }
    if (existing.filePath !== recording.filePath || existing.createdAt !== recording.createdAt) {
      throw new Error('The selected recording no longer matches the stored file.');
    }
    const remaining = recentlyDeleted.filter((item: RecordingInfo): boolean => item.id !== existing.id);
    RecordingRepository.prepareTransaction(context, 'delete', existing, existing);
    try {
      // Unlink is the irreversible commit point: complete fallible metadata work first.
      RecordingRepository.writeIndex(directory, RecordingRepository.TRASH_INDEX_FILE, remaining);
      fileIo.unlinkSync(existing.filePath);
    } catch (error) {
      RecordingRepository.recoverTransaction(context);
      throw new Error(`Unable to permanently delete recording: ${String(error)}`);
    }
    RecordingRepository.clearTransaction(context);
    snapshot.trash = remaining;
    snapshot.revision = RecordingRepository.revision;
  }

  static applyBatch(context: common.Context, recordings: RecordingInfo[], action: RecordingBatchAction): RecordingBatchResult {
    const result = new RecordingBatchResult();
    const seen = new Set<string>();
    let snapshot = RecordingRepository.librarySnapshot(context);
    for (const recording of recordings) {
      if (seen.has(recording.id)) {
        continue;
      }
      seen.add(recording.id);
      snapshot = RecordingRepository.applyBatchItem(context, recording, action, snapshot, result);
    }
    return result;
  }

  static async applyBatchAsync(context: common.Context, recordings: RecordingInfo[],
    action: RecordingBatchAction): Promise<RecordingBatchResult> {
    const result = new RecordingBatchResult();
    const seen = new Set<string>();
    // Yield before the first scan and between transactions so the busy state,
    // native sheets and input events can render while a large batch is processed.
    await RecordingRepository.yieldToUI();
    let snapshot = RecordingRepository.librarySnapshot(context);
    for (const recording of recordings) {
      if (seen.has(recording.id)) { continue; }
      seen.add(recording.id);
      snapshot = RecordingRepository.applyBatchItem(context, recording, action, snapshot, result);
      await RecordingRepository.yieldToUI();
    }
    return result;
  }

  private static yieldToUI(): Promise<void> {
    return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 16); });
  }

  private static librarySnapshot(context: common.Context): RecordingLibrarySnapshot {
    const active = RecordingRepository.list(context);
    const trash = RecordingRepository.listRecentlyDeleted(context);
    return new RecordingLibrarySnapshot(active, trash, RecordingRepository.revision);
  }

  private static applyBatchItem(context: common.Context, recording: RecordingInfo, action: RecordingBatchAction,
    snapshot: RecordingLibrarySnapshot, result: RecordingBatchResult): RecordingLibrarySnapshot {
    try {
      if (snapshot.revision !== RecordingRepository.revision) {
        // A recording/conversion may be saved while the batch yields, or a
        // failed transaction may have rolled back. Catch refresh failures per
        // item so already committed successes remain visible in the result.
        snapshot = RecordingRepository.librarySnapshot(context);
      }
      if (action === RecordingBatchAction.MOVE_TO_TRASH) {
        RecordingRepository.moveWithSnapshot(context, recording, snapshot);
      } else if (action === RecordingBatchAction.RESTORE) {
        RecordingRepository.restoreWithSnapshot(context, recording, snapshot);
      } else if (action === RecordingBatchAction.PERMANENTLY_DELETE) {
        RecordingRepository.deleteWithSnapshot(context, recording, snapshot);
      } else {
        throw new Error('Unknown recording batch action.');
      }
      result.completedIds.push(recording.id);
    } catch (error) {
      result.failedIds.push(recording.id);
      console.error(`Recording batch item failed: ${String(error)}`);
      // Rollback recovery can change indexes; invalidate before the next item.
      snapshot.revision = -1;
    }
    return snapshot;
  }

  static discardTemporary(recording: RecordingInfo): void {
    if (!RecordingRepository.reservedPaths.has(recording.filePath)) {
      throw new Error('只能放弃本次尚未保存的录音，已保存文件请从资料库删除。');
    }
    if (recording.filePath.length > 0 && RecordingRepository.isExistingFile(recording.filePath)) {
      fileIo.unlinkSync(recording.filePath);
    }
    RecordingRepository.reservedPaths.delete(recording.filePath);
  }

  static releaseTemporaryReservation(recording: RecordingInfo): void {
    RecordingRepository.reservedPaths.delete(recording.filePath);
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
    const forbidden: string[] = ['/', '\\', ':', '*', '?', '"', '<', '>', '|', '\n', '\r', '\0'];
    for (let index = 0; index < forbidden.length; index++) {
      if (normalized.indexOf(forbidden[index]) >= 0) {
        throw new Error('录音名称不能包含文件路径或保留字符。');
      }
    }
    return normalized;
  }

  private static listDirectory(directory: string, indexFileName: string, isRecentlyDeleted: boolean): RecordingInfo[] {
    RecordingRepository.unreadableCounts.set(directory, 0);
    const fromIndex = RecordingRepository.readIndex(directory, indexFileName);
    const existing: RecordingInfo[] = [];
    for (let index = 0; index < fromIndex.length; index++) {
      const item = fromIndex[index];
      // The containing directory is authoritative, including older eight-field indexes without trash metadata.
      item.deletedAt = isRecentlyDeleted ? Math.max(1, item.deletedAt) : 0;
      item.originalFileName = isRecentlyDeleted ? (item.originalFileName || item.fileName) : '';
      if (RecordingRepository.isExistingFile(item.filePath)) {
        item.sizeBytes = RecordingRepository.readFileSize(item.filePath);
        const metadata = RecordingRepository.readAudioMetadata(item.filePath, item.extension, item.sizeBytes);
        if (metadata === undefined) {
          // Keep indexed damaged files visible for export/recovery or explicit deletion; never erase their bytes.
          RecordingRepository.countUnreadable(directory);
          existing.push(new RecordingInfo(item.fileName, item.filePath,
            new RecordingConfig(item.config.format, 0, 0, 0, 0), 0,
            item.createdAt, item.sizeBytes, item.deletedAt, item.originalFileName));
        } else {
          existing.push(new RecordingInfo(item.fileName, item.filePath, metadata.config, metadata.durationMs,
            item.createdAt, item.sizeBytes, item.deletedAt, item.originalFileName));
        }
      }
    }

    const knownIds: string[] = existing.map((item: RecordingInfo): string => item.id);
    const scanned = RecordingRepository.scanRecordings(directory, isRecentlyDeleted, knownIds);
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

  private static scanRecordings(directory: string, isRecentlyDeleted: boolean, knownIds: string[]): RecordingInfo[] {
    const recordings: RecordingInfo[] = [];
    const known = new Set<string>(knownIds);
    const fileNames = fileIo.listFileSync(directory);
    for (let index = 0; index < fileNames.length; index++) {
      const fileName = fileNames[index];
      if (known.has(fileName) || RecordingRepository.reservedPaths.has(`${directory}/${fileName}`)) {
        continue;
      }
      const extensionIndex = fileName.lastIndexOf('.');
      if (extensionIndex < 0) {
        continue;
      }
      const extension = fileName.substring(extensionIndex + 1).toLowerCase();
      if (!RecordingRepository.isSafeFileName(fileName) ||
        (extension !== 'wav' && extension !== 'm4a' && extension !== 'flac')) {
        continue;
      }
      const filePath = `${directory}/${fileName}`;
      if (!RecordingRepository.isExistingFile(filePath)) {
        continue;
      }
      const sizeBytes = RecordingRepository.readFileSize(filePath);
      const metadata = RecordingRepository.readAudioMetadata(filePath, extension, sizeBytes);
      const createdAt = TimeUtils.parseTimestampFromFileName(fileName);
      const deletedAt = isRecentlyDeleted ? Math.max(1, createdAt) : 0;
      if (metadata === undefined) {
        RecordingRepository.countUnreadable(directory);
        // An unknown config is explicit, and keeps orphaned damaged files available for user-directed cleanup.
        recordings.push(new RecordingInfo(fileName, filePath,
          new RecordingConfig(extension as RecordingFormat, 0, 0, 0, 0), 0, createdAt,
          sizeBytes, deletedAt, isRecentlyDeleted ? fileName : ''));
        continue;
      }
      recordings.push(new RecordingInfo(fileName, filePath, metadata.config, metadata.durationMs, createdAt,
        sizeBytes, deletedAt, isRecentlyDeleted ? fileName : ''));
    }
    return recordings;
  }

  // Header-only decoding remains available for model tests; real files use AudioFileUtils.read for container bounds.
  static parseAudioMetadata(header: ArrayBuffer, extension: string, sizeBytes: number): RecordingFileMetadata | undefined {
    const data = new DataView(header);
    if (extension === 'flac') {
      if (header.byteLength < 42 || data.getUint32(0, false) !== 0x664C6143 ||
        (data.getUint8(4) & 0x7F) !== 0 || data.getUint32(4, false) % 0x1000000 !== 34) {
        return undefined;
      }
      const sampleRate = data.getUint8(18) * 4096 + data.getUint8(19) * 16 + (data.getUint8(20) >> 4);
      const channels = ((data.getUint8(20) >> 1) & 7) + 1;
      const bitDepth = ((data.getUint8(20) & 1) * 16 + (data.getUint8(21) >> 4)) + 1;
      const totalSamples = (data.getUint8(21) & 15) * 4294967296 + data.getUint32(22, false);
      if (sampleRate <= 0 || bitDepth < 4 || bitDepth > 32) {
        return undefined;
      }
      const config = new RecordingConfig(RecordingFormat.FLAC, sampleRate, bitDepth, 0, channels);
      return new RecordingFileMetadata(config, Math.floor(totalSamples * 1000 / sampleRate));
    }
    if (extension !== 'wav' || header.byteLength < 44 || data.getUint32(0, false) !== 0x52494646 ||
      data.getUint32(8, false) !== 0x57415645 || data.getUint32(12, false) !== 0x666D7420 ||
      data.getUint32(16, true) !== 16 || data.getUint16(20, true) !== 1 ||
      data.getUint32(36, false) !== 0x64617461) {
      return undefined;
    }
    const channels = data.getUint16(22, true);
    const sampleRate = data.getUint32(24, true);
    const bitDepth = data.getUint16(34, true);
    if (channels <= 0 || sampleRate <= 0 || (bitDepth !== 16 && bitDepth !== 24)) {
      return undefined;
    }
    const config = new RecordingConfig(RecordingFormat.WAV, sampleRate, bitDepth, 0, channels);
    const dataLength = Math.min(data.getUint32(40, true), Math.max(0, sizeBytes - WaveFileUtils.HEADER_LENGTH));
    return new RecordingFileMetadata(config, Math.floor(dataLength * 1000 / (sampleRate * channels * bitDepth / 8)));
  }

  private static readAudioMetadata(filePath: string, extension: string, sizeBytes: number): RecordingFileMetadata | undefined {
    const actual = AudioFileUtils.read(filePath, extension);
    return actual === undefined ? undefined : new RecordingFileMetadata(actual.config, actual.durationMs);
  }

  private static countUnreadable(directory: string): void {
    RecordingRepository.unreadableCounts.set(directory, (RecordingRepository.unreadableCounts.get(directory) ?? 0) + 1);
  }

  private static isExistingFile(path: string): boolean {
    if (!fileIo.accessSync(path)) {
      return false;
    }
    return fileIo.statSync(path).isFile();
  }

  private static readFileSize(path: string): number {
    return fileIo.statSync(path).size;
  }

  private static createUniqueRecordingFileName(directory: string, extension: string, timestamp: number): string {
    return RecordingRepository.createAvailableFileName(directory, TimeUtils.createRecordingFileName(extension, timestamp));
  }

  private static createAvailableFileName(directory: string, desiredFileName: string): string {
    if (!fileIo.accessSync(`${directory}/${desiredFileName}`) &&
      !RecordingRepository.reservedPaths.has(`${directory}/${desiredFileName}`)) {
      return desiredFileName;
    }
    const extensionIndex = desiredFileName.lastIndexOf('.');
    const baseName = extensionIndex > 0 ? desiredFileName.substring(0, extensionIndex) : desiredFileName;
    const extension = extensionIndex > 0 ? desiredFileName.substring(extensionIndex) : '';
    let duplicateIndex = 1;
    let candidate = `${baseName}_${duplicateIndex}${extension}`;
    while (fileIo.accessSync(`${directory}/${candidate}`) || RecordingRepository.reservedPaths.has(`${directory}/${candidate}`)) {
      duplicateIndex += 1;
      candidate = `${baseName}_${duplicateIndex}${extension}`;
    }
    return candidate;
  }

  private static readIndex(directory: string, indexFileName: string): RecordingInfo[] {
    const indexPath = `${directory}/${indexFileName}`;
    if (!fileIo.accessSync(indexPath)) {
      return [];
    }
    const content = fileIo.readTextSync(indexPath);
    const recordings: RecordingInfo[] = [];
    const seenIds = new Set<string>();
    const lines = content.split('\n');
    for (let index = 0; index < lines.length; index++) {
      const item = RecordingRepository.parseLine(directory, lines[index]);
      if (item !== undefined && !seenIds.has(item.id)) {
        recordings.push(item);
        seenIds.add(item.id);
      }
    }
    return recordings;
  }

  private static writeIndex(directory: string, indexFileName: string, recordings: RecordingInfo[]): void {
    const sorted = recordings.slice().sort((left: RecordingInfo, right: RecordingInfo): number => {
      const leftTime = left.isInRecentlyDeleted ? left.deletedAt : left.createdAt;
      const rightTime = right.isInRecentlyDeleted ? right.deletedAt : right.createdAt;
      return rightTime - leftTime;
    });
    const content = sorted.map((item: RecordingInfo): string => RecordingRepository.serialize(item)).join('\n');
    RecordingRepository.writeTextAtomically(`${directory}/${indexFileName}`, content);
    ++RecordingRepository.revision;
  }

  private static writeTextAtomically(path: string, content: string): void {
    const temporaryPath = `${path}.tmp`;
    let file: fileIo.File | undefined = undefined;
    try {
      // API 24 can return undefined for encodeInto(''); an empty index must still be fsynced and replaced.
      const bytes = content.length === 0 ? new Uint8Array(0) : new util.TextEncoder().encodeInto(content);
      file = fileIo.openSync(temporaryPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      let written = 0;
      while (written < bytes.byteLength) {
        const count = fileIo.writeSync(file.fd, bytes.buffer.slice(bytes.byteOffset + written, bytes.byteOffset + bytes.byteLength));
        if (count <= 0) {
          throw new Error('Unable to complete metadata write.');
        }
        written += count;
      }
      fileIo.fsyncSync(file.fd);
      fileIo.closeSync(file);
      file = undefined;
      fileIo.renameSync(temporaryPath, path);
    } catch (error) {
      throw new Error(`Unable to replace recording metadata: ${String(error)}`);
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
    if (parts.length < 8 || parts.length > 11 || !RecordingRepository.isSafeFileName(parts[0])) {
      return undefined;
    }
    if (parts[1] !== RecordingFormat.WAV && parts[1] !== RecordingFormat.M4A && parts[1] !== RecordingFormat.FLAC) {
      return undefined;
    }
    const format = parts[1] as RecordingFormat;
    if (!parts[0].toLowerCase().endsWith(`.${format}`)) {
      return undefined;
    }
    const config = new RecordingConfig(format, Number(parts[2]), Number(parts[3]), Number(parts[4]), Number(parts[5]));
    const durationMs = Number(parts[6]);
    const createdAt = Number(parts[7]);
    const sizeBytes = parts.length >= 9 ? Number(parts[8]) : 0;
    const deletedAt = parts.length >= 10 ? Number(parts[9]) : 0;
    const originalFileName = parts.length >= 11 ? parts[10] : '';
    if (!Number.isFinite(config.sampleRate) || !Number.isFinite(config.bitDepth) || !Number.isFinite(config.bitrate) ||
      !Number.isFinite(config.channels) || !Number.isFinite(durationMs) || !Number.isFinite(createdAt) ||
      !Number.isFinite(sizeBytes) || !Number.isFinite(deletedAt) || config.sampleRate < 0 || config.channels < 0 ||
      !Number.isInteger(config.sampleRate) || !Number.isInteger(config.channels) || config.bitDepth < 0 ||
      config.bitrate < 0 || durationMs < 0 || createdAt < 0 ||
      (originalFileName.length > 0 && !RecordingRepository.isSafeFileName(originalFileName))) {
      return undefined;
    }
    if ((config.sampleRate === 0 || config.channels === 0) &&
      (config.sampleRate !== 0 || config.channels !== 0 || config.bitDepth !== 0 || config.bitrate !== 0 || durationMs !== 0)) {
      return undefined;
    }
    return new RecordingInfo(parts[0], `${directory}/${parts[0]}`, config, durationMs, createdAt,
      Math.max(0, sizeBytes), Math.max(0, deletedAt), originalFileName);
  }

  private static isSafeFileName(name: string): boolean {
    return name.length > 0 && name !== '.' && name !== '..' &&
      !name.includes('/') && !name.includes('\\') && !name.includes('|') &&
      !name.includes('\n') && !name.includes('\r') && !name.includes('\0');
  }

  private static prepareTransaction(context: common.Context, operation: string,
    source: RecordingInfo, target: RecordingInfo): void {
    const path = `${RecordingRepository.ensureRecordingsDirectory(context)}/${RecordingRepository.TRANSACTION_FILE}`;
    if (fileIo.accessSync(path)) {
      throw new Error('A previous recording transaction still needs recovery.');
    }
    RecordingRepository.writeTransaction(context, operation, source, target, false);
  }

  private static writeTransaction(context: common.Context, operation: string,
    source: RecordingInfo, target: RecordingInfo, committed: boolean): void {
    const path = `${RecordingRepository.ensureRecordingsDirectory(context)}/${RecordingRepository.TRANSACTION_FILE}`;
    const content = [committed ? 'committed' : 'prepared', operation,
      RecordingRepository.serialize(source), RecordingRepository.serialize(target)].join('\n');
    RecordingRepository.writeTextAtomically(path, content);
  }

  private static clearTransaction(context: common.Context): void {
    const path = `${RecordingRepository.ensureRecordingsDirectory(context)}/${RecordingRepository.TRANSACTION_FILE}`;
    // A cleanup failure must not turn a completed irreversible deletion into a reported failure.
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
    } catch (error) {
      console.error(`Recording transaction cleanup deferred: ${String(error)}`);
    }
  }

  private static commitTransfer(context: common.Context, operation: string, source: RecordingInfo,
    target: RecordingInfo, active: RecordingInfo[], trash: RecordingInfo[]): void {
    RecordingRepository.prepareTransaction(context, operation, source, target);
    try {
      fileIo.renameSync(source.filePath, target.filePath);
      const activeDirectory = RecordingRepository.ensureRecordingsDirectory(context);
      const trashDirectory = RecordingRepository.ensureRecentlyDeletedDirectory(context);
      RecordingRepository.writeIndex(activeDirectory, RecordingRepository.INDEX_FILE, active);
      if (operation !== 'rename') {
        RecordingRepository.writeIndex(trashDirectory, RecordingRepository.TRASH_INDEX_FILE, trash);
      }
      RecordingRepository.writeTransaction(context, operation, source, target, true);
    } catch (error) {
      // Keep the prepared journal if compensation itself fails; the next read retries recovery.
      RecordingRepository.recoverTransaction(context);
      throw new Error(`Unable to transfer recording: ${String(error)}`);
    }
    RecordingRepository.clearTransaction(context);
  }

  private static recoverTransaction(context: common.Context): void {
    const activeDirectory = RecordingRepository.ensureRecordingsDirectory(context);
    const journalPath = `${activeDirectory}/${RecordingRepository.TRANSACTION_FILE}`;
    if (!fileIo.accessSync(journalPath)) {
      return;
    }
    const lines = fileIo.readTextSync(journalPath).split('\n');
    if (lines.length !== 4 || (lines[0] !== 'prepared' && lines[0] !== 'committed') ||
      !['rename', 'move', 'restore', 'delete'].includes(lines[1])) {
      throw new Error('The pending recording transaction is invalid.');
    }
    const operation = lines[1];
    const trashDirectory = RecordingRepository.ensureRecentlyDeletedDirectory(context);
    const sourceDirectory = operation === 'restore' || operation === 'delete' ? trashDirectory : activeDirectory;
    const targetDirectory = operation === 'move' || operation === 'delete' ? trashDirectory : activeDirectory;
    const source = RecordingRepository.parseLine(sourceDirectory, lines[2]);
    const target = RecordingRepository.parseLine(targetDirectory, lines[3]);
    if (source === undefined || target === undefined) {
      throw new Error('The pending recording transaction has invalid metadata.');
    }
    if (lines[0] === 'committed') {
      RecordingRepository.clearTransaction(context);
      return;
    }
    const sourceExists = RecordingRepository.isExistingFile(source.filePath);
    if (operation === 'delete') {
      const trash = RecordingRepository.readIndex(trashDirectory, RecordingRepository.TRASH_INDEX_FILE)
        .filter((item: RecordingInfo): boolean => item.id !== source.id);
      if (sourceExists) {
        trash.push(source);
      }
      RecordingRepository.writeIndex(trashDirectory, RecordingRepository.TRASH_INDEX_FILE, trash);
      RecordingRepository.clearTransaction(context);
      return;
    }
    const targetExists = RecordingRepository.isExistingFile(target.filePath);
    if (!sourceExists && targetExists) {
      fileIo.renameSync(target.filePath, source.filePath);
    } else if (!sourceExists || targetExists) {
      throw new Error('Unable to safely recover recording paths.');
    }
    const active = RecordingRepository.readIndex(activeDirectory, RecordingRepository.INDEX_FILE)
      .filter((item: RecordingInfo): boolean => item.id !== (sourceDirectory === activeDirectory ? source.id : target.id));
    const trash = RecordingRepository.readIndex(trashDirectory, RecordingRepository.TRASH_INDEX_FILE)
      .filter((item: RecordingInfo): boolean => item.id !== (sourceDirectory === trashDirectory ? source.id : target.id));
    if (operation === 'rename') {
      const restoredIndex = active.filter((item: RecordingInfo): boolean => item.id !== target.id);
      restoredIndex.push(source);
      RecordingRepository.writeIndex(activeDirectory, RecordingRepository.INDEX_FILE, restoredIndex);
    } else {
      if (sourceDirectory === activeDirectory) {
        active.push(source);
      } else {
        trash.push(source);
      }
      RecordingRepository.writeIndex(activeDirectory, RecordingRepository.INDEX_FILE, active);
      RecordingRepository.writeIndex(trashDirectory, RecordingRepository.TRASH_INDEX_FILE, trash);
    }
    RecordingRepository.clearTransaction(context);
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
