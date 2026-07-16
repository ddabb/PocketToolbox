import { IdiomDetailItem } from '../model/IdiomModels';
import { ClipboardUtil } from '../common/utils/ClipboardUtil';
import { FavoritesUtil, FavoriteItem } from '../common/utils/FavoritesUtil';
import { ShareImageCard } from './ShareImageCard';
import { buildIdiomMarkdown } from '../common/utils/ShareImageUtil';

@CustomDialog
export struct DetailModal {
  controller: CustomDialogController;
  @State detailItem: IdiomDetailItem | null = null;
  @State isFav: boolean = false;
  @State showShareCard: boolean = false;
  @State shareMdText: string = '';
  private uiContext: UIContext = this.getUIContext();

  aboutToAppear(): void {
    if (this.detailItem) {
      this.isFav = FavoritesUtil.isFavorite(this.uiContext.getHostContext() as Context, 'idiom', this.detailItem!.word);
    }
  }

  private toggleFav(): void {
    if (!this.detailItem) {
      return;
    }
    let ctx: Context = this.uiContext.getHostContext() as Context;
    if (this.isFav) {
      FavoritesUtil.remove(ctx, 'idiom', this.detailItem!.word);
      this.isFav = false;
      this.uiContext.getPromptAction().showToast({ message: '已取消收藏', duration: 1000 });
    } else {
      let item: FavoriteItem = new FavoriteItem();
      item.type = 'idiom';
      item.title = this.detailItem!.word;
      item.subtitle = this.detailItem!.pinyin;
      item.data = JSON.stringify(this.detailItem);
      FavoritesUtil.add(ctx, item);
      this.isFav = true;
      this.uiContext.getPromptAction().showToast({ message: '已收藏', duration: 1000 });
    }
    FavoritesUtil.invalidateCache();
  }

  build() {
    Column() {
      Row() {
        Text()
          .width(1)
          .height(1)
        Blank()
        Text('\u2715')
        .fontSize(18)
        .fontColor($r('app.color.tertiary_text'))
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor($r('app.color.border_color'))
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.controller.close();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ right: 12, top: 12 })

      if (this.detailItem) {
        Scroll() {
          Column() {
            Text(this.detailItem!.word)
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
              .letterSpacing(4)
              .margin({ bottom: 4 })

            Text(this.detailItem!.pinyin)
              .fontSize(14)
              .fontColor($r('app.color.secondary_text'))
              .margin({ bottom: 16 })

            if (this.detailItem!.explanation) {
              Column() {
                Row() {
                  Text('释义')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.primary_text'))
                  Blank()
                  Text('复制')
                    .fontSize(12)
                    .fontColor($r('app.color.idiom_blue'))
                    .backgroundColor($r('app.color.idiom_blue') + '18')
                    .borderRadius(8)
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    .onClick(() => {
                      ClipboardUtil.copy(this.detailItem!.explanation);
                      this.uiContext.getPromptAction().showToast({ message: '已复制到剪贴板', duration: 1000 });
                    })
                }
                .width('100%')
                .margin({ bottom: 6 })
                Text(this.detailItem!.explanation)
                  .fontSize(14)
                  .fontColor($r('app.color.secondary_text'))
                  .lineHeight(24)
              }
              .width('100%')
              .margin({ bottom: 12 })
            }

            if (this.detailItem!.derivation) {
              Column() {
                Row() {
                  Text('出处')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.primary_text'))
                  Blank()
                  Text('复制')
                    .fontSize(12)
                    .fontColor($r('app.color.idiom_blue'))
                    .backgroundColor($r('app.color.idiom_blue') + '18')
                    .borderRadius(8)
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    .onClick(() => {
                      ClipboardUtil.copy(this.detailItem!.derivation);
                      this.uiContext.getPromptAction().showToast({ message: '已复制到剪贴板', duration: 1000 });
                    })
                }
                .width('100%')
                .margin({ bottom: 6 })
                Text(this.detailItem!.derivation)
                  .fontSize(14)
                  .fontColor($r('app.color.secondary_text'))
                  .lineHeight(24)
              }
              .width('100%')
              .margin({ bottom: 12 })
            }

            if (this.detailItem!.example) {
              Column() {
                Row() {
                  Text('例句')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.primary_text'))
                }
                .width('100%')
                .margin({ bottom: 6 })
                Text(this.detailItem!.example)
                  .fontSize(14)
                  .fontColor($r('app.color.secondary_text'))
                  .lineHeight(24)
              }
              .width('100%')
              .margin({ bottom: 12 })
            }

            Row({ space: 10 }) {
              Text(this.isFav ? '\u2665' : '\u2661')
                .fontSize(14)
                .fontColor(this.isFav ? $r('app.color.danger_red') : $r('app.color.secondary_text'))
                .backgroundColor(this.isFav ? $r('app.color.danger_red') + '18' : $r('app.color.border_color'))
                .borderRadius(12)
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .onClick(() => {
                  this.toggleFav();
                })

              Text('复制全部')
                .fontSize(14)
                .fontColor($r('app.color.secondary_text'))
                .backgroundColor($r('app.color.border_color'))
                .borderRadius(12)
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .onClick(() => {
                  let all: string = this.detailItem!.word + '\n' +
                    this.detailItem!.pinyin + '\n' +
                    '\u3010\u91CA\u4E49\u3011' + this.detailItem!.explanation + '\n' +
                    '\u3010\u51FA\u5904\u3011' + this.detailItem!.derivation;
                  if (this.detailItem!.example) {
                    all += '\n\u3010\u4F8B\u53E5\u3011' + this.detailItem!.example;
                  }
                  ClipboardUtil.copy(all);
                  this.uiContext.getPromptAction().showToast({ message: '已复制到剪贴板', duration: 1000 });
                })

              Text('图片')
                .fontSize(14)
                .fontColor('#ffffff')
                .backgroundColor($r('app.color.idiom_blue'))
                .borderRadius(12)
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .onClick(() => {
                  this.shareMdText = buildIdiomMarkdown(this.detailItem!);
                  this.showShareCard = !this.showShareCard;
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .margin({ top: 8 })

            if (this.showShareCard) {
              ShareImageCard({
                mdText: this.shareMdText,
                accentColor: '#3182ce',
                bgColor: '#ffffff',
                cardId: 'idiom_share_card'
              })
                .margin({ top: 12 })
            }
          }
          .padding({ left: 20, right: 20, bottom: 20 })
        }
        .scrollable(ScrollDirection.Vertical)
        .constraintSize({ maxHeight: '60%' })
      }
    }
    .width('85%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
    .shadow({ radius: 20, color: '#33000000', offsetY: 8 })
  }
}
