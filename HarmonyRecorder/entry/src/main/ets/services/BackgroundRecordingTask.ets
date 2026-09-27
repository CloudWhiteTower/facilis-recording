import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';

// Only an actively capturing, user-started recording owns this task/notification.
export class BackgroundRecordingTask {
  private context: common.Context | undefined = undefined;
  private cancelCallback: ((info: backgroundTaskManager.ContinuousTaskCancelInfo) => void) | undefined = undefined;
  private stopping: boolean = false;

  async start(context: common.Context, onCancelled: () => void): Promise<void> {
    if (this.context !== undefined) {
      return;
    }
    const agent = await wantAgent.getWantAgent({
      wants: [{ bundleName: 'com.example.harmonyrecorder', abilityName: 'EntryAbility' }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 1,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
    const callback = (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
      if (this.context === undefined) {
        return;
      }
      this.context = undefined;
      this.detach();
      console.warn(`Recording background task cancelled: ${info.reason}`);
      if (!this.stopping) {
        onCancelled();
      }
    };
    this.cancelCallback = callback;
    try {
      this.context = context;
      backgroundTaskManager.on('continuousTaskCancel', callback);
      await backgroundTaskManager.startBackgroundRunning(context,
        backgroundTaskManager.BackgroundMode.AUDIO_RECORDING, agent);
    } catch (error) {
      this.context = undefined;
      this.detach();
      throw new Error(`无法开启后台录音任务：${String(error)}`);
    }
  }

  async stop(): Promise<void> {
    const context = this.context;
    if (context === undefined) {
      this.detach();
      return;
    }
    this.stopping = true;
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      this.context = undefined;
      this.detach();
    } catch (error) {
      // Retain context so a later cleanup can retry cancelling this task.
      console.error(`Stop recording background task failed: ${String(error)}`);
      throw new Error(`无法结束后台录音任务：${String(error)}`);
    } finally {
      this.stopping = false;
    }
  }

  private detach(): void {
    if (this.cancelCallback !== undefined) {
      try {
        backgroundTaskManager.off('continuousTaskCancel', this.cancelCallback);
      } catch (error) {
        console.error(`Detach recording task callback failed: ${String(error)}`);
      }
      this.cancelCallback = undefined;
    }
  }
}
