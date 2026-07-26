import { FavoriteItem, FavoritesUtil, FavoriteAddResult } from '../common/utils/FavoritesUtil';
import { PoemItem } from '../model/PoetryModels';
import { IdiomDetailItem } from '../model/IdiomModels';
import { XiehouyuItem } from '../model/XiehouyuModels';
import { ClipboardUtil } from '../common/utils/ClipboardUtil';
import { ShareImageCard } from './ShareImageCard';
import { buildPoemMarkdown, buildIdiomMarkdown, buildXiehouyuMarkdown } from '../common/utils/ShareImageUtil';
import { Md2PngTemplates, ShareTemplateInfo } from '../model/Md2PngModels';

@CustomDialog
export struct FavDetailModal {
  controller?: CustomDialogController;
  @State favItem: FavoriteItem | null = null;
  @State showShareCard: boolean = false;
  @State shareMdText: string = '';
  @State shareAccent: string = '';
  @State shareBg: string = '';
  @State shareTheme: ShareTemplateInfo | null = null;
  @State authorLine: string = '';
  @State poemData: PoemItem | null = null;
  @State idiomData: IdiomDetailItem | null = null;
  @State xiehouyuData: XiehouyuItem | null = null;
  private uiContext: UIContext = this.getUIContext();

  aboutToAppear(): void {
    if (!this.favItem) {
      return;
    }
    if (this.favItem!.type === 'poem') {
      try {
        this.poemData = JSON.parse(this.favItem!.data) as PoemItem;
        let line: string = '';
        if (this.poemData!.a) {
          line += this.poemData!.a;
        }
        if (this.poemData!.d) {
          line += ' \u00B7 ' + this.poemData!.d;
        }
        this.authorLine = line;
      } catch (e) {
        console.error('[FavModal] parse poem failed');
      }
    } else if (this.favItem!.type === 'idiom') {
      try {
        this.idiomData = JSON.parse(this.favItem!.data) as IdiomDetailItem;
      } catch (e) {
        console.error('[FavModal] parse idiom failed');
      }
    } else if (this.favItem!.type === 'xiehouyu') {
      try {
        this.xiehouyuData = JSON.parse(this.favItem!.data) as XiehouyuItem;
      } catch (e) {
        console.error('[FavModal] parse xiehouyu failed');
      }
    }
  }

  private onShareImage(): void {
    if (this.favItem!.type === 'poem' && this.poemData) {
      this.shareMdText = buildPoemMarkdown(this.poemData!);
      this.shareTheme = Md2PngTemplates.getPoetryTemplate();
      this.shareAccent = '#6b8e6b';
      this.shareBg = '#fdf8f0';
    } else if (this.favItem!.type === 'idiom' && this.idiomData) {
      this.shareMdText = buildIdiomMarkdown(this.idiomData!);
      this.shareTheme = Md2PngTemplates.getIdiomTemplate();
      this.shareAccent = '#9e2b25';
      this.shareBg = '#f6efe1';
    } else if (this.favItem!.type === 'xiehouyu' && this.xiehouyuData) {
      this.shareMdText = buildXiehouyuMarkdown(this.xiehouyuData!);
      this.shareTheme = Md2PngTemplates.getXiehouyuTemplate();
      this.shareAccent = '#e67e22';
      this.shareBg = '#fffbf0';
    } else {
      return;
    }
    this.showShareCard = true;
  }

  private copyAll(): void {
    let text: string = '';
    if (this.favItem!.type === 'poem' && this.poemData) {
      text = this.poemData!.n + '\n';
      if (this.poemData!.a) {
        text += this.poemData!.a;
      }
      if (this.poemData!.d) {
        text += ' \u00B7 ' + this.poemData!.d;
      }
      text += '\n' + this.poemData!.c;
    } else if (this.favItem!.type === 'idiom' && this.idiomData) {
      text = this.idiomData!.word + '\n' + this.idiomData!.pinyin + '\n';
      text += '【释义】' + this.idiomData!.explanation;
      if (this.idiomData!.derivation) {
        text += '\n【出处】' + this.idiomData!.derivation;
      }
      if (this.idiomData!.example) {
        text += '\n【例句】' + this.idiomData!.example;
      }
    } else if (this.favItem!.type === 'xiehouyu' && this.xiehouyuData) {
      text = this.xiehouyuData!.riddle + '——' + this.xiehouyuData!.answer;
    }
    if (text) {
      ClipboardUtil.copy(text);
      this.uiContext.getPromptAction().showToast({ message: '已复制到剪贴板', duration: 1000 });
    }
  }

  build() {
    Stack() {
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
              this.controller?.close();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: 12, top: 12 })

