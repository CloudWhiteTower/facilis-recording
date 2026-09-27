import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry, DisplayRotation, Driver, ON } from '@kit.TestKit';
import { fileIo } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import flac from 'libfacilis_flac.so';
import { PlaybackService } from '../../../main/ets/services/PlaybackService';
import { RecordingConfig, RecordingInfo } from '../../../main/ets/models/RecordingTypes';
import { RecordingRepository } from '../../../main/ets/repository/RecordingRepository';
import { AudioFileUtils } from '../../../main/ets/utils/AudioFileUtils';

function delay(ms: number): Promise<void> {
  return new Promise((resolve: () => void): void => { setTimeout(resolve, ms); });
}

function writeAll(fd: number, data: ArrayBuffer): void {
  let offset = 0;
  while (offset < data.byteLength) {
    const written = fileIo.writeSync(fd, data.slice(offset));
    if (written <= 0) {
      throw new Error('No file write progress');
    }
    offset += written;
  }
}

async function fixtureDuration(filePath: string): Promise<number> {
  // Codec fixtures deliberately live in cache, outside the managed recording
  // repository. Test system decoding directly without importing user recordings.
  const source = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
  let player: media.AVPlayer | undefined = undefined;
  let timeoutId = -1;
  let active = true;
  try {
    const nativePlayer = await media.createAVPlayer();
    player = nativePlayer;
    return await new Promise<number>((resolve: (duration: number) => void, reject: (reason: Error) => void): void => {
      nativePlayer.on('stateChange', (state: media.AVPlayerState): void => {
        if (!active) { return; }
        if (state === 'initialized') {
          nativePlayer.prepare().catch((error: Error): void => {
            if (active) { reject(error); }
          });
        } else if (state === 'prepared') {
          resolve(nativePlayer.duration);
        }
      });
      nativePlayer.on('error', (error): void => {
        if (active) { reject(new Error(`FLAC fixture prepare: ${error.code} ${error.message}`)); }
      });
      timeoutId = setTimeout((): void => { reject(new Error('FLAC player prepare timeout')); }, 8000);
      nativePlayer.fdSrc = { fd: source.fd, offset: 0, length: fileIo.statSync(source.fd).size };
    });
  } finally {
    active = false;
    if (timeoutId >= 0) { clearTimeout(timeoutId); }
    try {
      if (player !== undefined) { await player.release(); }
    } finally {
      fileIo.closeSync(source);
    }
  }
}

