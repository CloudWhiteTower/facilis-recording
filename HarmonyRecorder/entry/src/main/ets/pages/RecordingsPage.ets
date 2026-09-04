import { common } from '@kit.AbilityKit';
import { RecordingInfo } from '../models/RecordingTypes';
import { RecordingRepository } from '../repository/RecordingRepository';
import { ShareService } from '../services/ShareService';
import { FileSizeUtils } from '../utils/FileSizeUtils';
import { HarmonyPalette, HarmonyTheme, ThemeMode, ThemeStore } from '../utils/HarmonyTheme';
import { AppPage, NavigationStore, RecordingSelectionStore } from '../utils/NavigationStore';
import { ResponsiveLayout } from '../utils/ResponsiveLayout';
import { TimeUtils } from '../utils/TimeUtils';

@Component
export struct RecordingsPage {
  @State private recordings: RecordingInfo[] = [];
  @State private recentlyDeleted: RecordingInfo[] = [];
  @State private showingTrash: boolean = false;
  @State private searchQuery: string = '';
  @State private isSearching: boolean = false;
  @State private isSelecting: boolean = false;
  @State private selectedRecordingIds: string[] = [];
  @State private showQuickActions: boolean = false;
  @State private quickActionRecordingId: string = '';
  @State private isQuickRenaming: boolean = false;
  @State private renameValue: string = '';
  @State private isWorking: boolean = false;
  @State private status: string = '';
  @State private isWide: boolean = false;
  @StorageLink(ThemeStore.MODE_KEY) private themeMode: number = ThemeMode.LIGHT;

  aboutToAppear(): void {
    this.loadRecordings();
  }

