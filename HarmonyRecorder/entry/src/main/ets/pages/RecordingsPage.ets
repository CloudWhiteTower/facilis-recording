import { common } from '@kit.AbilityKit';
import { TextRole, VisualTheme } from '../utils/VisualTheme';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  HdsNavigation,
  HdsNavigationMenuItemOptions,
  HdsNavigationTitleMode,
  ScrollEffectType
} from '@kit.UIDesignKit';
import { RecordingInfo } from '../models/RecordingTypes';
import { AudioConversionPanel } from '../components/AudioConversionPanel';
import { ExportService } from '../services/ExportService';
import { RecordingBatchAction, RecordingRepository } from '../repository/RecordingRepository';
import { ShareService } from '../services/ShareService';
import { FileSizeUtils } from '../utils/FileSizeUtils';
import { HarmonyPalette, HarmonyTheme, HarmonyTokens, ThemeMode, ThemeStore } from '../utils/HarmonyTheme';
import { MaterialRole, MaterialTheme } from '../utils/MaterialTheme';
import { MotionTheme } from '../utils/MotionTheme';
import { PressFeedback } from '../utils/PressFeedback';
import { AppPage, NavigationStore, RecordingSelectionStore } from '../utils/NavigationStore';
import { ResponsiveLayout } from '../utils/ResponsiveLayout';
import { TimeUtils } from '../utils/TimeUtils';

class RecordingLibraryRow {
  readonly key: string;
  readonly label: string;
  readonly recording: RecordingInfo;

  constructor(key: string, label: string, recording: RecordingInfo = RecordingInfo.placeholder()) {
    this.key = key;
    this.label = label;
    this.recording = recording;
  }

  get isHeader(): boolean {
    return this.recording.id.length === 0;
  }
}

@Component
export struct RecordingsPage {
  @Prop @Watch('onVisibilityChanged') isVisible: boolean = false;
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
  @State private showingConversion: boolean = false;
  @State private conversionRecording: RecordingInfo = RecordingInfo.placeholder();
  @State private unreadableCount: number = 0;
  @State private renameValue: string = '';
  @State private isWorking: boolean = false;
  @State private isConfirming: boolean = false;
  @State private status: string = '';
  @State private isWide: boolean = false;
  @State private availableWidth: number = 360;
  @State private availableHeight: number = 640;
  @StorageLink(ThemeStore.MODE_KEY) private themeMode: number = ThemeMode.LIGHT;
  @StorageLink(MotionTheme.REDUCE_KEY) private reduceMotion: boolean = false;
  private pendingTrashConfirmation: RecordingInfo[] = [];
  private filteredSource: RecordingInfo[] | undefined = undefined;
  private filteredQuery: string = '';
  private filteredCache: RecordingInfo[] = [];
  private rowsSource: RecordingInfo[] | undefined = undefined;
  private rowsKey: string = '';
  private rowsCache: RecordingLibraryRow[] = [];

  aboutToAppear(): void {
    if (this.isVisible) { this.loadRecordings(); }
  }

  private onVisibilityChanged(): void {
    if (this.isVisible) {
      this.loadRecordings();
    }
  }

