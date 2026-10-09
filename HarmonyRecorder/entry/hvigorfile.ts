// @ts-nocheck – Template file, only used when copied into a project directory
import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import { preserveLayeredIcons } from '../hvigor/preserve-layered-icons';

export default {
  system: hapTasks /* Built-in plugin of Hvigor. It cannot be modified. */,
  plugins: [preserveLayeredIcons()],
};
