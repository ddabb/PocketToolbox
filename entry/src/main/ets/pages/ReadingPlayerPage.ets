import { ReadingListStore, ReadingList, ReadingItem } from '../model/ReadingListModels';
import { TtsController, TtsState, TtsErrorKind, splitToSegments } from '../common/utils/TtsUtil';
import { ReadingAvSession } from '../common/utils/ReadingAvSession';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { ToastUtil } from '../common/utils/ToastUtil';

const SPEED_PREFS_NAME: string = 'reading_settings';
const SPEED_KEY: string = 'reading_speed';

class PlayerParamInfo {
  listId: string = '';
}

function buildPlayerParam(param: Object): PlayerParamInfo {
  let p: Record<string, Object> = param as Record<string, Object>;
  let info: PlayerParamInfo = new PlayerParamInfo();
  info.listId = (p['listId'] ?? '') as string;
  return info;
}

@Builder
export function ReadingPlayerPageBuilder(param: Object) {
  NavDestination() {
    ReadingPlayerContent({ playerParam: buildPlayerParam(param) })
  }
  .title($r('app.string.player_title'))
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct ReadingPlayerContent {
  @Prop playerParam: PlayerParamInfo = new PlayerParamInfo();
  @State currentList: ReadingList | null = null;
  @State currentIndex: number = -1;
  @State ttsState: TtsState = 'idle';
  @State showItemMenu: boolean = false;
  @State menuItemId: string = '';
  @State currentSegments: string[] = [];
  @State currentSegmentIndex: number = -1;
  @State speedValue: number = 1;
  @State showSpeedPanel: boolean = false;
  private prevSpeed: number = 1;
  private segmentItemId: string = '';
  private segmentScroller: Scroller = new Scroller();
  private ttsController: TtsController = new TtsController();
  private avSessionHelper: ReadingAvSession = new ReadingAvSession();
  private uiContext: UIContext = this.getUIContext();

  aboutToAppear(): void {
    this.loadList();
    this.speedValue = this.loadSpeed();
    this.ttsController.setSpeed(this.speedValue);
    this.ttsController.onStateChange((state: TtsState) => {
      this.ttsState = state;
      this.avSessionHelper.setPlaying(state === 'speaking');
      this.setKeepScreenOn(state === 'speaking');
    });
    this.ttsController.onSegmentChange((index: number, total: number) => {
      this.onSegmentChanged(index);
    });
    this.ttsController.onComplete(() => {
      this.playNext();
    });
    this.ttsController.onTtsError((code: number, message: string, kind: TtsErrorKind) => {
      if (kind === 'init') {
        ToastUtil.show(this.uiContext, $r('app.string.player_tts_unsupported'), 2500);
      } else {
        ToastUtil.show(this.uiContext, $r('app.string.player_tts_failed', code), 2500);
      }
    });
  }

  aboutToDisappear(): void {
    this.setKeepScreenOn(false);
    this.ttsController.shutdown();
    this.avSessionHelper.stop();
  }

  private setKeepScreenOn(keep: boolean): void {
    window.getLastWindow(this.uiContext.getHostContext() as Context)
      .then((win: window.Window) => {
        return win.setWindowKeepScreenOn(keep);
      })
      .catch((err: BusinessError) => {
        console.error('[ReadingPlayer] setKeepScreenOn failed: ' + err.message);
      });
  }

  private loadSpeed(): number {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(
        this.uiContext.getHostContext() as Context, { name: SPEED_PREFS_NAME });
      return prefs.getSync(SPEED_KEY, 1) as number;
    } catch (e) {
      return 1;
    }
  }

  private saveSpeed(value: number): void {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(
        this.uiContext.getHostContext() as Context, { name: SPEED_PREFS_NAME });
      prefs.putSync(SPEED_KEY, value);
      prefs.flush();
    } catch (e) {
      console.error('[ReadingPlayer] save speed failed: ' + (e as Error).message);
    }
  }

  private formatSpeedLabel(v: number): string {
    let s: string = v.toFixed(2).replace(/0+$/, '');
    if (s.endsWith('.')) {
      s = s.substring(0, s.length - 1) + '.0';
    }
    return s + 'x';
  }

  private openSpeedPanel(): void {
    this.prevSpeed = this.speedValue;
    this.showSpeedPanel = true;
  }

  private cancelSpeed(): void {
    this.speedValue = this.prevSpeed;
    this.showSpeedPanel = false;
  }

  private applySpeed(): void {
    let v: number = Math.round(this.speedValue * 100) / 100;
    this.speedValue = v;
    this.saveSpeed(v);
    this.ttsController.setSpeed(v);
    this.showSpeedPanel = false;
    if (this.ttsState === 'speaking' && this.currentSegmentIndex >= 0) {
      this.ttsController.startFrom(this.currentSegmentIndex);
    }
  }

  private playFromSegment(segIndex: number): void {
    let ok: boolean = this.ttsController.startFrom(segIndex);
    if (!ok) {
      this.playCurrent();
    }
  }

  private onSegmentChanged(index: number): void {
    this.currentSegmentIndex = index;
    if (index > 0) {
      this.segmentScroller.scrollToIndex(index, true, ScrollAlign.CENTER);
    }
  }

  private isSegmentActive(segIndex: number): boolean {
    return segIndex === this.currentSegmentIndex &&
      (this.ttsState === 'speaking' || this.ttsState === 'paused');
  }

  private getStatusText(): ResourceStr {
    if (this.ttsState === 'speaking') {
      if (this.currentSegments.length > 0 && this.currentSegmentIndex >= 0) {
        return $r('app.string.player_status_playing', this.currentSegmentIndex + 1, this.currentSegments.length);
      }
      return $r('app.string.player_status_playing_short');
    }
    if (this.ttsState === 'paused') {
      return $r('app.string.player_paused');
    }
    return $r('app.string.player_tap_to_read');
  }

  private loadList(): void {
    ReadingListStore.invalidateCache();
    let list: ReadingList | null = ReadingListStore.getList(
      this.uiContext.getHostContext() as Context, this.playerParam.listId);
    let previousId: string = '';
    let previousItem: ReadingItem | null = this.getCurrentItem();
    if (previousItem) {
      previousId = previousItem.id;
    }
    this.currentList = list;
    if (!list || list.items.length === 0) {
      this.currentIndex = -1;
      return;
    }
    let restoredIndex: number = 0;
    if (previousId !== '') {
      for (let i = 0; i < list.items.length; i++) {
        if (list.items[i].id === previousId) {
          restoredIndex = i;
          break;
        }
      }
    }
    this.currentIndex = restoredIndex;
  }

  private getCurrentItem(): ReadingItem | null {
    if (!this.currentList || this.currentIndex < 0 || this.currentIndex >= this.currentList.items.length) {
      return null;
    }
    return this.currentList.items[this.currentIndex];
  }

  private playCurrent(): void {
    let item: ReadingItem | null = this.getCurrentItem();
    if (!item) {
      return;
    }
    this.avSessionHelper.start(this.uiContext.getHostContext() as Context, item.title,
      (): void => {
        if (this.ttsState === 'paused') {
          this.ttsController.resume();
        } else {
          this.playCurrent();
        }
      },
      (): void => {
        if (this.ttsState === 'speaking') {
          this.ttsController.pause();
        } else if (this.ttsState === 'paused') {
          this.ttsController.resume();
        }
      },
      (): void => {
        this.ttsController.stop();
        this.playNext();
      },
      (): void => {
        this.playPrev();
      });
    let text: string = this.buildSpeakText(item);
    let segments: string[] = splitToSegments(text);
    this.segmentItemId = item.id;
    this.currentSegments = segments;
    this.currentSegmentIndex = segments.length > 0 ? 0 : -1;
    this.ttsController.speakSegmented(segments);
  }

  private playNext(): void {
    if (!this.currentList) {
      return;
    }
    let nextIndex: number = this.currentIndex + 1;
    if (nextIndex < this.currentList.items.length) {
      this.currentIndex = nextIndex;
      this.playCurrent();
    } else {
      this.currentIndex = this.currentList.items.length - 1;
      ToastUtil.show(this.uiContext, $r('app.string.player_all_done'), 1500);
    }
  }

  private playPrev(): void {
    if (this.currentIndex > 0) {
      this.currentIndex--;
      this.ttsController.stop();
      this.playCurrent();
    }
  }

  private togglePlay(): void {
    if (this.ttsState === 'speaking') {
      this.ttsController.pause();
    } else if (this.ttsState === 'paused') {
      this.ttsController.resume();
    } else {
      this.playCurrent();
    }
  }

  private buildSpeakText(item: ReadingItem): string {
    if (item.type === 'poem') {
      let parts: string[] = [];
      parts.push(item.title);
      if (item.subtitle) {
        parts.push(item.subtitle);
      }
      parts.push(item.content);
      return parts.join('。');
    } else if (item.type === 'idiom') {
      let parts: string[] = [];
      parts.push(item.title);
      if (item.subtitle) {
        parts.push(item.subtitle);
      }
      parts.push(item.content);
      return parts.join('。');
    } else if (item.type === 'xiehouyu') {
      return item.title + '，' + item.content;
    }
    return item.title + '。' + item.content;
  }

  private removeItem(itemId: string): void {
    if (!this.currentList) {
      return;
    }
    ReadingListStore.removeItemFromList(this.uiContext.getHostContext() as Context,
      this.currentList.id, itemId);
    this.ttsController.stop();
    this.loadList();
    ToastUtil.show(this.uiContext, $r('app.string.player_removed'), 1000);
  }

  private moveItemUp(index: number): void {
    if (!this.currentList || index <= 0) {
      return;
    }
    ReadingListStore.moveItem(this.uiContext.getHostContext() as Context,
      this.currentList.id, index, index - 1);
    this.loadList();
  }

  private moveItemDown(index: number): void {
    if (!this.currentList) {
      return;
    }
    if (index >= this.currentList.items.length - 1) {
      return;
    }
    ReadingListStore.moveItem(this.uiContext.getHostContext() as Context,
      this.currentList.id, index, index + 1);
    this.loadList();
  }

  private getTypeIcon(type: string): string {
    if (type === 'poem') {
      return '\uD83C\uDF3C';
    } else if (type === 'idiom') {
      return '\uD83D\uDCD6';
    } else if (type === 'xiehouyu') {
      return '\uD83E\uDD14';
    }
    return '\uD83D\uDCDC';
  }

  private getTypeLabel(type: string): ResourceStr {
    if (type === 'poem') {
      return $r('app.string.player_type_poem');
    } else if (type === 'idiom') {
      return $r('app.string.player_type_idiom');
    } else if (type === 'xiehouyu') {
      return $r('app.string.xiehouyu_short');
    }
    return $r('app.string.player_type_text');
  }

  build() {
    Stack() {
      Column() {
        if (this.currentList && this.currentList.items.length > 0) {
          this.PlaylistSection()
          this.PlayerControls()
        } else if (this.currentList) {
          Column() {
            Text('\uD83D\uDCD6')
              .fontSize(48)
              .margin({ bottom: 12 })
            Text($r('app.string.player_empty_list'))
              .fontSize(16)
              .fontColor($r('app.color.tertiary_text'))
            Text($r('app.string.player_empty_hint'))
              .fontSize(13)
              .fontColor($r('app.color.hint_text'))
              .margin({ top: 6 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Column() {
            Text($r('app.string.player_list_missing'))
              .fontSize(16)
              .fontColor($r('app.color.tertiary_text'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: 720 })

      if (this.showItemMenu) {
        this.ItemMenuOverlay()
      }

      if (this.showSpeedPanel) {
        this.SpeedPanelOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  PlaylistSection() {
    List({ space: 4 }) {
      ForEach(this.currentList!.items, (item: ReadingItem, index: number) => {
        ListItem() {
          Column() {
            Row() {
              Text(this.getTypeIcon(item.type))
                .fontSize(16)
                .margin({ right: 6 })
              Text(item.title)
                .fontSize(15)
                .fontWeight(this.currentIndex === index ? FontWeight.Bold : FontWeight.Medium)
                .fontColor(this.currentIndex === index ? $r('app.color.poetry_green') : $r('app.color.primary_text'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text(this.getTypeLabel(item.type))
                .fontSize(11)
                .fontColor($r('app.color.poetry_green'))
                .backgroundColor($r('app.color.poetry_green') + '18')
                .borderRadius(6)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .margin({ left: 6 })
            }
            .width('100%')
            Text(item.subtitle)
              .fontSize(12)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ top: 2, left: 22 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            if (this.currentIndex === index && item.content) {
              Column() {
                if (this.segmentItemId === item.id && this.currentSegments.length > 0) {
                  List({ space: 4, scroller: this.segmentScroller }) {
                    ForEach(this.currentSegments, (seg: string, segIndex: number) => {
                      ListItem() {
                        Text(seg)
                          .fontSize(14)
                          .fontWeight(this.isSegmentActive(segIndex) ? FontWeight.Bold : FontWeight.Normal)
                          .fontColor(this.isSegmentActive(segIndex) ?
                            $r('app.color.poetry_green') : $r('app.color.secondary_text'))
                          .backgroundColor(this.isSegmentActive(segIndex) ?
                            $r('app.color.poetry_green') + '14' : Color.Transparent)
                          .borderRadius(6)
                          .lineHeight(24)
                          .width('100%')
                          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      }
                      .onClick(() => {
                        this.playFromSegment(segIndex);
                      })
                    }, (seg: string, segIndex: number) => segIndex.toString())
                  }
                  .width('100%')
                  .constraintSize({ maxHeight: 240 })
                  .edgeEffect(EdgeEffect.Fade)
                  .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
                  .padding({ top: 6, bottom: 4 })
                } else {
                  Text(item.content)
                    .fontSize(14)
                    .fontColor($r('app.color.secondary_text'))
                    .lineHeight(24)
                    .width('100%')
                }
              }
              .width('100%')
              .padding({ top: 10, bottom: 4, left: 22 })
            }

            Row() {
              if (this.currentIndex === index) {
                Row() {
                  Text(this.ttsState === 'speaking' ? '\u23F8' : '\u25B6')
                    .fontSize(14)
                    .fontColor($r('app.color.poetry_green'))
                    .margin({ right: 4 })
                  Text(this.getStatusText())
                    .fontSize(12)
                    .fontColor($r('app.color.poetry_green'))
                }
              }
              Blank()
              Text('\u2022\u2022\u2022')
                .fontSize(18)
                .fontColor($r('app.color.hint_text'))
                .margin({ left: 8 })
                .onClick(() => {
                  this.menuItemId = item.id;
                  this.showItemMenu = true;
                })
            }
            .width('100%')
            .padding({ top: 4 })
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          .backgroundColor(this.currentIndex === index ? $r('app.color.poetry_card_bg') : $r('app.color.card_background'))
          .borderRadius(10)
          .border(this.currentIndex === index ? {
            width: 1,
            color: $r('app.color.poetry_green'),
            style: BorderStyle.Solid
          } : undefined)
          .onClick(() => {
            if (this.currentIndex !== index) {
              this.ttsController.stop();
              this.currentIndex = index;
              this.playCurrent();
            } else {
              this.togglePlay();
            }
          })
        }
      }, (item: ReadingItem) => item.id)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 12, right: 12, top: 8 })
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder
  PlayerControls() {
    Column() {
      Row({ space: 24 }) {
        Text('\u23EA')
          .fontSize(28)
          .fontColor(this.currentIndex > 0 ? $r('app.color.poetry_green') : $r('app.color.hint_text'))
          .onClick(() => {
            this.playPrev();
          })

        Text(this.ttsState === 'speaking' ? '\u23F8' : this.ttsState === 'paused' ? '\u25B6' : '\u25B6')
          .fontSize(40)
          .fontColor($r('app.color.poetry_green'))
          .width(64)
          .height(64)
          .borderRadius(32)
          .backgroundColor($r('app.color.poetry_green') + '18')
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.togglePlay();
          })

        Text('\u23E9')
          .fontSize(28)
          .fontColor(this.currentList && this.currentIndex < this.currentList.items.length - 1 ?
            $r('app.color.poetry_green') : $r('app.color.hint_text'))
          .onClick(() => {
            this.ttsController.stop();
            this.playNext();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 8, bottom: 8 })

      Text($r('app.string.player_speed', this.formatSpeedLabel(this.speedValue)))
        .fontSize(12)
        .fontColor($r('app.color.poetry_green'))
        .backgroundColor($r('app.color.poetry_green') + '18')
        .borderRadius(12)
        .padding({ left: 14, right: 14, top: 4, bottom: 4 })
        .margin({ bottom: 4 })
        .onClick(() => {
          this.openSpeedPanel();
        })
    }
    .width('100%')
    .padding({ top: 12, bottom: 24 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius({ topLeft: 20, topRight: 20 })
    .shadow({ radius: 10, color: '#1a000000', offsetY: -2 })
  }

  @Builder
  SpeedPanelOverlay() {
    Column() {
      Column() {
        Text($r('app.string.player_speed_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .margin({ bottom: 12 })

        Text(this.formatSpeedLabel(this.speedValue))
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.poetry_green'))
          .margin({ bottom: 12 })

        Slider({ value: this.speedValue, min: 0.5, max: 2, step: 0.05, style: SliderStyle.OutSet })
          .width('100%')
          .onChange((value: number, mode: SliderChangeMode) => {
            this.speedValue = value;
          })

        Row({ space: 12 }) {
          Text($r('app.string.readlist_cancel'))
            .fontSize(15)
            .fontColor($r('app.color.tertiary_text'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 8, bottom: 8 })
            .backgroundColor($r('app.color.page_background'))
            .borderRadius(10)
            .onClick(() => {
              this.cancelSpeed();
            })

          Text($r('app.string.player_confirm'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_accent_text'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 8, bottom: 8 })
            .backgroundColor($r('app.color.poetry_green'))
            .borderRadius(10)
            .onClick(() => {
              this.applySpeed();
            })
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .width('75%')
      .padding({ left: 20, right: 20, top: 20, bottom: 20 })
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#99000000')
    .onClick(() => {
      this.cancelSpeed();
    })
  }

  @Builder
  ItemMenuOverlay() {
    Column() {
      Column() {
        Row() {
          Text('\u2B06')
            .fontSize(20)
            .margin({ right: 8 })
          Text($r('app.string.player_move_up'))
            .fontSize(15)
            .fontColor($r('app.color.primary_text'))
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 14, bottom: 14 })
        .onClick(() => {
          let idx: number = this.findItemIndex(this.menuItemId);
          if (idx >= 0) {
            this.moveItemUp(idx);
          }
          this.showItemMenu = false;
        })

        Divider().color($r('app.color.border_color')).margin({ left: 20 })

        Row() {
          Text('\u2B07')
            .fontSize(20)
            .margin({ right: 8 })
          Text($r('app.string.player_move_down'))
            .fontSize(15)
            .fontColor($r('app.color.primary_text'))
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 14, bottom: 14 })
        .onClick(() => {
          let idx: number = this.findItemIndex(this.menuItemId);
          if (idx >= 0) {
            this.moveItemDown(idx);
          }
          this.showItemMenu = false;
        })

        Divider().color($r('app.color.border_color')).margin({ left: 20 })

        Row() {
          Text('\uD83D\uDDD1')
            .fontSize(20)
            .margin({ right: 8 })
          Text($r('app.string.player_remove'))
            .fontSize(15)
            .fontColor($r('app.color.danger_red'))
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 14, bottom: 14 })
        .onClick(() => {
          this.removeItem(this.menuItemId);
          this.showItemMenu = false;
        })

        Divider().color($r('app.color.border_color')).margin({ left: 20 })

        Row() {
          Text($r('app.string.readlist_cancel'))
            .fontSize(15)
            .fontColor($r('app.color.tertiary_text'))
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 14, bottom: 14 })
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.showItemMenu = false;
        })
      }
      .width('75%')
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(16)
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#99000000')
    .onClick(() => {
      this.showItemMenu = false;
    })
  }

  private findItemIndex(itemId: string): number {
    if (!this.currentList) {
      return -1;
    }
    for (let i = 0; i < this.currentList.items.length; i++) {
      if (this.currentList.items[i].id === itemId) {
        return i;
      }
    }
    return -1;
  }
}
