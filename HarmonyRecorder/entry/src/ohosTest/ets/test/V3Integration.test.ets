import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import codec from 'libfacilis_flac.so';
import { RecordingConfig, RecordingInfo, RecordingState } from '../../../main/ets/models/RecordingTypes';
import { RecordingRepository } from '../../../main/ets/repository/RecordingRepository';
import { RecordingService } from '../../../main/ets/services/RecordingService';
import { PlaybackService } from '../../../main/ets/services/PlaybackService';
import { PermissionService } from '../../../main/ets/services/PermissionService';
import { AudioFileUtils } from '../../../main/ets/utils/AudioFileUtils';
import { WaveFileUtils } from '../../../main/ets/utils/WaveFileUtils';

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
}

function directory(): string {
  const path = `${abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir}/v3-validation`;
  if (!fileIo.accessSync(path)) { fileIo.mkdirSync(path, true); }
  return path;
}

function writeAll(fd: number, bytes: ArrayBuffer): void {
  let cursor = 0;
  while (cursor < bytes.byteLength) {
    const count = fileIo.writeSync(fd, bytes.slice(cursor));
    if (count <= 0) { throw new Error('Fixture write made no progress'); }
    cursor += count;
  }
}

function streamedFixture(rate: number, samples: number): string {
  const path = `${directory()}/stream_${rate}_${samples}.wav`;
  const output = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  try {
    writeAll(output.fd, WaveFileUtils.createPcmHeader(RecordingConfig.wav(rate, 16), samples * 2));
    const chunkSamples = 8192;
    let random = 42;
    for (let cursor = 0; cursor < samples; cursor += chunkSamples) {
      const count = Math.min(chunkSamples, samples - cursor);
      const bytes = new ArrayBuffer(count * 2);
      const view = new DataView(bytes);
      for (let index = 0; index < count; index++) {
        random = (Math.imul(random, 1664525) + 1013904223) >>> 0;
        const absolute = cursor + index;
        view.setInt16(index * 2, absolute % 97 === 0 ? -32768 :
          (absolute % 101 === 0 ? 32767 : (random >>> 16) - 32768), true);
      }
      writeAll(output.fd, bytes);
    }
    fileIo.fsyncSync(output.fd);
  } finally { fileIo.closeSync(output); }
  return path;
}

async function convert(sourcePath: string, targetName: string, format: string): Promise<string> {
  const targetPath = `${directory()}/${targetName}`;
  const source = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
  const output = fileIo.openSync(targetPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  let handle = 0;
  const started = Date.now();
  try {
    handle = await codec.conversionCreate(source.fd, fileIo.statSync(source.fd).size, output.fd, format, 256000, 16);
    const result = await codec.conversionRun(handle);
    expect(result.channels).assertEqual(1);
    expect(result.durationMs > 0).assertTrue();
    await codec.conversionRelease(handle); handle = 0;
    fileIo.fsyncSync(output.fd);
    console.info(`V3_CONVERSION name=${targetName} elapsedMs=${Date.now() - started} durationMs=${result.durationMs}`);
  } finally {
    if (handle > 0) { await codec.conversionRelease(handle); }
    fileIo.closeSync(source); fileIo.closeSync(output);
  }
  return targetPath;
}

function equalPcm(firstPath: string, secondPath: string): void {
  const a = AudioFileUtils.read(firstPath, 'wav');
  const b = AudioFileUtils.read(secondPath, 'wav');
  expect(a !== undefined && b !== undefined).assertTrue();
  if (a === undefined || b === undefined) { throw new Error('Missing fixture metadata'); }
  expect(b.dataLength).assertEqual(a.dataLength);
  const first = fileIo.openSync(firstPath, fileIo.OpenMode.READ_ONLY);
  const second = fileIo.openSync(secondPath, fileIo.OpenMode.READ_ONLY);
  try {
    for (let cursor = 0; cursor < a.dataLength; cursor += 65536) {
      const count = Math.min(65536, a.dataLength - cursor);
      const x = new Uint8Array(count), y = new Uint8Array(count);
      expect(fileIo.readSync(first.fd, x.buffer, { offset: a.dataOffset + cursor })).assertEqual(count);
      expect(fileIo.readSync(second.fd, y.buffer, { offset: b.dataOffset + cursor })).assertEqual(count);
      for (let index = 0; index < count; index++) {
        if (x[index] !== y[index]) { throw new Error(`PCM mismatch at byte ${cursor + index}`); }
      }
    }
  } finally { fileIo.closeSync(first); fileIo.closeSync(second); }
}

async function foregroundContext(): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  await delegator.startAbility({ bundleName: 'com.example.harmonyrecorder', abilityName: 'EntryAbility' });
  await delay(600);
  return (await delegator.getCurrentTopAbility()).context;
}

