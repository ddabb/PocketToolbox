import { PoetryViewModel } from '../viewmodel/PoetryViewModel';
import { PoetItem, SearchResultItem, PoetDetail, PoemItem } from '../model/PoetryModels';
import { Constants } from '../common/constants/Constants';
import { ErrorState } from '../components/ErrorState';
import { preferences } from '@kit.ArkData';
import { FavoritesUtil } from '../common/utils/FavoritesUtil';
import { ToastUtil } from '../common/utils/ToastUtil';
import { OcrUtil } from '../common/utils/OcrUtil';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';

@Builder
export function PoetryQueryPageBuilder(param?: Object) {
  NavDestination() {
    PoetryQueryContent({
      initialDynasty: param ? ((param as Record<string, Object>)['dynasty'] as string || '') : ''
    })
  }
  .title('诗词查询')
  .backButtonIcon($r('sys.symbol.chevron_left'))
}

@Component
struct PoetryQueryContent {
  @State searchText: string = '';
  @State activeDynasty: string = '全部';
  @State dynasties: string[] = ['全部'];
  @State poets: PoetItem[] = [];
  @State results: SearchResultItem[] = [];
  @State isLoading: boolean = true;
  @State hasError: boolean = false;
  @State poetPage: number = 0;
  @State hasMorePoets: boolean = true;
  @State isSearching: boolean = false;
  @State searchHistory: string[] = [];
  @State loadingMore: boolean = false;
  @State ocrSheetVisible: boolean = false;
  @State ocrLines: string[] = [];
  @State ocrLoading: boolean = false;
  initialDynasty: string = '';
  private viewModel: PoetryViewModel = PoetryViewModel.getInstance();
  private uiContext: UIContext = this.getUIContext();
  private getNavPathStack(): NavPathStack {
    return AppStorage.get('AppNavPathStack') as NavPathStack;
  }

  aboutToAppear(): void {
    setTimeout(() => {
      this.loadData();
    }, 0);
  }

  private loadData(): void {
    if (this.viewModel.isDataLoaded()) {
      this.isLoading = false;
      this.dynasties = ['全部'].concat(this.viewModel.getDynasties());
      this.applyInitialDynasty();
      this.refreshContent();
      return;
    }
    this.isLoading = true;
    this.hasError = false;
    console.info('[PoetryQuery] loadData start');
    let ok: boolean = this.viewModel.loadIndex(this.uiContext.getHostContext() as Context);
    if (ok) {
      this.dynasties = ['全部'].concat(this.viewModel.getDynasties());
      console.info('[PoetryQuery] loadData ok, dynasties=' + this.dynasties.length.toString());
      this.applyInitialDynasty();
      this.refreshContent();
      this.isLoading = false;
    } else {
      console.error('[PoetryQuery] loadData failed');
      this.hasError = true;
      this.isLoading = false;
    }
  }

  private applyInitialDynasty(): void {
    if (this.initialDynasty && this.dynasties.indexOf(this.initialDynasty) >= 0) {
      this.activeDynasty = this.initialDynasty;
      console.info('[PoetryQuery] apply initial dynasty=' + this.initialDynasty);
    }
  }

  private refreshContent(): void {
    let query: string = this.searchText.trim();
    if (query) {
      this.isSearching = true;
      this.results = this.viewModel.buildSearchResults(query, this.activeDynasty);
      console.info('[PoetryQuery] search query=' + query + ', dynasty=' + this.activeDynasty +
        ', results=' + this.results.length.toString());
      return;
    }
    this.isSearching = false;
    this.results = [];
    this.poetPage = 0;
    this.poets = this.viewModel.getFilteredPoetsByPage(this.activeDynasty, 0, Constants.POET_PAGE_SIZE);
    this.hasMorePoets = this.viewModel.hasMoreFilteredPoets(this.activeDynasty, 0, Constants.POET_PAGE_SIZE);
    console.info('[PoetryQuery] browse dynasty=' + this.activeDynasty +
      ', poets=' + this.poets.length.toString() + ', hasMore=' + this.hasMorePoets.toString());
  }

