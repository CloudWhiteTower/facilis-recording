import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { fileIo } from '@kit.CoreFileKit';
import codec from 'libfacilis_flac.so';
import { RecordingConfig, RecordingFormat, RecordingInfo } from '../../../main/ets/models/RecordingTypes';
import { RecordingRepository } from '../../../main/ets/repository/RecordingRepository';
import { AudioConversionService } from '../../../main/ets/services/AudioConversionService';
import { WaveFileUtils } from '../../../main/ets/utils/WaveFileUtils';
import { AudioFileUtils } from '../../../main/ets/utils/AudioFileUtils';

function directory(): string {
  const result = `${abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir}/conversion-tests`;
  if (!fileIo.accessSync(result)) { fileIo.mkdirSync(result, true); }
  return result;
}

function writeAll(fd: number, bytes: ArrayBuffer): void {
  let cursor = 0;
  while (cursor < bytes.byteLength) {
    const count = fileIo.writeSync(fd, bytes.slice(cursor));
    if (count <= 0) { throw new Error('Fixture write failed'); }
    cursor += count;
  }
}

function waveFixture(rate: number, depth: number, samples: number, baseDir: string = directory()): string {
  const path = `${baseDir}/source_${rate}_${depth}_${samples}.wav`;
  const config = RecordingConfig.wav(rate, depth);
  const bytes = new ArrayBuffer(samples * depth / 8);
  const view = new DataView(bytes);
  for (let index = 0; index < samples; index++) {
    if (depth === 16) {
      view.setInt16(index * 2, index % 97 === 0 ? -32768 :
        Math.round(Math.sin(index * 0.082) * 24000), true);
    } else {
      const value = Math.round(Math.sin(index * 0.082) * 7000000) | 1;
      view.setUint8(index * 3, value & 255);
      view.setUint8(index * 3 + 1, (value >> 8) & 255);
      view.setUint8(index * 3 + 2, (value >> 16) & 255);
    }
  }
  const output = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  try {
    writeAll(output.fd, WaveFileUtils.createPcmHeader(config, bytes.byteLength));
    writeAll(output.fd, bytes);
    if (bytes.byteLength % 2 !== 0) { writeAll(output.fd, new ArrayBuffer(1)); }
    fileIo.fsyncSync(output.fd);
  } finally { fileIo.closeSync(output); }
  return path;
}

