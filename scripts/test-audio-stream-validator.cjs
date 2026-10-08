#!/usr/bin/env node
// Independent FFmpeg fixtures validate the reporting tool, not the app's codec.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const tempRoot = path.resolve(os.tmpdir());
const directory = fs.mkdtempSync(path.join(tempRoot, 'facilis-stream-check-'));
function encode(args, name) {
  const result = spawnSync('ffmpeg', ['-v', 'error', '-nostdin', '-y', ...args, path.join(directory, name)],
    { encoding: 'utf8', windowsHide: true, timeout: 30000 });
  assert.equal(result.status, 0, result.stderr || String(result.error));
}
function inspect() {
  const result = spawnSync(process.execPath, [path.join(__dirname, 'verify-audio-streams.cjs'), directory],
    { encoding: 'utf8', windowsHide: true, timeout: 30000 });
  assert.equal(result.status, 0, result.stderr || result.stdout || String(result.error));
  return JSON.parse(result.stdout);
}
try {
  encode(['-f', 'lavfi', '-i', 'aevalsrc=0.25:s=48000:d=2', '-af', 'atrim=end_sample=48037',
    '-c:a', 'pcm_s16le'], 'source_48000_16_48037.wav');
  encode(['-i', path.join(directory, 'source_48000_16_48037.wav'), '-c:a', 'flac'], 'roundtrip_48000.flac');
  encode(['-i', path.join(directory, 'roundtrip_48000.flac'), '-c:a', 'pcm_s16le'], 'roundtrip_48000.wav');
  encode(['-f', 'lavfi', '-i', 'aevalsrc=0.25|-0.25:s=48000:d=1', '-c:a', 'pcm_s16le'], 'stereo.wav');
  encode(['-f', 'lavfi', '-i', 'aevalsrc=-1:s=48000:d=0.1', '-c:a', 'pcm_s16le'], 'fullscale.wav');
  encode(['-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=mono:d=0.1', '-c:a', 'pcm_s16le'], 'silence.wav');
  const result = inspect(), files = new Map(result.results.map(item => [item.name, item]));
  assert.equal(result.failures, 0); assert.equal(result.losslessComparisons.length, 2);
  assert.ok(result.losslessComparisons.every(item => item.pcmBitExact));
  const mono = files.get('source_48000_16_48037.wav');
  assert.equal(mono.decodedSamples, 48037); assert.equal(mono.rms, 0.25); assert.equal(mono.dcOffset, 0.25);
  console.log('PASS mono sample count, known RMS/DC and lossless pair reporting');
  const stereo = files.get('stereo.wav');
  assert.equal(stereo.decodedSamples, 96000); assert.equal(stereo.decodedFrames, 48000);
  assert.equal(stereo.durationMs, 1000); assert.equal(stereo.dcOffset, 0); assert.equal(stereo.rms, 0.25);
  console.log('PASS stereo duration uses frames rather than interleaved sample count');
  assert.equal(files.get('silence.wav').nonzeroSamples, 0); assert.equal(files.get('silence.wav').rms, 0);
  assert.equal(files.get('fullscale.wav').fullScaleFraction, 1); assert.equal(mono.fullScaleFraction, 0);
  console.log('PASS silence and full-scale sample statistics');
  const encoded = 'from_flac_48000.m4a', decoded = 'from_aac_48000.wav';
  const source = path.join(directory, 'source_48000_16_48037.wav');
  encode(['-i', source, '-c:a', 'aac', '-b:a', '128k'], encoded);
  const completeAac = fs.readFileSync(path.join(directory, encoded));
  encode(['-i', path.join(directory, encoded), '-c:a', 'pcm_s16le'], decoded);
  assert.ok(inspect().aacChecks.every(item => item.tailPreserved && item.primingTrimmed));
  console.log('PASS complete AAC tail and decoded presentation sample count');
  const inspectFailure = () => {
    const checked = spawnSync(process.execPath, [path.join(__dirname, 'verify-audio-streams.cjs'), directory],
      { encoding: 'utf8', windowsHide: true, timeout: 30000 });
    assert.equal(checked.status, 1, checked.stderr || checked.stdout);
    return JSON.parse(checked.stdout);
  };
  encode(['-i', source, '-af', 'atrim=end_sample=45056', '-c:a', 'aac', '-b:a', '128k'], encoded);
  encode(['-i', path.join(directory, encoded), '-c:a', 'pcm_s16le'], decoded);
  const truncated = inspectFailure().aacChecks[0];
  assert.equal(truncated.tailPreserved, false); assert.equal(truncated.primingTrimmed, true);
  console.log('PASS truncated AAC tail fails independent validation');
  fs.writeFileSync(path.join(directory, encoded), completeAac);
  encode(['-i', path.join(directory, encoded), '-af', 'adelay=2048S:all=1', '-c:a', 'pcm_s16le'], decoded);
  const priming = inspectFailure().aacChecks[0];
  assert.equal(priming.tailPreserved, true); assert.equal(priming.primingTrimmed, false);
  console.log('PASS extra decoded priming samples fail independent validation');
  encode(['-i', path.join(directory, encoded), '-c:a', 'pcm_s16le'], decoded);
  encode(['-f', 'lavfi', '-i', 'aevalsrc=0.25:s=44100:d=2', '-af', 'atrim=end_sample=48037',
    '-c:a', 'pcm_s16le'], 'wrong-rate.wav');
  fs.copyFileSync(path.join(directory, 'wrong-rate.wav'), path.join(directory, 'roundtrip_48000.wav'));
  const mismatched = spawnSync(process.execPath, [path.join(__dirname, 'verify-audio-streams.cjs'), directory],
    { encoding: 'utf8', windowsHide: true, timeout: 30000 });
  assert.equal(mismatched.status, 1); const mismatch = JSON.parse(mismatched.stdout);
  assert.equal(mismatch.losslessComparisons.find(item => item.output === 'roundtrip_48000.wav').pcmBitExact, false);
  console.log('PASS identical PCM at a different sample rate fails the lossless comparison');
  console.log('Stream validator checks: 7 passed. Fixtures use FFmpeg; app codecs remain separate.');
} finally {
  const resolved = path.resolve(directory);
  assert.equal(path.dirname(resolved), tempRoot);
  assert.ok(path.basename(resolved).startsWith('facilis-stream-check-'));
  fs.rmSync(resolved, { recursive: true, force: true });
}
