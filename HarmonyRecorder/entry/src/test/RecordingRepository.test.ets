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

    it('keeps phone and tablet portrait windows in a single column', 0, () => {
      expect(ResponsiveLayout.usesSplitLayout(360, 780)).assertFalse();
      expect(ResponsiveLayout.usesSplitLayout(800, 1280)).assertFalse();
      expect(ResponsiveLayout.usesSplitLayout(1024, 1366)).assertFalse();
      expect(ResponsiveLayout.usesSplitLayout(800, 800)).assertFalse();
    });

    it('splits landscape windows only when both columns have enough width', 0, () => {
      expect(ResponsiveLayout.usesSplitLayout(780, 360)).assertTrue();
      expect(ResponsiveLayout.usesSplitLayout(1280, 800)).assertTrue();
      expect(ResponsiveLayout.usesSplitLayout(599, 360)).assertFalse();
      expect(ResponsiveLayout.usesSplitLayout(800, 0)).assertFalse();
      expect(ResponsiveLayout.usesSplitLayout(800, Number.NaN)).assertFalse();
      expect(ResponsiveLayout.usesSplitLayout(Number.POSITIVE_INFINITY, 360)).assertFalse();
    });

    it('budgets the recorder stage, controls and floating bar for short windows', 0, () => {
      for (const height of [240, 320, 360, 480, 640, 1280]) {
        for (const split of [false, true]) {
          for (const notice of [false, true]) {
            const waveform = ResponsiveLayout.recorderWaveformHeight(height, split, notice);
            const body = ResponsiveLayout.recorderContentHeight(height, split, notice);
            const occupied = split ? 138 + waveform + 16 + 104 :
              138 + waveform + 16 + 112 + 8 + 104 + (notice ? 80 : 0);
            expect(waveform >= 64 && waveform <= (split ? 220 : 170)).assertTrue();
            expect(body >= height && occupied <= body).assertTrue();
          }
        }
      }
    });

    it('uses finite recorder dimensions before the first area measurement', 0, () => {
      expect(ResponsiveLayout.recorderWaveformHeight(Number.NaN, false)).assertEqual(170);
      expect(ResponsiveLayout.recorderContentHeight(0, true)).assertEqual(640);
      expect(ResponsiveLayout.recorderContentHeight(Number.POSITIVE_INFINITY, false)).assertEqual(640);
    });
  });
}
