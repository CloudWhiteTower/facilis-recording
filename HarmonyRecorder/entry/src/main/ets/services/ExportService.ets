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

export class PcmShareCleanupInfo {
  fileCount: number = 0;
  sizeBytes: number = 0;
  protectedFileCount: number = 0;
  protectedSizeBytes: number = 0;
  failedCount: number = 0;
}

export class PcmShareCleanupResult {
  removedCount: number = 0;
  removedBytes: number = 0;
  protectedFileCount: number = 0;
  protectedSizeBytes: number = 0;
  failedCount: number = 0;
}

class PcmShareCopy {
  readonly path: string;
  readonly sizeBytes: number;
  readonly createdAt: number;
  readonly legacy: boolean;
  readonly incomplete: boolean;

  constructor(path: string, sizeBytes: number, createdAt: number, legacy: boolean, incomplete: boolean) {
    this.path = path;
    this.sizeBytes = sizeBytes;
    this.createdAt = createdAt;
    this.legacy = legacy;
    this.incomplete = incomplete;
  }
}

export class ExportService {
  private static readonly COPY_BUFFER_BYTES: number = 64 * 1024;
  private static readonly SHARE_CACHE_DIRECTORY: string = 'pcm_shares';
  private static readonly SHARE_GRACE_MS: number = 24 * 60 * 60 * 1000;
  private static readonly SHARE_TTL_MS: number = 7 * 24 * 60 * 60 * 1000;
  private static readonly SHARE_MAX_FILES: number = 32;
  private static readonly SHARE_MAX_BYTES: number = 2 * 1024 * 1024 * 1024;
  private static readonly activeShares: Map<string, number> = new Map<string, number>();
  private static cacheQueue: Promise<void> = Promise.resolve();
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
    return ExportService.withCacheLock((): Promise<ExportedAudio> =>
      ExportService.createPcmShareCopy(context, recording));
  }

  // Read and delete only recognized work copies. Legacy exports are removed only after explicit user confirmation.
  static async getPcmShareCleanupInfo(context: common.Context): Promise<PcmShareCleanupInfo> {
    return ExportService.withCacheLock(async (): Promise<PcmShareCleanupInfo> => {
      const result = new PcmShareCleanupInfo();
      const copies = await ExportService.listPcmShareCopies(context, true, result);
      for (const copy of copies) {
        if (ExportService.isProtected(copy)) {
          result.protectedFileCount += 1;
          result.protectedSizeBytes += copy.sizeBytes;
        } else {
          result.fileCount += 1;
          result.sizeBytes += copy.sizeBytes;
        }
      }
      return result;
    });
  }

  static async clearPcmShareCopies(context: common.Context): Promise<PcmShareCleanupResult> {
    return ExportService.withCacheLock((): Promise<PcmShareCleanupResult> =>
      ExportService.cleanPcmShareCopies(context, true));
  }

  // Safe to call at application startup. It never visits filesDir/exports or any recording directory.
  static async prunePcmShareCache(context: common.Context): Promise<PcmShareCleanupResult> {
    return ExportService.withCacheLock((): Promise<PcmShareCleanupResult> =>
      ExportService.cleanPcmShareCopies(context, false));
  }

  // show() resolves when a panel is presented, not when a receiver has read its URI.
  // A dismiss listener releases this in-memory pin; the 24-hour grace still applies afterwards.
  static async retainPcmShareCopy(context: common.Context, filePath: string): Promise<() => void> {
    const directory = ExportService.shareCachePath(context);
    const fileName = filePath.substring(directory.length + 1);
    if (filePath !== `${directory}/${fileName}` || !ExportService.isGeneratedPcmName(fileName)) {
      return (): void => {};
    }
    return ExportService.withCacheLock(async (): Promise<() => void> => {
      const stat = await fileIo.lstat(filePath);
      if (!stat.isFile() || stat.isSymbolicLink()) { throw new Error('PCM 分享副本已失效，请重新导出。'); }
      ExportService.activeShares.set(filePath, (ExportService.activeShares.get(filePath) ?? 0) + 1);
      let retained = true;
      return (): void => {
        if (!retained) { return; }
        retained = false;
        const count = (ExportService.activeShares.get(filePath) ?? 1) - 1;
        if (count > 0) { ExportService.activeShares.set(filePath, count); }
        else { ExportService.activeShares.delete(filePath); }
      };
    });
  }

  private static async createPcmShareCopy(context: common.Context,
    recording: RecordingInfo): Promise<ExportedAudio> {
    const verified = RecordingRepository.inspectRecording(context, recording);
    if (verified.config.format !== RecordingFormat.WAV) {
      throw new Error('当前仅支持将 WAV 录音导出为原始 PCM。');
    }
    const metadata = AudioFileUtils.read(verified.filePath, verified.extension);
    if (metadata === undefined || metadata.dataLength <= 0) {
      throw new Error('WAV 文件中没有完整的 PCM 音频数据。');
    }
    const directory = ExportService.shareCachePath(context);
    await ExportService.ensureShareCacheDirectory(directory);
    await ExportService.cleanPcmShareCopies(context, false);
    const inventory = new PcmShareCleanupInfo();
    const existing = await ExportService.listPcmShareCopies(context, false, inventory);
    if (inventory.failedCount > 0) { throw new Error('无法检查 PCM 分享缓存，请稍后重试。'); }
    const totalBytes = existing.reduce((sum: number, item: PcmShareCopy): number => sum + item.sizeBytes, 0);
    if (existing.length >= ExportService.SHARE_MAX_FILES ||
      totalBytes + metadata.dataLength > ExportService.SHARE_MAX_BYTES) {
      throw new Error('PCM 分享缓存已达上限（32 份或 2 GiB），请在设置中清理旧副本；新副本需保留 24 小时。');
    }
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

  private static shareCachePath(context: common.Context): string {
    return ExportService.childDirectory(context.cacheDir, ExportService.SHARE_CACHE_DIRECTORY);
  }

  private static childDirectory(root: string, name: string): string {
    if (!/^(?:\/|[A-Za-z]:\/)/.test(root) || root.includes('\\') ||
      root.split('/').some((part: string): boolean => part === '.' || part === '..')) {
      throw new Error('无效的应用缓存目录。');
    }
    return `${root.replace(/\/+$/, '')}/${name}`;
  }

  private static async ensureShareCacheDirectory(directory: string): Promise<void> {
    if (!(await fileIo.access(directory))) { await fileIo.mkdir(directory); }
    const stat = await fileIo.lstat(directory);
    if (!stat.isDirectory() || stat.isSymbolicLink()) { throw new Error('PCM 分享缓存目录不可用。'); }
  }

  private static isGeneratedPcmName(name: string): boolean {
    return !name.includes('/') && !name.includes('\\') && !name.includes('\0') &&
      /^.+_PCM_[0-9]{10,16}_[0-9]+\.pcm(?:\.tmp)?$/.test(name);
  }

  private static async listPcmShareCopies(context: common.Context, includeLegacy: boolean,
    errors: PcmShareCleanupInfo): Promise<PcmShareCopy[]> {
    const directories = [ExportService.shareCachePath(context)];
    if (includeLegacy) { directories.push(ExportService.childDirectory(context.filesDir, 'exports')); }
    const copies: PcmShareCopy[] = [];
    for (let index = 0; index < directories.length; index++) {
      const directory = directories[index];
      if (!(await fileIo.access(directory))) { continue; }
      const stat = await fileIo.lstat(directory);
      if (!stat.isDirectory() || stat.isSymbolicLink()) { throw new Error('PCM 分享副本目录不可用。'); }
      const names = await fileIo.listFile(directory);
      for (const name of names) {
        if (!ExportService.isGeneratedPcmName(name)) { continue; }
        const path = `${directory}/${name}`;
        try {
          const fileStat = await fileIo.lstat(path);
          // Never recurse or follow symbolic links into recordings, external files or another cache.
          if (!fileStat.isFile() || fileStat.isSymbolicLink()) { continue; }
          const suffix = name.match(/_PCM_([0-9]{10,16})_[0-9]+\.pcm(?:\.tmp)?$/);
          if (suffix === null) { continue; }
          copies.push(new PcmShareCopy(path, fileStat.size, Number(suffix[1]), index > 0, name.endsWith('.tmp')));
        } catch (error) {
          errors.failedCount += 1;
          console.error(`Check PCM share copy failed: ${String(error)}`);
        }
      }
    }
    return copies;
  }

  private static isProtected(copy: PcmShareCopy): boolean {
    return ExportService.activeShares.has(copy.path) ||
      (!copy.legacy && !copy.incomplete && Date.now() - copy.createdAt < ExportService.SHARE_GRACE_MS);
  }

  private static async cleanPcmShareCopies(context: common.Context,
    manual: boolean): Promise<PcmShareCleanupResult> {
    const errors = new PcmShareCleanupInfo();
    const copies = await ExportService.listPcmShareCopies(context, manual, errors);
    const result = new PcmShareCleanupResult();
    result.failedCount = errors.failedCount;
    for (const copy of copies) {
      if (ExportService.isProtected(copy)) {
        result.protectedFileCount += 1;
        result.protectedSizeBytes += copy.sizeBytes;
        continue;
      }
      if (!manual && !copy.incomplete && Date.now() - copy.createdAt < ExportService.SHARE_TTL_MS) { continue; }
      try {
        // A pin can be acquired while an earlier asynchronous scan is pending. Recheck immediately before unlink.
        if (ExportService.activeShares.has(copy.path)) {
          result.protectedFileCount += 1;
          result.protectedSizeBytes += copy.sizeBytes;
          continue;
        }
        await fileIo.unlink(copy.path);
        result.removedCount += 1;
        result.removedBytes += copy.sizeBytes;
      } catch (error) {
        result.failedCount += 1;
        console.error(`Clean PCM share copy failed: ${String(error)}`);
      }
    }
    return result;
  }

  private static async withCacheLock<T>(operation: () => Promise<T>): Promise<T> {
    const preceding = ExportService.cacheQueue;
    let release: () => void = (): void => {};
    ExportService.cacheQueue = new Promise<void>((resolve: () => void): void => { release = resolve; });
    await preceding;
    try { return await operation(); }
    finally { release(); }
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
