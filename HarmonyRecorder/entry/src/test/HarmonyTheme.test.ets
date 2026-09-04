import { describe, expect, it } from '@ohos/hypium';
import { HarmonyTheme, ThemeMode } from '../main/ets/utils/HarmonyTheme';

export default function harmonyThemeTest() {
  describe('harmonyThemeTest', () => {
    it('provides an orange primary palette for both light and dark modes', 0, () => {
      const light = HarmonyTheme.palette(ThemeMode.LIGHT);
      const dark = HarmonyTheme.palette(ThemeMode.DARK);

      expect(light.primary).assertEqual('#C85A10');
      expect(light.recording).assertEqual('#C85A10');
      expect(dark.primary).assertEqual('#FFB457');
      expect(dark.recording).assertEqual('#FFB457');
      expect(light.pageBackground === dark.pageBackground).assertFalse();
    });
  });
}
