export class TimeUtils {
  static formatDuration(durationMs: number): string {
    if (!isFinite(durationMs) || durationMs <= 0) {
      return '00:00:00';
    }
    const totalSeconds = Math.floor(durationMs / 1000);
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;
    return `${TimeUtils.pad(hours)}:${TimeUtils.pad(minutes)}:${TimeUtils.pad(seconds)}`;
  }

  static formatDateTime(timestamp: number): string {
    if (!isFinite(timestamp) || timestamp <= 0) {
      return '--';
    }
    const date = new Date(timestamp);
    return `${date.getFullYear()}-${TimeUtils.pad(date.getMonth() + 1)}-${TimeUtils.pad(date.getDate())} ` +
      `${TimeUtils.pad(date.getHours())}:${TimeUtils.pad(date.getMinutes())}`;
  }

  static createRecordingFileName(extension: string, timestamp: number): string {
    const date = new Date(timestamp);
    const datePart = `${date.getFullYear()}${TimeUtils.pad(date.getMonth() + 1)}${TimeUtils.pad(date.getDate())}`;
    const timePart = `${TimeUtils.pad(date.getHours())}${TimeUtils.pad(date.getMinutes())}${TimeUtils.pad(date.getSeconds())}`;
    return `Recording_${datePart}_${timePart}.${extension}`;
  }

  static parseTimestampFromFileName(fileName: string): number {
    const name = fileName.substring(0, fileName.lastIndexOf('.'));
    const parts = name.split('_');
    if ((parts.length !== 3 && parts.length !== 4) || parts[1].length !== 8 || parts[2].length !== 6) {
      return 0;
    }
    const year = Number(parts[1].substring(0, 4));
    const month = Number(parts[1].substring(4, 6));
    const day = Number(parts[1].substring(6, 8));
    const hour = Number(parts[2].substring(0, 2));
    const minute = Number(parts[2].substring(2, 4));
    const second = Number(parts[2].substring(4, 6));
    if (isNaN(year) || isNaN(month) || isNaN(day) || isNaN(hour) || isNaN(minute) || isNaN(second) ||
      month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 59) {
      return 0;
    }
    const timestamp = new Date(year, month - 1, day, hour, minute, second).getTime();
    const date = new Date(timestamp);
    if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) {
      return 0;
    }
    return timestamp;
  }

  private static pad(value: number): string {
    return value < 10 ? `0${value}` : value.toString();
  }
}
