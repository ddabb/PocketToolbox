import { TemplateInfo, Md2PngTemplates } from '../model/Md2PngModels';
import { image } from '@kit.ImageKit';
import { fileIo as fs, WriteOptions } from '@kit.CoreFileKit';
import { picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { Markdown, MarkdownController } from '@luvi/lv-markdown-in';

@Builder
export function Md2PngPageBuilder() {
  NavDestination() {
    Md2PngContent()
  }
  .title('文字转图片')
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct Md2PngContent {
  @State inputText: string = '';
  @State currentTemplateId: string = 'default';
  @State generatedImageUri: string = '';
  @State isGenerating: boolean = false;
  @State previewBgColor: string = '#ffffff';
  @State previewTextColor: string = '#2c3e50';
  @State previewAccentColor: string = '#3182ce';
  @State previewHeaderColor: string = '#1a365d';
  @State previewCodeBgColor: string = '#edf2f7';
  @State previewQuoteBgColor: string = '#f7fafc';
  @State previewQuoteBorderColor: string = '#3182ce';
  private templates: TemplateInfo[] = Md2PngTemplates.getAll();
  private mdController: MarkdownController = new MarkdownController();

  aboutToAppear(): void {
    this.inputText = '# 欢迎使用文字转图片\n\n输入 **Markdown** 或普通文本，选择喜欢的模板，一键生成精美图片！\n\n## 功能特点\n\n- 支持多种精美模板\n- 支持Markdown语法\n- 一键保存到相册\n\n> 让文字更有表现力\n\n`代码片段` 也能高亮显示';
    this.applyTemplate();
  }

  private applyTemplate(): void {
    let tpl: TemplateInfo = Md2PngTemplates.getById(this.currentTemplateId);
    this.previewBgColor = tpl.bgColor;
    this.previewTextColor = tpl.textColor;
    this.previewAccentColor = tpl.accentColor;
    this.previewHeaderColor = tpl.headerColor;
    this.previewCodeBgColor = tpl.codeBgColor;
    this.previewQuoteBgColor = tpl.quoteBgColor;
    this.previewQuoteBorderColor = tpl.quoteBorderColor;

    let isDark: boolean = this.isDarkTheme(tpl);
    this.mdController
      .setTitleColor(tpl.headerColor)
      .setTitleSize([24, 20, 17, 15, 14, 13])
      .setTitleFontWeight(FontWeight.Bold)
      .setTextColor(tpl.textColor)
      .setTextSize(15)
      .setTextLineHeight(24)
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

  private isDarkTheme(tpl: TemplateInfo): boolean {
    let bgColor: string = tpl.bgColor.toLowerCase();
    if (bgColor.startsWith('#')) {
      let hex: string = bgColor.substring(1);
      if (hex.length >= 6) {
        let r: number = parseInt(hex.substring(0, 2), 16);
        let g: number = parseInt(hex.substring(2, 4), 16);
        let b: number = parseInt(hex.substring(4, 6), 16);
        return (r * 299 + g * 587 + b * 114) / 1000 < 128;
      }
    }
    return false;
  }

  private async pasteFromClipboard(): Promise<void> {
    try {
      let systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      let pasteData: pasteboard.PasteData = await systemPasteboard.getData();
      if (pasteData.getPrimaryMimeType() === pasteboard.MIMETYPE_TEXT_PLAIN) {
        let text: string = pasteData.getPrimaryText();
        if (text) {
          this.inputText = text;
          this.getUIContext().getPromptAction().showToast({ message: '已粘贴', duration: 1000 });
        }
      }
    } catch (e) {
      console.error('[Md2Png] paste failed: ' + (e as BusinessError).message);
    }
  }

  private async generateImage(): Promise<void> {
    this.isGenerating = true;
    try {
      let uiCtx: UIContext = this.getUIContext();
      let snapshot = uiCtx.getComponentSnapshot();
      let pixelMap: image.PixelMap = await snapshot.get('md_preview_card');
      let packer: image.ImagePacker = image.createImagePacker();
      let packOpts: image.PackingOption = {
        format: 'image/png',
        quality: 100
      };
      let arrayBuffer: ArrayBuffer = await packer.packing(pixelMap, packOpts);
      let context: common.UIAbilityContext = uiCtx.getHostContext() as common.UIAbilityContext;
      let dir: string = context.cacheDir;
      let fileName: string = 'md2png_' + Date.now() + '.png';
      let filePath: string = dir + '/' + fileName;
      let file: fs.File = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, arrayBuffer);
      fs.closeSync(file);
      this.generatedImageUri = filePath;
      packer.release();
      pixelMap.release();
      uiCtx.getPromptAction().showToast({ message: '图片已生成，点击保存到相册', duration: 1500 });
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[Md2Png] generate failed: ' + err.message);
      this.getUIContext().getPromptAction().showToast({ message: '生成失败', duration: 2000 });
    }
    this.isGenerating = false;
  }

  private async saveToAlbum(): Promise<void> {
    if (!this.generatedImageUri) {
      return;
    }
    try {
      let docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      let saveOpts: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      saveOpts.newFileNames = ['md2png_' + Date.now() + '.png'];
      let uris: Array<string> = await docPicker.save(saveOpts);
      if (uris.length > 0) {
        let sourceFile: fs.File = fs.openSync(this.generatedImageUri, fs.OpenMode.READ_ONLY);
        let destFile: fs.File = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        let buf: ArrayBuffer = new ArrayBuffer(4096);
        let readLen: number = fs.readSync(sourceFile.fd, buf);
        while (readLen > 0) {
          let writeOpts: WriteOptions = { length: readLen };
          fs.writeSync(destFile.fd, buf, writeOpts);
          readLen = fs.readSync(sourceFile.fd, buf);
        }
        fs.closeSync(sourceFile);
        fs.closeSync(destFile);
        this.getUIContext().getPromptAction().showToast({ message: '已保存', duration: 1500 });
      }
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[Md2Png] save failed: ' + err.message);
      this.getUIContext().getPromptAction().showToast({ message: '保存失败', duration: 1500 });
    }
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          this.InputSection()
          this.TemplateSelector()
          this.PreviewSection()
          this.ActionButtons()
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollable(ScrollDirection.Vertical)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  InputSection() {
    Column() {
      Row() {
        Text('输入内容')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        Blank()
        Text('粘贴')
          .fontSize(12)
          .fontColor($r('app.color.idiom_blue'))
          .backgroundColor($r('app.color.idiom_blue') + '18')
          .borderRadius(8)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .onClick(() => {
            this.pasteFromClipboard();
          })
      }
      .width('100%')
      .margin({ bottom: 8 })

      TextArea({ text: $$this.inputText, placeholder: '输入Markdown或普通文本...' })
        .width('100%')
        .height(160)
        .fontSize(14)
        .fontColor($r('app.color.primary_text'))
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)
        .padding(12)
        .onChange((value: string) => {
          this.inputText = value;
        })
    }
    .width('100%')
    .margin({ top: 12 })
  }

  @Builder
  TemplateSelector() {
    Column() {
      Text('选择模板')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
        .margin({ bottom: 8, top: 16 })

      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.templates, (tpl: TemplateInfo) => {
            Column() {
              Column() {
                Text(tpl.icon)
                  .fontSize(18)
              }
              .width(44)
              .height(44)
              .borderRadius(12)
              .backgroundColor(tpl.bgColor)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .border({
                width: this.currentTemplateId === tpl.id ? 2 : 0,
                color: tpl.accentColor,
                style: BorderStyle.Solid
              })
              .margin({ bottom: 4 })
              Text(tpl.name)
                .fontSize(11)
                .fontColor(this.currentTemplateId === tpl.id ? tpl.accentColor : $r('app.color.tertiary_text'))
                .fontWeight(this.currentTemplateId === tpl.id ? FontWeight.Bold : FontWeight.Normal)
            }
            .onClick(() => {
              this.currentTemplateId = tpl.id;
              this.applyTemplate();
            })
          }, (tpl: TemplateInfo) => tpl.id)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  PreviewSection() {
    Column() {
      Text('预览效果')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
        .margin({ bottom: 8, top: 16 })

      this.RenderedCard()
    }
    .width('100%')
  }

  @Builder
  RenderedCard() {
    Column() {
      Markdown({ controller: this.mdController, text: this.inputText })
        .width('100%')
    }
    .width('100%')
    .padding(20)
    .backgroundColor(this.previewBgColor)
    .borderRadius(16)
    .shadow({ radius: 8, color: this.previewAccentColor + '18', offsetY: 4 })
    .id('md_preview_card')
  }

  @Builder
  ActionButtons() {
    Column() {
      if (this.generatedImageUri) {
        Row() {
          Text('生成结果')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
        }
        .width('100%')
        .margin({ top: 16, bottom: 8 })

        Image(this.generatedImageUri)
          .width('100%')
          .borderRadius(12)
          .objectFit(ImageFit.Contain)
          .backgroundColor($r('app.color.card_background'))
          .margin({ bottom: 8 })
      }

      Row({ space: 10 }) {
        Button(this.isGenerating ? '生成中...' : '生成图片')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .backgroundColor(this.previewAccentColor)
          .borderRadius(22)
          .height(44)
          .layoutWeight(1)
          .enabled(!this.isGenerating)
          .onClick(() => {
            this.generateImage();
          })

        if (this.generatedImageUri) {
          Button('保存到相册')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.previewAccentColor)
            .backgroundColor(Color.Transparent)
            .border({
              width: 1,
              color: this.previewAccentColor,
              style: BorderStyle.Solid
            })
            .borderRadius(22)
            .height(44)
            .layoutWeight(1)
            .onClick(() => {
              this.saveToAlbum();
            })
        }
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
  }
}
