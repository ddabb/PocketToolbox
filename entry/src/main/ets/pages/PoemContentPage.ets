import { PoemItem, PoetItem, PoetDetail } from '../model/PoetryModels';
import { ClipboardUtil } from '../common/utils/ClipboardUtil';
import { FavoritesUtil, FavoriteItem, FavoriteAddResult } from '../common/utils/FavoritesUtil';
import { PoetryViewModel } from '../viewmodel/PoetryViewModel';
import { ShareImageCard } from '../components/ShareImageCard';
import { buildPoemMarkdown } from '../common/utils/ShareImageUtil';
import { Md2PngTemplates } from '../model/Md2PngModels';
import { AddToReadingListUtil, AddToListResult } from '../common/utils/AddToReadingListUtil';
import { ReadingList, ReadingItem, ReadingListStore } from '../model/ReadingListModels';
import { StickinessUtil } from '../common/utils/StickinessUtil';
import { ToastUtil } from '../common/utils/ToastUtil';
import { CharBookUtil } from '../common/utils/CharBookUtil';

class DynastyQueryParam {
  dynasty: string = '';
}

function buildPoemItem(param: Object): PoemItem {
  return PoetryViewModel.getInstance().parsePoemFromParam(param as Record<string, Object>);
}

@Builder
export function PoemContentPageBuilder(param: Object) {
  NavDestination() {
    PoemContentContent({ poemParam: buildPoemItem(param) })
  }
  .title($r('app.string.poemct_title'))
  .hideTitleBar(false)
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
export struct PoemContentContent {
  @Prop poemParam: PoemItem = new PoemItem();
  @State poetName: string = '';
  @State isFav: boolean = false;
  @State inReadingList: boolean = false;
  @State showShareCard: boolean = false;
  @State shareMdText: string = '';
  @State showReadingListPicker: boolean = false;
  @State readingLists: ReadingList[] = [];
  @State showCreateInPicker: boolean = false;
  @State newListName: string = '';
  @State showCharPicker: boolean = false;
  @State pickerChars: string[] = [];
  @State selectedChars: string[] = [];
  @State bookChars: string[] = [];
  @StorageLink('PoemFavStatus') @Watch('onFavStatusChange') favStatus: boolean = false;
  private uiContext: UIContext = this.getUIContext();
  private viewModel: PoetryViewModel = PoetryViewModel.getInstance();
  private getNavPathStack(): NavPathStack {
    return AppStorage.get('AppNavPathStack') as NavPathStack;
  }

  aboutToAppear(): void {
    this.poetName = this.poemParam.a || '';
    this.isFav = FavoritesUtil.isFavorite(this.uiContext.getHostContext() as Context, 'poem', this.poemParam.n);
    this.inReadingList = AddToReadingListUtil.isInAnyList(
      this.uiContext.getHostContext() as Context, 'poem', this.poemParam.n);
    AppStorage.setOrCreate('PoemFavStatus', this.isFav);
    StickinessUtil.incrementBrowseCount(this.uiContext.getHostContext() as Context);
    console.info('[PoemContent] poem=' + this.poemParam.n + ', poet=' + this.poetName);
  }

  onFavStatusChange(): void {
    this.isFav = FavoritesUtil.isFavorite(this.uiContext.getHostContext() as Context, 'poem', this.poemParam.n);
  }

  private onShareImage(): void {
    this.showShareCard = false;
    this.shareMdText = buildPoemMarkdown(this.poemParam);
    this.showShareCard = true;
  }

  private copyPoem(): void {
    let text: string = '\u3010' + this.poemParam.n + '\u3011' + this.poetName + '\n' + this.poemParam.c;
    ClipboardUtil.copy(text);
    ToastUtil.show(this.uiContext, $r('app.string.poemct_copied'), 1000);
    console.info('[PoemContent] copied poem=' + this.poemParam.n);
  }

  // 点击诗人：跳转到该诗人的作品列表（诗人详情页）
  private onPoetTap(): void {
    if (!this.poetName) {
      return;
    }
    let poet: PoetItem | null = this.viewModel.getPoetByName(this.poetName);
    if (poet) {
      let detail: PoetDetail = this.viewModel.loadPoetDetail(
        this.uiContext.getHostContext() as Context, poet.n, poet.i, poet.d);
      let stack: NavPathStack = this.getNavPathStack();
    if (stack) {
      stack.pushPathByName('PoetryDetailPage', detail);
    }
      console.info('[PoemContent] tap poet=' + this.poetName + ', poems=' + detail.poems.length.toString());
    } else {
      ToastUtil.show(this.uiContext, $r('app.string.poemct_poet_not_found'), 1000);
      console.warn('[PoemContent] poet not found: ' + this.poetName);
    }
  }

  // 点击朝代：跳转到诗词查询页并按该朝代筛选
  private onDynastyTap(): void {
    if (!this.poemParam.d) {
      return;
    }
    let queryParam: DynastyQueryParam = new DynastyQueryParam();
    queryParam.dynasty = this.poemParam.d;
    let stack: NavPathStack = this.getNavPathStack();
    if (stack) {
      stack.pushPathByName('PoetryQueryPage', queryParam);
    }
    console.info('[PoemContent] tap dynasty=' + this.poemParam.d);
  }

  private toggleFav(): void {
    let ctx: Context = this.uiContext.getHostContext() as Context;
    if (this.isFav) {
      FavoritesUtil.remove(ctx, 'poem', this.poemParam.n);
      this.isFav = false;
      AppStorage.setOrCreate('PoemFavStatus', false);
      ToastUtil.show(this.uiContext, $r('app.string.poemct_unfavorited'), 1000);
    } else {
      let item: FavoriteItem = new FavoriteItem();
      item.type = 'poem';
      item.title = this.poemParam.n;
      item.subtitle = this.poetName + ' \u00B7 ' + this.poemParam.d;
      item.data = JSON.stringify(this.poemParam);
      let res: FavoriteAddResult = FavoritesUtil.add(ctx, item);
      this.isFav = true;
      AppStorage.setOrCreate('PoemFavStatus', true);
      if (res.truncated) {
        ToastUtil.show(this.uiContext, $r('app.string.poemct_fav_full'), 2000);
      } else {
        ToastUtil.show(this.uiContext, $r('app.string.poemct_favorited'), 1000);
      }
    }
    FavoritesUtil.invalidateCache();
  }

  private openReadingListPicker(): void {
    this.readingLists = AddToReadingListUtil.getLists(this.uiContext.getHostContext() as Context);
    this.showCreateInPicker = false;
    this.newListName = '';
    this.showReadingListPicker = true;
  }

  private createListAndAdd(): void {
    let name: string = this.newListName.trim();
    if (!name) {
      ToastUtil.show(this.uiContext, $r('app.string.readlist_input_name'), 1000);
      return;
    }
    let list: ReadingList = ReadingListStore.addList(this.uiContext.getHostContext() as Context, name);
    this.newListName = '';
    this.showCreateInPicker = false;
    this.addToReadingList(list.id);
  }

  private openCharPicker(): void {
    this.pickerChars = CharBookUtil.extractChars(this.poemParam.c);
    this.bookChars = CharBookUtil.load(this.uiContext.getHostContext() as Context);
    this.selectedChars = [];
    this.showCharPicker = true;
  }

  private togglePickChar(ch: string): void {
    let next: string[] = [];
    let found: boolean = false;
    for (let i = 0; i < this.selectedChars.length; i++) {
      if (this.selectedChars[i] === ch) {
        found = true;
      } else {
        next.push(this.selectedChars[i]);
      }
    }
    if (!found) {
      next.push(ch);
    }
    this.selectedChars = next;
  }

  private confirmAddToCharBook(): void {
    let added: number = CharBookUtil.addChars(this.uiContext.getHostContext() as Context, this.selectedChars);
    this.showCharPicker = false;
    if (added > 0) {
      ToastUtil.show(this.uiContext, $r('app.string.poemct_charbook_added', added), 1500);
    } else {
      ToastUtil.show(this.uiContext, $r('app.string.poemct_charbook_dup'), 1500);
    }
  }

  private addToReadingList(listId: string): void {
    let subtitle: string = this.poetName;
    if (this.poemParam.d) {
      subtitle += ' \u00B7 ' + this.poemParam.d;
    }
    let result: AddToListResult = AddToReadingListUtil.addToListWithCheck(
      this.uiContext.getHostContext() as Context, listId, 'poem', this.poemParam.n, subtitle, this.poemParam.c);
    this.showReadingListPicker = false;
    if (result.success) {
      this.inReadingList = true;
    }
    ToastUtil.show(this.uiContext, result.msg, 1500);
  }

  @Builder
  ReadingListButton() {
    Text('\uD83D\uDCD6')
      .fontSize(14)
      .fontColor($r('app.color.poetry_green'))
      .backgroundColor($r('app.color.poetry_green') + '18')
      .borderRadius(16)
      .padding({ left: 20, right: 20, top: 8, bottom: 8 })
      .accessibilityText(this.inReadingList ? $r('app.string.poemct_in_reading_list') : $r('app.string.poemct_add_to_reading'))
      .onClick(() => {
        this.openReadingListPicker();
      })
  }

  build() {
    Stack() {
      Column() {
        Scroll() {
          Column() {
            Text(this.poemParam.n)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
              .width('100%')
              .textAlign(TextAlign.Center)

            if (this.poetName || this.poemParam.d) {
              Row({ space: 6 }) {
                if (this.poetName) {
                  Text(this.poetName)
                    .fontSize(14)
                    .fontColor($r('app.color.poetry_green'))
                    .decoration({ type: TextDecorationType.Underline, color: $r('app.color.poetry_green') })
                    .onClick(() => {
                      this.onPoetTap();
                    })
                }
                if (this.poetName && this.poemParam.d) {
                  Text('\u00B7')
                    .fontSize(14)
                    .fontColor($r('app.color.tertiary_text'))
                }
                if (this.poemParam.d) {
                  Text(this.poemParam.d)
                    .fontSize(14)
                    .fontColor($r('app.color.poetry_green'))
                    .decoration({ type: TextDecorationType.Underline, color: $r('app.color.poetry_green') })
                    .onClick(() => {
                      this.onDynastyTap();
                    })
                }
              }
              .width('100%')
              .margin({ top: 8 })
              .justifyContent(FlexAlign.Center)
            }

            if (this.poemParam.f) {
              Text(this.poemParam.f)
                .fontSize(12)
                .fontColor($r('app.color.poetry_green'))
                .backgroundColor($r('app.color.poetry_green') + '18')
                .borderRadius(8)
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                .margin({ top: 8 })
            }

            Text(this.poemParam.c)
              .fontSize(16)
              .fontColor($r('app.color.secondary_text'))
              .lineHeight(30)
              .width('100%')
              .margin({ top: 20 })
              .padding({ left: 8, right: 8 })

            Row({ space: 12 }) {
              Text(this.isFav ? '\u2665' : '\u2661')
                .fontSize(14)
                .fontColor(this.isFav ? $r('app.color.danger_red') : $r('app.color.poetry_green'))
                .backgroundColor(this.isFav ? $r('app.color.danger_red') + '18' : $r('app.color.poetry_green') + '18')
                .borderRadius(16)
                .padding({ left: 20, right: 20, top: 8, bottom: 8 })
                .accessibilityText(this.isFav ? $r('app.string.poemct_a11y_unfav') : $r('app.string.poemct_a11y_fav'))
                .onClick(() => {
                  this.toggleFav();
                })

              if (this.inReadingList) {
                Badge({
                  value: '',
                  position: BadgePosition.RightTop,
                  style: { badgeSize: 8, badgeColor: $r('app.color.danger_red') }
                }) {
                  this.ReadingListButton()
                }
              } else {
                this.ReadingListButton()
              }

              Text($r('app.string.poemct_copy'))
                .fontSize(14)
                .fontColor($r('app.color.on_accent_text'))
                .backgroundColor($r('app.color.poetry_green'))
                .borderRadius(16)
                .padding({ left: 24, right: 24, top: 8, bottom: 8 })
                .onClick(() => {
                  this.copyPoem();
                })

              Text($r('app.string.poemct_share_image'))
                .fontSize(14)
                .fontColor($r('app.color.on_accent_text'))
                .backgroundColor($r('app.color.poetry_green'))
                .borderRadius(16)
                .padding({ left: 20, right: 20, top: 8, bottom: 8 })
                .onClick(() => {
                  this.onShareImage();
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .margin({ top: 24 })

            Row({ space: 6 }) {
              Text($r('app.string.poemct_trace'))
                .fontSize(13)
                .fontColor($r('app.color.on_accent_text'))
              Text($r('app.string.poemct_pick_chars_hint'))
                .fontSize(13)
                .fontColor($r('app.color.on_accent_text'))
            }
            .backgroundColor($r('app.color.danger_red'))
            .borderRadius(16)
            .padding({ left: 20, right: 20, top: 8, bottom: 8 })
            .margin({ top: 12 })
            .onClick(() => {
              this.openCharPicker();
            })

            if (this.showShareCard) {
              ShareImageCard({
                mdText: this.shareMdText,
                accentColor: '#4A7C6F',
                bgColor: '#fdf8f0',
                cardId: 'poem_share_card',
                theme: Md2PngTemplates.getPoetryTemplate(),
                autoShare: true,
                onAutoShared: () => {
                  this.showShareCard = false;
                }
              })
                .position({ x: -10000, y: 0 })
            }
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 16, bottom: 24 })
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: 720 })

      if (this.showReadingListPicker) {
        this.ReadingListPickerOverlay()
      }

      if (this.showCharPicker) {
        this.CharPickerOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  ReadingListPickerOverlay() {
    Column() {
      Column() {
        Text(this.showCreateInPicker ? $r('app.string.readlist_create_title') : $r('app.string.poemct_add_to_reading'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .margin({ bottom: 16 })

        if (this.readingLists.length > 0) {
          List({ space: 8 }) {
            ForEach(this.readingLists, (list: ReadingList) => {
              ListItem() {
                Row() {
                  Text(list.name)
                    .fontSize(15)
                    .fontColor($r('app.color.primary_text'))
                    .layoutWeight(1)
                  Text($r('app.string.poemct_items_count', list.items.length))
                    .fontSize(12)
                    .fontColor($r('app.color.tertiary_text'))
                    .margin({ left: 8 })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .backgroundColor($r('app.color.page_background'))
                .borderRadius(10)
                .onClick(() => {
                  this.addToReadingList(list.id);
                })
              }
            }, (list: ReadingList) => list.id)
          }
          .width('100%')
          .constraintSize({ maxHeight: '50%' })
        } else if (!this.showCreateInPicker) {
          Text($r('app.string.poemct_no_lists'))
            .fontSize(14)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 20, bottom: 12 })

          Text($r('app.string.readlist_new_list'))
            .fontSize(15)
            .fontColor($r('app.color.on_accent_text'))
            .backgroundColor($r('app.color.poetry_green'))
            .borderRadius(22)
            .padding({ left: 28, right: 28, top: 10, bottom: 10 })
            .margin({ bottom: 8 })
            .onClick(() => {
              this.showCreateInPicker = true;
            })
        } else {
          TextInput({ placeholder: $r('app.string.readlist_name_hint'), text: this.newListName })
            .width('100%')
            .height(44)
            .fontSize(15)
            .fontColor($r('app.color.primary_text'))
            .placeholderColor($r('app.color.hint_text'))
            .backgroundColor($r('app.color.page_background'))
            .borderRadius(12)
            .padding({ left: 16, right: 16 })
            .margin({ top: 12 })
            .onChange((value: string) => {
              this.newListName = value;
            })

          Row({ space: 12 }) {
            Text($r('app.string.readlist_cancel'))
              .fontSize(15)
              .fontColor($r('app.color.tertiary_text'))
              .backgroundColor($r('app.color.border_color'))
              .borderRadius(22)
              .padding({ left: 28, right: 28, top: 10, bottom: 10 })
              .onClick(() => {
                this.showCreateInPicker = false;
              })

            Text($r('app.string.readlist_create'))
              .fontSize(15)
              .fontColor($r('app.color.on_accent_text'))
              .backgroundColor($r('app.color.poetry_green'))
              .borderRadius(22)
              .padding({ left: 28, right: 28, top: 10, bottom: 10 })
              .onClick(() => {
                this.createListAndAdd();
              })
          }
          .margin({ top: 16 })
        }

        Text($r('app.string.readlist_cancel'))
          .fontSize(15)
          .fontColor($r('app.color.tertiary_text'))
          .backgroundColor($r('app.color.border_color'))
          .borderRadius(22)
          .padding({ left: 32, right: 32, top: 10, bottom: 10 })
          .margin({ top: 12 })
          .onClick(() => {
            this.showReadingListPicker = false;
          })
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
      this.showReadingListPicker = false;
    })
  }

  @Builder
  CharPickerOverlay() {
    Column() {
      Column() {
        Text($r('app.string.poemct_pick_chars_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))

        Text($r('app.string.poemct_pick_chars_desc'))
          .fontSize(12)
          .fontColor($r('app.color.tertiary_text'))
          .margin({ top: 6, bottom: 14 })

        Scroll() {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
            ForEach(this.pickerChars, (ch: string) => {
              Text(ch)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.selectedChars.indexOf(ch) >= 0 ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
                .backgroundColor(this.selectedChars.indexOf(ch) >= 0 ?
                  $r('app.color.danger_red') : $r('app.color.page_background'))
                .borderRadius(10)
                .border({
                  width: this.bookChars.indexOf(ch) >= 0 ? 1.5 : 0,
                  color: $r('app.color.success_green')
                })
                .width(40)
                .height(40)
                .textAlign(TextAlign.Center)
                .margin(4)
                .onClick(() => {
                  this.togglePickChar(ch);
                })
            }, (ch: string) => ch)
          }
          .width('100%')
        }
        .constraintSize({ maxHeight: '40%' })
        .width('100%')

        Row({ space: 12 }) {
          Text($r('app.string.readlist_cancel'))
            .fontSize(15)
            .fontColor($r('app.color.tertiary_text'))
            .backgroundColor($r('app.color.border_color'))
            .borderRadius(20)
            .padding({ left: 24, right: 24, top: 9, bottom: 9 })
            .onClick(() => {
              this.showCharPicker = false;
            })

          Text($r('app.string.poemct_add_to_book', this.selectedChars.length))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.selectedChars.length > 0 ? $r('app.color.on_accent_text') : $r('app.color.tertiary_text'))
            .backgroundColor(this.selectedChars.length > 0 ? $r('app.color.danger_red') : $r('app.color.border_color'))
            .borderRadius(20)
            .padding({ left: 20, right: 20, top: 9, bottom: 9 })
            .margin({ top: 16 })
            .onClick(() => {
              if (this.selectedChars.length > 0) {
                this.confirmAddToCharBook();
              }
            })
        }
        .margin({ top: 8 })
      }
      .width('88%')
      .padding(20)
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
      this.showCharPicker = false;
    })
  }
}
