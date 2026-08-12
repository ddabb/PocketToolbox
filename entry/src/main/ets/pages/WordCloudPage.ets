import { KeywordUtil, WordCountEntry } from '../common/utils/KeywordUtil';
import { FontUtil } from '../common/utils/FontUtil';
import { FontScaler, WeightedItem } from '../core/style/FontScaler';
import { Palette, PaletteColor } from '../core/style/Palette';
import { ShapeDef } from '../core/layout/ShapeDef';
import { PlacedWord, CloudWord } from '../model/WordItem';
import { TemplateInfo, Md2PngTemplates } from '../model/Md2PngModels';
import { WordCloudView } from '../components/WordCloudView';
import { ImageSaveShareBar } from '../components/ImageSaveShareBar';
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
  @State cloudWords: CloudWord[] = [];
  @State placedWords: PlacedWord[] = [];
  @State currentPaletteIndex: number = 0;
  @State currentFontIndex: number = 0;
  @State currentShapeIndex: number = 0;
  @State forceRepeat: boolean = false;
  @State isGenerating: boolean = false;
  @State isExtracting: boolean = false;
  @State canvasSize: number = 360;
  @State canvasPixelSize: number = 720;
  @State progressText: string = '';
  @State progressValue: number = 0;
  @State customWord: string = '';
  @State customCount: string = '1';
  @State directWordsText: string = '';
  @State rawSourceText: string = '';
  @State showWordsDialog: boolean = false;
  @State showSettingsDialog: boolean = false;
  private uiContext: UIContext = this.getUIContext();
  private palettes: PaletteColor[] = Palette.getAll();
  private templates: TemplateInfo[] = Md2PngTemplates.getAll();
  private lastWeightedItems: WeightedItem[] = [];
  private shapes: ShapeDef[] = ShapeDef.SHAPES;
  private shapeIcons: string[] = [
    'shape_circle', 'shape_cardioid', 'shape_star5', 'shape_diamond',
    'shape_triangle', 'shape_triangleUp', 'shape_triangleLeft', 'shape_triangleRight',
    'shape_square', 'shape_pentagon', 'shape_hexagon',
    'shape_cross', 'shape_cloud', 'shape_oval', 'shape_leaf',
    'shape_star8', 'shape_flower', 'shape_octagon'
  ];
  private fontNames: string[] = [
    Md2PngTemplates.FONT_SMILEY, Md2PngTemplates.FONT_WENKAI,
    Md2PngTemplates.FONT_MASHAN, Md2PngTemplates.FONT_KUAILE,
    Md2PngTemplates.FONT_HUANGYOU, Md2PngTemplates.FONT_LONGCANG,
    Md2PngTemplates.FONT_MAOMAO, Md2PngTemplates.FONT_XIAOWEI,
    Md2PngTemplates.FONT_ZHIMANG,
    Md2PngTemplates.FONT_SOURCE_HAN_SANS, Md2PngTemplates.FONT_SOURCE_HAN_SERIF,
    Md2PngTemplates.FONT_CHILL_CHUNQIU, Md2PngTemplates.FONT_CHILL_ROUND,
    Md2PngTemplates.FONT_TSANGER_FEIBAI, Md2PngTemplates.FONT_TSANGER_XWZ
  ];
  private fontLabels: string[] = [
    '得意黑', '霞鹜文楷', '马善政', '站酷快乐',
    '站酷庆科黄油', '龙藏体', '刘建毛草', '站酷小薇', '志芒行',
    '思源黑体', '思源宋体',
    '寒蝉春风', '寒蝉全圆体', '仓耳非白', '仓耳小丸子'
  ];
  private readonly COMPONENT_ID: string = 'wordcloud_canvas';
  private readonly MAX_WORDS: number = 180;
  private readonly LAYOUT_CANVAS_SIZE: number = 800;

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
        // 词语编辑区 — 紧凑排版
        Column() {
          Row() {
            Text('词语编辑')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
            Blank()
            if (this.rawSourceText.length > 0) {
              Text('还原原文')
                .fontSize(11)
                .fontColor(this.getAccentColor())
                .onClick(() => {
                  this.directWordsText = this.rawSourceText;
                  this.rawSourceText = '';
                })
            }
          }
          .width('100%')

          TextArea({ placeholder: '每行一个词语，冒号指定权重  例如: 创新:5', text: this.directWordsText })
            .width('100%')
            .height(96)
            .fontSize(13)
            .fontColor($r('app.color.primary_text'))
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(10)
            .padding(10)
            .margin({ top: 6 })
            .onChange((value: string) => {
              this.directWordsText = value;
              this.parseDirectWords();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10 })

        // 操作按钮行 + 词语计数
        Row({ space: 6 }) {
          Button('示例')
            .fontSize(13)
            .fontColor(Color.White)
            .backgroundColor('#07c160')
            .borderRadius(16)
            .height(32)
            .onClick(() => { this.loadExample(); })

          Button('清空')
            .fontSize(13)
            .fontColor($r('app.color.tertiary_text'))
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(16)
            .height(32)
            .onClick(() => { this.clearWords(); })

          Button(this.isExtracting ? '分词中...' : '从文本提取')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .backgroundColor('#2563eb')
            .borderRadius(16)
            .height(32)
            .enabled(!this.isExtracting)
            .onClick(() => { this.extractWordsToDirect(); })

          Blank()

          if (this.cloudWords.length > 0) {
            Text('共' + this.cloudWords.length.toString() + '词')
              .fontSize(12)
              .fontColor($r('app.color.tertiary_text'))
              .onClick(() => { this.showWordsDialog = true; })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })

        // 配色/形状/字体 — 画布上方
        this.StyleThumbBar()

        Column() {
          Column() {
            if (this.placedWords.length > 0) {
              WordCloudView({
                placedWords: this.placedWords,
                bgColor: this.palettes[this.currentPaletteIndex].bgColor,
                layoutSize: this.LAYOUT_CANVAS_SIZE
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
        .padding({ left: 16, right: 16, top: 8 })
        .alignItems(HorizontalAlign.Center)

        if (this.placedWords.length > 0) {
          ImageSaveShareBar({
            accentColor: this.getAccentColor(),
            onPmForSave: (): image.PixelMap => this.renderExportPixelMap(),
            onPmForShare: (): image.PixelMap => this.renderExportPixelMap(),
          })
            .width('100%')
            .padding({ left: 16, right: 16, top: 6 })
        }

        // 底部留白避免被导航栏遮挡
        Blank()
          .height(20)
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
    .bindContentCover(this.showSettingsDialog, this.SettingsCover(), {
      modalTransition: ModalTransition.NONE,
      onDisappear: () => {
        this.showSettingsDialog = false;
      }
    })
  }

  @Builder
  SettingsCover() {
    Column() {
      Row() {
        Text('样式设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        Blank()
        Button('完成')
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor(this.getAccentColor())
          .borderRadius(18)
          .height(32)
          .padding({ left: 16, right: 16 })
          .onClick(() => {
            this.showSettingsDialog = false;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 20, bottom: 12 })

      Scroll() {
        Column() {
          // 配色方案 — 可视化色块预览
          Text('配色方案')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .width('100%')
            .padding({ left: 16, bottom: 8 })

          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.templates, (tpl: TemplateInfo, index: number) => {
              Column() {
                // 显示该配色方案的前 3 个颜色作为预览
                Row({ space: 1 }) {
                  ForEach(this.palettes[index].colors.slice(0, 3), (color: string) => {
                    Column()
                      .width(16)
                      .height(20)
                      .borderRadius(4)
                      .backgroundColor(color)
                  })
                }
                .padding({ top: 1, bottom: 1 })
                Text(tpl.name)
                  .fontSize(11)
                  .fontColor(this.currentPaletteIndex === index ? this.getTemplateAccent(index) : $r('app.color.tertiary_text'))
                  .margin({ top: 5 })
              }
              .padding({ left: 9, right: 9, top: 6, bottom: 6 })
              .borderRadius(10)
              .backgroundColor(this.currentPaletteIndex === index ? this.getTemplateAccent(index) + '15' : Color.Transparent)
              .border({
                width: this.currentPaletteIndex === index ? 1.5 : 0,
                color: this.getTemplateAccent(index),
                style: BorderStyle.Solid
              })
              .alignItems(HorizontalAlign.Center)
              .onClick(() => {
                this.currentPaletteIndex = index;
                this.refreshColors();
              })
            }, (tpl: TemplateInfo) => tpl.id)
          }
          .width('100%')
          .padding({ left: 8, right: 8 })

          // 形状 — 大图标预览
          Text('形状')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .width('100%')
            .padding({ left: 16, top: 18, bottom: 8 })

          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.shapes, (shape: ShapeDef, index: number) => {
              Column() {
                Image($r('app.media.' + this.shapeIcons[index]))
                  .width(30)
                  .height(30)
                  .fillColor(this.currentShapeIndex === index ? this.getAccentColor() : $r('app.color.tertiary_text'))
                  .objectFit(ImageFit.Contain)
                Text(shape.label)
                  .fontSize(11)
                  .fontColor(this.currentShapeIndex === index ? this.getAccentColor() : $r('app.color.tertiary_text'))
                  .margin({ top: 5 })
              }
              .padding({ left: 9, right: 9, top: 6, bottom: 6 })
              .borderRadius(10)
              .backgroundColor(this.currentShapeIndex === index ? this.getAccentColor() + '15' : Color.Transparent)
              .border({
                width: this.currentShapeIndex === index ? 1.5 : 0,
                color: this.getAccentColor(),
                style: BorderStyle.Solid
              })
              .alignItems(HorizontalAlign.Center)
              .onClick(() => {
                this.currentShapeIndex = index;
              })
            }, (shape: ShapeDef) => shape.id)
          }
          .width('100%')
          .padding({ left: 8, right: 8 })

          // 字体 — 大字预览
          Text('字体')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .width('100%')
            .padding({ left: 16, top: 18, bottom: 8 })

          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.fontNames, (fontName: string, index: number) => {
              Column() {
                Text('词云')
                  .fontSize(24)
                  .fontFamily(fontName)
                  .fontColor(this.currentFontIndex === index ? this.getAccentColor() : $r('app.color.primary_text'))
                Text(this.fontLabels[index])
                  .fontSize(11)
                  .fontColor(this.currentFontIndex === index ? this.getAccentColor() : $r('app.color.tertiary_text'))
                  .margin({ top: 5 })
              }
              .padding({ left: 10, right: 10, top: 7, bottom: 7 })
              .borderRadius(10)
              .backgroundColor(this.currentFontIndex === index ? this.getAccentColor() + '15' : Color.Transparent)
              .border({
                width: this.currentFontIndex === index ? 1.5 : 0,
                color: this.getAccentColor(),
                style: BorderStyle.Solid
              })
              .alignItems(HorizontalAlign.Center)
              .onClick(() => {
                this.currentFontIndex = index;
                this.refreshFont();
              })
            }, (fontName: string) => fontName)
          }
          .width('100%')
          .padding({ left: 8, right: 8 })
        }
        .width('100%')
        .padding({ bottom: 32 })
      }
      .scrollable(ScrollDirection.Vertical)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('82%')
    .backgroundColor($r('app.color.page_background'))
    .borderRadius({ topLeft: 20, topRight: 20 })
  }

  // 词云下方紧凑风格工具栏
  @Builder
  StyleThumbBar() {
    Column() {
      // 配色 — 两行显示
      Row({ space: 4 }) {
        Text('配色')
          .fontSize(11)
          .fontColor($r('app.color.tertiary_text'))
          .width(32)
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.templates, (tpl: TemplateInfo, index: number) => {
            Row({ space: 0 }) {
              ForEach(this.palettes[index].colors.slice(0, 4), (color: string) => {
                Column()
                  .width(10).height(12).borderRadius(2).backgroundColor(color)
              })
            }
            .width(44).height(14).borderRadius(5)
            .margin({ right: 4, bottom: 3 })
            .border({ width: this.currentPaletteIndex === index ? 1.5 : 0,
              color: this.getTemplateAccent(index) })
            .onClick(() => { this.currentPaletteIndex = index; this.refreshColors(); })
          })
        }
        .layoutWeight(1)
      }
      .width('100%').padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Top)

      // 形状行 — 自动换行
      Row({ space: 4 }) {
        Text('形状')
          .fontSize(11)
          .fontColor($r('app.color.tertiary_text'))
          .width(32)
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.shapes, (shape: ShapeDef, index: number) => {
            Image($r('app.media.' + this.shapeIcons[index]))
              .width(18).height(18)
              .fillColor(this.currentShapeIndex === index ? this.getAccentColor() : $r('app.color.tertiary_text'))
              .borderRadius(4).padding(2)
              .margin({ right: 4, bottom: 3 })
              .border({ width: this.currentShapeIndex === index ? 1.5 : 0,
                color: this.getAccentColor(), radius: 6 })
              .onClick(() => { this.currentShapeIndex = index; })
          })
        }
        .layoutWeight(1)
      }
      .width('100%').padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Top)

      // 字体行 — 自动换行
      Row({ space: 4 }) {
        Text('字体')
          .fontSize(11)
          .fontColor($r('app.color.tertiary_text'))
          .width(32)
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.fontNames, (fontName: string, index: number) => {
            Text('云')
              .fontSize(15).fontFamily(fontName)
              .fontColor(this.currentFontIndex === index ? this.getAccentColor() : $r('app.color.tertiary_text'))
              .borderRadius(4).width(24).height(20).textAlign(TextAlign.Center)
              .margin({ right: 4, bottom: 3 })
              .border({ width: this.currentFontIndex === index ? 1.5 : 0,
                color: this.getAccentColor(), radius: 6 })
              .onClick(() => { this.currentFontIndex = index; this.refreshFont(); })
          })
        }
        .layoutWeight(1)
      }
      .width('100%').padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Top)

      // 当前配置提示
      Text('配色: ' + this.templates[this.currentPaletteIndex].name +
        ' | 形状: ' + this.shapes[this.currentShapeIndex].label +
        ' | 字体: ' + this.fontLabels[this.currentFontIndex])
        .fontSize(10)
        .fontColor($r('app.color.tertiary_text'))
        .width('100%')
        .padding({ left: 16, right: 16 })

      // 强制重复开关
      Row({ space: 4 }) {
        Toggle({ type: ToggleType.Checkbox, isOn: this.forceRepeat })
          .selectedColor(this.getAccentColor())
          .width(16).height(16)
          .onChange((isOn: boolean) => { this.forceRepeat = isOn; })
        Text('词少时强制重复填充')
          .fontSize(11)
          .fontColor($r('app.color.tertiary_text'))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4 })

      // 生成词云按钮
      Button(this.isGenerating ? '生成中...' : '生成词云')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .backgroundColor('#2563eb')
        .borderRadius(18)
        .height(38)
        .width('100%')
        .margin({ left: 16, right: 16, top: 6, bottom: 8 })
        .enabled(!this.isGenerating && this.cloudWords.length > 0)
        .onClick(() => { this.generateWordCloud(); })
    }
    .width('100%')
    .padding({ top: 6 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(10)
    .margin({ left: 16, right: 16, top: 6 })
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
    this.rawSourceText = '';
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
    this.rawSourceText = '';
    this.cloudWords = [];
    this.placedWords = [];
  }

  private async extractWordsToDirect(): Promise<void> {
    if (!this.directWordsText || this.directWordsText.trim().length === 0) {
      this.uiContext.getPromptAction().showToast({ message: '请先输入或粘贴文本到上方编辑区', duration: 1500 });
      return;
    }
    this.isExtracting = true;
    try {
      let wordEntries: Array<WordCountEntry> = await KeywordUtil.extractAllWords(this.directWordsText);
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
      // 暂存原文，替换为提取后的关键词列表
      this.rawSourceText = this.directWordsText;
      this.directWordsText = lines.join('\n');
      this.cloudWords = newWords;
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

      // 强制重复：词少时循环补充到足够填充形状
      if (this.forceRepeat && wordInputs.length < 30) {
        let target: number = Math.min(wordInputs.length * 8, this.MAX_WORDS);
        let repeated: WordInput[] = [];
        while (repeated.length < target) {
          for (let i: number = 0; i < wordInputs.length && repeated.length < target; i++) {
            repeated.push(wordInputs[i]);
          }
        }
        wordInputs = repeated;
      }

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

  // P1优化: 就地更新颜色, 避免逐词深度拷贝 (减少100-200+对象创建)
  private refreshColors(): void {
    if (this.placedWords.length === 0) {
      return;
    }
    let palette: PaletteColor = this.palettes[this.currentPaletteIndex];
    let colors: string[] = palette.colors;
    for (let i: number = 0; i < this.placedWords.length; i++) {
      this.placedWords[i].color = colors[i % colors.length];
    }
    // 触发 @Watch: 新建数组引用但共享对象
    this.placedWords = [...this.placedWords];
  }

  // P1优化: 就地更新字体
  private refreshFont(): void {
    if (this.placedWords.length === 0) {
      return;
    }
    let fontName: string = this.fontNames[this.currentFontIndex];
    for (let i: number = 0; i < this.placedWords.length; i++) {
      this.placedWords[i].font = fontName;
    }
    this.placedWords = [...this.placedWords];
  }

  private getAccentColor(): string {
    return this.templates[this.currentPaletteIndex].accentColor;
  }

  private getTemplateAccent(index: number): string {
    return this.templates[index].accentColor;
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
}