async function convert(sourcePath: string, outputName: string, format: string, depth: number = 16): Promise<string> {
  const outputPath = `${directory()}/${outputName}`;
  const source = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
  const output = fileIo.openSync(outputPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  let handle = 0;
  try {
    handle = await codec.conversionCreate(source.fd, fileIo.statSync(source.fd).size, output.fd, format, 256000, depth);
    const result = await codec.conversionRun(handle);
    expect(result.durationMs > 0).assertTrue();
    expect(result.channels).assertEqual(1);
    expect(codec.conversionProgress(handle) >= 0.99).assertTrue();
    await codec.conversionRelease(handle);
    handle = 0;
    fileIo.fsyncSync(output.fd);
    const metadata = AudioFileUtils.read(outputPath, format);
    expect(metadata !== undefined).assertTrue();
    if (metadata !== undefined) {
      expect(metadata.config.sampleRate).assertEqual(result.sampleRate);
      expect(metadata.config.bitDepth).assertEqual(result.bitDepth);
    }
    console.info(`CONVERSION_FIXTURE ${sourcePath} -> ${outputPath} samples=${result.durationMs * result.sampleRate / 1000}`);
    return outputPath;
  } finally {
    if (handle > 0) { await codec.conversionRelease(handle); }
    fileIo.closeSync(source);
    fileIo.closeSync(output);
  }
}

function comparePcm(original: string, result: string): void {
  const firstMetadata = AudioFileUtils.read(original, 'wav');
  const secondMetadata = AudioFileUtils.read(result, 'wav');
  expect(firstMetadata !== undefined && secondMetadata !== undefined).assertTrue();
  if (firstMetadata === undefined || secondMetadata === undefined) { return; }
  expect(secondMetadata.dataLength).assertEqual(firstMetadata.dataLength);
  const first = fileIo.openSync(original, fileIo.OpenMode.READ_ONLY);
  const second = fileIo.openSync(result, fileIo.OpenMode.READ_ONLY);
  try {
    const a = new Uint8Array(firstMetadata.dataLength);
    const b = new Uint8Array(secondMetadata.dataLength);
    expect(fileIo.readSync(first.fd, a.buffer, { offset: firstMetadata.dataOffset })).assertEqual(a.byteLength);
    expect(fileIo.readSync(second.fd, b.buffer, { offset: secondMetadata.dataOffset })).assertEqual(b.byteLength);
    let equal = a.byteLength === b.byteLength;
    for (let index = 0; equal && index < a.byteLength; index++) { equal = a[index] === b[index]; }
    expect(equal).assertTrue();
  } finally { fileIo.closeSync(first); fileIo.closeSync(second); }
}

export default function conversionIntegrationTest() {
  const parameters = abilityDelegatorRegistry.getArguments().parameters;
  const uiFile = parameters['conversionUiFile'] || parameters['-s conversionUiFile'] || '';
  if (uiFile.length > 0) {
    describe('audioFileActionsUi', () => {
      it('opens conversion choices and the system save picker without changing the recording', 0, async () => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator();
        const driver = Driver.create();
        const cacheDir = delegator.getAppContext().cacheDir;
        await delegator.startAbility({ bundleName: 'com.example.harmonyrecorder', abilityName: 'EntryAbility' });
        await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 1200); });
        await (await driver.findComponent(ON.id('tab-1'))).click();
        await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 600); });
        await (await driver.findComponent(ON.id(`recording-more-${uiFile}`))).click();
        await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 500); });
        await (await driver.findComponent(ON.text('转换格式'))).click();
        await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 400); });
        expect(await driver.findComponent(ON.id('audio-conversion-wav')) !== null).assertTrue();
        expect(await driver.findComponent(ON.id('audio-conversion-start')) !== null).assertTrue();
        expect(await driver.screenCap(`${cacheDir}/audio-conversion-panel.png`)).assertTrue();
        await driver.pressBack();
        await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 500); });
        await (await driver.findComponent(ON.id(`recording-more-${uiFile}`))).click();
        await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 500); });
        await (await driver.findComponent(ON.text('保存到文件'))).click();
        const saveButton = await driver.waitForComponent(ON.text('保存'), 8000);
        expect(await driver.screenCap(`${cacheDir}/audio-save-picker.png`)).assertTrue();
        expect(saveButton !== null).assertTrue();
        if (parameters['saveCopy'] === 'true' || parameters['-s saveCopy'] === 'true') {
          const extension = uiFile.substring(uiFile.lastIndexOf('.') + 1);
          const exportName = `Facilis_ExportCheck_${Date.now()}.${extension}`;
          await (await driver.findComponent(ON.text(uiFile))).inputText(exportName);
          // Editing the native picker replaces accessibility nodes; reacquire it.
          await driver.screenCap(`${cacheDir}/export-named.png`);
          // The tablet floating keyboard covers the picker Save button.
          await driver.pressBack();
          await (await driver.waitForComponent(ON.text('保存'), 5000)).click();
          expect(await driver.waitForComponent(ON.text('已保存到所选位置，原始录音已保留'), 10000) !== null).assertTrue();
          console.info(`EXPORT_UI_COPY ${exportName}`);
        } else { await driver.pressBack(); }
      });
    });
  }
  if (parameters['conversion'] !== 'true' && parameters['-s conversion'] !== 'true') { return; }
  describe('nativeAudioConversion', () => {
    it('registers a converted file through the production service and preserves the original', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.example.harmonyrecorder', abilityName: 'EntryAbility' });
      // This end-to-end service fixture uses the runner's isolated module library.
      const context = (await delegator.getCurrentTopAbility()).context;
      const fixture = waveFixture(48000, 16, 6017, context.cacheDir);
      const owned: RecordingInfo[] = [];
      try {
        const original = RecordingRepository.importCompletedFile(context, fixture, RecordingConfig.wav(),
          'ConversionCheck_Source');
        owned.push(original);
        const converted = await new AudioConversionService().convert(context, original, RecordingFormat.FLAC,
          256000, (progress: number): void => {});
        expect(converted !== undefined).assertTrue();
        if (converted !== undefined) {
          owned.push(converted);
          expect(RecordingRepository.list(context).some((item: RecordingInfo): boolean =>
            item.id === converted.id)).assertTrue();
          expect(RecordingRepository.inspectRecording(context, converted).config.format).assertEqual(RecordingFormat.FLAC);
        }
        expect(fileIo.statSync(original.filePath).size).assertEqual(original.sizeBytes);
        expect(RecordingRepository.inspectRecording(context, original).durationMs).assertEqual(original.durationMs);
      } finally {
        // Only remove recordings created by this test; historical files are never selected.
        for (const item of owned) {
          RecordingRepository.permanentlyDelete(context, RecordingRepository.moveToRecentlyDeleted(context, item));
        }
      }
    });
    it('roundtrips 48 kHz WAV through FLAC without changing PCM samples', 0, async () => {
      const source = waveFixture(48000, 16, 48037);
      const flac = await convert(source, 'roundtrip_48000.flac', 'flac');
      const wav = await convert(flac, 'roundtrip_48000.wav', 'wav');
      comparePcm(source, wav);
      const aac = await convert(flac, 'from_flac_48000.m4a', 'm4a');
      await convert(aac, 'from_aac_48000.wav', 'wav');
    });
    it('roundtrips 44.1 kHz WAV through FLAC and converts AAC to FLAC', 0, async () => {
      const source = waveFixture(44100, 16, 44137);
      const flac = await convert(source, 'roundtrip_44100.flac', 'flac');
      const wav = await convert(flac, 'roundtrip_44100.wav', 'wav');
      comparePcm(source, wav);
      const aac = await convert(source, 'from_wav_44100.m4a', 'm4a');
      await convert(aac, 'from_aac_44100.flac', 'flac');
    });
    it('preserves 24 bit WAV including odd padding and encodes AAC', 0, async () => {
      const source = waveFixture(48000, 24, 48037);
      const wav = await convert(source, 'preserved_24.wav', 'wav', 24);
      comparePcm(source, wav);
      const aac = await convert(source, 'from_24bit.m4a', 'm4a');
      await convert(aac, 'decoded_24bit_aac.wav', 'wav');
    });
    it('cancels native conversion and releases descriptors without touching source', 0, async () => {
      const sourcePath = waveFixture(48000, 16, 48000);
      const source = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
      const output = fileIo.openSync(`${directory()}/cancelled.flac`,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      let handle = 0;
      try {
        const size = fileIo.statSync(source.fd).size;
        handle = await codec.conversionCreate(source.fd, size, output.fd, 'flac', 256000, 16);
        const run = codec.conversionRun(handle);
        codec.conversionCancel(handle);
        let cancelled = false;
        try { await run; } catch (error) { cancelled = true; }
        expect(cancelled).assertTrue();
        expect(fileIo.statSync(source.fd).size).assertEqual(size);
      } finally {
        if (handle > 0) { await codec.conversionRelease(handle); }
        fileIo.closeSync(source);
        fileIo.closeSync(output);
      }
    });
  });
}
