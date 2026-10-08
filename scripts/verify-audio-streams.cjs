#!/usr/bin/env node
// Independent, bounded-memory FFmpeg validation of long device fixtures.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawn, spawnSync } = require('node:child_process');
const directory = path.resolve(process.argv[2] || '.');

async function inspect(name) {
  const file = path.join(directory, name);
  const probe = spawnSync('ffprobe', ['-v', 'error', '-show_streams', '-of', 'json', file],
    { encoding: 'utf8', windowsHide: true });
  const stream = probe.status === 0 ? JSON.parse(probe.stdout).streams.find(item => item.codec_type === 'audio') : undefined;
  const hash = crypto.createHash('sha256');
  let carry = Buffer.alloc(0), samples = 0, square = 0, peak = 0, error = '';
  const child = spawn('ffmpeg', ['-v', 'error', '-nostdin', '-err_detect', 'explode', '-i', file,
    '-map', '0:a:0', '-c:a', 'pcm_s32le', '-f', 's32le', 'pipe:1'], { windowsHide: true });
  child.stdout.on('data', chunk => {
    hash.update(chunk);
    const bytes = carry.length ? Buffer.concat([carry, chunk]) : chunk;
    const length = bytes.length - bytes.length % 4;
    for (let offset = 0; offset < length; offset += 4) {
      const value = bytes.readInt32LE(offset) / 2147483648;
      square += value * value; peak = Math.max(peak, Math.abs(value)); samples++;
    }
    carry = Buffer.from(bytes.subarray(length));
  });
  child.stderr.on('data', chunk => { if (error.length < 4096) error += chunk.toString(); });
  const status = await new Promise((resolve, reject) => {
    child.on('error', reject); child.on('close', resolve);
  });
  return { name, valid: probe.status === 0 && status === 0 && samples > 0 && carry.length === 0,
    sampleRate: Number(stream?.sample_rate), channels: stream?.channels, decodedSamples: samples,
    durationMs: samples * 1000 / Number(stream?.sample_rate), peak,
    rms: samples ? Math.sqrt(square / samples) : 0, pcmSha256: hash.digest('hex'),
    ...(error.trim() ? { error: error.trim() } : {}) };
}

(async () => {
  const results = [];
  for (const name of fs.readdirSync(directory).filter(name => /\.(wav|flac|m4a)$/.test(name) && !name.startsWith('cancelled'))) {
    results.push(await inspect(name));
  }
  const byName = new Map(results.map(item => [item.name, item]));
  const comparisons = [];
  const compare = (source, output) => {
    const a = byName.get(source), b = byName.get(output);
    comparisons.push({ source, output, pcmBitExact: !!a?.valid && !!b?.valid && a.pcmSha256 === b.pcmSha256 &&
      a.decodedSamples === b.decodedSamples });
  };
  for (const rate of [44100, 48000]) {
    const stress = results.find(item => item.name.startsWith(`stream_${rate}_`) && item.name !== 'stream_48000_14400000.wav');
    if (stress) {
      compare(stress.name, `stress_${rate}.flac`);
      compare(stress.name, `roundtrip_${rate}.wav`);
    }
    const original = `source_${rate}_16_${rate + 37}.wav`;
    if (byName.has(original)) {
      compare(original, `roundtrip_${rate}.flac`);
      compare(original, `roundtrip_${rate}.wav`);
    }
  }
  if (byName.has('source_48000_24_48037.wav')) compare('source_48000_24_48037.wav', 'preserved_24.wav');
  const failures = results.filter(item => !item.valid).length + comparisons.filter(item => !item.pcmBitExact).length;
  console.log(JSON.stringify({ results, losslessComparisons: comparisons, failures }, null, 2));
  if (!results.length || failures) process.exitCode = 1;
})().catch(error => { console.error(error); process.exitCode = 1; });