  private loadMorePoets(): void {
    if (this.loadingMore || !this.hasMorePoets || this.isSearching) {
      return;
    }
    this.loadingMore = true;
    this.poetPage++;
    let more: PoetItem[] = this.viewModel.getFilteredPoetsByPage(this.activeDynasty, this.poetPage, Constants.POET_PAGE_SIZE);
    this.poets = this.poets.concat(more);
    this.hasMorePoets = this.viewModel.hasMoreFilteredPoets(this.activeDynasty, this.poetPage, Constants.POET_PAGE_SIZE);
    console.info('[PoetryQuery] loadMore page=' + this.poetPage.toString() +
      ', added=' + more.length.toString() + ', total=' + this.poets.length.toString());
    this.loadingMore = false;
  }

  private onSearchSubmit(): void {
    let q: string = this.searchText.trim();
    if (q) {
      this.addToHistory(q);
    }
    this.refreshContent();
    if (this.isSearching && this.results.length === 0) {
      ToastUtil.show(this.uiContext, '未找到相关结果', 1000);
    }
  }

  private loadHistory(): void {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(
        this.uiContext.getHostContext() as Context, { name: 'app_cache' });
      let histStr: string = prefs.getSync('poetry_query_history', '') as string;
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
      prefs.putSync('poetry_query_history', JSON.stringify(this.searchHistory));
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

  private onDynastyTap(dynasty: string): void {
    if (this.activeDynasty === dynasty) {
      return;
    }
    console.info('[PoetryQuery] dynasty tap: ' + this.activeDynasty + ' -> ' + dynasty);
    this.activeDynasty = dynasty;
    this.refreshContent();
  }

  private clearSearch(): void {
    this.searchText = '';
    this.refreshContent();
  }

  private async onOcrPick(): Promise<void> {
    if (this.ocrLoading) {
      return;
    }
    try {
      let selectOptions: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      selectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      selectOptions.maxSelectNumber = 1;
      let picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      let result: photoAccessHelper.PhotoSelectResult = await picker.select(selectOptions);
      if (result.photoUris.length === 0) {
        return;
      }
      await this.runOcr(result.photoUris[0]);
    } catch (e) {
      console.info('[PoetryQuery] ocr pick cancelled');
    }
  }

  private async runOcr(uri: string): Promise<void> {
    this.ocrLoading = true;
    let pixelMap: image.PixelMap | null = null;
    let source: image.ImageSource | null = null;
    let file: fileIo.File | null = null;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      pixelMap = await source.createPixelMap();
      let lines: string[] = await OcrUtil.recognizeLines(pixelMap);
      if (lines.length === 0) {
        ToastUtil.show(this.uiContext, '未识别到文本', 1500);
      } else {
        this.ocrLines = lines;
        this.ocrSheetVisible = true;
      }
    } catch (e) {
      console.error('[PoetryQuery] ocr failed: ' + (e as Error).message);
      ToastUtil.show(this.uiContext, '识别失败，请重试', 1500);
    } finally {
      if (pixelMap) {
        pixelMap.release();
      }
      if (source) {
        source.release();
      }
      if (file) {
        try {
          fileIo.closeSync(file);
        } catch (e2) {
        }
      }
      this.ocrLoading = false;
    }
  }

  private onOcrLineTap(line: string): void {
    this.ocrSheetVisible = false;
    this.searchText = line;
    this.onSearchSubmit();
  }

  private onPoetTap(poet: PoetItem): void {
    console.info('[PoetryQuery] tap poet=' + poet.n + ', dynasty=' + poet.d + ', initial=' + poet.i);
    let detail: PoetDetail = this.viewModel.loadPoetDetail(
      this.uiContext.getHostContext() as Context, poet.n, poet.i, poet.d);
    console.info('[PoetryQuery] loaded poems=' + detail.poems.length.toString() + ' for poet=' + poet.n);
    let stack: NavPathStack = this.getNavPathStack();
    if (stack) {
      stack.pushPathByName('PoetryDetailPage', detail);
    }
  }

