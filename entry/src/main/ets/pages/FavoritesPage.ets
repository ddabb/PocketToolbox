import { FavoritesUtil, FavoriteItem } from '../common/utils/FavoritesUtil';
import { FavDetailModal } from '../components/FavDetailModal';
import { promptAction } from '@kit.ArkUI';

@Builder
export function FavoritesPageBuilder() {
  NavDestination() {
    FavoritesContent()
  }
  .title($r('app.string.page_favorites'))
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct FavoritesContent {
  @State favorites: FavoriteItem[] = [];
  @State activeTab: string = 'all';
  @State displayItems: FavoriteItem[] = [];
  @State detailItem: FavoriteItem | null = null;
  private uiContext: UIContext = this.getUIContext();
  private detailDialogController: CustomDialogController | null = null;

  private getNavPathStack(): NavPathStack {
    return AppStorage.get('AppNavPathStack') as NavPathStack;
  }

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
    AppStorage.setOrCreate('favCount', this.favorites.length);
    console.info('[Favorites] loaded: ' + this.favorites.length.toString());
  }

  private refreshDisplay(): void {
    if (this.activeTab === 'all') {
      this.displayItems = this.favorites.slice();
    } else {
      let items: FavoriteItem[] = [];
      for (let i = 0; i < this.favorites.length; i++) {
        if (this.favorites[i].type === this.activeTab) {
          items.push(this.favorites[i]);
        }
      }
      this.displayItems = items;
    }
  }

  private removeItem(item: FavoriteItem): void {
    let uiContext: UIContext = this.getUIContext();
    uiContext.getPromptAction().showDialog({
      title: $r('app.string.readlist_confirm_delete'),
      message: $r('app.string.favsp_delete_msg', item.title),
      buttons: [
        { text: $r('app.string.readlist_cancel'), color: $r('app.color.tertiary_text') },
        { text: $r('app.string.readlist_delete'), color: $r('app.color.danger_red') }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        FavoritesUtil.remove(uiContext.getHostContext() as Context, item.type, item.title);
        this.loadFavorites();
      }
    }).catch(() => {});
  }

  private onTap(item: FavoriteItem): void {
    this.detailItem = item;
    this.detailDialogController = new CustomDialogController({
      builder: FavDetailModal({ favItem: this.detailItem }),
      customStyle: true,
      alignment: DialogAlignment.Center,
      autoCancel: true
    });
    this.detailDialogController.open();
  }

  build() {
    Column() {
      Column() {
        Row({ space: 8 }) {
          Text($r('app.string.favsp_tab_all'))
            .fontSize(14)
            .fontColor(this.activeTab === 'all' ? $r('app.color.on_accent_text') : $r('app.color.secondary_text'))
            .backgroundColor(this.activeTab === 'all' ? $r('app.color.tab_selected_bg') : $r('app.color.border_color'))
            .borderRadius(12)
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
            .onClick(() => {
              this.activeTab = 'all';
              this.refreshDisplay();
            })

          Text($r('app.string.favsp_tab_poem'))
            .fontSize(14)
            .fontColor(this.activeTab === 'poem' ? $r('app.color.on_accent_text') : $r('app.color.secondary_text'))
            .backgroundColor(this.activeTab === 'poem' ? $r('app.color.poetry_green') : $r('app.color.border_color'))
            .borderRadius(12)
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
            .onClick(() => {
              this.activeTab = 'poem';
              this.refreshDisplay();
            })

          Text($r('app.string.favsp_tab_idiom'))
            .fontSize(14)
            .fontColor(this.activeTab === 'idiom' ? $r('app.color.on_accent_text') : $r('app.color.secondary_text'))
            .backgroundColor(this.activeTab === 'idiom' ? $r('app.color.idiom_blue') : $r('app.color.border_color'))
            .borderRadius(12)
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
            .onClick(() => {
              this.activeTab = 'idiom';
              this.refreshDisplay();
            })

          Text($r('app.string.xiehouyu_short'))
            .fontSize(14)
            .fontColor(this.activeTab === 'xiehouyu' ? $r('app.color.on_accent_text') : $r('app.color.secondary_text'))
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
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        } else {
          Column() {
            Text(this.activeTab === 'all' ? $r('app.string.favsp_empty_all') :
              this.activeTab === 'poem' ? $r('app.string.favsp_empty_poem') :
                this.activeTab === 'idiom' ? $r('app.string.favsp_empty_idiom') : $r('app.string.favsp_empty_xiehouyu'))
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
      .constraintSize({ maxWidth: 720 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
