import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { RecordingConfig, RecordingInfo } from '../../../main/ets/models/RecordingTypes';
import { RecordingRepository } from '../../../main/ets/repository/RecordingRepository';
import { ExportService } from '../../../main/ets/services/ExportService';
import { WaveFileUtils } from '../../../main/ets/utils/WaveFileUtils';

let sequence: number = 0;

// File services under test only read these two context fields. Both point into a unique test-only cache subtree;
// this adapter never redirects or mutates a real application Context or its filesDir.
class CacheFixtureContext {
  readonly root: string;
  readonly filesDir: string;
  readonly cacheDir: string;

  constructor() {
    sequence += 1;
    const parent = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir;
    this.root = `${parent}/store-pcm-cache-${Date.now()}-${sequence}`;
    if (fileIo.accessSync(this.root)) { throw new Error('A cache fixture directory already exists'); }
    fileIo.mkdirSync(this.root);
    this.filesDir = `${this.root}/files`;
    this.cacheDir = `${this.root}/cache`;
    fileIo.mkdirSync(this.filesDir);
    fileIo.mkdirSync(this.cacheDir);
  }

  context(): common.Context {
    return this as Object as common.Context;
  }

  cleanup(): void {
    const parent = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir;
    if (!this.root.startsWith(`${parent}/store-pcm-cache-`) ||
      !/^store-pcm-cache-[0-9]+-[0-9]+$/.test(this.root.substring(parent.length + 1))) {
      throw new Error('Refusing to clean a directory outside this cache fixture');
    }
    this.removeOwnedDirectory(this.root);
  }

  private removeOwnedDirectory(directory: string): void {
    if (directory !== this.root && !directory.startsWith(`${this.root}/`)) {
      throw new Error('Fixture cleanup escaped its root');
    }
    const stat = fileIo.lstatSync(directory);
    if (!stat.isDirectory() || stat.isSymbolicLink()) { throw new Error('Unexpected fixture directory type'); }
    for (const name of fileIo.listFileSync(directory)) {
      if (!name || name.includes('/') || name.includes('\\') || name === '.' || name === '..') {
        throw new Error('Unexpected fixture child path');
      }
      const path = `${directory}/${name}`;
      const child = fileIo.lstatSync(path);
      if (child.isDirectory() && !child.isSymbolicLink()) { this.removeOwnedDirectory(path); }
      else { fileIo.unlinkSync(path); }
    }
    fileIo.rmdirSync(directory);
  }
}

function writeAll(fd: number, bytes: ArrayBuffer): void {
  let cursor = 0;
  while (cursor < bytes.byteLength) {
    const count = fileIo.writeSync(fd, bytes.slice(cursor));
    if (count <= 0) { throw new Error('Cache fixture write made no progress'); }
    cursor += count;
  }
}

function writeFile(path: string, bytes: ArrayBuffer): void {
  const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  try { writeAll(file.fd, bytes); fileIo.fsyncSync(file.fd); }
  finally { fileIo.closeSync(file); }
}

function readFile(path: string): ArrayBuffer {
  const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
  try {
    const size = fileIo.statSync(file.fd).size;
    const bytes = new ArrayBuffer(size);
    let cursor = 0;
    while (cursor < size) {
      const next = new ArrayBuffer(size - cursor);
      const count = fileIo.readSync(file.fd, next, { offset: cursor, length: next.byteLength });
      if (count <= 0) { throw new Error('Cache fixture read ended early'); }
      new Uint8Array(bytes).set(new Uint8Array(next, 0, count), cursor);
      cursor += count;
    }
    return bytes;
  } finally { fileIo.closeSync(file); }
}

function assertBytes(actual: ArrayBuffer, expected: ArrayBuffer): void {
  expect(actual.byteLength).assertEqual(expected.byteLength);
  const a = new Uint8Array(actual);
  const b = new Uint8Array(expected);
  let equal = a.byteLength === b.byteLength;
  for (let index = 0; equal && index < a.byteLength; index++) { equal = a[index] === b[index]; }
  expect(equal).assertTrue();
}

function waveFixture(fixture: CacheFixtureContext, depth: number = 24): RecordingInfo {
  const directory = `${fixture.filesDir}/recordings`;
  if (!fileIo.accessSync(directory)) { fileIo.mkdirSync(directory); }
  const config = RecordingConfig.wav(48000, depth);
  const samples = depth === 24 ? 22003 : 33005;
  const data = new ArrayBuffer(samples * depth / 8);
  const view = new DataView(data);
  for (let index = 0; index < data.byteLength; index++) { view.setUint8(index, (index * 37 + 11) % 256); }
  const bytes = new Uint8Array(44 + data.byteLength + WaveFileUtils.paddingBytes(data.byteLength));
  bytes.set(new Uint8Array(WaveFileUtils.createPcmHeader(config, data.byteLength)));
  bytes.set(new Uint8Array(data), 44);
  const fileName = `cache-fixture-${depth}.wav`;
  const path = `${directory}/${fileName}`;
  writeFile(path, bytes.buffer as ArrayBuffer);
  return RecordingRepository.save(fixture.context(), new RecordingInfo(fileName, path, config,
    WaveFileUtils.calculateDurationMs(data.byteLength, config), Date.now(), bytes.byteLength));
}

function generatedCopy(directory: string, prefix: string, daysAgo: number, incomplete: boolean = false): string {
  if (!fileIo.accessSync(directory)) { fileIo.mkdirSync(directory); }
  const path = `${directory}/${prefix}_PCM_${Date.now() - daysAgo * 86400000}_1.pcm${incomplete ? '.tmp' : ''}`;
  writeFile(path, new Uint8Array([17, 34, 51, 68]).buffer as ArrayBuffer);
  return path;
}

