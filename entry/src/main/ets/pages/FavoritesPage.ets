import { FavoritesUtil, FavoriteItem } from '../common/utils/FavoritesUtil';
import { PoemItem } from '../model/PoetryModels';
import { IdiomDetailItem } from '../model/IdiomModels';
import { IdiomViewModel } from '../viewmodel/IdiomViewModel';

@Builder
export function FavoritesPageBuilder() {
  NavDestination() {
    FavoritesContent()
  }
  .title('我的收藏')
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct FavoritesContent {
  @State favorites: FavoriteItem[] = [];
  @State activeTab: string = 'poem';
  @State displayItems: FavoriteItem[] = [];
  private uiContext: UIContext = this.getUIContext();
  navPathStack: NavPathStack = AppStorage.get('AppNavPathStack') as NavPathStack;

  aboutToAppear(): void {
    this.loadFavorites();
  }

  onPageShow(): void {
    FavoritesUtil.invalidateCache();
    this.loadFavorites();
  }

  private loadFavorites(): void {
    this.favorites = FavoritesUtil.load(this.uiContext.getHostContext() as Context);
    this.refreshDisplay();
    console.info('[Favorites] loaded: ' + this.favorites.length.toString());
  }

  private refreshDisplay(): void {
    let items: FavoriteItem[] = [];
    for (let i = 0; i < this.favorites.length; i++) {
      if (this.favorites[i].type === this.activeTab) {
        items.push(this.favorites[i]);
      }
    }
    this.displayItems = items;
  }

  private removeItem(item: FavoriteItem): void {
    FavoritesUtil.remove(this.uiContext.getHostContext() as Context, item.type, item.title);
    this.loadFavorites();
  }

  private onTap(item: FavoriteItem): void {
    if (item.type === 'poem') {
      try {
        let poem: PoemItem = JSON.parse(item.data) as PoemItem;
        this.navPathStack.pushPathByName('PoemContentPage', poem);
      } catch (e) {
        console.error('[Favorites] parse poem failed: ' + (e as Error).message);
      }
    } else if (item.type === 'idiom') {
      let detail: IdiomDetailItem | null = IdiomViewModel.getInstance().findIdiomDetail(
        this.uiContext.getHostContext() as Context, item.title);
      if (detail) {
        console.info('[Favorites] idiom detail: ' + detail.word);
      }
    }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text('诗词')
          .fontSize(14)
          .fontColor(this.activeTab === 'poem' ? '#ffffff' : $r('app.color.secondary_text'))
          .backgroundColor(this.activeTab === 'poem' ? $r('app.color.poetry_green') : $r('app.color.border_color'))
          .borderRadius(12)
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .onClick(() => {
            this.activeTab = 'poem';
            this.refreshDisplay();
          })

        Text('成语')
          .fontSize(14)
          .fontColor(this.activeTab === 'idiom' ? '#ffffff' : $r('app.color.secondary_text'))
          .backgroundColor(this.activeTab === 'idiom' ? $r('app.color.idiom_blue') : $r('app.color.border_color'))
          .borderRadius(12)
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .onClick(() => {
            this.activeTab = 'idiom';
            this.refreshDisplay();
          })

        Text('歇后语')
          .fontSize(14)
          .fontColor(this.activeTab === 'xiehouyu' ? '#ffffff' : $r('app.color.secondary_text'))
          .backgroundColor(this.activeTab === 'xiehouyu' ? $r('app.color.idiom_orange') : $r('app.color.border_color'))
          .borderRadius(12)
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .onClick(() => {
            this.activeTab = 'xiehouyu';
            this.refreshDisplay();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 4 })

      if (this.displayItems.length > 0) {
        List({ space: 6 }) {
          ForEach(this.displayItems, (item: FavoriteItem) => {
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

                Text('\u2715')
                  .fontSize(14)
                  .fontColor($r('app.color.danger_red'))
                  .width(28)
                  .height(28)
                  .borderRadius(14)
                  .backgroundColor($r('app.color.danger_red') + '18')
                  .textAlign(TextAlign.Center)
                  .onClick(() => {
                    this.removeItem(item);
                  })
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(10)
              .onClick(() => {
                this.onTap(item);
              })
            }
          }, (item: FavoriteItem) => item.type + '_' + item.title)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 10, right: 10, top: 4 })
        .cachedCount(10)
      } else {
        Column() {
          Text(this.activeTab === 'poem' ? '暂无收藏的诗词' : this.activeTab === 'idiom' ? '暂无收藏的成语' : '暂无收藏的歇后语')
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
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
