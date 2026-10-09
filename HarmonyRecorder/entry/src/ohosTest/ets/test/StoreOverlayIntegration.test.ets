import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, DisplayRotation } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { RecordingConfig, RecordingInfo } from '../../../main/ets/models/RecordingTypes';
import { RecordingRepository } from '../../../main/ets/repository/RecordingRepository';
import { WaveFileUtils } from '../../../main/ets/utils/WaveFileUtils';

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
}

function fixture(context: common.Context, name: string): RecordingInfo {
  const config = RecordingConfig.wav();
  const path = `${context.cacheDir}/overlay-${Date.now()}.wav`;
  const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  const data = new ArrayBuffer(config.sampleRate * 2 * 3);
  const view = new DataView(data);
  for (let index = 0; index < data.byteLength / 2; index++) {
    view.setInt16(index * 2, Math.round(2000 * Math.sin(index * 2 * Math.PI * 440 / config.sampleRate)), true);
  }
  try {
    fileIo.writeSync(file.fd, WaveFileUtils.createPcmHeader(config, data.byteLength));
    fileIo.writeSync(file.fd, data);
    fileIo.fsyncSync(file.fd);
  } finally { fileIo.closeSync(file); }
  return RecordingRepository.importCompletedFile(context, path, config, name);
}

async function capture(driver: Driver, name: string): Promise<void> {
  const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  const directory = `${context.cacheDir}/store-visuals`;
  if (!fileIo.accessSync(directory)) { fileIo.mkdirSync(directory); }
  expect(await driver.screenCap(`${directory}/${name}.png`)).assertTrue();
}

async function assertConversion(driver: Driver, sheetId: string, oldTitleId: string): Promise<void> {
  await driver.waitForComponent(ON.id('audio-conversion-panel'), 5000);
  // Hidden old branches must be removed, rather than fading over the new controls.
  expect(await driver.findComponent(ON.id(oldTitleId)) === null).assertTrue();
  expect(await driver.findComponent(ON.id('recording_quick_share')) === null).assertTrue();
  const sheet = await driver.waitForComponent(ON.id(sheetId), 5000);
  await sheet.scrollToBottom(1200);
  const bounds = await sheet.getBounds();
  const start = await (await driver.waitForComponent(ON.id('audio-conversion-start'), 5000)).getBounds();
  const back = await (await driver.waitForComponent(ON.id('audio-conversion-back'), 5000)).getBounds();
  expect(start.left >= bounds.left && start.right <= bounds.right && start.bottom <= bounds.bottom).assertTrue();
  expect(back.left >= bounds.left && back.right <= start.left && back.top >= bounds.top).assertTrue();
}