        if (this.favItem) {
          Scroll() {
            Column() {
              if (this.favItem!.type === 'poem' && this.poemData) {
                this.PoemContent()
              } else if (this.favItem!.type === 'idiom' && this.idiomData) {
                this.IdiomContent()
              } else if (this.favItem!.type === 'xiehouyu' && this.xiehouyuData) {
                this.XiehouyuContent()
              }

              Row({ space: 10 }) {
                Text('复制全部')
                  .fontSize(14)
                  .fontColor($r('app.color.secondary_text'))
                  .backgroundColor($r('app.color.border_color'))
                  .borderRadius(12)
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                  .onClick(() => {
                    this.copyAll();
                  })

                Text('分享图片')
                  .fontSize(14)
                  .fontColor('#ffffff')
                  .backgroundColor(this.favItem!.type === 'poem' ? $r('app.color.poetry_green') :
                  this.favItem!.type === 'idiom' ? $r('app.color.idiom_blue') : $r('app.color.idiom_orange'))
                  .borderRadius(12)
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                  .onClick(() => {
                    this.onShareImage();
                  })
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .margin({ top: 12 })

              if (this.showShareCard && this.shareTheme) {
                ShareImageCard({
                  mdText: this.shareMdText,
                  accentColor: this.shareAccent,
                  bgColor: this.shareBg,
                  cardId: 'fav_share_card',
                  theme: this.shareTheme!,
                  autoShare: true,
                  onAutoShared: () => {
                    this.showShareCard = false;
                  }
                })
                  .position({ x: -10000, y: 0 })
              }
            }
            .padding({ left: 20, right: 20, bottom: 20 })
          }
          .scrollable(ScrollDirection.Vertical)
          .constraintSize({ maxHeight: '60%' })
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        }
      }
      .width('85%')
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(20)
      .shadow({ radius: 20, color: '#33000000', offsetY: 8 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  PoemContent() {
    Column() {
      Text(this.poemData!.n)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .margin({ bottom: 4 })

      if (this.authorLine) {
        Text(this.authorLine)
          .fontSize(14)
          .fontColor($r('app.color.secondary_text'))
          .margin({ bottom: 4 })
      }

      if (this.poemData!.f) {
        Text(this.poemData!.f)
          .fontSize(12)
          .fontColor($r('app.color.poetry_green'))
          .backgroundColor($r('app.color.poetry_green') + '18')
          .borderRadius(8)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .margin({ bottom: 12 })
      }

      Text(this.poemData!.c)
        .fontSize(15)
        .fontColor($r('app.color.primary_text'))
        .lineHeight(26)
        .margin({ top: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  IdiomContent() {
    Column() {
      Text(this.idiomData!.word)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .letterSpacing(4)
        .margin({ bottom: 4 })

      Text(this.idiomData!.pinyin)
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))
        .margin({ bottom: 16 })

      if (this.idiomData!.explanation) {
        Column() {
          Text('释义')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .margin({ bottom: 6 })
          Text(this.idiomData!.explanation)
            .fontSize(14)
            .fontColor($r('app.color.secondary_text'))
            .lineHeight(24)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ bottom: 12 })
      }

      if (this.idiomData!.derivation) {
        Column() {
          Text('出处')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .margin({ bottom: 6 })
          Text(this.idiomData!.derivation)
            .fontSize(14)
            .fontColor($r('app.color.secondary_text'))
            .lineHeight(24)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ bottom: 12 })
      }

      if (this.idiomData!.example) {
        Column() {
          Text('例句')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .margin({ bottom: 6 })
          Text(this.idiomData!.example)
            .fontSize(14)
            .fontColor($r('app.color.secondary_text'))
            .lineHeight(24)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  XiehouyuContent() {
    Column() {
      Text('谜面')
        .fontSize(14)
        .fontColor($r('app.color.tertiary_text'))
        .margin({ bottom: 6 })

      Text(this.xiehouyuData!.riddle)
        .fontSize(20)
        .fontColor($r('app.color.primary_text'))
        .fontWeight(FontWeight.Bold)
        .textAlign(TextAlign.Center)
        .lineHeight(28)
        .width('100%')
        .margin({ bottom: 16 })

      Divider()
        .color($r('app.color.border_color'))
        .margin({ bottom: 16 })

      Text('谜底')
        .fontSize(14)
        .fontColor($r('app.color.tertiary_text'))
        .margin({ bottom: 6 })

      Text(this.xiehouyuData!.answer)
        .fontSize(22)
        .fontColor($r('app.color.idiom_orange'))
        .fontWeight(FontWeight.Bold)
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }
}
