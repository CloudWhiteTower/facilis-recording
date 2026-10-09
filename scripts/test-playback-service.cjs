#!/usr/bin/env node
// Executes the actual PlaybackService with controlled native-player/file fakes.
// These are lifecycle/concurrency regressions, not device decoder compatibility tests.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const compilerPath = process.argv[2] || process.env.FACILIS_TYPESCRIPT;
if (!compilerPath) throw new Error('Pass the DevEco TypeScript compiler path');
const ts = require(path.resolve(compilerPath));
const source = fs.readFileSync(path.resolve(__dirname,
  '../HarmonyRecorder/entry/src/main/ets/services/PlaybackService.ets'), 'utf8');
const output = ts.transpileModule(source, {
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
}).outputText;
function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
const settle = () => new Promise(resolve => setImmediate(resolve));
async function completes(promise) {
  let timer;
  try {
    return await Promise.race([promise, new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error('operation did not settle')), 1000);
    })]);
  } finally { clearTimeout(timer); }
}
function environment() {
  const files = new Map(), closed = [], players = [], notices = [];
  const timers = new Map();
  let timerClock = 0, nextTimer = 1;
  const setTimer = (callback, delayMs) => {
    const id = nextTimer++; timers.set(id, { callback, deadline: timerClock + delayMs }); return id;
  };
  const clearTimer = id => timers.delete(id);
  function advanceTimers(milliseconds) {
    timerClock += milliseconds;
    for (const [id, timer] of Array.from(timers.entries())) {
      if (timer.deadline <= timerClock && timers.has(id)) { timers.delete(id); timer.callback(); }
    }
  }
  const state = { nextFd: 10, factory: null, statFails: false, setterFails: false, fileSize: 16000,
    inspectionFails: false, inspectedPath: '' };
  const io = {
    OpenMode: { READ_ONLY: 0 },
    openSync(name) { const file = { fd: state.nextFd++, name }; files.set(file.fd, file); return file; },
    statSync(fd) {
      assert.ok(files.has(fd), 'stat must describe the opened source descriptor');
      if (state.statFails) throw new Error('stat failed'); return { size: state.fileSize };
    },
    closeSync(file) {
      assert.ok(files.has(file.fd), 'descriptor must close exactly once');
      files.delete(file.fd); closed.push(file.fd);
    }
  };
  function newPlayer() {
    const listeners = new Map();
    const player = {
      state: 'idle', duration: 1000, descriptor: null, prepareGate: null, releaseGate: null, playGate: null,
      prepareCalls: 0, releaseCalls: 0, playCalls: 0, pauseCalls: 0, seeks: [],
      audioRendererInfo: null, audioInterruptMode: null, volume: null, autoSeekDone: true, seekFails: false,
      on(name, fn) { listeners.set(name, fn); },
      emit(name, value) {
        if (name === 'stateChange') this.state = value;
        listeners.get(name)?.(value);
      },
      set fdSrc(value) {
        assert.ok(files.has(value.fd), 'fdSrc must never reference a closed descriptor');
        this.descriptor = value;
        if (state.setterFails) throw new Error('source rejected');
        this.emit('stateChange', 'initialized');
      },
      async prepare() { this.prepareCalls++; if (this.prepareGate) await this.prepareGate.promise; },
      async release() {
        this.releaseCalls++;
        if (this.releaseGate) await this.releaseGate.promise;
        if (this.descriptor) assert.ok(files.has(this.descriptor.fd), 'file stays open until native release finishes');
      },
      async play() { this.playCalls++; if (this.playGate) await this.playGate.promise; this.emit('stateChange', 'playing'); },
      async pause() { this.pauseCalls++; this.emit('stateChange', 'paused'); },
      setVolume(value) { this.volume = value; },
      seek(value) {
        if (this.seekFails) throw new Error('seek failed');
        this.seeks.push(value);
        if (this.autoSeekDone) queueMicrotask(() => this.emit('seekDone', value));
      }
    };
    players.push(player); return player;
  }
  const media = { SeekMode: { SEEK_PREV_SYNC: 0 },
    createAVPlayer() { return state.factory ? state.factory() : Promise.resolve(newPlayer()); } };
  const audio = {
    StreamUsage: { STREAM_USAGE_MUSIC: 1 }, InterruptMode: { INDEPENDENT_MODE: 1 },
    InterruptHint: { INTERRUPT_HINT_PAUSE: 2, INTERRUPT_HINT_STOP: 3 },
    InterruptForceType: { INTERRUPT_FORCE: 0, INTERRUPT_SHARE: 1 },
    AudioStreamDeviceChangeReason: { REASON_OLD_DEVICE_UNAVAILABLE: 2 }
  };
  const module = { exports: {} };
  new Function('require', 'module', 'exports', 'setTimeout', 'clearTimeout', output)(name => {
    if (name === '@kit.CoreFileKit') return { fileIo: io };
    if (name === '@kit.MediaKit') return { media };
    if (name === '@kit.AudioKit') return { audio };
    if (name === '@kit.BasicServicesKit') return {};
    if (name === '../repository/RecordingRepository') return { RecordingRepository: {
      inspectRecording(context, recording) {
        assert.deepEqual(context, {}, 'source inspection receives the caller context');
        if (state.inspectionFails) throw new Error('WAV 数据块不完整');
        return { ...recording, filePath: state.inspectedPath || recording.filePath };
      }
    } };
    throw new Error('Unexpected import ' + name);
  }, module, module.exports, setTimer, clearTimer);
  const service = new module.exports.PlaybackService();
  service.setObserver((ready, playing, position, duration, message) => {
    notices.push({ ready, playing, position, duration, message });
  });
  const recording = name => ({ filePath: '/files/' + name });
  async function ready(name = 'recording') {
    const pending = service.load(recording(name), {});
    await settle();
    const player = players.at(-1);
    player.emit('stateChange', 'prepared');
    await completes(pending);
    return player;
  }
  return { service, state, files, closed, players, notices, newPlayer, recording, ready, timers, advanceTimers };
}
function playerPage() {
  // Builders require ArkUI. Extract only the actual lifecycle/control methods
  // so a browser/Node UI imitation cannot hide page-side message regressions.
  const source = fs.readFileSync(path.resolve(__dirname,
    '../HarmonyRecorder/entry/src/main/ets/pages/PlayerPage.ets'), 'utf8');
  const names = ['aboutToAppear', 'onSeekChange', 'preparePlayback', 'togglePlayback'];
  const bodies = names.map(name => {
    const match = source.match(new RegExp('^  (?:private )?(?:async )?' + name + '\\([^]*?^  }', 'm'));
    assert.ok(match, 'Production page method missing: ' + name); return match[0];
  }).join('\n');
  const output = ts.transpileModule('class Subject {\n' + bodies + '\n}', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const selection = { filePath: '', durationMs: 1000, displayName: 'test' }, selected = [];
  const modes = { Begin: 0, Moving: 1, End: 2, Click: 3 };
  const Subject = new Function('RecordingSelectionStore', 'MotionTheme', 'SliderChangeMode',
    output + '\nreturn Subject;')({ getSelected: () => selection, select: value => selected.push(value) },
    { state: () => ({}) }, modes);
  const page = Object.assign(new Subject(), { isReady: false, isPlaying: false, positionMs: 0, durationMs: 0,
    status: '', displayName: '', isWorking: false, isConfirming: false, isPreparing: false,
    isScrubbing: false, seekGuardUntilMs: 0, seekTargetMs: 0, seeks: [] });
  page.getUIContext = () => ({ getHostContext: () => ({}), animateTo: (_, commit) => commit() });
  page.playbackService = {
    setObserver(observer) { page.observer = observer; observer(false, false, 0, 0, ''); },
    seek(value) { page.seeks.push(value); return Promise.resolve(true); },
    async load(recording) { return recording; }, async toggle() {}
  };
  page.aboutToAppear(); return { page, selected, modes };
}
let passed = 0, failed = 0;
async function test(name, body) {
  try { await body(); passed++; console.log('PASS ' + name); }
  catch (error) { failed++; console.error('FAIL ' + name + ': ' + error.stack); }
}
(async () => {
  await test('stalled playback control settles at its deadline and late native success stays detached', async () => {
    const e = environment(), old = await e.ready(), gate = deferred(); old.playGate = gate;
    const pending = e.service.toggle(); await settle(); e.advanceTimers(8000); await completes(pending);
    assert.equal(e.notices.at(-1).ready, false); assert.match(e.notices.at(-1).message, /播放控制超时/);
    const current = await e.ready('retry'); gate.resolve(); await settle();
    assert.equal(e.notices.at(-1).playing, false); await e.service.toggle(); assert.equal(current.playCalls, 1);
    await e.service.release(); assert.equal(e.files.size, 0); assert.equal(e.timers.size, 0);
  });
  await test('observer failures do not prevent playback or descriptor cleanup', async () => {
    const e = environment(); e.service.setObserver(() => { throw new Error('detached observer'); });
    await e.ready(); await e.service.toggle(); await e.service.release(); assert.equal(e.files.size, 0);
  });
  await test('normal preparation, playback, bounded seeking and replay remain functional', async () => {
    const e = environment(), player = await e.ready();
    assert.equal(player.prepareCalls, 1);
    assert.deepEqual(e.notices.at(-1), { ready: true, playing: false, position: 0, duration: 1000, message: '' });
    await e.service.toggle(); assert.equal(e.notices.at(-1).playing, true);
    await e.service.toggle(); assert.equal(player.pauseCalls, 1);
    await e.service.seek(1500); await e.service.seek(-3); assert.deepEqual(player.seeks, [1000, 0]);
    player.emit('timeUpdate', 320); assert.equal(e.notices.at(-1).position, 320);
    player.emit('durationUpdate', 2000); player.emit('stateChange', 'completed');
    assert.equal(e.notices.at(-1).position, 2000);
    await e.service.toggle(); assert.equal(player.seeks.at(-1), 0);
    await e.service.release(); assert.equal(e.files.size, 0); assert.equal(player.releaseCalls, 1);
  });
  await test('immediate exit cancels load before opening its source', async () => {
    const e = environment();
    const loading = e.service.load(e.recording('early'), {});
    await completes(e.service.release()); await completes(loading);
    assert.equal(e.players.length, 0); assert.equal(e.files.size, 0); assert.equal(e.closed.length, 0);
  });
  await test('exit during asynchronous factory disposes late player without assigning a closed fd', async () => {
    const e = environment(), factory = deferred(); e.state.factory = () => factory.promise;
    const loading = e.service.load(e.recording('late'), {}); await settle();
    assert.equal(e.files.size, 1);
    await e.service.release(); assert.equal(e.files.size, 0);
    const count = e.notices.length, player = e.newPlayer(); factory.resolve(player);
    await completes(loading);
    await settle();
    assert.equal(player.releaseCalls, 1); assert.equal(player.descriptor, null);
    assert.equal(e.notices.length, count);
  });
  await test('exit during preparation settles load and ignores every late native event', async () => {
    const e = environment(); const loading = e.service.load(e.recording('preparing'), {}); await settle();
    const player = e.players[0]; assert.equal(player.prepareCalls, 1);
    await e.service.release(); await completes(loading);
    const count = e.notices.length;
    player.emit('stateChange', 'initialized'); player.emit('stateChange', 'prepared');
    player.emit('stateChange', 'playing'); player.emit('timeUpdate', 900); player.emit('durationUpdate', 9999);
    player.emit('error', { code: 5400103 }); await settle();
    assert.equal(e.notices.length, count); assert.equal(player.prepareCalls, 1); assert.equal(e.files.size, 0);
  });
  await test('older factory completion cannot release or overwrite a newer prepared load', async () => {
    const e = environment(), factory = deferred(); e.state.factory = () => factory.promise;
    const first = e.service.load(e.recording('first'), {}); await settle();
    e.state.factory = null; const current = await e.ready('second');
    const count = e.notices.length, obsolete = e.newPlayer(); factory.resolve(obsolete);
    await completes(first);
    await settle();
    assert.equal(obsolete.releaseCalls, 1); assert.equal(obsolete.descriptor, null);
    assert.equal(current.releaseCalls, 0); assert.equal(e.files.size, 1); assert.equal(e.notices.length, count);
    await e.service.toggle(); assert.equal(current.playCalls, 1); await e.service.release();
  });
  await test('older factory failure cannot clear a newer successful load', async () => {
    const e = environment(), factory = deferred(); e.state.factory = () => factory.promise;
    const first = e.service.load(e.recording('first'), {}); await settle();
    e.state.factory = null; const current = await e.ready('second');
    const count = e.notices.length; factory.reject(new Error('old factory failure')); await completes(first);
    assert.equal(current.releaseCalls, 0); assert.equal(e.files.size, 1); assert.equal(e.notices.length, count);
    await e.service.release();
  });
  await test('late prepare rejection cannot mark the replacement as failed', async () => {
    const e = environment(), prepare = deferred(), old = e.newPlayer();
    old.prepareGate = prepare; e.state.factory = () => Promise.resolve(old);
    const first = e.service.load(e.recording('first'), {}); await settle();
    e.state.factory = null; const current = await e.ready('second'); await completes(first);
    const count = e.notices.length; prepare.reject(new Error('released while preparing')); await settle();
    old.emit('stateChange', 'initialized'); old.emit('stateChange', 'prepared'); old.emit('error', { code: 1 });
    assert.equal(e.notices.length, count); assert.equal(current.prepareCalls, 1); assert.equal(e.files.size, 1);
    await e.service.release();
  });
  await test('duplicate release waits for native cleanup and keeps the descriptor alive until completion', async () => {
    const e = environment(), old = await e.ready('first'), gate = deferred(); old.releaseGate = gate;
    const a = e.service.release(), b = e.service.release(); await settle();
    const second = e.service.load(e.recording('second'), {}); await settle();
    assert.equal(old.releaseCalls, 1); assert.equal(e.files.size, 1); assert.equal(e.players.length, 1);
    gate.resolve(); await completes(a); await completes(b); await settle();
    const current = e.players.at(-1); assert.notEqual(current, old);
    current.emit('stateChange', 'prepared'); await completes(second);
    assert.equal(e.files.size, 1); assert.deepEqual(e.closed, [old.descriptor.fd]);
    await e.service.release(); assert.equal(e.closed.length, 2);
  });
  await test('release during replacement cleanup prevents its deferred file open', async () => {
    const e = environment(), old = await e.ready('first'), gate = deferred(); old.releaseGate = gate;
    const replacement = e.service.load(e.recording('second'), {}); await settle();
    const exit = e.service.release(); gate.resolve(); await completes(exit); await completes(replacement);
    assert.equal(e.players.length, 1); assert.equal(e.closed.length, 1); assert.equal(e.files.size, 0);
  });
  await test('current factory error closes source and reports opening failure', async () => {
    const e = environment(); e.state.factory = () => Promise.reject(new Error('factory failed'));
    await assert.rejects(e.service.load(e.recording('bad'), {}), /无法打开录音.*factory failed/);
    assert.equal(e.files.size, 0); assert.equal(e.closed.length, 1); assert.match(e.notices.at(-1).message, /无法打开录音/);
  });
  await test('current prepare error releases native player and its source', async () => {
    const e = environment(), gate = deferred(), player = e.newPlayer();
    player.prepareGate = gate; e.state.factory = () => Promise.resolve(player);
    const loading = e.service.load(e.recording('bad'), {});
    const rejected = assert.rejects(loading, /无法打开录音.*prepare failed/);
    await settle(); gate.reject(new Error('prepare failed')); await rejected;
    assert.equal(player.releaseCalls, 1); assert.equal(e.files.size, 0);
  });
  await test('stat and descriptor assignment failures release precisely their own resources', async () => {
    const e = environment(); e.state.statFails = true;
    await assert.rejects(e.service.load(e.recording('bad-stat'), {}), /stat failed/);
    assert.equal(e.files.size, 0); assert.equal(e.players.length, 0);
    e.state.statFails = false; e.state.setterFails = true;
    await assert.rejects(e.service.load(e.recording('bad-source'), {}), /source rejected/);
    assert.equal(e.files.size, 0); assert.equal(e.players[0].releaseCalls, 1); assert.equal(e.closed.length, 2);
  });
  await test('late playback control failure does not surface on a replacement load', async () => {
    const e = environment(), old = await e.ready('first'), gate = deferred(); old.playGate = gate;
    const playing = e.service.toggle(); const current = await e.ready('second');
    const count = e.notices.length; gate.reject(new Error('old play cancelled')); await completes(playing);
    assert.equal(e.notices.length, count); assert.equal(current.releaseCalls, 0); await e.service.release();
  });
  await test('media renderer is configured before preparation and independent focus before playing', async () => {
    const e = environment(), player = e.newPlayer();
    player.prepare = async () => { assert.deepEqual(player.audioRendererInfo, { usage: 1, rendererFlags: 0 }); };
    player.play = async () => {
      assert.equal(player.audioInterruptMode, 1); assert.equal(player.volume, 1);
      player.emit('stateChange', 'playing');
    };
    e.state.factory = () => Promise.resolve(player);
    await e.ready(); await e.service.toggle(); await e.service.release();
  });
  await test('runtime error clears readiness, closes resources and persists the native error code', async () => {
    const e = environment(), player = await e.ready(); await e.service.toggle();
    player.emit('stateChange', 'error'); player.emit('error', { code: 5400103, message: 'decode rejected' });
    const error = e.notices.at(-1);
    assert.equal(error.ready, false); assert.equal(error.playing, false); assert.match(error.message, /5400103.*|decode rejected/);
    assert.match(error.message, /decode rejected/); assert.match(error.message, /5400103/);
    player.emit('timeUpdate', 300); player.emit('durationUpdate', 1000); player.emit('stateChange', 'paused');
    assert.deepEqual(e.notices.at(-1), error);
    await settle(); assert.equal(e.files.size, 0); assert.equal(player.releaseCalls, 1);
    const next = await e.ready('retry'); assert.equal(e.notices.at(-1).message, '');
    await e.service.release(); assert.equal(next.releaseCalls, 1);
  });
  await test('empty files fail before creating a native decoder', async () => {
    const e = environment(); e.state.fileSize = 0;
    await assert.rejects(e.service.load(e.recording('empty'), {}), /录音文件为空/);
    assert.equal(e.players.length, 0); assert.equal(e.files.size, 0);
  });
  await test('continuous seeks keep the newest preview and wait for native completion', async () => {
    const e = environment(), player = await e.ready(); player.autoSeekDone = false;
    const first = e.service.seek(200), second = e.service.seek(400), last = e.service.seek(700);
    assert.deepEqual(player.seeks, [200]); assert.equal(e.notices.at(-1).position, 700);
    player.emit('timeUpdate', 50); assert.equal(e.notices.at(-1).position, 700);
    player.emit('seekDone', 200); assert.deepEqual(player.seeks, [200, 700]);
    assert.equal(e.notices.at(-1).position, 700);
    player.emit('timeUpdate', 220); assert.equal(e.notices.at(-1).position, 700);
    player.emit('seekDone', 690);
    assert.deepEqual(await Promise.all([first, second, last]), [true, true, true]);
    assert.equal(e.notices.at(-1).position, 690);
    player.emit('timeUpdate', 720); assert.equal(e.notices.at(-1).position, 720);
    await e.service.release();
  });
  await test('completed replay waits for seekDone and repeated play clicks cannot overlap', async () => {
    const e = environment(), player = await e.ready(); player.autoSeekDone = false;
    player.emit('stateChange', 'completed'); const replay = e.service.toggle();
    await e.service.toggle(); assert.equal(player.playCalls, 0); assert.deepEqual(player.seeks, [0]);
    player.emit('seekDone', 0); await completes(replay); assert.equal(player.playCalls, 1);
    await e.service.release();
  });
  await test('cancellation settles pending seeks and replay without starting a released player', async () => {
    const e = environment(), player = await e.ready(); player.autoSeekDone = false;
    player.emit('stateChange', 'completed'); const replay = e.service.toggle();
    const seeking = e.service.seek(100); await e.service.release();
    assert.equal(await completes(seeking), false); await completes(replay); assert.equal(player.playCalls, 0);
    player.emit('seekDone', 0); assert.equal(e.notices.at(-1).ready, false);
  });
  await test('seek failures persist across ticks and prevent a false completed replay', async () => {
    const e = environment(), player = await e.ready(); player.seekFails = true;
    player.emit('stateChange', 'completed'); await e.service.toggle(); assert.equal(player.playCalls, 0);
    assert.match(e.notices.at(-1).message, /seek failed/);
    player.emit('timeUpdate', 30); assert.match(e.notices.at(-1).message, /seek failed/);
    assert.equal(await e.service.seek(NaN), false); await e.service.release();
  });
  await test('shared focus interruption pauses and is not erased by later progress updates', async () => {
    const e = environment(), player = await e.ready(); await e.service.toggle();
    player.emit('audioInterrupt', { hintType: 2, forceType: 1 }); await settle();
    assert.equal(player.pauseCalls, 1); assert.equal(e.notices.at(-1).playing, false);
    player.emit('timeUpdate', 100); assert.match(e.notices.at(-1).message, /其他音频打断/);
    await e.service.toggle(); assert.equal(e.notices.at(-1).message, ''); await e.service.release();
  });
  await test('output disconnection pauses without forcing a speaker route', async () => {
    const e = environment(), player = await e.ready(); await e.service.toggle();
    player.emit('audioOutputDeviceChangeWithInfo', { changeReason: 2, devices: [] }); await settle();
    assert.equal(player.pauseCalls, 1); assert.equal(e.notices.at(-1).playing, false);
    assert.match(e.notices.at(-1).message, /输出设备已断开/); await e.service.release();
  });
  await test('invalid source inspection fails before opening a file or creating a decoder', async () => {
    const e = environment(); e.state.inspectionFails = true;
    await assert.rejects(e.service.load(e.recording('incomplete'), {}), /WAV 数据块不完整/);
    assert.equal(e.files.size, 0); assert.equal(e.closed.length, 0); assert.equal(e.players.length, 0);
    assert.match(e.notices.at(-1).message, /WAV 数据块不完整/);
  });
  await test('load returns inspected metadata and opens precisely the inspected source', async () => {
    const e = environment(); e.state.inspectedPath = '/files/inspected.wav';
    const pending = e.service.load(e.recording('stale'), {}); await settle();
    const player = e.players[0];
    assert.equal(e.files.get(player.descriptor.fd).name, e.state.inspectedPath);
    player.emit('stateChange', 'prepared');
    assert.equal((await completes(pending)).filePath, e.state.inspectedPath);
    await e.service.release();
  });
  await test('page preserves detailed opening and control errors across normal progress callbacks', async () => {
    const { page } = playerPage(); page.recording = { filePath: '/files/take.wav', durationMs: 1000 };
    page.playbackService.load = async () => { throw new Error('WAV 数据块不完整（错误码 5400103）'); };
    await page.preparePlayback(); assert.equal(page.isPreparing, false);
    assert.match(page.status, /数据块不完整.*5400103/);
    page.observer(true, false, 20, 1000, ''); assert.match(page.status, /数据块不完整/);
    page.playbackService.toggle = async () => { throw new Error('播放焦点申请失败（错误码 5400102）'); };
    await page.togglePlayback(); assert.match(page.status, /焦点申请失败.*5400102/);
    page.observer(true, false, 30, 1000, ''); assert.match(page.status, /焦点申请失败/);
  });
  await test('page drag preview survives repeated notices and commits only once per gesture', () => {
    const { page, modes } = playerPage(); page.observer(true, false, 0, 1000, '播放已被其他音频打断');
    page.onSeekChange(200, modes.Begin); page.onSeekChange(650, modes.Moving);
    page.observer(true, false, 10, 1000, '播放已被其他音频打断');
    assert.equal(page.isScrubbing, true); assert.equal(page.positionMs, 650); assert.deepEqual(page.seeks, []);
    page.onSeekChange(700, modes.End); page.onSeekChange(700, modes.End);
    assert.deepEqual(page.seeks, [700]); assert.equal(page.isScrubbing, false); assert.equal(page.status, '');
    page.onSeekChange(NaN, modes.Click); assert.equal(page.positionMs, 700); assert.deepEqual(page.seeks, [700]);
  });
  await test('page adopts inspected metadata and passes the host context into loading', async () => {
    const { page, selected } = playerPage();
    page.recording = { filePath: '/files/take.wav', durationMs: 9999, displayName: 'stale' };
    const inspected = { ...page.recording, durationMs: 1000, displayName: 'inspected', sizeBytes: 96044 };
    page.playbackService.load = async (recording, context) => {
      assert.equal(recording.filePath, inspected.filePath); assert.deepEqual(context, {}); return inspected;
    };
    await page.preparePlayback(); assert.equal(page.recording, inspected);
    assert.equal(page.displayName, 'inspected'); assert.deepEqual(selected, [inspected]);
    assert.equal(page.isPreparing, false);
  });
  await test('factory timeout settles promptly and a late result cannot touch a replacement descriptor', async () => {
    const e = environment(), factory = deferred(); e.state.factory = () => factory.promise;
    const loading = e.service.load(e.recording('factory-hang'), {});
    const rejected = assert.rejects(loading, /准备超时/);
    let settled = false; loading.then(() => { settled = true; }, () => { settled = true; });
    await settle(); assert.equal(e.files.size, 1);
    e.advanceTimers(14999); await settle(); assert.equal(settled, false);
    e.advanceTimers(1); await completes(rejected);
    assert.equal(settled, true); assert.equal(e.files.size, 0); assert.equal(e.timers.size, 0);
    e.state.factory = null; const current = await e.ready('replacement');
    const count = e.notices.length, late = e.newPlayer(); factory.resolve(late); await settle();
    assert.equal(late.releaseCalls, 1); assert.equal(late.descriptor, null);
    assert.equal(current.releaseCalls, 0); assert.equal(e.files.size, 1); assert.equal(e.notices.length, count);
    await e.service.release();
  });
  await test('late factory rejection after timeout is consumed without replacing the visible error', async () => {
    const e = environment(), factory = deferred(); e.state.factory = () => factory.promise;
    const rejected = assert.rejects(e.service.load(e.recording('late-failure'), {}), /准备超时/);
    await settle(); e.advanceTimers(15000); await completes(rejected);
    const count = e.notices.length; factory.reject(new Error('late native factory error')); await settle();
    assert.equal(e.notices.length, count); assert.match(e.notices.at(-1).message, /准备超时/);
    assert.equal(e.timers.size, 0); assert.equal(e.files.size, 0);
  });
  await test('prepare timeout detaches callbacks immediately but keeps the fd until native release completes', async () => {
    const e = environment(), release = deferred();
    const rejected = assert.rejects(e.service.load(e.recording('prepare-hang'), {}), /准备超时/);
    await settle(); const player = e.players[0]; player.releaseGate = release;
    e.advanceTimers(15000); await settle();
    assert.equal(player.releaseCalls, 1); assert.equal(e.files.size, 1); assert.equal(e.notices.at(-1).ready, false);
    const count = e.notices.length; player.emit('stateChange', 'prepared'); player.emit('timeUpdate', 500);
    assert.equal(e.notices.length, count);
    release.resolve(); await completes(rejected);
    assert.equal(e.files.size, 0); assert.equal(e.timers.size, 0); assert.match(e.notices.at(-1).message, /准备超时/);
  });
  await test('successful prepare clears its deadline and obsolete timer callbacks cannot cancel another load', async () => {
    const e = environment(); const loading = e.service.load(e.recording('first'), {}); await settle();
    const obsolete = Array.from(e.timers.values())[0].callback;
    e.players[0].emit('stateChange', 'prepared'); await completes(loading); assert.equal(e.timers.size, 0);
    obsolete(); assert.equal(e.notices.at(-1).ready, true);
    const replacement = await e.ready('second'), count = e.notices.length;
    obsolete(); assert.equal(e.notices.length, count); assert.equal(replacement.releaseCalls, 0);
    await e.service.release(); assert.equal(e.timers.size, 0);
  });
  await test('cancelling a pending factory settles load and invalidates its already queued timeout callback', async () => {
    const e = environment(), factory = deferred(); e.state.factory = () => factory.promise;
    const loading = e.service.load(e.recording('cancel-factory'), {}); await settle();
    const obsolete = Array.from(e.timers.values())[0].callback;
    await e.service.release(); assert.equal(await completes(loading), undefined); assert.equal(e.timers.size, 0);
    const count = e.notices.length; obsolete(); assert.equal(e.notices.length, count);
    const late = e.newPlayer(); factory.resolve(late); await settle();
    assert.equal(late.releaseCalls, 1); assert.equal(late.descriptor, null); assert.equal(e.files.size, 0);
  });
  await test('seek timeout settles all waiting requests and reload isolates late events before retry', async () => {
    const e = environment(), old = await e.ready(); old.autoSeekDone = false;
    const first = e.service.seek(200), latest = e.service.seek(700);
    const obsolete = Array.from(e.timers.values())[0].callback;
    e.advanceTimers(8000); assert.deepEqual(await Promise.all([first, latest]), [false, false]); await settle();
    assert.equal(e.notices.at(-1).ready, false); assert.match(e.notices.at(-1).message, /跳转播放超时/);
    assert.equal(e.files.size, 0); assert.equal(e.timers.size, 0);
    const current = await e.ready('retry'); current.autoSeekDone = false;
    const retried = e.service.seek(600), count = e.notices.length;
    obsolete(); old.emit('seekDone', 200); assert.equal(e.notices.length, count);
    assert.equal(current.releaseCalls, 0); assert.equal(e.timers.size, 1);
    current.emit('seekDone', 600); assert.equal(await completes(retried), true); assert.equal(e.timers.size, 0);
    await e.service.release();
  });
  await test('queued seek replaces its deadline and a completed seek leaves no timer behind', async () => {
    const e = environment(), player = await e.ready(); player.autoSeekDone = false;
    const first = e.service.seek(200), next = e.service.seek(700);
    const obsolete = Array.from(e.timers.values())[0].callback;
    e.advanceTimers(4000); player.emit('seekDone', 200);
    e.advanceTimers(4000); obsolete(); assert.equal(e.notices.at(-1).ready, true); assert.equal(e.timers.size, 1);
    player.emit('seekDone', 700); assert.deepEqual(await Promise.all([first, next]), [true, true]);
    assert.equal(e.timers.size, 0); obsolete(); assert.equal(e.notices.at(-1).ready, true);
    const cancelled = e.service.seek(100), cancelledTimer = Array.from(e.timers.values())[0].callback;
    await e.service.release(); assert.equal(await completes(cancelled), false); assert.equal(e.timers.size, 0);
    const count = e.notices.length; cancelledTimer(); assert.equal(e.notices.length, count);
  });
  await test('completed replay cannot retain the control lock after a seek timeout', async () => {
    const e = environment(), player = await e.ready(); player.autoSeekDone = false;
    player.emit('stateChange', 'completed'); const replay = e.service.toggle();
    e.advanceTimers(8000); await completes(replay); await settle();
    assert.equal(player.playCalls, 0); assert.match(e.notices.at(-1).message, /跳转播放超时/);
    const retry = await e.ready('retry'); await e.service.toggle(); assert.equal(retry.playCalls, 1);
    await e.service.release(); assert.equal(e.timers.size, 0);
  });
  console.log(`Playback service host tests: ${passed} passed, ${failed} failed`);
  if (failed) process.exitCode = 1;
})().catch(error => { console.error(error); process.exitCode = 1; });
