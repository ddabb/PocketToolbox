import { TemplateInfo, Md2PngTemplates } from '../model/Md2PngModels';
import { image } from '@kit.ImageKit';
import { fileIo as fs, WriteOptions, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { Markdown, MarkdownController } from '@luvi/lv-markdown-in';
import { display } from '@kit.ArkUI';
import { DecorPatternUtil } from '../common/utils/DecorPatternUtil';

class MdCanvasStore {
  private contexts: CanvasRenderingContext2D[] = [];
  private drawn: Set<number> = new Set();

  get(index: number): CanvasRenderingContext2D {
    if (index >= this.contexts.length) {
      this.contexts.push(new CanvasRenderingContext2D(new RenderingContextSettings(true)));
    }
    return this.contexts[index];
  }

  markDrawn(index: number): void {
    this.drawn.add(index);
  }

  isDrawn(index: number): boolean {
    return this.drawn.has(index);
  }
}

class MdControllerStore {
  private controllers: MarkdownController[] = [];

  get(index: number): MarkdownController {
    if (index >= this.controllers.length) {
      let ctrl: MarkdownController = new MarkdownController();
      this.controllers.push(ctrl);
    }
    return this.controllers[index];
  }

  applyTemplate(index: number, tpl: TemplateInfo): void {
    let ctrl: MarkdownController = this.get(index);
    let isDark: boolean = this.isDarkColor(tpl.bgColor);
    ctrl
      .setTitleColor(tpl.headerColor)
      .setTitleSize([20, 17, 15, 13, 12, 11])
      .setTitleFontWeight(FontWeight.Bold)
      .setTextColor(tpl.textColor)
      .setTextSize(13)
      .setTextLineHeight(20)
      .setQuoteTextColor(tpl.textColor)
      .setQuoteBorderColor(tpl.quoteBorderColor)
      .setQuoteBackgroundColor(tpl.quoteBgColor)
      .setQuoteBorderRadius(6)
      .setQuoteBorderWidth(2)
      .setInlineCodeColor(tpl.accentColor)
      .setInlineCodeBackgroundColor(tpl.codeBgColor)
      .setInlineCodeBackgroundRadius(3)
      .setCodeBlockTheme(isDark ? 'dark' : 'light')
      .setCodeBlockBorderRadius(6)
      .setUlPointColor(tpl.accentColor)
      .setLineColor(tpl.accentColor)
      .setHyperlinkTextColor(tpl.accentColor)
      .setBlockSpacing(6);
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
}

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
  @State currentTemplateIndex: number = 0;
  @State generatedImageUri: string = '';
  @State isGenerating: boolean = false;
  @State currentAccentColor: string = '#3182ce';
  @State cardWidth: number = 360;
  @State cardHeight: number = 640;
  private templates: TemplateInfo[] = Md2PngTemplates.getAll();
  private controllerStore: MdControllerStore = new MdControllerStore();
  private canvasStore: MdCanvasStore = new MdCanvasStore();
  private swiperController: SwiperController = new SwiperController();

  aboutToAppear(): void {
    this.inputText = '# 欢迎使用文字转图片\n\n输入 **Markdown** 或普通文本，选择喜欢的模板，一键生成精美图片！\n\n## 功能特点\n\n- 支持多种精美模板\n- 支持Markdown语法\n- 一键保存到相册\n\n> 让文字更有表现力\n\n`代码片段` 也能高亮显示';
    this.currentAccentColor = this.templates[this.currentTemplateIndex].accentColor;
    this.initAllControllers();
    this.calcCardSize();
  }

  private initAllControllers(): void {
    for (let i = 0; i < this.templates.length; i++) {
      this.controllerStore.applyTemplate(i, this.templates[i]);
    }
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
      let tpl: TemplateInfo = this.templates[this.currentTemplateIndex];
      let cardId: string = 'md_card_' + tpl.id;
      let pixelMap: image.PixelMap = await snapshot.get(cardId);
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
      let uiCtx: UIContext = this.getUIContext();
      let context: common.UIAbilityContext = uiCtx.getHostContext() as common.UIAbilityContext;
      let helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      let srcFileUri: string = fileUri.getUriFromPath(this.generatedImageUri);
      let srcFileUris: Array<string> = [srcFileUri];
      let photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [
        {
          title: 'md2png_' + Date.now(),
          fileNameExtension: 'png',
          photoType: photoAccessHelper.PhotoType.IMAGE,
          subtype: photoAccessHelper.PhotoSubtype.DEFAULT,
        }
      ];
      let desFileUris: Array<string> = await helper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs);
      if (desFileUris.length > 0) {
        let sourceFile: fs.File = fs.openSync(this.generatedImageUri, fs.OpenMode.READ_ONLY);
        let destFile: fs.File = fs.openSync(desFileUris[0], fs.OpenMode.READ_WRITE);
        let buf: ArrayBuffer = new ArrayBuffer(4096);
        let readLen: number = fs.readSync(sourceFile.fd, buf);
        while (readLen > 0) {
          let writeOpts: WriteOptions = { length: readLen };
          fs.writeSync(destFile.fd, buf, writeOpts);
          readLen = fs.readSync(sourceFile.fd, buf);
        }
        fs.closeSync(sourceFile);
        fs.closeSync(destFile);
        uiCtx.getPromptAction().showToast({ message: '已保存到相册', duration: 1500 });
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
          this.PreviewSwiper()
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
        .height(140)
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
  PreviewSwiper() {
    Column() {
      Row() {
        Text('预览效果')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        Blank()
        Text('左右滑动切换模板')
          .fontSize(12)
          .fontColor($r('app.color.tertiary_text'))
      }
      .width('100%')
      .margin({ bottom: 8, top: 16 })

      Swiper(this.swiperController) {
        ForEach(this.templates, (tpl: TemplateInfo, index: number) => {
          Column() {
            Stack() {
              Column() {
                Markdown({ controller: this.controllerStore.get(index), text: this.inputText })
                  .width('100%')
              }
              .width('100%')
              .padding({ left: 20, right: 20, top: 16, bottom: 16 })

              Canvas(this.canvasStore.get(index))
                .width(this.cardWidth)
                .height(320)
                .onReady(() => {
                  if (!this.canvasStore.isDrawn(index)) {
                    DecorPatternUtil.draw(this.canvasStore.get(index), this.cardWidth, 320, tpl.accentColor, tpl.decorPattern);
                    this.canvasStore.markDrawn(index);
                  }
                })
            }
            .width(this.cardWidth)
            .height(320)
            .backgroundColor(tpl.bgColor)
            .borderRadius(16)
            .clip(true)
            .id('md_card_' + tpl.id)

            Row() {
              Stack() {
                Column()
                  .width(20)
                  .height(20)
                  .borderRadius(6)
                  .backgroundColor(tpl.bgColor)
                Column()
                  .width(6)
                  .height(6)
                  .borderRadius(3)
                  .backgroundColor(tpl.accentColor)
              }
              .margin({ right: 6 })
              Text(tpl.name)
                .fontSize(13)
                .fontColor(this.currentTemplateIndex === index ? tpl.accentColor : $r('app.color.tertiary_text'))
                .fontWeight(this.currentTemplateIndex === index ? FontWeight.Bold : FontWeight.Normal)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 10, bottom: 6 })
          }
        }, (tpl: TemplateInfo) => tpl.id)
      }
      .width('100%')
      .indicator(false)
      .displayMode(SwiperDisplayMode.STRETCH)
      .onChange((index: number) => {
        this.currentTemplateIndex = index;
        this.currentAccentColor = this.templates[index].accentColor;
      })
    }
    .width('100%')
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
          .backgroundColor(this.currentAccentColor)
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
            .fontColor(this.currentAccentColor)
            .backgroundColor(Color.Transparent)
            .border({
              width: 1,
              color: this.currentAccentColor,
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
