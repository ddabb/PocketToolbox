import { XiehouyuViewModel } from '../viewmodel/XiehouyuViewModel';
import { XiehouyuItem, XiehouyuCategory } from '../model/XiehouyuModels';
import { ClipboardUtil } from '../common/utils/ClipboardUtil';
import { FavoritesUtil, FavoriteItem } from '../common/utils/FavoritesUtil';
import { ErrorState } from '../components/ErrorState';
import { ShareImageCard } from '../components/ShareImageCard';
import { buildXiehouyuMarkdown } from '../common/utils/ShareImageUtil';

class XiehouyuListDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private items: XiehouyuItem[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): Object {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    let pos: number = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  setItems(newItems: XiehouyuItem[]): void {
    this.items = newItems;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }
}

@Builder
export function XiehouyuQueryPageBuilder() {
  NavDestination() {
    XiehouyuQueryContent()
  }
  .title('歇后语查询')
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct XiehouyuQueryContent {
  @State activeTab: string = 'search';
  @State loading: boolean = true;
  @State hasError: boolean = false;
  @State searchQuery: string = '';
  @State searchResults: XiehouyuItem[] = [];
  @State categories: XiehouyuCategory[] = [];
  @State activeCategory: string = '';
  @State revealAnswer: string = '';
  private categorySwitching: boolean = false;
  private categoryDataSource: XiehouyuListDataSource = new XiehouyuListDataSource();
  @State guessItem: XiehouyuItem | null = null;
  @State guessInput: string = '';
  @State guessMsg: string = '';
  @State guessScore: number = 0;
  @State guessTotal: number = 0;
  @State detailItem: XiehouyuItem | null = null;
  @State isFav: boolean = false;
  @State showShareCard: boolean = false;
  @State shareMdText: string = '';
  private viewModel: XiehouyuViewModel = XiehouyuViewModel.getInstance();
  private uiContext: UIContext = this.getUIContext();
  private detailDialogController: CustomDialogController = new CustomDialogController({
    builder: XiehouyuDetailModal({ detailItem: this.detailItem, isFav: this.isFav }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true
  });

  aboutToAppear(): void {
    this.loadData();
  }

  private loadData(): void {
    if (this.viewModel.isReady()) {
      this.loading = false;
      this.categories = this.viewModel.getCategories();
      this.startNewGuess();
      return;
    }
    this.loading = true;
    this.hasError = false;
    let ok: boolean = this.viewModel.loadData(this.uiContext.getHostContext() as Context);
    if (ok) {
      this.loading = false;
      this.categories = this.viewModel.getCategories();
      this.startNewGuess();
    } else {
      this.hasError = true;
      this.loading = false;
    }
  }

  private doSearch(): void {
    let q: string = this.searchQuery.trim();
    if (!q) {
      this.searchResults = [];
      return;
    }
    this.searchResults = this.viewModel.search(q);
    console.info('[Xiehouyu] search q=' + q + ', results=' + this.searchResults.length.toString());
  }

  private onCategoryTap(key: string): void {
    if (this.categorySwitching) {
      return;
    }
    if (this.activeCategory === key) {
      return;
    }
    this.categorySwitching = true;
    this.activeCategory = key;
    this.categoryDataSource.setItems(this.viewModel.getCategoryItems(key));
    setTimeout(() => {
      this.categorySwitching = false;
    }, 150);
  }

  private startNewGuess(): void {
    let items: XiehouyuItem[] = this.viewModel.getRandomItems(1);
    if (items.length > 0) {
      this.guessItem = items[0];
      this.guessInput = '';
      this.guessMsg = '';
      this.revealAnswer = '';
    }
  }

  private checkGuess(): void {
    if (!this.guessItem) {
      return;
    }
    let input: string = this.guessInput.trim();
    if (!input) {
      return;
    }
    this.guessTotal++;
    if (input === this.guessItem.answer || this.guessItem.answer.indexOf(input) >= 0 || input.indexOf(this.guessItem.answer) >= 0) {
      this.guessScore++;
      this.guessMsg = '答对了！';
    } else {
      this.guessMsg = '不对哦，答案是：' + this.guessItem.answer;
    }
  }

  private toggleReveal(): void {
    if (this.revealAnswer) {
      this.revealAnswer = '';
    } else if (this.guessItem) {
      this.revealAnswer = this.guessItem.answer;
    }
  }

  private onItemTap(item: XiehouyuItem): void {
    this.detailItem = item;
    let ctx: Context = this.uiContext.getHostContext() as Context;
    this.isFav = FavoritesUtil.isFavorite(ctx, 'xiehouyu', item.riddle);
    this.detailDialogController.open();
  }

  private onCopyItem(item: XiehouyuItem): void {
    ClipboardUtil.copy(item.riddle + '——' + item.answer);
    this.uiContext.getPromptAction().showToast({ message: '已复制到剪贴板', duration: 1000 });
  }

  private toggleFav(item: XiehouyuItem): void {
    let ctx: Context = this.uiContext.getHostContext() as Context;
    if (this.isFav) {
      FavoritesUtil.remove(ctx, 'xiehouyu', item.riddle);
      this.isFav = false;
      this.uiContext.getPromptAction().showToast({ message: '已取消收藏', duration: 1000 });
    } else {
      let fav: FavoriteItem = new FavoriteItem();
      fav.type = 'xiehouyu';
      fav.title = item.riddle;
      fav.subtitle = item.answer;
      fav.data = JSON.stringify({ riddle: item.riddle, answer: item.answer });
      FavoritesUtil.add(ctx, fav);
      this.isFav = true;
      this.uiContext.getPromptAction().showToast({ message: '已收藏', duration: 1000 });
    }
    FavoritesUtil.invalidateCache();
  }

  build() {
    Column() {
      this.TabBar()
      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color($r('app.color.idiom_orange'))
          Text('加载中...')
            .fontSize(16)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.hasError) {
        Column() {
          ErrorState({
            text: '数据加载失败',
            subText: '歇后语数据读取异常，请重试',
            onRetry: () => {
              this.loadData();
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
      } else if (this.activeTab === 'search') {
        this.SearchTab()
      } else if (this.activeTab === 'browse') {
        this.BrowseTab()
      } else {
        this.GuessTab()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  TabBar() {
    Row() {
      Text('搜索查询')
        .fontSize(14)
        .fontColor(this.activeTab === 'search' ? '#ffffff' : $r('app.color.secondary_text'))
        .backgroundColor(this.activeTab === 'search' ? $r('app.color.idiom_orange') : $r('app.color.border_color'))
        .borderRadius(12)
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .onClick(() => {
          this.activeTab = 'search';
        })

      Text('分类浏览')
        .fontSize(14)
        .fontColor(this.activeTab === 'browse' ? '#ffffff' : $r('app.color.secondary_text'))
        .backgroundColor(this.activeTab === 'browse' ? $r('app.color.idiom_orange') : $r('app.color.border_color'))
        .borderRadius(12)
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .margin({ left: 8 })
        .onClick(() => {
          this.activeTab = 'browse';
        })

      Text('猜谜玩法')
        .fontSize(14)
        .fontColor(this.activeTab === 'guess' ? '#ffffff' : $r('app.color.secondary_text'))
        .backgroundColor(this.activeTab === 'guess' ? $r('app.color.idiom_orange') : $r('app.color.border_color'))
        .borderRadius(12)
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .margin({ left: 8 })
        .onClick(() => {
          this.activeTab = 'guess';
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 4 })
  }

  @Builder
  SearchTab() {
    Column() {
      Row() {
        TextInput({ placeholder: '搜索歇后语...', text: this.searchQuery })
          .layoutWeight(1)
          .height(36)
          .fontSize(14)
          .fontColor($r('app.color.primary_text'))
          .placeholderColor($r('app.color.hint_text'))
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(18)
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.searchQuery = value;
          })
          .onSubmit(() => {
            this.doSearch();
          })

        Text('搜索')
          .fontSize(12)
          .fontColor('#ffffff')
          .backgroundColor($r('app.color.idiom_orange'))
          .borderRadius(10)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .margin({ left: 6 })
          .onClick(() => {
            this.doSearch();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 4 })

      if (this.searchResults.length > 0) {
        Row() {
          Text('搜索结果')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          Text('(' + this.searchResults.length.toString() + ')')
            .fontSize(12)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ left: 4 })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 6, bottom: 4 })

        List({ space: 4 }) {
          ForEach(this.searchResults, (item: XiehouyuItem) => {
            ListItem() {
              Row() {
                Column() {
                  Text(item.riddle)
                    .fontSize(14)
                    .fontColor($r('app.color.primary_text'))
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.answer)
                    .fontSize(13)
                    .fontColor($r('app.color.idiom_orange'))
                    .margin({ top: 2 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Text('\u203A')
                  .fontSize(18)
                  .fontColor($r('app.color.hint_text'))
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(8)
              .onClick(() => {
                this.onItemTap(item);
              })
            }
          }, (item: XiehouyuItem) => item.riddle)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 10, right: 10 })
        .cachedCount(10)
      } else if (this.searchQuery) {
        Column() {
          Text('未找到匹配的歇后语')
            .fontSize(14)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 30 })
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column() {
          Text('输入关键词搜索歇后语')
            .fontSize(16)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 60 })
          Text('搜索谜面或谜底')
            .fontSize(13)
            .fontColor($r('app.color.hint_text'))
            .margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  BrowseTab() {
    Column() {
      if (this.categories.length > 0) {
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.categories, (cat: XiehouyuCategory) => {
              Text(cat.label)
                .fontSize(13)
                .fontColor(this.activeCategory === cat.key ? '#ffffff' : $r('app.color.primary_text'))
                .backgroundColor(this.activeCategory === cat.key ? $r('app.color.idiom_orange') : $r('app.color.card_background'))
                .borderRadius(8)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .onClick(() => {
                  this.onCategoryTap(cat.key);
                })
            }, (cat: XiehouyuCategory) => cat.key)
          }
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .padding({ left: 4, right: 4, top: 4, bottom: 4 })
        .backgroundColor($r('app.color.border_color'))
        .borderRadius(8)
        .margin({ left: 12, right: 12, top: 6 })
        .friction(0.6)
      }

      if (this.activeCategory && this.categoryDataSource.totalCount() > 0) {
        Row() {
          Text('相关歇后语')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          Text('(' + this.categoryDataSource.totalCount().toString() + ')')
            .fontSize(12)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ left: 4 })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 8, bottom: 4 })

        List({ space: 4 }) {
          LazyForEach(this.categoryDataSource, (item: XiehouyuItem) => {
            ListItem() {
              Row() {
                Column() {
                  Text(item.riddle)
                    .fontSize(14)
                    .fontColor($r('app.color.primary_text'))
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.answer)
                    .fontSize(13)
                    .fontColor($r('app.color.idiom_orange'))
                    .margin({ top: 2 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Text('\u203A')
                  .fontSize(18)
                  .fontColor($r('app.color.hint_text'))
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(8)
              .onClick(() => {
                this.onItemTap(item);
              })
            }
          }, (item: XiehouyuItem) => item.riddle)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 10, right: 10 })
        .cachedCount(10)
      } else if (this.activeCategory) {
        Column() {
          Text('该分类暂无歇后语')
            .fontSize(14)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 30 })
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column() {
          Text('选择分类浏览歇后语')
            .fontSize(16)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 40 })
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  GuessTab() {
    Column() {
      if (this.guessItem) {
        Column() {
          Row() {
            Text('得分：' + this.guessScore.toString() + '/' + this.guessTotal.toString())
              .fontSize(14)
              .fontColor($r('app.color.idiom_orange'))
              .fontWeight(FontWeight.Bold)
            Blank()
            Text('跳过')
              .fontSize(13)
              .fontColor($r('app.color.idiom_blue'))
              .onClick(() => {
                this.startNewGuess();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16 })

          Column() {
            Text('猜谜面')
              .fontSize(12)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ bottom: 8 })

            Text(this.guessItem.riddle)
              .fontSize(20)
              .fontColor($r('app.color.primary_text'))
              .fontWeight(FontWeight.Bold)
              .textAlign(TextAlign.Center)
              .lineHeight(30)
              .padding({ left: 20, right: 20 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .margin({ top: 30, bottom: 20 })

          Text('—— ?')
            .fontSize(24)
            .fontColor($r('app.color.hint_text'))
            .margin({ bottom: 20 })

          Row() {
            TextInput({ placeholder: '输入你的答案...', text: this.guessInput })
              .layoutWeight(1)
              .height(40)
              .fontSize(16)
              .fontColor($r('app.color.primary_text'))
              .placeholderColor($r('app.color.hint_text'))
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(20)
              .padding({ left: 16, right: 16 })
              .onChange((value: string) => {
                this.guessInput = value;
              })
              .onSubmit(() => {
                this.checkGuess();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .margin({ bottom: 12 })

          Row({ space: 10 }) {
            Text('提交答案')
              .fontSize(14)
              .fontColor('#ffffff')
              .backgroundColor($r('app.color.idiom_orange'))
              .borderRadius(20)
              .padding({ left: 24, right: 24, top: 8, bottom: 8 })
              .onClick(() => {
                this.checkGuess();
              })

            Text(this.revealAnswer ? '隐藏答案' : '查看答案')
              .fontSize(14)
              .fontColor('#ffffff')
              .backgroundColor($r('app.color.tertiary_text'))
              .borderRadius(20)
              .padding({ left: 20, right: 20, top: 8, bottom: 8 })
              .onClick(() => {
                this.toggleReveal();
              })

            Text('下一题')
              .fontSize(14)
              .fontColor('#ffffff')
              .backgroundColor($r('app.color.poetry_green'))
              .borderRadius(20)
              .padding({ left: 20, right: 20, top: 8, bottom: 8 })
              .onClick(() => {
                this.startNewGuess();
              })
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .padding({ left: 16, right: 16 })

          if (this.revealAnswer) {
            Text('答案：' + this.revealAnswer)
            .fontSize(18)
            .fontColor($r('app.color.idiom_orange'))
              .fontWeight(FontWeight.Bold)
              .margin({ top: 16 })
          }

          if (this.guessMsg) {
            Text(this.guessMsg)
              .fontSize(16)
              .fontColor(this.guessMsg.indexOf('对了') >= 0 ? '#2d7d46' : '#e74c3c')
              .fontWeight(FontWeight.Medium)
              .margin({ top: 16 })
          }
        }
        .layoutWeight(1)
      }
    }
    .width('100%')
    .layoutWeight(1)
  }
}
@CustomDialog
struct XiehouyuDetailModal {
  controller?: CustomDialogController;

  @State detailItem: XiehouyuItem | null = null;
  @State isFav: boolean = false;
  @State modalShowShare: boolean = false;
  @State modalShareMd: string = '';
  private uiContext: UIContext = this.getUIContext();

  private toggleFav(): void {
    if (!this.detailItem || !this.uiContext) {
      return;
    }
    let ctx: Context = this.uiContext.getHostContext() as Context;
    if (this.isFav) {
      FavoritesUtil.remove(ctx, 'xiehouyu', this.detailItem!.riddle);
      this.isFav = false;
      this.uiContext.getPromptAction().showToast({ message: '已取消收藏', duration: 1000 });
    } else {
      let fav: FavoriteItem = new FavoriteItem();
      fav.type = 'xiehouyu';
      fav.title = this.detailItem!.riddle;
      fav.subtitle = this.detailItem!.answer;
      fav.data = JSON.stringify({ riddle: this.detailItem!.riddle, answer: this.detailItem!.answer });
      FavoritesUtil.add(ctx, fav);
      this.isFav = true;
      this.uiContext.getPromptAction().showToast({ message: '已收藏', duration: 1000 });
    }
    FavoritesUtil.invalidateCache();
  }

  build() {
    Column() {
      Row() {
        Text()
          .width(1)
          .height(1)
        Blank()
        Text('\u2715')
          .fontSize(18)
          .fontColor($r('app.color.tertiary_text'))
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor($r('app.color.border_color'))
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.controller?.close();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ right: 12, top: 12 })

      if (this.detailItem) {
        Scroll() {
          Column() {
            Text('谜面')
              .fontSize(14)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ bottom: 6 })

            Text(this.detailItem!.riddle)
              .fontSize(20)
              .fontColor($r('app.color.primary_text'))
              .fontWeight(FontWeight.Bold)
              .textAlign(TextAlign.Center)
              .lineHeight(28)
              .width('100%')
              .margin({ bottom: 16 })

            Divider()
              .color($r('app.color.border_color'))
              .margin({ bottom: 16 })

            Text('谜底')
              .fontSize(14)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ bottom: 6 })

            Text(this.detailItem!.answer)
              .fontSize(22)
              .fontColor($r('app.color.idiom_orange'))
              .fontWeight(FontWeight.Bold)
              .textAlign(TextAlign.Center)
              .width('100%')
              .margin({ bottom: 20 })

            Row({ space: 10 }) {
              Text(this.isFav ? '\u2665' : '\u2661')
                .fontSize(14)
                .fontColor(this.isFav ? $r('app.color.danger_red') : $r('app.color.secondary_text'))
                .backgroundColor(this.isFav ? $r('app.color.danger_red') + '18' : $r('app.color.border_color'))
                .borderRadius(12)
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .onClick(() => {
                  this.toggleFav();
                })

              Text('复制')
                .fontSize(14)
                .fontColor($r('app.color.secondary_text'))
                .backgroundColor($r('app.color.border_color'))
                .borderRadius(12)
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .onClick(() => {
                  ClipboardUtil.copy(this.detailItem!.riddle + '——' + this.detailItem!.answer);
                  this.uiContext.getPromptAction().showToast({ message: '已复制到剪贴板', duration: 1000 });
                })

              Text('图片')
                .fontSize(14)
                .fontColor('#ffffff')
                .backgroundColor($r('app.color.idiom_orange'))
                .borderRadius(12)
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .onClick(() => {
                  this.modalShareMd = buildXiehouyuMarkdown(this.detailItem!);
                  this.modalShowShare = !this.modalShowShare;
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)

            if (this.modalShowShare) {
              ShareImageCard({
                mdText: this.modalShareMd,
                accentColor: '#ff6b35',
                bgColor: '#ffffff',
                cardId: 'xiehouyu_share_card'
              })
                .margin({ top: 12 })
            }
          }
          .padding({ left: 20, right: 20, bottom: 20 })
        }
        .scrollable(ScrollDirection.Vertical)
        .constraintSize({ maxHeight: '50%' })
      }
    }
    .width('85%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
    .shadow({ radius: 20, color: '#33000000', offsetY: 8 })
  }
}
