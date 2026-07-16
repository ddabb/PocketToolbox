import { PoetryQueryPageBuilder } from './PoetryQueryPage';
import { IdiomQueryPageBuilder } from './IdiomQueryPage';
import { XiehouyuQueryPageBuilder } from './XiehouyuQueryPage';
import { PoetryDetailPageBuilder } from './PoetryDetailPage';
import { PoemContentPageBuilder } from './PoemContentPage';
import { FavoritesPageBuilder } from './FavoritesPage';
import { MinePageBuilder } from './MinePage';
import { AboutPageBuilder } from './AboutPage';
import { PoetryViewModel } from '../viewmodel/PoetryViewModel';
import { IdiomViewModel } from '../viewmodel/IdiomViewModel';
import { XiehouyuViewModel } from '../viewmodel/XiehouyuViewModel';
import { PoemItem, PoetDetail, PoetItem } from '../model/PoetryModels';
import { IdiomDetailItem } from '../model/IdiomModels';
import { XiehouyuItem } from '../model/XiehouyuModels';
import { FavoritesUtil } from '../common/utils/FavoritesUtil';

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
  homeStack: NavPathStack = new NavPathStack();
  mineStack: NavPathStack = new NavPathStack();
  @State currentTab: number = 0;
  @State categories: ToolCategory[] = [
    new ToolCategory('poetry', '诗词查询', '唐诗宋词，按朝代浏览', '\uD83C\uDF3C', '#2d7d46', 'PoetryQueryPage'),
    new ToolCategory('idiom', '成语查询', '成语接龙，顺查逆查', '\uD83D\uDCD6', '#2980b9', 'IdiomQueryPage'),
    new ToolCategory('xiehouyu', '歇后语', '趣味歇后语，猜谜玩法', '\uD83E\uDD14', '#bf5b04', 'XiehouyuQueryPage')
  ];
  @State dailyPoemTitle: string = '';
  @State dailyPoemAuthor: string = '';
  @State dailyPoemContent: string = '';
  @State dailyIdiom: string = '';
  @State dailyIdiomMeaning: string = '';
  @State dailyXiehouyu: string = '';
  @State dailyXiehouyuAnswer: string = '';
  @State favCount: number = 0;
  private poetryVm: PoetryViewModel = PoetryViewModel.getInstance();
  private idiomVm: IdiomViewModel = IdiomViewModel.getInstance();
  private xiehouyuVm: XiehouyuViewModel = XiehouyuViewModel.getInstance();

  aboutToAppear(): void {
    AppStorage.setOrCreate('AppNavPathStack', this.homeStack);
    AppStorage.setOrCreate('AppHostContext', this.getUIContext().getHostContext() as Context);
    AppStorage.setOrCreate('AppUIContext', this.getUIContext());
    this.loadDailyContent();
    this.loadFavCount();
  }

  onPageShow(): void {
    this.loadFavCount();
  }

  private loadFavCount(): void {
    let ctx: Context = this.getUIContext().getHostContext() as Context;
    FavoritesUtil.invalidateCache();
    let favs = FavoritesUtil.load(ctx);
    this.favCount = favs.length;
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
    } else if (name === 'MinePage') {
      MinePageBuilder()
    } else if (name === 'AboutPage') {
      AboutPageBuilder()
    }
  }

  build() {
    Column() {
      Tabs({ index: this.currentTab }) {
        TabContent() {
          this.HomeContent()
        }
        .tabBar(this.TabBarItem(0, '\uD83C\uDFE0', '首页'))

        TabContent() {
          this.MineContent()
        }
        .tabBar(this.TabBarItem(1, '\uD83D\uDC64', '我的'))
      }
      .barPosition(BarPosition.End)
      .scrollable(false)
      .onChange((index: number) => {
        this.currentTab = index;
        if (index === 0) {
          this.homeStack.clear();
          AppStorage.setOrCreate('AppNavPathStack', this.homeStack);
        } else {
          this.mineStack.clear();
          AppStorage.setOrCreate('AppNavPathStack', this.mineStack);
          this.loadFavCount();
        }
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  TabBarItem(index: number, icon: string, label: string) {
    Column() {
      Text(icon)
        .fontSize(22)
      Text(label)
        .fontSize(11)
        .fontColor(this.currentTab === index ? $r('app.color.poetry_green') : $r('app.color.tertiary_text'))
        .margin({ top: 2 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  HomeContent() {
    Navigation(this.homeStack) {
      Scroll() {
        Column() {
          Column() {
            Text('\uD83D\uDCD6')
              .fontSize(40)
              .margin({ bottom: 6 })
            Text('解语珠玑')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
            Text('品读经典，感悟文字之美')
              .fontSize(13)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ top: 3 })
          }
          .width('100%')
          .padding({ top: 8, bottom: 12 })
          .alignItems(HorizontalAlign.Center)

          if (this.dailyPoemTitle) {
            this.DailyPoemCard()
          }

          Row() {
            if (this.dailyIdiom) {
              Column() {
                this.DailyIdiomCardInner()
              }
              .layoutWeight(1)
              .padding({ right: 5 })
            }
            if (this.dailyXiehouyu) {
              Column() {
                this.DailyXiehouyuCardInner()
              }
              .layoutWeight(1)
              .padding({ left: 5 })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          Grid() {
            ForEach(this.categories, (cat: ToolCategory) => {
              GridItem() {
                Column() {
                  Column() {
                    Text(cat.icon)
                      .fontSize(32)
                  }
                  .width(48)
                  .height(48)
                  .borderRadius(14)
                  .backgroundColor(cat.color + '18')
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .margin({ bottom: 8 })
                  Text(cat.title)
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.primary_text'))
                    .margin({ bottom: 3 })
                  Text(cat.subtitle)
                    .fontSize(11)
                    .fontColor($r('app.color.tertiary_text'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                .padding({ left: 10, right: 10, top: 16, bottom: 16 })
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(14)
                .alignItems(HorizontalAlign.Center)
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.homeStack.pushPathByName(cat.page, null);
                })
              }
            }, (cat: ToolCategory) => cat.id)
          }
          .columnsTemplate('1fr 1fr 1fr')
          .rowsGap(8)
          .columnsGap(8)
          .width('100%')
          .padding({ left: 16, right: 16, top: 10 })
        }
        .width('100%')
        .padding({ bottom: 8 })
      }
      .width('100%')
      .height('100%')
      .scrollable(ScrollDirection.Vertical)
    }
    .navDestination(this.PageMap)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .backgroundColor($r('app.color.page_background'))
    .hideToolBar(true)
  }

  @Builder
  MineContent() {
    Navigation(this.mineStack) {
      Scroll() {
        Column() {
          Column() {
            Text('\uD83D\uDC64')
              .fontSize(40)
              .margin({ bottom: 6 })
            Text('解语珠玑')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
            Text('品读经典，感悟文字之美')
              .fontSize(13)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ top: 3 })
          }
          .width('100%')
          .padding({ top: 8, bottom: 12 })
          .alignItems(HorizontalAlign.Center)

          Row() {
            Column() {
              Text(this.favCount.toString())
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor('#e74c3c')
              Text('收藏总数')
                .fontSize(11)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.mineStack.pushPathByName('FavoritesPage', null);
            })

            Divider()
              .vertical(true)
              .height(30)
              .color($r('app.color.border_color'))

            Column() {
              Text('\u2665')
                .fontSize(22)
                .fontColor('#e74c3c')
              Text('我的收藏')
                .fontSize(11)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.mineStack.pushPathByName('FavoritesPage', null);
            })

            Divider()
              .vertical(true)
              .height(30)
              .color($r('app.color.border_color'))

            Column() {
              Text('\u2139')
                .fontSize(22)
                .fontColor($r('app.color.poetry_green'))
              Text('关于')
                .fontSize(11)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.mineStack.pushPathByName('AboutPage', null);
            })
          }
          .width('100%')
          .padding({ top: 14, bottom: 14 })
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(14)
          .margin({ left: 16, right: 16 })

          Column() {
            Row() {
              Text('\u2665')
                .fontSize(20)
                .margin({ right: 10 })
              Text('我的收藏')
                .fontSize(15)
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text('\u203A')
                .fontSize(18)
                .fontColor($r('app.color.hint_text'))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .onClick(() => {
              this.mineStack.pushPathByName('FavoritesPage', null);
            })

            Divider()
              .color($r('app.color.border_color'))
              .margin({ left: 46 })

            Row() {
              Text('\uD83C\uDF3C')
                .fontSize(20)
                .margin({ right: 10 })
              Text('诗词查询')
                .fontSize(15)
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text('\u203A')
                .fontSize(18)
                .fontColor($r('app.color.hint_text'))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .onClick(() => {
              this.mineStack.pushPathByName('PoetryQueryPage', null);
            })

            Divider()
              .color($r('app.color.border_color'))
              .margin({ left: 46 })

            Row() {
              Text('\uD83D\uDCD6')
                .fontSize(20)
                .margin({ right: 10 })
              Text('成语查询')
                .fontSize(15)
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text('\u203A')
                .fontSize(18)
                .fontColor($r('app.color.hint_text'))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .onClick(() => {
              this.mineStack.pushPathByName('IdiomQueryPage', null);
            })

            Divider()
              .color($r('app.color.border_color'))
              .margin({ left: 46 })

            Row() {
              Text('\uD83E\uDD14')
                .fontSize(20)
                .margin({ right: 10 })
              Text('歇后语')
                .fontSize(15)
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text('\u203A')
                .fontSize(18)
                .fontColor($r('app.color.hint_text'))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .onClick(() => {
              this.mineStack.pushPathByName('XiehouyuQueryPage', null);
            })
          }
          .width('100%')
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(14)
          .margin({ left: 16, right: 16, top: 12 })

          Text('解语珠玑 \u00B7 v1.0.0')
            .fontSize(12)
            .fontColor($r('app.color.hint_text'))
            .margin({ top: 24, bottom: 16 })
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .scrollable(ScrollDirection.Vertical)
    }
    .navDestination(this.PageMap)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .backgroundColor($r('app.color.page_background'))
    .hideToolBar(true)
  }

  @Builder
  DailyPoemCard() {
    Column() {
      Row() {
        Text('\uD83C\uDF3C')
          .fontSize(14)
          .margin({ right: 4 })
        Text('每日一诗')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.poetry_green'))
        Blank()
        Text(this.dailyPoemAuthor)
          .fontSize(11)
          .fontColor($r('app.color.tertiary_text'))
      }
      .width('100%')
      .margin({ bottom: 6 })
      Text(this.dailyPoemTitle)
        .fontSize(15)
        .fontColor($r('app.color.primary_text'))
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .margin({ bottom: 3 })
      Text(this.dailyPoemContent)
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
        .lineHeight(20)
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.poetry_card_bg'))
    .borderRadius(12)
    .margin({ left: 16, right: 16, bottom: 8 })
    .onClick(() => {
      this.homeStack.pushPathByName('PoetryQueryPage', null);
    })
  }

  @Builder
  DailyIdiomCardInner() {
    Column() {
      Row() {
        Text('\uD83D\uDCD6')
          .fontSize(13)
          .margin({ right: 3 })
        Text('每日成语')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.idiom_blue'))
      }
      .margin({ bottom: 5 })
      Text(this.dailyIdiom)
        .fontSize(18)
        .fontColor($r('app.color.primary_text'))
        .fontWeight(FontWeight.Bold)
        .letterSpacing(2)
        .margin({ bottom: 3 })
      Text(this.dailyIdiomMeaning)
        .fontSize(11)
        .fontColor($r('app.color.secondary_text'))
        .lineHeight(16)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.idiom_card_bg'))
    .borderRadius(12)
    .onClick(() => {
      this.homeStack.pushPathByName('IdiomQueryPage', null);
    })
  }

  @Builder
  DailyXiehouyuCardInner() {
    Column() {
      Row() {
        Text('\uD83E\uDD14')
          .fontSize(13)
          .margin({ right: 3 })
        Text('每日歇后语')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.idiom_orange'))
      }
      .margin({ bottom: 5 })
      Text(this.dailyXiehouyu)
        .fontSize(13)
        .fontColor($r('app.color.primary_text'))
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ bottom: 2 })
      Text('—— ' + this.dailyXiehouyuAnswer)
        .fontSize(12)
        .fontColor($r('app.color.idiom_orange'))
        .fontWeight(FontWeight.Bold)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.xiehouyu_card_bg'))
    .borderRadius(12)
    .onClick(() => {
      this.homeStack.pushPathByName('XiehouyuQueryPage', null);
    })
  }
}
