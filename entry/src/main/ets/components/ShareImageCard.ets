import { Markdown, MarkdownController } from '@luvi/lv-markdown-in';
import { generateShareImage, saveImageToAlbum, shareImageViaPanel } from '../common/utils/ShareImageUtil';
import { ShareTemplateInfo } from '../model/Md2PngModels';
import { BusinessError } from '@kit.BasicServicesKit';
import { display } from '@kit.ArkUI';
import { DecorPatternUtil } from '../common/utils/DecorPatternUtil';

@Component
export struct ShareImageCard {
  @Prop mdText: string = '';
  @Prop accentColor: string = '#3182ce';
  @Prop bgColor: string = '#ffffff';
  @Prop cardId: string = 'share_card';
  @Prop theme: ShareTemplateInfo | null = null;
  @State isGenerating: boolean = false;
  @State generatedImageUri: string = '';
  @State resolvedBgColor: string = '#ffffff';
  @State resolvedAccentColor: string = '#3182ce';
  @State cardWidth: number = 360;
  @State cardHeight: number = 640;
  @State decorPattern: string = '';
  private mdController: MarkdownController = new MarkdownController();
  private decorCanvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));

  aboutToAppear(): void {
    this.resolveTheme();
    this.applyStyle();
    this.calcCardSize();
  }

  private resolveTheme(): void {
    if (this.theme !== null) {
      this.resolvedBgColor = this.theme.bgColor;
      this.resolvedAccentColor = this.theme.accentColor;
      this.decorPattern = this.theme.decorPattern;
    } else {
      this.resolvedBgColor = this.bgColor;
      this.resolvedAccentColor = this.accentColor;
      this.decorPattern = '';
    }
  }

  private applyStyle(): void {
    let tpl: ShareTemplateInfo = this.theme !== null ? this.theme : this.buildFallbackTheme();
    let isDark: boolean = this.isDarkColor(tpl.bgColor);
    this.mdController
      .setTitleColor(tpl.headerColor)
      .setTitleSize([22, 18, 16, 14, 13, 12])
      .setTitleFontWeight(FontWeight.Bold)
      .setTextColor(tpl.textColor)
      .setTextSize(14)
      .setTextLineHeight(22)
      .setQuoteTextColor(tpl.textColor)
      .setQuoteBorderColor(tpl.quoteBorderColor)
      .setQuoteBackgroundColor(tpl.quoteBgColor)
      .setQuoteBorderRadius(8)
      .setQuoteBorderWidth(3)
      .setInlineCodeColor(tpl.accentColor)
      .setInlineCodeBackgroundColor(tpl.codeBgColor)
      .setInlineCodeBackgroundRadius(4)
      .setCodeBlockTheme(isDark ? 'dark' : 'light')
      .setCodeBlockBorderRadius(8)
      .setUlPointColor(tpl.accentColor)
      .setLineColor(tpl.accentColor)
      .setHyperlinkTextColor(tpl.accentColor)
      .setBlockSpacing(8);
  }

  private buildFallbackTheme(): ShareTemplateInfo {
    return new ShareTemplateInfo(
      this.accentColor, this.bgColor,
      this.isDarkColor(this.bgColor) ? '#ffffff' : '#2c3e50',
      this.isDarkColor(this.bgColor) ? '#ffffff' : '#1a365d',
      this.isDarkColor(this.bgColor) ? 'rgba(255,255,255,0.1)' : '#edf2f7',
      this.isDarkColor(this.bgColor) ? 'rgba(255,255,255,0.06)' : '#f7fafc',
      this.accentColor, this.accentColor, ''
    );
  }

  private isDarkColor(color: string): boolean {
    let c: string = color.toLowerCase();
    if (c.startsWith('#')) {
      let hex: string = c.substring(1);
      if (hex.length >= 6) {
        let r: number = parseInt(hex.substring(0, 2), 16);
        let g: number = parseInt(hex.substring(2, 4), 16);
        let b: number = parseInt(hex.substring(4, 6), 16);
        return (r * 299 + g * 587 + b * 114) / 1000 < 128;
      }
    }
    return false;
  }

  private calcCardSize(): void {
    try {
      let disp: display.Display = display.getDefaultDisplaySync();
      let density: number = disp.densityPixels;
      this.cardWidth = Math.floor(disp.width / density);
      this.cardHeight = Math.floor(disp.height / density);
    } catch (e) {
      this.cardWidth = 360;
      this.cardHeight = 780;
    }
  }

  async doGenerate(): Promise<void> {
    this.isGenerating = true;
    try {
      let uiCtx: UIContext = this.getUIContext();
      this.generatedImageUri = await generateShareImage(uiCtx, this.cardId, 'share');
      uiCtx.getPromptAction().showToast({ message: '图片已生成', duration: 1500 });
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[ShareCard] generate failed: ' + err.message);
      this.getUIContext().getPromptAction().showToast({ message: '生成失败', duration: 2000 });
    }
    this.isGenerating = false;
  }

  async doSave(): Promise<void> {
    if (!this.generatedImageUri) {
      return;
    }
    try {
      await saveImageToAlbum(this.getUIContext(), this.generatedImageUri, 'share');
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[ShareCard] save failed: ' + err.message);
      this.getUIContext().getPromptAction().showToast({ message: '保存失败', duration: 1500 });
    }
  }

  doShare(): void {
    if (!this.generatedImageUri) {
      return;
    }
    shareImageViaPanel(this.getUIContext(), this.generatedImageUri);
  }

  build() {
    Column() {
      Stack() {
        Column() {
          Column() {
            Markdown({ controller: this.mdController, text: this.mdText })
              .width('100%')
          }
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 20 })
        }
        .width(this.cardWidth)
        .height(this.cardHeight)
        .justifyContent(FlexAlign.Start)
        .padding({ top: 40, bottom: 40 })

        Canvas(this.decorCanvasCtx)
          .width(this.cardWidth)
          .height(this.cardHeight)
          .onReady(() => {
            DecorPatternUtil.draw(this.decorCanvasCtx, this.cardWidth, this.cardHeight, this.resolvedAccentColor, this.decorPattern);
          })
      }
      .width(this.cardWidth)
      .height(this.cardHeight)
      .backgroundColor(this.resolvedBgColor)
      .id(this.cardId)

      if (this.generatedImageUri) {
        Image(this.generatedImageUri)
          .width('100%')
          .borderRadius(12)
          .objectFit(ImageFit.Contain)
          .margin({ top: 12 })
      }

      Row({ space: 8 }) {
        Text(this.isGenerating ? '生成中...' : '生成图片')
          .fontSize(13)
          .fontColor('#ffffff')
          .backgroundColor(this.resolvedAccentColor)
          .borderRadius(16)
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .enabled(!this.isGenerating)
          .onClick(() => {
            this.doGenerate();
          })

        if (this.generatedImageUri) {
          Text('分享')
            .fontSize(13)
            .fontColor(this.resolvedAccentColor)
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: this.resolvedAccentColor, style: BorderStyle.Solid })
            .borderRadius(16)
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
            .onClick(() => {
              this.doShare();
            })

          Text('保存到相册')
            .fontSize(13)
            .fontColor(this.resolvedAccentColor)
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: this.resolvedAccentColor, style: BorderStyle.Solid })
            .borderRadius(16)
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
            .onClick(() => {
              this.doSave();
            })
        }
      }
      .margin({ top: 12 })
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
  }
}
