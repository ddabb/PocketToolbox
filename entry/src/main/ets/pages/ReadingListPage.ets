import { ReadingListStore, ReadingList, ReadingItem } from '../model/ReadingListModels';
import { promptAction } from '@kit.ArkUI';

@Builder
export function ReadingListPageBuilder() {
  NavDestination() {
    ReadingListContent()
  }
  .title('朗读清单')
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct ReadingListContent {
  @State lists: ReadingList[] = [];
  @State editingListId: string = '';
  @State editName: string = '';
  @State showAddDialog: boolean = false;
  @State showRenameDialog: boolean = false;
  @State newListName: string = '';
  @State listVersion: number = 0;
  private uiContext: UIContext = this.getUIContext();
  private getNavPathStack(): NavPathStack {
    return AppStorage.get('AppNavPathStack') as NavPathStack;
  }

  aboutToAppear(): void {
    this.loadLists();
  }

  private loadLists(): void {
    ReadingListStore.invalidateCache();
    let loaded: ReadingList[] = ReadingListStore.load(this.uiContext.getHostContext() as Context);
    let json: string = JSON.stringify(loaded);
    let raw: Object[] = JSON.parse(json) as Object[];
    let deepCopy: ReadingList[] = [];
    for (let i = 0; i < raw.length; i++) {
      let obj: Record<string, Object> = raw[i] as Record<string, Object>;
      let list: ReadingList = new ReadingList();
      list.id = (obj['id'] as string) || '';
      list.name = (obj['name'] as string) || '';
      list.createdAt = (obj['createdAt'] as number) || 0;
      list.updatedAt = (obj['updatedAt'] as number) || 0;
      list.lastPlayedIndex = (obj['lastPlayedIndex'] as number) || -1;
      list.lastPlayedTime = (obj['lastPlayedTime'] as number) || 0;
      let itemsRaw: Object[] = (obj['items'] as Object[]) || [];
      list.items = [];
      for (let j = 0; j < itemsRaw.length; j++) {
        let itemObj: Record<string, Object> = itemsRaw[j] as Record<string, Object>;
        let item: ReadingItem = new ReadingItem();
        item.id = (itemObj['id'] as string) || '';
        item.type = (itemObj['type'] as string) || '';
        item.title = (itemObj['title'] as string) || '';
        item.subtitle = (itemObj['subtitle'] as string) || '';
        item.content = (itemObj['content'] as string) || '';
        item.timestamp = (itemObj['timestamp'] as number) || 0;
        list.items.push(item);
      }
      deepCopy.push(list);
    }
    this.lists = deepCopy;
  }

  private addList(): void {
    let name: string = this.newListName.trim();
    if (!name) {
      this.uiContext.getPromptAction().showToast({ message: '请输入清单名称', duration: 1000 });
      return;
    }
    ReadingListStore.addList(this.uiContext.getHostContext() as Context, name);
    this.newListName = '';
    this.showAddDialog = false;
    this.loadLists();
    this.uiContext.getPromptAction().showToast({ message: '清单已创建', duration: 1000 });
  }

  private renameList(): void {
    let name: string = this.editName.trim();
    if (!name) {
      this.uiContext.getPromptAction().showToast({ message: '请输入清单名称', duration: 1000 });
      return;
    }
    ReadingListStore.renameList(this.uiContext.getHostContext() as Context, this.editingListId, name);
    this.editName = '';
    this.editingListId = '';
    this.showRenameDialog = false;
    this.listVersion++;
    this.loadLists();
    this.uiContext.getPromptAction().showToast({ message: '已重命名', duration: 1000 });
  }

  private deleteList(listId: string, listName: string): void {
    this.uiContext.getPromptAction().showDialog({
      title: '确认删除',
      message: '确定要删除清单「' + listName + '」吗？',
      buttons: [
        { text: '取消', color: $r('app.color.tertiary_text') },
        { text: '删除', color: $r('app.color.danger_red') }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        ReadingListStore.removeList(this.uiContext.getHostContext() as Context, listId);
        this.loadLists();
        this.uiContext.getPromptAction().showToast({ message: '已删除', duration: 1000 });
      }
    }).catch(() => {});
  }

  private openList(listId: string): void {
    let stack: NavPathStack = this.getNavPathStack();
    if (stack) {
      let param: Record<string, Object> = { 'listId': listId as Object };
      stack.pushPathByName('ReadingPlayerPage', param);
    }
  }

  private getItemCountText(items: ReadingItem[]): string {
    if (items.length === 0) {
      return '暂无内容';
    }
    let poemCount: number = 0;
    let idiomCount: number = 0;
    let xiehouyuCount: number = 0;
    for (let i = 0; i < items.length; i++) {
      if (items[i].type === 'poem') {
        poemCount++;
      } else if (items[i].type === 'idiom') {
        idiomCount++;
      } else if (items[i].type === 'xiehouyu') {
        xiehouyuCount++;
      }
    }
    let parts: string[] = [];
    if (poemCount > 0) {
      parts.push('诗词' + poemCount.toString());
    }
    if (idiomCount > 0) {
      parts.push('成语' + idiomCount.toString());
    }
    if (xiehouyuCount > 0) {
      parts.push('歇后语' + xiehouyuCount.toString());
    }
    return '共' + items.length.toString() + '项：' + parts.join('、');
  }

  private formatDate(timestamp: number): string {
    let date: Date = new Date(timestamp);
    let m: number = date.getMonth() + 1;
    let d: number = date.getDate();
    return m.toString() + '月' + d.toString() + '日';
  }

  build() {
    Stack() {
      Column() {
        if (this.lists.length > 0) {
          List({ space: 8 }) {
            ForEach(this.lists, (list: ReadingList) => {
              ListItem() {
                Row() {
                  Column() {
                    Text(list.name)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.primary_text'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.getItemCountText(list.items))
                      .fontSize(12)
                      .fontColor($r('app.color.tertiary_text'))
                      .margin({ top: 4 })
                    Text('更新于 ' + this.formatDate(list.updatedAt))
                      .fontSize(11)
                      .fontColor($r('app.color.hint_text'))
                      .margin({ top: 2 })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  Text('\u270E')
                    .fontSize(18)
                    .fontColor($r('app.color.idiom_blue'))
                    .width(36)
                    .height(36)
                    .borderRadius(18)
                    .backgroundColor($r('app.color.idiom_blue') + '12')
                    .textAlign(TextAlign.Center)
                    .margin({ right: 6 })
                    .onClick(() => {
                      this.editingListId = list.id;
                      this.editName = list.name;
                      this.showRenameDialog = true;
                    })

                  Text('\u2715')
                    .fontSize(16)
                    .fontColor($r('app.color.danger_red'))
                    .width(36)
                    .height(36)
                    .borderRadius(18)
                    .backgroundColor($r('app.color.danger_red') + '12')
                    .textAlign(TextAlign.Center)
                    .onClick(() => {
                      this.deleteList(list.id, list.name);
                    })

                  Text('\u203A')
                    .fontSize(20)
                    .fontColor($r('app.color.hint_text'))
                    .margin({ left: 6 })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 14, bottom: 14 })
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(12)
                .onClick(() => {
                  this.openList(list.id);
                })
              }
            }, (list: ReadingList) => list.id + '_' + list.name + '_' + this.listVersion.toString())
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 12, right: 12, top: 8 })
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        } else {
          Column() {
            Text('\uD83D\uDCD6')
              .fontSize(48)
              .margin({ bottom: 12 })
            Text('暂无朗读清单')
              .fontSize(16)
              .fontColor($r('app.color.tertiary_text'))
            Text('点击下方按钮创建您的第一个清单')
              .fontSize(13)
              .fontColor($r('app.color.hint_text'))
              .margin({ top: 6 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }

        Row() {
          Text('+ 新建清单')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffffff')
            .backgroundColor($r('app.color.poetry_green'))
            .borderRadius(24)
            .padding({ left: 32, right: 32, top: 12, bottom: 12 })
            .onClick(() => {
              this.newListName = '';
              this.showAddDialog = true;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 12, bottom: 24 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))

      if (this.showAddDialog) {
        this.AddListOverlay()
      }

      if (this.showRenameDialog) {
        this.RenameListOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  AddListOverlay() {
    Column() {
      Column() {
        Text('新建朗读清单')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .margin({ bottom: 20 })

        TextInput({ placeholder: '输入清单名称，如：每日诗词', text: this.newListName })
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor($r('app.color.primary_text'))
          .placeholderColor($r('app.color.hint_text'))
          .backgroundColor($r('app.color.page_background'))
          .borderRadius(12)
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.newListName = value;
          })

        Row({ space: 12 }) {
          Text('取消')
            .fontSize(15)
            .fontColor($r('app.color.tertiary_text'))
            .backgroundColor($r('app.color.border_color'))
            .borderRadius(22)
            .padding({ left: 28, right: 28, top: 10, bottom: 10 })
            .onClick(() => {
              this.showAddDialog = false;
            })

          Text('创建')
            .fontSize(15)
            .fontColor('#ffffff')
            .backgroundColor($r('app.color.poetry_green'))
            .borderRadius(22)
            .padding({ left: 28, right: 28, top: 10, bottom: 10 })
            .onClick(() => {
              this.addList();
            })
        }
        .margin({ top: 20 })
      }
      .width('85%')
      .padding(24)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(20)
      .shadow({ radius: 20, color: '#33000000', offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#99000000')
    .onClick(() => {
      this.showAddDialog = false;
    })
  }

  @Builder
  RenameListOverlay() {
    Column() {
      Column() {
        Text('重命名清单')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .margin({ bottom: 20 })

        TextInput({ placeholder: '输入新的清单名称', text: this.editName })
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor($r('app.color.primary_text'))
          .placeholderColor($r('app.color.hint_text'))
          .backgroundColor($r('app.color.page_background'))
          .borderRadius(12)
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.editName = value;
          })

        Row({ space: 12 }) {
          Text('取消')
            .fontSize(15)
            .fontColor($r('app.color.tertiary_text'))
            .backgroundColor($r('app.color.border_color'))
            .borderRadius(22)
            .padding({ left: 28, right: 28, top: 10, bottom: 10 })
            .onClick(() => {
              this.showRenameDialog = false;
            })

          Text('保存')
            .fontSize(15)
            .fontColor('#ffffff')
            .backgroundColor($r('app.color.poetry_green'))
            .borderRadius(22)
            .padding({ left: 28, right: 28, top: 10, bottom: 10 })
            .onClick(() => {
              this.renameList();
            })
        }
        .margin({ top: 20 })
      }
      .width('85%')
      .padding(24)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(20)
      .shadow({ radius: 20, color: '#33000000', offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#99000000')
    .onClick(() => {
      this.showRenameDialog = false;
    })
  }
}
