import { describe, expect, it } from '@ohos/hypium';
import { TimeUtils } from '../main/ets/utils/TimeUtils';

export default function timeUtilsTest() {
  describe('timeUtilsTest', () => {
    it('formats valid millisecond durations as zero-padded time', 0, () => {
      expect(TimeUtils.formatDuration(0)).assertEqual('00:00:00');
      expect(TimeUtils.formatDuration(999)).assertEqual('00:00:00');
      expect(TimeUtils.formatDuration(61000)).assertEqual('00:01:01');
      expect(TimeUtils.formatDuration(3661000)).assertEqual('01:01:01');
    });

    it('normalizes non-finite duration values', 0, () => {
      expect(TimeUtils.formatDuration(Number.NaN)).assertEqual('00:00:00');
      expect(TimeUtils.formatDuration(Number.POSITIVE_INFINITY)).assertEqual('00:00:00');
      expect(TimeUtils.formatDuration(-1)).assertEqual('00:00:00');
    });

    it('creates and parses the automatic recording file name', 0, () => {
      const timestamp = new Date(2026, 8, 2, 21, 35, 22).getTime();
      const fileName = TimeUtils.createRecordingFileName('wav', timestamp);
      expect(fileName).assertEqual('Recording_20260902_213522.wav');
      expect(TimeUtils.parseTimestampFromFileName(fileName)).assertEqual(timestamp);
      expect(TimeUtils.parseTimestampFromFileName('Recording_20260902_213522_1.wav')).assertEqual(timestamp);
      expect(TimeUtils.parseTimestampFromFileName('Recording_20261302_213522.wav')).assertEqual(0);
    });

    it('creates stable date keys and friendly date section labels', 0, () => {
      const now = new Date(2026, 8, 5, 12, 0, 0).getTime();
      expect(TimeUtils.dateSectionKey(now)).assertEqual('2026-09-05');
      expect(TimeUtils.formatDateSection(now, now)).assertEqual('今天');
      expect(TimeUtils.formatDateSection(new Date(2026, 8, 4, 20, 0, 0).getTime(), now)).assertEqual('昨天');
      expect(TimeUtils.formatDateSection(new Date(2026, 7, 28, 20, 0, 0).getTime(), now)).assertEqual('8月28日');
    });
  });
}