  private onResultTap(result: SearchResultItem): void {
    console.info('[PoetryQuery] tap result type=' + result.type + ', title=' + result.title);
    if (result.type === 'poet') {
      let poet: PoetItem | null = this.viewModel.getPoetByName(result.title);
      if (poet) {
        this.onPoetTap(poet);
      } else {
        console.warn('[PoetryQuery] poet not found: ' + result.title);
      }
    } else if (result.type === 'poem') {
      let poet: PoetItem | null = this.viewModel.getPoetByName(result.poetName);
      if (poet) {
        let detail: PoetDetail = this.viewModel.loadPoetDetail(
          this.uiContext.getHostContext() as Context, poet.n, poet.i, poet.d);
        for (let i = 0; i < detail.poems.length; i++) {
          if (detail.poems[i].n === result.title) {
            let stack2: NavPathStack = this.getNavPathStack();
            if (stack2) {
              stack2.pushPathByName('PoemContentPage', detail.poems[i]);
            }
            return;
          }
        }
        ToastUtil.show(this.uiContext, '未找到诗词详情', 1000);
      } else {
        ToastUtil.show(this.uiContext, '未找到诗人信息', 1000);
      }
    } else {
      ToastUtil.show(this.uiContext, '请搜索诗人姓名查看详情', 1000);
    }
  }

  private isPoemFav(title: string): boolean {
    let ctx: Context = this.uiContext.getHostContext() as Context;
    return FavoritesUtil.isFavorite(ctx, 'poem', title);
  }