// Explicit opt-in. Real platform file I/O is exercised, with every byte inside an isolated cache fixture root.
export default function storeCacheIntegrationTest() {
  const parameters = abilityDelegatorRegistry.getArguments().parameters;
  if ((parameters['storeCache'] || parameters['-s storeCache']) !== 'true') { return; }
  describe('storePcmShareCache', () => {
    it('exports 16 and 24 bit data across copy buffers without header or RIFF padding and keeps both originals', 0,
      async () => {
        const fixture = new CacheFixtureContext();
        try {
          for (const depth of [16, 24]) {
            const recording = waveFixture(fixture, depth);
            const original = readFile(recording.filePath);
            const dataLength = new DataView(original).getUint32(40, true);
            const exported = await ExportService.exportWavAsPcm(fixture.context(), recording);
            expect(exported.filePath.startsWith(`${fixture.cacheDir}/pcm_shares/`)).assertTrue();
            expect(exported.sizeBytes).assertEqual(dataLength);
            assertBytes(readFile(exported.filePath), original.slice(44, 44 + dataLength));
            assertBytes(readFile(recording.filePath), original);
          }
          expect(fileIo.accessSync(`${fixture.filesDir}/exports`)).assertFalse();
          expect(RecordingRepository.list(fixture.context()).length).assertEqual(2);
        } finally { fixture.cleanup(); }
      });
    it('retains a complete new PCM share copy during automatic and explicit cleanup for the 24 hour grace', 0,
      async () => {
        const fixture = new CacheFixtureContext();
        try {
          const recording = waveFixture(fixture);
          const original = readFile(recording.filePath);
          const exported = await ExportService.exportWavAsPcm(fixture.context(), recording);
          const info = await ExportService.getPcmShareCleanupInfo(fixture.context());
          expect(info.fileCount).assertEqual(0);
          expect(info.protectedFileCount).assertEqual(1);
          expect(info.protectedSizeBytes).assertEqual(exported.sizeBytes);
          expect((await ExportService.prunePcmShareCache(fixture.context())).removedCount).assertEqual(0);
          const cleared = await ExportService.clearPcmShareCopies(fixture.context());
          expect(cleared.removedCount).assertEqual(0);
          expect(cleared.protectedFileCount).assertEqual(1);
          expect(cleared.failedCount).assertEqual(0);
          expect(fileIo.accessSync(exported.filePath)).assertTrue();
          assertBytes(readFile(recording.filePath), original);
        } finally { fixture.cleanup(); }
      });
    it('clears recognized legacy PCM only after an explicit call and leaves unrelated copies and recordings', 0,
      async () => {
        const fixture = new CacheFixtureContext();
        try {
          const recording = waveFixture(fixture);
          const original = readFile(recording.filePath);
          const legacy = `${fixture.filesDir}/exports`;
          const complete = generatedCopy(legacy, 'legacy', 10);
          const incomplete = generatedCopy(legacy, 'incomplete', 10, true);
          const unrelated = `${legacy}/keep.pcm`;
          writeFile(unrelated, new Uint8Array([99, 88]).buffer as ArrayBuffer);
          expect((await ExportService.prunePcmShareCache(fixture.context())).removedCount).assertEqual(0);
          expect(fileIo.accessSync(complete) && fileIo.accessSync(incomplete)).assertTrue();
          const cleared = await ExportService.clearPcmShareCopies(fixture.context());
          expect(cleared.removedCount).assertEqual(2);
          expect(cleared.removedBytes).assertEqual(8);
          expect(cleared.failedCount).assertEqual(0);
          expect(fileIo.accessSync(complete) || fileIo.accessSync(incomplete)).assertFalse();
          assertBytes(readFile(unrelated), new Uint8Array([99, 88]).buffer as ArrayBuffer);
          assertBytes(readFile(recording.filePath), original);
        } finally { fixture.cleanup(); }
      });
    it('expires old complete copies and abandoned temporary bytes while protecting an active share pin', 0,
      async () => {
        const fixture = new CacheFixtureContext();
        let release: () => void = (): void => {};
        try {
          const cache = `${fixture.cacheDir}/pcm_shares`;
          const old = generatedCopy(cache, 'expired', 8);
          const recent = generatedCopy(cache, 'recent', 2);
          const temporary = generatedCopy(cache, 'incomplete', 0, true);
          const pinned = generatedCopy(cache, 'active', 8);
          release = await ExportService.retainPcmShareCopy(fixture.context(), pinned);
          const expired = await ExportService.prunePcmShareCache(fixture.context());
          expect(expired.removedCount).assertEqual(2);
          expect(expired.removedBytes).assertEqual(8);
          expect(expired.protectedFileCount).assertEqual(1);
          expect(fileIo.accessSync(old) || fileIo.accessSync(temporary)).assertFalse();
          expect(fileIo.accessSync(recent) && fileIo.accessSync(pinned)).assertTrue();
          release();
          expect((await ExportService.prunePcmShareCache(fixture.context())).removedCount).assertEqual(1);
          expect(fileIo.accessSync(pinned)).assertFalse();
          expect((await ExportService.clearPcmShareCopies(fixture.context())).removedCount).assertEqual(1);
          expect(fileIo.listFileSync(cache).length).assertEqual(0);
        } finally { release(); fixture.cleanup(); }
      });
  });
}
