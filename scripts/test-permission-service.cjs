#!/usr/bin/env node
// Permission flow checks use the real service and a fake system permission
// manager. They verify when a declined request may lead to a settings prompt.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const compilerPath = process.argv[2] || process.env.FACILIS_TYPESCRIPT;
if (!compilerPath) throw new Error('Pass the DevEco TypeScript compiler path');
const ts = require(path.resolve(compilerPath));
const source = path.resolve(__dirname, '../HarmonyRecorder/entry/src/main/ets/services/PermissionService.ets');

function environment(options = {}) {
  const calls = [];
  const manager = {
    getSelfPermissionStatus(permission) {
      calls.push(['status', permission]);
      if (options.statusError) throw options.statusError;
      return options.granted ? 0 : -1;
    },
    async requestPermissionsFromUser(context, permissions) {
      calls.push(['request', context, permissions]);
      if (options.requestError) throw options.requestError;
      return options.request ?? { authResults: [-1], dialogShownResults: [true] };
    },
    async requestPermissionOnSetting(context, permissions) {
      calls.push(['settings', context, permissions]);
      if (options.settingsError) throw options.settingsError;
      return options.settings ?? [0];
    }
  };
  const module = { exports: {} };
  const compiled = ts.transpileModule(fs.readFileSync(source, 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  }).outputText;
  new Function('require', 'module', 'exports', 'console', compiled)(name => {
    assert.equal(name, '@kit.AbilityKit');
    return { abilityAccessCtrl: { createAtManager: () => manager, PermissionStatus: { GRANTED: 0, DENIED: -1 },
      GrantStatus: { PERMISSION_GRANTED: 0, PERMISSION_DENIED: -1 } } };
  }, module, module.exports, { error() {} });
  return { service: module.exports.PermissionService, calls, context: { tag: 'own-ui-context' } };
}

let passed = 0;
async function check(name, action) {
  await action();
  passed++;
  process.stdout.write(`PASS ${name}\n`);
}

(async () => {
  await check('granted recording permission does not open any prompt', async () => {
    const e = environment({ granted: true });
    assert.equal(await e.service.ensureMicrophonePermission(e.context), true);
    assert.deepEqual(e.calls.map(call => call[0]), ['status']);
  });
  await check('ordinary grant requests only microphone in the owning context', async () => {
    const e = environment({ request: { authResults: [0], dialogShownResults: [true] } });
    assert.equal(await e.service.ensureMicrophonePermission(e.context), true);
    assert.deepEqual(e.calls[1], ['request', e.context, ['ohos.permission.MICROPHONE']]);
  });
  await check('ordinary denial never automatically opens a second settings prompt', async () => {
    const e = environment({ request: { authResults: [-1], dialogShownResults: [false] } });
    assert.equal(await e.service.ensureMicrophonePermission(e.context), false);
    assert.deepEqual(e.calls.map(call => call[0]), ['status', 'request']);
  });
  await check('ordinary permission failure prevents recording', async () => {
    const e = environment({ requestError: new Error('system dialog unavailable') });
    assert.equal(await e.service.ensureMicrophonePermission(e.context), false);
  });
  await check('settings action recognises permission already granted', async () => {
    const e = environment({ granted: true });
    assert.equal(await e.service.requestMicrophonePermissionSettings(e.context), true);
    assert.deepEqual(e.calls.map(call => call[0]), ['status']);
  });
  await check('first settings action can grant through the normal permission dialog', async () => {
    const e = environment({ request: { authResults: [0], dialogShownResults: [true] } });
    assert.equal(await e.service.requestMicrophonePermissionSettings(e.context), true);
    assert.deepEqual(e.calls.map(call => call[0]), ['status', 'request']);
  });
  await check('declining a visible dialog ends the explicit action without another prompt', async () => {
    const e = environment();
    assert.equal(await e.service.requestMicrophonePermissionSettings(e.context), false);
    assert.deepEqual(e.calls.map(call => call[0]), ['status', 'request']);
  });
  await check('previously denied permission can be granted through official settings prompt', async () => {
    const e = environment({ request: { authResults: [-1], dialogShownResults: [false] } });
    assert.equal(await e.service.requestMicrophonePermissionSettings(e.context), true);
    assert.deepEqual(e.calls[2], ['settings', e.context, ['ohos.permission.MICROPHONE']]);
  });
  await check('settings prompt denial leaves permission disabled', async () => {
    const e = environment({ request: { authResults: [-1], dialogShownResults: [false] }, settings: [-1] });
    assert.equal(await e.service.requestMicrophonePermissionSettings(e.context), false);
  });
  await check('missing visibility information does not risk a repeated prompt', async () => {
    for (const request of [{ authResults: [-1] }, { authResults: [-1], dialogShownResults: [] }]) {
      const e = environment({ request });
      assert.equal(await e.service.requestMicrophonePermissionSettings(e.context), false);
      assert.deepEqual(e.calls.map(call => call[0]), ['status', 'request']);
    }
  });
  await check('settings failure is propagated for accurate manual settings guidance', async () => {
    const e = environment({ request: { authResults: [-1], dialogShownResults: [false] }, settingsError: new Error('settings unavailable') });
    await assert.rejects(e.service.requestMicrophonePermissionSettings(e.context), /settings unavailable/);
  });
  await check('empty settings response is not claimed as an authorisation', async () => {
    const e = environment({ request: { authResults: [], dialogShownResults: [false] }, settings: [] });
    assert.equal(await e.service.requestMicrophonePermissionSettings(e.context), false);
  });
  process.stdout.write(`PermissionService: ${passed}/${passed} passed\n`);
})().catch(error => { console.error(error); process.exitCode = 1; });
