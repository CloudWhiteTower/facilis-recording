#!/usr/bin/env node
// Accelerated host fault tests of the real ArkTS RecordingService. Audio, clock,
// background tasks and OS file APIs are fakes: this is NOT a long device recording.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const compilerPath = process.argv[2] || process.env.FACILIS_TYPESCRIPT;
if (!compilerPath) throw new Error('Pass the DevEco TypeScript compiler path');
const ts = require(path.resolve(compilerPath));
const root = path.resolve(__dirname, '..');
const ets = path.join(root, 'HarmonyRecorder/entry/src/main/ets');
let passed = 0;

function environment() {
  const files = new Map(), descriptors = new Map(), cache = new Map(), saved = [], notices = [], timers = new Map();
  const state = { now: 1000, nextFd: 10, sequence: 0, activeMic: 0, bgActive: false, capturer: null,
    partialLimit: Infinity, failAfter: Infinity, dataWritten: 0, zeroNext: false, seekFails: false,
    fsyncFails: false, deleteFails: false, bgStartFails: false, blocked: false, unblock: null,
    backgroundCancel: null, pcmMaximum: 0, queueMaximum: 0, amplitude: 0,
    cancelDuringStart: false, cancelDuringPause: false, flacCalls: [], nativeFd: -1,
    flacCreateFails: false, flacFinishFails: false, stopFailures: 0, releaseFailures: 0, writeCalls: 0,
    streamOverride: null, streamInfoFails: false, capturers: [], recorders: [],
    m4aPausePending: null, m4aPauseResolve: null };
  const recordFile = fd => {
    const handle = descriptors.get(fd);
    assert.ok(handle, 'file descriptor is open');
    return handle;
  };
  const writeBytes = (fd, bytes, options) => {
    const h = recordFile(fd), input = new Uint8Array(bytes);
    const position = options?.offset ?? h.position;
    if (position < 44) h.file.header.set(input.subarray(0, Math.min(input.length, 44 - position)), position);
    if (options?.offset === undefined) h.position += input.length;
    h.file.size = Math.max(h.file.size, position + input.length);
    return input.length;
  };
  const io = {
    OpenMode: { READ_WRITE: 1, CREATE: 2, TRUNC: 4 }, WhenceType: { SEEK_SET: 0 },
    openSync(name) {
      const file = { size: 0, header: new Uint8Array(44) };
      files.set(name, file);
      const fd = state.nextFd++;
      descriptors.set(fd, { file, position: 0 });
      return { fd };
    },
    closeSync(file) { descriptors.delete(typeof file === 'number' ? file : file.fd); },
    statSync(name) { if (!files.has(name)) throw new Error('ENOENT'); return { size: files.get(name).size }; },
    lseek(fd, offset) { if (state.seekFails && offset >= 44) throw new Error('EIO seek'); recordFile(fd).position = offset; },
    truncateSync(fd, length) { recordFile(fd).file.size = length; },
    writeSync(fd, bytes) { return writeBytes(fd, bytes); },
    async write(fd, bytes, options) {
      if (state.blocked) await new Promise(resolve => { state.unblock = resolve; });
      if (state.zeroNext) { state.zeroNext = false; return 0; }
      const payload = options?.offset === undefined;
      if (payload && state.dataWritten >= state.failAfter) throw new Error('ENOSPC injected');
      const count = Math.min(bytes.byteLength, state.partialLimit, payload ? state.failAfter - state.dataWritten : Infinity);
      const actual = writeBytes(fd, bytes.slice(0, count), options);
      if (payload) { state.dataWritten += actual; state.writeCalls++; }
      return actual;
    },
    async fsync() { if (state.fsyncFails) throw new Error('EIO fsync'); },
    fsyncSync() { if (state.fsyncFails) throw new Error('EIO fsync'); }
  };
  const repository = {
    createNewRecording(context, config) {
      const { RecordingInfo } = load(path.join(ets, 'models/RecordingTypes.ets'));
      return new RecordingInfo(`take-${++state.sequence}.${config.extension}`,
        `/fake/take-${state.sequence}.${config.extension}`, config, 0, state.now);
    },
    save(context, recording) { saved.push(recording); return recording; },
    releaseTemporaryReservation() {},
    discardTemporary(recording) { if (state.deleteFails) throw new Error('EACCES injected'); files.delete(recording.filePath); }
  };
  class BackgroundTask {
    async start(context, cancelled) {
      if (state.bgStartFails) throw new Error('background denied');
      state.bgActive = true; state.backgroundCancel = cancelled;
      if (state.cancelDuringStart) {
        state.cancelDuringStart = false;
        state.capturer.emit(new ArrayBuffer(9600));
        cancelled();
      }
    }
    async stop() { state.bgActive = false; state.backgroundCancel = null; }
  }
  const audio = {
    AudioSamplingRate: { SAMPLE_RATE_44100: 44100, SAMPLE_RATE_48000: 48000 },
    AudioChannel: { CHANNEL_1: 1 }, AudioSampleFormat: { SAMPLE_FORMAT_S16LE: 16, SAMPLE_FORMAT_S24LE: 24 },
    AudioEncodingType: { ENCODING_TYPE_RAW: 0 }, SourceType: { SOURCE_TYPE_MIC: 0 },
    InterruptHint: { INTERRUPT_HINT_NONE: 0, INTERRUPT_HINT_RESUME: 1 },
    async createAudioCapturer(options) {
      const listeners = new Map();
      const capturer = { running: false, released: false, starts: 0,
        async getStreamInfo() {
          if (state.streamInfoFails) throw new Error('injected stream-info query failure');
          return { ...options.streamInfo, ...state.streamOverride };
        },
        on(name, fn) { listeners.set(name, fn); }, off(name) { listeners.delete(name); },
        async start() { this.starts++; if (!this.running) state.activeMic++; this.running = true; },
        async stop() {
          if (state.stopFailures > 0) { state.stopFailures--; throw new Error('injected capturer stop failure'); }
          if (this.running) state.activeMic--;
          this.running = false;
          if (state.cancelDuringPause) {
            state.cancelDuringPause = false;
            state.backgroundCancel?.();
          }
        },
        async release() {
          if (state.releaseFailures > 0) { state.releaseFailures--; throw new Error('injected capturer release failure'); }
          if (this.running) state.activeMic--;
          this.running = false;
          this.released = true;
        },
        emit(bytes) { if (this.running) listeners.get('readData')?.(bytes); },
        interrupt() { listeners.get('audioInterrupt')?.({ hintType: 2 }); }
      };
      state.capturer = capturer;
      state.capturers.push(capturer);
      return capturer;
    }
  };
  const media = {
    AudioSourceType: { AUDIO_SOURCE_TYPE_MIC: 0 }, CodecMimeType: { AUDIO_AAC: 0 },
    AacProfile: { AAC_LC: 0 }, ContainerFormatType: { CFT_MPEG_4A: 0 },
    StateChangeReason: { USER: 1, BACKGROUND: 2 },
    async createAVRecorder() {
      let running = false;
      const listeners = new Map();
      const recorder = { state: 'idle', listeners, stopCalls: 0, releaseCalls: 0,
        on(name, callback) { listeners.set(name, callback); }, off(name) { listeners.delete(name); },
        transition(next, reason = media.StateChangeReason.USER) {
          this.state = next;
          listeners.get('stateChange')?.(next, reason);
        },
        async prepare() { this.transition('prepared'); },
        async start() { running = true; state.activeMic++; this.transition('started'); },
        async pause() {
          if (running) state.activeMic--;
          running = false; this.transition('paused');
          if (state.m4aPausePending) await state.m4aPausePending;
        },
        async resume() { if (!running) state.activeMic++; running = true; this.transition('started'); },
        async stop() {
          this.stopCalls++;
          if (this.state !== 'started' && this.state !== 'paused') throw new Error('illegal native stop state');
          if (running) state.activeMic--;
          running = false; this.transition('stopped');
        },
        async release() {
          this.releaseCalls++;
          if (running) state.activeMic--;
          running = false; this.transition('released');
        },
        systemTransition(next) {
          if (running) state.activeMic--;
          running = false; this.transition(next, media.StateChangeReason.BACKGROUND);
        },
        async getAudioCapturerMaxAmplitude() { return 0; }
      };
      state.recorders.push(recorder);
      return recorder;
    }
  };
  function load(filename) {
    const file = path.resolve(filename);
    if (cache.has(file)) return cache.get(file).exports;
    const module = { exports: {} }; cache.set(file, module);
    const compiled = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    function localRequire(name) {
      if (name === '@kit.AbilityKit') return {};
      if (name === '@kit.AudioKit') return { audio };
      if (name === '@kit.CoreFileKit') return { fileIo: io };
      if (name === '@kit.MediaKit') return { media };
      if (name === '@kit.BasicServicesKit') return {
        systemDateTime: { TimeType: { STARTUP: 0 }, getUptime: () => state.now }
      };
      if (name === 'libfacilis_flac.so') return { default: {
        async create(fd) {
          state.flacCalls.push('create');
          if (state.flacCreateFails) throw new Error('unsupported encoder');
          state.nativeFd = fd;
          return 1;
        },
        async write(handle, bytes) {
          state.flacCalls.push('write');
          writeBytes(state.nativeFd, bytes); // Lifecycle fake, not a FLAC encoder.
        },
        async finish() {
          state.flacCalls.push('finish');
          if (state.flacFinishFails) throw new Error('injected encoder finalization error');
        },
        async release() { state.flacCalls.push('release'); }
      } };
      if (name.endsWith('/RecordingRepository')) return { RecordingRepository: repository };
      if (name.endsWith('/BackgroundRecordingTask')) return { BackgroundRecordingTask: BackgroundTask };
      if (name.startsWith('.')) return load(path.resolve(path.dirname(file), name + '.ets'));
      throw new Error(`Unexpected import ${name}`);
    }
    new Function('require', 'module', 'exports', 'setInterval', 'clearInterval', compiled)(
      localRequire, module, module.exports,
      callback => { const id = timers.size + 1; timers.set(id, callback); return id; }, id => timers.delete(id));
    return module.exports;
  }
  const { RecordingService } = load(path.join(ets, 'services/RecordingService.ets'));
  const { RecordingConfig, RecordingState } = load(path.join(ets, 'models/RecordingTypes.ets'));
  const service = RecordingService.getInstance();
  service.setObserver(snapshot => { if (snapshot.message) notices.push(snapshot.message); });
  async function settled() {
    for (let pass = 0; pass < 300; pass++) {
      await Promise.resolve();
      if (!service.operationBusy && service.pcmWritePromise === undefined) return;
    }
    throw new Error('Recording operation failed to settle');
  }
  async function feed(bytes, wait = true) {
    state.capturer.emit(bytes);
    state.pcmMaximum = Math.max(state.pcmMaximum, service.pcmPendingBytes);
    state.queueMaximum = Math.max(state.queueMaximum, service.pcmWriteQueue.length);
    if (wait) await settled();
  }
  return { state, files, saved, notices, service, config: RecordingConfig, states: RecordingState, feed, settled,
    tick() { for (const callback of [...timers.values()]) callback(); },
    assertReleased() {
      assert.equal(state.activeMic, 0); assert.equal(state.bgActive, false); assert.equal(descriptors.size, 0);
      assert.ok(state.capturers.every(capturer => capturer.released), 'every created capturer was released');
    }
  };
}