  build() {
    Stack() {
      Column() {
        this.SearchBar()
        if (!this.isSearching && this.searchHistory.length > 0) {
          this.HistorySection()
        }
        this.DynastyTabs()
        this.ContentArea()
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))

      if (this.ocrSheetVisible) {
        this.OcrSheetOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  OcrSheetOverlay() {
    Column() {
      Blank()

      Column() {
        Row() {
          Text('\uD83D\uDCF7')
            .fontSize(16)
            .margin({ right: 6 })
          Text('识诗结果 · 点击一行搜索')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .layoutWeight(1)
          Text('\u2715')
            .fontSize(14)
            .fontColor($r('app.color.tertiary_text'))
            .width(28)
            .height(28)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.ocrSheetVisible = false;
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 10 })

        Divider().color($r('app.color.border_color'))

        Scroll() {
          Column() {
            ForEach(this.ocrLines, (line: string) => {
              Text(line)
                .fontSize(14)
                .fontColor($r('app.color.primary_text'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .onClick(() => {
                  this.onOcrLineTap(line);
                })
              if (this.ocrLines.indexOf(line) < this.ocrLines.length - 1) {
                Divider().color($r('app.color.border_color')).margin({ left: 16 })
              }
            }, (line: string) => line)
          }
          .width('100%')
        }
        .scrollable(ScrollDirection.Vertical)
        .constraintSize({ maxHeight: 360 })
        .width('100%')
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .backgroundColor($r('app.color.card_background'))
      .borderRadius({ topLeft: 20, topRight: 20 })
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
    .onClick(() => {
      this.ocrSheetVisible = false;
    })
  }

  @Builder
  HistorySection() {
    if (this.searchHistory.length > 0) {
      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.searchHistory, (word: string) => {
            Text(word)
              .fontSize(13)
              .fontColor($r('app.color.poetry_green'))
              .backgroundColor($r('app.color.poetry_green') + '18')
              .borderRadius(10)
              .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              .onClick(() => {
                this.searchText = word;
                this.onSearchSubmit();
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
  SearchBar() {
    Row() {
      TextInput({ placeholder: '搜索诗人/诗词...', text: this.searchText })
        .layoutWeight(1)
        .height(40)
        .fontSize(14)
        .fontColor($r('app.color.primary_text'))
        .placeholderColor($r('app.color.hint_text'))
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(20)
        .padding({ left: 16, right: 32 })
        .onChange((value: string) => {
          this.searchText = value;
        })
        .onSubmit(() => {
          this.onSearchSubmit();
        })

      if (this.searchText) {
        Text('\u2715')
          .fontSize(14)
          .fontColor($r('app.color.tertiary_text'))
          .width(24)
          .height(24)
          .textAlign(TextAlign.Center)
          .margin({ left: -32 })
          .onClick(() => {
            this.clearSearch();
          })
      }

      if (this.ocrLoading) {
        LoadingProgress()
          .width(22)
          .height(22)
          .margin({ left: 10 })
          .color($r('app.color.poetry_green'))
      } else {
        Text('\uD83D\uDCF7')
          .fontSize(16)
          .fontColor($r('app.color.poetry_green'))
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .backgroundColor($r('app.color.poetry_green') + '18')
          .borderRadius(16)
          .margin({ left: 10 })
          .onClick(() => {
            this.onOcrPick();
          })
      }

      Text('搜索')
        .fontSize(14)
        .fontColor($r('app.color.on_accent_text'))
        .backgroundColor($r('app.color.poetry_green'))
        .borderRadius(16)
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .margin({ left: 8 })
        .onClick(() => {
          this.onSearchSubmit();
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 4 })
  }

  @Builder
  DynastyTabs() {
    Scroll() {
      Row({ space: 6 }) {
        ForEach(this.dynasties, (dynasty: string) => {
          Text(dynasty)
            .fontSize(13)
            .fontColor(this.activeDynasty === dynasty ? $r('app.color.on_accent_text') : $r('app.color.secondary_text'))
            .backgroundColor(this.activeDynasty === dynasty ? $r('app.color.poetry_green') : $r('app.color.border_color'))
            .borderRadius(12)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .onClick(() => {
              this.onDynastyTap(dynasty);
            })
        }, (dynasty: string) => dynasty)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder
  ContentArea() {
    if (this.isLoading) {
      Column() {
        LoadingProgress()
          .width(48)
          .height(48)
          .color($r('app.color.poetry_green'))
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
    } else if (this.isSearching) {
      this.SearchResults()
    } else {
      this.PoetList()
    }
  }

  @Builder
  SearchResults() {
    List({ space: 6 }) {
      if (this.results.length === 0) {
        ListItem() {
          Text('未找到相关结果')
            .fontSize(16)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 40 })
        }
      }

      ForEach(this.results, (item: SearchResultItem) => {
        ListItem() {
          Row() {
            Column() {
              Text(item.title)
                .fontSize(15)
                .fontColor($r('app.color.primary_text'))
                .fontWeight(FontWeight.Medium)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(item.subtitle)
                .fontSize(12)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            if (item.type === 'poem' && this.isPoemFav(item.title)) {
              Text('\u2665')
                .fontSize(14)
                .fontColor($r('app.color.danger_red'))
                .margin({ right: 6 })
            }

            Text(item.type === 'poet' ? '诗人' : '诗词')
              .fontSize(11)
              .fontColor($r('app.color.poetry_green'))
              .backgroundColor($r('app.color.poetry_green') + '18')
              .borderRadius(6)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(10)
          .onClick(() => {
            this.onResultTap(item);
          })
        }
      }, (item: SearchResultItem) => item.type + '_' + item.title)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 12, right: 12, top: 4 })
    .cachedCount(10)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder
  PoetList() {
    List({ space: 6 }) {
      ForEach(this.poets, (poet: PoetItem) => {
        ListItem() {
          Row() {
            Column() {
              Text(poet.n)
                .fontSize(15)
                .fontColor($r('app.color.primary_text'))
                .fontWeight(FontWeight.Medium)
              Text(poet.d + ' \u00B7 ' + poet.pc.toString() + '首')
                .fontSize(12)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Text('\u203A')
              .fontSize(20)
              .fontColor($r('app.color.hint_text'))
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(10)
          .onClick(() => {
            this.onPoetTap(poet);
          })
        }
      }, (poet: PoetItem) => poet.n + '_' + poet.d)

      if (this.hasMorePoets) {
        ListItem() {
          Row() {
            if (this.loadingMore) {
              LoadingProgress()
                .width(20)
                .height(20)
                .color($r('app.color.poetry_green'))
                .margin({ right: 6 })
            }
            Text(this.loadingMore ? '加载中...' : '加载更多')
              .fontSize(14)
              .fontColor($r('app.color.tertiary_text'))
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 10, bottom: 10 })
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 12, right: 12, top: 4 })
    .cachedCount(10)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .onReachEnd(() => {
      this.loadMorePoets();
    })
  }
}
