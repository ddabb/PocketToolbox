import { PoetryQueryPageBuilder } from './PoetryQueryPage';
import { IdiomQueryPageBuilder } from './IdiomQueryPage';
import { XiehouyuQueryPageBuilder } from './XiehouyuQueryPage';
import { PoetryDetailPageBuilder } from './PoetryDetailPage';
import { PoemContentPageBuilder } from './PoemContentPage';
import { FavoritesPageBuilder } from './FavoritesPage';
import { AboutPageBuilder } from './AboutPage';
import { Md2PngPageBuilder } from './Md2PngPage';
import { UnitCategoryPageBuilder } from './UnitCategoryPage';
import { UnitConverterPageBuilder } from './UnitConverterPage';
import { BaseConverterPageBuilder } from './BaseConverterPage';
import { TimezoneConverterPageBuilder } from './TimezoneConverterPage';
import { ReadingListPageBuilder } from './ReadingListPage';
import { ReadingPlayerPageBuilder } from './ReadingPlayerPage';
import { DailyChallengePageBuilder } from './DailyChallengePage';
import { AchievementPageBuilder } from './AchievementPage';
import { GcdLcmPageBuilder } from './GcdLcmPage';
import { PrimeFactorPageBuilder } from './PrimeFactorPage';
import { PoetryViewModel } from '../viewmodel/PoetryViewModel';
import { IdiomViewModel } from '../viewmodel/IdiomViewModel';
import { XiehouyuViewModel } from '../viewmodel/XiehouyuViewModel';
import { PoemItem, PoetDetail, PoetItem } from '../model/PoetryModels';
import { IdiomDetailItem } from '../model/IdiomModels';
import { XiehouyuItem } from '../model/XiehouyuModels';
import { FavoritesUtil, FavoriteItem } from '../common/utils/FavoritesUtil';
import { StickinessUtil, CheckInData, ChallengeProgress, UserStats } from '../common/utils/StickinessUtil';
import { ReadingListStore, ReadingList } from '../model/ReadingListModels';
import { bundleManager } from '@kit.AbilityKit';
import { ConverterCategory, UnitConverterData } from '../model/UnitModels';

class ToolItem {
  id: string = '';
  title: string = '';
  subtitle: string = '';
  icon: string = '';
  color: string = '';
  page: string = '';
  param: Record<string, Object> | null = null;

  constructor(id: string, title: string, subtitle: string, icon: string, color: string,
    page: string, param: Record<string, Object> | null = null) {
    this.id = id;
    this.title = title;
    this.subtitle = subtitle;
    this.icon = icon;
    this.color = color;
    this.page = page;
    this.param = param;
  }
}

@Entry
@Component
struct Index {
  homeStack: NavPathStack = new NavPathStack();
  toolStack: NavPathStack = new NavPathStack();
  mineStack: NavPathStack = new NavPathStack();
  @State currentTab: number = 0;
  @State dailyPoemTitle: string = '';
  @State dailyPoemAuthor: string = '';
  @State dailyPoemContent: string = '';
  @State dailyIdiom: string = '';
  @State dailyIdiomMeaning: string = '';
  @State dailyXiehouyu: string = '';
  @State dailyXiehouyuAnswer: string = '';
  @State dailyPoemItem: PoemItem | null = null;
  @State poemOffset: number = 0;
  @State idiomOffset: number = 0;
  @State xiehouyuOffset: number = 0;
  @StorageLink('favCount') favCount: number = 0;
  @State unitTools: ToolItem[] = [];
  @State checkInData: CheckInData = new CheckInData();
  @State checkedInToday: boolean = false;
  @State challengeProgress: ChallengeProgress = new ChallengeProgress();
  @State reviewItem: FavoriteItem | null = null;
  @State reviewVisible: boolean = false;
  @State appVersionName: string = '';
  @State mineUserStats: UserStats = new UserStats();
  @State mineCheckInData: CheckInData = new CheckInData();
  @State mineChallengeProgress: ChallengeProgress = new ChallengeProgress();
  private poetryVm: PoetryViewModel = PoetryViewModel.getInstance();
  private idiomVm: IdiomViewModel = IdiomViewModel.getInstance();
  private xiehouyuVm: XiehouyuViewModel = XiehouyuViewModel.getInstance();
  private readonly DAILY_PADDING: number = 12;
  private readonly DAILY_RADIUS: number = 12;
  private readonly DAILY_HEADER_ICON_SIZE: number = 13;
  private readonly DAILY_HEADER_TITLE_SIZE: number = 12;
  private readonly DAILY_HEADER_MARGIN_BOTTOM: number = 5;
  private readonly DAILY_LOADING_SIZE: number = 15;
  private readonly DAILY_SKELETON_RADIUS: number = 4;
  private readonly POEM_HEADER_ICON_SIZE: number = 14;
  private readonly POEM_HEADER_MARGIN_BOTTOM: number = 6;
  private readonly POEM_TITLE_SIZE: number = 15;
  private readonly POEM_CONTENT_SIZE: number = 12;
  private readonly IDIOM_WORD_SIZE: number = 18;
  private readonly IDIOM_MEANING_SIZE: number = 11;
  private readonly XIEHOUYU_QUESTION_SIZE: number = 13;
  private readonly XIEHOUYU_ANSWER_SIZE: number = 12;

