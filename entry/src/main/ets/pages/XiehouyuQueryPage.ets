import { XiehouyuViewModel } from '../viewmodel/XiehouyuViewModel';
import { XiehouyuItem, XiehouyuCategory } from '../model/XiehouyuModels';
import { ClipboardUtil } from '../common/utils/ClipboardUtil';
import { preferences } from '@kit.ArkData';
import { FavoritesUtil, FavoriteItem, FavoriteAddResult } from '../common/utils/FavoritesUtil';
import { ErrorState } from '../components/ErrorState';
import { ShareImageCard } from '../components/ShareImageCard';
import { buildXiehouyuMarkdown } from '../common/utils/ShareImageUtil';
import { Md2PngTemplates } from '../model/Md2PngModels';
import { AddToReadingListUtil, AddToListResult } from '../common/utils/AddToReadingListUtil';
import { ReadingList, ReadingListStore } from '../model/ReadingListModels';
import { StickinessUtil } from '../common/utils/StickinessUtil';
import { ToastUtil } from '../common/utils/ToastUtil';
import { StrUtil } from '../common/utils/StrUtil';

class XiehouyuListDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private items: XiehouyuItem[] = [];
  private totalSize: number = 0;

  totalCount(): number {
    return this.items.length;
  }

  getTotalSize(): number {
    return this.totalSize;
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

  reset(newItems: XiehouyuItem[], total: number): void {
    this.items = newItems.slice(0);
    this.totalSize = total;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  append(moreItems: XiehouyuItem[]): void {
    let oldLen: number = this.items.length;
    for (let i = 0; i < moreItems.length; i++) {
      this.items.push(moreItems[i]);
    }
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataAdd(oldLen);
    }
  }

  hasMore(): boolean {
    return this.items.length < this.totalSize;
  }
}

