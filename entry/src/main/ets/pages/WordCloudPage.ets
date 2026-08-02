import { KeywordUtil, WordCountEntry } from '../common/utils/KeywordUtil';
import { FontUtil } from '../common/utils/FontUtil';
import { FontScaler, WeightedItem } from '../core/style/FontScaler';
import { Palette, PaletteColor } from '../core/style/Palette';
import { ShapeDef } from '../core/layout/ShapeDef';
import { ImageExporter } from '../core/export/ImageExporter';
import { PlacedWord, CloudWord } from '../model/WordItem';
import { TemplateInfo, Md2PngTemplates } from '../model/Md2PngModels';
import { WordCloudView } from '../components/WordCloudView';
import { runPlacementAsync, WordInput, WordCloudInput } from '../core/layout/WordCloudTask';
import { display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { LengthMetricsUnit } from '@kit.ArkUI';

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
  @State cloudWords: CloudWord[] = [];
  @State placedWords: PlacedWord[] = [];
  @State currentPaletteIndex: number = 0;
  @State currentFontIndex: number = 0;
  @State currentShapeIndex: number = 0;
  @State isGenerating: boolean = false;
  @State isExtracting: boolean = false;
  @State canvasSize: number = 360;
  @State canvasPixelSize: number = 720;
  @State generatedCachePath: string = '';
  @State progressText: string = '';
  @State progressValue: number = 0;
  @State customWord: string = '';
  @State customCount: string = '1';
  @State directWordsText: string = '';
  @State showWordsDialog: boolean = false;
  private uiContext: UIContext = this.getUIContext();
  private palettes: PaletteColor[] = Palette.getAll();
  private templates: TemplateInfo[] = Md2PngTemplates.getAll();
  private lastWeightedItems: WeightedItem[] = [];
  private shapes: ShapeDef[] = ShapeDef.SHAPES;
  private shapeIcons: string[] = [
    'shape_circle', 'shape_cardioid', 'shape_star5', 'shape_diamond',
    'shape_triangle', 'shape_square', 'shape_pentagon', 'shape_hexagon',
    'shape_cross', 'shape_cloud', 'shape_oval', 'shape_leaf'
  ];
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
  private readonly LAYOUT_CANVAS_SIZE: number = 1000;

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
          Text('词语编辑')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .width('100%')
            .margin({ bottom: 8 })

          TextArea({ placeholder: '每行输入一个词语，可用冒号指定权重\n例如：\n创新:5\n科技:3\n未来', text: this.directWordsText })
            .width('100%')
            .height(140)
            .fontSize(14)
            .fontColor($r('app.color.primary_text'))
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)
            .padding(12)
            .onChange((value: string) => {
              this.directWordsText = value;
              this.parseDirectWords();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12 })

        Row({ space: 8 }) {
          Button('示例')
            .fontSize(14)
            .fontColor(Color.White)
            .backgroundColor('#07c160')
            .borderRadius(20)
            .height(36)
            .onClick(() => {
              this.loadExample();
            })

          Button('清空')
            .fontSize(14)
            .fontColor($r('app.color.tertiary_text'))
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(20)
            .height(36)
            .onClick(() => {
              this.clearWords();
            })

          Button(this.isExtracting ? '分词中...' : '从文本提取')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .backgroundColor('#2563eb')
            .borderRadius(20)
            .height(36)
            .enabled(!this.isExtracting)
            .onClick(() => {
              this.extractWordsToDirect();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })
        .justifyContent(FlexAlign.Start)

        if (this.cloudWords.length > 0) {
          Row() {
            Text('参与词语 (' + this.cloudWords.length.toString() + ')')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))
            Blank()
            Text('点击编辑 ›')
              .fontSize(12)
              .fontColor(this.getAccentColor())
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .onClick(() => {
            this.showWordsDialog = true;
          })
        }

        Row({ space: 8 }) {
          Button(this.isGenerating ? this.progressText : '生成词云')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .backgroundColor('#2563eb')
            .borderRadius(20)
            .height(36)
            .enabled(!this.isGenerating && this.cloudWords.length > 0)
            .layoutWeight(1)
            .onClick(() => {
              this.generateWordCloud();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })

        this.StyleSelector()

        Column() {
          Column() {
            if (this.placedWords.length > 0) {
              WordCloudView({
                placedWords: this.placedWords,
                bgColor: this.palettes[this.currentPaletteIndex].bgColor,
                paletteColors: this.palettes[this.currentPaletteIndex].colors,
                canvasPixelSize: this.canvasPixelSize,
                canvasSize: this.LAYOUT_CANVAS_SIZE
              })
                .width(this.canvasSize)
                .height(this.canvasSize)
            } else if (this.isGenerating) {
              Column() {
                Progress({ value: this.progressValue, total: 100, type: ProgressType.Linear })
                  .width(Math.floor(this.canvasSize * 0.6))
                  .color(this.getAccentColor())
                  .margin({ bottom: 12 })
                Text(this.progressText)
                  .fontSize(13)
                  .fontColor($r('app.color.tertiary_text'))
              }
              .width('100%')
              .height(this.canvasSize)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
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
            Column() {
              SaveButton({ icon: SaveIconStyle.FULL_FILLED, text: SaveDescription.SAVE_IMAGE, buttonType: ButtonType.Normal })
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.getAccentColor())
                .backgroundColor(Color.Transparent)
                .borderRadius(21)
                .height(42)
                .onClick(async (_event: ClickEvent, result: SaveButtonOnClickResult) => {
                  if (result === SaveButtonOnClickResult.SUCCESS) {
                    await this.saveToAlbum();
                  } else {
                    this.uiContext.getPromptAction().showToast({ message: '授权失败', duration: 1500 });
                  }
                })
            }
            .backgroundColor(this.getAccentColor())
            .borderRadius(22)
            .height(44)
            .layoutWeight(1)
            .padding(1)

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

        if (this.isGenerating) {
          Column() {
            Progress({ value: this.progressValue, total: 100, type: ProgressType.Linear })
              .width('60%')
              .color(this.getAccentColor())
            Text(this.progressText)
              .fontSize(12)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ top: 4 })
          }
          .margin({ top: 8, bottom: 16 })
        }
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .scrollable(ScrollDirection.Vertical)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .backgroundColor($r('app.color.page_background'))
    .bindContentCover(this.showWordsDialog, this.WordsEditCover(), {
      modalTransition: ModalTransition.NONE,
      onDisappear: () => {
        this.showWordsDialog = false;
      }
    })
  }

  @Builder
  WordsEditCover() {
    Column() {
      Row() {
        Text('参与词语 (' + this.cloudWords.length.toString() + ')')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        Blank()
        Button('完成')
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor('#2563eb')
          .borderRadius(18)
          .height(32)
          .padding({ left: 16, right: 16 })
          .onClick(() => {
            this.showWordsDialog = false;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 12 })

      Row() {
        TextInput({ placeholder: '输入词语', text: this.customWord })
          .fontSize(14)
          .fontColor($r('app.color.primary_text'))
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(8)
          .layoutWeight(1)
          .height(36)
          .padding({ left: 8, right: 8 })
          .onChange((value: string) => {
            this.customWord = value;
          })

        TextInput({ placeholder: '权重', text: this.customCount })
          .fontSize(14)
          .fontColor($r('app.color.primary_text'))
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(8)
          .type(InputType.Number)
          .width(60)
          .height(36)
          .padding({ left: 8, right: 8 })
          .margin({ left: 6 })
          .onChange((value: string) => {
            this.customCount = value;
          })

        Button('添加')
          .fontSize(13)
          .fontColor(Color.White)
          .backgroundColor(this.getAccentColor())
          .borderRadius(18)
          .height(32)
          .padding({ left: 12, right: 12 })
          .margin({ left: 6 })
          .onClick(() => {
            this.addCustomWordFromDialog();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 12 })

      if (this.cloudWords.length > 0) {
        Text('点击词语可移除')
          .fontSize(11)
          .fontColor($r('app.color.hint_text'))
          .width('100%')
          .padding({ left: 16, bottom: 6 })

        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.cloudWords, (entry: CloudWord, index: number) => {
            Row() {
              Text(entry.text)
                .fontSize(13)
                .fontColor(this.getAccentColor())
                .fontWeight(FontWeight.Medium)
              if (entry.weight > 1) {
                Text('×' + entry.weight.toString())
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
              this.removeWordAndSync(entry.text);
            })
          }, (entry: CloudWord, index: number) => entry.text + '_' + entry.weight.toString())
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }

      Row({ space: 8 }) {
        Button('示例')
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor('#07c160')
          .borderRadius(20)
          .height(36)
          .onClick(() => {
            this.loadExample();
          })

        Button('清空')
          .fontSize(14)
          .fontColor($r('app.color.tertiary_text'))
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(20)
          .height(36)
          .onClick(() => {
            this.clearWords();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 })
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .height('70%')
    .backgroundColor($r('app.color.page_background'))
    .borderRadius({ topLeft: 20, topRight: 20 })
    .padding({ bottom: 24 })
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

      Text('输入词语后点击生成')
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

      Text('形状')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
        .padding({ left: 16, top: 8, bottom: 6 })

      Scroll() {
        Row() {
          ForEach(this.shapes, (shape: ShapeDef, index: number) => {
            Column() {
              Image($r('app.media.' + this.shapeIcons[index]))
                .width(24)
                .height(24)
                .fillColor(this.currentShapeIndex === index ? this.getAccentColor() : $r('app.color.tertiary_text'))
              Text(shape.label)
                .fontSize(10)
                .fontColor(this.currentShapeIndex === index ? this.getAccentColor() : $r('app.color.tertiary_text'))
                .margin({ top: 2 })
            }
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .borderRadius(8)
            .backgroundColor(this.currentShapeIndex === index ? this.getAccentColor() + '18' : Color.Transparent)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.currentShapeIndex = index;
            })
          }, (shape: ShapeDef) => shape.id)
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

  private parseDirectWords(): void {
    let raw: string = this.directWordsText;
    if (!raw || raw.trim().length === 0) {
      this.cloudWords = [];
      return;
    }
    let lines: string[] = raw.split('\n');
    let newWords: CloudWord[] = [];
    for (let i: number = 0; i < lines.length && newWords.length < this.MAX_WORDS; i++) {
      let line: string = lines[i].trim();
      if (line.length === 0) {
        continue;
      }
      let parts: string[] = line.split(new RegExp('[:：]'));
      let text: string = parts[0].trim();
      if (text.length === 0) {
        continue;
      }
      let weight: number = 1;
      if (parts.length > 1) {
        let parsed: number = parseInt(parts[1].trim());
        if (!isNaN(parsed) && parsed > 0) {
          weight = parsed;
        }
      }
      let found: boolean = false;
      for (let j: number = 0; j < newWords.length; j++) {
        if (newWords[j].text === text) {
          let merged: CloudWord = new CloudWord(text, newWords[j].weight + weight, newWords[j].custom);
          newWords[j] = merged;
          found = true;
          break;
        }
      }
      if (!found) {
        newWords.push(new CloudWord(text, weight, true));
      }
    }
    this.cloudWords = newWords;
  }

  private removeWordAndSync(word: string): void {
    let newWords: CloudWord[] = [];
    for (let i: number = 0; i < this.cloudWords.length; i++) {
      if (this.cloudWords[i].text !== word) {
        newWords.push(this.cloudWords[i]);
      }
    }
    this.cloudWords = newWords;
    this.syncDirectTextFromWords();
  }

  private syncDirectTextFromWords(): void {
    let lines: string[] = [];
    for (let i: number = 0; i < this.cloudWords.length; i++) {
      let w: CloudWord = this.cloudWords[i];
      if (w.weight > 1) {
        lines.push(w.text + ':' + w.weight.toString());
      } else {
        lines.push(w.text);
      }
    }
    this.directWordsText = lines.join('\n');
  }

  private loadExample(): void {
    let exampleData: string[][] = [
      ['分词', '8'], ['语言', '5'], ['文本', '4'], ['技术', '3'], ['模型', '3'], ['任务', '3'],
      ['机器', '3'], ['规则', '3'], ['中文', '3'], ['词汇', '3'], ['条件随机场', '3'], ['理解', '3'],
      ['算法', '2'], ['人工智能', '2'], ['自然语言处理', '2'], ['领域', '2'], ['边界', '2'], ['单元', '2'],
      ['情感', '2'], ['含义', '2'], ['语法', '2'], ['网络', '2'], ['新词', '2'], ['机器学习', '2'],
      ['隐马尔可夫', '2'], ['语料', '2'], ['共现', '2'], ['深度学习', '2'], ['语义', '2'], ['歧义', '2'],
      ['切分', '2'], ['词性标注', '2'], ['命名实体', '2'], ['句法分析', '2'], ['人类', '2'], ['字符', '2'],
      ['词典', '2'], ['计算机', '2'], ['大数据', '2'], ['信息', '2'], ['知识', '2'], ['基石', '2'],
      ['系统', '2'], ['发展', '2'], ['方法', '2'], ['关系', '2'],
      ['统计模型', '1'], ['双向长短期记忆', '1'], ['搜索引擎', '1'],
      ['智能客服', '1'], ['情感分析', '1'], ['大脑', '1'], ['散文', '1'],
      ['意合语言', '1'], ['连续', '1'], ['片段', '1'], ['内涵', '1'], ['认知', '1'], ['人工', '1'],
      ['精确度', '1'], ['挑战性', '1'], ['魅力', '1'], ['分支', '1'], ['高级', '1'], ['钥匙', '1'],
      ['大门', '1'], ['浩瀚', '1'], ['海洋', '1'], ['有价值', '1'], ['碎片', '1'], ['不可或缺', '1'],
    ];
    let lines: string[] = [];
    for (let i: number = 0; i < exampleData.length; i++) {
      let text: string = exampleData[i][0];
      let weight: string = exampleData[i][1];
      if (weight === '1') {
        lines.push(text);
      } else {
        lines.push(text + ':' + weight);
      }
    }
    this.directWordsText = lines.join('\n');
    this.parseDirectWords();
  }

  private addCustomWordFromDialog(): void {
    let word: string = this.customWord.trim();
    if (word.length === 0) {
      return;
    }
    let weight: number = 1;
    let parsed: number = parseInt(this.customCount);
    if (!isNaN(parsed) && parsed > 0) {
      weight = parsed;
    }
    let found: boolean = false;
    for (let i: number = 0; i < this.cloudWords.length; i++) {
      if (this.cloudWords[i].text === word) {
        let merged: CloudWord = new CloudWord(word, this.cloudWords[i].weight + weight, true);
        this.cloudWords[i] = merged;
        found = true;
        break;
      }
    }
    if (!found) {
      this.cloudWords.push(new CloudWord(word, weight, true));
    }
    this.syncDirectTextFromWords();
    this.customWord = '';
    this.customCount = '1';
  }

  private clearWords(): void {
    this.directWordsText = '';
    this.cloudWords = [];
    this.placedWords = [];
    this.generatedCachePath = '';
  }

  private async extractWordsToDirect(): Promise<void> {
    if (!this.inputText || this.inputText.trim().length === 0) {
      this.uiContext.getPromptAction().showToast({ message: '请先输入或粘贴文本到上方编辑区', duration: 1500 });
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
      let lines: string[] = [];
      let newWords: CloudWord[] = [];
      for (let i: number = 0; i < entries.length; i++) {
        newWords.push(new CloudWord(entries[i].word, entries[i].count, false));
        if (entries[i].count > 1) {
          lines.push(entries[i].word + ':' + entries[i].count.toString());
        } else {
          lines.push(entries[i].word);
        }
      }
      if (this.directWordsText.length > 0) {
        this.directWordsText = this.directWordsText + '\n' + lines.join('\n');
      } else {
        this.directWordsText = lines.join('\n');
      }
      this.cloudWords = newWords;
      this.syncDirectTextFromWords();
    } catch (e) {
      this.uiContext.getPromptAction().showToast({ message: '分词失败', duration: 2000 });
    }
    this.isExtracting = false;
  }

  private async generateWordCloud(): Promise<void> {
    console.info('[WordCloud] generateWordCloud START, cloudWords=' + this.cloudWords.length.toString());
    if (this.cloudWords.length === 0) {
      this.uiContext.getPromptAction().showToast({ message: '请先提取或添加词语', duration: 1500 });
      return;
    }
    this.isGenerating = true;
    this.placedWords = [];
    this.generatedCachePath = '';
    this.progressValue = 10;
    this.progressText = '布局中...';

    try {
      let wordInputs: WordInput[] = [];
      for (let i: number = 0; i < this.cloudWords.length; i++) {
        let wi: WordInput = {
          text: this.cloudWords[i].text,
          weight: this.cloudWords[i].weight,
        };
        wordInputs.push(wi);
      }

      let fontName: string = this.fontNames[this.currentFontIndex];
      let layoutSize: number = this.LAYOUT_CANVAS_SIZE;

      let input: WordCloudInput = {
        words: wordInputs,
        canvasSize: layoutSize,
        shapeIndex: this.currentShapeIndex,
        fontName: fontName,
      };

      console.info('[WordCloud] calling runPlacementAsync...');
      let result = await runPlacementAsync(input);
      console.info('[WordCloud] placement done, placed=' + result.count.toString());

      this.progressValue = 90;
      this.progressText = '着色中...';

      let palette: PaletteColor = this.palettes[this.currentPaletteIndex];
      let placedResults: PlacedWord[] = [];
      for (let i: number = 0; i < result.placed.length; i++) {
        let pd = result.placed[i];
        let pw: PlacedWord = new PlacedWord();
        pw.text = pd.text;
        pw.x = pd.x;
        pw.y = pd.y;
        pw.size = pd.size;
        pw.color = palette.colors[i % palette.colors.length];
        pw.angle = pd.angle;
        pw.font = fontName;
        pw.width = pd.width;
        pw.height = pd.height;
        placedResults.push(pw);
      }

      this.placedWords = placedResults;
      this.lastWeightedItems = [];
      for (let i: number = 0; i < this.cloudWords.length; i++) {
        let item: WeightedItem = new WeightedItem();
        item.text = this.cloudWords[i].text;
        item.weight = this.cloudWords[i].weight;
        item.tag = '';
        this.lastWeightedItems.push(item);
      }

      this.progressValue = 100;
      this.progressText = '已生成 ' + placedResults.length.toString() + ' 个词';
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[WordCloud] generate FAILED: code=' + err.code + ' msg=' + err.message);
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

  private async refreshFont(): Promise<void> {
    if (this.lastWeightedItems.length === 0) {
      return;
    }
    let fontName: string = this.fontNames[this.currentFontIndex];
    let layoutSize: number = this.LAYOUT_CANVAS_SIZE;

    let wordInputs: WordInput[] = [];
    for (let i: number = 0; i < this.lastWeightedItems.length; i++) {
      let wi: WordInput = {
        text: this.lastWeightedItems[i].text,
        weight: this.lastWeightedItems[i].weight,
      };
      wordInputs.push(wi);
    }

    let input: WordCloudInput = {
      words: wordInputs,
      canvasSize: layoutSize,
      shapeIndex: this.currentShapeIndex,
      fontName: fontName,
    };

    try {
      let result = await runPlacementAsync(input);
      let palette: PaletteColor = this.palettes[this.currentPaletteIndex];
      let placedResults: PlacedWord[] = [];
      for (let i: number = 0; i < result.placed.length; i++) {
        let pd = result.placed[i];
        let pw: PlacedWord = new PlacedWord();
        pw.text = pd.text;
        pw.x = pd.x;
        pw.y = pd.y;
        pw.size = pd.size;
        pw.color = palette.colors[i % palette.colors.length];
        pw.angle = pd.angle;
        pw.font = fontName;
        pw.width = pd.width;
        pw.height = pd.height;
        placedResults.push(pw);
      }
      this.placedWords = placedResults;
    } catch (e) {
      console.error('[WordCloud] refreshFont failed');
    }
  }

  private getAccentColor(): string {
    return this.templates[this.currentPaletteIndex].accentColor;
  }

  private renderExportPixelMap(): image.PixelMap {
    let exportSize: number = this.LAYOUT_CANVAS_SIZE * 2;
    let off: OffscreenCanvas = new OffscreenCanvas(exportSize, exportSize, LengthMetricsUnit.PX);
    let ctx: OffscreenCanvasRenderingContext2D = off.getContext('2d', new RenderingContextSettings(true)) as OffscreenCanvasRenderingContext2D;
    let palette: PaletteColor = this.palettes[this.currentPaletteIndex];
    let colors: string[] = palette.colors.length > 0 ? palette.colors : ['#333333'];

    ctx.clearRect(0, 0, exportSize, exportSize);
    ctx.fillStyle = palette.bgColor;
    ctx.fillRect(0, 0, exportSize, exportSize);

    let scale: number = exportSize / this.LAYOUT_CANVAS_SIZE;
    for (let i: number = 0; i < this.placedWords.length; i++) {
      let pw: PlacedWord = this.placedWords[i];
      let color: string = pw.color && pw.color.length > 0 ? pw.color : colors[i % colors.length];
      let drawSize: number = pw.size * scale;
      let drawX: number = pw.x * scale;
      let drawY: number = pw.y * scale;
      ctx.save();
      ctx.translate(drawX, drawY);
      if (pw.angle !== 0) {
        ctx.rotate(pw.angle * Math.PI / 180);
      }
      ctx.font = drawSize.toString() + 'px ' + (pw.font && pw.font.length > 0 ? pw.font : 'sans-serif');
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillStyle = color;
      ctx.fillText(pw.text, 0, 0);
      ctx.restore();
    }

    return ctx.getPixelMap(0, 0, exportSize, exportSize);
  }

   private cachedPixelMap: image.PixelMap | undefined = undefined;

   private async saveToAlbum(): Promise<void> {
     try {
       let pm: image.PixelMap = this.renderExportPixelMap();
       this.cachedPixelMap = pm;
       await ImageExporter.saveToAlbum(this.uiContext, pm);
       let cachePath: string = await ImageExporter.pixelMapToCache(this.uiContext, pm, 'wordcloud');
       this.generatedCachePath = cachePath;
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
        let pm: image.PixelMap = this.renderExportPixelMap();
        cachePath = await ImageExporter.pixelMapToCache(this.uiContext, pm, 'wordcloud');
        this.generatedCachePath = cachePath;
        pm.release();
      }
      ImageExporter.share(this.uiContext, cachePath);
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[WordCloud] share failed: ' + err.code + ' ' + err.message);
      this.uiContext.getPromptAction().showToast({ message: '分享失败', duration: 2000 });
    }
  }
}
