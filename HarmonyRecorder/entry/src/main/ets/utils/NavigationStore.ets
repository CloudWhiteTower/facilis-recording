import { RecordingInfo } from '../models/RecordingTypes';

export enum AppPage {
  RECORDER = 0,
  RECORDINGS = 1,
  PLAYER = 2,
  SETTINGS = 3
}

export class NavigationStore {
  static readonly PAGE_KEY = 'harmony_recorder_current_page';
  static readonly ACTIVE_RECORDING_KEY = 'harmony_recorder_active_recording';
  static readonly FOREGROUND_KEY = 'harmony_recorder_foreground';

  static initialize(): void {
    if (!AppStorage.has(NavigationStore.PAGE_KEY)) {
      AppStorage.setOrCreate(NavigationStore.PAGE_KEY, AppPage.RECORDER);
    }
    if (!AppStorage.has(NavigationStore.ACTIVE_RECORDING_KEY)) {
      AppStorage.setOrCreate(NavigationStore.ACTIVE_RECORDING_KEY, false);
    }
  }

  static open(page: AppPage): void {
    if (AppStorage.get<AppPage>(NavigationStore.PAGE_KEY) !== page) {
      AppStorage.setOrCreate(NavigationStore.PAGE_KEY, page);
    }
  }

  static setRecordingActive(active: boolean): void {
    if (AppStorage.get<boolean>(NavigationStore.ACTIVE_RECORDING_KEY) !== active) {
      AppStorage.setOrCreate(NavigationStore.ACTIVE_RECORDING_KEY, active);
    }
  }
}

export class RecordingSelectionStore {
  private static selectedRecording: RecordingInfo = RecordingInfo.placeholder();

  static select(recording: RecordingInfo): void {
    RecordingSelectionStore.selectedRecording = recording;
  }

  static getSelected(): RecordingInfo {
    return RecordingSelectionStore.selectedRecording;
  }
}
