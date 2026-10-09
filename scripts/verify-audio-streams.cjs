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
  const sampleRate = Number(stream?.sample_rate), channels = Number(stream?.channels);
  const bitDepth = Number(stream?.bits_per_raw_sample || stream?.bits_per_sample) || 32;
  const positiveFullScale = 1 - 2 ** (1 - Math.min(bitDepth, 32));
  const hash = crypto.createHash('sha256');
  let carry = Buffer.alloc(0), samples = 0, square = 0, sum = 0, peak = 0, error = '';
  let nonzeroSamples = 0, fullScaleSamples = 0;
  const child = spawn('ffmpeg', ['-v', 'error', '-nostdin', '-err_detect', 'explode', '-i', file,
    '-map', '0:a:0', '-c:a', 'pcm_s32le', '-f', 's32le', 'pipe:1'], { windowsHide: true });
  child.stdout.on('data', chunk => {
    hash.update(chunk);
    const bytes = carry.length ? Buffer.concat([carry, chunk]) : chunk;
    const length = bytes.length - bytes.length % 4;
    for (let offset = 0; offset < length; offset += 4) {
      const value = bytes.readInt32LE(offset) / 2147483648;
      square += value * value; sum += value; peak = Math.max(peak, Math.abs(value)); samples++;
      if (value !== 0) nonzeroSamples++;
      if (value <= -1 || value >= positiveFullScale) fullScaleSamples++;
    }
    carry = Buffer.from(bytes.subarray(length));
  });
  child.stderr.on('data', chunk => { if (error.length < 4096) error += chunk.toString(); });
  const status = await new Promise((resolve, reject) => {
    child.on('error', reject); child.on('close', resolve);
  });
  return { name, valid: probe.status === 0 && status === 0 && samples > 0 && carry.length === 0 &&
      Number.isFinite(sampleRate) && sampleRate > 0 && Number.isInteger(channels) && channels > 0 && samples % channels === 0,
    sampleRate, channels, decodedSamples: samples, decodedFrames: samples / channels,
    durationMs: samples * 1000 / (sampleRate * channels), peak,
    rms: samples ? Math.sqrt(square / samples) : 0, dcOffset: samples ? sum / samples : 0,
    nonzeroSamples, fullScaleSamples, fullScaleFraction: samples ? fullScaleSamples / samples : 0,
    pcmSha256: hash.digest('hex'),
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
      a.decodedSamples === b.decodedSamples && a.sampleRate === b.sampleRate && a.channels === b.channels });
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
  const aacChecks = [];
  const checkAac = (source, encoded, decoded) => {
    const a = byName.get(source), b = byName.get(encoded), c = byName.get(decoded);
    const sameFormat = !!a?.valid && !!b?.valid && !!c?.valid &&
      a.sampleRate === b.sampleRate && b.sampleRate === c.sampleRate &&
      a.channels === b.channels && b.channels === c.channels;
    aacChecks.push({ source, encoded, decoded,
      tailPreserved: sameFormat && b.decodedFrames >= a.decodedFrames && b.decodedFrames < a.decodedFrames + 1024,
      primingTrimmed: sameFormat && c.decodedFrames === b.decodedFrames });
  };
  for (const rate of [44100, 48000]) {
    const stress = `stream_${rate}_${rate * 60 + 37}.wav`;
    if (byName.has(stress)) checkAac(stress, `stress_${rate}.m4a`, `aac_${rate}.wav`);
  }
  for (const [source, encoded, decoded] of [
    ['source_48000_16_48037.wav', 'from_flac_48000.m4a', 'from_aac_48000.wav'],
    ['source_44100_16_44137.wav', 'from_wav_44100.m4a', 'from_aac_44100.flac'],
    ['source_48000_24_48037.wav', 'from_24bit.m4a', 'decoded_24bit_aac.wav']
  ]) {
    if (byName.has(encoded) || byName.has(decoded)) checkAac(source, encoded, decoded);
  }
  for (const name of byName.keys()) {
    const tail = /^aac_tail_(44100|48000)_(16|24)_(\d+)\.m4a$/.exec(name);
    if (tail) checkAac(`source_${tail[1]}_${tail[2]}_${tail[3]}.wav`, name, name.replace(/\.m4a$/, '.wav'));
  }
  const failures = results.filter(item => !item.valid).length + comparisons.filter(item => !item.pcmBitExact).length +
    aacChecks.filter(item => !item.tailPreserved || !item.primingTrimmed).length;
  console.log(JSON.stringify({ results, losslessComparisons: comparisons, aacChecks, failures }, null, 2));
  if (!results.length || failures) process.exitCode = 1;
})().catch(error => { console.error(error); process.exitCode = 1; });
