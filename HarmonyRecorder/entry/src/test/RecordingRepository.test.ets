import { describe, expect, it } from '@ohos/hypium';
import { RecordingRepository } from '../main/ets/repository/RecordingRepository';
import { ResponsiveLayout } from '../main/ets/utils/ResponsiveLayout';

export default function recordingRepositoryTest() {
  describe('recordingRepositoryTest', () => {
    it('normalizes a user-facing recording name without duplicating its extension', 0, () => {
      expect(RecordingRepository.normalizeDisplayName('  课堂访谈.wav  ', 'wav')).assertEqual('课堂访谈');
      expect(RecordingRepository.normalizeDisplayName('实验记录', 'm4a')).assertEqual('实验记录');
    });

    it('uses the official 600 vp breakpoint for the wide layout', 0, () => {
      expect(ResponsiveLayout.isWide(599)).assertFalse();
      expect(ResponsiveLayout.isWide(600)).assertTrue();
    });
  });
}
