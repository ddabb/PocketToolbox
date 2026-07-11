import { PoetryQueryPageBuilder } from './PoetryQueryPage';
import { IdiomQueryPageBuilder } from './IdiomQueryPage';
import { XiehouyuQueryPageBuilder } from './XiehouyuQueryPage';
import { PoetryDetailPageBuilder } from './PoetryDetailPage';
import { PoemContentPageBuilder } from './PoemContentPage';
import { FavoritesPageBuilder } from './FavoritesPage';
import { PoetryViewModel } from '../viewmodel/PoetryViewModel';
import { IdiomViewModel } from '../viewmodel/IdiomViewModel';
import { XiehouyuViewModel } from '../viewmodel/XiehouyuViewModel';
import { PoemItem, PoetDetail, PoetItem } from '../model/PoetryModels';
import { IdiomDetailItem } from '../model/IdiomModels';
import { XiehouyuItem } from '../model/XiehouyuModels';
import { ClipboardUtil } from '../common/utils/ClipboardUtil';

class ToolCategory {
  id: string = '';
  title: string = '';
  subtitle: string = '';
  icon: string = '';
  color: string = '';
  page: string = '';

  constructor(id: string, title: string, subtitle: string, icon: string, color: string, page: string) {
    this.id = id;
    this.title = title;
    this.subtitle = subtitle;
    this.icon = icon;
    this.color = color;
    this.page = page;
  }
}

@Entry
@Component
struct Index {
  pageStack: NavPathStack = new NavPathStack();
  @State categories: ToolCategory[] = [
    new ToolCategory('poetry', '诗词查询', '唐诗宋词，按朝代浏览', '\uD83C\uDF3C', '#2d7d46', 'PoetryQueryPage'),
    new ToolCategory('idiom', '成语查询', '成语接龙，顺查逆查', '\uD83D\uDCD6', '#2980b9', 'IdiomQueryPage'),
    new ToolCategory('xiehouyu', '歇后语', '趣味歇后语，猜谜玩法', '\uD83E\uDD14', '#e67e22', 'XiehouyuQueryPage'),
    new ToolCategory('favorites', '我的收藏', '收藏的诗词和成语', '\u2665', '#e74c3c', 'FavoritesPage')
  ];
  @State dailyPoemTitle: string = '';
  @State dailyPoemAuthor: string = '';
  @State dailyPoemContent: string = '';
  @State dailyIdiom: string = '';
  @State dailyIdiomMeaning: string = '';
  @State dailyXiehouyu: string = '';
  @State dailyXiehouyuAnswer: string = '';
  private poetryVm: PoetryViewModel = PoetryViewModel.getInstance();
  private idiomVm: IdiomViewModel = IdiomViewModel.getInstance();
  private xiehouyuVm: XiehouyuViewModel = XiehouyuViewModel.getInstance();

  aboutToAppear(): void {
    AppStorage.setOrCreate('AppNavPathStack', this.pageStack);
    AppStorage.setOrCreate('AppHostContext', this.getUIContext().getHostContext() as Context);
    AppStorage.setOrCreate('AppUIContext', this.getUIContext());
    this.loadDailyContent();
  }

  private loadDailyContent(): void {
    let seed: number = this.getDailySeed();
    this.loadDailyPoem(seed);
    this.loadDailyIdiom(seed);
    this.loadDailyXiehouyu(seed);
  }

  private getDailySeed(): number {
    let now: Date = new Date();
    let dayNum: number = now.getFullYear() * 10000 + (now.getMonth() + 1) * 100 + now.getDate();
    return dayNum;
  }

  private seededRandom(seed: number): number {
    let x: number = Math.sin(seed) * 10000;
    return x - Math.floor(x);
  }

