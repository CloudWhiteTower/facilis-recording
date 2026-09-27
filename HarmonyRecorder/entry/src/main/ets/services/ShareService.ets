import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';
import { RecordingInfo } from '../models/RecordingTypes';
import { RecordingRepository } from '../repository/RecordingRepository';

export class ShareService {
  static async shareRecording(context: common.UIAbilityContext, recording: RecordingInfo, anchorId: string): Promise<void> {
    const path = RecordingRepository.validateRecordingPath(context, recording);
    await ShareService.shareAudioFile(context, path, recording.fileName, anchorId);
  }

  static async shareAudioFile(context: common.UIAbilityContext, filePath: string, fileName: string,
    anchorId: string): Promise<void> {
    const data = new systemShare.SharedData({
      utd: utd.UniformDataType.AUDIO,
      uri: fileUri.getUriFromPath(filePath),
      title: fileName,
      description: '来自 HarmonyRecorder 的本地录音'
    });
    const controller = new systemShare.ShareController(data);
    await controller.show(context, {
      anchor: anchorId,
      previewMode: systemShare.SharePreviewMode.DETAIL,
      selectionMode: systemShare.SelectionMode.SINGLE
    });
  }
}
