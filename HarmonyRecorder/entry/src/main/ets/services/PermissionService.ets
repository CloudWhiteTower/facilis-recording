import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';

export class PermissionService {
  static async ensureMicrophonePermission(context: common.UIAbilityContext): Promise<boolean> {
    const permission: Permissions = 'ohos.permission.MICROPHONE';
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const status = atManager.getSelfPermissionStatus(permission);
      if (status === abilityAccessCtrl.PermissionStatus.GRANTED) {
        return true;
      }
      const result = await atManager.requestPermissionsFromUser(context, [permission]);
      return result.authResults.length > 0 && result.authResults[0] === 0;
    } catch (error) {
      console.error(`Request microphone permission failed: ${String(error)}`);
      return false;
    }
  }
}