  aboutToAppear(): void {
    AppStorage.setOrCreate('AppNavPathStack', this.homeStack);
    AppStorage.setOrCreate('AppHostContext', this.getUIContext().getHostContext() as Context);
    AppStorage.setOrCreate('AppUIContext', this.getUIContext());
    this.buildToolItems();
    setTimeout(() => {
      this.loadDailyContent();
    }, 0);
    this.loadFavCount();
    this.loadStickinessData();
    try {
      let info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.appVersionName = info.versionName;
    } catch (e) {
      this.appVersionName = '';
    }
  }

  private buildToolItems(): void {
    let tools: ToolItem[] = [];
    tools.push(new ToolItem('gcd_lcm', '公约/倍数', '最大公约数、最小公倍数', 'unit_gcd_lcm', '#e74c3c', 'GcdLcmPage'));
    tools.push(new ToolItem('prime_factor', '质因数分解', '分解合数为质数乘积', 'unit_prime_factor', '#9b59b6', 'PrimeFactorPage'));
    let cats: ConverterCategory[] = UnitConverterData.getCategories();
    for (let i = 0; i < cats.length; i++) {
      let cat: ConverterCategory = cats[i];
      if (cat.isBase) {
        tools.push(new ToolItem(cat.id, cat.title, '二进制/八进制/十六进制/Base64', cat.icon, cat.color, 'BaseConverterPage'));
      } else if (cat.isTimezone) {
        tools.push(new ToolItem(cat.id, cat.title, '全球城市时区对照与会议协调', cat.icon, cat.color, 'TimezoneConverterPage'));
      } else {
        let sub: string = this.getUnitSubtitle(cat);
        let param: Record<string, Object> = {
          'categoryId': cat.id as Object,
          'title': cat.title as Object
        };
        tools.push(new ToolItem(cat.id, cat.title, sub, cat.icon, cat.color, 'UnitConverterPage', param));
      }
    }
    this.unitTools = tools;
  }

  private getUnitSubtitle(cat: ConverterCategory): string {
    if (cat.isTemperature) {
      return '摄氏度、华氏度、开尔文等';
    }
    let names: string[] = [];
    let count: number = Math.min(cat.units.length, 3);
    for (let i = 0; i < count; i++) {
      names.push(cat.units[i].name);
    }
    let suffix: string = cat.units.length > 3 ? '等' + cat.units.length.toString() + '种' : '';
    return names.join('、') + suffix;
  }

  onPageShow(): void {
    this.loadFavCount();
    this.loadStickinessData();
  }

  private loadStickinessData(): void {
    let ctx: Context = this.getUIContext().getHostContext() as Context;
    this.checkInData = StickinessUtil.loadCheckIn(ctx);
    this.checkedInToday = StickinessUtil.isCheckedInToday(ctx);
    this.challengeProgress = StickinessUtil.loadChallengeProgress(ctx);
    this.loadReviewItem(ctx);
    this.mineCheckInData = StickinessUtil.loadCheckIn(ctx);
    this.mineChallengeProgress = StickinessUtil.loadChallengeProgress(ctx);
    FavoritesUtil.invalidateCache();
    let favs: FavoriteItem[] = FavoritesUtil.load(ctx);
    let poemCount: number = 0;
    let idiomCount: number = 0;
    let xiehouyuCount: number = 0;
    for (let i = 0; i < favs.length; i++) {
      if (favs[i].type === 'poem') {
        poemCount++;
      } else if (favs[i].type === 'idiom') {
        idiomCount++;
      } else if (favs[i].type === 'xiehouyu') {
        xiehouyuCount++;
      }
    }
    StickinessUtil.syncFavStats(ctx, poemCount, idiomCount, xiehouyuCount);
    let readingItemCount: number = 0;
    let readingLists: ReadingList[] = ReadingListStore.load(ctx);
    for (let i = 0; i < readingLists.length; i++) {
      readingItemCount += readingLists[i].items.length;
    }
    StickinessUtil.syncReadingStats(ctx, readingItemCount);
    this.mineUserStats = StickinessUtil.loadStats(ctx);
  }

