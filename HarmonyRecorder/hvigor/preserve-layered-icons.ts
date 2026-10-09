import { HvigorNode, HvigorPlugin } from '@ohos/hvigor';
import { OhosHapContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import * as fs from 'fs';
import * as path from 'path';
import { inflateSync, inflateRawSync } from 'zlib';

// SDK 6.1.1 passes an HMS transcoder config even with media.enable=false. Its ImageFilter reduces our
// 1024px PNGs to 512px and changes opaque alpha 255 to 254. Restore the validated source icons in the
// resource tree before packaging; iconCheck and the normal packaging/signing pipeline stay enabled.
// Official lifecycle: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-hvigor-config-ohos-sample
// Official restool config: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/restool

function requirePng(file: Buffer, foreground: boolean): void {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (file.length < 33 || !file.subarray(0, 8).equals(signature) ||
    file.readUInt32BE(16) !== 1024 || file.readUInt32BE(20) !== 1024 ||
    file[24] !== 8 || file[25] !== (foreground ? 6 : 2) || file[28] !== 0) {
    throw new Error('Layered icons must be 1024px 8-bit non-interlaced PNG: RGB background and RGBA foreground.');
  }
  const chunks: Buffer[] = [];
  for (let cursor = 8; cursor < file.length;) {
    const count = file.readUInt32BE(cursor);
    if (cursor + 12 + count > file.length) { throw new Error('Invalid icon PNG chunk.'); }
    if (file.toString('ascii', cursor + 4, cursor + 8) === 'IDAT') {
      chunks.push(file.subarray(cursor + 8, cursor + 8 + count));
    }
    cursor += count + 12;
  }
  const channels = foreground ? 4 : 3;
  const rowBytes = 1024 * channels;
  const decoded = inflateSync(Buffer.concat(chunks), { maxOutputLength: (rowBytes + 1) * 1024 });
  if (decoded.length !== (rowBytes + 1) * 1024) { throw new Error('Invalid icon PNG pixel length.'); }
  let previous = Buffer.alloc(rowBytes);
  let color: Buffer | undefined;
  let transparent = false;
  let opaque = false;
  for (let y = 0; y < 1024; y++) {
    const filter = decoded[y * (rowBytes + 1)];
    if (filter > 4) { throw new Error('Unsupported icon PNG filter.'); }
    const row = Buffer.from(decoded.subarray(y * (rowBytes + 1) + 1, (y + 1) * (rowBytes + 1)));
    for (let x = 0; x < rowBytes; x++) {
      const left = x >= channels ? row[x - channels] : 0;
      const above = previous[x];
      const upperLeft = x >= channels ? previous[x - channels] : 0;
      const predictor = left + above - upperLeft;
      const paeth = Math.abs(predictor - left) <= Math.abs(predictor - above) &&
        Math.abs(predictor - left) <= Math.abs(predictor - upperLeft) ? left :
        (Math.abs(predictor - above) <= Math.abs(predictor - upperLeft) ? above : upperLeft);
      const offset = filter === 1 ? left : filter === 2 ? above :
        filter === 3 ? Math.floor((left + above) / 2) : filter === 4 ? paeth : 0;
      row[x] = (row[x] + offset) & 255;
    }
    for (let x = 0; x < rowBytes; x += channels) {
      if (foreground) { transparent ||= row[x + 3] === 0; opaque ||= row[x + 3] === 255; }
      else {
        if (!color) { color = Buffer.from(row.subarray(x, x + 3)); }
        if (!row.subarray(x, x + 3).equals(color)) { throw new Error('Layered icon background must be one opaque color.'); }
      }
    }
    previous = row;
  }
  if (foreground && (!transparent || !opaque)) { throw new Error('Layered icon foreground must retain transparent and opaque pixels.'); }
}

function verifyIcons(read: (name: string) => Buffer, sourceDirectory: string): void {
  for (const name of ['background.png', 'foreground.png']) {
    const actual = read(name);
    const expected = fs.readFileSync(path.join(sourceDirectory, name));
    requirePng(actual, name === 'foreground.png');
    if (!actual.equals(expected)) {
      throw new Error(`Compiled ${name} differs from its source. Run a clean build and verify the SDK image pipeline.`);
    }
  }
}

// Read two ordinary ZIP entries using Node built-ins. No package is rewritten, and no signing data is read.
function zipEntry(zip: Buffer, wanted: string): Buffer {
  for (let end = zip.length - 22; end >= Math.max(0, zip.length - 65557); end--) {
    if (zip.readUInt32LE(end) !== 0x06054b50) { continue; }
    let cursor = zip.readUInt32LE(end + 16);
    const entries = zip.readUInt16LE(end + 10);
    for (let index = 0; index < entries; index++) {
      if (zip.readUInt32LE(cursor) !== 0x02014b50) { throw new Error('Invalid HAP ZIP directory.'); }
      const nameLength = zip.readUInt16LE(cursor + 28);
      const extraLength = zip.readUInt16LE(cursor + 30);
      const commentLength = zip.readUInt16LE(cursor + 32);
      const name = zip.toString('utf8', cursor + 46, cursor + 46 + nameLength);
      if (name === wanted) {
        const local = zip.readUInt32LE(cursor + 42);
        const method = zip.readUInt16LE(cursor + 10);
        const compressedSize = zip.readUInt32LE(cursor + 20);
        const size = zip.readUInt32LE(cursor + 24);
        const offset = local + 30 + zip.readUInt16LE(local + 26) + zip.readUInt16LE(local + 28);
        const input = zip.subarray(offset, offset + compressedSize);
        if (size > 16 * 1024 * 1024) { throw new Error('Unexpected icon ZIP entry size.'); }
        const bytes = method === 0 ? input : method === 8 ? inflateRawSync(input, { maxOutputLength: size }) : undefined;
        if (!bytes || bytes.length !== size) { throw new Error('Unsupported or invalid icon ZIP entry.'); }
        return bytes;
      }
      cursor += 46 + nameLength + extraLength + commentLength;
    }
    throw new Error(`Missing layered icon in unsigned HAP: ${wanted}`);
  }
  throw new Error('Missing HAP ZIP directory.');
}

export function preserveLayeredIcons(): HvigorPlugin {
  return {
    pluginId: 'facilis.preserve-layered-icons',
    apply(node: HvigorNode): void {
      const context = node.getContext(OhosPluginId.OHOS_HAP_PLUGIN) as OhosHapContext;
      const sourceDirectory = path.resolve(context.getModulePath(), '../AppScope/resources/base/media');
      let targetCount = 0;
      context.targets(targetContext => {
        targetCount += 1;
        const target = targetContext.getTargetName();
        const resourceDirectory = targetContext.getModulePathDetails().getIntermediatesRes();
        // getAllTasks omits lazy tasks in current Hvigor; explicit lookup instantiates the SDK task.
        for (const name of ['CompileResource', 'PackageHap', 'SignHap']) {
          if (!node.getTaskByName(`${target}@${name}`)) {
            throw new Error(`Missing ${target}@${name}; layered icon verification cannot be registered.`);
          }
        }
        node.registerTask({
          name: `${target}@VerifyLayeredIconResources`,
          dependencies: [`${target}@CompileResource`],
          postDependencies: [`${target}@PackageHap`],
          run: () => {
            const config = JSON.parse(fs.readFileSync(path.join(resourceDirectory, 'resConfig.json'), 'utf8'));
            // Preserve the SDK's original check policy, including its test-target policy.
            if (target !== 'ohosTest' && config.iconCheck !== true) {
              throw new Error('Standard main-target iconCheck must remain enabled.');
            }
            for (const name of ['background.png', 'foreground.png']) {
              const source = fs.readFileSync(path.join(sourceDirectory, name));
              requirePng(source, name === 'foreground.png');
              const destination = path.join(resourceDirectory, 'resources/base/media', name);
              if (!fs.existsSync(destination)) { throw new Error(`Compiled icon input is missing: ${name}`); }
              if (!fs.readFileSync(destination).equals(source)) { fs.writeFileSync(destination, source); }
            }
            verifyIcons(name => fs.readFileSync(path.join(resourceDirectory, 'resources/base/media', name)), sourceDirectory);
            console.info(`[layered-icons] ${target}: VerifyLayeredIconResources passed (iconCheck=${config.iconCheck}).`);
          }
        });
        node.registerTask({
          name: `${target}@VerifyPackagedLayeredIcons`,
          dependencies: [`${target}@PackageHap`],
          postDependencies: [`${target}@SignHap`],
          run: () => {
            const output = targetContext.getBuildTargetOutputPath();
            const files = fs.readdirSync(output).filter(name => name.endsWith('-unsigned.hap'));
            if (files.length !== 1) { throw new Error('Expected one unsigned HAP for layered icon verification.'); }
            const hap = fs.readFileSync(path.join(output, files[0]));
            verifyIcons(name => zipEntry(hap, `resources/base/media/${name}`), sourceDirectory);
            console.info(`[layered-icons] ${target}: VerifyPackagedLayeredIcons passed.`);
          }
        });
      });
      if (targetCount === 0) { throw new Error('No build target found; layered icon verification cannot be registered.'); }
    }
  };
}
