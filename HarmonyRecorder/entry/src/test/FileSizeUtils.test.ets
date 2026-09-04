import { describe, expect, it } from '@ohos/hypium';
import { FileSizeUtils } from '../main/ets/utils/FileSizeUtils';

export default function fileSizeUtilsTest() {
  describe('fileSizeUtilsTest', () => {
    it('formats recording file sizes as MB with one decimal place', 0, () => {
      expect(FileSizeUtils.format(0)).assertEqual('0.0 MB');
      expect(FileSizeUtils.format(1023)).assertEqual('0.0 MB');
      expect(FileSizeUtils.format(1024 * 1024)).assertEqual('1.0 MB');
      expect(FileSizeUtils.format(1536 * 1024)).assertEqual('1.5 MB');
    });
  });
}
