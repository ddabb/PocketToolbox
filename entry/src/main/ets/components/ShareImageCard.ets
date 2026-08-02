import { Markdown, MarkdownController } from '@luvi/lv-markdown-in';
import { shareImageViaPanel } from '../common/utils/ShareImageUtil';
import { ShareTemplateInfo } from '../model/Md2PngModels';
import { BusinessError } from '@kit.BasicServicesKit';
import { display } from '@kit.ArkUI';
import { DecorPatternUtil } from '../common/utils/DecorPatternUtil';
import { image } from '@kit.ImageKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';

@Component
export struct ShareImageCard {
  @Prop mdText: string = '';
  @Prop accentColor: string = '#3182ce';
  @Prop bgColor: string = '#ffffff';
  @Prop cardId: string = 'share_card';
  @Prop theme: ShareTemplateInfo | null = null;
  @Prop autoShare: boolean = false;
  onAutoShared: () => void = () => {};
  @State isGenerating: boolean = false;
  @State generatedImageUri: string = '';
  @State resolvedBgColor: string = '#ffffff';
  @State resolvedAccentColor: string = '#3182ce';
  @State cardWidth: number = 360;
  @State @Watch('onCardHeightChange') cardHeight: number = 0;
  @State decorPattern: string = '';
  private readonly minCardHeight: number = 320;
  private canvasReady: boolean = false;
  private cachedPixelMap: image.PixelMap | undefined = undefined;
  private mdController: MarkdownController = new MarkdownController();
  private decorCanvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));

  aboutToAppear(): void {
    this.resolveTheme();
    this.applyStyle();
    this.calcCardSize();
    if (this.autoShare) {
      setTimeout(() => {
        this.doGenerateAndShare();
      }, 700);
    }
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
    } catch (e) {
      this.cardWidth = 360;
    }
    if (this.cardHeight <= 0) {
      this.cardHeight = this.minCardHeight;
    }
  }

  private redrawDecor(): void {
    if (!this.canvasReady) {
      return;
    }
    DecorPatternUtil.draw(this.decorCanvasCtx, this.cardWidth, this.cardHeight, this.resolvedAccentColor, this.decorPattern);
  }

  private onCardHeightChange(): void {
    this.redrawDecor();
  }

  private async takeSnapshot(): Promise<image.PixelMap | undefined> {
    try {
      let uiCtx: UIContext = this.getUIContext();
      let snapshot = uiCtx.getComponentSnapshot();
      let pixelMap: image.PixelMap = await snapshot.get(this.cardId, { scale: 2, waitUntilRenderFinished: true });
      return pixelMap;
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[ShareCard] snapshot failed: ' + err.code + ' ' + err.message);
      return undefined;
    }
  }

  private async pixelMapToCache(uiContext: UIContext, pixelMap: image.PixelMap, prefix: string): Promise<string> {
    let context: common.UIAbilityContext = uiContext.getHostContext() as common.UIAbilityContext;
    let dir: string = context.cacheDir;
    let fileName: string = prefix + '_' + Date.now() + '.png';
    let filePath: string = dir + '/' + fileName;
    let file: fs.File = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    let packer: image.ImagePacker = image.createImagePacker();
    let packOpts: image.PackingOption = { format: 'image/png', quality: 100 };
    try {
      await packer.packToFile(pixelMap, file.fd, packOpts);
    } finally {
      fs.closeSync(file.fd);
      packer.release();
    }
    return filePath;
  }

  async doGenerate(): Promise<string> {
    this.isGenerating = true;
    let result: string = '';
    try {
      let pixelMap: image.PixelMap | undefined = await this.takeSnapshot();
      if (!pixelMap) {
        this.getUIContext().getPromptAction().showToast({ message: '截图失败', duration: 2000 });
        this.isGenerating = false;
        return '';
      }
      this.cachedPixelMap = pixelMap;
      let uiCtx: UIContext = this.getUIContext();
      result = await this.pixelMapToCache(uiCtx, pixelMap, 'share');
      this.generatedImageUri = result;
      if (!this.autoShare) {
        uiCtx.getPromptAction().showToast({ message: '图片已生成', duration: 1000 });
      }
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[ShareCard] generate failed: ' + err.code + ' ' + err.message);
      this.getUIContext().getPromptAction().showToast({ message: '生成失败', duration: 2000 });
    }
    this.isGenerating = false;
    return result;
  }

  async doGenerateAndShare(): Promise<void> {
    this.isGenerating = true;
    try {
      let cachePath: string = await this.doGenerate();
      if (cachePath) {
        shareImageViaPanel(this.getUIContext(), cachePath);
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '生成图片失败，无法分享', duration: 2000 });
      }
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[ShareCard] generateAndShare failed: ' + err.code + ' ' + err.message);
      this.getUIContext().getPromptAction().showToast({ message: '分享失败', duration: 2000 });
    }
    this.isGenerating = false;
    this.onAutoShared();
  }

  async doSave(): Promise<void> {
    if (!this.generatedImageUri) {
      this.getUIContext().getPromptAction().showToast({ message: '请先生成图片', duration: 1500 });
      return;
    }
    let uiCtx: UIContext = this.getUIContext();
    try {
      let context: common.UIAbilityContext = uiCtx.getHostContext() as common.UIAbilityContext;
      let helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      let srcFileUri: string = fileUri.getUriFromPath(this.generatedImageUri);
      let srcFileUris: Array<string> = [srcFileUri];
      let photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [{
        title: 'share_' + Date.now(),
        fileNameExtension: 'png',
        photoType: photoAccessHelper.PhotoType.IMAGE,
      }];
      let desFileUris: Array<string> = await helper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs);
      if (desFileUris.length > 0) {
        let srcFile: fs.File = await fs.open(this.generatedImageUri, fs.OpenMode.READ_ONLY);
        let desFile: fs.File = await fs.open(desFileUris[0], fs.OpenMode.WRITE_ONLY);
        await fs.copyFile(srcFile.fd, desFile.fd);
        await fs.close(srcFile);
        await fs.close(desFile.fd);
        uiCtx.getPromptAction().showToast({ message: '已保存到相册', duration: 1000 });
      }
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[ShareCard] save failed: ' + err.code + ' ' + err.message);
      uiCtx.getPromptAction().showToast({ message: '保存失败', duration: 2000 });
    }
  }

  async doSaveFromPixelMap(): Promise<void> {
    let pixelMap: image.PixelMap | undefined = this.cachedPixelMap;
    if (!pixelMap) {
      pixelMap = await this.takeSnapshot();
    }
    if (!pixelMap) {
      this.getUIContext().getPromptAction().showToast({ message: '截图失败', duration: 2000 });
      return;
    }
    let uiCtx: UIContext = this.getUIContext();
    try {
      let cachePath: string = await this.pixelMapToCache(uiCtx, pixelMap, 'save_tmp');
      let context: common.UIAbilityContext = uiCtx.getHostContext() as common.UIAbilityContext;
      let helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      let srcFileUri: string = fileUri.getUriFromPath(cachePath);
      let srcFileUris: Array<string> = [srcFileUri];
      let photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [{
        title: 'share_' + Date.now(),
        fileNameExtension: 'png',
        photoType: photoAccessHelper.PhotoType.IMAGE,
      }];
      let desFileUris: Array<string> = await helper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs);
      if (desFileUris.length > 0) {
        let srcFile: fs.File = await fs.open(cachePath, fs.OpenMode.READ_ONLY);
        let desFile: fs.File = await fs.open(desFileUris[0], fs.OpenMode.WRITE_ONLY);
        await fs.copyFile(srcFile.fd, desFile.fd);
        await fs.close(srcFile);
        await fs.close(desFile.fd);
        uiCtx.getPromptAction().showToast({ message: '已保存到相册', duration: 1000 });
      }
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[ShareCard] savePixelMap failed: ' + err.code + ' ' + err.message);
      uiCtx.getPromptAction().showToast({ message: '保存失败', duration: 2000 });
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
        Canvas(this.decorCanvasCtx)
          .width(this.cardWidth)
          .height(this.cardHeight)
          .hitTestBehavior(HitTestMode.Transparent)
          .onReady(() => {
            this.canvasReady = true;
            this.redrawDecor();
          })

        Column() {
          Column() {
            Markdown({ controller: this.mdController, text: this.mdText })
              .width('100%')
          }
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 20 })
        }
        .width(this.cardWidth)
        .padding({ top: 40, bottom: 40 })
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          let contentH: number = newValue.height as number;
          if (contentH < this.minCardHeight) {
            contentH = this.minCardHeight;
          }
          if (Math.abs(contentH - this.cardHeight) > 1) {
            this.cardHeight = contentH;
          }
        })
      }
      .width(this.cardWidth)
      .constraintSize({ minHeight: this.cardHeight })
      .backgroundColor(this.resolvedBgColor)
      .clip(true)
      .id(this.cardId)

      if (this.generatedImageUri) {
        Image(this.generatedImageUri)
          .width('100%')
          .borderRadius(12)
          .objectFit(ImageFit.Contain)
          .margin({ top: 12 })
      }

      if (!this.autoShare) {
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

            Text('保存')
              .fontSize(13)
              .fontColor('#ffffff')
              .backgroundColor(this.resolvedAccentColor)
              .borderRadius(16)
              .padding({ left: 16, right: 16, top: 6, bottom: 6 })
              .onClick(() => {
                this.doSaveFromPixelMap();
              })
          }
        }
        .margin({ top: 12 })
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
  }
}
