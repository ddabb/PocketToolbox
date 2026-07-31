import { KeywordUtil, WordCountEntry } from '../common/utils/KeywordUtil';
import { FontUtil } from '../common/utils/FontUtil';
import { ClipboardUtil } from '../common/utils/ClipboardUtil';
import { FontScaler, WeightedItem } from '../core/style/FontScaler';
import { Palette, PaletteColor } from '../core/style/Palette';
import { SpiralPlacer, PlaceInput } from '../core/layout/SpiralPlacer';
import { ImageExporter } from '../core/export/ImageExporter';
import { PlacedWord } from '../model/WordItem';
import { TemplateInfo, Md2PngTemplates } from '../model/Md2PngModels';
import { WordCloudView } from '../components/WordCloudView';
import { display } from '@kit.ArkUI';

@Builder
export function WordCloudPageBuilder() {
  NavDestination() {
    WordCloudContent()
  }
  .title('词云生成')
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct WordCloudContent {
  @State inputText: string = '';
  @State placedWords: PlacedWord[] = [];
  @State currentPaletteIndex: number = 0;
  @State currentFontIndex: number = 0;
  @State isGenerating: boolean = false;
  @State canvasSize: number = 360;
  @State canvasPixelSize: number = 720;
  @State generatedCachePath: string = '';
  @State progressText: string = '';
  private uiContext: UIContext = this.getUIContext();
  private palettes: PaletteColor[] = Palette.getAll();
  private templates: TemplateInfo[] = Md2PngTemplates.getAll();
  private lastWeightedItems: WeightedItem[] = [];
  private fontNames: string[] = [
    Md2PngTemplates.FONT_SMILEY, Md2PngTemplates.FONT_WENKAI,
    Md2PngTemplates.FONT_MASHAN, Md2PngTemplates.FONT_KUAILE,
    Md2PngTemplates.FONT_HUANGYOU, Md2PngTemplates.FONT_LONGCANG,
    Md2PngTemplates.FONT_MAOMAO, Md2PngTemplates.FONT_XIAOWEI,
    Md2PngTemplates.FONT_ZHIMANG
  ];
  private fontLabels: string[] = [
    '得意黑', '霞鹜文楷', '马善政', '站酷快乐',
    '站酷庆科黄油', '龙藏体', '刘建毛草', '站酷小薇', '志芒行'
  ];
  private readonly COMPONENT_ID: string = 'wordcloud_canvas';
  /** 单页最多放置词数：过多会导致螺旋布局耗时与过度拥挤 */
  private readonly MAX_WORDS: number = 180;

  aboutToAppear(): void {
    FontUtil.registerAll(this.uiContext);
    this.calcCanvasSize();
  }

  private calcCanvasSize(): void {
    try {
      let disp: display.Display = display.getDefaultDisplaySync();
      let density: number = disp.densityPixels;
      let screenWidth: number = Math.floor(disp.width / density);
      // 留出两侧各 16dp 边距；将画布尺寸限制在 400dp 以内保证紧凑美观
      this.canvasSize = Math.min(screenWidth - 32, 400);
      // 渲染像素 = 逻辑尺寸 × 密度，保证导出图清晰
      this.canvasPixelSize = this.canvasSize * Math.ceil(density);
    } catch (e) {
      this.canvasSize = 360;
      this.canvasPixelSize = 720;
    }
  }

  build() {
    Scroll() {
      Column() {
        Column() {
          TextArea({ placeholder: '粘贴文本内容，自动分词生成词云...', text: this.inputText })
            .width('100%')
            .height(120)
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
        .padding({ left: 16, right: 16, top: 12 })

        Row({ space: 8 }) {
          Button('粘贴')
            .fontSize(14)
            .fontColor(Color.White)
            .backgroundColor('#07c160')
            .borderRadius(20)
            .height(36)
            .onClick(() => {
              this.doPaste();
            })

          Button(this.isGenerating ? this.progressText : '生成词云')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .backgroundColor('#2563eb')
            .borderRadius(20)
            .height(36)
            .enabled(!this.isGenerating)
            .onClick(() => {
              this.generateWordCloud();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })
        .justifyContent(FlexAlign.Start)

        this.StyleSelector()

        Column() {
          Column() {
            if (this.placedWords.length > 0) {
              WordCloudView({
                placedWords: this.placedWords,
                bgColor: this.palettes[this.currentPaletteIndex].bgColor,
                paletteColors: this.palettes[this.currentPaletteIndex].colors,
                canvasPixelSize: this.canvasPixelSize
              })
                .width(this.canvasSize)
                .height(this.canvasSize)
            } else {
              this.EmptyPlaceholder()
            }
          }
          .width(this.canvasSize)
          .height(this.canvasSize)
          .id(this.COMPONENT_ID)
          .backgroundColor(this.palettes[this.currentPaletteIndex].bgColor)
          .borderRadius(12)
          .clip(true)
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12 })
        .alignItems(HorizontalAlign.Center)

        if (this.placedWords.length > 0) {
          Row({ space: 12 }) {
            Button('保存到相册')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getAccentColor())
              .backgroundColor(Color.Transparent)
              .border({ width: 1, color: this.getAccentColor(), style: BorderStyle.Solid })
              .borderRadius(22)
              .height(44)
              .layoutWeight(1)
              .onClick(() => {
                this.saveToAlbum();
              })

            Button('分享')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .backgroundColor(this.getAccentColor())
              .borderRadius(22)
              .height(44)
              .layoutWeight(1)
              .onClick(() => {
                this.shareImage();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12 })
        }

        Text(this.isGenerating ? this.progressText : '')
          .fontSize(12)
          .fontColor($r('app.color.tertiary_text'))
          .margin({ top: 8, bottom: 16 })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .scrollable(ScrollDirection.Vertical)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  EmptyPlaceholder() {
    Column() {
      Row() {
        Text('词')
          .fontSize(22)
          .fontColor($r('app.color.hint_text'))
          .opacity(0.3)
          .margin({ right: 6 })
        Text('云')
          .fontSize(28)
          .fontColor($r('app.color.hint_text'))
          .opacity(0.2)
          .margin({ right: 6 })
        Text('生')
          .fontSize(18)
          .fontColor($r('app.color.hint_text'))
          .opacity(0.25)
          .margin({ right: 6 })
        Text('成')
          .fontSize(24)
          .fontColor($r('app.color.hint_text'))
          .opacity(0.15)
      }
      .margin({ bottom: 12 })

      Text('粘贴文本后点击生成')
        .fontSize(13)
        .fontColor($r('app.color.tertiary_text'))
    }
    .width('100%')
    .height(this.canvasSize)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .border({
      width: 1,
      color: $r('app.color.hint_text'),
      style: BorderStyle.Dashed
    })
    .borderRadius(12)
    .opacity(0.5)
  }

  @Builder
  StyleSelector() {
    Column() {
      Text('配色方案')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
        .padding({ left: 16, bottom: 6 })

      Scroll() {
        Row() {
          ForEach(this.templates, (tpl: TemplateInfo, index: number) => {
            Column() {
              Column()
                .width(28)
                .height(28)
                .borderRadius(14)
                .backgroundColor(tpl.accentColor)
                .border({
                  width: this.currentPaletteIndex === index ? 2 : 0,
                  color: tpl.accentColor,
                  style: BorderStyle.Solid
                })
              Text(tpl.name)
                .fontSize(10)
                .fontColor(this.currentPaletteIndex === index ? tpl.accentColor : $r('app.color.tertiary_text'))
                .margin({ top: 3 })
            }
            .padding({ left: 6, right: 6 })
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.currentPaletteIndex = index;
              this.refreshColors();
            })
          }, (tpl: TemplateInfo) => tpl.id)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .width('100%')
      .padding({ left: 10, right: 10 })

      Text('字体')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
        .padding({ left: 16, top: 8, bottom: 6 })

      Scroll() {
        Row() {
          ForEach(this.fontLabels, (label: string, index: number) => {
            Column() {
              Text('云')
                .fontSize(20)
                .fontFamily(this.fontNames[index])
                .fontColor(this.currentFontIndex === index ? this.getAccentColor() : $r('app.color.primary_text'))
              Text(label)
                .fontSize(10)
                .fontColor(this.currentFontIndex === index ? this.getAccentColor() : $r('app.color.tertiary_text'))
                .margin({ top: 2 })
            }
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .borderRadius(8)
            .backgroundColor(this.currentFontIndex === index ? this.getAccentColor() + '18' : Color.Transparent)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.currentFontIndex = index;
              this.refreshFont();
            })
          }, (label: string) => label)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .width('100%')
      .padding({ left: 10, right: 10 })
    }
    .width('100%')
    .padding({ top: 8 })
  }

  private async doPaste(): Promise<void> {
    let text: string = await ClipboardUtil.paste();
    if (text && text.length > 0) {
      this.inputText = text;
    }
  }

  private async generateWordCloud(): Promise<void> {
    if (!this.inputText || this.inputText.trim().length === 0) {
      this.uiContext.getPromptAction().showToast({ message: '请先输入或粘贴文本', duration: 1500 });
      return;
    }
    this.isGenerating = true;
    this.generatedCachePath = '';
    this.progressText = '正在分词...';

    try {
      let wordEntries: Array<WordCountEntry> = await KeywordUtil.extractAllWords(this.inputText);
      if (wordEntries.length === 0) {
        this.uiContext.getPromptAction().showToast({ message: '未提取到有效词语，请输入更多文本', duration: 2000 });
        this.isGenerating = false;
        this.progressText = '';
        return;
      }

      let maxWords: number = this.MAX_WORDS;
      // 截断多余词语：词过多会导致螺旋布局耗时严重且整体拥挤
      let entries: Array<WordCountEntry> = wordEntries.length > maxWords ? wordEntries.slice(0, maxWords) : wordEntries;

      this.progressText = '正在布局...';

      // 步骤 1：根据词频生成 WeightedItem，并通过 FontScaler 完成字号映射
      let weightedItems: WeightedItem[] = [];
      for (let i = 0; i < entries.length; i++) {
        let item: WeightedItem = new WeightedItem();
        item.text = entries[i].word;
        item.weight = entries[i].count;
        item.tag = entries[i].tag;
        weightedItems.push(item);
      }

      FontScaler.scaleAll(weightedItems);
      this.lastWeightedItems = weightedItems;

      let fontName: string = this.fontNames[this.currentFontIndex];
      // 步骤 2：构建布局输入（此时字号已被 FontScaler 映射到紧凑区间）
      let inputs: PlaceInput[] = [];
      for (let i = 0; i < weightedItems.length; i++) {
        let pi: PlaceInput = new PlaceInput();
        pi.text = weightedItems[i].text;
        pi.size = weightedItems[i].fontSize;
        pi.weight = weightedItems[i].weight;
        pi.font = fontName;
        inputs.push(pi);
      }

      // 步骤 3：使用紧凑螺旋布局器完成排布
      let placer: SpiralPlacer = new SpiralPlacer(this.canvasSize, this.canvasSize);
      let results: PlacedWord[] = placer.place(inputs);

      // 步骤 4：为每个词语分色（按调色板顺序循环）
      let palette: PaletteColor = this.palettes[this.currentPaletteIndex];
      for (let i = 0; i < results.length; i++) {
        if (!results[i].color || results[i].color.length === 0) {
          results[i].color = palette.colors[i % palette.colors.length];
        }
        results[i].font = fontName;
      }

      this.placedWords = results;
      this.progressText = '已生成 ' + results.length + ' 个词';
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[WordCloud] generate failed: ' + err.code + ' ' + err.message);
      this.uiContext.getPromptAction().showToast({ message: '生成失败', duration: 2000 });
    }

    this.isGenerating = false;
  }

  private refreshColors(): void {
    if (this.placedWords.length === 0) {
      return;
    }
    let palette: PaletteColor = this.palettes[this.currentPaletteIndex];
    let newWords: PlacedWord[] = [];
    for (let i = 0; i < this.placedWords.length; i++) {
      let pw: PlacedWord = new PlacedWord();
      pw.text = this.placedWords[i].text;
      pw.x = this.placedWords[i].x;
      pw.y = this.placedWords[i].y;
      pw.size = this.placedWords[i].size;
      pw.color = palette.colors[i % palette.colors.length];
      pw.angle = this.placedWords[i].angle;
      pw.font = this.placedWords[i].font;
      pw.width = this.placedWords[i].width;
      pw.height = this.placedWords[i].height;
      newWords.push(pw);
    }
    this.placedWords = newWords;
  }

  private refreshFont(): void {
    if (this.lastWeightedItems.length === 0) {
      return;
    }
    let fontName: string = this.fontNames[this.currentFontIndex];
    let inputs: PlaceInput[] = [];
    for (let i = 0; i < this.lastWeightedItems.length; i++) {
      let pi: PlaceInput = new PlaceInput();
      pi.text = this.lastWeightedItems[i].text;
      pi.size = this.lastWeightedItems[i].fontSize;
      pi.weight = this.lastWeightedItems[i].weight;
      pi.font = fontName;
      inputs.push(pi);
    }

    let placer: SpiralPlacer = new SpiralPlacer(this.canvasSize, this.canvasSize);
    let results: PlacedWord[] = placer.place(inputs);

    let palette: PaletteColor = this.palettes[this.currentPaletteIndex];
    for (let i = 0; i < results.length; i++) {
      if (!results[i].color || results[i].color.length === 0) {
        results[i].color = palette.colors[i % palette.colors.length];
      }
      results[i].font = fontName;
    }

    this.placedWords = results;
  }

  private getAccentColor(): string {
    return this.templates[this.currentPaletteIndex].accentColor;
  }

  private async saveToAlbum(): Promise<void> {
    try {
      let cachePath: string = await ImageExporter.exportToCache(this.uiContext, this.COMPONENT_ID, 'wordcloud');
      this.generatedCachePath = cachePath;
      await ImageExporter.saveToAlbum(this.uiContext, cachePath, 'wordcloud');
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[WordCloud] save failed: ' + err.code + ' ' + err.message);
      this.uiContext.getPromptAction().showToast({ message: '保存失败', duration: 2000 });
    }
  }

  private async shareImage(): Promise<void> {
    try {
      let cachePath: string = this.generatedCachePath;
      if (!cachePath || cachePath.length === 0) {
        cachePath = await ImageExporter.exportToCache(this.uiContext, this.COMPONENT_ID, 'wordcloud');
        this.generatedCachePath = cachePath;
      }
      ImageExporter.share(this.uiContext, cachePath);
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[WordCloud] share failed: ' + err.code + ' ' + err.message);
      this.uiContext.getPromptAction().showToast({ message: '分享失败', duration: 2000 });
    }
  }
}