  private loadDailyPoem(seed: number): void {
    let context: Context = this.getUIContext().getHostContext() as Context;
    if (!this.poetryVm.isDataLoaded()) {
      let ok: boolean = this.poetryVm.loadIndex(context);
      if (!ok) {
        console.error('[Index] loadDailyPoem: poetry index load failed');
        return;
      }
    }
    let poets: PoetItem[] = this.poetryVm.getFilteredPoets('全部');
    if (poets.length === 0) {
      return;
    }
    let poetIdx: number = Math.floor(this.seededRandom(seed) * poets.length);
    let poet: PoetItem = poets[poetIdx];
    let detail: PoetDetail = this.poetryVm.loadPoetDetail(context, poet.n, poet.i, poet.d);
    if (detail.poems.length === 0) {
      return;
    }
    let poemIdx: number = Math.floor(this.seededRandom(seed + 1) * detail.poems.length);
    let poem: PoemItem = detail.poems[poemIdx];
    this.dailyPoemTitle = poem.n;
    this.dailyPoemAuthor = detail.name + ' \u00B7 ' + detail.dynasty;
    this.dailyPoemContent = poem.c.length > 60 ? poem.c.substring(0, 60) + '...' : poem.c;
    console.info('[Index] dailyPoem: ' + poem.n + ' by ' + detail.name);
  }

  private loadDailyIdiom(seed: number): void {
    let context: Context = this.getUIContext().getHostContext() as Context;
    if (!this.idiomVm.isDataLoaded()) {
      let ok: boolean = this.idiomVm.loadData(context);
      if (!ok) {
        return;
      }
    }
    let detail: IdiomDetailItem | null = this.idiomVm.getDailyIdiom(context, seed);
    if (detail) {
      this.dailyIdiom = detail.word;
      this.dailyIdiomMeaning = detail.explanation.length > 30 ? detail.explanation.substring(0, 30) + '...' : detail.explanation;
      console.info('[Index] dailyIdiom: ' + detail.word);
    }
  }

  private loadDailyXiehouyu(seed: number): void {
    let context: Context = this.getUIContext().getHostContext() as Context;
    if (!this.xiehouyuVm.isReady()) {
      let ok: boolean = this.xiehouyuVm.loadData(context);
      if (!ok) {
        return;
      }
    }
    let item: XiehouyuItem | null = this.xiehouyuVm.getDailyItem(seed);
    if (item) {
      this.dailyXiehouyu = item.riddle;
      this.dailyXiehouyuAnswer = item.answer;
      console.info('[Index] dailyXiehouyu: ' + item.riddle);
    }
  }

  @Builder
  PageMap(name: string, param: Object) {
    if (name === 'PoetryQueryPage') {
      PoetryQueryPageBuilder()
    } else if (name === 'IdiomQueryPage') {
      IdiomQueryPageBuilder()
    } else if (name === 'XiehouyuQueryPage') {
      XiehouyuQueryPageBuilder()
    } else if (name === 'PoetryDetailPage') {
      PoetryDetailPageBuilder(param)
    } else if (name === 'PoemContentPage') {
      PoemContentPageBuilder(param)
    } else if (name === 'FavoritesPage') {
      FavoritesPageBuilder()
    }
  }

