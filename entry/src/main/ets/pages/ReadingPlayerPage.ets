import { ReadingListStore, ReadingList, ReadingItem } from '../model/ReadingListModels';
import { TtsController, TtsState } from '../common/utils/TtsUtil';
import { promptAction } from '@kit.ArkUI';

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
  .title('朗读播放')
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
  private ttsController: TtsController = new TtsController();
  private uiContext: UIContext = this.getUIContext();

  aboutToAppear(): void {
    this.loadList();
    this.ttsController.onStateChange((state: TtsState) => {
      this.ttsState = state;
    });
    this.ttsController.onComplete(() => {
      this.playNext();
    });
  }

  aboutToDisappear(): void {
    this.ttsController.shutdown();
  }

  private loadList(): void {
    ReadingListStore.invalidateCache();
    let list: ReadingList | null = ReadingListStore.getList(
      this.uiContext.getHostContext() as Context, this.playerParam.listId);
    this.currentList = list;
    if (list && list.items.length > 0) {
      this.currentIndex = 0;
    }
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
    let text: string = this.buildSpeakText(item);
    this.ttsController.speak(text).then((ok: boolean) => {
      if (!ok) {
        this.uiContext.getPromptAction().showToast({ message: '朗读引擎初始化失败，请确认设备支持TTS', duration: 2500 });
      }
    });
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
      this.uiContext.getPromptAction().showToast({ message: '全部朗读完毕', duration: 1500 });
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
      this.ttsController.stop();
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
    this.uiContext.getPromptAction().showToast({ message: '已移除', duration: 1000 });
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

  private getTypeLabel(type: string): string {
    if (type === 'poem') {
      return '诗词';
    } else if (type === 'idiom') {
      return '成语';
    } else if (type === 'xiehouyu') {
      return '歇后语';
    }
    return '文本';
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
            Text('清单为空')
              .fontSize(16)
              .fontColor($r('app.color.tertiary_text'))
            Text('请在诗词、成语或歇后语详情页添加内容')
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
            Text('清单不存在或已删除')
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
      .backgroundColor($r('app.color.page_background'))

      if (this.showItemMenu) {
        this.ItemMenuOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  PlaylistSection() {
    List({ space: 4 }) {
      ForEach(this.currentList!.items, (item: ReadingItem, index: number) => {
        ListItem() {
          Row() {
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
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

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
      if (this.currentIndex >= 0 && this.currentList && this.currentIndex < this.currentList.items.length) {
        Text(this.currentList!.items[this.currentIndex].title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ left: 24, right: 24 })
        Text((this.currentIndex + 1).toString() + ' / ' + this.currentList!.items.length.toString())
          .fontSize(12)
          .fontColor($r('app.color.tertiary_text'))
          .margin({ top: 4 })
      }

      Row({ space: 24 }) {
        Text('\u23EA')
          .fontSize(28)
          .fontColor(this.currentIndex > 0 ? $r('app.color.poetry_green') : $r('app.color.hint_text'))
          .onClick(() => {
            this.playPrev();
          })

        Text(this.ttsState === 'speaking' ? '\u23F8' : '\u25B6')
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
      .margin({ top: 16, bottom: 16 })
    }
    .width('100%')
    .padding({ top: 16, bottom: 24 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius({ topLeft: 20, topRight: 20 })
    .shadow({ radius: 10, color: '#1a000000', offsetY: -2 })
  }

  @Builder
  ItemMenuOverlay() {
    Column() {
      Column() {
        Row() {
          Text('\u2B06')
            .fontSize(20)
            .margin({ right: 8 })
          Text('上移')
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
          Text('下移')
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
          Text('移除')
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
          Text('取消')
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
