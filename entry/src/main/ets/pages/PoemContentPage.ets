import { PoemItem, PoetItem, PoetDetail } from '../model/PoetryModels';
import { ClipboardUtil } from '../common/utils/ClipboardUtil';
import { FavoritesUtil, FavoriteItem, FavoriteAddResult } from '../common/utils/FavoritesUtil';
import { PoetryViewModel } from '../viewmodel/PoetryViewModel';
import { ShareImageCard } from '../components/ShareImageCard';
import { buildPoemMarkdown } from '../common/utils/ShareImageUtil';
import { Md2PngTemplates } from '../model/Md2PngModels';

class DynastyQueryParam {
  dynasty: string = '';
}

function buildPoemItem(param: Object): PoemItem {
  return PoetryViewModel.getInstance().parsePoemFromParam(param as Record<string, Object>);
}

@Builder
export function PoemContentPageBuilder(param: Object) {
  NavDestination() {
    PoemContentContent({ poemParam: buildPoemItem(param) })
  }
  .title('诗词鉴赏')
  .hideTitleBar(false)
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
export struct PoemContentContent {
  @Prop poemParam: PoemItem = new PoemItem();
  @State poetName: string = '';
  @State isFav: boolean = false;
  @State showShareCard: boolean = false;
  @State shareMdText: string = '';
  @StorageLink('PoemFavStatus') @Watch('onFavStatusChange') favStatus: boolean = false;
  private uiContext: UIContext = this.getUIContext();
  private viewModel: PoetryViewModel = PoetryViewModel.getInstance();
  navPathStack: NavPathStack = AppStorage.get('AppNavPathStack') as NavPathStack;

  aboutToAppear(): void {
    this.poetName = this.poemParam.a || '';
    this.isFav = FavoritesUtil.isFavorite(this.uiContext.getHostContext() as Context, 'poem', this.poemParam.n);
    AppStorage.setOrCreate('PoemFavStatus', this.isFav);
    console.info('[PoemContent] poem=' + this.poemParam.n + ', poet=' + this.poetName);
  }

  onFavStatusChange(): void {
    this.isFav = FavoritesUtil.isFavorite(this.uiContext.getHostContext() as Context, 'poem', this.poemParam.n);
  }

  private onShareImage(): void {
    this.showShareCard = false;
    this.shareMdText = buildPoemMarkdown(this.poemParam);
    this.showShareCard = true;
  }

  private copyPoem(): void {
    let text: string = '\u3010' + this.poemParam.n + '\u3011' + this.poetName + '\n' + this.poemParam.c;
    ClipboardUtil.copy(text);
    this.uiContext.getPromptAction().showToast({ message: '已复制到剪贴板', duration: 1000 });
    console.info('[PoemContent] copied poem=' + this.poemParam.n);
  }

  // 点击诗人：跳转到该诗人的作品列表（诗人详情页）
  private onPoetTap(): void {
    if (!this.poetName) {
      return;
    }
    let poet: PoetItem | null = this.viewModel.getPoetByName(this.poetName);
    if (poet) {
      let detail: PoetDetail = this.viewModel.loadPoetDetail(
        this.uiContext.getHostContext() as Context, poet.n, poet.i, poet.d);
      this.navPathStack.pushPathByName('PoetryDetailPage', detail);
      console.info('[PoemContent] tap poet=' + this.poetName + ', poems=' + detail.poems.length.toString());
    } else {
      this.uiContext.getPromptAction().showToast({ message: '未找到诗人信息', duration: 1000 });
      console.warn('[PoemContent] poet not found: ' + this.poetName);
    }
  }

  // 点击朝代：跳转到诗词查询页并按该朝代筛选
  private onDynastyTap(): void {
    if (!this.poemParam.d) {
      return;
    }
    let queryParam: DynastyQueryParam = new DynastyQueryParam();
    queryParam.dynasty = this.poemParam.d;
    this.navPathStack.pushPathByName('PoetryQueryPage', queryParam);
    console.info('[PoemContent] tap dynasty=' + this.poemParam.d);
  }

  private toggleFav(): void {
    let ctx: Context = this.uiContext.getHostContext() as Context;
    if (this.isFav) {
      FavoritesUtil.remove(ctx, 'poem', this.poemParam.n);
      this.isFav = false;
      AppStorage.setOrCreate('PoemFavStatus', false);
      this.uiContext.getPromptAction().showToast({ message: '已取消收藏', duration: 1000 });
    } else {
      let item: FavoriteItem = new FavoriteItem();
      item.type = 'poem';
      item.title = this.poemParam.n;
      item.subtitle = this.poetName + ' \u00B7 ' + this.poemParam.d;
      item.data = JSON.stringify(this.poemParam);
      let res: FavoriteAddResult = FavoritesUtil.add(ctx, item);
      this.isFav = true;
      AppStorage.setOrCreate('PoemFavStatus', true);
      if (res.truncated) {
        this.uiContext.getPromptAction().showToast({ message: '收藏已达上限，最早一条已移除', duration: 2000 });
      } else {
        this.uiContext.getPromptAction().showToast({ message: '已收藏', duration: 1000 });
      }
    }
    FavoritesUtil.invalidateCache();
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

          if (this.poetName || this.poemParam.d) {
            Row({ space: 6 }) {
              if (this.poetName) {
                Text(this.poetName)
                  .fontSize(14)
                  .fontColor($r('app.color.poetry_green'))
                  .decoration({ type: TextDecorationType.Underline, color: $r('app.color.poetry_green') })
                  .onClick(() => {
                    this.onPoetTap();
                  })
              }
              if (this.poetName && this.poemParam.d) {
                Text('\u00B7')
                  .fontSize(14)
                  .fontColor($r('app.color.tertiary_text'))
              }
              if (this.poemParam.d) {
                Text(this.poemParam.d)
                  .fontSize(14)
                  .fontColor($r('app.color.poetry_green'))
                  .decoration({ type: TextDecorationType.Underline, color: $r('app.color.poetry_green') })
                  .onClick(() => {
                    this.onDynastyTap();
                  })
              }
            }
            .width('100%')
            .margin({ top: 8 })
            .justifyContent(FlexAlign.Center)
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

            Text('分享图片')
              .fontSize(14)
              .fontColor('#ffffff')
              .backgroundColor($r('app.color.poetry_green'))
              .borderRadius(16)
              .padding({ left: 20, right: 20, top: 8, bottom: 8 })
              .onClick(() => {
                this.onShareImage();
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 24 })

          if (this.showShareCard) {
            ShareImageCard({
              mdText: this.shareMdText,
              accentColor: '#6b8e6b',
              bgColor: '#fdf8f0',
              cardId: 'poem_share_card',
              theme: Md2PngTemplates.getPoetryTemplate(),
              autoShare: true,
              onAutoShared: () => {
                this.showShareCard = false;
              }
            })
              .position({ x: -10000, y: 0 })
          }
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
