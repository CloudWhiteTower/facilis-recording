#!/usr/bin/env node
// Independent FFmpeg decoding; never invokes the app's native codec implementation.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
const directory = path.resolve(process.argv[2] || '.');
const results = [], decoded = new Map();
let failed = 0;
for (const name of fs.readdirSync(directory).filter(n => /\.(wav|flac|m4a)$/.test(n) && !n.startsWith('cancelled'))) {
  const file = path.join(directory, name);
  const probe = spawnSync('ffprobe', ['-v', 'error', '-show_streams', '-show_format', '-of', 'json', file],
    { encoding: 'utf8', windowsHide: true });
  const decode = spawnSync('ffmpeg', ['-v', 'error', '-nostdin', '-err_detect', 'explode', '-i', file,
    '-map', '0:a:0', '-c:a', 'pcm_s32le', '-f', 's32le', 'pipe:1'],
    { windowsHide: true, maxBuffer: 32 * 1024 * 1024 });
  const pcm = decode.stdout || Buffer.alloc(0);
  const okay = probe.status === 0 && decode.status === 0 && pcm.length > 0 && pcm.length % 4 === 0;
  let peak = 0, square = 0;
  for (let offset = 0; offset + 4 <= pcm.length; offset += 4) {
    const value = pcm.readInt32LE(offset) / 2147483648;
    peak = Math.max(peak, Math.abs(value)); square += value * value;
  }
  const metadata = probe.status === 0 ? JSON.parse(probe.stdout) : {};
  const stream = metadata.streams?.find(stream => stream.codec_type === 'audio');
  results.push({ name, valid: okay, sampleRate: Number(stream?.sample_rate), channels: stream?.channels,
    decodedSamples: pcm.length / 4, peak, rms: pcm.length > 0 ? Math.sqrt(square / (pcm.length / 4)) : 0,
    pcmSha256: crypto.createHash('sha256').update(pcm).digest('hex'),
    error: okay ? undefined : (decode.stderr || Buffer.from(probe.stderr || '')).toString().trim() });
  if (!okay) failed++;
  decoded.set(name, pcm);
}
const pairs = [
  ['source_48000_16_48037.wav', 'roundtrip_48000.flac'],
  ['source_48000_16_48037.wav', 'roundtrip_48000.wav'],
  ['source_44100_16_44137.wav', 'roundtrip_44100.flac'],
  ['source_44100_16_44137.wav', 'roundtrip_44100.wav'],
  ['source_48000_24_48037.wav', 'preserved_24.wav']
].map(([source, output]) => {
  const equal = decoded.has(source) && decoded.has(output) && decoded.get(source).length > 0 &&
    decoded.get(source).equals(decoded.get(output));
  if (!equal) failed++;
  return { source, output, pcmBitExact: equal };
});
console.log(JSON.stringify({ results, losslessComparisons: pairs, failures: failed }, null, 2));
if (failed) process.exitCode = 1;