// Independent opt-in: never interacts with historical recordings or registers store accounts.
export default function storeOverlayIntegrationTest() {
  const parameters = abilityDelegatorRegistry.getArguments().parameters;
  if ((parameters['storeOverlay'] || parameters['-s storeOverlay']) !== 'true') { return; }
  describe('storeOverlayIntegration', () => {
    it('switches library conversion and rename views without retained action layers in both orientations', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.example.harmonyrecorder', abilityName: 'EntryAbility' });
      const context = (await delegator.getCurrentTopAbility()).context;
      const driver = Driver.create();
      const original = await driver.getDisplayRotation();
      const before = RecordingRepository.list(context).map((item: RecordingInfo): string => item.id).sort().join('|');
      const name = `Facilis 验收 ${Date.now()}`;
      let recording: RecordingInfo | undefined = undefined;
      try {
        recording = fixture(context, name);
        await (await driver.waitForComponent(ON.id('tab-1'), 5000)).click();
        await (await driver.waitForComponent(ON.id('recordings-search'), 5000)).click();
        await (await driver.waitForComponent(ON.id('recording_search'), 5000)).inputText(name);
        await driver.pressBack(); // Hide the keyboard; keep a uniquely filtered library in every screenshot.
        for (const rotation of [DisplayRotation.ROTATION_0, DisplayRotation.ROTATION_90]) {
          await driver.setDisplayRotation(rotation); await delay(900);
          await (await driver.waitForComponent(ON.id(`recording-more-${recording.fileName}`), 5000)).click();
          await (await driver.waitForComponent(ON.id('library-action-转换格式'), 5000)).click();
          await assertConversion(driver, 'library-actions-sheet', 'library-actions-title');
          await capture(driver, `conversion-library-${rotation}`);
          await (await driver.waitForComponent(ON.id('audio-conversion-back'), 5000)).click();
          await driver.waitForComponent(ON.id('library-actions-title'), 5000);
          expect(await driver.findComponent(ON.id('audio-conversion-panel')) === null).assertTrue();
          await (await driver.waitForComponent(ON.text('重命名'), 5000)).click();
          await driver.waitForComponent(ON.id('library-rename-input'), 5000);
          expect(await driver.findComponent(ON.id('library-action-转换格式')) === null).assertTrue();
          await delay(400);
          await driver.pressBack(); // Keyboard first, then Sheet.
          if (await driver.findComponent(ON.id('library-actions-sheet')) !== null) { await driver.pressBack(); }
          await delay(900);
        }
      } finally {
        if (await driver.findComponent(ON.id('library-actions-sheet')) !== null) { await driver.pressBack(); await delay(900); }
        const close = await driver.findComponent(ON.id('recordings-search-close'));
        if (close !== null) { await close.click(); }
        await driver.setDisplayRotation(original);
        if (recording !== undefined) {
          RecordingRepository.permanentlyDelete(context, RecordingRepository.moveToRecentlyDeleted(context, recording));
        }
        const home = await driver.findComponent(ON.id('tab-0'));
        if (home !== null) { await home.click(); }
      }
      expect(RecordingRepository.list(context).map((item: RecordingInfo): string => item.id).sort().join('|'))
        .assertEqual(before);
    });

    it('keeps player conversion controls separate from actions and dismisses before a native file picker', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.example.harmonyrecorder', abilityName: 'EntryAbility' });
      const context = (await delegator.getCurrentTopAbility()).context;
      const driver = Driver.create();
      const original = await driver.getDisplayRotation();
      let recording: RecordingInfo | undefined = undefined;
      try {
        recording = fixture(context, 'Facilis');
        await (await driver.waitForComponent(ON.id('tab-1'), 5000)).click();
        await (await driver.waitForComponent(ON.id(`recording-open-${recording.fileName}`), 5000)).click();
        await delay(900);
        for (const rotation of [DisplayRotation.ROTATION_0, DisplayRotation.ROTATION_90]) {
          await driver.setDisplayRotation(rotation); await delay(900);
          await (await driver.waitForComponent(ON.id('recording_actions'), 5000)).click();
          await (await driver.waitForComponent(ON.id('player-action-转换格式'), 5000)).click();
          await assertConversion(driver, 'player-actions-sheet', 'player-actions-title');
          await capture(driver, `conversion-player-${rotation}`);
          await (await driver.waitForComponent(ON.id('audio-conversion-back'), 5000)).click();
          await driver.waitForComponent(ON.id('player-actions-title'), 5000);
          expect(await driver.findComponent(ON.id('audio-conversion-panel')) === null).assertTrue();
          await driver.pressBack(); await delay(900);
        }
        await (await driver.waitForComponent(ON.id('recording_actions'), 5000)).click();
        await (await driver.waitForComponent(ON.id('player-action-保存到文件'), 5000)).click();
        await delay(1400);
        expect(await driver.findComponent(ON.id('player-actions-sheet')) === null).assertTrue();
        await driver.pressBack(); await delay(900);
        expect(await driver.waitForComponent(ON.id('player-toggle'), 5000) !== null).assertTrue();
      } finally {
        if (await driver.findComponent(ON.id('player-actions-sheet')) !== null) { await driver.pressBack(); await delay(900); }
        if (await driver.findComponent(ON.id('player-toggle')) !== null) { await driver.pressBack(); await delay(900); }
        await driver.setDisplayRotation(original);
        if (recording !== undefined) {
          RecordingRepository.permanentlyDelete(context, RecordingRepository.moveToRecentlyDeleted(context, recording));
        }
        const home = await driver.findComponent(ON.id('tab-0'));
        if (home !== null) { await home.click(); }
      }
    });
  });
}
