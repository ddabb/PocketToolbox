import { Markdown, MarkdownController } from '@luvi/lv-markdown-in';
import { generateShareImage, saveImageToAlbum } from '../common/utils/ShareImageUtil';
import { BusinessError } from '@kit.BasicServicesKit';

@Component
export struct ShareImageCard {
  @Prop mdText: string = '';
  @Prop accentColor: string = '#3182ce';
  @Prop bgColor: string = '#ffffff';
  @Prop cardId: string = 'share_card';
  @State isGenerating: boolean = false;
  @State generatedImageUri: string = '';
  private mdController: MarkdownController = new MarkdownController();

  aboutToAppear(): void {
    this.applyStyle();
  }

  private applyStyle(): void {
    let isDark: boolean = this.isDarkColor(this.bgColor);
    let textColor: string = isDark ? '#ffffff' : '#2c3e50';
    let headerColor: string = isDark ? '#ffffff' : '#1a365d';
    this.mdController
      .setTitleColor(headerColor)
      .setTitleSize([24, 20, 17, 15, 14, 13])
      .setTitleFontWeight(FontWeight.Bold)
      .setTextColor(textColor)
      .setTextSize(15)
      .setTextLineHeight(24)
      .setQuoteTextColor(textColor)
      .setQuoteBorderColor(this.accentColor)
      .setQuoteBackgroundColor(isDark ? 'rgba(255,255,255,0.06)' : '#f7fafc')
      .setQuoteBorderRadius(8)
      .setQuoteBorderWidth(3)
      .setInlineCodeColor(this.accentColor)
      .setInlineCodeBackgroundColor(isDark ? 'rgba(255,255,255,0.1)' : '#edf2f7')
      .setInlineCodeBackgroundRadius(4)
      .setCodeBlockTheme(isDark ? 'dark' : 'light')
      .setCodeBlockBorderRadius(8)
      .setUlPointColor(this.accentColor)
      .setLineColor(this.accentColor)
      .setHyperlinkTextColor(this.accentColor)
      .setBlockSpacing(8);
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

  build() {
    Column() {
      Column() {
        Markdown({ controller: this.mdController, text: this.mdText })
          .width('100%')
      }
      .width('100%')
      .padding(20)
      .backgroundColor(this.bgColor)
      .borderRadius(16)
      .shadow({ radius: 8, color: this.accentColor + '18', offsetY: 4 })
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
          .backgroundColor(this.accentColor)
          .borderRadius(16)
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .enabled(!this.isGenerating)
          .onClick(() => {
            this.doGenerate();
          })

        if (this.generatedImageUri) {
          Text('保存')
            .fontSize(13)
            .fontColor(this.accentColor)
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: this.accentColor, style: BorderStyle.Solid })
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