@Builder
export function XiehouyuQueryPageBuilder() {
  NavDestination() {
    XiehouyuQueryContent()
  }
  .title($r('app.string.page_xiehouyu_query'))
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct XiehouyuQueryContent {
  @State activeTab: string = 'search';
  @State loading: boolean = true;
  @State hasError: boolean = false;
  @State searchQuery: string = '';
  @State searchHistory: string[] = [];
  @State searchResults: XiehouyuItem[] = [];
  @State categories: XiehouyuCategory[] = [];
  @State activeCategory: string = '';
  @State revealAnswer: string = '';
  @State browseInited: boolean = false;
  @State categoryTotal: number = 0;
  @State loadedCount: number = 0;
  private categoryDataSource: XiehouyuListDataSource = new XiehouyuListDataSource();
  private categoryOffset: number = 0;
  private readonly PAGE_SIZE: number = 50;
  private isLoadingMore: boolean = false;
  @State guessItem: XiehouyuItem | null = null;
  @State guessInput: string = '';
  @State guessMsg: ResourceStr = '';
  @State guessCorrect: boolean = false;
  @State guessScore: number = 0;
  @State guessTotal: number = 0;
  @State guessStreak: number = 0;
  @State detailItem: XiehouyuItem | null = null;
  @State isFav: boolean = false;
  @State showShareCard: boolean = false;
  @State shareMdText: string = '';
  private viewModel: XiehouyuViewModel = XiehouyuViewModel.getInstance();
  private uiContext: UIContext = this.getUIContext();
  private detailDialogController: CustomDialogController | null = null;

  aboutToAppear(): void {
    this.loadHistory();
    setTimeout(() => {
      this.loadData();
    }, 0);
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

  private doSearch(addHistory: boolean = true): void {
    let q: string = this.searchQuery.trim();
    if (!q) {
      this.searchResults = [];
      return;
    }
    this.searchResults = this.viewModel.search(q);
    if (addHistory) {
      this.addToHistory(q);
    }
    console.info('[Xiehouyu] search q=' + q + ', results=' + this.searchResults.length.toString());
  }

  private loadHistory(): void {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(
        this.uiContext.getHostContext() as Context, { name: 'app_cache' });
      let histStr: string = prefs.getSync('xiehouyu_query_history', '') as string;
      if (histStr) {
        this.searchHistory = JSON.parse(histStr) as string[];
      }
    } catch (e) {
      this.searchHistory = [];
    }
  }

  private saveHistory(): void {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(
        this.uiContext.getHostContext() as Context, { name: 'app_cache' });
      prefs.putSync('xiehouyu_query_history', JSON.stringify(this.searchHistory));
      prefs.flush();
    } catch (e) {
    }
  }

  private addToHistory(word: string): void {
    let idx: number = this.searchHistory.indexOf(word);
    if (idx >= 0) {
      this.searchHistory.splice(idx, 1);
    }
    this.searchHistory.unshift(word);
    if (this.searchHistory.length > 5) {
      this.searchHistory = this.searchHistory.slice(0, 5);
    }
    this.saveHistory();
  }

  private onCategoryTap(key: string): void {
    if (this.activeCategory === key) {
      return;
    }
    this.activeCategory = key;
    this.categoryOffset = 0;
    let total: number = this.viewModel.getCategoryTotal(key);
    this.categoryTotal = total;
    let firstPage: XiehouyuItem[] = this.viewModel.getCategoryItemsPage(key, 0, this.PAGE_SIZE);
    this.categoryDataSource.reset(firstPage, total);
    this.loadedCount = firstPage.length;
  }

  private initBrowseTab(): void {
    if (this.browseInited) {
      return;
    }
    this.browseInited = true;
    if (this.categories.length > 0) {
      let firstKey: string = this.categories[0].key;
      this.activeCategory = firstKey;
      let total: number = this.viewModel.getCategoryTotal(firstKey);
      this.categoryTotal = total;
      let firstPage: XiehouyuItem[] = this.viewModel.getCategoryItemsPage(firstKey, 0, this.PAGE_SIZE);
      this.categoryDataSource.reset(firstPage, total);
      this.loadedCount = firstPage.length;
    }
  }

  private loadMore(): void {
    if (this.isLoadingMore || !this.categoryDataSource.hasMore()) {
      return;
    }
    this.isLoadingMore = true;
    let nextOffset: number = this.categoryOffset + this.PAGE_SIZE;
    let moreItems: XiehouyuItem[] = this.viewModel.getCategoryItemsPage(this.activeCategory, nextOffset, this.PAGE_SIZE);
    if (moreItems.length > 0) {
      this.categoryOffset = nextOffset;
      this.categoryDataSource.append(moreItems);
      this.loadedCount = this.categoryDataSource.totalCount();
    }
    this.isLoadingMore = false;
  }

  private startNewGuess(): void {
    let items: XiehouyuItem[] = this.viewModel.getRandomItems(1);
    if (items.length > 0) {
      this.guessItem = items[0];
      this.guessInput = '';
      this.guessMsg = '';
      this.guessCorrect = false;
      this.revealAnswer = '';
      if (this.activeTab === 'guess') {
        setTimeout(() => {
          this.getUIContext().getFocusController().requestFocus('guess_input');
        }, 100);
      }
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
      this.guessStreak++;
      this.guessCorrect = true;
      if (this.guessStreak >= 2) {
        this.guessMsg = $r('app.string.xhyq_guess_correct_streak', this.guessStreak);
      } else {
        this.guessMsg = $r('app.string.xhyq_guess_correct');
      }
      setTimeout(() => {
        this.startNewGuess();
      }, 1000);
    } else {
      this.guessStreak = 0;
      this.guessCorrect = false;
      this.guessMsg = $r('app.string.xhyq_guess_wrong', this.guessItem.answer);
    }
  }

  private toggleReveal(): void {
    if (this.revealAnswer) {
      this.revealAnswer = '';
    } else if (this.guessItem) {
      this.revealAnswer = this.guessItem.answer;
    }
  }

  private isItemFav(item: XiehouyuItem): boolean {
    let ctx: Context = this.uiContext.getHostContext() as Context;
    return FavoritesUtil.isFavorite(ctx, 'xiehouyu', item.riddle);
  }

  private onItemTap(item: XiehouyuItem): void {
    this.detailItem = item;
    let ctx: Context = this.uiContext.getHostContext() as Context;
    this.isFav = FavoritesUtil.isFavorite(ctx, 'xiehouyu', item.riddle);
    this.detailDialogController = new CustomDialogController({
      builder: XiehouyuDetailModal({ detailItem: this.detailItem, isFav: this.isFav }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });
    this.detailDialogController.open();
    StickinessUtil.incrementBrowseCount(ctx);
  }

  private onCopyItem(item: XiehouyuItem): void {
    ClipboardUtil.copy(item.riddle + '——' + item.answer);
    ToastUtil.show(this.uiContext, $r('app.string.idiomq_copied'), 1000);
  }

  private toggleFav(item: XiehouyuItem): void {
    let ctx: Context = this.uiContext.getHostContext() as Context;
    if (this.isFav) {
      FavoritesUtil.remove(ctx, 'xiehouyu', item.riddle);
      this.isFav = false;
      ToastUtil.show(this.uiContext, $r('app.string.xhyq_unfaved'), 1000);
    } else {
      let fav: FavoriteItem = new FavoriteItem();
      fav.type = 'xiehouyu';
      fav.title = item.riddle;
      fav.subtitle = item.answer;
      fav.data = JSON.stringify({ riddle: item.riddle, answer: item.answer });
      let res: FavoriteAddResult = FavoritesUtil.add(ctx, fav);
      this.isFav = true;
      if (res.truncated) {
        ToastUtil.show(this.uiContext, $r('app.string.xhyq_fav_full'), 2000);
      } else {
        ToastUtil.show(this.uiContext, $r('app.string.xhyq_faved'), 1000);
      }
    }
    FavoritesUtil.invalidateCache();
  }

  build() {
    Column() {
      Column() {
        this.TabBar()
        if (this.loading) {
          Column() {
            LoadingProgress()
              .width(48)
              .height(48)
              .color($r('app.color.idiom_orange'))
            Text($r('app.string.poemq_loading'))
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
              text: StrUtil.text(this.uiContext.getHostContext() as Context, $r('app.string.poemq_load_failed')),
              subText: StrUtil.text(this.uiContext.getHostContext() as Context, $r('app.string.xhyq_load_failed_sub')),
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
      .constraintSize({ maxWidth: 720 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  TabBar() {
    Row() {
      Text($r('app.string.xhyq_tab_search'))
        .fontSize(14)
        .fontColor(this.activeTab === 'search' ? $r('app.color.on_accent_text') : $r('app.color.secondary_text'))
        .backgroundColor(this.activeTab === 'search' ? $r('app.color.idiom_orange') : $r('app.color.border_color'))
        .borderRadius(12)
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .onClick(() => {
          this.activeTab = 'search';
        })

      Text($r('app.string.xhyq_tab_browse'))
        .fontSize(14)
        .fontColor(this.activeTab === 'browse' ? $r('app.color.on_accent_text') : $r('app.color.secondary_text'))
        .backgroundColor(this.activeTab === 'browse' ? $r('app.color.idiom_orange') : $r('app.color.border_color'))
        .borderRadius(12)
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .margin({ left: 8 })
        .onClick(() => {
          this.activeTab = 'browse';
          this.initBrowseTab();
        })

      Text($r('app.string.xhyq_tab_guess'))
        .fontSize(14)
        .fontColor(this.activeTab === 'guess' ? $r('app.color.on_accent_text') : $r('app.color.secondary_text'))
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
        TextInput({ placeholder: $r('app.string.xhyq_search_hint'), text: this.searchQuery })
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
            this.doSearch(false);
          })
          .onSubmit(() => {
            this.doSearch();
          })

        Text($r('app.string.poemq_search'))
          .fontSize(12)
          .fontColor($r('app.color.on_accent_text'))
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

      this.HistorySection()

      if (this.searchResults.length > 0) {
        Row() {
          Text($r('app.string.search_results'))
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

                if (this.isItemFav(item)) {
                  Text('\u2665')
                    .fontSize(14)
                    .fontColor($r('app.color.danger_red'))
                    .margin({ right: 6 })
                }

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
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      } else if (this.searchQuery) {
        Column() {
          Text($r('app.string.xhyq_no_match'))
            .fontSize(14)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 30 })
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column() {
          Text($r('app.string.xhyq_search_empty'))
            .fontSize(16)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 60 })
          Text($r('app.string.xhyq_search_hint_sub'))
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
  HistorySection() {
    if (this.searchHistory.length > 0) {
      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.searchHistory, (word: string) => {
            Text(word)
              .fontSize(13)
              .fontColor($r('app.color.idiom_orange'))
              .backgroundColor($r('app.color.idiom_orange') + '18')
              .borderRadius(10)
              .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              .onClick(() => {
                this.searchQuery = word;
                this.doSearch();
              })
          }, (word: string) => word)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .width('100%')
      .padding({ left: 12, right: 12, top: 2, bottom: 4 })
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
  }

  @Builder
  BrowseTab() {
    Column() {
      if (this.categories.length > 0) {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Start }) {
          ForEach(this.categories, (cat: XiehouyuCategory) => {
            Text(cat.label)
              .fontSize(13)
              .fontColor(this.activeCategory === cat.key ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
              .backgroundColor(this.activeCategory === cat.key ? $r('app.color.idiom_orange') : $r('app.color.card_background'))
              .borderRadius(8)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .margin({ right: 6, bottom: 6 })
              .onClick(() => {
                this.onCategoryTap(cat.key);
              })
          }, (cat: XiehouyuCategory) => cat.key)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      }

      if (this.activeCategory && this.loadedCount > 0) {
        Row() {
          Text($r('app.string.xhyq_related'))
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          Text('(' + this.categoryTotal.toString() + ')')
            .fontSize(12)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ left: 4 })
          Text($r('app.string.xhyq_loaded_count', this.loadedCount))
            .fontSize(11)
            .fontColor($r('app.color.hint_text'))
            .margin({ left: 8 })
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

                if (this.isItemFav(item)) {
                  Text('\u2665')
                    .fontSize(14)
                    .fontColor($r('app.color.danger_red'))
                    .margin({ right: 6 })
                }

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

          ListItem() {
            Row() {
              if (this.categoryDataSource.hasMore()) {
                LoadingProgress()
                  .width(24)
                  .height(24)
                  .color($r('app.color.idiom_orange'))
                  .margin({ right: 8 })
                Text($r('app.string.xhyq_load_more'))
                  .fontSize(13)
                  .fontColor($r('app.color.tertiary_text'))
              } else if (this.categoryTotal > 0) {
                Text($r('app.string.xhyq_all_loaded'))
                  .fontSize(13)
                  .fontColor($r('app.color.hint_text'))
              }
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 12, bottom: 12 })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 10, right: 10 })
        .cachedCount(5)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .onReachEnd(() => {
          this.loadMore();
        })
      } else if (this.activeCategory) {
        Column() {
          Text($r('app.string.xhyq_category_empty'))
            .fontSize(14)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 30 })
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column() {
          Text($r('app.string.xhyq_pick_category'))
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
            Text($r('app.string.xhyq_guess_score', this.guessScore, this.guessTotal))
              .fontSize(14)
              .fontColor($r('app.color.idiom_orange'))
              .fontWeight(FontWeight.Bold)
            Blank()
            Text($r('app.string.xhyq_skip'))
              .fontSize(13)
              .fontColor($r('app.color.idiom_blue'))
              .onClick(() => {
                this.startNewGuess();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16 })

          Column() {
            Text($r('app.string.xhyq_guess_riddle_label'))
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
            TextInput({ placeholder: $r('app.string.xhyq_guess_input_hint'), text: this.guessInput })
              .id('guess_input')
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
            Text($r('app.string.xhyq_submit'))
              .fontSize(14)
              .fontColor($r('app.color.on_accent_text'))
              .backgroundColor($r('app.color.idiom_orange'))
              .borderRadius(20)
              .padding({ left: 24, right: 24, top: 8, bottom: 8 })
              .onClick(() => {
                this.checkGuess();
              })

            Text(this.revealAnswer ? $r('app.string.xhyq_hide_answer') : $r('app.string.xhyq_show_answer'))
              .fontSize(14)
              .fontColor($r('app.color.on_accent_text'))
              .backgroundColor($r('app.color.tertiary_text'))
              .borderRadius(20)
              .padding({ left: 20, right: 20, top: 8, bottom: 8 })
              .onClick(() => {
                this.toggleReveal();
              })

            Text($r('app.string.xhyq_next'))
              .fontSize(14)
              .fontColor($r('app.color.on_accent_text'))
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
            Text($r('app.string.xhyq_answer_label', this.revealAnswer))
            .fontSize(18)
            .fontColor($r('app.color.idiom_orange'))
              .fontWeight(FontWeight.Bold)
              .margin({ top: 16 })
          }

          if (this.guessMsg !== '') {
            Text(this.guessMsg)
              .fontSize(16)
              .fontColor(this.guessCorrect ? $r('app.color.success_green') : $r('app.color.error_red'))
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
  @State inReadingList: boolean = false;
  @State modalShowShare: boolean = false;
  @State modalShareMd: string = '';
  @State showReadingListPicker: boolean = false;
  @State readingLists: ReadingList[] = [];
  @State showCreateInPicker: boolean = false;
  @State newListName: string = '';
  private uiContext: UIContext = this.getUIContext();

  aboutToAppear(): void {
    if (this.detailItem) {
      this.inReadingList = AddToReadingListUtil.isInAnyList(
        this.uiContext.getHostContext() as Context, 'xiehouyu', this.detailItem!.riddle);
    }
  }

  private toggleFav(): void {
    if (!this.detailItem || !this.uiContext) {
      return;
    }
    let ctx: Context = this.uiContext.getHostContext() as Context;
    if (this.isFav) {
      FavoritesUtil.remove(ctx, 'xiehouyu', this.detailItem!.riddle);
      this.isFav = false;
      ToastUtil.show(this.uiContext, $r('app.string.xhyq_unfaved'), 1000);
    } else {
      let fav: FavoriteItem = new FavoriteItem();
      fav.type = 'xiehouyu';
      fav.title = this.detailItem!.riddle;
      fav.subtitle = this.detailItem!.answer;
      fav.data = JSON.stringify({ riddle: this.detailItem!.riddle, answer: this.detailItem!.answer });
      let res: FavoriteAddResult = FavoritesUtil.add(ctx, fav);
      this.isFav = true;
      if (res.truncated) {
        ToastUtil.show(this.uiContext, $r('app.string.xhyq_fav_full'), 2000);
      } else {
        ToastUtil.show(this.uiContext, $r('app.string.xhyq_faved'), 1000);
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
      ToastUtil.show(this.uiContext, $r('app.string.xhyq_input_list_name'), 1000);
      return;
    }
    let list: ReadingList = ReadingListStore.addList(this.uiContext.getHostContext() as Context, name);
    this.newListName = '';
    this.showCreateInPicker = false;
    this.addToReadingList(list.id);
  }

  private addToReadingList(listId: string): void {
    if (!this.detailItem) {
      return;
    }
    let result: AddToListResult = AddToReadingListUtil.addToListWithCheck(
      this.uiContext.getHostContext() as Context, listId, 'xiehouyu',
      this.detailItem!.riddle, this.detailItem!.answer,
      this.detailItem!.riddle + '\u2014\u2014' + this.detailItem!.answer);
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
      .fontColor($r('app.color.idiom_orange'))
      .backgroundColor($r('app.color.idiom_orange') + '18')
      .borderRadius(12)
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .accessibilityText(this.inReadingList ? $r('app.string.xhyq_in_reading_list') : $r('app.string.xhyq_add_to_reading_list'))
      .onClick(() => {
        this.openReadingListPicker();
      })
  }

  build() {
    Stack() {
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
              Text($r('app.string.xhyq_riddle_label'))
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

              Text($r('app.string.xhyq_answer_label_short'))
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

                Text($r('app.string.xhyq_copy'))
                  .fontSize(14)
                  .fontColor($r('app.color.secondary_text'))
                  .backgroundColor($r('app.color.border_color'))
                  .borderRadius(12)
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                  .onClick(() => {
                    ClipboardUtil.copy(this.detailItem!.riddle + '——' + this.detailItem!.answer);
                    ToastUtil.show(this.uiContext, $r('app.string.idiomq_copied'), 1000);
                  })

                Text($r('app.string.xhyq_share_image'))
                  .fontSize(14)
                  .fontColor($r('app.color.on_accent_text'))
                  .backgroundColor($r('app.color.idiom_orange'))
                  .borderRadius(12)
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                  .onClick(() => {
                    this.modalShowShare = false;
                    this.modalShareMd = buildXiehouyuMarkdown(this.detailItem!);
                    this.modalShowShare = true;
                  })
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)

              if (this.modalShowShare) {
                ShareImageCard({
                  mdText: this.modalShareMd,
                  accentColor: '#C2410C',
                  bgColor: '#fffbf0',
                  cardId: 'xiehouyu_share_card',
                  theme: Md2PngTemplates.getXiehouyuTemplate(),
                  autoShare: true,
                  onAutoShared: () => {
                    this.modalShowShare = false;
                  }
                })
              }
            }
            .padding({ left: 20, right: 20, bottom: 20 })
          }
          .scrollable(ScrollDirection.Vertical)
          .constraintSize({ maxHeight: '50%' })
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        }
      }
      .width('85%')
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(20)
      .shadow({ radius: 20, color: '#33000000', offsetY: 8 })

      if (this.showReadingListPicker) {
        this.ReadingListPickerOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ReadingListPickerOverlay() {
    Column() {
      Column() {
         Text(this.showCreateInPicker ? $r('app.string.xhyq_create_list_title') : $r('app.string.xhyq_add_to_reading_list'))
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
                  Text($r('app.string.xhyq_item_count', list.items.length))
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
          Text($r('app.string.xhyq_no_reading_list'))
            .fontSize(14)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 20, bottom: 12 })

          Text($r('app.string.xhyq_new_list'))
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
          TextInput({ placeholder: $r('app.string.xhyq_list_name_hint'), text: this.newListName })
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
        Text($r('app.string.xhyq_cancel'))
              .fontSize(15)
              .fontColor($r('app.color.tertiary_text'))
              .backgroundColor($r('app.color.border_color'))
              .borderRadius(22)
              .padding({ left: 28, right: 28, top: 10, bottom: 10 })
              .onClick(() => {
                this.showCreateInPicker = false;
              })

            Text($r('app.string.xhyq_create'))
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

            Text($r('app.string.xhyq_cancel'))
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
}
