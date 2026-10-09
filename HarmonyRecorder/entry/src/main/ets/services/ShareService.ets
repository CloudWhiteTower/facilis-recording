import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';
import { RecordingInfo } from '../models/RecordingTypes';
import { RecordingRepository } from '../repository/RecordingRepository';
import { ExportService } from './ExportService';

export class ShareService {
  static async shareRecording(context: common.UIAbilityContext, recording: RecordingInfo, anchorId: string): Promise<void> {
    const path = RecordingRepository.validateRecordingPath(context, recording);
    await ShareService.shareAudioFile(context, path, recording.fileName, anchorId);
  }

  static async shareAudioFile(context: common.UIAbilityContext, filePath: string, fileName: string,
    anchorId: string): Promise<void> {
    const releaseCopy = await ExportService.retainPcmShareCopy(context, filePath);
    let controller: systemShare.ShareController | undefined = undefined;
    const onDismiss = (): void => {
      releaseCopy();
      if (controller !== undefined) {
        try { controller.off('dismiss', onDismiss); }
        catch (error) { console.error(`Remove share dismiss listener failed: ${String(error)}`); }
      }
    };
    try {
      const data = new systemShare.SharedData({
        utd: utd.UniformDataType.AUDIO,
        uri: fileUri.getUriFromPath(filePath),
        title: fileName,
        description: '来自 HarmonyRecorder 的本地录音'
      });
      controller = new systemShare.ShareController(data);
      controller.on('dismiss', onDismiss);
      await controller.show(context, {
        anchor: anchorId,
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
      // Neither successful presentation nor dismiss proves that a receiving app finished reading.
      // The dedicated PCM cache retains a grace period; no file is removed here.
    } catch (error) {
      onDismiss();
      throw new Error((error as Error).message || String(error));
    }
  }
}
