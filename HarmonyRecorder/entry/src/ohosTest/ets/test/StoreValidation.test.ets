import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry, DisplayRotation, Driver, ON } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { power } from '@kit.BasicServicesKit';
import { KeyCode } from '@kit.InputKit';
import { fileIo } from '@kit.CoreFileKit';
import { RecordingConfig, RecordingInfo, RecordingState } from '../../../main/ets/models/RecordingTypes';
import { RecordingService } from '../../../main/ets/services/RecordingService';
import { RecordingRepository } from '../../../main/ets/repository/RecordingRepository';
import { PlaybackService } from '../../../main/ets/services/PlaybackService';
import { PermissionService } from '../../../main/ets/services/PermissionService';
import { AudioFileUtils } from '../../../main/ets/utils/AudioFileUtils';
import { AppPage } from '../../../main/ets/utils/NavigationStore';

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
}

async function foregroundContext(driver: Driver): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  await delegator.startAbility({ bundleName: 'com.example.harmonyrecorder', abilityName: 'EntryAbility' });
  await delay(600);
  await (await driver.waitForComponent(ON.id('tab-0'), 5000)).click();
  expect(await driver.waitForComponent(ON.id('record-start'), 5000) !== null).assertTrue();
  return (await delegator.getCurrentTopAbility()).context;
}

function libraryIds(context: common.Context): string {
  return RecordingRepository.list(context).map((item: RecordingInfo): string => item.id).sort().join('|');
}

function validationDirectory(): string {
  const directory = `${abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir}/store-validation`;
  if (!fileIo.accessSync(directory)) { fileIo.mkdirSync(directory, true); }
  return directory;
}

async function playable(recording: RecordingInfo, context: common.Context): Promise<void> {
  const player = new PlaybackService();
  let position = 0;
  let errorMessage = '';
  player.setObserver((ready: boolean, playing: boolean, current: number, duration: number, error: string): void => {
    position = current; errorMessage = error;
  });
  try {
    expect(await player.load(recording, context) !== undefined).assertTrue();
    await player.toggle(); await delay(600);
    expect(position > 0).assertTrue(); expect(errorMessage).assertEqual('');
    await player.toggle();
    for (const target of [Math.floor(recording.durationMs / 2), Math.max(0, recording.durationMs - 1800)]) {
      expect(await player.seek(target)).assertTrue();
      await player.toggle(); await delay(400); await player.toggle();
      expect(errorMessage).assertEqual('');
    }
  } finally { await player.release(); }
}

async function shortBackground(config: RecordingConfig): Promise<void> {
  const driver = Driver.create();
  const context = await foregroundContext(driver);
  expect(await PermissionService.ensureMicrophonePermission(context)).assertTrue();
  const before = libraryIds(context);
  const service = RecordingService.getInstance();
  let recording: RecordingInfo | undefined = undefined;
  try {
    await service.start(context, config); await delay(1500);
    await driver.pressHome();
    for (let tick = 0; tick < 9; tick++) {
      await delay(5000);
      expect(service.getState()).assertEqual(RecordingState.RECORDING);
      expect(service.getDuration() >= (tick + 1) * 4000).assertTrue();
    }
    await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
      bundleName: 'com.example.harmonyrecorder', abilityName: 'EntryAbility'
    });
    await delay(400);
    await service.pause(); const paused = service.getDuration(); await delay(300);
    expect(service.getDuration()).assertEqual(paused);
    await service.resume(); await delay(700); recording = await service.stop();
    expect(recording !== undefined).assertTrue();
    if (recording === undefined) { throw new Error('Missing saved background recording'); }
    expect(recording.durationMs >= 45000).assertTrue();
    expect(recording.sizeBytes > 1000).assertTrue();
    expect(AudioFileUtils.read(recording.filePath, config.extension) !== undefined).assertTrue();
    fileIo.copyFileSync(recording.filePath, `${validationDirectory()}/background.${config.extension}`);
    await playable(recording, context);
    console.info(`STORE_BACKGROUND format=${config.format} durationMs=${recording.durationMs} bytes=${recording.sizeBytes}`);
  } finally {
    if (service.getState() === RecordingState.RECORDING || service.getState() === RecordingState.PAUSED) {
      await service.discard();
    }
    if (recording !== undefined) {
      RecordingRepository.permanentlyDelete(context, RecordingRepository.moveToRecentlyDeleted(context, recording));
    }
  }
  expect(libraryIds(context)).assertEqual(before);
}