  build() {
    Column({ space: 0 }) {
      this.pageHeader()
      if (!this.showingTrash) {
        this.libraryToolbar()
      }
      if (this.status.length > 0) {
        Text(this.status)
          .fontSize(13)
          .fontColor(this.palette().danger)
          .width(ResponsiveLayout.contentWidth(this.isWide))
          .padding({
            left: ResponsiveLayout.horizontalPadding(this.isWide),
            right: ResponsiveLayout.horizontalPadding(this.isWide),
            top: 4,
            bottom: 8
          })
      }

      if (this.filteredRecordings().length === 0) {
        Blank().layoutWeight(1)
        this.emptyState()
        Blank().layoutWeight(1)
      } else {
        this.recordingsList()
      }
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(this.palette().pageBackground)
    .onAreaChange((oldValue: Area, newValue: Area): void => {
      this.isWide = ResponsiveLayout.isWide(newValue.width);
    })
    .bindSheet($$this.showQuickActions, this.quickActionsSheet(), {
      height: SheetSize.MEDIUM,
      preferType: SheetType.BOTTOM,
      dragBar: true,
      showClose: false,
      backgroundColor: this.palette().surface,
      onDisappear: (): void => {
        this.isQuickRenaming = false;
        this.renameValue = '';
        this.quickActionRecordingId = '';
      }
    })
  }

  @Builder
  private pageHeader() {
    Row({ space: 8 }) {
      Column({ space: 4 }) {
        Text(this.showingTrash ? '最近删除' : '资料库')
          .fontSize(this.isWide ? 30 : 26)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().textPrimary)
        Text(this.showingTrash ? `${this.recentlyDeleted.length} 条录音` :
          (this.isSelecting ? `${this.selectedRecordingIds.length} 项已选` : `${this.recordings.length} 段录音`))
          .fontSize(13)
          .fontColor(this.palette().textTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.showingTrash) {
        Button() {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(21)
            .fontColor([this.palette().primary])
        }
          .width(40)
          .height(40)
          .backgroundColor('#00000000')
          .borderRadius(20)
          .accessibilityText('完成')
          .onClick((): void => {
            this.showingTrash = false;
            this.status = '';
          })
      }
    }
    .width(ResponsiveLayout.contentWidth(this.isWide))
    .padding({
      left: ResponsiveLayout.horizontalPadding(this.isWide),
      right: ResponsiveLayout.horizontalPadding(this.isWide),
      top: this.isWide ? 30 : 18,
      bottom: 14
    })
  }

  @Builder
  private libraryToolbar() {
    Row({ space: 10 }) {
      if (this.isSearching) {
        Search({ value: this.searchQuery, placeholder: '搜索录音' })
          .id('recording_search')
          .layoutWeight(1)
          .height(44)
          .fontColor(this.palette().textPrimary)
          .placeholderColor(this.palette().textTertiary)
          .searchIcon({ size: 18, color: this.palette().textSecondary })
          .cancelButton({
            style: CancelButtonStyle.CONSTANT,
            icon: { size: 18, color: this.palette().textSecondary }
          })
          .backgroundColor(this.palette().surfaceSubtle)
          .borderRadius(16)
          .defaultFocus(true)
          .onChange((value: string): void => {
            this.searchQuery = value;
          })
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(19)
            .fontColor([this.palette().textSecondary])
        }
          .width(44)
          .height(44)
          .backgroundColor(this.palette().surface)
          .borderRadius(16)
          .accessibilityText('关闭搜索')
          .onClick((): void => {
            this.isSearching = false;
            this.searchQuery = '';
          })
      } else if (this.isSelecting) {
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(19)
            .fontColor([this.palette().textSecondary])
        }
          .width(44)
          .height(44)
          .backgroundColor(this.palette().surface)
          .borderRadius(16)
          .accessibilityText('退出多选')
          .onClick((): void => {
            this.leaveSelectionMode();
          })
        Blank().layoutWeight(1)
        Button() {
          SymbolGlyph($r('sys.symbol.checkmark_square'))
            .fontSize(21)
            .fontColor([this.palette().primary])
        }
          .width(44)
          .height(44)
          .backgroundColor(this.palette().primarySubtle)
          .borderRadius(16)
          .accessibilityText('全选当前录音')
          .onClick((): void => {
            this.toggleSelectAllFiltered();
          })
        Button() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(20)
            .fontColor([this.palette().danger])
        }
          .width(44)
          .height(44)
          .backgroundColor(this.palette().dangerSubtle)
          .borderRadius(16)
          .enabled(this.selectedRecordingIds.length > 0 && !this.isWorking)
          .opacity(this.selectedRecordingIds.length > 0 ? 1 : 0.38)
          .accessibilityText('将所选录音移至最近删除')
          .onClick((): void => {
            this.confirmMoveSelectedToTrash();
          })
      } else {
        Button() {
          SymbolGlyph($r('sys.symbol.checkmark_square_on_square'))
            .fontSize(21)
            .fontColor([this.palette().textPrimary])
        }
          .width(44)
          .height(44)
          .backgroundColor(this.palette().surface)
          .borderRadius(16)
          .enabled(this.recordings.length > 0)
          .opacity(this.recordings.length > 0 ? 1 : 0.38)
          .accessibilityText('多选录音')
          .onClick((): void => {
            this.isSelecting = true;
            this.selectedRecordingIds = [];
          })
        Button() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(20)
            .fontColor([this.palette().textPrimary])
        }
          .width(44)
          .height(44)
          .backgroundColor(this.palette().surface)
          .borderRadius(16)
          .accessibilityText('搜索录音')
          .onClick((): void => {
            this.isSearching = true;
          })
        Blank().layoutWeight(1)
      }
    }
    .width(ResponsiveLayout.contentWidth(this.isWide))
    .padding({
      left: ResponsiveLayout.horizontalPadding(this.isWide),
      right: ResponsiveLayout.horizontalPadding(this.isWide),
      bottom: 10
    })
  }

  @Builder
  private recordingsList() {
    List({ space: 0 }) {
      if (this.filteredRecordings().length > 0) {
        ListItem() {
          Text(this.showingTrash ? '已删除录音' : '按时间')
            .fontSize(13)
            .fontColor(this.palette().textTertiary)
            .width('100%')
            .padding({ top: 8, bottom: 6 })
        }
      }

      ForEach(this.filteredRecordings(), (recording: RecordingInfo) => {
        ListItem() {
          this.recordingListItem(recording)
        }
      }, (recording: RecordingInfo): string => recording.id)

      if (!this.showingTrash && this.searchQuery.length === 0 && !this.isSearching && !this.isSelecting) {
        ListItem() {
          this.recentlyDeletedEntry()
        }
      }
    }
    .width(ResponsiveLayout.contentWidth(this.isWide))
    .layoutWeight(1)
    .padding({
      left: ResponsiveLayout.horizontalPadding(this.isWide),
      right: ResponsiveLayout.horizontalPadding(this.isWide),
      bottom: 28
    })
    .scrollBar(BarState.Off)
  }

  @Builder
  private recordingListItem(recording: RecordingInfo) {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        if (this.isSelecting && !this.showingTrash) {
          Checkbox({ name: recording.id })
            .width(24)
            .height(24)
            .margin(0)
            .select(this.isRecordingSelected(recording.id))
            .selectedColor(this.palette().primary)
            .unselectedColor(this.palette().textTertiary)
            .shape(CheckBoxShape.CIRCLE)
            .accessibilityText(`选择${recording.displayName}`)
            .onChange((selected: boolean): void => {
              this.setRecordingSelected(recording.id, selected);
            })
        }

        Row({ space: 12 }) {
          Column({ space: 5 }) {
            Text(recording.displayName)
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.showingTrash ? `删除于 ${TimeUtils.formatDateTime(recording.deletedAt)}` :
              `${TimeUtils.formatDateTime(recording.createdAt)} · ${recording.config.formatLabel}`)
              .fontSize(13)
              .fontColor(this.palette().textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Column({ space: 5 }) {
            Text(TimeUtils.formatDuration(recording.durationMs))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().textPrimary)
            Text(FileSizeUtils.format(recording.sizeBytes))
              .fontSize(12)
              .fontColor(this.palette().textTertiary)
          }
          .alignItems(HorizontalAlign.End)
        }
        .layoutWeight(1)
        .onClick((): void => {
          if (this.isSelecting && !this.showingTrash) {
            this.toggleRecordingSelection(recording.id);
          } else if (!this.showingTrash) {
            RecordingSelectionStore.select(recording);
            NavigationStore.open(AppPage.PLAYER);
          }
        })

        if (!this.showingTrash && !this.isSelecting) {
          Button() {
            SymbolGlyph($r('sys.symbol.ellipsis_circle'))
              .fontSize(21)
              .fontColor([this.palette().textSecondary])
              .rotate({ angle: 90 })
          }
            .width(40)
            .height(40)
            .backgroundColor('#00000000')
            .borderRadius(20)
            .accessibilityText(`${recording.displayName}的更多操作`)
            .onClick((): void => {
              this.openQuickActions(recording);
            })
        }
      }
      .width('100%')

      if (this.showingTrash) {
        Row({ space: 8 }) {
          Button() {
            SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
              .fontSize(18)
              .fontColor([this.palette().primary])
          }
            .width(38)
            .height(38)
            .backgroundColor(this.palette().primarySubtle)
            .borderRadius(19)
            .accessibilityText('恢复录音')
            .onClick((): void => {
              this.restoreRecording(recording);
            })
          Button() {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(18)
              .fontColor([this.palette().danger])
          }
            .width(38)
            .height(38)
            .backgroundColor('#00000000')
            .borderRadius(19)
            .accessibilityText('永久删除录音')
            .onClick((): void => {
              this.confirmPermanentDeletion(recording);
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
      }

      Divider().color(this.palette().divider)
    }
    .width('100%')
    .padding({ top: 14, bottom: 4 })
  }

  @Builder
  private quickActionsSheet() {
    Column({ space: 10 }) {
      Text(this.isQuickRenaming ? '重命名' : this.quickActionDisplayName())
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 8, bottom: 8 })

      if (this.isQuickRenaming) {
        TextInput({ text: this.renameValue, placeholder: '录音名称' })
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontColor(this.palette().textPrimary)
          .placeholderColor(this.palette().textTertiary)
          .backgroundColor(this.palette().surfaceSubtle)
          .border({ width: 1, color: this.palette().primaryBorder })
          .borderRadius(14)
          .defaultFocus(true)
          .maxLength(80)
          .onChange((value: string): void => {
            this.renameValue = value;
          })
        Row({ space: 10 }) {
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(20)
              .fontColor([this.palette().textSecondary])
          }
            .layoutWeight(1)
            .height(44)
            .backgroundColor(this.palette().surfaceSubtle)
            .borderRadius(16)
            .accessibilityText('取消重命名')
            .onClick((): void => {
              this.isQuickRenaming = false;
            })
          Button() {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(20)
              .fontColor([this.palette().onPrimary])
          }
            .layoutWeight(1)
            .height(44)
            .backgroundColor(this.palette().primary)
            .borderRadius(16)
            .enabled(this.renameValue.trim().length > 0 && !this.isWorking)
            .accessibilityText('保存名称')
            .onClick((): void => {
              this.saveQuickRename();
            })
        }
        .width('100%')
      } else {
        Button() {
          Row({ space: 14 }) {
            SymbolGlyph($r('sys.symbol.share'))
              .fontSize(21)
              .fontColor([this.palette().primary])
            Text('分享原始文件')
              .fontSize(16)
              .fontColor(this.palette().textPrimary)
            Blank()
          }
          .width('100%')
        }
          .id('recording_quick_share')
          .width('100%')
          .height(52)
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.palette().surfaceSubtle)
          .borderRadius(16)
          .enabled(!this.isWorking)
          .onClick((): void => {
            this.shareQuickRecording();
          })
        Button() {
          Row({ space: 14 }) {
            SymbolGlyph($r('sys.symbol.square_and_pencil'))
              .fontSize(21)
              .fontColor([this.palette().primary])
            Text('重命名')
              .fontSize(16)
              .fontColor(this.palette().textPrimary)
            Blank()
          }
          .width('100%')
        }
          .width('100%')
          .height(52)
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.palette().surfaceSubtle)
          .borderRadius(16)
          .enabled(!this.isWorking)
          .onClick((): void => {
            this.renameValue = this.quickActionDisplayName();
            this.isQuickRenaming = true;
          })
        Button() {
          Row({ space: 14 }) {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(21)
              .fontColor([this.palette().danger])
            Text('移至最近删除')
              .fontSize(16)
              .fontColor(this.palette().danger)
            Blank()
          }
          .width('100%')
        }
          .width('100%')
          .height(52)
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.palette().dangerSubtle)
          .borderRadius(16)
          .enabled(!this.isWorking)
          .onClick((): void => {
            this.confirmMoveQuickRecordingToTrash();
          })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 10, bottom: 30 })
    .backgroundColor(this.palette().surface)
  }

  @Builder
  private recentlyDeletedEntry() {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 4 }) {
          Text('最近删除')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().textPrimary)
          Text(this.recentlyDeleted.length > 0 ? `${this.recentlyDeleted.length} 条可恢复录音` : '没有可恢复录音')
            .fontSize(13)
            .fontColor(this.palette().textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(19)
          .fontColor([this.palette().primary])
      }
      .width('100%')
      Divider().color(this.palette().divider)
    }
    .width('100%')
    .padding({ top: 18, bottom: 4 })
    .onClick((): void => {
      this.showingTrash = true;
      this.status = '';
    })
  }

  @Builder
  private emptyState() {
    Column({ space: 10 }) {
      Text(this.showingTrash ? '最近删除为空' :
        (this.searchQuery.trim().length > 0 ? '没有匹配的录音' : '还没有录音'))
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette().textPrimary)
      if (!this.showingTrash && this.recordings.length === 0) {
        Button() {
          SymbolGlyph($r('sys.symbol.mic_fill'))
            .fontSize(22)
            .fontColor([this.palette().onPrimary])
        }
          .width(52)
          .height(52)
          .backgroundColor(this.palette().primary)
          .borderRadius(26)
          .accessibilityText('开始录音')
          .onClick((): void => {
            NavigationStore.open(AppPage.RECORDER);
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  private isRecordingSelected(recordingId: string): boolean {
    return this.selectedRecordingIds.includes(recordingId);
  }

  private setRecordingSelected(recordingId: string, selected: boolean): void {
    const nextIds = this.selectedRecordingIds.filter((id: string): boolean => id !== recordingId);
    if (selected) {
      nextIds.push(recordingId);
    }
    this.selectedRecordingIds = nextIds;
  }

  private toggleRecordingSelection(recordingId: string): void {
    this.setRecordingSelected(recordingId, !this.isRecordingSelected(recordingId));
  }

  private leaveSelectionMode(): void {
    this.isSelecting = false;
    this.selectedRecordingIds = [];
  }

  private toggleSelectAllFiltered(): void {
    const visibleRecordings = this.filteredRecordings();
    let allSelected = visibleRecordings.length > 0;
    for (let index = 0; index < visibleRecordings.length; index++) {
      if (!this.isRecordingSelected(visibleRecordings[index].id)) {
        allSelected = false;
        break;
      }
    }
    if (allSelected) {
      const visibleIds = visibleRecordings.map((recording: RecordingInfo): string => recording.id);
      this.selectedRecordingIds = this.selectedRecordingIds.filter((id: string): boolean => !visibleIds.includes(id));
      return;
    }
    const nextIds = this.selectedRecordingIds.slice();
    for (let index = 0; index < visibleRecordings.length; index++) {
      const recordingId = visibleRecordings[index].id;
      if (!nextIds.includes(recordingId)) {
        nextIds.push(recordingId);
      }
    }
    this.selectedRecordingIds = nextIds;
  }

  private openQuickActions(recording: RecordingInfo): void {
    this.quickActionRecordingId = recording.id;
    this.renameValue = recording.displayName;
    this.isQuickRenaming = false;
    this.showQuickActions = true;
  }

  private quickActionRecording(): RecordingInfo | undefined {
    for (let index = 0; index < this.recordings.length; index++) {
      if (this.recordings[index].id === this.quickActionRecordingId) {
        return this.recordings[index];
      }
    }
    return undefined;
  }

  private quickActionDisplayName(): string {
    const recording = this.quickActionRecording();
    return recording === undefined ? '录音操作' : recording.displayName;
  }

  private async shareQuickRecording(): Promise<void> {
    const recording = this.quickActionRecording();
    if (recording === undefined) {
      this.status = '录音已不可用';
      this.showQuickActions = false;
      return;
    }
    this.isWorking = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await ShareService.shareRecording(context, recording, 'recording_quick_share');
      this.status = '';
    } catch (error) {
      this.status = '无法打开分享面板';
    } finally {
      this.isWorking = false;
    }
  }

  private saveQuickRename(): void {
    const recording = this.quickActionRecording();
    if (recording === undefined) {
      this.status = '录音已不可用';
      this.showQuickActions = false;
      return;
    }
    this.isWorking = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      RecordingRepository.rename(context, recording, this.renameValue);
      this.showQuickActions = false;
      this.loadRecordings();
    } catch (error) {
      this.status = '重命名失败';
    } finally {
      this.isWorking = false;
    }
  }

  private confirmMoveQuickRecordingToTrash(): void {
    const recording = this.quickActionRecording();
    if (recording === undefined) {
      this.status = '录音已不可用';
      this.showQuickActions = false;
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '移至最近删除？',
      message: `“${recording.displayName}”仍可在最近删除中恢复。`,
      buttons: [
        { text: '取消', color: this.palette().textSecondary },
        { text: '移除', color: this.palette().danger }
      ]
    }).then((result): void => {
      if (result.index === 1) {
        this.moveQuickRecordingToTrash(recording);
      }
    }).catch((error: Error): void => {
      this.status = '无法打开确认窗口';
    });
  }

  private moveQuickRecordingToTrash(recording: RecordingInfo): void {
    this.isWorking = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      RecordingRepository.moveToRecentlyDeleted(context, recording);
      this.showQuickActions = false;
      this.loadRecordings();
    } catch (error) {
      this.status = '移至最近删除失败';
    } finally {
      this.isWorking = false;
    }
  }

  private confirmMoveSelectedToTrash(): void {
    const selectedCount = this.selectedRecordingIds.length;
    if (selectedCount === 0) {
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: `移除 ${selectedCount} 段录音？`,
      message: '所选录音仍可在最近删除中恢复。',
      buttons: [
        { text: '取消', color: this.palette().textSecondary },
        { text: '移除', color: this.palette().danger }
      ]
    }).then((result): void => {
      if (result.index === 1) {
        this.moveSelectedToTrash();
      }
    }).catch((error: Error): void => {
      this.status = '无法打开确认窗口';
    });
  }

  private moveSelectedToTrash(): void {
    this.isWorking = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      for (let index = 0; index < this.selectedRecordingIds.length; index++) {
        const recording = this.findRecordingById(this.selectedRecordingIds[index]);
        if (recording !== undefined) {
          RecordingRepository.moveToRecentlyDeleted(context, recording);
        }
      }
      this.leaveSelectionMode();
      this.loadRecordings();
    } catch (error) {
      this.leaveSelectionMode();
      this.loadRecordings();
      this.status = '部分录音移动失败';
    } finally {
      this.isWorking = false;
    }
  }

  private findRecordingById(recordingId: string): RecordingInfo | undefined {
    for (let index = 0; index < this.recordings.length; index++) {
      if (this.recordings[index].id === recordingId) {
        return this.recordings[index];
      }
    }
    return undefined;
  }

  private filteredRecordings(): RecordingInfo[] {
    const source = this.showingTrash ? this.recentlyDeleted : this.recordings;
    const query = this.searchQuery.trim().toLowerCase();
    if (query.length === 0) {
      return source;
    }
    return source.filter((recording: RecordingInfo): boolean => {
      return recording.displayName.toLowerCase().includes(query) ||
        recording.config.formatLabel.toLowerCase().includes(query);
    });
  }

  private palette(): HarmonyPalette {
    return HarmonyTheme.palette(this.themeMode);
  }

  private loadRecordings(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.recordings = RecordingRepository.list(context);
      this.recentlyDeleted = RecordingRepository.listRecentlyDeleted(context);
      this.status = '';
    } catch (error) {
      this.recordings = [];
      this.recentlyDeleted = [];
      this.status = '读取本地录音失败';
    }
  }

  private restoreRecording(recording: RecordingInfo): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const restored = RecordingRepository.restore(context, recording);
      this.loadRecordings();
      this.status = `已恢复“${restored.displayName}”`;
    } catch (error) {
      this.status = '恢复录音失败';
    }
  }

  private confirmPermanentDeletion(recording: RecordingInfo): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '永久删除录音？',
      message: `“${recording.displayName}”将从本机移除，且无法恢复。`,
      buttons: [
        { text: '取消', color: this.palette().textSecondary },
        { text: '永久删除', color: this.palette().danger }
      ]
    }).then((result): void => {
      if (result.index === 1) {
        this.permanentlyDelete(recording);
      }
    }).catch((error: Error): void => {
      this.status = '无法打开确认窗口';
    });
  }

  private permanentlyDelete(recording: RecordingInfo): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      RecordingRepository.permanentlyDelete(context, recording);
      this.loadRecordings();
      this.status = '录音已永久删除';
    } catch (error) {
      this.status = '永久删除失败';
    }
  }
}