async function test(name, fn) { await fn(); passed++; console.log(`PASS ${name}`); }
(async () => {
  await test('negotiated rate, channels, bit depth and encoding must match before PCM capture starts', async () => {
    for (const override of [{ samplingRate: 44100 }, { channels: 2 }, { sampleFormat: 16 }, { encodingType: 1 }]) {
      const e = environment(); e.state.streamOverride = override;
      await assert.rejects(e.service.start({}, e.config.wav(48000, 24)), /不支持所选录音质量/);
      assert.equal(e.state.capturer.starts, 0); assert.equal(e.saved.length, 0);
      assert.equal(e.files.size, 0); assert.equal(e.service.getState(), e.states.IDLE); e.assertReleased();
    }
  });
  await test('stream-info query failure releases the prepared capturer and empty WAV or FLAC output', async () => {
    for (const config of [e => e.config.wav(), e => e.config.flac()]) {
      const e = environment(); e.state.streamInfoFails = true;
      await assert.rejects(e.service.start({}, config(e)), /stream-info query failure/);
      assert.equal(e.state.capturer.starts, 0); assert.equal(e.files.size, 0);
      assert.equal(e.saved.length, 0); e.assertReleased();
    }
  });
  await test('an input-format change on resume saves only the previously recorded, valid PCM prefix', async () => {
    const e = environment(); await e.service.start({}, e.config.wav()); await e.feed(new ArrayBuffer(9600));
    await e.service.pause(); e.state.streamOverride = { samplingRate: 44100 };
    await assert.rejects(e.service.resume(), /不支持所选录音质量/); await e.settled();
    assert.equal(e.state.capturer.starts, 0); assert.equal(e.saved.length, 1);
    assert.equal(e.saved[0].sizeBytes, 44 + 9600); assert.equal(e.saved[0].durationMs, 100);
    assert.equal(e.service.getState(), e.states.STOPPED); e.assertReleased();
  });
  await test('periodic WAV checkpoints expose only complete, even sample prefixes before stop', async () => {
    const e = environment(); await e.service.start({}, e.config.wav(48000, 24));
    for (let index = 0; index < 5; index++) await e.feed(new ArrayBuffer(144000));
    const file = [...e.files.values()][0];
    assert.equal(new DataView(file.header.buffer).getUint32(40, true), 720000);
    await e.feed(new ArrayBuffer(303)); await e.service.pause();
    assert.equal(new DataView(file.header.buffer).getUint32(40, true), 720300);
    const result = await e.service.stop();
    assert.equal(new DataView(file.header.buffer).getUint32(40, true), 720303);
    assert.equal(result.sizeBytes, 44 + 720304); e.assertReleased();
  });
  await test('queued packets are coalesced without losing samples or extending the memory bound', async () => {
    const e = environment(); await e.service.start({}, e.config.wav()); e.state.blocked = true;
    for (let index = 0; index < 15; index++) await e.feed(new ArrayBuffer(9600), false);
    e.state.blocked = false; e.state.unblock(); await e.settled();
    const result = await e.service.stop();
    assert.equal(result.sizeBytes, 44 + 15 * 9600);
    assert.ok(e.state.writeCalls < 15); e.assertReleased();
  });
  await test('a stalled PCM source saves its committed prefix, while pause does not trigger the watchdog', async () => {
    const e = environment(); await e.service.start({}, e.config.wav()); await e.feed(new ArrayBuffer(9600));
    await e.service.pause(); e.state.now += 6000; e.tick(); await e.settled();
    assert.equal(e.service.getState(), e.states.PAUSED);
    await e.service.resume(); e.state.now += 5000; e.tick(); await e.settled();
    assert.equal(e.saved.length, 1); assert.equal(e.saved[0].durationMs, 100); e.assertReleased();
  });
  await test('a detached observer cannot interrupt capture or committed saves', async () => {
    const e = environment(); e.service.setObserver(() => { throw new Error('detached view'); });
    await e.service.start({}, e.config.wav()); await e.feed(new ArrayBuffer(9600));
    const result = await e.service.stop(); assert.equal(result.durationMs, 100); e.assertReleased();
  });
  await test('accelerated 2-hour WAV stream has exact committed bytes and sample duration, with bounded memory', async () => {
    const e = environment();
    await e.service.start({}, e.config.wav());
    const packet = new ArrayBuffer(96000); // One second of mono 48 kHz S16LE.
    for (let second = 0; second < 7200; second++) {
      e.state.now += 1000;
      await e.feed(packet);
    }
    const result = await e.service.stop();
    assert.equal(result.durationMs, 7200000);
    assert.equal(result.sizeBytes, 44 + 7200 * 96000);
    assert.equal(new DataView(e.files.get(result.filePath).header.buffer).getUint32(40, true), 7200 * 96000);
    assert.ok(e.state.pcmMaximum <= 2 * 1024 * 1024);
    assert.ok(e.state.queueMaximum <= 64);
    e.assertReleased();
  });
  await test('pause excludes downtime and resume appends audio rather than resetting the stream', async () => {
    const e = environment(); await e.service.start({}, e.config.wav(44100, 24));
    await e.feed(new ArrayBuffer(132300)); await e.service.pause();
    assert.equal(e.state.activeMic, 0); assert.equal(e.state.bgActive, false);
    e.state.now += 3600000; assert.equal(e.service.getDuration(), 1000);
    await e.service.resume(); await e.feed(new ArrayBuffer(132300));
    const result = await e.service.stop(); assert.equal(result.durationMs, 2000); e.assertReleased();
  });
  await test('short writes preserve every byte and 24-bit odd payloads receive a RIFF pad', async () => {
    const e = environment(); e.state.partialLimit = 7;
    await e.service.start({}, e.config.wav(48000, 24)); await e.feed(new ArrayBuffer(303));
    const result = await e.service.stop(), header = new DataView(e.files.get(result.filePath).header.buffer);
    assert.equal(result.sizeBytes, 44 + 304); assert.equal(header.getUint32(40, true), 303);
    assert.equal(header.getUint32(4, true), 36 + 304); e.assertReleased();
  });
  await test('disk failure auto-stops and saves only the complete-sample prefix', async () => {
    const e = environment(); e.state.failAfter = 9603;
    await e.service.start({}, e.config.wav()); await e.feed(new ArrayBuffer(9600));
    await e.feed(new ArrayBuffer(9600)); await e.settled();
    assert.equal(e.saved.length, 1); assert.equal(e.saved[0].sizeBytes, 44 + 9602);
    assert.ok(e.notices.some(x => x.includes('写入失败'))); e.assertReleased();
  });
  await test('zero-progress and synchronous seek errors terminate without a flush microtask loop', async () => {
    for (const failure of ['zeroNext', 'seekFails']) {
      const e = environment(); await e.service.start({}, e.config.wav()); e.state[failure] = true;
      await e.feed(new ArrayBuffer(9600)); await e.settled();
      assert.equal(e.saved.length, 0); assert.equal(e.service.getState(), e.states.STOPPED); e.assertReleased();
    }
  });
  await test('slow storage cannot grow beyond either the packet or byte queue bound', async () => {
    for (const packetBytes of [9600, 128 * 1024]) {
      const e = environment(); await e.service.start({}, e.config.wav()); e.state.blocked = true;
      for (let index = 0; index < 1000; index++) await e.feed(new ArrayBuffer(packetBytes), false);
      assert.ok(e.state.pcmMaximum <= 2 * 1024 * 1024); assert.ok(e.state.queueMaximum <= 64);
      e.state.blocked = false; e.state.unblock(); await e.settled();
      assert.equal(e.saved.length, 1); assert.ok(e.notices.some(x => x.includes('写入速度不足'))); e.assertReleased();
    }
  });
  await test('RIFF limit is checked before accepting the next packet and preserves a legal header', async () => {
    const e = environment(); await e.service.start({}, e.config.wav());
    const limit = 0xFFFFFFFE - 36;
    e.service.pcmDataBytes = limit - 2;
    await e.feed(new ArrayBuffer(4)); await e.settled();
    assert.equal(e.saved.length, 1);
    const header = new DataView(e.files.get(e.saved[0].filePath).header.buffer);
    assert.equal(header.getUint32(40, true), limit - 2);
    assert.ok(e.notices.some(x => x.includes('RIFF'))); e.assertReleased();
  });
  await test('background task denial and cancellation cannot leave a microphone active', async () => {
    const denied = environment(); denied.state.bgStartFails = true;
    await assert.rejects(denied.service.start({}, denied.config.wav())); denied.assertReleased();
    const e = environment(); await e.service.start({}, e.config.wav()); await e.feed(new ArrayBuffer(9600));
    e.state.backgroundCancel(); await e.settled(); assert.equal(e.saved.length, 1); e.assertReleased();
  });
  await test('failed background reacquisition rolls a resumed stream back to paused', async () => {
    const e = environment(); await e.service.start({}, e.config.wav()); await e.feed(new ArrayBuffer(9600));
    await e.service.pause(); e.state.bgStartFails = true;
    await assert.rejects(e.service.resume()); assert.equal(e.service.getState(), e.states.PAUSED);
    assert.equal(e.state.activeMic, 0); assert.equal(e.state.bgActive, false);
    await e.service.stop(); e.assertReleased();
  });
  await test('capture interruption and file removal failure both clear the recording state', async () => {
    const interrupted = environment(); await interrupted.service.start({}, interrupted.config.wav());
    await interrupted.feed(new ArrayBuffer(9600)); interrupted.state.capturer.interrupt(); await interrupted.settled();
    interrupted.assertReleased(); assert.equal(interrupted.saved.length, 1);
    const e = environment(); await e.service.start({}, e.config.wav()); await e.feed(new ArrayBuffer(9600));
    e.state.deleteFails = true; await assert.rejects(e.service.discard());
    assert.equal(e.service.getState(), e.states.STOPPED); e.assertReleased();
  });
  await test('fsync failure is reported and releases recording resources', async () => {
    const e = environment(); await e.service.start({}, e.config.wav()); await e.feed(new ArrayBuffer(9600));
    e.state.fsyncFails = true; await assert.rejects(e.service.stop());
    assert.equal(e.saved.length, 0); assert.equal(e.service.getState(), e.states.STOPPED); e.assertReleased();
  });
  await test('M4A uses a monotonic pause-aware clock and does not inherit a previous WAV write error', async () => {
    const e = environment(); await e.service.start({}, e.config.wav()); e.state.zeroNext = true;
    await e.feed(new ArrayBuffer(100)); await e.settled(); e.notices.length = 0;
    await e.service.start({}, e.config.aac(128000)); e.state.now += 1000; await e.service.pause();
    e.state.now += 60000; assert.equal(e.service.getDuration(), 1000);
    await e.service.resume(); e.state.now += 2000;
    const result = await e.service.stop(); assert.equal(result.durationMs, 3000);
    assert.equal(e.notices.length, 0); e.assertReleased();
  });
  await test('system-stopped M4A finalizes promptly without a duplicate native stop', async () => {
    const e = environment(); await e.service.start({}, e.config.aac(128000));
    e.state.now += 30000;
    const recorder = e.state.recorders[0]; recorder.systemTransition('stopped');
    await e.settled();
    assert.equal(e.service.getState(), e.states.STOPPED);
    assert.equal(e.saved.length, 1); assert.equal(e.saved[0].durationMs, 30000);
    assert.equal(recorder.stopCalls, 0); assert.equal(recorder.releaseCalls, 1);
    assert.equal(recorder.listeners.size, 0); e.assertReleased();
  });
  await test('system-paused M4A saves the interrupted prefix and clears its background lease', async () => {
    const e = environment(); await e.service.start({}, e.config.aac(128000)); e.state.now += 8000;
    const recorder = e.state.recorders[0]; recorder.systemTransition('paused'); await e.settled();
    assert.equal(e.saved.length, 1); assert.equal(e.saved[0].durationMs, 8000);
    assert.equal(recorder.stopCalls, 1); assert.equal(e.service.getState(), e.states.STOPPED);
    e.assertReleased();
  });
  await test('M4A error state without an error callback releases native resources without an illegal stop', async () => {
    const e = environment(); await e.service.start({}, e.config.aac(128000));
    const recorder = e.state.recorders[0]; recorder.systemTransition('error'); await e.settled();
    assert.equal(recorder.stopCalls, 0); assert.equal(recorder.releaseCalls, 1);
    assert.equal(e.service.getState(), e.states.STOPPED);
    assert.ok(e.notices.some(message => message.includes('错误状态'))); e.assertReleased();
  });
  await test('user M4A pause, resume and stop events never masquerade as a system interruption', async () => {
    const e = environment(); await e.service.start({}, e.config.aac(128000)); e.state.now += 1000;
    await e.service.pause(); await e.settled();
    assert.equal(e.saved.length, 0); assert.equal(e.service.getState(), e.states.PAUSED);
    assert.equal(e.state.bgActive, false);
    e.state.now += 60000; await e.service.resume(); e.state.now += 2000;
    const saved = await e.service.stop(); await e.settled();
    assert.equal(saved.durationMs, 3000); assert.equal(e.saved.length, 1);
    assert.equal(e.state.recorders[0].stopCalls, 1); assert.equal(e.notices.length, 0); e.assertReleased();
  });
  await test('late state and error callbacks from a released M4A cannot stop its replacement', async () => {
    const e = environment(); await e.service.start({}, e.config.aac(128000));
    const old = e.state.recorders[0];
    const lateState = old.listeners.get('stateChange'), lateError = old.listeners.get('error');
    await e.service.stop(); await e.service.start({}, e.config.aac(128000));
    lateState('stopped', 2); lateError({ code: 5400103 }); await e.settled();
    assert.equal(e.saved.length, 1); assert.equal(e.service.getState(), e.states.RECORDING);
    assert.equal(e.state.activeMic, 1); assert.equal(e.state.bgActive, true);
    assert.equal(old.listeners.size, 0); await e.service.stop(); e.assertReleased();
  });
  await test('system M4A interruption during a pending pause freezes time and defers saving safely', async () => {
    const e = environment(); await e.service.start({}, e.config.aac(128000)); e.state.now += 2000;
    e.state.m4aPausePending = new Promise(resolve => { e.state.m4aPauseResolve = resolve; });
    const pausing = e.service.pause();
    for (let pass = 0; pass < 10; pass++) await Promise.resolve();
    e.state.recorders[0].systemTransition('stopped'); e.state.now += 30000;
    assert.equal(e.service.getDuration(), 2000); assert.equal(e.saved.length, 0);
    e.state.m4aPauseResolve(); await pausing; await e.settled();
    assert.equal(e.saved.length, 1); assert.equal(e.saved[0].durationMs, 2000);
    assert.equal(e.state.recorders[0].stopCalls, 0); e.assertReleased();
  });
  await test('system cancellation received during start or pause is deferred and never lost', async () => {
    const starting = environment(); starting.state.cancelDuringStart = true;
    await starting.service.start({}, starting.config.wav()); await starting.settled();
    assert.equal(starting.saved.length, 1); starting.assertReleased();
    const pausing = environment(); await pausing.service.start({}, pausing.config.wav());
    await pausing.feed(new ArrayBuffer(9600)); pausing.state.cancelDuringPause = true;
    await pausing.service.pause(); await pausing.settled();
    assert.equal(pausing.saved.length, 1); pausing.assertReleased();
  });
  await test('FLAC bridge calls are serial and finalization failures release all resources', async () => {
    const e = environment(); await e.service.start({}, e.config.flac());
    await e.feed(new ArrayBuffer(9600)); await e.service.pause();
    await e.service.resume(); await e.feed(new ArrayBuffer(9600));
    const result = await e.service.stop();
    assert.equal(result.durationMs, 200);
    assert.deepEqual(e.state.flacCalls, ['create', 'write', 'write', 'finish', 'release']);
    e.assertReleased();
    const unsupported = environment(); unsupported.state.flacCreateFails = true;
    await assert.rejects(unsupported.service.start({}, unsupported.config.flac())); unsupported.assertReleased();
    const failed = environment(); await failed.service.start({}, failed.config.flac());
    await failed.feed(new ArrayBuffer(9600)); failed.state.flacFinishFails = true;
    await assert.rejects(failed.service.stop()); assert.equal(failed.saved.length, 0);
    assert.equal(failed.state.flacCalls[failed.state.flacCalls.length - 1], 'release'); failed.assertReleased();
  });
  await test('cleanup retries a retained capturer when its first stop and release both fail', async () => {
    const e = environment(); await e.service.start({}, e.config.wav()); await e.feed(new ArrayBuffer(9600));
    e.state.stopFailures = 1; e.state.releaseFailures = 1;
    await assert.rejects(e.service.stop());
    assert.equal(e.service.getState(), e.states.STOPPED); e.assertReleased();
  });
  console.log(`\nRecordingService host scenarios: ${passed} passed. Two-hour stream is accelerated simulation; device audio, power and codec quality are not validated here.`);
})().catch(error => { console.error(error.stack); process.exitCode = 1; });
