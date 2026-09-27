#!/usr/bin/env node
// Runs actual non-builder page methods with fake dialogs/playback/repository responses.
// Method extraction is needed because the host TypeScript compiler cannot parse ArkUI builders.
// This verifies state transitions and call ordering, not native Sheet/List rendering.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const compilerPath = process.argv[2] || process.env.FACILIS_TYPESCRIPT;
if (!compilerPath) throw new Error('Pass the DevEco TypeScript compiler path');
const ts = require(path.resolve(compilerPath));
const root = path.resolve(__dirname, '..');
const actions = { MOVE_TO_TRASH: 'move', RESTORE: 'restore', PERMANENTLY_DELETE: 'delete' };
const tokens = { textSecondary: () => 'secondary', danger: () => 'danger', primary: () => 'primary' };
function subject(page, methods, repository = {}, navigation = {}) {
  const source = fs.readFileSync(path.join(root, 'HarmonyRecorder/entry/src/main/ets/pages', page + '.ets'), 'utf8');
  const bodies = methods.map(name => {
    const expression = new RegExp('^  private (?:async )?' + name + '\\([^]*?^  }', 'm');
    const match = source.match(expression);
    assert.ok(match, 'Production method missing: ' + name);
    return match[0];
  }).join('\n');
  const output = ts.transpileModule('class Subject {\n' + bodies + '\n}', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const Subject = new Function('RecordingRepository', 'RecordingBatchAction', 'HarmonyTokens',
    'MotionTheme', 'NavigationStore', 'AppPage', '$r', output + '\nreturn Subject;')(
    { getUnreadableCount: () => 0, ...repository }, actions, tokens, { content: () => ({}) }, navigation, { RECORDINGS: 'recordings' },
    name => ({ resource: name }));
  const item = Object.assign(new Subject(), { isWorking: false, isConfirming: false, isVisible: true,
    isSelecting: false, selectedRecordingIds: [], status: '', recordings: [], recentlyDeleted: [],
    showingTrash: false, isReady: true, isPreparing: false, isScrubbing: true, seekGuardUntilMs: 100,
    pendingTrashConfirmation: page === 'PlayerPage' ? false : [], showActionSheet: true,
    showQuickActions: true, isRenaming: false, isQuickRenaming: false });
  item.getUIContext = () => ({ getHostContext: () => ({}),
    getPromptAction: () => ({ showDialog: options => item.dialog(options) }),
    animateTo: (_, commit) => { item.animationCount = (item.animationCount || 0) + 1; commit(); } });
  return item;
}
const playerMethods = ['requestMoveToTrash', 'onActionsSheetDismissed', 'confirmMoveToTrash', 'moveToTrash'];
const libraryMethods = ['confirmMoveQuickRecordingToTrash', 'onQuickActionsDismissed', 'quickActionRecording',
  'confirmBatch', 'runBatch', 'loadRecordings', 'selectedRecordings'];
const recording = id => ({ id, filePath: '/files/' + id });
function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
const settle = () => new Promise(resolve => setImmediate(resolve));
let passed = 0;
let failed = 0;
async function test(name, body) {
  try { await body(); passed++; console.log('PASS ' + name); }
  catch (error) { failed++; console.error('FAIL ' + name + ': ' + error.stack); }
}
(async () => {
  await test('player waits for Sheet dismissal and deduplicates requests', async () => {
    const page = subject('PlayerPage', playerMethods);
    const answer = deferred();
    let dialogs = 0;
    page.dialog = () => { dialogs++; return answer.promise; };
    page.requestMoveToTrash();
    page.requestMoveToTrash();
    assert.equal(dialogs, 0);
    assert.equal(page.showActionSheet, false);
    assert.equal(page.isConfirming, true);
    page.onActionsSheetDismissed();
    page.onActionsSheetDismissed();
    assert.equal(dialogs, 1);
    answer.resolve({ index: 0 });
    await settle();
    assert.equal(page.isConfirming, false);
    assert.equal(page.isWorking, false);
  });
  await test('player releases confirmation lock on synchronous and asynchronous dialog failure', async () => {
    const page = subject('PlayerPage', playerMethods);
    page.dialog = () => { throw new Error('prompt unavailable'); };
    await page.confirmMoveToTrash();
    assert.equal(page.isConfirming, false);
    page.dialog = () => Promise.reject(new Error('prompt failed'));
    await page.confirmMoveToTrash();
    assert.equal(page.isConfirming, false);
    assert.equal(page.status, '无法打开确认窗口');
  });
  await test('player closes source before moving and rejects repeated delete while waiting', async () => {
    const calls = [];
    const release = deferred();
    const page = subject('PlayerPage', playerMethods,
      { moveToRecentlyDeleted: () => calls.push('move') }, { open: () => calls.push('navigate') });
    page.playbackService = { release: () => { calls.push('release'); return release.promise; } };
    const pending = page.moveToTrash();
    await page.moveToTrash();
    assert.deepEqual(calls, ['release']);
    assert.equal(page.isWorking, true);
    assert.equal(page.isScrubbing, false);
    assert.equal(page.seekGuardUntilMs, 0);
    release.resolve();
    await pending;
    assert.deepEqual(calls, ['release', 'move', 'navigate']);
    assert.equal(page.isWorking, false);
  });
  await test('failed player delete reloads original and unlocks retry without navigating', async () => {
    const calls = [];
    const page = subject('PlayerPage', playerMethods,
      { moveToRecentlyDeleted: () => { throw new Error('transaction rolled back'); } },
      { open: () => calls.push('navigate') });
    page.playbackService = { release: async () => { calls.push('release'); page.isReady = false; } };
    page.preparePlayback = async () => { calls.push('reload'); page.isReady = true; };
    await page.moveToTrash();
    assert.deepEqual(calls, ['release', 'reload']);
    assert.equal(page.isWorking, false);
    assert.equal(page.status, '移至最近删除失败，可重试');
  });
  await test('player does not race deletion with source preparation and unlocks after load failure', async () => {
    const page = subject('PlayerPage', [...playerMethods, 'preparePlayback']);
    const loading = deferred();
    page.recording = { durationMs: 1000 };
    page.playbackService = { load: () => loading.promise };
    const pending = page.preparePlayback();
    assert.equal(page.isPreparing, true);
    page.requestMoveToTrash();
    await page.moveToTrash();
    assert.equal(page.pendingTrashConfirmation, false);
    assert.equal(page.isWorking, false);
    loading.reject(new Error('unsupported audio'));
    await pending;
    assert.equal(page.isPreparing, false);
    page.requestMoveToTrash();
    assert.equal(page.pendingTrashConfirmation, true);
  });
  await test('library snapshots quick action before Sheet clears its selection', async () => {
    const page = subject('RecordingsPage', libraryMethods);
    page.recordings = [recording('a')];
    page.quickActionRecordingId = 'a';
    let dialogs = 0;
    page.dialog = options => { dialogs++; assert.match(options.title, /1 段/); return Promise.resolve({ index: 0 }); };
    page.confirmMoveQuickRecordingToTrash();
    page.confirmMoveQuickRecordingToTrash();
    assert.equal(dialogs, 0);
    page.onQuickActionsDismissed();
    page.onQuickActionsDismissed();
    await settle();
    assert.equal(dialogs, 1);
    assert.equal(page.quickActionRecordingId, '');
    assert.equal(page.isConfirming, false);
  });
  await test('library restores multiple trash selections and confirms exact count', async () => {
    const first = recording('a');
    const second = recording('b');
    let batches = 0;
    const page = subject('RecordingsPage', libraryMethods, {
      applyBatch: (_, items, action) => { batches++; assert.deepEqual(items, [first, second]);
        assert.equal(action, actions.RESTORE); return { completedIds: ['a', 'b'], failedIds: [] }; },
      list: () => [first, second], listRecentlyDeleted: () => []
    });
    page.recentlyDeleted = [first, second];
    page.showingTrash = true;
    page.isSelecting = true;
    page.selectedRecordingIds = ['a', 'b'];
    const answer = deferred();
    page.dialog = options => { assert.equal(options.title, '恢复 2 段录音？'); return answer.promise; };
    const pending = page.confirmBatch(page.selectedRecordings(), actions.RESTORE);
    await page.confirmBatch(page.selectedRecordings(), actions.RESTORE);
    answer.resolve({ index: 1 });
    await pending;
    assert.equal(batches, 1);
    assert.equal(page.recentlyDeleted.length, 0);
    assert.equal(page.isSelecting, false);
    assert.equal(page.isWorking, false);
    assert.equal(page.isConfirming, false);
  });
  await test('library keeps failed selection and prunes confirmed successes even if refresh fails', () => {
    const page = subject('RecordingsPage', libraryMethods, {
      applyBatch: () => ({ completedIds: ['a'], failedIds: ['b'] }),
      list: () => { throw new Error('read unavailable'); }
    });
    page.showingTrash = true;
    page.recentlyDeleted = [recording('a'), recording('b')];
    page.runBatch(page.recentlyDeleted, actions.PERMANENTLY_DELETE);
    assert.deepEqual(page.recentlyDeleted.map(x => x.id), ['b']);
    assert.deepEqual(page.selectedRecordingIds, ['b']);
    assert.equal(page.isSelecting, true);
    assert.equal(page.isWorking, false);
    assert.match(page.status, /永久删除 1 段.*失败 1 段.*刷新失败/);
  });
  await test('library read failure retains snapshot and dialog failure releases lock', async () => {
    const page = subject('RecordingsPage', libraryMethods, { list: () => { throw new Error('read failed'); } });
    page.recordings = [recording('a')];
    assert.equal(page.loadRecordings(true), false);
    assert.equal(page.recordings.length, 1);
    page.dialog = () => { throw new Error('prompt failed'); };
    await page.confirmBatch(page.recordings, actions.MOVE_TO_TRASH);
    assert.equal(page.isConfirming, false);
    assert.equal(page.status, '无法打开确认窗口');
  });
  await test('library does not claim a failed item remains selected when it is no longer listed', () => {
    const page = subject('RecordingsPage', libraryMethods, {
      applyBatch: () => ({ completedIds: [], failedIds: ['a'] }),
      list: () => [], listRecentlyDeleted: () => []
    });
    page.showingTrash = true;
    page.recentlyDeleted = [recording('a')];
    page.runBatch(page.recentlyDeleted, actions.PERMANENTLY_DELETE);
    assert.equal(page.selectedRecordingIds.length, 0);
    assert.match(page.status, /失败 1 段/);
    assert.doesNotMatch(page.status, /已保留选择/);
  });
  await test('native Back or mask cancellation releases both dialog locks without reporting an error', async () => {
    const player = subject('PlayerPage', playerMethods);
    const library = subject('RecordingsPage', libraryMethods);
    library.recordings = [recording('a')];
    for (const page of [player, library]) {
      page.status = 'previous status';
      page.dialog = () => Promise.reject(new Error('cancel'));
    }
    await player.confirmMoveToTrash();
    await library.confirmBatch(library.recordings, actions.MOVE_TO_TRASH);
    for (const page of [player, library]) {
      assert.equal(page.isConfirming, false);
      assert.equal(page.isWorking, false);
      assert.equal(page.status, 'previous status');
    }
  });
  await test('HDS title menus remain mounted and disabled during selection, search and requests', () => {
    const page = subject('RecordingsPage', [...libraryMethods, 'navigationMenu', 'canUseNavigationMenu', 'enterSelectionMode']);
    page.recordings = [recording('a')];
    page.recentlyDeleted = [recording('b')];
    for (const trash of [false, true]) {
      page.showingTrash = trash;
      for (const mode of ['isSelecting', 'isSearching', 'isWorking', 'isConfirming']) {
        page[mode] = true;
        const menu = page.navigationMenu();
        assert.equal(menu.length, 2);
        assert.ok(menu.every(item => item.content.isEnabled === false));
        const before = [page.isSelecting, page.isSearching, page.showingTrash];
        menu.forEach(item => item.content.action());
        assert.deepEqual([page.isSelecting, page.isSearching, page.showingTrash], before);
        page[mode] = false;
      }
      assert.equal(page.navigationMenu().length, 2);
      assert.ok(page.navigationMenu().every(item => item.content.isEnabled === true));
    }
  });
  console.log(`Recording action checks: ${passed} passed, ${failed} failed. Native rendering remains separate.`);
  process.exitCode = failed ? 1 : 0;
})();
