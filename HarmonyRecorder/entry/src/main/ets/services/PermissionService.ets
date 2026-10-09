import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';

export class PermissionService {
  static readonly MICROPHONE_DENIED_NOTICE: string = '需要麦克风权限，可在“设置 > 麦克风权限”中开启。';

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

  // This is an explicit settings action, never an automatic second prompt after
  // the user has just declined the first permission request.
  static async requestMicrophonePermissionSettings(context: common.UIAbilityContext): Promise<boolean> {
    const permission: Permissions = 'ohos.permission.MICROPHONE';
    const atManager = abilityAccessCtrl.createAtManager();
    if (atManager.getSelfPermissionStatus(permission) === abilityAccessCtrl.PermissionStatus.GRANTED) {
      return true;
    }
    const request = await atManager.requestPermissionsFromUser(context, [permission]);
    if (request.authResults.length > 0 && request.authResults[0] === 0) {
      return true;
    }
    // A newly declined visible dialog ends this action. Previously denied
    // permission no longer shows it; the official settings prompt can then be used.
    if (request.dialogShownResults === undefined || request.dialogShownResults.length === 0 ||
      request.dialogShownResults[0]) {
      return false;
    }
    const result = await atManager.requestPermissionOnSetting(context, [permission]);
    return result.length > 0 && result[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }
}
