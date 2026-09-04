export class FileSizeUtils {
  static format(bytes: number): string {
    const safeBytes = Number.isFinite(bytes) && bytes > 0 ? bytes : 0;
    return `${(safeBytes / (1024 * 1024)).toFixed(1)} MB`;
  }
}
