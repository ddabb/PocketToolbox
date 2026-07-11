import { PoemItem } from '../model/PoetryModels';
import { ClipboardUtil } from '../common/utils/ClipboardUtil';
import { FavoritesUtil, FavoriteItem } from '../common/utils/FavoritesUtil';
import { PoetryViewModel } from '../viewmodel/PoetryViewModel';

function buildPoemItem(param: Object): PoemItem {
  return PoetryViewModel.getInstance().parsePoemFromParam(param as Record<string, Object>);
}

@Builder
export function PoemContentPageBuilder(param: Object) {
  NavDestination() {
    PoemContentContent({ poemParam: buildPoemItem(param) })
  }
  .title((param as Record<string, Object>)['n'] as string || '诗词详情')
  .hideTitleBar(false)
  .menus([
    {
      value: '收藏',
      icon: $r('sys.symbol.heart'),
      action: () => {
        let poem: PoemItem = buildPoemItem(param);
        let ctx: Context = AppStorage.get('AppHostContext') as Context;
        let item: FavoriteItem = new FavoriteItem();
        item.type = 'poem';
        item.title = poem.n;
        item.subtitle = (poem.a || '') + ' \u00B7 ' + (poem.d || '');
        item.data = JSON.stringify(poem);
        let added: boolean = FavoritesUtil.add(ctx, item);
        let msg: string = added ? '已收藏' : '已在收藏中';
        let uiCtx: UIContext = AppStorage.get('AppUIContext') as UIContext;
        uiCtx.getPromptAction().showToast({ message: msg, duration: 1000 });
      }
    },
    {
      value: '首页',
      icon: $r('sys.symbol.house'),
      action: () => {
        let stack: NavPathStack = AppStorage.get('AppNavPathStack') as NavPathStack;
        stack.clear();
      }
    }
  ])
}

@Component
export struct PoemContentContent {
  @Prop poemParam: PoemItem = new PoemItem();
  @State poetName: string = '';
  @State isFav: boolean = false;
  private uiContext: UIContext = this.getUIContext();

  aboutToAppear(): void {
    this.poetName = this.poemParam.a || '';
    this.isFav = FavoritesUtil.isFavorite(this.uiContext.getHostContext() as Context, 'poem', this.poemParam.n);
    console.info('[PoemContent] poem=' + this.poemParam.n + ', poet=' + this.poetName);
  }

  private copyPoem(): void {
    let text: string = '\u3010' + this.poemParam.n + '\u3011' + this.poetName + '\n' + this.poemParam.c;
    ClipboardUtil.copy(text);
    console.info('[PoemContent] copied poem=' + this.poemParam.n);
  }

  private toggleFav(): void {
    let ctx: Context = this.uiContext.getHostContext() as Context;
    if (this.isFav) {
      FavoritesUtil.remove(ctx, 'poem', this.poemParam.n);
      this.isFav = false;
      this.uiContext.getPromptAction().showToast({ message: '已取消收藏', duration: 1000 });
    } else {
      let item: FavoriteItem = new FavoriteItem();
      item.type = 'poem';
      item.title = this.poemParam.n;
      item.subtitle = this.poetName + ' \u00B7 ' + this.poemParam.d;
      item.data = JSON.stringify(this.poemParam);
      FavoritesUtil.add(ctx, item);
      this.isFav = true;
      this.uiContext.getPromptAction().showToast({ message: '已收藏', duration: 1000 });
    }
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          Text(this.poemParam.n)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .width('100%')
            .textAlign(TextAlign.Center)

          if (this.poetName) {
            Text(this.poetName + (this.poemParam.d ? ' \u00B7 ' + this.poemParam.d : ''))
              .fontSize(14)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ top: 8 })
              .width('100%')
              .textAlign(TextAlign.Center)
          }

          if (this.poemParam.f) {
            Text(this.poemParam.f)
              .fontSize(12)
              .fontColor($r('app.color.poetry_green'))
              .backgroundColor($r('app.color.poetry_green') + '18')
              .borderRadius(8)
              .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              .margin({ top: 8 })
          }

          Text(this.poemParam.c)
            .fontSize(16)
            .fontColor($r('app.color.secondary_text'))
            .lineHeight(30)
            .width('100%')
            .margin({ top: 20 })
            .padding({ left: 8, right: 8 })

          Row({ space: 12 }) {
            Text(this.isFav ? '\u2665' : '\u2661')
              .fontSize(14)
              .fontColor(this.isFav ? $r('app.color.danger_red') : $r('app.color.poetry_green'))
              .backgroundColor(this.isFav ? $r('app.color.danger_red') + '18' : $r('app.color.poetry_green') + '18')
              .borderRadius(16)
              .padding({ left: 20, right: 20, top: 8, bottom: 8 })
              .onClick(() => {
                this.toggleFav();
              })

            Text('复制')
              .fontSize(14)
              .fontColor('#ffffff')
              .backgroundColor($r('app.color.poetry_green'))
              .borderRadius(16)
              .padding({ left: 24, right: 24, top: 8, bottom: 8 })
              .onClick(() => {
                this.copyPoem();
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 24 })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 24 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
