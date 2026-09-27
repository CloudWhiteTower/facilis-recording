#!/usr/bin/env node
// Read-only inspection with the production ArkTS container parser and Node file descriptors.
// Usage: node scripts/inspect-audio-files.cjs <DevEco typescript.js> <audio-file> [...]
// Or set FACILIS_TYPESCRIPT and pass only the audio paths. This is metadata inspection, not decoding.
const fs = require('node:fs');
const path = require('node:path');
let paths = process.argv.slice(2);
const compilerPath = paths[0]?.endsWith('typescript.js') ? paths.shift() : process.env.FACILIS_TYPESCRIPT;
if (!compilerPath || paths.length === 0) {
  console.error('Usage: node scripts/inspect-audio-files.cjs <DevEco typescript.js> <audio-file> [...]');
  process.exit(2);
}
const ts = require(path.resolve(compilerPath));
const root = path.resolve(__dirname, '../HarmonyRecorder/entry/src/main/ets');
const opened = new Set();
const fileIo = {
  OpenMode: { READ_ONLY: fs.constants.O_RDONLY },
  statSync: name => fs.statSync(name),
  openSync: name => { const fd = fs.openSync(name, fs.constants.O_RDONLY); opened.add(fd); return { fd }; },
  readSync: (fd, buffer, options = {}) => fs.readSync(fd, Buffer.from(buffer), 0,
    options.length ?? buffer.byteLength, options.offset ?? null),
  closeSync: file => { fs.closeSync(file.fd); opened.delete(file.fd); }
};
const cache = new Map();
function load(filename) {
  const resolved = path.resolve(filename);
  if (!resolved.startsWith(root + path.sep)) throw new Error('Module outside application source');
  if (cache.has(resolved)) return cache.get(resolved).exports;
  const module = { exports: {} }; cache.set(resolved, module);
  const output = ts.transpileModule(fs.readFileSync(resolved, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const requireLocal = name => {
    if (name === '@kit.CoreFileKit') return { fileIo };
    if (name.startsWith('.')) return load(path.resolve(path.dirname(resolved), name + '.ets'));
    throw new Error('Unexpected module: ' + name);
  };
  new Function('require', 'exports', 'module', output)(requireLocal, module.exports, module);
  return module.exports;
}
try {
  const { AudioFileUtils } = load(path.join(root, 'utils/AudioFileUtils.ets'));
  const results = paths.map(input => {
    const file = path.resolve(input);
    try {
      const metadata = AudioFileUtils.read(file, path.extname(file).slice(1).toLowerCase());
      if (!metadata) { process.exitCode = 1; return { file, validContainer: false }; }
      return { file, validContainer: true, sizeBytes: fs.statSync(file).size,
        format: metadata.config.format, sampleRate: metadata.config.sampleRate,
        bitDepth: metadata.config.bitDepth, channels: metadata.config.channels,
        bitrate: metadata.config.bitrate, durationMs: metadata.durationMs,
        pcmDataOffset: metadata.dataOffset, pcmDataLength: metadata.dataLength };
    } catch (error) {
      process.exitCode = 1; return { file, validContainer: false, error: String(error) };
    }
  });
  console.log(JSON.stringify(results, null, 2));
} finally {
  for (const fd of opened) fs.closeSync(fd);
}