  private doCheckIn(): void {
    let ctx: Context = this.getUIContext().getHostContext() as Context;
    let ok: boolean = StickinessUtil.doCheckIn(ctx);
    if (ok) {
      this.checkInData = StickinessUtil.loadCheckIn(ctx);
      this.checkedInToday = true;
      this.getUIContext().getPromptAction().showToast({ message: '签到成功！连续' + this.checkInData.streak.toString() + '天', duration: 1500 });
    }
  }

  private loadReviewItem(ctx: Context): void {
    let favs: FavoriteItem[] = FavoritesUtil.load(ctx);
    if (favs.length === 0) {
      this.reviewVisible = false;
      this.reviewItem = null;
      return;
    }
    let poemFavs: FavoriteItem[] = [];
    for (let i = 0; i < favs.length; i++) {
      if (favs[i].type === 'poem') {
        poemFavs.push(favs[i]);
      }
    }
    let pool: FavoriteItem[] = poemFavs.length > 0 ? poemFavs : favs;
    let seed: number = new Date().getFullYear() * 10000 + (new Date().getMonth() + 1) * 100 + new Date().getDate();
    let idx: number = Math.floor(Math.abs(Math.sin(seed + 999) * 10000) % pool.length);
    this.reviewItem = pool[idx];
    this.reviewVisible = true;
  }

  private loadFavCount(): void {
    let ctx: Context = this.getUIContext().getHostContext() as Context;
    FavoritesUtil.invalidateCache();
    let favs = FavoritesUtil.load(ctx);
    this.favCount = favs.length;
  }

  private loadDailyContent(): void {
    let seed: number = this.getDailySeed();
    this.loadDailyPoem(seed + this.poemOffset);
    this.loadDailyIdiom(seed + this.idiomOffset);
    this.loadDailyXiehouyu(seed + this.xiehouyuOffset);
  }

  private refreshPoem(): void {
    this.poemOffset = Math.floor(Math.random() * 100000);
    this.loadDailyPoem(this.getDailySeed() + this.poemOffset);
  }

  private refreshIdiom(): void {
    this.idiomOffset = Math.floor(Math.random() * 100000);
    this.loadDailyIdiom(this.getDailySeed() + this.idiomOffset);
  }

  private refreshXiehouyu(): void {
    this.xiehouyuOffset = Math.floor(Math.random() * 100000);
    this.loadDailyXiehouyu(this.getDailySeed() + this.xiehouyuOffset);
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
    this.dailyPoemContent = poem.c;
    this.dailyPoemItem = poem;
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
      PoetryQueryPageBuilder(param)
    } else if (name === 'IdiomQueryPage') {
      IdiomQueryPageBuilder(param)
    } else if (name === 'XiehouyuQueryPage') {
      XiehouyuQueryPageBuilder()
    } else if (name === 'PoetryDetailPage') {
      PoetryDetailPageBuilder(param)
    } else if (name === 'PoemContentPage') {
      PoemContentPageBuilder(param)
    } else if (name === 'FavoritesPage') {
      FavoritesPageBuilder()
    } else if (name === 'AboutPage') {
      AboutPageBuilder()
    } else if (name === 'Md2PngPage') {
      Md2PngPageBuilder()
    } else if (name === 'UnitCategoryPage') {
      UnitCategoryPageBuilder()
    } else if (name === 'UnitConverterPage') {
      UnitConverterPageBuilder(param)
    } else if (name === 'BaseConverterPage') {
      BaseConverterPageBuilder()
    } else if (name === 'TimezoneConverterPage') {
      TimezoneConverterPageBuilder()
    } else if (name === 'ReadingListPage') {
      ReadingListPageBuilder()
    } else if (name === 'ReadingPlayerPage') {
      ReadingPlayerPageBuilder(param)
    } else if (name === 'DailyChallengePage') {
      DailyChallengePageBuilder()
    } else if (name === 'AchievementPage') {
      AchievementPageBuilder()
    } else if (name === 'GcdLcmPage') {
      GcdLcmPageBuilder()
    } else if (name === 'PrimeFactorPage') {
      PrimeFactorPageBuilder()
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
          this.ToolContent()
        }
        .tabBar(this.TabBarItem(1, '\uD83D\uDD27', '工具'))

