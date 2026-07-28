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
import { shareImageViaPanel } from '../common/utils/ShareImageUtil';
import { KeywordUtil } from '../common/utils/KeywordUtil';
import { FontUtil } from '../common/utils/FontUtil';

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

  applyTemplate(index: number, tpl: TemplateInfo, textSize: number, titleSize: number[], lineHeight: number): void {
    let ctrl: MarkdownController = this.get(index);
    let isDark: boolean = this.isDarkColor(tpl.bgColor);
    let ts: [number, number, number, number, number, number] = [
      titleSize[0], titleSize[1], titleSize[2], titleSize[3], titleSize[4], titleSize[5]
    ];
    ctrl
      .setTitleColor(tpl.headerColor)
      .setTitleSize(ts)
      .setTitleFontWeight(FontWeight.Bold)
      .setTextColor(tpl.textColor)
      .setTextSize(textSize)
      .setTextLineHeight(lineHeight)
      .setQuoteTextColor(tpl.textColor)
      .setQuoteBorderColor(tpl.quoteBorderColor)
      .setQuoteBackgroundColor(tpl.quoteBgColor)
      .setQuoteBorderRadius(6)
      .setQuoteBorderWidth(2)
      .setInlineCodeColor(tpl.accentColor)
      .setInlineCodeBackgroundColor(tpl.highlightBgColor || tpl.codeBgColor)
      .setInlineCodeBackgroundRadius(3)
      .setCodeBlockTheme(isDark ? 'dark' : 'light')
      .setCodeBlockBorderRadius(6)
      .setUlPointColor(tpl.accentColor)
      .setLineColor(tpl.accentColor)
      .setHyperlinkTextColor(tpl.accentColor)
      .setBlockSpacing(6);
    FontUtil.applyFonts(ctrl, tpl);
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
  @State highlightWords: string[] = [];
  @State isExtractingKeywords: boolean = false;
  @State customKeyword: string = '';
  @State cardWidth: number = 360;
  @State cardHeights: number[] = [];
  @State dynamicTextSize: number = 18;
  @State dynamicTitleSize: number[] = [28, 24, 20, 18, 16, 15];
  @State dynamicLineHeight: number = 28;
  @State dynamicPaddingLeft: number = 28;
  @State dynamicPaddingRight: number = 28;
  @State dynamicPaddingTop: number = 24;
  @State dynamicPaddingBottom: number = 24;
  @State dynamicMinCardHeight: number = 260;
  private baseCardWidth: number = 360;
  private readonly maxInputLength: number = 1000;
  private templates: TemplateInfo[] = Md2PngTemplates.getAll();
  private controllerStore: MdControllerStore = new MdControllerStore();
  private canvasStore: MdCanvasStore = new MdCanvasStore();
  private swiperController: SwiperController = new SwiperController();
  private regenerateTimer: number = -1;
  private readonly markdownExample: string = '# 欢迎使用文字转图片\n\n输入 **Markdown** 或普通文本，选择喜欢的模板，一键生成精美图片！\n\n## 功能特点\n\n- 支持多种精美模板\n- 支持Markdown语法\n- 一键保存到相册\n\n> 让文字更有表现力\n\n`代码片段` 也能高亮显示';
  private readonly textExample: string = '今天天气真好，阳光明媚，微风不燥。\n出门走走，看花开花落，心情格外舒畅。\n把生活里的美好，藏进最平凡的句子。';

  aboutToAppear(): void {
    this.inputText = '';
    this.currentAccentColor = this.templates[this.currentTemplateIndex].accentColor;
    FontUtil.registerAll(this.getUIContext());
    this.initAllControllers();
    this.calcCardSize();
    let heights: number[] = [];
    for (let i: number = 0; i < this.templates.length; i++) {
      heights.push(this.dynamicMinCardHeight);
    }
    this.cardHeights = heights;
  }

  private initAllControllers(): void {
    for (let i = 0; i < this.templates.length; i++) {
      this.controllerStore.applyTemplate(i, this.templates[i], this.dynamicTextSize, this.dynamicTitleSize, this.dynamicLineHeight);
    }
  }

  private calcCardSize(): void {
    try {
      let disp: display.Display = display.getDefaultDisplaySync();
      let density: number = disp.densityPixels;
      this.baseCardWidth = Math.floor(disp.width / density) - 32;
    } catch (e) {
      this.baseCardWidth = 328;
    }
    this.cardWidth = this.baseCardWidth;
  }

  private getKeywordTopN(): number {
    let len: number = this.inputText.length;
    if (len <= 50) {
      return 2;
    } else if (len <= 200) {
      return 3;
    } else if (len <= 500) {
      return 5;
    } else {
      return 7;
    }
  }

  private calcDynamicStyle(): void {
    let len: number = this.inputText.length;
    if (len <= 30) {
      this.dynamicTextSize = 20;
      this.dynamicTitleSize = [32, 28, 24, 22, 20, 18];
      this.dynamicLineHeight = 32;
      this.dynamicPaddingLeft = 32;
      this.dynamicPaddingRight = 32;
      this.dynamicPaddingTop = 28;
      this.dynamicPaddingBottom = 28;
      this.cardWidth = Math.min(this.baseCardWidth, 280);
      this.dynamicMinCardHeight = Math.max(this.cardWidth + 40, 320);
    } else if (len <= 80) {
      this.dynamicTextSize = 19;
      this.dynamicTitleSize = [30, 26, 22, 20, 18, 16];
      this.dynamicLineHeight = 30;
      this.dynamicPaddingLeft = 30;
      this.dynamicPaddingRight = 30;
      this.dynamicPaddingTop = 26;
      this.dynamicPaddingBottom = 26;
      this.cardWidth = Math.min(this.baseCardWidth, 300);
      this.dynamicMinCardHeight = Math.max(Math.floor(this.cardWidth * 0.9), 280);
    } else if (len <= 200) {
      this.dynamicTextSize = 18;
      this.dynamicTitleSize = [28, 24, 20, 18, 16, 15];
      this.dynamicLineHeight = 28;
      this.dynamicPaddingLeft = 28;
      this.dynamicPaddingRight = 28;
      this.dynamicPaddingTop = 24;
      this.dynamicPaddingBottom = 24;
      this.cardWidth = Math.min(this.baseCardWidth, 320);
      this.dynamicMinCardHeight = Math.max(Math.floor(this.cardWidth * 0.8), 260);
    } else if (len <= 500) {
      this.dynamicTextSize = 16;
      this.dynamicTitleSize = [24, 21, 18, 16, 14, 13];
      this.dynamicLineHeight = 26;
      this.dynamicPaddingLeft = 24;
      this.dynamicPaddingRight = 24;
      this.dynamicPaddingTop = 20;
      this.dynamicPaddingBottom = 20;
      this.cardWidth = this.baseCardWidth;
      this.dynamicMinCardHeight = Math.max(Math.floor(this.cardWidth * 0.7), 240);
    } else {
      this.dynamicTextSize = 15;
      this.dynamicTitleSize = [22, 19, 17, 15, 13, 12];
      this.dynamicLineHeight = 24;
      this.dynamicPaddingLeft = 22;
      this.dynamicPaddingRight = 22;
      this.dynamicPaddingTop = 18;
      this.dynamicPaddingBottom = 18;
      this.cardWidth = this.baseCardWidth;
      this.dynamicMinCardHeight = 220;
    }
  }

  private getCardHeight(index: number): number {
    if (index >= 0 && index < this.cardHeights.length) {
      return this.cardHeights[index];
    }
    return this.dynamicMinCardHeight;
  }

  private getMaxCardHeight(): number {
    let maxH: number = this.dynamicMinCardHeight;
    for (let i = 0; i < this.cardHeights.length; i++) {
      if (this.cardHeights[i] > maxH) {
        maxH = this.cardHeights[i];
      }
    }
    return maxH;
  }

  private async pasteFromClipboard(): Promise<void> {
    try {
      let systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      let pasteData: pasteboard.PasteData = await systemPasteboard.getData();
      if (pasteData.getPrimaryMimeType() === pasteboard.MIMETYPE_TEXT_PLAIN) {
        let text: string = pasteData.getPrimaryText();
        if (text) {
          if (text.length > this.maxInputLength) {
            text = text.substring(0, this.maxInputLength);
            this.getUIContext().getPromptAction().showToast({ message: '已粘贴（超出 ' + this.maxInputLength.toString() + ' 字符部分已截断）', duration: 2000 });
          } else {
            this.getUIContext().getPromptAction().showToast({ message: '已粘贴', duration: 1000 });
          }
          this.inputText = text;
        }
      }
    } catch (e) {
      console.error('[Md2Png] paste failed: ' + (e as BusinessError).message);
    }
  }

  private fillMarkdownExample(): void {
    this.inputText = this.markdownExample;
    this.scheduleRegenerate();
    this.getUIContext().getPromptAction().showToast({ message: '已填入 Markdown 示例', duration: 1000 });
  }

  private fillTextExample(): void {
    this.inputText = this.textExample;
    this.scheduleRegenerate();
    this.getUIContext().getPromptAction().showToast({ message: '已填入文本示例', duration: 1000 });
  }

  private scheduleRegenerate(): void {
    if (this.regenerateTimer !== -1) {
      clearTimeout(this.regenerateTimer);
    }
    this.regenerateTimer = setTimeout(() => {
      this.extractAndGenerate();
    }, 800);
  }

  private addCustomKeyword(): void {
    let kw: string = this.customKeyword.trim();
    if (!kw) {
      return;
    }
    if (this.highlightWords.includes(kw)) {
      this.getUIContext().getPromptAction().showToast({ message: '该词已在高亮列表中', duration: 1000 });
      this.customKeyword = '';
      return;
    }
    let newWords: string[] = [];
    for (let i = 0; i < this.highlightWords.length; i++) {
      newWords.push(this.highlightWords[i]);
    }
    newWords.push(kw);
    this.highlightWords = newWords;
    this.customKeyword = '';
    this.generateImage();
  }

  private removeKeyword(word: string): void {
    let newWords: string[] = [];
    for (let i = 0; i < this.highlightWords.length; i++) {
      if (this.highlightWords[i] !== word) {
        newWords.push(this.highlightWords[i]);
      }
    }
    this.highlightWords = newWords;
    this.generateImage();
  }

  private async regenerateImageOnly(): Promise<void> {
    if (!this.inputText || this.inputText.trim().length === 0) {
      this.generatedImageUri = '';
      return;
    }
    this.calcDynamicStyle();
    this.initAllControllers();
    if (this.highlightWords.length > 0) {
      this.highlightWords = [...this.highlightWords];
    }
    this.generateImage();
  }

  private async extractAndGenerate(): Promise<void> {
    if (!this.inputText || this.inputText.trim().length === 0) {
      this.highlightWords = [];
      this.generatedImageUri = '';
      return;
    }
    this.calcDynamicStyle();
    this.initAllControllers();
    this.isExtractingKeywords = true;
    try {
      let topN: number = this.getKeywordTopN();
      let keywords: string[] = await KeywordUtil.extractKeywords(this.inputText, topN);
      this.highlightWords = keywords;
    } catch (e) {
      this.highlightWords = [];
    }
    this.isExtractingKeywords = false;
    this.generateImage();
  }

  private async generateImage(): Promise<void> {
    if (!this.inputText || this.inputText.trim().length === 0) {
      this.generatedImageUri = '';
      return;
    }
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
        uiCtx.getPromptAction().showToast({ message: '已保存到相册', duration: 1000 });
      }
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[Md2Png] save failed: ' + err.message);
      this.getUIContext().getPromptAction().showToast({ message: '保存失败', duration: 2000 });
    }
  }

  private doShare(): void {
    if (!this.generatedImageUri) {
      return;
    }
    shareImageViaPanel(this.getUIContext(), this.generatedImageUri);
  }

  build() {
    Column() {
      this.InputSection()

      if (this.highlightWords.length > 0 || this.inputText.trim().length > 0) {
        this.HighlightWordsSection()
      }

      Column() {
        Scroll() {
          Column() {
            this.PreviewSwiper()
            this.ActionButtons()
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .scrollable(ScrollDirection.Vertical)
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16, bottom: 16 })
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
        Text('Markdown示例')
          .fontSize(12)
          .fontColor($r('app.color.idiom_blue'))
          .backgroundColor($r('app.color.idiom_blue') + '18')
          .borderRadius(8)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .margin({ right: 8 })
          .onClick(() => {
            this.fillMarkdownExample();
          })

        Text('文本示例')
          .fontSize(12)
          .fontColor($r('app.color.idiom_blue'))
          .backgroundColor($r('app.color.idiom_blue') + '18')
          .borderRadius(8)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .onClick(() => {
            this.fillTextExample();
          })
      }
      .width('100%')
      .margin({ bottom: 8 })

      Scroll() {
        TextArea({ text: $$this.inputText, placeholder: '输入Markdown或普通文本...' })
          .width('100%')
          .height(140)
          .fontSize(14)
          .maxLength(this.maxInputLength)
          .fontColor($r('app.color.primary_text'))
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .padding(12)
          .onChange((value: string) => {
            let text: string = value;
            if (text.length > this.maxInputLength) {
              text = text.substring(0, this.maxInputLength);
              this.getUIContext().getPromptAction()
                .showToast({ message: '最多输入 ' + this.maxInputLength.toString() + ' 字符', duration: 1500 });
            }
            this.inputText = text;
            this.scheduleRegenerate();
          })
      }
      .width('100%')
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      Row() {
        Blank()
        Text(this.inputText.length.toString() + ' / ' + this.maxInputLength.toString())
          .fontSize(12)
          .fontColor($r('app.color.tertiary_text'))
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  HighlightWordsSection() {
    Column() {
      Row() {
        Text('高亮词')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        if (this.isExtractingKeywords) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color($r('app.color.idiom_blue'))
            .margin({ left: 8 })
        }
        Blank()
        Text('点击 \u00D7 移除，手动添加新词')
          .fontSize(11)
          .fontColor($r('app.color.hint_text'))
      }
      .width('100%')
      .margin({ bottom: 8 })

      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.highlightWords, (word: string) => {
          Row() {
            Text(word)
              .fontSize(13)
              .fontColor(this.currentAccentColor)
              .fontWeight(FontWeight.Medium)
            Text(' \u00D7')
              .fontSize(14)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ left: 2 })
          }
          .backgroundColor(this.currentAccentColor + '18')
          .borderRadius(14)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .margin({ right: 6, bottom: 6 })
          .onClick(() => {
            this.removeKeyword(word);
          })
        }, (word: string) => word)

        Row() {
          TextInput({ placeholder: '添加高亮词', text: this.customKeyword })
            .fontSize(13)
            .fontColor($r('app.color.primary_text'))
            .placeholderColor($r('app.color.hint_text'))
            .backgroundColor(Color.Transparent)
            .padding(0)
            .layoutWeight(1)
            .height(28)
            .onChange((value: string) => {
              this.customKeyword = value;
            })
            .onSubmit(() => {
              this.addCustomKeyword();
            })
          Text('+')
            .fontSize(16)
            .fontColor($r('app.color.idiom_blue'))
            .fontWeight(FontWeight.Bold)
            .margin({ left: 4 })
            .onClick(() => {
              this.addCustomKeyword();
            })
        }
        .height(28)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(14)
        .padding({ left: 10, right: 10 })
        .margin({ right: 6, bottom: 6 })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.page_background'))
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
              Canvas(this.canvasStore.get(index))
                .width(this.cardWidth)
                .height(this.getCardHeight(index))
                .hitTestBehavior(HitTestMode.Transparent)
                .onReady(() => {
                  DecorPatternUtil.draw(this.canvasStore.get(index), this.cardWidth, this.getCardHeight(index), tpl.accentColor, tpl.decorPattern);
                })
                .onAreaChange((_oldValue: Area, newValue: Area) => {
                  let newW: number = newValue.width as number;
                  let newH: number = newValue.height as number;
                  let oldW: number = _oldValue.width as number;
                  let oldH: number = _oldValue.height as number;
                  if (Math.abs(newW - oldW) > 1 || Math.abs(newH - oldH) > 1) {
                    DecorPatternUtil.draw(this.canvasStore.get(index), newW, newH, tpl.accentColor, tpl.decorPattern);
                  }
                })

              Column() {
                Markdown({ controller: this.controllerStore.get(index), text: KeywordUtil.highlightText(this.inputText, this.highlightWords, tpl.highlightFont, tpl.accentColor) })
                  .width('100%')
              }
              .width('100%')
              .padding({ left: this.dynamicPaddingLeft, right: this.dynamicPaddingRight, top: this.dynamicPaddingTop, bottom: this.dynamicPaddingBottom })
              .onAreaChange((_oldValue: Area, newValue: Area) => {
                let contentH: number = newValue.height as number;
                if (contentH < this.dynamicMinCardHeight) {
                  contentH = this.dynamicMinCardHeight;
                }
                if (index >= 0 && index < this.cardHeights.length) {
                  if (Math.abs(this.cardHeights[index] - contentH) > 1) {
                    let newArr: number[] = this.cardHeights.slice();
                    newArr[index] = contentH;
                    this.cardHeights = newArr;
                  }
                }
              })
            }
            .width(this.cardWidth)
            .constraintSize({ minHeight: this.getCardHeight(index) })
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
        this.generatedImageUri = '';
        this.regenerateImageOnly();
      })
    }
    .width('100%')
  }

  @Builder
  ActionButtons() {
    Column() {
      Row() {
        Text('生成结果')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
      }
      .width('100%')
      .margin({ top: 16, bottom: 8 })
      .visibility(this.generatedImageUri ? Visibility.Visible : Visibility.Hidden)

      Image(this.generatedImageUri)
        .width('100%')
        .borderRadius(12)
        .objectFit(ImageFit.Contain)
        .backgroundColor($r('app.color.card_background'))
        .margin({ bottom: 8 })
        .visibility(this.generatedImageUri ? Visibility.Visible : Visibility.Hidden)

      Row({ space: 10 }) {
        Button('分享')
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
            this.doShare();
          })

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
      .width('100%')
      .margin({ top: 12 })
      .visibility(this.generatedImageUri ? Visibility.Visible : Visibility.Hidden)
    }
    .width('100%')
  }
}