async function flacFixture(sampleRate: number, samples: number, pattern: string = 'signal'): Promise<void> {
  const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  const directory = `${context.cacheDir}/flac-tests`;
  if (!fileIo.accessSync(directory)) {
    fileIo.mkdirSync(directory, true);
  }
  const name = `native_${sampleRate}_${samples}${pattern === 'signal' ? '' : `_${pattern}`}`;
  const pcm = new ArrayBuffer(samples * 2);
  const view = new DataView(pcm);
  for (let index = 0; index < samples; index++) {
    // Known non-silent, signed 16-bit PCM includes extrema and changing frequency.
    const value = pattern === 'silence' ? 0 : pattern === 'constant' ? 12000 :
      index % 97 === 0 ? -32768 : index % 89 === 0 ? 32767 :
      Math.round(Math.sin(index * 0.071 + index * index * 0.000003) * 24000);
    view.setInt16(index * 2, value, true);
  }
  const raw = fileIo.openSync(`${directory}/${name}.pcm`,
    fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  try { writeAll(raw.fd, pcm); } finally { fileIo.closeSync(raw); }
  const outputPath = `${directory}/${name}.flac`;
  const output = fileIo.openSync(outputPath,
    fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  let handle = -1;
  try {
    handle = await flac.create(output.fd, sampleRate, 1);
    for (let offset = 0; offset < pcm.byteLength; offset += 2560) {
      await flac.write(handle, pcm.slice(offset, Math.min(offset + 2560, pcm.byteLength)));
    }
    await flac.finish(handle);
    await flac.release(handle);
    handle = -1;
    fileIo.fsyncSync(output.fd);
  } finally {
    if (handle >= 0) { await flac.release(handle); }
    fileIo.closeSync(output);
  }
  const file = fileIo.openSync(outputPath, fileIo.OpenMode.READ_ONLY);
  try {
    const header = new ArrayBuffer(4);
    expect(fileIo.readSync(file.fd, header)).assertEqual(4);
    expect(new DataView(header).getUint32(0, false)).assertEqual(0x664C6143);
  } finally { fileIo.closeSync(file); }
  const actualDuration = await fixtureDuration(outputPath);
  expect(Math.abs(actualDuration - samples * 1000 / sampleRate) <= 25).assertTrue();
  console.info(`FLAC_FIXTURE ${outputPath} samples=${samples} durationMs=${actualDuration}`);
}

// Explicit opt-in; ordinary unit tests neither capture audio nor rotate a display.
export default function deviceIntegrationTest() {
  const parameters = abilityDelegatorRegistry.getArguments().parameters;
  const uiPlaybackFile = parameters['playbackUiFile'] || parameters['-s playbackUiFile'] || '';
  if (uiPlaybackFile.length > 0) {
    describe('savedRecordingPlaybackUi', () => {
      it('opens a real library recording through the app and starts then pauses playback', 0, async () => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator();
        await delegator.startAbility({ bundleName: 'com.example.harmonyrecorder', abilityName: 'EntryAbility' });
        const driver = Driver.create();
        await (await driver.waitForComponent(ON.id('tab-1'), 5000)).click();
        const stem = uiPlaybackFile.substring(0, uiPlaybackFile.lastIndexOf('.'));
        await (await driver.waitForComponent(ON.text(stem), 5000)).click();
        const play = await driver.waitForComponent(ON.id('player-toggle'), 5000);
        await driver.screenCap(`${delegator.getAppContext().cacheDir}/playback-before.png`);
        await delay(800);
        expect(await play.isEnabled()).assertTrue();
        await play.click();
        await delay(1500);
        const manager = audio.getAudioManager();
        const volume = await manager.getVolume(audio.AudioVolumeType.MEDIA);
        const outputs = await manager.getDevices(audio.DeviceFlag.OUTPUT_DEVICES_FLAG);
        console.info(`AUDIO_OUTPUT volume=${volume} availableTypes=${outputs.map((device: audio.AudioDeviceDescriptor): number =>
          device.deviceType).join(',')}`);
        expect(await driver.screenCap(`${delegator.getAppContext().cacheDir}/playback-${uiPlaybackFile}.png`)).assertTrue();
        await (await driver.findComponent(ON.id('player-toggle'))).click();
        await driver.pressBack();
      });
    });
  }
  if (parameters['integration'] === 'true' || parameters['-s integration'] === 'true') {
    describe('nativeFlacIntegration', () => {
      it('encodes 48k PCM including the final partial frame and opens in AVPlayer', 0, async () => {
        await flacFixture(48000, 4608 * 3 + 37);
      });
      it('encodes 44k1 PCM including the final partial frame and opens in AVPlayer', 0, async () => {
        await flacFixture(44100, 4608 * 3 + 37);
      });
      it('encodes a recording shorter than one FLAC frame', 0, async () => {
        await flacFixture(48000, 137);
      });
      it('encodes exactly one complete FLAC frame', 0, async () => {
        await flacFixture(48000, 4608);
      });
      it('encodes a complete FLAC frame plus one sample', 0, async () => {
        await flacFixture(48000, 4609);
      });
      it('encodes a short 44k1 recording without duplicating EOS data', 0, async () => {
        await flacFixture(44100, 137);
      });
      it('encodes a single sample without padding or duplication', 0, async () => {
        await flacFixture(48000, 1);
      });
      it('keeps exact sample counts around the minimum STREAMINFO block size', 0, async () => {
        await flacFixture(48000, 15);
        await flacFixture(48000, 16);
        await flacFixture(44100, 17);
      });
      it('keeps metadata correct for highly compressed silent and constant frames', 0, async () => {
        await flacFixture(48000, 4609, 'silence');
        await flacFixture(44100, 13861, 'constant');
      });
      it('rejects an empty stream instead of reporting a valid recording', 0, async () => {
        const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
        const file = fileIo.openSync(`${context.cacheDir}/empty-flac-test.flac`,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        const handle = await flac.create(file.fd, 48000, 1);
        let rejected = false;
        try {
          try { await flac.finish(handle); } catch (error) { rejected = true; }
          expect(rejected).assertTrue();
        } finally {
          await flac.release(handle);
          fileIo.closeSync(file);
          fileIo.unlinkSync(`${context.cacheDir}/empty-flac-test.flac`);
        }
      });
    });
  }
  if (parameters['layout'] === 'true' || parameters['-s layout'] === 'true') {
    describe('responsiveDeviceLayout', () => {
      it('keeps recording controls accessible in both display orientations', 0, async () => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator();
        await delegator.startAbility({ bundleName: 'com.example.harmonyrecorder', abilityName: 'EntryAbility' });
        const driver = Driver.create();
        await delay(1500);
        const original = await driver.getDisplayRotation();
        const screenshots = delegator.getAppContext().cacheDir;
        try {
          for (const rotation of [DisplayRotation.ROTATION_0, DisplayRotation.ROTATION_90]) {
            await driver.setDisplayRotation(rotation);
            await delay(1500);
            expect(await driver.screenCap(`${screenshots}/facilis-recorder-${rotation}.png`)).assertTrue();
            const button = await driver.findComponent(ON.id('record-start'));
            expect(button !== null).assertTrue();
            const quality = await driver.findComponent(ON.id('record-quality'));
            expect(quality !== null).assertTrue();
            await quality.click();
            await delay(700);
            expect(await driver.screenCap(`${screenshots}/facilis-quality-${rotation}.png`)).assertTrue();
            await driver.pressBack();
          }
        } finally {
          await driver.setDisplayRotation(original);
        }
      });
    });
  }
  const playbackFile = parameters['playbackFile'] || parameters['-s playbackFile'] || '';
  if (playbackFile.length > 0) {
    describe('savedRecordingPlayback', () => {
      it('plays a saved file at the beginning, middle and end', 0, async () => {
        const player = new PlaybackService();
        const delegator = abilityDelegatorRegistry.getAbilityDelegator();
        await delegator.startAbility({ bundleName: 'com.example.harmonyrecorder', abilityName: 'EntryAbility' });
        // TestKit contexts resolve to the runner's module. Copy only the requested
        // bytes into that isolated managed library; direct UI tests cover the real path.
        const context = delegator.getAppContext();
        const fileName = playbackFile.substring(playbackFile.lastIndexOf('/') + 1);
        const extension = fileName.substring(fileName.lastIndexOf('.') + 1);
        const temporaryPath = `${context.cacheDir}/playback_check_${Date.now()}.${extension}`;
        let selected: RecordingInfo | undefined = undefined;
        let durationMs = 0;
        let positionMs = 0;
        let message = '';
        let timeoutId = -1;
        player.setObserver((ready: boolean, playing: boolean, position: number,
          duration: number, error: string): void => {
          positionMs = position;
          durationMs = duration;
          if (error.length > 0) { message = error; }
        });
        try {
          await fileIo.copyFile(playbackFile, temporaryPath);
          const metadata = AudioFileUtils.read(temporaryPath, extension);
          if (metadata === undefined) { throw new Error('Requested playback fixture has invalid metadata'); }
          selected = RecordingRepository.importCompletedFile(context, temporaryPath, metadata.config, 'PlaybackCheck');
          await Promise.race([
            player.load(selected, context),
            new Promise<void>((resolve: () => void, reject: (reason: Error) => void): void => {
              timeoutId = setTimeout((): void => { reject(new Error('Saved recording prepare timeout')); }, 10000);
            })
          ]);
          expect(durationMs > 3000).assertTrue();
          const duration = durationMs;
          await player.toggle();
          for (const target of [0, Math.floor(duration / 2), duration - 2000]) {
            expect(await player.seek(target)).assertTrue();
            await delay(1200);
            expect(message).assertEqual('');
            expect(positionMs > target + 100).assertTrue();
            console.info(`SAVED_PLAYBACK targetMs=${target} positionMs=${positionMs} durationMs=${duration}`);
          }
        } finally {
          if (timeoutId >= 0) { clearTimeout(timeoutId); }
          await player.release();
          if (selected !== undefined) {
            RecordingRepository.permanentlyDelete(context, RecordingRepository.moveToRecentlyDeleted(context, selected));
          }
          if (fileIo.accessSync(temporaryPath)) { fileIo.unlinkSync(temporaryPath); }
        }
      });
    });
  }
}