  build() {
    Navigation(this.pageStack) {
      Scroll() {
        Column() {
          Column() {
            Text('\uD83D\uDCD6')
              .fontSize(48)
              .margin({ bottom: 8 })
            Text('文字之美')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
            Text('品读经典，感悟文字之美')
              .fontSize(14)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ top: 4 })
          }
          .margin({ top: 40, bottom: 24 })

          if (this.dailyPoemTitle) {
            this.DailyPoemCard()
          }

          if (this.dailyIdiom) {
            this.DailyIdiomCard()
          }

          if (this.dailyXiehouyu) {
            this.DailyXiehouyuCard()
          }

          Grid() {
            ForEach(this.categories, (cat: ToolCategory) => {
              GridItem() {
                Column() {
                  Column() {
                    Text(cat.icon)
                      .fontSize(36)
                  }
                  .width(56)
                  .height(56)
                  .borderRadius(16)
                  .backgroundColor(cat.color + '18')
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .margin({ bottom: 12 })

                  Text(cat.title)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.primary_text'))
                    .margin({ bottom: 4 })

                  Text(cat.subtitle)
                    .fontSize(12)
                    .fontColor($r('app.color.tertiary_text'))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 20, bottom: 20 })
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(14)
                .alignItems(HorizontalAlign.Center)
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.pageStack.pushPathByName(cat.page, null);
                })
              }
            }, (cat: ToolCategory) => cat.id)
          }
          .columnsTemplate('1fr 1fr')
          .rowsGap(10)
          .columnsGap(10)
          .width('100%')
          .padding({ left: 16, right: 16 })
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .scrollable(ScrollDirection.Vertical)
    }
    .navDestination(this.PageMap)
    .title('文字之美')
    .titleMode(NavigationTitleMode.Mini)
    .mode(NavigationMode.Stack)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  DailyPoemCard() {
    Column() {
      Row() {
        Text('\uD83C\uDF3C')
          .fontSize(16)
          .margin({ right: 4 })
        Text('每日一诗')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.poetry_green'))
        Blank()
        Text(this.dailyPoemAuthor)
          .fontSize(12)
          .fontColor($r('app.color.tertiary_text'))
      }
      .width('100%')
      .margin({ bottom: 8 })

      Text(this.dailyPoemTitle)
        .fontSize(16)
        .fontColor($r('app.color.primary_text'))
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .margin({ bottom: 4 })

      Text(this.dailyPoemContent)
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
        .lineHeight(22)
        .width('100%')
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.poetry_card_bg'))
    .borderRadius(12)
    .margin({ left: 16, right: 16, bottom: 10 })
    .onClick(() => {
      this.pageStack.pushPathByName('PoetryQueryPage', null);
    })
  }

  @Builder
  DailyIdiomCard() {
    Column() {
      Row() {
        Text('\uD83D\uDCD6')
          .fontSize(16)
          .margin({ right: 4 })
        Text('每日成语')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.idiom_blue'))
        Blank()
        Text('点击查看详情 >')
          .fontSize(12)
          .fontColor($r('app.color.idiom_blue'))
      }
      .width('100%')
      .margin({ bottom: 8 })

      Text(this.dailyIdiom)
        .fontSize(20)
        .fontColor($r('app.color.primary_text'))
        .fontWeight(FontWeight.Bold)
        .letterSpacing(4)
        .margin({ bottom: 4 })

      Text(this.dailyIdiomMeaning)
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
        .lineHeight(20)
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.idiom_card_bg'))
    .borderRadius(12)
    .margin({ left: 16, right: 16, bottom: 10 })
    .onClick(() => {
      this.pageStack.pushPathByName('IdiomQueryPage', null);
    })
  }

  @Builder
  DailyXiehouyuCard() {
    Column() {
      Row() {
        Text('\uD83E\uDD14')
          .fontSize(16)
          .margin({ right: 4 })
        Text('每日歇后语')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.idiom_orange'))
        Blank()
        Text('猜谜玩法 >')
          .fontSize(12)
          .fontColor($r('app.color.idiom_orange'))
      }
      .width('100%')
      .margin({ bottom: 8 })

      Text(this.dailyXiehouyu)
        .fontSize(15)
        .fontColor($r('app.color.primary_text'))
        .fontWeight(FontWeight.Medium)
        .lineHeight(22)
        .width('100%')
        .margin({ bottom: 4 })

      Text('—— ' + this.dailyXiehouyuAnswer)
        .fontSize(14)
        .fontColor($r('app.color.idiom_orange'))
        .fontWeight(FontWeight.Bold)
        .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.xiehouyu_card_bg'))
    .borderRadius(12)
    .margin({ left: 16, right: 16, bottom: 10 })
    .onClick(() => {
      this.pageStack.pushPathByName('XiehouyuQueryPage', null);
    })
  }
}
