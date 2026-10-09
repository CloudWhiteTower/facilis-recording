#!/usr/bin/env node
// Real repository code against temporary host files, with a narrow fileIo adapter and injected failures.
// This checks transaction semantics, not HarmonyOS filesystem durability or ArkUI rendering.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const ts = require(path.resolve(process.argv[2] || process.env.FACILIS_TYPESCRIPT || ''));
const root = path.resolve(__dirname, '..');
const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'facilis-repository-tests-'));
const descriptors = new Map();
let fault = () => false;
let maxWrite = Infinity;
let maxRead = Infinity;
let asyncEof = false;
let pickerAnswer = () => [];
let shareShow = async () => {};
let shareControllers = [];
let passed = 0;
let failed = 0;
let scans = 0;
function before(operation, source, target = '') {
  if (fault(operation, source.replaceAll('\\', '/'), target.replaceAll('\\', '/'))) {
    throw new Error('Injected ' + operation + ' failure');
  }
}
const fileIo = {
  OpenMode: { READ_ONLY: fs.constants.O_RDONLY, READ_WRITE: fs.constants.O_RDWR,
    CREATE: fs.constants.O_CREAT, TRUNC: fs.constants.O_TRUNC },
  accessSync: p => { before('access', p); return fs.existsSync(p); },
  statSync: p => { before('stat', p); return fs.statSync(p); },
  mkdirSync: (p, recursive) => { before('mkdir', p); return fs.mkdirSync(p, { recursive }); },
  listFileSync: p => { before('list', p); scans++; return fs.readdirSync(p); },
  readTextSync: p => { before('readText', p); return fs.readFileSync(p, 'utf8'); },
  openSync: (p, flags) => {
    before('open', p);
    const fd = fs.openSync(p, flags);
    descriptors.set(fd, p);
    return { fd };
  },
  writeSync: (fd, bytes, options = {}) => {
    before('write', descriptors.get(fd));
    const buffer = typeof bytes === 'string' ? Buffer.from(bytes) : Buffer.from(bytes);
    return fs.writeSync(fd, buffer, 0, Math.min(buffer.byteLength, options.length ?? Infinity, maxWrite), options.offset ?? null);
  },
  readSync: (fd, bytes, options = {}) => {
    before('read', descriptors.get(fd));
    return fs.readSync(fd, Buffer.from(bytes), 0, Math.min(bytes.byteLength, options.length ?? Infinity, maxRead), options.offset ?? null);
  },
  fsyncSync: fd => { before('fsync', descriptors.get(fd)); fs.fsyncSync(fd); },
  closeSync: file => {
    const fd = typeof file === 'number' ? file : file.fd;
    fs.closeSync(fd); descriptors.delete(fd);
  },
  renameSync: (a, b) => { before('rename', a, b); fs.renameSync(a, b); },
  unlinkSync: p => { before('unlink', p); fs.unlinkSync(p); },
  async access(p) { return fileIo.accessSync(p); },
  async stat(p) { return fileIo.statSync(p); },
  async lstat(p) { before('lstat', p); return fs.lstatSync(p); },
  async mkdir(p) { before('mkdir', p); return fs.mkdirSync(p); },
  async listFile(p) { return fileIo.listFileSync(p); },
  async open(p, flags) { return fileIo.openSync(p, flags); },
  async read(fd, bytes, options) { return asyncEof ? 0 : fileIo.readSync(fd, bytes, options); },
  async write(fd, bytes, options) { return fileIo.writeSync(fd, bytes, options); },
  async close(file) { fileIo.closeSync(file); },
  async fsync(fd) { fileIo.fsyncSync(fd); },
  async rename(a, b) { fileIo.renameSync(a, b); },
  async unlink(p) { fileIo.unlinkSync(p); }
};
const cache = new Map();
function load(filename) {
  const file = path.resolve(filename);
  assert.ok(file.startsWith(root + path.sep));
  if (cache.has(file)) return cache.get(file).exports;
  const module = { exports: {} };
  cache.set(file, module);
  const source = fs.readFileSync(file, 'utf8');
  const output = ts.transpileModule(source,
    { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  const requireLocal = name => {
    if (name === '@kit.CoreFileKit') return { fileIo, fileUri: { getUriFromPath: p => 'file://' + p },
      picker: { DocumentSaveOptions: class {}, DocumentViewPicker: class { async save(options) { return pickerAnswer(options); } } } };
    // Match API24 device behavior: encodeInto('') may return undefined rather than an empty array.
    if (name === '@kit.ArkTS') return { util: { TextEncoder: class { encodeInto(text) { return text.length ? new TextEncoder().encode(text) : undefined; } } } };
    if (name === '@kit.AbilityKit') return {};
    if (name === '@kit.ArkData') return { uniformTypeDescriptor: { UniformDataType: { AUDIO: 'audio' } } };
    if (name === '@kit.ShareKit') return { systemShare: {
      SharedData: class { constructor(record) { this.record = record; } },
      ShareController: class {
        constructor(data) { this.data = data; this.callbacks = new Map(); shareControllers.push(this); }
        on(name, callback) { this.callbacks.set(name, callback); }
        off(name, callback) { if (this.callbacks.get(name) === callback) this.callbacks.delete(name); }
        async show(context, options) { return shareShow(this, context, options); }
        dismiss() { this.callbacks.get('dismiss')?.(); }
      }, SharePreviewMode: { DETAIL: 'detail' }, SelectionMode: { SINGLE: 'single' }
    } };
    if (name.startsWith('.')) return load(path.resolve(path.dirname(file), name + '.ets'));
    throw new Error('Unexpected test import: ' + name);
  };
  new Function('require', 'exports', 'module', 'canIUse', output)(requireLocal, module.exports, module, () => true);
  return module.exports;
}
const base = path.join(root, 'HarmonyRecorder/entry/src/main/ets');
const { RecordingRepository: repository, RecordingBatchAction: action } = load(path.join(base, 'repository/RecordingRepository.ets'));
const { RecordingConfig, RecordingInfo } = load(path.join(base, 'models/RecordingTypes.ets'));
const { WaveFileUtils } = load(path.join(base, 'utils/WaveFileUtils.ets'));
const { ExportService } = load(path.join(base, 'services/ExportService.ets'));
const { ShareService } = load(path.join(base, 'services/ShareService.ets'));
const { AudioFileUtils } = load(path.join(base, 'utils/AudioFileUtils.ets'));
function context() {
  const filesDir = fs.mkdtempSync(path.join(temporaryRoot, 'case-')).replaceAll('\\', '/');
  const cacheDir = filesDir + '/cache';
  fs.mkdirSync(cacheDir);
  return { filesDir, cacheDir };
}
function create(context, name = '测试课堂.wav', duration = 1000) {
  const directory = path.join(context.filesDir, 'recordings');
  fs.mkdirSync(directory, { recursive: true });
  const config = RecordingConfig.wav(44100, 24);
  const bytes = 132300 * duration / 1000;
  const target = path.join(directory, name).replaceAll('\\', '/');
  fs.writeFileSync(target, Buffer.concat([Buffer.from(WaveFileUtils.createPcmHeader(config, bytes)), Buffer.alloc(bytes)]));
  const recording = new RecordingInfo(name, target, config, duration, 1000, bytes + 44);
  repository.save(context, recording);
  return recording;
}
function atom(type, payload) {
  const header = Buffer.alloc(8); header.writeUInt32BE(payload.length + 8); header.write(type, 4, 'ascii');
  return Buffer.concat([header, payload]);
}
function m4aFixture() {
  const mdhd = Buffer.alloc(24); mdhd.writeUInt32BE(44100, 12); mdhd.writeUInt32BE(88200, 16);
  const hdlr = Buffer.alloc(12); hdlr.write('soun', 8);
  const mp4a = Buffer.alloc(28); mp4a.writeUInt16BE(1, 6); mp4a.writeUInt16BE(2, 16);
  mp4a.writeUInt16BE(16, 18); mp4a.writeUInt32BE(48000 * 65536, 24);
  const decoder = Buffer.alloc(13); decoder[0] = 0x40; decoder[1] = 0x15;
  decoder.writeUInt32BE(128000, 5); decoder.writeUInt32BE(96000, 9);
  const specific = Buffer.from([5, 2, 0x12, 0x08]); // AAC-LC, 44.1 kHz, mono.
  const decoderDescriptor = Buffer.concat([Buffer.from([4, decoder.length + specific.length]), decoder, specific]);
  const elementary = Buffer.concat([Buffer.from([3, decoderDescriptor.length + 3, 0, 1, 0]), decoderDescriptor]);
  const entry = atom('mp4a', Buffer.concat([mp4a, atom('esds', Buffer.concat([Buffer.alloc(4), elementary]))]));
  const stsdHeader = Buffer.alloc(8); stsdHeader.writeUInt32BE(1, 4);
  const stbl = atom('stbl', atom('stsd', Buffer.concat([stsdHeader, entry])));
  const mdia = atom('mdia', Buffer.concat([atom('mdhd', mdhd), atom('hdlr', hdlr), atom('minf', stbl)]));
  return Buffer.concat([atom('ftyp', Buffer.from('M4A \0\0\0\0isom', 'binary')),
    atom('mdat', Buffer.from([1, 2, 3, 4])), atom('moov', atom('trak', mdia))]);
}
function chunkedWave() {
  const fmt = Buffer.from(WaveFileUtils.createPcmHeader(RecordingConfig.wav(44100, 24), 3)).subarray(12, 36);
  const junk = Buffer.from('JUNK\x02\0\0\0ab', 'binary');
  const data = Buffer.from('data\x03\0\0\0\x11\x22\x33\0', 'binary');
  const tail = Buffer.from('LIST\x02\0\0\0xy', 'binary');
  const body = Buffer.concat([Buffer.from('WAVE'), junk, fmt, data, tail]);
  const header = Buffer.alloc(8); header.write('RIFF'); header.writeUInt32LE(body.length, 4);
  return Buffer.concat([header, body]);
}
function failOnce(predicate) {
  let armed = true;
  fault = (...args) => { if (armed && predicate(...args)) { armed = false; return true; } return false; };
}
function test(name, body) {
  fault = () => false;
  maxWrite = Infinity;
  maxRead = Infinity;
  asyncEof = false;
  try { body(); passed++; console.log('PASS ' + name); }
  catch (error) { failed++; console.error('FAIL ' + name + ': ' + error.stack); }
  finally { fault = () => false; }
}
async function asyncTest(name, body) {
  fault = () => false; maxWrite = Infinity; maxRead = Infinity; asyncEof = false; pickerAnswer = () => [];
  shareShow = async () => {}; shareControllers = [];
  try { await body(); passed++; console.log('PASS ' + name); }
  catch (error) { failed++; console.error('FAIL ' + name + ': ' + error.stack); }
  finally { fault = () => false; }
}
(async () => {
try {
  test('move, reopen, restore and permanently delete preserve metadata and remove actual bytes', () => {
    const ctx = context();
    const original = create(ctx);
    const moved = repository.moveToRecentlyDeleted(ctx, original);
    assert.equal(fs.existsSync(original.filePath), false);
    assert.equal(repository.list(ctx).length, 0);
    assert.equal(repository.listRecentlyDeleted(ctx)[0].config.bitDepth, 24);
    assert.equal(repository.listRecentlyDeleted(ctx)[0].durationMs, 1000);
    const restored = repository.restore(ctx, moved);
    assert.equal(restored.fileName, original.fileName);
    assert.equal(repository.listRecentlyDeleted(ctx).length, 0);
    const trashed = repository.moveToRecentlyDeleted(ctx, restored);
    repository.permanentlyDelete(ctx, trashed);
    repository.permanentlyDelete(ctx, trashed);
    assert.equal(fs.existsSync(trashed.filePath), false);
    assert.equal(repository.listRecentlyDeleted(ctx).length, 0);
  });
  test('failed second index commit rolls audio and both indexes back', () => {
    const ctx = context();
    const original = create(ctx);
    failOnce((op, a, b) => op === 'rename' && b.endsWith('/recently_deleted.index'));
    assert.throws(() => repository.moveToRecentlyDeleted(ctx, original));
    assert.equal(fs.existsSync(original.filePath), true);
    assert.equal(repository.list(ctx)[0].durationMs, original.durationMs);
    assert.equal(repository.listRecentlyDeleted(ctx).length, 0);
  });
  test('failed restore commit rolls back to recently deleted', () => {
    const ctx = context();
    const moved = repository.moveToRecentlyDeleted(ctx, create(ctx));
    failOnce((op, a, b) => op === 'rename' && b.endsWith('/recently_deleted.index'));
    assert.throws(() => repository.restore(ctx, moved));
    assert.equal(fs.existsSync(moved.filePath), true);
    assert.equal(repository.list(ctx).length, 0);
    assert.equal(repository.listRecentlyDeleted(ctx)[0].originalFileName, moved.originalFileName);
  });
  test('unlink failure keeps bytes and restores the trash index', () => {
    const ctx = context();
    const moved = repository.moveToRecentlyDeleted(ctx, create(ctx));
    failOnce((op, p) => op === 'unlink' && p === moved.filePath);
    assert.throws(() => repository.permanentlyDelete(ctx, moved));
    assert.equal(fs.existsSync(moved.filePath), true);
    assert.equal(repository.listRecentlyDeleted(ctx)[0].id, moved.id);
  });
  test('permanent deletion does not unlink when metadata preparation fails', () => {
    const ctx = context();
    const moved = repository.moveToRecentlyDeleted(ctx, create(ctx));
    // An empty index has no payload write; inject atomic replacement instead.
    failOnce((op, a, b) => op === 'rename' && b.endsWith('/recently_deleted.index'));
    assert.throws(() => repository.permanentlyDelete(ctx, moved));
    assert.equal(fs.existsSync(moved.filePath), true);
    assert.equal(repository.listRecentlyDeleted(ctx).length, 1);
  });
  test('interrupted rollback journal recovers on the next repository read', () => {
    const ctx = context();
    const original = create(ctx);
    fault = (op, a, b) => op === 'rename' &&
      (b.endsWith('/recently_deleted.index') || (a.includes('/recently_deleted/') && b === original.filePath));
    assert.throws(() => repository.moveToRecentlyDeleted(ctx, original));
    assert.equal(fs.existsSync(path.join(ctx.filesDir, 'recordings/recordings.transaction')), true);
    fault = () => false;
    assert.equal(repository.list(ctx)[0].filePath, original.filePath);
    assert.equal(repository.listRecentlyDeleted(ctx).length, 0);
  });
  test('committed transfer survives journal cleanup failure', () => {
    const ctx = context();
    const original = create(ctx);
    fault = (op, p) => op === 'unlink' && p.endsWith('/recordings.transaction');
    const moved = repository.moveToRecentlyDeleted(ctx, original);
    fault = () => false;
    assert.equal(repository.list(ctx).length, 0);
    assert.equal(repository.listRecentlyDeleted(ctx)[0].filePath, moved.filePath);
  });
  test('successful irreversible delete survives journal cleanup failure', () => {
    const ctx = context();
    const moved = repository.moveToRecentlyDeleted(ctx, create(ctx));
    fault = (op, p) => op === 'unlink' && p.endsWith('/recordings.transaction');
    repository.permanentlyDelete(ctx, moved);
    fault = () => false;
    assert.equal(repository.listRecentlyDeleted(ctx).length, 0);
    assert.equal(fs.existsSync(moved.filePath), false);
  });
  test('partial batch continues after a failure and reports exact ids', () => {
    const ctx = context();
    const first = create(ctx, 'first.wav');
    const second = create(ctx, 'second.wav');
    fault = (op, p) => op === 'rename' && p === first.filePath;
    const result = repository.applyBatch(ctx, [first, second, second], action.MOVE_TO_TRASH);
    assert.deepEqual(result.completedIds, ['second.wav']);
    assert.deepEqual(result.failedIds, ['first.wav']);
    fault = () => false;
    assert.equal(repository.list(ctx)[0].id, 'first.wav');
    assert.equal(repository.listRecentlyDeleted(ctx)[0].id, 'second.wav');
  });
  test('a successful large batch scans each library directory only once', () => {
    const ctx = context(), items = [];
    for (let index = 0; index < 40; index++) items.push(create(ctx, `item-${index}.wav`));
    const beforeScans = scans;
    const result = repository.applyBatch(ctx, items, action.MOVE_TO_TRASH);
    assert.equal(result.completedIds.length, 40); assert.equal(result.failedIds.length, 0);
    assert.equal(scans - beforeScans, 2);
    assert.equal(repository.list(ctx).length, 0); assert.equal(repository.listRecentlyDeleted(ctx).length, 40);
  });
  test('batch restore retains only failed trash entries and supports retry', () => {
    const ctx = context();
    const first = repository.moveToRecentlyDeleted(ctx, create(ctx, 'first.wav'));
    const second = repository.moveToRecentlyDeleted(ctx, create(ctx, 'second.wav'));
    fault = (op, p) => op === 'rename' && p === first.filePath;
    const result = repository.applyBatch(ctx, [first, second], action.RESTORE);
    assert.deepEqual(result.completedIds, [second.id]);
    assert.deepEqual(result.failedIds, [first.id]);
    fault = () => false;
    assert.deepEqual(repository.listRecentlyDeleted(ctx).map(x => x.id), [first.id]);
    assert.equal(repository.list(ctx).length, 1);
    assert.deepEqual(repository.applyBatch(ctx, [first], action.RESTORE).completedIds, [first.id]);
    assert.equal(repository.list(ctx).length, 2);
    assert.equal(repository.listRecentlyDeleted(ctx).length, 0);
  });
  test('batch permanent deletion preserves failed bytes and removes successful bytes', () => {
    const ctx = context();
    const first = repository.moveToRecentlyDeleted(ctx, create(ctx, 'first.wav'));
    const second = repository.moveToRecentlyDeleted(ctx, create(ctx, 'second.wav'));
    fault = (op, p) => op === 'unlink' && p === first.filePath;
    const result = repository.applyBatch(ctx, [first, second, second], action.PERMANENTLY_DELETE);
    assert.deepEqual(result.completedIds, [second.id]);
    assert.deepEqual(result.failedIds, [first.id]);
    assert.equal(fs.existsSync(first.filePath), true);
    assert.equal(fs.existsSync(second.filePath), false);
    fault = () => false;
    assert.deepEqual(repository.listRecentlyDeleted(ctx).map(x => x.id), [first.id]);
    assert.deepEqual(repository.applyBatch(ctx, [first], action.PERMANENTLY_DELETE).completedIds, [first.id]);
    assert.equal(fs.existsSync(first.filePath), false);
    assert.equal(repository.listRecentlyDeleted(ctx).length, 0);
  });
  test('permanent deletion never reports success for an existing file missing from the index and scan', () => {
    const ctx = context();
    const moved = repository.moveToRecentlyDeleted(ctx, create(ctx));
    fs.unlinkSync(path.join(ctx.filesDir, 'recordings/recently_deleted/recently_deleted.index'));
    fs.writeFileSync(moved.filePath, Buffer.from('broken audio header'));
    const result = repository.applyBatch(ctx, [moved], action.PERMANENTLY_DELETE);
    assert.deepEqual(result.completedIds, []);
    assert.deepEqual(result.failedIds, [moved.id]);
    assert.equal(fs.existsSync(moved.filePath), true);
  });
  test('atomic UTF-8 writes handle partial writes and leave previous index on failure', () => {
    const ctx = context();
    maxWrite = 7;
    const original = create(ctx);
    const index = path.join(ctx.filesDir, 'recordings/recordings.index');
    const beforeText = fs.readFileSync(index, 'utf8');
    failOnce((op, p) => op === 'fsync' && p.endsWith('/recordings.index.tmp'));
    assert.throws(() => repository.save(ctx, original));
    assert.equal(fs.readFileSync(index, 'utf8'), beforeText);
    assert.equal(repository.list(ctx)[0].fileName, '测试课堂.wav');
  });
  test('directory read errors propagate and list does not rewrite metadata', () => {
    const ctx = context();
    create(ctx);
    fault = op => op === 'write';
    assert.equal(repository.list(ctx).length, 1);
    fault = op => op === 'list';
    assert.throws(() => repository.list(ctx));
  });
  test('renaming and restoring resolve name conflicts without overwriting another file', () => {
    const ctx = context();
    const original = create(ctx, 'same.wav');
    const moved = repository.moveToRecentlyDeleted(ctx, original);
    const replacement = create(ctx, 'same.wav', 2000);
    const restored = repository.restore(ctx, moved);
    assert.equal(restored.fileName, 'same_1.wav');
    assert.equal(repository.list(ctx).find(x => x.id === replacement.id).durationMs, 2000);
  });
  test('same-millisecond names remain unique before either recorder opens its file', () => {
    const ctx = context(), now = Date.now;
    Date.now = () => 1800000000000;
    try {
      const first = repository.createNewRecording(ctx, RecordingConfig.wav());
      const second = repository.createNewRecording(ctx, RecordingConfig.wav());
      assert.notEqual(first.fileName, second.fileName);
      repository.discardTemporary(first); repository.discardTemporary(second);
    } finally { Date.now = now; }
  });
  test('renaming to the current name preserves id, path and bytes', () => {
    const ctx = context(), original = create(ctx);
    const beforeBytes = fs.readFileSync(original.filePath);
    const result = repository.rename(ctx, original, original.fileName);
    assert.equal(result.fileName, original.fileName);
    assert.deepEqual(fs.readFileSync(result.filePath), beforeBytes);
    assert.equal(repository.list(ctx).length, 1);
  });
  test('indexed WAV metadata follows real bytes instead of stale duration and quality', () => {
    const ctx = context(), original = create(ctx);
    const index = path.join(ctx.filesDir, 'recordings/recordings.index');
    const fields = fs.readFileSync(index, 'utf8').split('|');
    fields[2] = '48000'; fields[3] = '16'; fields[6] = '99999';
    fs.writeFileSync(index, fields.join('|'));
    const found = repository.list(ctx)[0];
    assert.equal(found.config.sampleRate, 44100); assert.equal(found.config.bitDepth, 24);
    assert.equal(found.durationMs, 1000);
    assert.equal(repository.inspectRecording(ctx, original).durationMs, 1000);
  });
  test('sandbox migration rebuilds paths from relative index filenames', () => {
    const first = context(), original = create(first), migrated = context();
    fs.cpSync(path.join(first.filesDir, 'recordings'), path.join(migrated.filesDir, 'recordings'), { recursive: true });
    const found = repository.list(migrated)[0];
    assert.equal(found.fileName, original.fileName);
    assert.equal(found.filePath, migrated.filesDir + '/recordings/' + original.fileName);
  });
  test('save rejects a forged external path without modifying its bytes', () => {
    const ctx = context(), original = create(ctx);
    const external = path.join(ctx.cacheDir, 'external.wav').replaceAll('\\', '/');
    fs.copyFileSync(original.filePath, external);
    const forged = new RecordingInfo(original.fileName, external, original.config, 1000, original.createdAt);
    assert.throws(() => repository.save(ctx, forged));
    assert.equal(fs.existsSync(external), true);
  });
  test('discardTemporary never unlinks an already saved recording', () => {
    const ctx = context(), original = create(ctx);
    assert.throws(() => repository.discardTemporary(original));
    assert.equal(fs.existsSync(original.filePath), true);
  });
  test('releasing a failed recording reservation makes preserved incomplete bytes visible', () => {
    const ctx = context(), recording = repository.createNewRecording(ctx, RecordingConfig.wav());
    fs.writeFileSync(recording.filePath, Buffer.from('unfinished'));
    assert.equal(repository.list(ctx).length, 0);
    repository.releaseTemporaryReservation(recording);
    assert.equal(repository.list(ctx)[0].id, recording.id);
    assert.equal(repository.getUnreadableCount(ctx), 1);
  });
  test('legacy trash index without deletedAt remains restorable using its actual directory', () => {
    const ctx = context(), moved = repository.moveToRecentlyDeleted(ctx, create(ctx));
    const index = ctx.filesDir + '/recordings/recently_deleted/recently_deleted.index';
    fs.writeFileSync(index, fs.readFileSync(index, 'utf8').split('|').slice(0, 8).join('|'));
    const found = repository.listRecentlyDeleted(ctx)[0];
    assert.equal(found.isInRecentlyDeleted, true);
    const restored = repository.restore(ctx, found);
    assert.equal(fs.existsSync(restored.filePath), true);
  });
  test('damaged indexed files stay visible and bytes are preserved, while open fails clearly', () => {
    const ctx = context(), original = create(ctx);
    fs.writeFileSync(original.filePath, Buffer.from('damaged'));
    assert.equal(repository.list(ctx).length, 1);
    assert.equal(repository.getUnreadableCount(ctx), 1);
    assert.throws(() => repository.inspectRecording(ctx, original), /损坏/);
    assert.equal(fs.readFileSync(original.filePath, 'utf8'), 'damaged');
  });
  test('unfinished unindexed M4A stays visible with unknown parameters and supports explicit cleanup', () => {
    const ctx = context(); create(ctx);
    fs.writeFileSync(path.join(ctx.filesDir, 'recordings/broken.m4a'), atom('ftyp', Buffer.alloc(8)));
    const list = repository.list(ctx);
    assert.equal(list.length, 2);
    assert.equal(repository.getUnreadableCount(ctx), 1);
    const broken = list.find(x => x.fileName === 'broken.m4a');
    assert.equal(broken.config.sampleRate, 0); assert.equal(broken.config.encodingDetailLabel, '文件待检查');
    assert.throws(() => repository.inspectRecording(ctx, broken));
    const moved = repository.moveToRecentlyDeleted(ctx, broken);
    repository.permanentlyDelete(ctx, moved);
    assert.equal(fs.existsSync(moved.filePath), false);
  });
  test('M4A duration and AAC config come from mdhd and esds rather than placeholder sample entry fields', () => {
    const ctx = context(); create(ctx);
    const target = path.join(ctx.filesDir, 'recordings/actual.m4a'); fs.writeFileSync(target, m4aFixture());
    const found = repository.list(ctx).find(x => x.fileName === 'actual.m4a');
    assert.ok(found); assert.equal(found.durationMs, 2000); assert.equal(found.config.sampleRate, 44100);
    assert.equal(found.config.channels, 1); assert.equal(found.config.bitrate, 96000);
  });
  test('WAV chunk scan handles metadata, odd payload padding and trailing chunks', () => {
    const ctx = context(), target = ctx.cacheDir + '/chunked.wav'; fs.writeFileSync(target, chunkedWave());
    const metadata = AudioFileUtils.read(target, 'wav'); assert.ok(metadata);
    assert.equal(metadata.dataOffset, 54); assert.equal(metadata.dataLength, 3);
    assert.equal(metadata.config.bitDepth, 24);
    const truncated = chunkedWave().subarray(0, 57); fs.writeFileSync(target, truncated);
    assert.equal(AudioFileUtils.read(target, 'wav'), undefined);
  });
  test('registration reads completed cache output and rolls back to cache when index commit fails', () => {
    const ctx = context(), original = create(ctx), cached = ctx.cacheDir + '/converted.tmp';
    fs.copyFileSync(original.filePath, cached);
    failOnce((op, p) => op === 'fsync' && p.endsWith('/recordings.index.tmp'));
    assert.throws(() => repository.importCompletedFile(ctx, cached, RecordingConfig.wav(), 'converted'));
    assert.equal(fs.existsSync(cached), true);
    assert.equal(fs.existsSync(ctx.filesDir + '/recordings/converted.wav'), false);
    const imported = repository.importCompletedFile(ctx, cached, RecordingConfig.wav(), 'converted');
    assert.equal(imported.config.sampleRate, 44100); assert.equal(imported.config.bitDepth, 24);
    assert.equal(fs.existsSync(cached), false); assert.equal(repository.list(ctx).length, 2);
  });
  await asyncTest('yielding a batch does not overwrite a recording saved between its transactions', async () => {
    const ctx = context(), first = create(ctx, 'first.wav'), second = create(ctx, 'second.wav');
    const yieldOriginal = repository.yieldToUI;
    let yields = 0, added;
    repository.yieldToUI = async () => {
      if (++yields === 2) added = create(ctx, 'added-during-batch.wav');
    };
    try {
      const result = await repository.applyBatchAsync(ctx, [first, second], action.MOVE_TO_TRASH);
      assert.deepEqual(result.completedIds, [first.id, second.id]);
      assert.deepEqual(repository.list(ctx).map(item => item.id), [added.id]);
      assert.equal(repository.listRecentlyDeleted(ctx).length, 2); assert.equal(yields, 3);
    } finally { repository.yieldToUI = yieldOriginal; }
  });
  await asyncTest('a failed refresh during an asynchronous batch retains its exact committed successes', async () => {
    const ctx = context(), first = create(ctx, 'first.wav'), second = create(ctx, 'second.wav'), third = create(ctx, 'third.wav');
    const yieldOriginal = repository.yieldToUI;
    let yields = 0;
    repository.yieldToUI = async () => {
      if (++yields === 2) fault = (op, p) => (op === 'rename' && p === second.filePath) || op === 'list';
    };
    try {
      const result = await repository.applyBatchAsync(ctx, [first, second, third], action.MOVE_TO_TRASH);
      assert.deepEqual(result.completedIds, [first.id]);
      assert.deepEqual(result.failedIds, [second.id, third.id]);
      fault = () => false;
      assert.equal(repository.list(ctx).length, 2); assert.equal(repository.listRecentlyDeleted(ctx).length, 1);
    } finally { repository.yieldToUI = yieldOriginal; fault = () => false; }
  });
  await asyncTest('PCM export copies only data chunk bytes and excludes pad and LIST metadata', async () => {
    const ctx = context(); create(ctx);
    const target = ctx.filesDir + '/recordings/chunked.wav'; fs.writeFileSync(target, chunkedWave());
    const recording = repository.list(ctx).find(x => x.fileName === 'chunked.wav');
    const result = await ExportService.exportWavAsPcm(ctx, recording);
    assert.equal(result.sizeBytes, 3); assert.deepEqual(fs.readFileSync(result.filePath), Buffer.from([0x11, 0x22, 0x33]));
  });
  await asyncTest('asynchronous PCM export completes partial reads and writes without corruption', async () => {
    const ctx = context(), original = create(ctx); maxRead = 113; maxWrite = 17;
    const result = await ExportService.exportWavAsPcm(ctx, original);
    assert.deepEqual(fs.readFileSync(result.filePath), fs.readFileSync(original.filePath).subarray(44));
  });
  await asyncTest('premature EOF and write failure remove incomplete PCM output and preserve source', async () => {
    const ctx = context(), original = create(ctx), beforeBytes = fs.readFileSync(original.filePath);
    asyncEof = true;
    await assert.rejects(ExportService.exportWavAsPcm(ctx, original), /提前结束/);
    assert.equal(fs.readdirSync(ctx.cacheDir + '/pcm_shares').length, 0);
    asyncEof = false;
    fault = (op, p) => op === 'write' && p.endsWith('.pcm.tmp');
    await assert.rejects(ExportService.exportWavAsPcm(ctx, original));
    assert.equal(fs.readdirSync(ctx.cacheDir + '/pcm_shares').length, 0);
    assert.deepEqual(fs.readFileSync(original.filePath), beforeBytes);
  });
  await asyncTest('repeated PCM exports use unique cache copies and never create permanent legacy exports', async () => {
    const ctx = context(), original = create(ctx), beforeBytes = fs.readFileSync(original.filePath);
    const now = Date.now; Date.now = () => 1800000000000;
    try {
      const [first, second] = await Promise.all([
        ExportService.exportWavAsPcm(ctx, original), ExportService.exportWavAsPcm(ctx, original)
      ]);
      assert.notEqual(first.filePath, second.filePath);
      assert.ok(first.filePath.startsWith(ctx.cacheDir + '/pcm_shares/'));
      assert.equal(fs.existsSync(ctx.filesDir + '/exports'), false);
      assert.deepEqual(fs.readFileSync(first.filePath), beforeBytes.subarray(44));
      const info = await ExportService.getPcmShareCleanupInfo(ctx);
      assert.equal(info.fileCount, 0); assert.equal(info.protectedFileCount, 2);
      assert.equal(info.protectedSizeBytes, original.sizeBytes * 2 - 88);
    } finally { Date.now = now; }
  });
  await asyncTest('share presentation and cancellation retain the copy through the receiver grace', async () => {
    const ctx = context(), original = create(ctx), exported = await ExportService.exportWavAsPcm(ctx, original);
    await ShareService.shareAudioFile(ctx, exported.filePath, exported.fileName, 'anchor');
    assert.equal(fs.existsSync(exported.filePath), true);
    shareControllers[0].dismiss();
    assert.equal(shareControllers[0].callbacks.size, 0);
    const result = await ExportService.clearPcmShareCopies(ctx);
    assert.equal(result.removedCount, 0); assert.equal(result.protectedFileCount, 1);
    assert.equal(fs.existsSync(exported.filePath), true);
  });
  await asyncTest('an unfinished share remains protected beyond expiry until its panel closes', async () => {
    const ctx = context(), original = create(ctx), exported = await ExportService.exportWavAsPcm(ctx, original);
    await ShareService.shareAudioFile(ctx, exported.filePath, exported.fileName, 'anchor');
    const now = Date.now, future = now() + 8 * 86400000; Date.now = () => future;
    try {
      assert.equal((await ExportService.prunePcmShareCache(ctx)).protectedFileCount, 1);
      assert.equal((await ExportService.clearPcmShareCopies(ctx)).removedCount, 0);
      shareControllers[0].dismiss();
      assert.equal((await ExportService.prunePcmShareCache(ctx)).removedCount, 1);
      assert.equal(fs.existsSync(exported.filePath), false);
      assert.equal(fs.existsSync(original.filePath), true);
    } finally { Date.now = now; }
  });
  await asyncTest('failed share presentation releases its pin while preserving the receiver grace', async () => {
    const ctx = context(), original = create(ctx), exported = await ExportService.exportWavAsPcm(ctx, original);
    shareShow = async () => { throw new Error('panel unavailable'); };
    await assert.rejects(ShareService.shareAudioFile(ctx, exported.filePath, exported.fileName, 'anchor'), /panel unavailable/);
    assert.equal(shareControllers[0].callbacks.size, 0);
    assert.equal((await ExportService.clearPcmShareCopies(ctx)).protectedFileCount, 1);
    const now = Date.now, future = now() + 2 * 86400000; Date.now = () => future;
    try { assert.equal((await ExportService.clearPcmShareCopies(ctx)).removedCount, 1); }
    finally { Date.now = now; }
  });
  await asyncTest('two panels referencing one PCM copy need both dismissals before its pin releases', async () => {
    const ctx = context(), original = create(ctx), exported = await ExportService.exportWavAsPcm(ctx, original);
    await ShareService.shareAudioFile(ctx, exported.filePath, exported.fileName, 'one');
    await ShareService.shareAudioFile(ctx, exported.filePath, exported.fileName, 'two');
    const now = Date.now, future = now() + 8 * 86400000; Date.now = () => future;
    try {
      shareControllers[0].dismiss(); shareControllers[0].dismiss();
      assert.equal((await ExportService.clearPcmShareCopies(ctx)).protectedFileCount, 1);
      shareControllers[1].dismiss();
      assert.equal((await ExportService.clearPcmShareCopies(ctx)).removedCount, 1);
    } finally { Date.now = now; }
  });
  await asyncTest('automatic expiry removes old cache copies and abandoned temporaries but never legacy exports', async () => {
    const ctx = context(), original = create(ctx), exported = await ExportService.exportWavAsPcm(ctx, original);
    const legacy = ctx.filesDir + '/exports'; fs.mkdirSync(legacy);
    const legacyFile = legacy + '/old_PCM_1700000000000_1.pcm'; fs.writeFileSync(legacyFile, 'legacy');
    const recentTemporary = ctx.cacheDir + `/pcm_shares/failure_PCM_${Date.now()}_999.pcm.tmp`;
    fs.writeFileSync(recentTemporary, 'incomplete');
    assert.equal((await ExportService.prunePcmShareCache(ctx)).removedCount, 1);
    assert.equal(fs.existsSync(exported.filePath), true); assert.equal(fs.existsSync(recentTemporary), false);
    const now = Date.now, future = now() + 8 * 86400000; Date.now = () => future;
    try {
      const result = await ExportService.prunePcmShareCache(ctx);
      assert.equal(result.removedCount, 1); assert.equal(fs.existsSync(legacyFile), true);
      assert.deepEqual(fs.readFileSync(original.filePath).subarray(44), Buffer.alloc(132300));
    } finally { Date.now = now; }
  });
  await asyncTest('a failed export whose temporary unlink also fails is recoverable by the next safe cleanup', async () => {
    const ctx = context(), original = create(ctx), beforeBytes = fs.readFileSync(original.filePath);
    fault = (op, p) => (op === 'write' || op === 'unlink') && p.endsWith('.pcm.tmp');
    await assert.rejects(ExportService.exportWavAsPcm(ctx, original), /导出 PCM 失败/);
    assert.equal(fs.readdirSync(ctx.cacheDir + '/pcm_shares').length, 1);
    fault = () => false;
    assert.equal((await ExportService.prunePcmShareCache(ctx)).removedCount, 1);
    const exported = await ExportService.exportWavAsPcm(ctx, original);
    assert.deepEqual(fs.readFileSync(exported.filePath), beforeBytes.subarray(44));
    assert.deepEqual(fs.readFileSync(original.filePath), beforeBytes);
  });
  await asyncTest('manual cleanup counts only generated legacy PCM copies and leaves unrelated files and directories', async () => {
    const ctx = context(), original = create(ctx), legacy = ctx.filesDir + '/exports'; fs.mkdirSync(legacy);
    const pcm = legacy + '/课堂_PCM_1800000000000_1.pcm'; fs.writeFileSync(pcm, 'abc');
    const incomplete = pcm + '.tmp'; fs.writeFileSync(incomplete, 'xy');
    const other = legacy + '/keep.pcm'; fs.writeFileSync(other, 'user file');
    const nested = legacy + '/nested_PCM_1800000000000_2.pcm'; fs.mkdirSync(nested);
    fs.writeFileSync(nested + '/must-stay.pcm', 'retained');
    const info = await ExportService.getPcmShareCleanupInfo(ctx);
    assert.equal(info.fileCount, 2); assert.equal(info.sizeBytes, 5);
    const result = await ExportService.clearPcmShareCopies(ctx);
    assert.equal(result.removedCount, 2); assert.equal(result.removedBytes, 5); assert.equal(result.failedCount, 0);
    assert.equal(fs.existsSync(other), true); assert.equal(fs.existsSync(nested + '/must-stay.pcm'), true);
    assert.equal(fs.existsSync(original.filePath), true); assert.equal(repository.list(ctx).length, 1);
    assert.equal((await ExportService.clearPcmShareCopies(ctx)).removedCount, 0);
  });
  await asyncTest('cleanup reports deletion failures without false success and retries without altering recordings', async () => {
    const ctx = context(), original = create(ctx), legacy = ctx.filesDir + '/exports'; fs.mkdirSync(legacy);
    const first = legacy + '/first_PCM_1800000000000_1.pcm', second = legacy + '/second_PCM_1800000000000_2.pcm';
    fs.writeFileSync(first, 'abc'); fs.writeFileSync(second, 'xy');
    fault = (op, p) => op === 'unlink' && p === first;
    const partial = await ExportService.clearPcmShareCopies(ctx);
    assert.equal(partial.removedCount, 1); assert.equal(partial.removedBytes, 2); assert.equal(partial.failedCount, 1);
    assert.equal(fs.existsSync(first), true); assert.equal(fs.existsSync(second), false);
    fault = () => false;
    assert.equal((await ExportService.clearPcmShareCopies(ctx)).removedBytes, 3);
    assert.equal(fs.existsSync(original.filePath), true);
  });
  await asyncTest('an unreadable cleanup directory fails before removing any recognized copy', async () => {
    const ctx = context(), legacy = ctx.filesDir + '/exports'; fs.mkdirSync(legacy);
    const pcm = legacy + '/keep_PCM_1800000000000_1.pcm'; fs.writeFileSync(pcm, 'abc');
    fault = (op, p) => op === 'list' && p === legacy;
    await assert.rejects(ExportService.clearPcmShareCopies(ctx), /Injected list/);
    assert.equal(fs.existsSync(pcm), true);
  });
  await asyncTest('an unreadable PCM entry is preserved and reported while other copies can be cleared', async () => {
    const ctx = context(), legacy = ctx.filesDir + '/exports'; fs.mkdirSync(legacy);
    const pcm = legacy + '/keep_PCM_1800000000000_1.pcm'; fs.writeFileSync(pcm, 'abc');
    fault = (op, p) => op === 'lstat' && p === pcm;
    assert.equal((await ExportService.getPcmShareCleanupInfo(ctx)).failedCount, 1);
    assert.equal((await ExportService.clearPcmShareCopies(ctx)).failedCount, 1);
    assert.equal(fs.existsSync(pcm), true);
  });
  await asyncTest('cache directory symbolic links are rejected instead of traversed', async () => {
    const ctx = context(), original = create(ctx), cached = ctx.cacheDir + '/pcm_shares'; fs.mkdirSync(cached);
    const lstat = fileIo.lstat;
    fileIo.lstat = async p => p === cached ? { isDirectory: () => true, isSymbolicLink: () => true } : lstat(p);
    try {
      await assert.rejects(ExportService.exportWavAsPcm(ctx, original), /目录不可用/);
      await assert.rejects(ExportService.clearPcmShareCopies(ctx), /目录不可用/);
      assert.equal(fs.existsSync(original.filePath), true);
    } finally { fileIo.lstat = lstat; }
  });
  await asyncTest('symbolic-link PCM entries are never followed or cleared', async () => {
    const ctx = context(), legacy = ctx.filesDir + '/exports'; fs.mkdirSync(legacy);
    const pcm = legacy + '/keep_PCM_1800000000000_1.pcm'; fs.writeFileSync(pcm, 'target');
    const lstat = fileIo.lstat;
    fileIo.lstat = async p => p === pcm ? { isFile: () => false, isSymbolicLink: () => true } : lstat(p);
    try {
      assert.equal((await ExportService.clearPcmShareCopies(ctx)).removedCount, 0);
      assert.equal(fs.readFileSync(pcm, 'utf8'), 'target');
    } finally { fileIo.lstat = lstat; }
  });
  await asyncTest('concurrent cleanup waits for an in-progress export and preserves the newly completed copy', async () => {
    const ctx = context(), original = create(ctx), write = fileIo.write;
    let resume, signal; const started = new Promise(resolve => { signal = resolve; });
    const blocked = new Promise(resolve => { resume = resolve; }); let first = true;
    fileIo.write = async (...args) => { if (first) { first = false; signal(); await blocked; } return write(...args); };
    try {
      const pending = ExportService.exportWavAsPcm(ctx, original); await started;
      const cleanup = ExportService.clearPcmShareCopies(ctx); resume();
      const exported = await pending, result = await cleanup;
      assert.equal(result.removedCount, 0); assert.equal(result.protectedFileCount, 1);
      assert.deepEqual(fs.readFileSync(exported.filePath), fs.readFileSync(original.filePath).subarray(44));
      assert.equal(fs.readdirSync(ctx.cacheDir + '/pcm_shares').some(name => name.endsWith('.tmp')), false);
    } finally { fileIo.write = write; resume(); }
  });
  await asyncTest('the count quota rejects further recent copies and expires old ones before exporting again', async () => {
    const ctx = context(), original = create(ctx), directory = ctx.cacheDir + '/pcm_shares'; fs.mkdirSync(directory);
    for (let index = 0; index < 32; index++) fs.writeFileSync(directory + `/copy_PCM_${Date.now()}_${index}.pcm`, 'x');
    await assert.rejects(ExportService.exportWavAsPcm(ctx, original), /32 份或 2 GiB/);
    assert.equal(fs.readdirSync(directory).length, 32); assert.equal(fs.existsSync(original.filePath), true);
    const now = Date.now, future = now() + 8 * 86400000; Date.now = () => future;
    try {
      const exported = await ExportService.exportWavAsPcm(ctx, original);
      assert.equal(fs.readdirSync(directory).length, 1); assert.equal(fs.existsSync(exported.filePath), true);
    } finally { Date.now = now; }
  });
  await asyncTest('the byte quota rejects a new copy before writing and preserves existing cache bytes', async () => {
    const ctx = context(), original = create(ctx), directory = ctx.cacheDir + '/pcm_shares'; fs.mkdirSync(directory);
    const cached = directory + `/copy_PCM_${Date.now()}_1.pcm`; fs.writeFileSync(cached, 'retained');
    const lstat = fileIo.lstat;
    fileIo.lstat = async p => {
      const stat = await lstat(p); if (p === cached) return { isFile: () => true, isSymbolicLink: () => false, size: 2 ** 31 };
      return stat;
    };
    try {
      await assert.rejects(ExportService.exportWavAsPcm(ctx, original), /32 份或 2 GiB/);
      assert.equal(fs.readFileSync(cached, 'utf8'), 'retained'); assert.equal(fs.readdirSync(directory).length, 1);
    } finally { fileIo.lstat = lstat; }
  });
  await asyncTest('invalid parent traversal is rejected without touching a recording or outside directory', async () => {
    const ctx = context(), original = create(ctx), bad = { ...ctx, cacheDir: ctx.cacheDir + '/../recordings' };
    await assert.rejects(ExportService.exportWavAsPcm(bad, original), /无效/);
    await assert.rejects(ExportService.clearPcmShareCopies(bad), /无效/);
    assert.equal(fs.existsSync(original.filePath), true); assert.equal(fs.existsSync(ctx.filesDir + '/recordings/pcm_shares'), false);
  });
  await asyncTest('system save returns URI only after complete copy, and cancellation creates no output', async () => {
    const ctx = context(), original = create(ctx), destination = ctx.cacheDir + '/user-save.wav';
    assert.equal(await ExportService.saveToDevice(ctx, original), undefined);
    pickerAnswer = options => {
      assert.equal(options.newFileNames[0], original.fileName);
      assert.equal(options.autoCreateEmptyFile, false); return [destination];
    };
    maxWrite = 31;
    assert.equal(await ExportService.saveToDevice(ctx, original), destination);
    assert.deepEqual(fs.readFileSync(destination), fs.readFileSync(original.filePath));
  });
  await asyncTest('failed system save removes only its newly created destination and retains original', async () => {
    const ctx = context(), original = create(ctx), destination = ctx.cacheDir + '/failed-save.wav';
    pickerAnswer = () => [destination];
    fault = (op, p) => op === 'fsync' && p === destination;
    await assert.rejects(ExportService.saveToDevice(ctx, original));
    assert.equal(fs.existsSync(destination), false); assert.equal(fs.existsSync(original.filePath), true);
  });
  await asyncTest('original-byte backup of a damaged recording remains available without pretending it is playable', async () => {
    const ctx = context(), original = create(ctx), destination = ctx.cacheDir + '/backup.wav';
    fs.writeFileSync(original.filePath, Buffer.from('incomplete captured bytes'));
    const visible = repository.list(ctx)[0];
    assert.throws(() => repository.inspectRecording(ctx, visible));
    pickerAnswer = () => [destination];
    await ExportService.saveToDevice(ctx, visible);
    assert.deepEqual(fs.readFileSync(destination), fs.readFileSync(original.filePath));
  });
} finally {
  for (const fd of descriptors.keys()) fs.closeSync(fd);
  const resolved = fs.realpathSync(temporaryRoot);
  assert.equal(path.dirname(resolved), fs.realpathSync(os.tmpdir()));
  assert.ok(path.basename(resolved).startsWith('facilis-repository-tests-'));
  fs.rmSync(resolved, { recursive: true, force: true });
}
console.log(`Repository/export host checks: ${passed} passed, ${failed} failed. Device filesystem behavior remains separate.`);
process.exitCode = failed ? 1 : 0;
})().catch(error => { console.error(error); process.exitCode = 1; });
