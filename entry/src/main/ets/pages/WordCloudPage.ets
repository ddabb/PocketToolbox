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
import { pasteboard } from '@kit.BasicServicesKit';

class CloudWordEntry {
  word: string = '';
  count: number = 1;
  custom: boolean = false;

  constructor(word: string, count: number, custom: boolean) {
    this.word = word;
    this.count = count;
    this.custom = custom;
  }
}

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
  @State cloudWords: CloudWordEntry[] = [];
  @State placedWords: PlacedWord[] = [];
  @State currentPaletteIndex: number = 0;
  @State currentFontIndex: number = 0;
  @State isGenerating: boolean = false;
  @State isExtracting: boolean = false;
  @State canvasSize: number = 360;
  @State canvasPixelSize: number = 720;
  @State generatedCachePath: string = '';
  @State progressText: string = '';
  @State customWord: string = '';
  @State customCount: string = '1';
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
      this.canvasSize = Math.min(screenWidth - 32, 400);
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

          Button(this.isExtracting ? '分词中...' : '提取词语')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .backgroundColor('#2563eb')
            .borderRadius(20)
            .height(36)
            .enabled(!this.isExtracting)
            .onClick(() => {
              this.extractWords();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })
        .justifyContent(FlexAlign.Start)

        if (this.cloudWords.length > 0 || this.isExtracting) {
          this.WordsEditorSection()
        }

        if (this.cloudWords.length > 0) {
          Row({ space: 8 }) {
            Button(this.isGenerating ? this.progressText : '生成词云')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .backgroundColor('#2563eb')
              .borderRadius(20)
              .height(36)
              .enabled(!this.isGenerating)
              .layoutWeight(1)
              .onClick(() => {
                this.generateWordCloud();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8 })
        }

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
  WordsEditorSection() {
    Column() {
      Row() {
        Text('参与词语')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        if (this.isExtracting) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color($r('app.color.idiom_blue'))
            .margin({ left: 8 })
        }
        Blank()
        Text('点击 × 移除，手动添加新词')
          .fontSize(11)
          .fontColor($r('app.color.hint_text'))
      }
      .width('100%')
      .margin({ bottom: 8 })

      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.cloudWords, (entry: CloudWordEntry, index: number) => {
          Row() {
            Text(entry.word)
              .fontSize(13)
              .fontColor(this.getAccentColor())
              .fontWeight(FontWeight.Medium)
            if (entry.count > 1) {
              Text('×' + entry.count.toString())
                .fontSize(10)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ left: 2 })
            }
            Text(' ×')
              .fontSize(12)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ left: 2 })
          }
          .backgroundColor(this.getAccentColor() + '14')
          .borderRadius(14)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .margin({ right: 6, bottom: 6 })
          .onClick(() => {
            this.removeWord(entry.word);
          })
        }, (entry: CloudWordEntry, index: number) => entry.word + '_' + entry.count.toString())

        Row() {
          TextInput({ placeholder: '词语', text: this.customWord })
            .fontSize(13)
            .fontColor($r('app.color.primary_text'))
            .placeholderColor($r('app.color.hint_text'))
            .backgroundColor(Color.Transparent)
            .padding(0)
            .layoutWeight(1)
            .height(28)
            .maxLength(10)
            .onChange((value: string) => {
              this.customWord = value;
            })
            .onSubmit(() => {
              this.addCustomWord();
            })
          Text('×')
            .fontSize(13)
            .fontColor($r('app.color.idiom_blue'))
            .fontWeight(FontWeight.Medium)
            .margin({ left: 4, right: 4 })
          TextInput({ placeholder: '权重', text: this.customCount })
            .fontSize(13)
            .fontColor($r('app.color.primary_text'))
            .placeholderColor($r('app.color.hint_text'))
            .backgroundColor(Color.Transparent)
            .padding(0)
            .width(32)
            .height(28)
            .type(InputType.Number)
            .inputFilter('^[0-9]*$', () => { return 0; })
            .maxLength(2)
            .onChange((value: string) => {
              this.customCount = value;
            })
          Text('+')
            .fontSize(16)
            .fontColor($r('app.color.idiom_blue'))
            .fontWeight(FontWeight.Bold)
            .margin({ left: 4 })
            .onClick(() => {
              this.addCustomWord();
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

  private async extractWords(): Promise<void> {
    if (!this.inputText || this.inputText.trim().length === 0) {
      this.uiContext.getPromptAction().showToast({ message: '请先输入或粘贴文本', duration: 1500 });
      return;
    }
    this.isExtracting = true;
    try {
      let wordEntries: Array<WordCountEntry> = await KeywordUtil.extractAllWords(this.inputText);
      if (wordEntries.length === 0) {
        this.uiContext.getPromptAction().showToast({ message: '未提取到有效词语', duration: 2000 });
        this.isExtracting = false;
        return;
      }
      let maxWords: number = this.MAX_WORDS;
      let entries: Array<WordCountEntry> = wordEntries.length > maxWords ? wordEntries.slice(0, maxWords) : wordEntries;
      let newWords: CloudWordEntry[] = [];
      for (let i: number = 0; i < entries.length; i++) {
        newWords.push(new CloudWordEntry(entries[i].word, entries[i].count, false));
      }
      this.cloudWords = newWords;
    } catch (e) {
      this.uiContext.getPromptAction().showToast({ message: '分词失败', duration: 2000 });
    }
    this.isExtracting = false;
  }

  private removeWord(word: string): void {
    let newWords: CloudWordEntry[] = [];
    for (let i: number = 0; i < this.cloudWords.length; i++) {
      if (this.cloudWords[i].word !== word) {
        newWords.push(this.cloudWords[i]);
      }
    }
    this.cloudWords = newWords;
  }

  private addCustomWord(): void {
    let w: string = this.customWord.trim();
    if (!w) {
      return;
    }
    let c: number = parseInt(this.customCount);
    if (isNaN(c) || c < 1) {
      c = 1;
    }
    for (let i: number = 0; i < this.cloudWords.length; i++) {
      if (this.cloudWords[i].word === w) {
        let newWords: CloudWordEntry[] = [];
        for (let j: number = 0; j < this.cloudWords.length; j++) {
          if (this.cloudWords[j].word === w) {
            newWords.push(new CloudWordEntry(w, this.cloudWords[j].count + c, this.cloudWords[j].custom));
          } else {
            newWords.push(this.cloudWords[j]);
          }
        }
        this.cloudWords = newWords;
        this.customWord = '';
        this.customCount = '1';
        this.uiContext.getPromptAction().showToast({ message: '已累加权重', duration: 1000 });
        return;
      }
    }
    let newWords: CloudWordEntry[] = [];
    for (let i: number = 0; i < this.cloudWords.length; i++) {
      newWords.push(this.cloudWords[i]);
    }
    newWords.push(new CloudWordEntry(w, c, true));
    this.cloudWords = newWords;
    this.customWord = '';
    this.customCount = '1';
  }

  private async generateWordCloud(): Promise<void> {
    if (this.cloudWords.length === 0) {
      this.uiContext.getPromptAction().showToast({ message: '请先提取或添加词语', duration: 1500 });
      return;
    }
    this.isGenerating = true;
    this.generatedCachePath = '';
    this.progressText = '正在布局...';

    try {
      let weightedItems: WeightedItem[] = [];
      for (let i: number = 0; i < this.cloudWords.length; i++) {
        let item: WeightedItem = new WeightedItem();
        item.text = this.cloudWords[i].word;
        item.weight = this.cloudWords[i].count;
        item.tag = '';
        weightedItems.push(item);
      }

      FontScaler.scaleAll(weightedItems);
      this.lastWeightedItems = weightedItems;

      let fontName: string = this.fontNames[this.currentFontIndex];
      let inputs: PlaceInput[] = [];
      for (let i: number = 0; i < weightedItems.length; i++) {
        let pi: PlaceInput = new PlaceInput();
        pi.text = weightedItems[i].text;
        pi.size = weightedItems[i].fontSize;
        pi.weight = weightedItems[i].weight;
        pi.font = fontName;
        inputs.push(pi);
      }

      let placer: SpiralPlacer = new SpiralPlacer(this.canvasSize, this.canvasSize);
      let results: PlacedWord[] = placer.place(inputs);

      let palette: PaletteColor = this.palettes[this.currentPaletteIndex];
      for (let i: number = 0; i < results.length; i++) {
        if (!results[i].color || results[i].color.length === 0) {
          results[i].color = palette.colors[i % palette.colors.length];
        }
        results[i].font = fontName;
      }

      this.placedWords = results;
      this.progressText = '已生成 ' + results.length.toString() + ' 个词';
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
    for (let i: number = 0; i < this.placedWords.length; i++) {
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
    for (let i: number = 0; i < this.lastWeightedItems.length; i++) {
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
    for (let i: number = 0; i < results.length; i++) {
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
