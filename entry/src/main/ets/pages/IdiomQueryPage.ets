import { IdiomViewModel } from '../viewmodel/IdiomViewModel';
import { IdiomQueryResultItem, IdiomDetailItem, SolitaireResult } from '../model/IdiomModels';
import { ClipboardUtil } from '../common/utils/ClipboardUtil';
import { ErrorState } from '../components/ErrorState';
import { DetailModal } from '../components/DetailModal';
import { preferences } from '@kit.ArkData';

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
export function IdiomQueryPageBuilder() {
  NavDestination() {
    IdiomQueryContent()
  }
  .title('成语查询')
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct IdiomQueryContent {
  @State queryMode: string = 'forward';
  @State queryInput: string = '';
  @State queryResults: IdiomQueryResultItem[] = [];
  @State queryTip: string = '';
  @State queryHistory: string[] = [];
  @State loading: boolean = true;
  @State hasError: boolean = false;
  @State hasContent: boolean = false;
  @State detailItem: IdiomDetailItem | null = null;
  @State isReverseReady: boolean = false;
  @State activeTab: string = 'solitaire';
  @State firstLetters: string[] = [];
  @State activeLetter: string = '';
  @State letterIdioms: IdiomDetailItem[] = [];
  @State pinyinResults: IdiomDetailItem[] = [];
  @State pinyinQuery: string = '';
  private letterSwitching: boolean = false;
  private letterDataSource: IdiomListDataSource = new IdiomListDataSource();
  private viewModel: IdiomViewModel = IdiomViewModel.getInstance();
  private uiContext: UIContext = this.getUIContext();
  private detailDialogController: CustomDialogController = new CustomDialogController({
    builder: DetailModal({ detailItem: this.detailItem }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true
  });

  aboutToAppear(): void {
    this.viewModel.setContext(this.uiContext.getHostContext() as Context);
    this.loadData();
    this.loadHistory();
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
        this.uiContext.getPromptAction().showToast({ message: '该成语不在词库中', duration: 1500 });
        return;
      }
    }
    this.querySolitaire(word);
  }

  private querySolitaire(word: string): void {
    let result: SolitaireResult = this.viewModel.querySolitaire(word, this.queryMode);
    if (result.error) {
      this.uiContext.getPromptAction().showToast({ message: result.error, duration: 1500 });
      this.isReverseReady = !result.lastIndexLoading;
      return;
    }
    this.addToHistory(word);
    this.queryResults = this.viewModel.buildQueryResults(result.candidates, word, this.queryMode);
    let modeText: string = this.queryMode === 'forward' ? '顺查' : '逆查';
    this.queryTip = '共 ' + this.queryResults.length.toString() + ' 条' + modeText + '结果';
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
    this.queryTip = '模糊匹配到 ' + fuzzyWords.length.toString() + ' 个成语';
    this.hasContent = true;
  }

  private onWordTap(word: string): void {
    let detail: IdiomDetailItem | null = this.viewModel.findIdiomDetail(this.uiContext.getHostContext() as Context, word);
    if (detail) {
      this.detailItem = detail;
      this.detailDialogController.open();
    } else {
      this.uiContext.getPromptAction().showToast({ message: '暂无详情', duration: 1500 });
    }
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
    this.uiContext.getPromptAction().showToast({ message: '已复制到剪贴板', duration: 1000 });
  }

  private toggleMode(): void {
    if (this.queryMode === 'forward') {
      if (!this.viewModel.isLastIndexReady()) {
        this.uiContext.getPromptAction().showToast({ message: '逆查数据加载中，请稍候...', duration: 1500 });
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
      return;
    }
    this.pinyinResults = this.viewModel.searchByPinyin(q);
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
      Text('接龙查询')
        .fontSize(14)
        .fontColor(this.activeTab === 'solitaire' ? '#ffffff' : $r('app.color.secondary_text'))
        .backgroundColor(this.activeTab === 'solitaire' ? $r('app.color.idiom_blue') : $r('app.color.border_color'))
        .borderRadius(12)
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .onClick(() => {
          this.activeTab = 'solitaire';
        })

      Text('按字浏览')
        .fontSize(14)
        .fontColor(this.activeTab === 'browse' ? '#ffffff' : $r('app.color.secondary_text'))
        .backgroundColor(this.activeTab === 'browse' ? $r('app.color.idiom_blue') : $r('app.color.border_color'))
        .borderRadius(12)
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .margin({ left: 8 })
        .onClick(() => {
          this.activeTab = 'browse';
        })

      Text('拼音搜索')
        .fontSize(14)
        .fontColor(this.activeTab === 'pinyin' ? '#ffffff' : $r('app.color.secondary_text'))
        .backgroundColor(this.activeTab === 'pinyin' ? $r('app.color.idiom_blue') : $r('app.color.border_color'))
        .borderRadius(12)
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .margin({ left: 8 })
        .onClick(() => {
          this.activeTab = 'pinyin';
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
      TextInput({ placeholder: this.queryMode === 'forward' ? '输入成语，顺查接龙...' : '输入成语，逆查接龙...', text: this.queryInput })
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

      Text(this.queryMode === 'forward' ? '顺查' : '逆查')
        .fontSize(12)
        .fontColor('#ffffff')
        .backgroundColor(this.queryMode === 'forward' ? $r('app.color.idiom_blue') : $r('app.color.idiom_orange'))
        .borderRadius(10)
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .margin({ left: 6 })
        .onClick(() => {
          this.toggleMode();
        })

      Text('查询')
        .fontSize(12)
        .fontColor('#ffffff')
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
          subText: '数据读取异常，请重试',
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
          Text('复制结果')
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

                if (item.canContinue) {
                  Text(item.actionText)
                    .fontSize(12)
                    .fontColor('#ffffff')
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
      }
      .width('100%')
      .layoutWeight(1)
    } else {
      Column() {
        Text('输入成语开始接龙查询')
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
            .fontColor(this.activeLetter === letter ? '#ffffff' : $r('app.color.secondary_text'))
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

      if (this.activeLetter && this.letterDataSource.totalCount() > 0) {
        Row() {
          Text(this.activeLetter.toUpperCase() + ' 开头的成语')
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
      } else if (this.activeLetter) {
        Column() {
          Text('暂无该字母开头的成语')
            .fontSize(14)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 30 })
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column() {
          Text('选择首字母浏览成语')
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
        TextInput({ placeholder: '输入拼音搜索，如 bai...', text: this.pinyinQuery })
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

        Text('搜索')
        .fontSize(12)
        .fontColor('#ffffff')
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
          Text('拼音搜索结果')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          Text('(' + this.pinyinResults.length.toString() + ')')
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
      } else if (this.pinyinQuery) {
        Column() {
          Text('未找到匹配的成语')
          .fontSize(14)
          .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 30 })
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column() {
          Text('输入拼音搜索成语')
          .fontSize(16)
          .fontColor($r('app.color.tertiary_text'))
          .margin({ top: 60 })
        Text('例如: bai \u2192 百发百中、百步穿杨')
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