        TabContent() {
          this.MineContent()
        }
        .tabBar(this.TabBarItem(2, '\uD83D\uDC64', '我的'))
      }
      .barPosition(BarPosition.End)
      .scrollable(false)
      .onChange((index: number) => {
        this.currentTab = index;
        if (index === 0) {
          this.homeStack.clear();
          AppStorage.setOrCreate('AppNavPathStack', this.homeStack);
        } else if (index === 1) {
          this.toolStack.clear();
          AppStorage.setOrCreate('AppNavPathStack', this.toolStack);
        } else {
          this.mineStack.clear();
          AppStorage.setOrCreate('AppNavPathStack', this.mineStack);
          this.loadFavCount();
          this.loadStickinessData();
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

          this.CheckInAndChallengeCard()

          Row() {
            Column() {
              Column() {
                Text('\uD83C\uDF3C')
                  .fontSize(28)
              }
              .width(44)
              .height(44)
              .borderRadius(12)
              .backgroundColor('#2d7d4618')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .margin({ bottom: 6 })
              Text('诗词查询')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary_text'))
              Text('唐诗宋词，按朝代浏览')
                .fontSize(10)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .padding(12)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)
            .alignItems(HorizontalAlign.Center)
            .margin({ right: 4 })
            .onClick(() => {
              this.homeStack.pushPathByName('PoetryQueryPage', null);
            })

            Column() {
              Column() {
                Text('\uD83D\uDCD6')
                  .fontSize(28)
              }
              .width(44)
              .height(44)
              .borderRadius(12)
              .backgroundColor('#2980b918')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .margin({ bottom: 6 })
              Text('成语查询')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary_text'))
              Text('成语接龙，顺查逆查')
                .fontSize(10)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .padding(12)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)
            .alignItems(HorizontalAlign.Center)
            .margin({ left: 4 })
            .onClick(() => {
              this.homeStack.pushPathByName('IdiomQueryPage', null);
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          Row() {
            Column() {
              Column() {
                Image($r('app.media.mine_xiehouyu'))
                  .width(44)
                  .height(44)
                  .borderRadius(12)
              }
              .margin({ bottom: 6 })
              Text('歇后语')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary_text'))
              Text('趣味歇后语，猜谜玩法')
                .fontSize(10)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .padding(12)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)
            .alignItems(HorizontalAlign.Center)
            .margin({ right: 4 })
            .onClick(() => {
              this.homeStack.pushPathByName('XiehouyuQueryPage', null);
            })

            Column() {
              Column() {
                Text('\uD83D\uDDBC\uFE0F')
                  .fontSize(28)
              }
              .width(44)
              .height(44)
              .borderRadius(12)
              .backgroundColor('#9b59b618')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .margin({ bottom: 6 })
              Text('文字转图片')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary_text'))
              Text('Markdown文本生成图片')
                .fontSize(10)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .padding(12)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)
            .alignItems(HorizontalAlign.Center)
            .margin({ left: 4 })
            .onClick(() => {
              this.homeStack.pushPathByName('Md2PngPage', null);
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8 })

          if (this.reviewVisible && this.reviewItem) {
            this.ReviewCard()
          }

          Row() {
            Column() {
              if (this.dailyIdiom) {
                this.DailyIdiomCardInner()
              } else {
                this.DailyIdiomSkeleton()
              }
            }
            .layoutWeight(1)
            .padding({ right: 5 })

            Column() {
              if (this.dailyXiehouyu) {
                this.DailyXiehouyuCardInner()
              } else {
                this.DailyXiehouyuSkeleton()
              }
            }
            .layoutWeight(1)
            .padding({ left: 5 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8 })

          if (this.dailyPoemTitle) {
            this.DailyPoemCard()
          } else {
            this.DailyPoemSkeleton()
          }
        }
        .width('100%')
        .padding({ bottom: 8 })
      }
      .width('100%')
      .height('100%')
      .scrollable(ScrollDirection.Vertical)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .navDestination(this.PageMap)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .backgroundColor($r('app.color.page_background'))
    .hideToolBar(true)
  }

  @Builder
  ToolContent() {
    Navigation(this.toolStack) {
      Scroll() {
        Column() {
          Column() {
            Text('\uD83D\uDD27')
              .fontSize(40)
              .margin({ bottom: 6 })
            Text('工具箱')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
            Text('实用计算与换算工具集')
              .fontSize(13)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ top: 3 })
          }
          .width('100%')
          .padding({ top: 8, bottom: 12 })
          .alignItems(HorizontalAlign.Center)

          Text('单位换算')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .width('100%')
            .padding({ left: 16, bottom: 8 })

          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.unitTools, (tool: ToolItem) => {
              Column() {
                Image($r('app.media.' + tool.icon))
                  .width(56)
                  .height(56)
                  .borderRadius(14)

                Text(tool.title)
                  .fontSize(12)
                  .fontColor($r('app.color.primary_text'))
                  .margin({ top: 6 })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: 72 })
              }
              .width('25%')
              .padding({ top: 8, bottom: 12 })
              .alignItems(HorizontalAlign.Center)
              .onClick(() => {
                this.toolStack.pushPathByName(tool.page, tool.param);
              })
            }, (tool: ToolItem) => tool.id)
          }
          .width('100%')
          .padding({ left: 8, right: 8 })
        }
        .width('100%')
        .padding({ bottom: 16 })
      }
      .width('100%')
      .height('100%')
      .scrollable(ScrollDirection.Vertical)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
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
            Image($r('app.media.foreground'))
              .width(52)
              .height(52)
              .borderRadius(12)
              .margin({ bottom: 6 })
            Text('解语珠玑')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))

          }
          .width('100%')
          .padding({ top: 8, bottom: 12 })
          .alignItems(HorizontalAlign.Center)

          Row() {
            Column() {
              Text(this.mineCheckInData.totalDays.toString())
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor('#27ae60')
              Text('累计签到')
                .fontSize(11)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)

            Divider()
              .vertical(true)
              .height(30)
              .color($r('app.color.border_color'))

            Column() {
              Text(this.mineCheckInData.streak.toString())
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.idiom_orange'))
              Text('连续签到')
                .fontSize(11)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)

            Divider()
              .vertical(true)
              .height(30)
              .color($r('app.color.border_color'))

            Column() {
              Text('\uD83D\uDCD6')
                .fontSize(22)
                .fontColor($r('app.color.poetry_green'))
              Text('朗读清单')
                .fontSize(11)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.mineStack.pushPathByName('ReadingListPage', null);
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
              Image($r('app.media.mine_xiehouyu'))
                .width(20)
                .height(20)
                .borderRadius(5)
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

          Column() {
            Row() {
              Text('\uD83D\uDCC5')
                .fontSize(20)
                .margin({ right: 10 })
              Text('今日签到')
                .fontSize(15)
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text(this.mineCheckInData.lastDate === StickinessUtil.todayStr() ? '\u2713 已签到' : '未签到')
                .fontSize(14)
                .fontColor(this.mineCheckInData.lastDate === StickinessUtil.todayStr() ? '#27ae60' : $r('app.color.tertiary_text'))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })

            Divider()
              .color($r('app.color.border_color'))
              .margin({ left: 46 })

            Row() {
              Text('\uD83D\uDD25')
                .fontSize(20)
                .margin({ right: 10 })
              Text('连续签到')
                .fontSize(15)
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text(this.mineCheckInData.streak.toString() + '天')
                .fontSize(14)
                .fontColor($r('app.color.idiom_orange'))
                .fontWeight(FontWeight.Bold)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })

            Divider()
              .color($r('app.color.border_color'))
              .margin({ left: 46 })

            Row() {
              Text('\uD83C\uDFC6')
                .fontSize(20)
                .margin({ right: 10 })
              Text('今日挑战')
                .fontSize(15)
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text(this.mineChallengeProgress.completed && this.mineChallengeProgress.date === StickinessUtil.todayStr() ? '已完成' : '未完成')
                .fontSize(14)
                .fontColor(this.mineChallengeProgress.completed && this.mineChallengeProgress.date === StickinessUtil.todayStr() ? '#27ae60' : $r('app.color.tertiary_text'))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })

            Divider()
              .color($r('app.color.border_color'))
              .margin({ left: 46 })

            Row() {
              Text('\uD83D\uDC41')
                .fontSize(20)
                .margin({ right: 10 })
              Text('累计浏览')
                .fontSize(15)
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text(this.mineUserStats.browseCount.toString() + '次')
                .fontSize(14)
                .fontColor($r('app.color.tertiary_text'))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })

            Divider()
              .color($r('app.color.border_color'))
              .margin({ left: 46 })

            Row() {
              Text('\uD83D\uDCDA')
                .fontSize(20)
                .margin({ right: 10 })
              Text('累计挑战')
                .fontSize(15)
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text(this.mineChallengeProgress.totalChallenges.toString() + '次')
                .fontSize(14)
                .fontColor($r('app.color.tertiary_text'))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })

            Divider()
              .color($r('app.color.border_color'))
              .margin({ left: 46 })

            Row() {
              Text('\uD83D\uDDE3')
                .fontSize(20)
                .margin({ right: 10 })
              Text('朗读内容')
                .fontSize(15)
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text(this.mineUserStats.readingItems.toString() + '篇')
                .fontSize(14)
                .fontColor($r('app.color.tertiary_text'))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          }
          .width('100%')
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(14)
          .margin({ left: 16, right: 16, top: 12 })

          Text('解语珠玑' + (this.appVersionName ? ' \u00B7 v' + this.appVersionName : ''))
            .fontSize(12)
            .fontColor($r('app.color.hint_text'))
            .margin({ top: 24, bottom: 16 })
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .scrollable(ScrollDirection.Vertical)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
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
          .fontSize(this.POEM_HEADER_ICON_SIZE)
          .margin({ right: 4 })
        Text('每日一诗')
          .fontSize(this.DAILY_HEADER_TITLE_SIZE + 1)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.poetry_green'))
        Blank()
        Text('\uD83D\uDD04')
          .fontSize(this.DAILY_LOADING_SIZE + 1)
          .fontColor($r('app.color.poetry_green'))
          .onClick(() => {
            this.refreshPoem();
          })
      }
      .width('100%')
      .margin({ bottom: this.POEM_HEADER_MARGIN_BOTTOM })
      Text(this.dailyPoemTitle)
        .fontSize(this.POEM_TITLE_SIZE)
        .fontColor($r('app.color.primary_text'))
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .margin({ bottom: 3 })
      Text(this.dailyPoemContent)
        .fontSize(this.POEM_CONTENT_SIZE)
        .fontColor($r('app.color.secondary_text'))
        .lineHeight(20)
        .width('100%')
    }
    .width('100%')
    .padding(this.DAILY_PADDING)
    .backgroundColor($r('app.color.poetry_card_bg'))
    .borderRadius(this.DAILY_RADIUS)
    .margin({ left: 16, right: 16, bottom: 8 })
    .onClick(() => {
      if (this.dailyPoemItem) {
        this.homeStack.pushPathByName('PoemContentPage', this.dailyPoemItem);
      } else {
        this.homeStack.pushPathByName('PoetryQueryPage', null);
      }
    })
  }

  @Builder
  DailyIdiomCardInner() {
    Column() {
      Row() {
        Text('\uD83D\uDCD6')
          .fontSize(this.DAILY_HEADER_ICON_SIZE)
          .margin({ right: 3 })
        Text('每日成语')
          .fontSize(this.DAILY_HEADER_TITLE_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.idiom_blue'))
        Blank()
        Text('\uD83D\uDD04')
          .fontSize(this.DAILY_LOADING_SIZE)
          .fontColor($r('app.color.idiom_blue'))
          .onClick(() => {
            this.refreshIdiom();
          })
      }
      .margin({ bottom: this.DAILY_HEADER_MARGIN_BOTTOM })
      Text(this.dailyIdiom)
        .fontSize(this.IDIOM_WORD_SIZE)
        .fontColor($r('app.color.primary_text'))
        .fontWeight(FontWeight.Bold)
        .letterSpacing(2)
        .margin({ bottom: 3 })
      Text(this.dailyIdiomMeaning)
        .fontSize(this.IDIOM_MEANING_SIZE)
        .fontColor($r('app.color.secondary_text'))
        .lineHeight(16)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(this.DAILY_PADDING)
    .backgroundColor($r('app.color.idiom_card_bg'))
    .borderRadius(this.DAILY_RADIUS)
    .onClick(() => {
      this.homeStack.pushPathByName('IdiomQueryPage', this.dailyIdiom);
    })
  }

  @Builder
  DailyXiehouyuCardInner() {
    Column() {
      Row() {
        Text('\uD83E\uDD14')
          .fontSize(this.DAILY_HEADER_ICON_SIZE)
          .margin({ right: 3 })
        Text('每日歇后语')
          .fontSize(this.DAILY_HEADER_TITLE_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.idiom_orange'))
        Blank()
        Text('\uD83D\uDD04')
          .fontSize(this.DAILY_LOADING_SIZE)
          .fontColor($r('app.color.idiom_orange'))
          .onClick(() => {
            this.refreshXiehouyu();
          })
      }
      .margin({ bottom: this.DAILY_HEADER_MARGIN_BOTTOM })
      Text(this.dailyXiehouyu)
        .fontSize(this.XIEHOUYU_QUESTION_SIZE)
        .fontColor($r('app.color.primary_text'))
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ bottom: 2 })
      Text('—— ' + this.dailyXiehouyuAnswer)
        .fontSize(this.XIEHOUYU_ANSWER_SIZE)
        .fontColor($r('app.color.idiom_orange'))
        .fontWeight(FontWeight.Bold)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(this.DAILY_PADDING)
    .backgroundColor($r('app.color.xiehouyu_card_bg'))
    .borderRadius(this.DAILY_RADIUS)
    .onClick(() => {
      this.homeStack.pushPathByName('XiehouyuQueryPage', null);
    })
  }

  @Builder
  DailyIdiomSkeleton() {
    Column() {
      Row() {
        Text('\uD83D\uDCD6')
          .fontSize(this.DAILY_HEADER_ICON_SIZE)
          .margin({ right: 3 })
        Text('每日成语')
          .fontSize(this.DAILY_HEADER_TITLE_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.idiom_blue'))
        Blank()
        LoadingProgress()
          .width(this.DAILY_LOADING_SIZE)
          .height(this.DAILY_LOADING_SIZE)
          .color($r('app.color.idiom_blue'))
      }
      .margin({ bottom: this.DAILY_HEADER_MARGIN_BOTTOM })
      Row()
        .width(80)
        .height(this.IDIOM_WORD_SIZE + 4)
        .borderRadius(this.DAILY_SKELETON_RADIUS)
        .backgroundColor($r('app.color.idiom_blue') + '12')
        .margin({ bottom: 3 })
      Row()
        .width('100%')
        .height(this.IDIOM_MEANING_SIZE + 3)
        .borderRadius(this.DAILY_SKELETON_RADIUS)
        .backgroundColor($r('app.color.idiom_blue') + '0a')
      Row()
        .width('70%')
        .height(this.IDIOM_MEANING_SIZE + 3)
        .borderRadius(this.DAILY_SKELETON_RADIUS)
        .backgroundColor($r('app.color.idiom_blue') + '0a')
        .margin({ top: 4 })
    }
    .width('100%')
    .padding(this.DAILY_PADDING)
    .backgroundColor($r('app.color.idiom_card_bg'))
    .borderRadius(this.DAILY_RADIUS)
  }

  @Builder
  DailyXiehouyuSkeleton() {
    Column() {
      Row() {
        Text('\uD83E\uDD14')
          .fontSize(this.DAILY_HEADER_ICON_SIZE)
          .margin({ right: 3 })
        Text('每日歇后语')
          .fontSize(this.DAILY_HEADER_TITLE_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.idiom_orange'))
        Blank()
        LoadingProgress()
          .width(this.DAILY_LOADING_SIZE)
          .height(this.DAILY_LOADING_SIZE)
          .color($r('app.color.idiom_orange'))
      }
      .margin({ bottom: this.DAILY_HEADER_MARGIN_BOTTOM })
      Row()
        .width('80%')
        .height(this.XIEHOUYU_QUESTION_SIZE + 3)
        .borderRadius(this.DAILY_SKELETON_RADIUS)
        .backgroundColor($r('app.color.idiom_orange') + '12')
        .margin({ bottom: 2 })
      Row()
        .width('60%')
        .height(this.XIEHOUYU_ANSWER_SIZE + 4)
        .borderRadius(this.DAILY_SKELETON_RADIUS)
        .backgroundColor($r('app.color.idiom_orange') + '0a')
    }
    .width('100%')
    .padding(this.DAILY_PADDING)
    .backgroundColor($r('app.color.xiehouyu_card_bg'))
    .borderRadius(this.DAILY_RADIUS)
  }

  @Builder
  DailyPoemSkeleton() {
    Column() {
      Row() {
        Text('\uD83C\uDF3C')
          .fontSize(this.POEM_HEADER_ICON_SIZE)
          .margin({ right: 4 })
        Text('每日一诗')
          .fontSize(this.DAILY_HEADER_TITLE_SIZE + 1)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.poetry_green'))
        Blank()
        LoadingProgress()
          .width(this.DAILY_LOADING_SIZE)
          .height(this.DAILY_LOADING_SIZE)
          .color($r('app.color.poetry_green'))
      }
      .width('100%')
      .margin({ bottom: this.POEM_HEADER_MARGIN_BOTTOM })
      Row()
        .width('60%')
        .height(this.POEM_TITLE_SIZE + 3)
        .borderRadius(this.DAILY_SKELETON_RADIUS)
        .backgroundColor($r('app.color.poetry_green') + '12')
        .margin({ bottom: 3 })
      Row()
        .width('100%')
        .height(this.POEM_CONTENT_SIZE + 2)
        .borderRadius(this.DAILY_SKELETON_RADIUS)
        .backgroundColor($r('app.color.poetry_green') + '0a')
      Row()
        .width('90%')
        .height(this.POEM_CONTENT_SIZE + 2)
        .borderRadius(this.DAILY_SKELETON_RADIUS)
        .backgroundColor($r('app.color.poetry_green') + '0a')
        .margin({ top: 3 })
      Row()
        .width('75%')
        .height(this.POEM_CONTENT_SIZE + 2)
        .borderRadius(this.DAILY_SKELETON_RADIUS)
        .backgroundColor($r('app.color.poetry_green') + '0a')
        .margin({ top: 3 })
    }
    .width('100%')
    .padding(this.DAILY_PADDING)
    .backgroundColor($r('app.color.poetry_card_bg'))
    .borderRadius(this.DAILY_RADIUS)
    .margin({ left: 16, right: 16, bottom: 8 })
  }

  @Builder
  CheckInAndChallengeCard() {
    Row() {
      Column() {
        Row() {
          Text('\uD83D\uDCC5')
            .fontSize(14)
            .margin({ right: 4 })
          Text('每日签到')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.idiom_orange'))
        }
        .margin({ bottom: 6 })
        if (this.checkedInToday) {
          Text('\u2713 已签到')
            .fontSize(14)
            .fontColor('#27ae60')
            .fontWeight(FontWeight.Bold)
          Text('连续' + this.checkInData.streak.toString() + '天')
            .fontSize(11)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 2 })
        } else {
          Text('点击签到')
            .fontSize(14)
            .fontColor($r('app.color.idiom_orange'))
            .fontWeight(FontWeight.Bold)
          if (this.checkInData.streak > 0) {
            Text('已连续' + this.checkInData.streak.toString() + '天')
              .fontSize(11)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ top: 2 })
          } else {
            Text('开始你的连续签到')
              .fontSize(11)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ top: 2 })
          }
        }
      }
      .layoutWeight(1)
      .padding(12)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(12)
      .alignItems(HorizontalAlign.Center)
      .margin({ right: 4 })
      .onClick(() => {
        if (!this.checkedInToday) {
          this.doCheckIn();
        }
      })

      Column() {
        Row() {
          Text('\uD83C\uDFC6')
            .fontSize(14)
            .margin({ right: 4 })
          Text('每日挑战')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.poetry_green'))
        }
        .margin({ bottom: 6 })
        if (this.challengeProgress.completed && this.challengeProgress.date === StickinessUtil.todayStr()) {
          Text('已完成')
            .fontSize(14)
            .fontColor('#27ae60')
            .fontWeight(FontWeight.Bold)
          Text('得分 ' + this.challengeProgress.score.toString())
            .fontSize(11)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 2 })
        } else {
          Text('去挑战')
            .fontSize(14)
            .fontColor($r('app.color.poetry_green'))
            .fontWeight(FontWeight.Bold)
          Text('答题赢积分')
            .fontSize(11)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .padding(12)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(12)
      .alignItems(HorizontalAlign.Center)
      .margin({ left: 4 })
      .onClick(() => {
        this.homeStack.pushPathByName('DailyChallengePage', null);
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8 })
  }

  @Builder
  ReviewCard() {
    Column() {
      Row() {
        Text('\uD83D\uDCDD')
          .fontSize(13)
          .margin({ right: 3 })
        Text('温故知新')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.poetry_green'))
        Blank()
        Text('\u203A')
          .fontSize(16)
          .fontColor($r('app.color.hint_text'))
      }
      .margin({ bottom: 5 })
      if (this.reviewItem) {
        Text(this.reviewItem.title)
          .fontSize(15)
          .fontColor($r('app.color.primary_text'))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ bottom: 2 })
        Text(this.reviewItem.subtitle)
          .fontSize(11)
          .fontColor($r('app.color.secondary_text'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.poetry_card_bg'))
    .borderRadius(12)
    .margin({ left: 16, right: 16, bottom: 8 })
    .onClick(() => {
      this.homeStack.pushPathByName('FavoritesPage', null);
    })
  }
}