async function microphone(context: common.UIAbilityContext): Promise<void> {
  const permission = PermissionService.ensureMicrophonePermission(context);
  const driver = Driver.create();
  await delay(300);
  // The explicit recording opt-in authorizes the microphone permission. Only
  // operate a visible permission button; an already granted permission needs no UI.
  for (const label of ['仅使用时允许', '使用期间允许', '允许']) {
    const button = await driver.findComponent(ON.text(label));
    if (button !== null) { await button.click(); break; }
  }
  expect(await permission).assertTrue();
}

async function verifyPlayback(recording: RecordingInfo, context: common.Context): Promise<void> {
  const playback = new PlaybackService();
  let position = 0, message = '';
  playback.setObserver((ready: boolean, playing: boolean, current: number, duration: number, detail: string): void => {
    position = current; message = detail;
  });
  try {
    expect(await playback.load(recording, context) !== undefined).assertTrue();
    await playback.toggle(); await delay(700);
    expect(position > 0).assertTrue(); expect(message.length).assertEqual(0);
    await playback.toggle();
    expect(await playback.seek(Math.floor(recording.durationMs * 0.5))).assertTrue();
    await playback.toggle(); await delay(300);
    expect(message.length).assertEqual(0);
  } finally { await playback.release(); }
}

export default function v3IntegrationTest() {
  const parameters = abilityDelegatorRegistry.getArguments().parameters;
  const enabled = parameters['v3'] || parameters['-s v3'];
  if (enabled !== 'true') { return; }
  describe('v3StreamingIntegration', () => {
    for (const rate of [44100, 48000]) {
      it(`roundtrips a minute of full-range ${rate} Hz PCM and decodes AAC`, 0, async () => {
        const source = streamedFixture(rate, rate * 60 + 37);
        const flac = await convert(source, `stress_${rate}.flac`, 'flac');
        const wav = await convert(flac, `roundtrip_${rate}.wav`, 'wav');
        equalPcm(source, wav);
        const aac = await convert(source, `stress_${rate}.m4a`, 'm4a');
        const decoded = await convert(aac, `aac_${rate}.wav`, 'wav');
        const metadata = AudioFileUtils.read(decoded, 'wav');
        expect(metadata !== undefined).assertTrue();
        if (metadata !== undefined) {
          expect(metadata.config.sampleRate).assertEqual(rate);
          expect(Math.abs(metadata.durationMs - (60000 + 37000 / rate)) < 60).assertTrue();
        }
      });
    }
    it('cancels a running long FLAC encode promptly and keeps the source unchanged', 0, async () => {
      const path = streamedFixture(48000, 48000 * 300);
      const source = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      const output = fileIo.openSync(`${directory()}/cancelled.flac`,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      const size = fileIo.statSync(source.fd).size;
      let handle = 0;
      try {
        handle = await codec.conversionCreate(source.fd, size, output.fd, 'flac', 256000, 16);
        const run = codec.conversionRun(handle);
        await delay(40);
        const started = Date.now(); codec.conversionCancel(handle);
        let cancelled = false;
        try { await run; } catch (error) { cancelled = true; }
        expect(cancelled).assertTrue();
        await codec.conversionRelease(handle); handle = 0;
        console.info(`V3_CANCEL elapsedMs=${Date.now() - started}`);
        expect(fileIo.statSync(source.fd).size).assertEqual(size);
      } finally {
        if (handle > 0) { await codec.conversionRelease(handle); }
        fileIo.closeSync(source); fileIo.closeSync(output);
      }
    });
  });

  const capture = parameters['capture'] || parameters['-s capture'];
  if (capture !== 'true') { return; }
  describe('v3MicrophoneIntegration', () => {
    it('records, pauses, resumes and plays each supported format using the production services', 0, async () => {
      const context = await foregroundContext(); await microphone(context);
      const previousIds = RecordingRepository.list(context).map((item: RecordingInfo): string => item.id).sort();
      const service = RecordingService.getInstance();
      const configs = [RecordingConfig.wav(44100, 24), RecordingConfig.flac(), RecordingConfig.aac(128000)];
      for (const config of configs) {
        let recording: RecordingInfo | undefined = undefined;
        try {
          await service.start(context, config); await delay(2300);
          await service.pause(); const paused = service.getDuration(); await delay(500);
          expect(service.getDuration()).assertEqual(paused);
          if (config.format === 'wav') {
            const files = RecordingRepository.list(context);
            // The active reserved path must remain outside library actions.
            expect(files.every((item: RecordingInfo): boolean => previousIds.includes(item.id))).assertTrue();
          }
          await service.resume(); await delay(700); recording = await service.stop();
          expect(recording !== undefined).assertTrue();
          if (recording !== undefined) {
            expect(recording.durationMs > 2000 && recording.durationMs < 5000).assertTrue();
            fileIo.copyFileSync(recording.filePath, `${directory()}/microphone.${config.extension}`);
            await verifyPlayback(recording, context);
            console.info(`V3_CAPTURE format=${config.format} durationMs=${recording.durationMs} bytes=${recording.sizeBytes}`);
          }
        } finally {
          if (service.getState() === RecordingState.RECORDING || service.getState() === RecordingState.PAUSED) {
            await service.discard();
          }
          if (recording !== undefined) {
            RecordingRepository.permanentlyDelete(context, RecordingRepository.moveToRecentlyDeleted(context, recording));
          }
        }
      }
      expect(RecordingRepository.list(context).map((item: RecordingInfo): string => item.id).sort().join('|'))
        .assertEqual(previousIds.join('|'));
    });
    const seconds = Number(parameters['soakSeconds'] || parameters['-s soakSeconds'] || '0');
    if (Number.isFinite(seconds) && seconds >= 60 && seconds <= 3600) {
      it(`records ${seconds} wall-clock seconds of WAV with a playable mid-recording checkpoint`, 0, async () => {
        const context = await foregroundContext(); await microphone(context);
        const service = RecordingService.getInstance();
        let recording: RecordingInfo | undefined = undefined;
        const initialNames = new Set<string>(fileIo.listFileSync(`${context.filesDir}/recordings`));
        try {
          const started = Date.now(); await service.start(context, RecordingConfig.wav());
          for (let elapsed = 0; elapsed < seconds; elapsed += 5) {
            await delay(Math.min(5, seconds - elapsed) * 1000);
            expect(service.getState()).assertEqual(RecordingState.RECORDING);
            expect(service.getDuration() > Math.max(0, elapsed - 1) * 1000).assertTrue();
            if (elapsed === 10) {
              const names = fileIo.listFileSync(`${context.filesDir}/recordings`);
              const latest = names.filter((name: string): boolean => name.endsWith('.wav') && !initialNames.has(name));
              expect(latest.length).assertEqual(1);
              const path = `${context.filesDir}/recordings/${latest[0]}`;
              const checkpoint = AudioFileUtils.read(path, 'wav');
              expect(checkpoint !== undefined && checkpoint.durationMs >= 5000).assertTrue();
            }
            if ((elapsed + 5) % 60 === 0) { console.info(`V3_SOAK elapsedSeconds=${elapsed + 5} samplesMs=${service.getDuration()}`); }
          }
          recording = await service.stop(); expect(recording !== undefined).assertTrue();
          if (recording !== undefined) {
            fileIo.copyFileSync(recording.filePath, `${directory()}/soak.wav`);
            await verifyPlayback(recording, context);
            console.info(`V3_SOAK_RESULT elapsedMs=${Date.now() - started} durationMs=${recording.durationMs} bytes=${recording.sizeBytes}`);
            expect(Math.abs(recording.durationMs - seconds * 1000) < 4000).assertTrue();
          }
        } finally {
          if (service.getState() === RecordingState.RECORDING || service.getState() === RecordingState.PAUSED) {
            await service.discard();
          }
          if (recording !== undefined) {
            RecordingRepository.permanentlyDelete(context, RecordingRepository.moveToRecentlyDeleted(context, recording));
          }
        }
      });
    }
  });
}