  build() {
    HdsNavigation() {
      Column({ space: 0 }) {
        if (this.isSearching || this.isSelecting) {
          this.libraryToolbar()
        }
        if (this.status.length > 0) {
          Text(this.status)
            .attributeModifier(VisualTheme.text(TextRole.CAPTION))
            .fontColor(HarmonyTokens.danger())
            .width(ResponsiveLayout.contentWidth(this.isWide))
            .constraintSize({ maxWidth: 920 })
            .padding({
              left: ResponsiveLayout.horizontalPadding(this.isWide),
              right: ResponsiveLayout.horizontalPadding(this.isWide),
              top: 4,
              bottom: 8
            })
            .transition(MotionTheme.appear(this.reduceMotion))
        }
        if (this.unreadableCount > 0) {
          Text(`${this.unreadableCount} 个录音文件不完整或无法识别；原文件已保留，可在详情查看错误。`)
            .attributeModifier(VisualTheme.text(TextRole.CAPTION)).fontColor(HarmonyTokens.textSecondary())
            .width(ResponsiveLayout.contentWidth(this.isWide)).constraintSize({ maxWidth: 920 })
            .padding({ left: ResponsiveLayout.horizontalPadding(this.isWide),
              right: ResponsiveLayout.horizontalPadding(this.isWide), bottom: 8 })
        }

        this.recordingsList()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(HarmonyTokens.pageBackground())
    }
    .width('100%')
    .height('100%')
    .titleBar({
      content: {
        title: {
          mainTitle: this.showingTrash ? '最近删除' : '资料库',
          subTitle: this.librarySubtitle()
        },
        menu: {
          value: this.navigationMenu(),
          maxCount: 2
        }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        systemMaterialEffect: MaterialTheme.resolve(MaterialRole.NAVIGATION)
      },
      enableComponentSafeArea: true
    })
    .mode(NavigationMode.Stack)
    .titleMode(ResponsiveLayout.usesSplitLayout(this.availableWidth, this.availableHeight) ?
      HdsNavigationTitleMode.MINI : HdsNavigationTitleMode.FULL)
    .hideBackButton(true)
    .backgroundColor(HarmonyTokens.pageBackground())
    .onAreaChange((oldValue: Area, newValue: Area): void => {
      this.isWide = ResponsiveLayout.isWide(newValue.width);
      const width = Number(newValue.width);
      const height = Number(newValue.height);
      if (Number.isFinite(width) && width > 0 && Math.abs(width - this.availableWidth) >= 1) {
        this.availableWidth = width;
      }
      if (Number.isFinite(height) && height > 0 && Math.abs(height - this.availableHeight) >= 1) {
        this.availableHeight = height;
      }
    })
    .bindSheet($$this.showQuickActions, this.quickActionsSheet(), {
      height: this.isWide ? Math.min(560, Math.max(180, this.availableHeight - 80)) : SheetSize.LARGE,
      width: this.isWide ? Math.min(560, this.availableWidth - 48) : '100%',
      preferType: this.isWide ? SheetType.CENTER : SheetType.BOTTOM,
      dragBar: true,
      showClose: false,
      backgroundColor: HarmonyTokens.glassSurface(),
      blurStyle: BlurStyle.COMPONENT_THICK,
      onDisappear: (): void => {
        this.onQuickActionsDismissed();
      }
    })
  }

  private librarySubtitle(): string {
    if (this.isSelecting) {
      return `${this.selectedRecordingIds.length} 项已选`;
    }
    if (this.showingTrash) {
      return `${this.recentlyDeleted.length} 条录音`;
    }
    return `${this.recordings.length} 段录音`;
  }

  private navigationMenu(): HdsNavigationMenuItemOptions[] {
    // Keep HDS menu nodes alive through their native touch-up/icon feedback handlers.
    // API24 can crash when the currently clicked title-bar menu is removed synchronously.
    const enabled = this.canUseNavigationMenu();
    if (this.showingTrash) {
      return [{
        content: {
          icon: $r('sys.symbol.checkmark_square_on_square'),
          label: '多选最近删除',
          isEnabled: this.recentlyDeleted.length > 0 && enabled,
          action: (): void => {
            this.enterSelectionMode();
          }
        }
      }, {
        content: {
          icon: $r('sys.symbol.checkmark'),
          label: '完成',
          isEnabled: enabled,
          action: (): void => {
            if (!this.canUseNavigationMenu()) {
              return;
            }
            this.getUIContext().animateTo(MotionTheme.content(), (): void => {
              this.showingTrash = false;
              this.status = '';
            });
          }
        }
      }];
    }
    return [
      {
        content: {
          icon: $r('sys.symbol.checkmark_square_on_square'),
          label: '多选录音',
          isEnabled: this.recordings.length > 0 && enabled,
          action: (): void => {
            this.enterSelectionMode();
          }
        }
      },
      {
        content: {
          icon: $r('sys.symbol.magnifyingglass'),
          label: '搜索录音',
          isEnabled: enabled,
          action: (): void => {
            if (!this.canUseNavigationMenu()) {
              return;
            }
            this.getUIContext().animateTo(MotionTheme.content(), (): void => {
              this.isSearching = true;
            });
          }
        }
      }
    ];
  }

  private canUseNavigationMenu(): boolean {
    return !this.isSearching && !this.isSelecting && !this.isWorking && !this.isConfirming;
  }

  @Builder
  private libraryToolbar() {
    Column() {
      Row({ space: 8 }) {
        if (this.isSearching) {
          Search({ value: this.searchQuery, placeholder: '搜索录音' })
            .id('recording_search')
            .layoutWeight(1)
            .height(VisualTheme.CONTROL_HEIGHT)
            .textFont({ size: VisualTheme.BODY_SIZE })
            .placeholderFont({ size: VisualTheme.BODY_SIZE })
            .fontColor(HarmonyTokens.textPrimary())
            .placeholderColor(HarmonyTokens.textTertiary())
            .searchIcon({ size: VisualTheme.ICON_TOOL, color: HarmonyTokens.textSecondary() })
            .cancelButton({
              style: CancelButtonStyle.CONSTANT,
              icon: { size: VisualTheme.ICON_TOOL, color: HarmonyTokens.textSecondary() }
            })
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .defaultFocus(true)
            .onChange((value: string): void => {
              this.getUIContext().animateTo(MotionTheme.content(), (): void => {
                this.searchQuery = value;
              });
            })
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(VisualTheme.ICON_TOOL)
              .fontColor([HarmonyTokens.textSecondary()])
          }
          .width(VisualTheme.CONTROL_HEIGHT)
          .height(VisualTheme.CONTROL_HEIGHT)
          .backgroundColor(Color.Transparent)
          .borderRadius(22)
          .accessibilityText('关闭搜索')
          .animation(undefined)
          .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
          .animation(MotionTheme.press(this.reduceMotion))
          .onClick((): void => {
            this.getUIContext().animateTo(MotionTheme.content(), (): void => {
              this.isSearching = false;
              this.searchQuery = '';
            });
          })
        } else {
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(VisualTheme.ICON_TOOL)
              .fontColor([HarmonyTokens.textSecondary()])
          }
          .width(VisualTheme.CONTROL_HEIGHT)
          .height(VisualTheme.CONTROL_HEIGHT)
          .backgroundColor(Color.Transparent)
          .borderRadius(22)
          .accessibilityText('退出多选')
          .enabled(!this.isWorking && !this.isConfirming)
          .animation(undefined)
          .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
          .animation(MotionTheme.press(this.reduceMotion))
          .onClick((): void => {
            this.leaveSelectionMode();
          })
          Blank().layoutWeight(1)
          Button() {
            SymbolGlyph($r('sys.symbol.checkmark_square'))
              .fontSize(VisualTheme.ICON_TOOL)
              .fontColor([HarmonyTokens.primary()])
          }
          .width(VisualTheme.CONTROL_HEIGHT)
          .height(VisualTheme.CONTROL_HEIGHT)
          .backgroundColor(HarmonyTokens.primarySubtle())
          .borderRadius(22)
          .accessibilityText('全选当前录音')
          .enabled(!this.isWorking && !this.isConfirming)
          .animation(undefined)
          .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
          .animation(MotionTheme.press(this.reduceMotion))
          .onClick((): void => {
            this.toggleSelectAllFiltered();
          })
          if (this.showingTrash) {
            Button() {
              SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
                .fontSize(VisualTheme.ICON_TOOL)
                .fontColor([HarmonyTokens.primary()])
            }
            .width(VisualTheme.CONTROL_HEIGHT)
            .height(VisualTheme.CONTROL_HEIGHT)
            .backgroundColor(HarmonyTokens.primarySubtle())
            .borderRadius(22)
            .enabled(this.selectedRecordingIds.length > 0 && !this.isWorking && !this.isConfirming)
            .accessibilityText('恢复所选录音')
            .animation(undefined)
            .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
            .animation(MotionTheme.press(this.reduceMotion))
            .onClick((): void => {
              this.confirmBatch(this.selectedRecordings(), RecordingBatchAction.RESTORE);
            })
          }
          Button() {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(VisualTheme.ICON_TOOL)
              .fontColor([HarmonyTokens.danger()])
          }
          .width(VisualTheme.CONTROL_HEIGHT)
          .height(VisualTheme.CONTROL_HEIGHT)
          .backgroundColor(HarmonyTokens.dangerSubtle())
          .borderRadius(22)
          .enabled(this.selectedRecordingIds.length > 0 && !this.isWorking && !this.isConfirming)
          .opacity(this.selectedRecordingIds.length > 0 ? 1 : 0.38)
          .accessibilityText(this.showingTrash ? '永久删除所选录音' : '将所选录音移至最近删除')
          .animation(undefined)
          .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
          .animation(MotionTheme.press(this.reduceMotion))
          .onClick((): void => {
            this.confirmBatch(this.selectedRecordings(), this.showingTrash ?
              RecordingBatchAction.PERMANENTLY_DELETE : RecordingBatchAction.MOVE_TO_TRASH);
          })
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 6, right: 6 })
      .attributeModifier(MaterialTheme.surface(MaterialRole.CONTROL, this.themeMode))
      .borderRadius(28)
    }
    .width(ResponsiveLayout.contentWidth(this.isWide))
      .constraintSize({ maxWidth: 920 })
    .padding({
      left: ResponsiveLayout.horizontalPadding(this.isWide),
      right: ResponsiveLayout.horizontalPadding(this.isWide),
      bottom: 8
    })
    .transition(MotionTheme.appear(this.reduceMotion))
  }

  @Builder
  private recordingsList() {
    List({ space: 0 }) {
      // Flatten date headers and recordings: stable group keys must not retain an old nested data array.
      ForEach(this.libraryRows(), (row: RecordingLibraryRow) => {
        ListItem() {
          if (row.isHeader) {
            this.dateGroupHeader(row.label)
          } else {
            this.recordingListItem(row.recording)
          }
        }
        .transition(MotionTheme.appear(this.reduceMotion))
      }, (row: RecordingLibraryRow): string => row.key)

      if (this.filteredRecordings().length === 0) {
        ListItem() {
          this.emptyState()
        }
        .height(ResponsiveLayout.usesSplitLayout(this.availableWidth, this.availableHeight) ?
          Math.min(240, Math.max(160, this.availableHeight - 240)) : 240)
        .transition(MotionTheme.appear(this.reduceMotion))
      }

      if (!this.showingTrash && this.searchQuery.length === 0 && !this.isSearching && !this.isSelecting) {
        ListItem() {
          this.recentlyDeletedEntry()
        }
        .transition(MotionTheme.appear(this.reduceMotion))
      }
    }
    .width(ResponsiveLayout.contentWidth(this.isWide))
      .constraintSize({ maxWidth: 920 })
    .id('recordings-list')
    .layoutWeight(1)
    .padding({
      left: ResponsiveLayout.horizontalPadding(this.isWide),
      right: ResponsiveLayout.horizontalPadding(this.isWide),
      bottom: 112
    })
    .scrollBar(BarState.Off)
  }

  @Builder
  private dateGroupHeader(label: string) {
    Text(label)
      .width('100%')
      .attributeModifier(VisualTheme.text(TextRole.METADATA, true))
      .fontColor(HarmonyTokens.textTertiary())
      .padding({ top: 12, bottom: 6 })
      .backgroundColor(HarmonyTokens.pageBackground())
  }

  @Builder
  private recordingListItem(recording: RecordingInfo) {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        if (this.isSelecting) {
          Checkbox({ name: recording.id })
            .width(VisualTheme.CONTROL_HEIGHT)
            .height(VisualTheme.CONTROL_HEIGHT)
            .padding(10)
            .margin(0)
            .select(this.isRecordingSelected(recording.id))
            .selectedColor(HarmonyTokens.primary())
            .unselectedColor(HarmonyTokens.textTertiary())
            .shape(CheckBoxShape.CIRCLE)
            .accessibilityText(`选择${recording.displayName}`)
            .enabled(!this.isWorking && !this.isConfirming)
            .transition(MotionTheme.appear(this.reduceMotion))
            .onChange((selected: boolean): void => {
              this.setRecordingSelected(recording.id, selected);
            })
        }

        Row({ space: 12 }) {
          Column({ space: 5 }) {
            Text(recording.displayName)
              .attributeModifier(VisualTheme.text(TextRole.BODY, true))
              .fontColor(HarmonyTokens.textPrimary())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.showingTrash ? `删除于 ${TimeUtils.formatDateTime(recording.deletedAt)}` :
              `${TimeUtils.formatDateTime(recording.createdAt)} · ${recording.config.formatLabel}`)
              .attributeModifier(VisualTheme.text(TextRole.METADATA))
              .fontColor(HarmonyTokens.textSecondary())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Column({ space: 5 }) {
            Text(TimeUtils.formatDuration(recording.durationMs))
              .attributeModifier(VisualTheme.text(TextRole.METADATA, true, true))
              .fontColor(HarmonyTokens.textPrimary())
            Text(FileSizeUtils.format(recording.sizeBytes))
              .attributeModifier(VisualTheme.text(TextRole.CAPTION, false, true))
              .fontColor(HarmonyTokens.textTertiary())
          }
          .alignItems(HorizontalAlign.End)
        }
        .layoutWeight(1)
        .onClick((): void => {
          if (this.isWorking || this.isConfirming) {
            return;
          }
          if (this.isSelecting) {
            this.toggleRecordingSelection(recording.id);
          } else if (!this.showingTrash) {
            RecordingSelectionStore.select(recording);
            NavigationStore.open(AppPage.PLAYER);
          }
        })

        if (!this.showingTrash && !this.isSelecting) {
          Button() {
            SymbolGlyph($r('sys.symbol.ellipsis_circle'))
              .fontSize(VisualTheme.ICON_TOOL)
              .fontColor([HarmonyTokens.textSecondary()])
              .rotate({ angle: 90 })
          }
            .width(VisualTheme.CONTROL_HEIGHT)
            .height(VisualTheme.CONTROL_HEIGHT)
            .backgroundColor('#00000000')
            .borderRadius(20)
            .accessibilityText(`${recording.displayName}的更多操作`)
            .id(`recording-more-${recording.fileName}`)
            .enabled(!this.isWorking && !this.isConfirming)
            .transition(MotionTheme.appear(this.reduceMotion))
            .animation(undefined)
            .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
            .animation(MotionTheme.press(this.reduceMotion))
            .onClick((): void => {
              this.openQuickActions(recording);
            })
        }
      }
      .width('100%')

      if (this.showingTrash && !this.isSelecting) {
        Row({ space: 8 }) {
          Button() {
            SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
              .fontSize(VisualTheme.ICON_TOOL)
              .fontColor([HarmonyTokens.primary()])
          }
            .width(VisualTheme.CONTROL_HEIGHT)
            .height(VisualTheme.CONTROL_HEIGHT)
            .backgroundColor(HarmonyTokens.primarySubtle())
            .borderRadius(19)
            .accessibilityText('恢复录音')
            .enabled(!this.isWorking && !this.isConfirming)
            .animation(undefined)
            .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
            .animation(MotionTheme.press(this.reduceMotion))
            .onClick((): void => {
              this.confirmBatch([recording], RecordingBatchAction.RESTORE);
            })
          Button() {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(VisualTheme.ICON_TOOL)
              .fontColor([HarmonyTokens.danger()])
          }
            .width(VisualTheme.CONTROL_HEIGHT)
            .height(VisualTheme.CONTROL_HEIGHT)
            .backgroundColor('#00000000')
            .borderRadius(19)
            .accessibilityText('永久删除录音')
            .enabled(!this.isWorking && !this.isConfirming)
            .animation(undefined)
            .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
            .animation(MotionTheme.press(this.reduceMotion))
            .onClick((): void => {
              this.confirmBatch([recording], RecordingBatchAction.PERMANENTLY_DELETE);
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .transition(MotionTheme.appear(this.reduceMotion))
      }

      Divider().color(HarmonyTokens.divider())
    }
    .width('100%')
    .padding({ top: 14, bottom: 4 })
  }

  @Builder
  private quickActionsSheet() {
    Scroll() {
      Column({ space: 10 }) {
        if (this.showingConversion) {
          AudioConversionPanel({
            recording: this.conversionRecording,
            onRunning: (running: boolean): void => { this.isWorking = running; },
            onBack: (): void => { this.showingConversion = false; },
            onComplete: (converted: RecordingInfo): void => {
              this.showQuickActions = false;
              this.loadRecordings(true);
              this.status = `已添加 ${converted.fileName}，原件已保留`;
            }
          })
        } else {
        Text(this.isQuickRenaming ? '重命名' : this.quickActionDisplayName())
          .width('100%')
          .attributeModifier(VisualTheme.text(TextRole.TITLE, true))
          .fontColor(HarmonyTokens.textPrimary())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 8, bottom: 8 })

        if (this.isQuickRenaming) {
          TextInput({ text: this.renameValue, placeholder: '录音名称' })
            .width('100%')
            .height(VisualTheme.INPUT_HEIGHT)
            .fontSize(VisualTheme.BODY_SIZE)
            .fontColor(HarmonyTokens.textPrimary())
            .placeholderColor(HarmonyTokens.textTertiary())
            .backgroundColor(HarmonyTokens.surfaceSubtle())
            .border({ width: 1, color: HarmonyTokens.primaryBorder() })
            .borderRadius(16)
            .defaultFocus(true)
            .maxLength(80)
            .transition(MotionTheme.appear(this.reduceMotion))
            .onChange((value: string): void => {
              this.renameValue = value;
            })
          Row({ space: 10 }) {
            Button() {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(VisualTheme.ICON_TOOL)
                .fontColor([HarmonyTokens.textSecondary()])
            }
              .layoutWeight(1)
              .height(VisualTheme.CONTROL_HEIGHT)
              .backgroundColor(HarmonyTokens.surfaceSubtle())
              .borderRadius(16)
              .accessibilityText('取消重命名')
              .animation(undefined)
              .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
              .animation(MotionTheme.press(this.reduceMotion))
              .onClick((): void => {
                this.getUIContext().animateTo(MotionTheme.content(), (): void => {
                  this.isQuickRenaming = false;
                });
              })
            Button() {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(VisualTheme.ICON_TOOL)
                .fontColor([HarmonyTokens.onPrimary()])
            }
              .layoutWeight(1)
              .height(VisualTheme.CONTROL_HEIGHT)
              .backgroundColor(HarmonyTokens.primary())
              .borderRadius(16)
              .enabled(this.renameValue.trim().length > 0 && !this.isWorking && !this.isConfirming)
              .accessibilityText('保存名称')
              .animation(undefined)
              .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
              .animation(MotionTheme.press(this.reduceMotion))
              .onClick((): void => {
                this.saveQuickRename();
              })
          }
          .width('100%')
          .transition(MotionTheme.appear(this.reduceMotion))
        } else {
          this.quickFileAction($r('sys.symbol.arrow_down'), '保存到文件', (): void => { this.saveQuickToDevice(); })
          this.quickFileAction($r('sys.symbol.waveform'), '转换格式', (): void => {
            const recording = this.quickActionRecording();
            if (recording !== undefined) {
              this.conversionRecording = recording;
              this.showingConversion = true;
            }
          })
          Button() {
            Row({ space: 14 }) {
              SymbolGlyph($r('sys.symbol.share'))
                .fontSize(VisualTheme.ICON_TOOL)
                .fontColor([HarmonyTokens.primary()])
              Text('分享原始文件')
                .attributeModifier(VisualTheme.text(TextRole.BODY))
                .fontColor(HarmonyTokens.textPrimary())
              Blank()
            }
            .width('100%')
          }
            .id('recording_quick_share')
            .width('100%')
            .height(VisualTheme.ACTION_HEIGHT)
            .padding({ left: 16, right: 16 })
            .backgroundColor(HarmonyTokens.surfaceSubtle())
            .borderRadius(16)
            .enabled(!this.isWorking && !this.isConfirming)
            .transition(MotionTheme.appear(this.reduceMotion))
            .animation(undefined)
            .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
            .animation(MotionTheme.press(this.reduceMotion))
            .onClick((): void => {
              this.shareQuickRecording();
            })
          Button() {
            Row({ space: 14 }) {
              SymbolGlyph($r('sys.symbol.square_and_pencil'))
                .fontSize(VisualTheme.ICON_TOOL)
                .fontColor([HarmonyTokens.primary()])
              Text('重命名')
                .attributeModifier(VisualTheme.text(TextRole.BODY))
                .fontColor(HarmonyTokens.textPrimary())
              Blank()
            }
            .width('100%')
          }
            .width('100%')
            .height(VisualTheme.ACTION_HEIGHT)
            .padding({ left: 16, right: 16 })
            .backgroundColor(HarmonyTokens.surfaceSubtle())
            .borderRadius(16)
            .enabled(!this.isWorking && !this.isConfirming)
            .transition(MotionTheme.appear(this.reduceMotion))
            .animation(undefined)
            .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
            .animation(MotionTheme.press(this.reduceMotion))
            .onClick((): void => {
              this.renameValue = this.quickActionDisplayName();
              this.getUIContext().animateTo(MotionTheme.content(), (): void => {
                this.isQuickRenaming = true;
              });
            })
          Button() {
            Row({ space: 14 }) {
              SymbolGlyph($r('sys.symbol.trash'))
                .fontSize(VisualTheme.ICON_TOOL)
                .fontColor([HarmonyTokens.danger()])
              Text('移至最近删除')
                .attributeModifier(VisualTheme.text(TextRole.BODY))
                .fontColor(HarmonyTokens.danger())
              Blank()
            }
            .width('100%')
          }
            .width('100%')
            .height(VisualTheme.ACTION_HEIGHT)
            .padding({ left: 16, right: 16 })
            .backgroundColor(HarmonyTokens.dangerSubtle())
            .borderRadius(16)
            .enabled(!this.isWorking && !this.isConfirming)
            .transition(MotionTheme.appear(this.reduceMotion))
            .animation(undefined)
            .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
            .animation(MotionTheme.press(this.reduceMotion))
            .onClick((): void => {
              this.confirmMoveQuickRecordingToTrash();
            })
        }
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 10, bottom: 30 })
      .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Auto)
  }

  @Builder
  private quickFileAction(symbol: Resource, title: string, action: () => void) {
    Button() {
      Row({ space: 14 }) {
        SymbolGlyph(symbol)
          .fontSize(VisualTheme.ICON_TOOL)
          .fontColor([HarmonyTokens.primary()])
        Text(title)
          .attributeModifier(VisualTheme.text(TextRole.BODY))
          .fontColor(HarmonyTokens.textPrimary())
        Blank()
      }
      .width('100%')
    }
      .width('100%').height(VisualTheme.ACTION_HEIGHT).padding({ left: 16, right: 16 })
      .backgroundColor(HarmonyTokens.surfaceSubtle()).borderRadius(16)
      .enabled(!this.isWorking && !this.isConfirming)
      .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
      .onClick(action)
  }

  private async saveQuickToDevice(): Promise<void> {
    if (this.isWorking || this.isConfirming) { return; }
    const recording = this.quickActionRecording();
    if (recording === undefined) { return; }
    this.isWorking = true;
    this.showQuickActions = false;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const destination = await ExportService.saveToDevice(context, recording);
      this.status = destination === undefined ? '' : '已保存到所选位置，原始录音已保留';
    } catch (error) {
      this.status = (error as Error).message || '保存到文件失败';
    } finally { this.isWorking = false; }
  }

  @Builder
  private recentlyDeletedEntry() {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 4 }) {
          Text('最近删除')
            .attributeModifier(VisualTheme.text(TextRole.BODY, true))
            .fontColor(HarmonyTokens.textPrimary())
          Text(this.recentlyDeleted.length > 0 ? `${this.recentlyDeleted.length} 条可恢复录音` : '没有可恢复录音')
            .attributeModifier(VisualTheme.text(TextRole.METADATA))
            .fontColor(HarmonyTokens.textSecondary())
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(VisualTheme.ICON_TOOL)
          .fontColor([HarmonyTokens.primary()])
      }
      .width('100%')
      Divider().color(HarmonyTokens.divider())
    }
    .width('100%')
    .padding({ top: 18, bottom: 4 })
    .onClick((): void => {
      if (this.isWorking || this.isConfirming) {
        return;
      }
      this.getUIContext().animateTo(MotionTheme.content(), (): void => {
        this.showingTrash = true;
        this.status = '';
      });
    })
  }

  @Builder
  private emptyState() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.waveform'))
        .fontSize(VisualTheme.ICON_EMPTY)
        .fontColor([HarmonyTokens.textTertiary()])
      Text(this.showingTrash ? '最近删除为空' :
        (this.searchQuery.trim().length > 0 ? '没有匹配的录音' : '还没有录音'))
        .attributeModifier(VisualTheme.text(TextRole.BODY, true))
        .fontColor(HarmonyTokens.textPrimary())
      if (!this.showingTrash && this.recordings.length === 0) {
        Button() {
          SymbolGlyph($r('sys.symbol.mic_fill'))
            .fontSize(VisualTheme.ICON_SECONDARY)
            .fontColor([HarmonyTokens.onPrimary()])
        }
          .width(VisualTheme.SECONDARY_BUTTON)
          .height(VisualTheme.SECONDARY_BUTTON)
          .backgroundColor(HarmonyTokens.primary())
          .borderRadius(VisualTheme.SECONDARY_BUTTON / 2)
          .accessibilityText('开始录音')
          .animation(undefined)
          .attributeModifier(PressFeedback.button(this.themeMode, this.reduceMotion))
          .animation(MotionTheme.press(this.reduceMotion))
          .onClick((): void => {
            NavigationStore.open(AppPage.RECORDER);
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .transition(MotionTheme.appear(this.reduceMotion))
  }

  private isRecordingSelected(recordingId: string): boolean {
    return this.selectedRecordingIds.includes(recordingId);
  }

  private setRecordingSelected(recordingId: string, selected: boolean): void {
    if (this.isWorking || this.isConfirming) {
      return;
    }
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
    if (this.isWorking || this.isConfirming) {
      return;
    }
    this.getUIContext().animateTo(MotionTheme.content(), (): void => {
      this.isSelecting = false;
      this.selectedRecordingIds = [];
    });
  }

  private enterSelectionMode(): void {
    if (!this.canUseNavigationMenu()) {
      return;
    }
    this.getUIContext().animateTo(MotionTheme.content(), (): void => {
      this.isSelecting = true;
      this.selectedRecordingIds = [];
    });
  }

  private toggleSelectAllFiltered(): void {
    if (this.isWorking || this.isConfirming) {
      return;
    }
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
    if (this.isWorking || this.isConfirming) {
      return;
    }
    this.quickActionRecordingId = recording.id;
    this.renameValue = recording.displayName;
    this.isQuickRenaming = false;
    this.showQuickActions = true;
  }

  private quickActionRecording(): RecordingInfo | undefined {
    const recordings = this.recordings;
    const selectedId = this.quickActionRecordingId;
    for (let index = 0; index < recordings.length; index++) {
      if (recordings[index].id === selectedId) {
        return recordings[index];
      }
    }
    return undefined;
  }

  private quickActionDisplayName(): string {
    const recording = this.quickActionRecording();
    return recording === undefined ? '录音操作' : recording.displayName;
  }

  private async shareQuickRecording(): Promise<void> {
    if (this.isWorking || this.isConfirming) {
      return;
    }
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
    if (this.isWorking || this.isConfirming) {
      return;
    }
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
      this.loadRecordings(true);
    } catch (error) {
      this.status = '重命名失败';
    } finally {
      this.isWorking = false;
    }
  }

  private confirmMoveQuickRecordingToTrash(): void {
    if (this.isWorking || this.isConfirming) {
      return;
    }
    const recording = this.quickActionRecording();
    if (recording === undefined) {
      this.showQuickActions = false;
      return;
    }
    // Dismiss the native Sheet before confirmation, so its exit cannot cover the row deletion.
    this.pendingTrashConfirmation = [recording];
    this.isConfirming = true;
    this.showQuickActions = false;
  }

  private onQuickActionsDismissed(): void {
    this.showingConversion = false;
    this.isQuickRenaming = false;
    this.renameValue = '';
    this.quickActionRecordingId = '';
    if (this.pendingTrashConfirmation.length > 0) {
      const pending = this.pendingTrashConfirmation;
      this.pendingTrashConfirmation = [];
      this.isConfirming = false;
      this.confirmBatch(pending, RecordingBatchAction.MOVE_TO_TRASH);
    }
  }

  private selectedRecordings(): RecordingInfo[] {
    const source = this.showingTrash ? this.recentlyDeleted : this.recordings;
    return source.filter((recording: RecordingInfo): boolean => this.selectedRecordingIds.includes(recording.id));
  }

  private async confirmBatch(requested: RecordingInfo[], action: RecordingBatchAction): Promise<void> {
    if (this.isWorking || this.isConfirming) {
      return;
    }
    const source = action === RecordingBatchAction.MOVE_TO_TRASH ? this.recordings : this.recentlyDeleted;
    const recordings = requested.filter((recording: RecordingInfo): boolean =>
      source.some((item: RecordingInfo): boolean => item.id === recording.id && item.filePath === recording.filePath));
    if (recordings.length === 0) {
      return;
    }
    const restoring = action === RecordingBatchAction.RESTORE;
    const deleting = action === RecordingBatchAction.PERMANENTLY_DELETE;
    const verb = restoring ? '恢复' : (deleting ? '永久删除' : '移至最近删除');
    this.isConfirming = true;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: `${verb} ${recordings.length} 段录音？`,
        message: restoring ? '所选录音将恢复到资料库。' :
          (deleting ? '所选录音将从本机永久移除，无法恢复。' : '所选录音仍可在最近删除中恢复。'),
        buttons: [
          { text: '取消', color: HarmonyTokens.textSecondary() },
          { text: `${verb}（${recordings.length}）`, color: deleting ? HarmonyTokens.danger() : HarmonyTokens.primary() }
        ]
      });
      this.isConfirming = false;
      if (result.index === 1) {
        await this.runBatch(recordings, action);
      }
    } catch (error) {
      // The native prompt API rejects with Error('cancel') for Back and mask dismissal.
      const dialogError = error as BusinessError;
      if (dialogError.message !== 'cancel') {
        console.error(`Recording confirmation failed: code=${dialogError.code}, message=${dialogError.message}`);
        this.status = '无法打开确认窗口';
      }
    } finally {
      this.isConfirming = false;
    }
  }

  private async runBatch(recordings: RecordingInfo[], action: RecordingBatchAction): Promise<void> {
    if (this.isWorking) {
      return;
    }
    this.isWorking = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result = await RecordingRepository.applyBatchAsync(context, recordings, action);
      const refreshed = this.loadRecordings(true, false, result.failedIds);
      if (!refreshed) {
        // The filesystem operation already succeeded; do not leave confirmed-deleted rows actionable after a refresh error.
        this.getUIContext().animateTo(MotionTheme.content(), (): void => {
          if (action === RecordingBatchAction.MOVE_TO_TRASH) {
            this.recordings = this.recordings.filter((item: RecordingInfo): boolean => !result.completedIds.includes(item.id));
          } else {
            this.recentlyDeleted = this.recentlyDeleted.filter((item: RecordingInfo): boolean => !result.completedIds.includes(item.id));
          }
          this.selectedRecordingIds = result.failedIds;
          this.isSelecting = result.failedIds.length > 0;
        });
      }
      const verb = action === RecordingBatchAction.RESTORE ? '恢复' :
        (action === RecordingBatchAction.PERMANENTLY_DELETE ? '永久删除' : '移入最近删除');
      const retryHint = this.selectedRecordingIds.length === result.failedIds.length ? '，已保留选择，可重试' :
        (this.selectedRecordingIds.length > 0 ? `，已保留 ${this.selectedRecordingIds.length} 段可重试项` :
          '，请重新进入资料库检查文件状态');
      this.status = `已${verb} ${result.completedIds.length} 段` +
        (result.failedIds.length > 0 ? `，失败 ${result.failedIds.length} 段${retryHint}` : '') +
        (refreshed ? '' : '；列表刷新失败，请重新进入资料库');
    } catch (error) {
      this.status = '操作未完成，请重新进入资料库后重试';
    } finally {
      this.isWorking = false;
    }
  }
  private filteredRecordings(): RecordingInfo[] {
    const source = this.showingTrash ? this.recentlyDeleted : this.recordings;
    const query = this.searchQuery.trim().toLowerCase();
    if (this.filteredSource === source && this.filteredQuery === query) { return this.filteredCache; }
    this.filteredSource = source;
    this.filteredQuery = query;
    if (query.length === 0) {
      this.filteredCache = source;
      return this.filteredCache;
    }
    this.filteredCache = source.filter((recording: RecordingInfo): boolean => {
      return recording.displayName.toLowerCase().includes(query) ||
        recording.config.formatLabel.toLowerCase().includes(query);
    });
    return this.filteredCache;
  }

  private libraryRows(): RecordingLibraryRow[] {
    const rows: RecordingLibraryRow[] = [];
    const prefix = this.showingTrash ? 'trash' : 'active';
    const source = this.filteredRecordings();
    const key = `${prefix}:${TimeUtils.dateSectionKey(Date.now())}`;
    if (this.rowsSource === source && this.rowsKey === key) { return this.rowsCache; }
    let previousDay = '';
    for (const recording of source) {
      const timestamp = this.showingTrash ? recording.deletedAt : recording.createdAt;
      const day = TimeUtils.dateSectionKey(timestamp);
      if (day !== previousDay) {
        rows.push(new RecordingLibraryRow(`${prefix}:date:${day}`, TimeUtils.formatDateSection(timestamp)));
        previousDay = day;
      }
      rows.push(new RecordingLibraryRow(`${prefix}:recording:${recording.id}`, '', recording));
    }
    this.rowsSource = source;
    this.rowsKey = key;
    this.rowsCache = rows;
    return this.rowsCache;
  }
  private palette(): HarmonyPalette {
    return HarmonyTheme.palette(this.themeMode);
  }

  private loadRecordings(animated: boolean = false, leaveSelection: boolean = false,
    selectedIds: string[] | undefined = undefined): boolean {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      // Keep directory reads outside the animation closure; only commit the prepared UI snapshot inside it.
      const recordings = RecordingRepository.list(context);
      const recentlyDeleted = RecordingRepository.listRecentlyDeleted(context);
      const unreadable = RecordingRepository.getUnreadableCount(context) +
        RecordingRepository.getUnreadableCount(context, true);
      const update = (): void => {
        this.recordings = recordings;
        this.recentlyDeleted = recentlyDeleted;
        this.unreadableCount = unreadable;
        this.status = '';
        if (leaveSelection) {
          this.isSelecting = false;
          this.selectedRecordingIds = [];
        } else if (selectedIds !== undefined) {
          const source = this.showingTrash ? recentlyDeleted : recordings;
          this.selectedRecordingIds = selectedIds.filter((id: string): boolean =>
            source.some((item: RecordingInfo): boolean => item.id === id));
          this.isSelecting = this.selectedRecordingIds.length > 0;
        }
      };
      if (animated && this.isVisible) {
        this.getUIContext().animateTo(MotionTheme.content(), update);
      } else {
        update();
      }
      return true;
    } catch (error) {
      // Retain the last readable snapshot on I/O errors instead of claiming the library is empty.
      this.status = '读取本地录音失败';
      return false;
    }
  }

}
