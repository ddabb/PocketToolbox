import { FavoritesUtil, FavoriteItem } from '../common/utils/FavoritesUtil';
import { preferences } from '@kit.ArkData';

class MineStatItem {
  label: string = '';
  value: string = '';
  icon: string = '';
  color: string = '';

  constructor(label: string, value: string, icon: string, color: string) {
    this.label = label;
    this.value = value;
    this.icon = icon;
    this.color = color;
  }
}

class MineActionItem {
  label: string = '';
  icon: string = '';
  color: string = '';
  page: string = '';

  constructor(label: string, icon: string, color: string, page: string) {
    this.label = label;
    this.icon = icon;
    this.color = color;
    this.page = page;
  }
}

@Builder
export function MinePageBuilder() {
  NavDestination() {
    MineContent()
  }
  .title('我的')
  .backButtonIcon($r('sys.symbol.chevron_left'))
}

@Component
struct MineContent {
  @State poemCount: number = 0;
  @State idiomCount: number = 0;
  @State xiehouyuCount: number = 0;
  @State browseCount: number = 0;
  @State stats: MineStatItem[] = [];
  @State actions: MineActionItem[] = [];
  private uiContext: UIContext = this.getUIContext();
  navPathStack: NavPathStack = AppStorage.get('AppNavPathStack') as NavPathStack;

  aboutToAppear(): void {
    this.loadStats();
    this.actions = [
      new MineActionItem('我的收藏', '\u2665', '#e74c3c', 'FavoritesPage'),
      new MineActionItem('诗词查询', '\uD83C\uDF3C', '#2d7d46', 'PoetryQueryPage'),
      new MineActionItem('成语查询', '\uD83D\uDCD6', '#2980b9', 'IdiomQueryPage'),
      new MineActionItem('歇后语', '\uD83E\uDD14', '#bf5b04', 'XiehouyuQueryPage')
    ];
  }

  onPageShow(): void {
    this.loadStats();
  }

  private loadStats(): void {
    let ctx: Context = this.uiContext.getHostContext() as Context;
    FavoritesUtil.invalidateCache();
    let favs: FavoriteItem[] = FavoritesUtil.load(ctx);
    this.poemCount = 0;
    this.idiomCount = 0;
    this.xiehouyuCount = 0;
    for (let i = 0; i < favs.length; i++) {
      if (favs[i].type === 'poem') {
        this.poemCount++;
      } else if (favs[i].type === 'idiom') {
        this.idiomCount++;
      } else if (favs[i].type === 'xiehouyu') {
        this.xiehouyuCount++;
      }
    }
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(ctx, { name: 'app_cache' });
      this.browseCount = (prefs.getSync('browse_count', 0) as number);
    } catch (e) {
      this.browseCount = 0;
    }
    this.stats = [
      new MineStatItem('收藏诗词', this.poemCount.toString(), '\uD83C\uDF3C', '#2d7d46'),
      new MineStatItem('收藏成语', this.idiomCount.toString(), '\uD83D\uDCD6', '#2980b9'),
      new MineStatItem('收藏歇后语', this.xiehouyuCount.toString(), '\uD83E\uDD14', '#bf5b04'),
      new MineStatItem('浏览次数', this.browseCount.toString(), '\uD83D\uDC41', '#8e44ad')
    ];
  }

  build() {
    Scroll() {
      Column() {
        Column() {
          Text('\uD83D\uDC64')
            .fontSize(48)
            .margin({ bottom: 8 })
          Text('解语珠玑')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          Text('品读经典，感悟文字之美')
            .fontSize(13)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 4 })
        }
        .width('100%')
        .padding({ top: 32, bottom: 20 })
        .alignItems(HorizontalAlign.Center)

        Row() {
          ForEach(this.stats, (stat: MineStatItem) => {
            Column() {
              Text(stat.icon)
                .fontSize(20)
                .margin({ bottom: 4 })
              Text(stat.value)
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(stat.color)
              Text(stat.label)
                .fontSize(11)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
          }, (stat: MineStatItem, index: number) => stat.label + '_' + index.toString())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(14)
        .margin({ left: 16, right: 16 })

        Column() {
          ForEach(this.actions, (action: MineActionItem, index: number) => {
            Row() {
              Text(action.icon)
                .fontSize(22)
                .margin({ right: 12 })
              Text(action.label)
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
              if (action.page === 'FavoritesPage') {
                this.navPathStack.pushPathByName('FavoritesPage', null);
              } else if (action.page === 'PoetryQueryPage') {
                this.navPathStack.pushPathByName('PoetryQueryPage', null);
              } else if (action.page === 'IdiomQueryPage') {
                this.navPathStack.pushPathByName('IdiomQueryPage', null);
              } else if (action.page === 'XiehouyuQueryPage') {
                this.navPathStack.pushPathByName('XiehouyuQueryPage', null);
              }
            })
            if (index < this.actions.length - 1) {
              Divider()
                .color($r('app.color.border_color'))
                .margin({ left: 50 })
            }
          }, (action: MineActionItem, index: number) => action.label + '_' + index.toString())
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(14)
        .margin({ left: 16, right: 16, top: 12 })

        Column() {
          Row() {
            Text('\u2139')
              .fontSize(18)
              .margin({ right: 8 })
            Text('关于')
              .fontSize(15)
              .fontColor($r('app.color.primary_text'))
              .layoutWeight(1)
            Text('v1.0.0')
              .fontSize(13)
              .fontColor($r('app.color.tertiary_text'))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(14)
        .margin({ left: 16, right: 16, top: 12 })

        Text('解语珠玑 \u00B7 品读经典，感悟文字之美')
          .fontSize(12)
          .fontColor($r('app.color.hint_text'))
          .margin({ top: 24, bottom: 16 })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