async function lockedWav(seconds: number): Promise<void> {
  const driver = Driver.create();
  const context = await foregroundContext(driver);
  expect(await PermissionService.ensureMicrophonePermission(context)).assertTrue();
  const before = libraryIds(context);
  const service = RecordingService.getInstance();
  let recording: RecordingInfo | undefined = undefined;
  let screenOffTicks = 0;
  try {
    await service.start(context, RecordingConfig.wav());
    const started = Date.now();
    await driver.pressHome(); await delay(1000);
    if (power.isActive()) { await driver.triggerKey(KeyCode.KEYCODE_POWER); }
    await delay(1000);
    expect(power.isActive()).assertFalse();
    for (let tick = 0; Date.now() - started < seconds * 1000; tick++) {
      await delay(Math.min(5000, Math.max(1, seconds * 1000 - (Date.now() - started))));
      expect(service.getState()).assertEqual(RecordingState.RECORDING);
      if (!power.isActive()) { screenOffTicks++; }
      expect(service.getDuration() >= Math.max(0, Date.now() - started - 7000)).assertTrue();
      if ((tick + 1) % 12 === 0) {
        console.info(`STORE_LOCK_PROGRESS elapsedMs=${Date.now() - started} durationMs=${service.getDuration()} screenOffTicks=${screenOffTicks}`);
      }
    }
    expect(screenOffTicks >= Math.floor(seconds / 5) - 3).assertTrue();
    recording = await service.stop();
    expect(recording !== undefined).assertTrue();
    if (recording === undefined) { throw new Error('Missing saved lock-screen recording'); }
    const metadata = AudioFileUtils.read(recording.filePath, 'wav');
    expect(metadata !== undefined).assertTrue();
    if (metadata === undefined) { throw new Error('Invalid WAV after screen-off recording'); }
    expect(Math.abs(metadata.durationMs - seconds * 1000) < 7000).assertTrue();
    expect(metadata.dataLength > 0 && metadata.dataLength % 2 === 0).assertTrue();
    fileIo.copyFileSync(recording.filePath, `${validationDirectory()}/locked.wav`);
    const report = `{"seconds":${seconds},"elapsedMs":${Date.now() - started},"durationMs":${metadata.durationMs},` +
      `"dataLength":${metadata.dataLength},"screenOffTicks":${screenOffTicks},"bytes":${recording.sizeBytes}}`;
    const reportFile = fileIo.openSync(`${validationDirectory()}/locked-report.json`,
      fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try { fileIo.writeSync(reportFile.fd, report); } finally { fileIo.closeSync(reportFile); }
    console.info(`STORE_LOCK_RESULT ${report}`);
  } finally {
    if (service.getState() === RecordingState.RECORDING || service.getState() === RecordingState.PAUSED) {
      await service.discard();
    }
    if (recording !== undefined) {
      RecordingRepository.permanentlyDelete(context, RecordingRepository.moveToRecentlyDeleted(context, recording));
    }
    await driver.wakeUpDisplay();
  }
  expect(libraryIds(context)).assertEqual(before);
}

// Explicit opt-in only. This suite actually records audio and locks the device;
// it never alters power settings or inspects/deletes pre-existing recordings.
export default function storeValidationTest() {
  const parameters = abilityDelegatorRegistry.getArguments().parameters;
  if ((parameters['storeVisual'] || parameters['-s storeVisual']) === 'true') {
    describe('storePrivacyVisualAcceptance', () => {
      it('shows offline privacy in both orientations without crossing underlying setting controls', 0, async () => {
        const driver = Driver.create();
        await foregroundContext(driver);
        const original = await driver.getDisplayRotation();
        const directory = `${abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir}/store-visuals`;
        if (!fileIo.accessSync(directory)) { fileIo.mkdirSync(directory, true); }
        try {
          for (const rotation of [DisplayRotation.ROTATION_0, DisplayRotation.ROTATION_90]) {
            await driver.setDisplayRotation(rotation); await delay(900);
            await (await driver.waitForComponent(ON.id(`tab-${AppPage.SETTINGS}`), 5000)).click(); await delay(400);
            const privacy = await driver.waitForComponent(ON.id('settings-privacy'), 5000);
            expect(await privacy.isEnabled()).assertTrue();
            await privacy.click(); await delay(700);
            const sheet = await driver.waitForComponent(ON.id('settings-privacy-sheet'), 5000);
            const bounds = await sheet.getBounds(); const displaySize = await driver.getDisplaySize();
            expect(bounds.left >= 0 && bounds.right <= displaySize.x && bounds.bottom <= displaySize.y).assertTrue();
            expect(await driver.findComponent(ON.text('本地处理')) !== null).assertTrue();
            expect(await driver.screenCap(`${directory}/privacy-${rotation}.png`)).assertTrue();
            await driver.pressBack(); await delay(700);
            expect(await driver.findComponent(ON.id('settings-privacy-sheet')) === null).assertTrue();
            expect(await driver.screenCap(`${directory}/settings-${rotation}.png`)).assertTrue();
          }
        } finally {
          if (await driver.findComponent(ON.id('settings-privacy-sheet')) !== null) { await driver.pressBack(); }
          await driver.setDisplayRotation(original);
          const tab = await driver.findComponent(ON.id('tab-0')); if (tab !== null) { await tab.click(); }
        }
      });
      it('opens share-copy cleanup without deleting copies until explicit confirmation', 0, async () => {
        const driver = Driver.create(); await foregroundContext(driver);
        await (await driver.waitForComponent(ON.id(`tab-${AppPage.SETTINGS}`), 5000)).click(); await delay(400);
        await (await driver.waitForComponent(ON.id('settings-clear-pcm'), 5000)).click(); await delay(600);
        const cancel = await driver.findComponent(ON.text('取消'));
        if (cancel !== null) { await cancel.click(); }
        else { expect(await driver.findComponent(ON.id('settings-notice')) !== null).assertTrue(); }
        await delay(300);
        expect(await (await driver.waitForComponent(ON.id('settings-clear-pcm'), 5000)).isEnabled()).assertTrue();
        await (await driver.waitForComponent(ON.id('tab-0'), 5000)).click();
      });
    });
  }
  if ((parameters['storeBackground'] || parameters['-s storeBackground']) !== 'true') { return; }
  const seconds = Number(parameters['lockSeconds'] || parameters['-s lockSeconds'] || '600');
  describe('storeBackgroundAcceptance', () => {
    it('records FLAC in the background then pauses, resumes, saves and plays it', 0, async () => {
      await shortBackground(RecordingConfig.flac());
    });
    it('records M4A in the background then pauses, resumes, saves and plays it', 0, async () => {
      await shortBackground(RecordingConfig.aac(128000));
    });
    if (Number.isFinite(seconds) && seconds >= 60 && seconds <= 1800) {
      it(`records ${seconds} real seconds of WAV with the screen locked`, 0, async () => {
        await lockedWav(seconds);
      });
    }
  });
}
