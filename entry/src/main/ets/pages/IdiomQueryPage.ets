import { IdiomViewModel } from '../viewmodel/IdiomViewModel';
import { IdiomQueryResultItem, IdiomDetailItem, SolitaireResult } from '../model/IdiomModels';
import { ClipboardUtil } from '../common/utils/ClipboardUtil';
import { ErrorState } from '../components/ErrorState';
import { DetailModal } from '../components/DetailModal';
import { FavoritesUtil } from '../common/utils/FavoritesUtil';
import { StickinessUtil } from '../common/utils/StickinessUtil';
import { preferences } from '@kit.ArkData';
import { ToastUtil } from '../common/utils/ToastUtil';
import { StrUtil } from '../common/utils/StrUtil';

class IdiomListDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private items: IdiomDetailItem[] = [];

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

  setItems(newItems: IdiomDetailItem[]): void {
    this.items = newItems;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }
}

@Builder
export function IdiomQueryPageBuilder(param: Object) {
  NavDestination() {
    IdiomQueryContent({ initialWord: (param as string) || '' })
  }
  .title($r('app.string.page_idiom_query'))
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct IdiomQueryContent {
  initialWord: string = '';
  @State queryMode: string = 'forward';
  @State queryInput: string = '';
  @State queryResults: IdiomQueryResultItem[] = [];
  @State queryTip: ResourceStr = '';
  @State queryHistory: string[] = [];
  @State loading: boolean = true;
  @State hasError: boolean = false;
  @State hasContent: boolean = false;
  @State detailItem: IdiomDetailItem | null = null;
  @State isReverseReady: boolean = false;
  @State activeTab: string = 'pinyin';
  @State firstLetters: string[] = [];
  @State activeLetter: string = '';
  @State letterIdioms: IdiomDetailItem[] = [];
  @State pinyinResults: IdiomDetailItem[] = [];
  @State pinyinQuery: string = '';
  @State pinyinAllCount: number = 0;
  @State pinyinDisplayed: number = 0;
  private readonly pinyinPageSize: number = 100;
  private letterSwitching: boolean = false;
  private letterDataSource: IdiomListDataSource = new IdiomListDataSource();
  private viewModel: IdiomViewModel = IdiomViewModel.getInstance();
  private uiContext: UIContext = this.getUIContext();
  private detailDialogController: CustomDialogController | null = null;

  aboutToAppear(): void {
    this.viewModel.setContext(this.uiContext.getHostContext() as Context);
    this.loadHistory();
    setTimeout(() => {
      this.loadData();
      if (!this.hasError && this.initialWord) {
        let ctx: Context = this.uiContext.getHostContext() as Context;
        // 录入拼音搜索：把当日成语转为拼音查询串并触发查询（查询效果）
        this.activeTab = 'pinyin';
        this.pinyinQuery = this.initialWord;
        this.doPinyinSearch();
        // 模拟结果点击：直接打开当日成语的详情弹窗
        let detail: IdiomDetailItem | null = this.viewModel.findIdiomDetail(ctx, this.initialWord);
        if (detail) {
          this.detailItem = detail;
          this.detailDialogController = new CustomDialogController({
            builder: DetailModal({ detailItem: this.detailItem }),
            autoCancel: true,
            alignment: DialogAlignment.Center,
            customStyle: true
          });
          this.detailDialogController.open();
          StickinessUtil.incrementBrowseCount(ctx);
        }
      }
    }, 0);
  }

  private loadData(): void {
    if (this.viewModel.isDataLoaded()) {
      this.loading = false;
      this.isReverseReady = this.viewModel.isLastIndexReady();
      this.firstLetters = this.viewModel.getFirstLetters();
      return;
    }
    this.loading = true;
    this.hasError = false;
    let ok: boolean = this.viewModel.loadData(this.uiContext.getHostContext() as Context);
    if (ok) {
      this.loading = false;
      this.isReverseReady = this.viewModel.isLastIndexReady();
      this.firstLetters = this.viewModel.getFirstLetters();
      console.info('[Idiom] loadData ok, firstLetters=' + this.firstLetters.length.toString());
    } else {
      this.hasError = true;
      this.loading = false;
    }
  }

  private loadHistory(): void {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(
        this.uiContext.getHostContext() as Context, { name: 'app_cache' });
      let histStr: string = prefs.getSync('idiom_query_history', '') as string;
      if (histStr) {
        this.queryHistory = JSON.parse(histStr) as string[];
      }
    } catch (e) {
      this.queryHistory = [];
    }
  }

  private saveHistory(): void {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(
        this.uiContext.getHostContext() as Context, { name: 'app_cache' });
      prefs.putSync('idiom_query_history', JSON.stringify(this.queryHistory));
      prefs.flush();
    } catch (e) {
    }
  }

  private addToHistory(word: string): void {
    let idx: number = this.queryHistory.indexOf(word);
    if (idx >= 0) {
      this.queryHistory.splice(idx, 1);
    }
    this.queryHistory.unshift(word);
    if (this.queryHistory.length > 5) {
      this.queryHistory = this.queryHistory.slice(0, 5);
    }
    this.saveHistory();
  }

  private doQuery(): void {
    let word: string = this.queryInput.trim();
    if (!word) {
      return;
    }
     let chineseRegex: RegExp = new RegExp('[\\u4e00-\\u9fa5]');
    if (!chineseRegex.test(word)) {
      return;
    }
    if (!this.viewModel.hasWord(word)) {
      let fuzzy: string[] = this.viewModel.fuzzySearch(word);
      if (fuzzy.length === 1) {
        word = fuzzy[0];
        this.queryInput = word;
      } else if (fuzzy.length > 1) {
        this.handleMultipleFuzzy(fuzzy);
        return;
      } else {
        ToastUtil.show(this.uiContext, $r('app.string.idiomq_not_in_lib'), 1000);
        return;
      }
    }
    this.querySolitaire(word);
  }

  private querySolitaire(word: string): void {
    let result: SolitaireResult = this.viewModel.querySolitaire(word, this.queryMode);
    if (result.error) {
      ToastUtil.show(this.uiContext, result.error === 'not_found'
        ? $r('app.string.idiomq_not_in_lib') : $r('app.string.idiomq_data_loading'), 1000);
      this.isReverseReady = !result.lastIndexLoading;
      return;
    }
    this.addToHistory(word);
    this.queryResults = this.viewModel.buildQueryResults(result.candidates, word, this.queryMode);
    this.queryTip = this.queryMode === 'forward'
      ? $r('app.string.idiomq_tip_forward', this.queryResults.length)
      : $r('app.string.idiomq_tip_reverse', this.queryResults.length);
    this.hasContent = true;
  }

  private handleMultipleFuzzy(fuzzyWords: string[]): void {
    let allResults: IdiomQueryResultItem[] = [];
    for (let i: number = 0; i < fuzzyWords.length; i++) {
      let word: string = fuzzyWords[i];
      let solResult: SolitaireResult = this.viewModel.querySolitaire(word, this.queryMode);
      let items: IdiomQueryResultItem[] = this.viewModel.buildQueryResults(solResult.candidates, word, this.queryMode);
      for (let j: number = 0; j < items.length; j++) {
        allResults.push(items[j]);
      }
    }
    this.queryResults = allResults;
    this.queryTip = $r('app.string.idiomq_fuzzy_tip', fuzzyWords.length);
    this.hasContent = true;
  }

  private onWordTap(word: string): void {
    let ctx: Context = this.uiContext.getHostContext() as Context;
    let detail: IdiomDetailItem | null = this.viewModel.findIdiomDetail(ctx, word);
    if (detail) {
      this.detailItem = detail;
      this.detailDialogController = new CustomDialogController({
        builder: DetailModal({ detailItem: this.detailItem }),
        autoCancel: true,
        alignment: DialogAlignment.Center,
        customStyle: true
      });
      this.detailDialogController.open();
      StickinessUtil.incrementBrowseCount(ctx);
    } else {
      ToastUtil.show(this.uiContext, $r('app.string.idiomq_no_detail'), 1000);
    }
  }

  private isIdiomFav(word: string): boolean {
    let ctx: Context = this.uiContext.getHostContext() as Context;
    return FavoritesUtil.isFavorite(ctx, 'idiom', word);
  }

  private onContinueChain(continueWord: string): void {
    this.queryInput = continueWord;
    this.querySolitaire(continueWord);
  }

  private onCopyResult(): void {
    if (this.queryResults.length === 0) {
      return;
    }
    let lines: string[] = [];
    for (let i: number = 0; i < this.queryResults.length; i++) {
      let item: IdiomQueryResultItem = this.queryResults[i];
      lines.push(item.leftWord + ' \u2192 ' + item.rightWord);
    }
    ClipboardUtil.copy(lines.join('\n'));
    ToastUtil.show(this.uiContext, $r('app.string.idiomq_copied'), 1000);
  }

  private toggleMode(): void {
    if (this.queryMode === 'forward') {
      if (!this.viewModel.isLastIndexReady()) {
        ToastUtil.show(this.uiContext, $r('app.string.idiomq_reverse_loading'), 1000);
        return;
      }
      this.queryMode = 'reverse';
    } else {
      this.queryMode = 'forward';
    }
    this.queryResults = [];
    this.queryTip = '';
    this.hasContent = false;
  }

  private onLetterTap(letter: string): void {
    if (this.letterSwitching) {
      return;
    }
    if (this.activeLetter === letter) {
      return;
    }
    this.letterSwitching = true;
    this.activeLetter = letter;
    this.letterDataSource.setItems(this.viewModel.getIdiomsByLetter(this.uiContext.getHostContext() as Context, letter));
    console.info('[Idiom] letter=' + letter + ', idioms=' + this.letterDataSource.totalCount().toString());
    setTimeout(() => {
      this.letterSwitching = false;
    }, 150);
  }

  private doPinyinSearch(): void {
    let q: string = this.pinyinQuery.trim().toLowerCase();
    if (!q) {
      this.pinyinResults = [];
      this.pinyinAllCount = 0;
      this.pinyinDisplayed = 0;
      return;
    }
    this.pinyinAllCount = this.viewModel.searchByPinyinTotal(q);
    this.pinyinDisplayed = Math.min(this.pinyinPageSize, this.pinyinAllCount);
    this.pinyinResults = this.viewModel.searchByPinyin(q, 0, this.pinyinDisplayed);
  }

  private loadMorePinyin(): void {
    let q: string = this.pinyinQuery.trim().toLowerCase();
    if (!q || this.pinyinDisplayed >= this.pinyinAllCount) {
      return;
    }
    let more: IdiomDetailItem[] = this.viewModel.searchByPinyin(q, this.pinyinDisplayed, this.pinyinPageSize);
    this.pinyinResults = this.pinyinResults.concat(more);
    this.pinyinDisplayed = Math.min(this.pinyinDisplayed + this.pinyinPageSize, this.pinyinAllCount);
  }

  build() {
    Column() {
      this.TabBar()
      if (this.activeTab === 'solitaire') {
        this.SolitaireTab()
      } else if (this.activeTab === 'browse') {
        this.BrowseTab()
      } else {
        this.SearchTab()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  TabBar() {
    Row() {
      Text($r('app.string.idiomq_tab_pinyin'))
        .fontSize(14)
        .fontColor(this.activeTab === 'pinyin' ? $r('app.color.on_accent_text') : $r('app.color.secondary_text'))
        .backgroundColor(this.activeTab === 'pinyin' ? $r('app.color.idiom_blue') : $r('app.color.border_color'))
        .borderRadius(12)
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .onClick(() => {
          this.activeTab = 'pinyin';
        })

      Text($r('app.string.idiomq_tab_solitaire'))
        .fontSize(14)
        .fontColor(this.activeTab === 'solitaire' ? $r('app.color.on_accent_text') : $r('app.color.secondary_text'))
        .backgroundColor(this.activeTab === 'solitaire' ? $r('app.color.idiom_blue') : $r('app.color.border_color'))
        .borderRadius(12)
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .margin({ left: 8 })
        .onClick(() => {
          this.activeTab = 'solitaire';
        })

      Text($r('app.string.idiomq_tab_browse'))
        .fontSize(14)
        .fontColor(this.activeTab === 'browse' ? $r('app.color.on_accent_text') : $r('app.color.secondary_text'))
        .backgroundColor(this.activeTab === 'browse' ? $r('app.color.idiom_blue') : $r('app.color.border_color'))
        .borderRadius(12)
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .margin({ left: 8 })
        .onClick(() => {
          this.activeTab = 'browse';
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 4 })
  }

  @Builder
  SolitaireTab() {
    Column() {
      this.SearchSection()
      this.HistorySection()
      this.ResultSection()
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  SearchSection() {
    Row() {
      TextInput({ placeholder: this.queryMode === 'forward' ? $r('app.string.idiomq_hint_forward') : $r('app.string.idiomq_hint_reverse'), text: this.queryInput })
        .layoutWeight(1)
        .height(36)
        .fontSize(14)
        .fontColor($r('app.color.primary_text'))
        .placeholderColor($r('app.color.hint_text'))
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(18)
        .padding({ left: 16, right: 28 })
        .onChange((value: string) => {
          this.queryInput = value;
        })
        .onSubmit(() => {
          this.doQuery();
        })

      if (this.queryInput) {
        Text('\u2715')
          .fontSize(14)
          .fontColor($r('app.color.tertiary_text'))
          .width(24)
          .height(24)
          .textAlign(TextAlign.Center)
          .margin({ left: -32 })
          .onClick(() => {
            this.queryInput = '';
            this.queryResults = [];
            this.queryTip = '';
            this.hasContent = false;
          })
      }

      Text(this.queryMode === 'forward' ? $r('app.string.idiomq_mode_forward') : $r('app.string.idiomq_mode_reverse'))
        .fontSize(12)
        .fontColor($r('app.color.on_accent_text'))
        .backgroundColor(this.queryMode === 'forward' ? $r('app.color.idiom_blue') : $r('app.color.idiom_orange'))
        .borderRadius(10)
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .margin({ left: 6 })
        .onClick(() => {
          this.toggleMode();
        })

      Text($r('app.string.idiomq_query'))
        .fontSize(12)
        .fontColor($r('app.color.on_accent_text'))
        .backgroundColor($r('app.color.poetry_green'))
        .borderRadius(10)
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .margin({ left: 6 })
        .onClick(() => {
          this.doQuery();
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 4 })
  }

  @Builder
  HistorySection() {
    if (this.queryHistory.length > 0) {
      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.queryHistory, (word: string) => {
            Text(word)
            .fontSize(13)
            .fontColor($r('app.color.idiom_blue'))
            .backgroundColor($r('app.color.idiom_blue') + '18')
              .borderRadius(10)
              .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              .onClick(() => {
                this.queryInput = word;
                this.querySolitaire(word);
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
  ResultSection() {
    if (this.loading) {
      Column() {
        LoadingProgress()
          .width(48)
          .height(48)
          .color($r('app.color.idiom_blue'))
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
          subText: StrUtil.text(this.uiContext.getHostContext() as Context, $r('app.string.poemq_load_failed_sub')),
          onRetry: () => {
            this.loadData();
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
    } else if (this.hasContent) {
      Column() {
        Row() {
          Text(this.queryTip)
            .fontSize(14)
            .fontColor($r('app.color.primary_text'))
            .fontWeight(FontWeight.Medium)
          Blank()
          Text($r('app.string.idiomq_copy_results'))
            .fontSize(12)
            .fontColor($r('app.color.idiom_blue'))
            .backgroundColor($r('app.color.idiom_blue') + '18')
            .borderRadius(8)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .onClick(() => {
              this.onCopyResult();
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 6 })

        List({ space: 6 }) {
          ForEach(this.queryResults, (item: IdiomQueryResultItem) => {
            ListItem() {
              Row() {
                Text(item.leftWord)
                  .fontSize(15)
                  .fontColor($r('app.color.idiom_blue'))
                  .fontWeight(FontWeight.Medium)
                  .decoration({ type: TextDecorationType.Underline, color: $r('app.color.idiom_blue') + '60' })

                Text(' \u2192 ')
                  .fontSize(14)
                  .fontColor($r('app.color.hint_text'))

                Text(item.rightWord)
                  .fontSize(15)
                  .fontColor($r('app.color.idiom_blue'))
                  .decoration({ type: TextDecorationType.Underline, color: $r('app.color.idiom_blue') + '60' })
                  .onClick(() => {
                    this.onWordTap(item.rightWord);
                  })

                Blank()

                if (this.isIdiomFav(item.leftWord) || this.isIdiomFav(item.rightWord)) {
                  Text('\u2665')
                    .fontSize(14)
                    .fontColor($r('app.color.danger_red'))
                    .margin({ right: 6 })
                }

                if (item.canContinue) {
                  Text(item.actionKind === 'forward'
                    ? $r('app.string.idiomq_chain_continue') : $r('app.string.idiomq_chain_reverse'))
                    .fontSize(12)
                    .fontColor($r('app.color.on_accent_text'))
                    .backgroundColor($r('app.color.danger_red'))
                    .borderRadius(10)
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .onClick(() => {
                      this.onContinueChain(item.continueWord);
                    })
                }
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(10)
            }
          }, (item: IdiomQueryResultItem) => item.leftWord + '_' + item.rightWord)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 10, right: 10 })
        .cachedCount(10)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .layoutWeight(1)
    } else {
      Column() {
          Text($r('app.string.idiomq_empty_solitaire'))
          .fontSize(16)
          .fontColor($r('app.color.tertiary_text'))
          .margin({ top: 60 })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Center)
    }
  }

  @Builder
  BrowseTab() {
    Column() {
      Scroll() {
        Row({ space: 4 }) {
          ForEach(this.firstLetters, (letter: string) => {
            Text(letter.toUpperCase())
            .fontSize(13)
            .fontColor(this.activeLetter === letter ? $r('app.color.on_accent_text') : $r('app.color.secondary_text'))
            .backgroundColor(this.activeLetter === letter ? $r('app.color.idiom_blue') : $r('app.color.border_color'))
              .borderRadius(8)
              .width(28)
              .height(28)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.onLetterTap(letter);
              })
          }, (letter: string) => letter)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      if (this.activeLetter && this.letterDataSource.totalCount() > 0) {
        Row() {
          Text($r('app.string.idiomq_letter_header', this.activeLetter.toUpperCase()))
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          Text('(' + this.letterDataSource.totalCount().toString() + ')')
            .fontSize(12)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ left: 4 })
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 4 })

        List({ space: 4 }) {
          LazyForEach(this.letterDataSource, (item: IdiomDetailItem) => {
            ListItem() {
              Row() {
                Column() {
                  Text(item.word)
                    .fontSize(14)
                    .fontColor($r('app.color.primary_text'))
                    .fontWeight(FontWeight.Medium)
                  if (item.pinyin) {
                    Text(item.pinyin)
                      .fontSize(11)
                      .fontColor($r('app.color.tertiary_text'))
                      .margin({ top: 1 })
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                if (item.explanation) {
                  Text(item.explanation.substring(0, Math.min(item.explanation.length, 20)) + (item.explanation.length > 20 ? '...' : ''))
                    .fontSize(12)
                    .fontColor($r('app.color.tertiary_text'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                    .margin({ left: 12 })
                }

                if (this.isIdiomFav(item.word)) {
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
                this.onWordTap(item.word);
              })
            }
          }, (item: IdiomDetailItem) => item.word)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 10, right: 10 })
        .cachedCount(10)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      } else if (this.activeLetter) {
        Column() {
          Text($r('app.string.idiomq_letter_empty'))
            .fontSize(14)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 30 })
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column() {
          Text($r('app.string.idiomq_letter_pick'))
            .fontSize(16)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 60 })
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
  SearchTab() {
    Column() {
      Row() {
        TextInput({ placeholder: $r('app.string.idiomq_pinyin_hint'), text: this.pinyinQuery })
        .layoutWeight(1)
        .height(36)
        .fontSize(14)
        .fontColor($r('app.color.primary_text'))
        .placeholderColor($r('app.color.hint_text'))
        .backgroundColor($r('app.color.card_background'))
          .borderRadius(18)
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.pinyinQuery = value;
            this.doPinyinSearch();
          })
          .onSubmit(() => {
            this.doPinyinSearch();
          })

        Text($r('app.string.poemq_search'))
        .fontSize(12)
        .fontColor($r('app.color.on_accent_text'))
        .backgroundColor($r('app.color.idiom_blue'))
          .borderRadius(10)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .margin({ left: 6 })
          .onClick(() => {
            this.doPinyinSearch();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 4 })

      if (this.pinyinResults.length > 0) {
        Row() {
          Text($r('app.string.search_results'))
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          Text($r('app.string.idiomq_total_count', this.pinyinAllCount))
            .fontSize(12)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ left: 4 })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 6, bottom: 4 })

        List({ space: 4 }) {
          ForEach(this.pinyinResults, (item: IdiomDetailItem) => {
            ListItem() {
              Row() {
                Column() {
                  Text(item.word)
                    .fontSize(14)
                    .fontColor($r('app.color.primary_text'))
                    .fontWeight(FontWeight.Medium)
                  if (item.pinyin) {
                    Text(item.pinyin)
                      .fontSize(11)
                      .fontColor($r('app.color.tertiary_text'))
                      .margin({ top: 1 })
                  }
                }
                .alignItems(HorizontalAlign.Start)

                Blank()

                if (this.isIdiomFav(item.word)) {
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
                this.onWordTap(item.word);
              })
            }
          }, (item: IdiomDetailItem) => item.word)

          if (this.pinyinDisplayed < this.pinyinAllCount) {
            ListItem() {
              Row() {
                Text($r('app.string.idiomq_load_more_remaining', this.pinyinAllCount - this.pinyinDisplayed))
                  .fontSize(13)
                  .fontColor($r('app.color.idiom_blue'))
              }
              .width('100%')
              .height(44)
              .justifyContent(FlexAlign.Center)
              .onClick(() => {
                this.loadMorePinyin();
              })
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 10, right: 10 })
        .cachedCount(10)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      } else if (this.pinyinQuery) {
        Column() {
          Text($r('app.string.idiomq_no_match'))
          .fontSize(14)
          .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 30 })
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column() {
          Text($r('app.string.idiomq_pinyin_empty'))
          .fontSize(16)
          .fontColor($r('app.color.tertiary_text'))
          .margin({ top: 60 })
        Text($r('app.string.idiomq_pinyin_example'))
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
}
