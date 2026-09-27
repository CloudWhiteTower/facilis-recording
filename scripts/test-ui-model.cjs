#!/usr/bin/env node
// Runs the same synchronous Hypium model tests on a host. This is NOT an
// ArkUI runtime, rendering, microphone, or real-device capability test.
// Pass the path to the TypeScript compiler bundled with DevEco Studio.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const compilerPath = process.argv[2] || process.env.FACILIS_TYPESCRIPT;
if (!compilerPath) throw new Error('Pass a path to DevEco tools/ohpm/node_modules/typescript/lib/typescript.js');
const ts = require(path.resolve(compilerPath));
const root = path.resolve(__dirname, '..');
const cache = new Map();
let passed = 0;
let failed = 0;
const hypium = {
  describe: (name, body) => { console.log(`\n${name}`); body(); },
  it: (name, flags, body) => {
    try {
      const result = body();
      assert.ok(!result || typeof result.then !== 'function', 'Async tests require the device runner');
      passed++;
      console.log(`  PASS ${name}`);
    } catch (error) { failed++; console.error(`  FAIL ${name}: ${error.message}`); }
  },
  expect: actual => ({
    assertEqual: expected => assert.equal(actual, expected),
    assertTrue: () => assert.equal(actual, true),
    assertFalse: () => assert.equal(actual, false)
  })
};
// Enum values mirror the installed HDS API declarations, not device support.
const hdsMaterial = {
  MaterialType: { NONE: 0, ADAPTIVE: 100, IMMERSIVE: 101 },
  MaterialLevel: { EXQUISITE: 0, GENTLE: 1, SMOOTH: 2, ADAPTIVE: 10 },
  getSystemMaterialTypes: () => { throw new Error('Host tests cannot query a device'); }
};
function load(filename) {
  const file = path.resolve(filename);
  assert.ok(file.startsWith(root + path.sep), 'Only this repository can be loaded');
  if (cache.has(file)) return cache.get(file).exports;
  const module = { exports: {} };
  cache.set(file, module);
  const source = fs.readFileSync(file, 'utf8');
  const output = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const localRequire = name => {
    if (name === '@ohos/hypium') return hypium;
    if (name === '@kit.UIDesignKit') return { hdsMaterial };
    if (name === '@kit.BasicServicesKit') return {};
    if (name === '@kit.ArkTS') return { util: { TextEncoder } };
    if (name === '@kit.AbilityKit' || name === '@kit.ArkUI' || name === '@kit.CoreFileKit') return {};
    if (name.startsWith('.')) return load(path.resolve(path.dirname(file), name + '.ets'));
    throw new Error(`Unsupported host import: ${name}`);
  };
  new Function('require', 'exports', 'module', '$r', output)(localRequire, module.exports, module,
    name => ({ resource: name }));
  return module.exports;
}
load(path.join(root, 'HarmonyRecorder/entry/src/test/List.test.ets')).default();

hypium.describe('semantic resource parity', () => {
  const readColors = mode => JSON.parse(fs.readFileSync(path.join(root,
    `HarmonyRecorder/entry/src/main/resources/${mode}/element/color.json`), 'utf8')).color;
  const light = readColors('base');
  const dark = readColors('dark');
  hypium.it('every light token has a valid dark counterpart', 0, () => {
    assert.deepEqual(light.map(x => x.name).sort(), dark.map(x => x.name).sort());
    for (const mode of [light, dark]) {
      assert.equal(new Set(mode.map(x => x.name)).size, mode.length);
      for (const color of mode) assert.match(color.value, /^#(?:[0-9a-f]{6}|[0-9a-f]{8})$/i);
    }
  });
  hypium.it('brand orange and page background match the Canvas/window palette', 0, () => {
    const { HarmonyTheme, ThemeMode } = load(path.join(root, 'HarmonyRecorder/entry/src/main/ets/utils/HarmonyTheme.ets'));
    for (const [colors, mode] of [[light, ThemeMode.LIGHT], [dark, ThemeMode.DARK]]) {
      const normalize = color => color.length === 9 ? '#' + color.slice(3) : color;
      assert.equal(normalize(colors.find(c => c.name === 'primary').value), HarmonyTheme.palette(mode).primary);
      assert.equal(normalize(colors.find(c => c.name === 'page_background').value), HarmonyTheme.palette(mode).pageBackground);
    }
  });
});
console.log(`\nHost model tests: ${passed} passed, ${failed} failed. Device rendering/audio remain unverified.`);
process.exitCode = failed ? 1 : 0;
