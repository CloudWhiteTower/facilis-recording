#!/usr/bin/env node
// Runs the actual conversion service against controlled native/file/repository
// adapters. It validates transactions and cancellation, not codec fidelity.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const compilerPath = process.argv[2] || process.env.FACILIS_TYPESCRIPT;
if (!compilerPath) throw new Error('Pass the DevEco TypeScript compiler path');
const ts = require(path.resolve(compilerPath));
const ets = path.resolve(__dirname, '../HarmonyRecorder/entry/src/main/ets');
const settle = () => new Promise(resolve => setImmediate(resolve));
function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
function environment() {
  const cache = new Map(), descriptors = new Map(), files = new Map(), nativeHandles = new Map();
  const intervals = new Map(), calls = [], imports = [], notices = [], logged = [];
  const context = { cacheDir: '/cache', filesDir: '/files' };
  const state = { nextFd: 10, nextHandle: 1, nextTimer: 1, inspectFails: false, createFails: false,
    runFails: false, importFails: false, fsyncFails: false, cancelFails: false, progressFails: false,
    releaseFailures: 0, createGate: null, runGate: null, releaseGate: null, fsyncGate: null,
    resultOverride: null, progress: 0.4 };
  const io = {
    OpenMode: { READ_ONLY: 1, READ_WRITE: 2, CREATE: 4, TRUNC: 8 },
    openSync(name, flags) {
      if (flags & 4) { assert.ok(name.startsWith('/cache/')); files.set(name, Buffer.alloc(0)); }
      assert.ok(files.has(name), 'opened path exists');
      const file = { fd: state.nextFd++ }; descriptors.set(file.fd, { name, flags });
      calls.push(['open', name, file.fd, flags]); return file;
    },
    statSync(fd) { return { size: files.get(descriptors.get(fd).name).length }; },
    async fsync(fd) {
      assert.ok(descriptors.has(fd)); calls.push(['fsync', fd]);
      if (state.fsyncGate) await state.fsyncGate.promise;
      if (state.fsyncFails) throw new Error('fsync failed');
    },
    closeSync(file) {
      assert.ok(descriptors.has(file.fd), 'descriptor closes exactly once');
      assert.ok(!Array.from(nativeHandles.values()).some(item => item.sourceFd === file.fd || item.outputFd === file.fd),
        'native release completes before either source or output is closed');
      calls.push(['close', file.fd]); descriptors.delete(file.fd);
    },
    unlinkSync(name) {
      assert.ok(name.startsWith('/cache/'), 'cleanup never unlinks original or imported recording');
      assert.ok(files.has(name), 'temporary file exists'); calls.push(['unlink', name]); files.delete(name);
    }
  };
  const codec = {
    async conversionCreate(sourceFd, length, outputFd, target, bitrate, depth) {
      calls.push(['create', sourceFd, outputFd, target, bitrate, depth]);
      assert.equal(descriptors.get(sourceFd).flags, 1, 'original is opened read-only');
      assert.equal(length, files.get(descriptors.get(sourceFd).name).length);
      assert.ok(descriptors.has(outputFd));
      if (state.createFails) throw new Error('create failed');
      const handle = state.nextHandle++;
      nativeHandles.set(handle, { sourceFd, outputFd, target, bitrate, depth, cancelled: false });
      if (state.createGate) await state.createGate.promise;
      return handle;
    },
    async conversionRun(handle) {
      calls.push(['run', handle]); const item = nativeHandles.get(handle); assert.ok(item);
      files.set(descriptors.get(item.outputFd).name, Buffer.from([70, 76, 65, 67, 1, 2, 3]));
      if (state.runGate) await state.runGate.promise;
      if (item.cancelled) throw new Error('native conversion cancelled');
      if (state.runFails) throw new Error('decode failed');
      return state.resultOverride || { sampleRate: 48000, channels: 1,
        bitDepth: item.target === 'm4a' ? 0 : item.depth, bitrate: item.target === 'm4a' ? item.bitrate : 0 };
    },
    conversionCancel(handle) {
      calls.push(['cancel', handle]);
      if (state.cancelFails) throw new Error('handle already gone');
      const item = nativeHandles.get(handle); if (item) item.cancelled = true;
    },
    conversionProgress(handle) {
      assert.ok(nativeHandles.has(handle)); calls.push(['progress', handle]);
      if (state.progressFails) throw new Error('progress unavailable'); return state.progress;
    },
    async conversionRelease(handle) {
      calls.push(['release', handle]);
      if (state.releaseGate) await state.releaseGate.promise;
      if (state.releaseFailures > 0) { state.releaseFailures--; throw new Error('release transient failure'); }
      const item = nativeHandles.get(handle);
      if (item) {
        assert.ok(descriptors.has(item.sourceFd)); assert.ok(descriptors.has(item.outputFd));
        nativeHandles.delete(handle);
      }
      calls.push(['released', handle]);
    }
  };
  const repository = {
    inspectRecording(receivedContext, recording) {
      assert.equal(receivedContext, context); calls.push(['inspect']);
      if (state.inspectFails) throw new Error('source invalid'); return recording;
    },
    importCompletedFile(receivedContext, temporaryPath, config, name) {
      assert.equal(receivedContext, context);
      assert.equal(nativeHandles.size, 0, 'import waits for native release');
      assert.ok(!Array.from(descriptors.values()).some(item => item.name === temporaryPath), 'output is closed before import');
      assert.ok(files.has(temporaryPath)); calls.push(['import', temporaryPath]);
      if (state.importFails) throw new Error('index commit failed');
      const destination = `/files/converted-${imports.length}.${config.format}`;
      files.set(destination, files.get(temporaryPath)); files.delete(temporaryPath);
      const { RecordingInfo } = load(path.join(ets, 'models/RecordingTypes.ets'));
      const result = new RecordingInfo(`${name}.${config.format}`, destination, config, 1000, 1000,
        files.get(destination).length);
      imports.push(result); return result;
    }
  };
  function load(filename) {
    if (cache.has(filename)) return cache.get(filename).exports;
    const module = { exports: {} }; cache.set(filename, module);
    const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    const requireLocal = name => {
      if (name === '@kit.CoreFileKit') return { fileIo: io };
      if (name === '@kit.AbilityKit') return {};
      if (name === 'libfacilis_flac.so') return { default: codec };
      if (name === '../repository/RecordingRepository') return { RecordingRepository: repository };
      if (name.startsWith('.')) return load(path.resolve(path.dirname(filename), name + '.ets'));
      throw new Error('Unexpected import ' + name);
    };
    new Function('require', 'module', 'exports', 'setInterval', 'clearInterval', 'console', code)(
      requireLocal, module, module.exports,
      callback => { const timer = state.nextTimer++; intervals.set(timer, callback); return timer; },
      timer => intervals.delete(timer), { error: message => logged.push(message) });
    return module.exports;
  }
  const types = load(path.join(ets, 'models/RecordingTypes.ets'));
  const { AudioConversionService } = load(path.join(ets, 'services/AudioConversionService.ets'));
  const service = new AudioConversionService();
  const original = new types.RecordingInfo('original.wav', '/files/original.wav', types.RecordingConfig.wav(), 1000, 1, 4);
  files.set(original.filePath, Buffer.from([1, 2, 3, 4]));
  const sourceBytes = Buffer.from(files.get(original.filePath)), sourceMetadata = JSON.stringify(original);
  const convert = (target = types.RecordingFormat.FLAC, progress = value => notices.push(value), selected = original,
    instance = service, bitrate = 128000) => instance.convert(context, selected, target, bitrate, progress);
  function clean(expectedImports = 0) {
    assert.equal(nativeHandles.size, 0); assert.equal(descriptors.size, 0); assert.equal(intervals.size, 0);
    assert.equal(imports.length, expectedImports); assert.ok(!Array.from(files.keys()).some(name => name.startsWith('/cache/')));
    assert.deepEqual(files.get(original.filePath), sourceBytes, 'original bytes are unchanged');
    assert.equal(JSON.stringify(original), sourceMetadata, 'original metadata is unchanged');
  }
  const tick = () => { for (const callback of intervals.values()) callback(); };
  return { service, AudioConversionService, state, calls, imports, files, descriptors, intervals,
    notices, logged, original, types, context, convert, clean, tick };
}
let passed = 0, failed = 0;
async function test(name, body) {
  try { await body(); passed++; console.log('PASS ' + name); }
  catch (error) { failed++; console.error('FAIL ' + name + ': ' + error.stack); }
}
(async () => {
  await test('progress is monotonic, deduplicated and resets when the same service is reused', async () => {
    const e = environment(), gate = deferred(); e.state.runGate = gate;
    const pending = e.convert(); await settle();
    for (const progress of [0.4, 0.4, 0.3, 0.4001, 0.8, 0.7]) { e.state.progress = progress; e.tick(); }
    assert.deepEqual(e.notices, [0, 0.4, 0.8]); gate.resolve(); await pending;
    e.state.runGate = null; await e.convert();
    assert.deepEqual(e.notices, [0, 0.4, 0.8, 1, 0, 1]); e.clean(2);
  });
  await test('success releases native resources, flushes and closes output, then imports a new file', async () => {
    const e = environment(), result = await e.convert(); e.clean(1);
    assert.notEqual(result.filePath, e.original.filePath); assert.deepEqual(e.notices, [0, 1]);
    const index = name => e.calls.findIndex(call => call[0] === name);
    assert.ok(index('released') < index('fsync')); assert.ok(index('fsync') < index('close'));
    assert.ok(index('close') < index('import'));
  });
  await test('cancelling during create releases the late handle without running or importing', async () => {
    const e = environment(), gate = deferred(); e.state.createGate = gate;
    const pending = e.convert(); await settle(); e.service.cancel(); gate.resolve();
    assert.equal(await pending, undefined); e.clean();
    assert.equal(e.calls.filter(call => call[0] === 'run').length, 0);
    assert.equal(e.calls.filter(call => call[0] === 'cancel').length, 1);
  });
  await test('cancelling during native run removes partial output and preserves original', async () => {
    const e = environment(), gate = deferred(); e.state.runGate = gate;
    const pending = e.convert(); await settle(); e.service.cancel(); gate.resolve();
    assert.equal(await pending, undefined); e.clean();
  });
  await test('cancelling during native release still prevents import', async () => {
    const e = environment(), gate = deferred(); e.state.releaseGate = gate;
    const pending = e.convert(); await settle(); assert.equal(e.intervals.size, 0);
    e.service.cancel(); gate.resolve(); assert.equal(await pending, undefined); e.clean();
  });
  await test('cancelling during fsync prevents import after native work completes', async () => {
    const e = environment(), gate = deferred(); e.state.fsyncGate = gate;
    const pending = e.convert(); await settle(); e.service.cancel(); gate.resolve();
    assert.equal(await pending, undefined); e.clean();
  });
  await test('global lock rejects same-instance and second-instance overlap, then allows reuse', async () => {
    const e = environment(), gate = deferred(); e.state.runGate = gate;
    const pending = e.convert(); await settle();
    await assert.rejects(e.convert(), /已有格式转换/);
    const other = new e.AudioConversionService(); await assert.rejects(e.convert(undefined, undefined, undefined, other), /已有格式转换/);
    e.service.cancel(); gate.resolve(); assert.equal(await pending, undefined); e.clean();
    e.state.runGate = null; await e.convert(undefined, undefined, undefined, other); e.clean(1);
  });
  await test('create, decode, fsync and import failures clean resources and release the lock', async () => {
    for (const [key, message] of [['createFails', /create failed/], ['runFails', /decode failed/],
      ['fsyncFails', /fsync failed/], ['importFails', /index commit failed/]]) {
      const e = environment(); e.state[key] = true;
      await assert.rejects(e.convert(), message); e.clean();
      e.state[key] = false; await e.convert(); e.clean(1);
    }
  });
  await test('a release error before commit retries cleanup and never imports incomplete work', async () => {
    const e = environment(); e.state.releaseFailures = 1;
    await assert.rejects(e.convert(), /release transient failure/); e.clean();
    assert.equal(e.calls.filter(call => call[0] === 'release').length, 2);
  });
  await test('progress read and observer errors cannot escape timers or undo a committed import', async () => {
    const e = environment(), gate = deferred(); e.state.runGate = gate;
    const pending = e.convert(undefined, () => { throw new Error('page detached'); }); await settle();
    e.state.progressFails = true; e.tick(); e.state.progressFails = false; e.state.progress = NaN; e.tick();
    e.state.progress = 2; e.tick(); gate.resolve(); assert.ok(await pending); e.clean(1);
    assert.ok(e.logged.some(message => message.includes('page detached')));
  });
  await test('progress stays below completion until commit and cancellation errors remain contained', async () => {
    const e = environment(), gate = deferred(); e.state.runGate = gate;
    const pending = e.convert(); await settle(); e.state.progress = 2; e.tick();
    assert.deepEqual(e.notices, [0, 0.99]);
    e.state.cancelFails = true; e.service.cancel(); gate.resolve();
    assert.equal(await pending, undefined); e.clean(); assert.ok(!e.notices.includes(1));
  });
  await test('invalid or unknown source parameters are rejected before creating output', async () => {
    for (const [rate, depth, channels] of [[0, 16, 1], [96000, 16, 1], [48000, 0, 1],
      [48000, 12, 1], [48000, 32, 1], [48000, 16, 2]]) {
      const e = environment(), config = new e.types.RecordingConfig(e.types.RecordingFormat.WAV, rate, depth, 0, channels);
      const selected = new e.types.RecordingInfo('unknown.wav', e.original.filePath, config, 1000, 1);
      await assert.rejects(e.convert(undefined, undefined, selected), /单声道|位深/); e.clean();
      assert.equal(e.calls.filter(call => call[0] === 'open').length, 0);
    }
  });
  await test('24-bit input cannot silently become 16-bit FLAC, but remains 24-bit when converted to WAV', async () => {
    const e = environment(), config = new e.types.RecordingConfig(e.types.RecordingFormat.FLAC, 48000, 24, 0, 1);
    const selected = new e.types.RecordingInfo('depth.flac', e.original.filePath, config, 1000, 1);
    await assert.rejects(e.convert(e.types.RecordingFormat.FLAC, undefined, selected), /保留精度/); e.clean();
    const result = await e.convert(e.types.RecordingFormat.WAV, undefined, selected); e.clean(1);
    assert.equal(result.config.bitDepth, 24);
  });
  await test('AAC bitDepth zero is a compressed format rather than an unknown PCM depth', async () => {
    const e = environment(), selected = new e.types.RecordingInfo('aac.m4a', e.original.filePath,
      e.types.RecordingConfig.aac(128000), 1000, 1);
    const result = await e.convert(e.types.RecordingFormat.WAV, undefined, selected); e.clean(1);
    assert.equal(result.config.bitDepth, 16);
  });
  await test('illegal target, unsupported AAC bitrate and redundant lossless conversion are rejected', async () => {
    const e = environment();
    await assert.rejects(e.convert('../original'), /目标音频格式/);
    await assert.rejects(e.convert(e.types.RecordingFormat.M4A, undefined, undefined, undefined, 0), /128 或 256/);
    await assert.rejects(e.convert(e.types.RecordingFormat.WAV), /已是此格式/); e.clean();
    assert.equal(e.calls.filter(call => call[0] === 'open').length, 0);
  });
  await test('native output with an unexpected rate, depth or channel count is never imported', async () => {
    for (const result of [{ sampleRate: 0, bitDepth: 16, channels: 1, bitrate: 0 },
      { sampleRate: 44100, bitDepth: 16, channels: 1, bitrate: 0 },
      { sampleRate: 48000, bitDepth: 0, channels: 1, bitrate: 0 },
      { sampleRate: 48000, bitDepth: 16, channels: 2, bitrate: 0 }]) {
      const e = environment(); e.state.resultOverride = result;
      await assert.rejects(e.convert(), /音频参数与请求不一致/); e.clean();
    }
  });
  await test('inspection failure creates no file and pre-start cancellation avoids native allocation', async () => {
    const e = environment(); e.state.inspectFails = true;
    await assert.rejects(e.convert(), /source invalid/); e.clean();
    e.state.inspectFails = false;
    assert.equal(await e.convert(undefined, progress => { if (progress === 0) e.service.cancel(); }), undefined);
    e.clean(); assert.equal(e.calls.filter(call => call[0] === 'create').length, 0);
  });
  console.log(`Audio conversion host tests: ${passed} passed, ${failed} failed`);
  if (failed) process.exitCode = 1;
})().catch(error => { console.error(error); process.exitCode = 1; });
