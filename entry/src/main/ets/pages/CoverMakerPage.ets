/**
 * 公众号首图制作页面：预览 + 模板选择 + 内容/样式编辑 + 导出(900x383) + 历史
 */
import { display, mediaquery } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CoverContent, CoverHistoryRecord, CoverSlot, CoverTemplate } from '../model/CoverModels';
import { CoverFont, CoverSeries, CoverTemplates } from '../core/cover/CoverTemplates';
import { CoverContentUtil } from '../core/cover/CoverContentUtil';
import { CoverHistoryStore } from '../core/cover/CoverHistoryStore';
import { CoverPreview } from '../components/cover/CoverPreview';
import { PaletteSection } from '../components/template/PaletteSection';
import { FontUtil } from '../common/utils/FontUtil';
import { ToastUtil } from '../common/utils/ToastUtil';
import { savePixelMapToAlbum, shareImageViaPanel } from '../common/utils/ShareImageUtil';

const PREVIEW_ID: string = 'cover_preview';
const SINGLE_LINE_LAYOUTS: string[] = ['a3_neon', 'c1_poster', 'c2_number', 'd1_geoblock', 'e2_texture', 'b4_solar'];

@Builder
export function CoverMakerPageBuilder() {
  NavDestination() {
    CoverMakerContent()
  }
  .title('首图制作')
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct CoverMakerContent {
  @State currentTemplateId: string = 'A1';
  @State content: CoverContent = new CoverContent();
  @State paletteIndex: number = 0;
  @State fontIndex: number = 0;
  @State seriesFilter: string = CoverSeries.ALL;
  @State editorTab: number = 0;
  @State exporting: boolean = false;
  @State historyRecords: CoverHistoryRecord[] = [];
  @State isDark: boolean = false;
  previewVp: number = 300;
  snapshotScale: number = 1;
  /** 拼音逐音节编辑：当前展开候选的字下标，-1 表示未展开 */
  @State pyEditIndex: number = -1;
  private darkListener: mediaquery.MediaQueryListener | null = null;

  aboutToAppear(): void {
    FontUtil.registerAll(this.getUIContext());
    let listener: mediaquery.MediaQueryListener =
      this.getUIContext().getMediaQuery().matchMediaSync('(prefers-color-scheme: dark)');
    this.darkListener = listener;
    this.isDark = listener.matches;
    listener.on('change', (result: mediaquery.MediaQueryResult) => {
      this.isDark = result.matches;
    });
    let uiCtx: UIContext = this.getUIContext();
    let d: display.Display = display.getDefaultDisplaySync();
    let density: number = d.densityPixels;
    let availVp: number = d.width / density - 32;
    this.previewVp = Math.min(900 / density, availVp);
    this.snapshotScale = 900 / (this.previewVp * density);
    this.selectTemplate(CoverTemplates.getById('A1'));
    let context = uiCtx.getHostContext() as common.UIAbilityContext;
    this.historyRecords = CoverHistoryStore.loadRecords(context);
  }

  // ---------- 状态与业务 ----------

  private currentTemplate(): CoverTemplate {
    return CoverTemplates.getById(this.currentTemplateId);
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private selectTemplate(t: CoverTemplate): void {
    this.currentTemplateId = t.id;
    this.paletteIndex = 0;
    this.fontIndex = 0;
    let c: CoverContent = this.content.copy();
    let seed: Record<string, string> = t.seed;
    if (c.title === '') {
      c.title = seed['title'] ?? '';
    }
    if (c.subtitle === '') {
      c.subtitle = seed['subtitle'] ?? '';
    }
    if (c.author === '') {
      c.author = seed['author'] ?? '';
    }
    if (c.quote === '') {
      c.quote = seed['quote'] ?? '';
    }
    if (c.quoteSource === '') {
      c.quoteSource = seed['quoteSource'] ?? '';
    }
    if (c.seal === '') {
      c.seal = seed['seal'] ?? '';
    }
    if (t.slots.indexOf(CoverSlot.ISSUE) >= 0 && c.issue === '') {
      let issue: string = seed['issue'] ?? '';
      c.issue = issue !== '' ? issue : CoverContentUtil.today();
    }
    if (t.slots.indexOf(CoverSlot.PINYIN) >= 0) {
      c.pinyinLocked = false;
      c.pinyin = CoverContentUtil.autoPinyin(c.title);
      this.pyEditIndex = -1;
    }
    this.content = c;
  }

  private onSlotChange(slot: string, value: string): void {
    let c: CoverContent = this.content.copy();
    if (slot === CoverSlot.TITLE) {
      c.title = value;
      if (this.currentTemplate().slots.indexOf(CoverSlot.PINYIN) >= 0 && !c.pinyinLocked) {
        c.pinyin = CoverContentUtil.autoPinyin(value);
      }
    } else if (slot === CoverSlot.SUBTITLE) {
      c.subtitle = value;
    } else if (slot === CoverSlot.AUTHOR) {
      c.author = value;
    } else if (slot === CoverSlot.ISSUE) {
      c.issue = value;
    } else if (slot === CoverSlot.QUOTE) {
      c.quote = value;
    } else if (slot === CoverSlot.QUOTE_SOURCE) {
      c.quoteSource = value;
    } else if (slot === CoverSlot.PINYIN) {
      c.pinyin = value;
      c.pinyinLocked = true;
    } else if (slot === CoverSlot.SEAL) {
      c.seal = value;
    } else {
      return;
    }
    this.content = c;
  }

  private slotValue(slot: string): string {
    let c: CoverContent = this.content;
    if (slot === CoverSlot.TITLE) {
      return c.title;
    } else if (slot === CoverSlot.SUBTITLE) {
      return c.subtitle;
    } else if (slot === CoverSlot.AUTHOR) {
      return c.author;
    } else if (slot === CoverSlot.ISSUE) {
      return c.issue;
    } else if (slot === CoverSlot.QUOTE) {
      return c.quote;
    } else if (slot === CoverSlot.QUOTE_SOURCE) {
      return c.quoteSource;
    } else if (slot === CoverSlot.PINYIN) {
      return c.pinyin;
    } else if (slot === CoverSlot.SEAL) {
      return c.seal;
    }
    return '';
  }

  private slotLabel(slot: string): string {
    if (slot === CoverSlot.TITLE) {
      return this.currentTemplate().titleLabel;
    } else if (slot === CoverSlot.SUBTITLE) {
      return '副标题';
    } else if (slot === CoverSlot.AUTHOR) {
      return '署名 / 公众号名';
    } else if (slot === CoverSlot.ISSUE) {
      return '期号 / 日期';
    } else if (slot === CoverSlot.QUOTE) {
      return '引言';
    } else if (slot === CoverSlot.QUOTE_SOURCE) {
      return '出处';
    } else if (slot === CoverSlot.PINYIN) {
      return '拼音（自动生成，点音节选择读音）';
    } else if (slot === CoverSlot.SEAL) {
      return '印章（2-4 字）';
    }
    return slot;
  }

  private slotMaxLength(slot: string): number {
    if (slot === CoverSlot.TITLE) {
      return 20;
    } else if (slot === CoverSlot.SUBTITLE) {
      return 30;
    } else if (slot === CoverSlot.AUTHOR) {
      return 12;
    } else if (slot === CoverSlot.ISSUE) {
      return 12;
    } else if (slot === CoverSlot.QUOTE) {
      return 16;
    } else if (slot === CoverSlot.QUOTE_SOURCE) {
      return 20;
    } else if (slot === CoverSlot.PINYIN) {
      return 48;
    } else if (slot === CoverSlot.SEAL) {
      return 4;
    }
    return 20;
  }

  private changeQuote(): void {
    let t: CoverTemplate = this.currentTemplate();
    let pick = CoverContentUtil.pickByKind(this.context(), t.contentKind);
    if (pick === null) {
      ToastUtil.show(this.getUIContext(), '推荐失败，请重试', 1500);
      return;
    }
    let c: CoverContent = this.content.copy();
    c.quote = pick.quote;
    if (t.id === 'B2') {
      c.quoteSource = pick.source;
      c.subtitle = pick.extra;
    } else if (t.id === 'B3') {
      c.subtitle = pick.source;
    } else {
      c.quoteSource = pick.source;
    }
    this.content = c;
  }

  private resetPinyin(): void {
    let c: CoverContent = this.content.copy();
    c.pinyinLocked = false;
    c.pinyin = CoverContentUtil.autoPinyin(c.title);
    this.content = c;
    this.pyEditIndex = -1;
  }

  /** 生字拆字（与预览 cleanChars 一致：去空白，最多 8 字） */
  private titleChars(): string[] {
    let clean: string = this.content.title.replace(new RegExp('\\s', 'g'), '');
    return clean.substring(0, 8).split('');
  }

  private pySyllables(): string[] {
    return CoverContentUtil.syllables(this.content.pinyin);
  }

  /** 第 index 字的候选读音：当前值置顶（候选缺失时保底），后接多音字候选 */
  private pyCandidatesFor(index: number): string[] {
    let chars: string[] = this.titleChars();
    if (index < 0 || index >= chars.length) {
      return [];
    }
    let sys: string[] = this.pySyllables();
    let current: string = index < sys.length ? sys[index] : '';
    let cands: string[] = CoverContentUtil.pinyinCandidates(chars[index]);
    let out: string[] = [];
    if (current !== '' && cands.indexOf(current) < 0) {
      out.push(current);
    }
    for (let i = 0; i < cands.length; i++) {
      out.push(cands[i]);
    }
    return out;
  }

  private applyPinyinSyllable(index: number, value: string): void {
    let c: CoverContent = this.content.copy();
    c.pinyin = CoverContentUtil.replaceSyllable(c.pinyin, index, value);
    c.pinyinLocked = true;
    this.content = c;
  }

  private restoreFromHistory(r: CoverHistoryRecord): void {
    let t: CoverTemplate = CoverTemplates.getById(r.templateId);
    this.currentTemplateId = t.id;
    this.paletteIndex = r.paletteIndex;
    this.fontIndex = r.fontIndex;
    this.content = CoverContent.fromJson(r.textsJson);
    this.editorTab = 0;
    this.pyEditIndex = -1;
    ToastUtil.show(this.getUIContext(), '已恢复：' + t.name, 1200);
  }

  private clearHistory(): void {
    CoverHistoryStore.clearAll(this.context());
    this.historyRecords = [];
  }

  private canExport(): boolean {
    let t: CoverTemplate = this.currentTemplate();
    let c: CoverContent = this.content;
    if (t.slots.indexOf(CoverSlot.TITLE) >= 0 && c.title.trim() === '') {
      return false;
    }
    if (t.layout === 'b1_poem_vertical' || t.layout === 'b2_idiom' || t.layout === 'b3_xiehouyu') {
      if (c.quote.trim() === '') {
        return false;
      }
    }
    return true;
  }

  private titleTooLong(): boolean {
    let t: CoverTemplate = this.currentTemplate();
    if (t.slots.indexOf(CoverSlot.TITLE) < 0) {
      return false;
    }
    if (SINGLE_LINE_LAYOUTS.indexOf(t.layout) >= 0) {
      return this.content.title.length > 12;
    }
    return this.content.title.length > 20;
  }

  private async doExport(save: boolean): Promise<void> {
    if (!this.canExport() || this.exporting) {
      return;
    }
    this.exporting = true;
    try {
      await new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, 150);
      });
      let uiCtx: UIContext = this.getUIContext();
      let snapshot = uiCtx.getComponentSnapshot();
      let pixelMap: image.PixelMap =
        await snapshot.get(PREVIEW_ID, { scale: this.snapshotScale, waitUntilRenderFinished: true });
      let packer: image.ImagePacker = image.createImagePacker();
      let context: common.UIAbilityContext = this.context();
      let fileName: string = 'cover_' + Date.now() + '.png';
      let filePath: string = context.cacheDir + '/' + fileName;
      let file: fs.File = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        await packer.packToFile(pixelMap, file.fd, { format: 'image/png', quality: 100 });
      } finally {
        fs.closeSync(file.fd);
        packer.release();
      }
      let record: CoverHistoryRecord = CoverHistoryRecord.of(
        Date.now().toString(36) + Math.floor(Math.random() * 1000).toString(),
        CoverHistoryStore.makeFileName(), this.currentTemplateId, this.paletteIndex,
        this.fontIndex, this.content.toJson(), Date.now());
      if (CoverHistoryStore.saveRecord(context, filePath, record)) {
        this.historyRecords = CoverHistoryStore.loadRecords(context);
      }
      if (save) {
        let ok: boolean = await savePixelMapToAlbum(uiCtx, pixelMap);
        ToastUtil.show(uiCtx, ok ? '已保存到相册' : '已取消保存', 1500);
      } else {
        shareImageViaPanel(uiCtx, filePath);
      }
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[Cover] export failed: ' + err.code + ' ' + err.message);
      ToastUtil.show(this.getUIContext(), '导出失败：' + err.message, 2000);
    }
    this.exporting = false;
  }

  // ---------- 主题色 ----------

  private inputBg(): string {
    return this.isDark ? '#2A2A2C' : '#F5F5F5';
  }

  private labelColor(): string {
    return this.isDark ? '#AAAAAA' : '#666666';
  }

  private chipBg(): string {
    return this.isDark ? '#333336' : '#F2F2F2';
  }

  private chipText(): string {
    return this.isDark ? '#E0E0E0' : '#333333';
  }

  private lineColor(): string {
    return this.isDark ? '#3A3A3C' : '#E5E5E5';
  }

  // ---------- UI ----------

  build() {
    Column() {
      Scroll() {
        Column({ space: 14 }) {
          this.PreviewSection()
          this.SeriesChips()
          this.TemplateScroller()
          this.EditorTabs()
          if (this.editorTab === 0) {
            this.TextEditor()
          } else {
            this.StyleEditor()
          }
          this.HistorySection()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')

      this.ExportBar()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  PreviewSection() {
    Column({ space: 8 }) {
      Row() {
        Column() {
          CoverPreview({
            template: this.currentTemplate(),
            content: this.content,
            paletteIndex: this.paletteIndex,
            fontIndex: this.fontIndex,
            previewWidth: this.previewVp,
          })
        }
        .width(this.previewVp)
        .height(this.previewVp * 383 / 900)
        .clip(true)
        .id(PREVIEW_ID)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Text('公众号首图 900 × 383')
        .fontSize(11)
        .fontColor(this.labelColor())
      if (this.titleTooLong()) {
        Text('文案偏长，建议精简（当前标题 ' + this.content.title.length.toString() + ' 字）')
          .fontSize(11)
          .fontColor('#E5484D')
      }
    }
    .width('100%')
  }

  @Builder
  SeriesChips() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(CoverSeries.all(), (name: string) => {
          Text(name)
            .fontSize(13)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .backgroundColor(this.seriesFilter === name ? '#2E6FD6' : this.chipBg())
            .fontColor(this.seriesFilter === name ? '#FFFFFF' : this.chipText())
            .borderRadius(14)
            .onClick(() => {
              this.seriesFilter = name;
            })
        }, (name: string) => name)
      }
      .padding({ left: 2, right: 2 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  TemplateScroller() {
    List({ space: 10 }) {
      ForEach(CoverTemplates.getBySeries(this.seriesFilter), (t: CoverTemplate) => {
        ListItem() {
          Column({ space: 5 }) {
            Column() {
              Blank()
              Row({ space: 5 }) {
                Row()
                  .width(14)
                  .height(3)
                  .backgroundColor(t.palettes[0].accent)
                  .borderRadius(2)
                Text(t.name)
                  .fontSize(11)
                  .fontColor(t.palettes[0].title)
                  .maxLines(1)
              }
              .alignItems(VerticalAlign.Center)
              Blank()
            }
            .width(94)
            .height(52)
            .backgroundColor(t.palettes[0].bg)
            .borderRadius(6)
            .border({
              width: this.currentTemplateId === t.id ? 2 : 1,
              color: this.currentTemplateId === t.id ? '#2E6FD6' : this.lineColor(),
            })
            .onClick(() => {
              this.selectTemplate(t);
            })

            Text(t.series + ' · ' + t.id)
              .fontSize(9)
              .fontColor(this.currentTemplateId === t.id ? '#2E6FD6' : this.labelColor())
          }
          .alignItems(HorizontalAlign.Center)
        }
      }, (t: CoverTemplate) => t.id + this.seriesFilter)
    }
    .listDirection(Axis.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(82)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  EditorTabs() {
    Row({ space: 0 }) {
      Text('文字')
        .fontSize(14)
        .fontWeight(this.editorTab === 0 ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.editorTab === 0 ? '#2E6FD6' : this.labelColor())
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .onClick(() => {
          this.editorTab = 0;
        })
      Text('样式')
        .fontSize(14)
        .fontWeight(this.editorTab === 1 ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.editorTab === 1 ? '#2E6FD6' : this.labelColor())
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .onClick(() => {
          this.editorTab = 1;
        })
    }
    .width('100%')
    .border({ width: { bottom: 1 }, color: this.lineColor() })
  }

  @Builder
  TextEditor() {
    Column({ space: 12 }) {
      if (this.currentTemplate().contentKind !== '') {
        Row() {
          Text('内容库推荐（诗词 / 成语 / 歇后语）')
            .fontSize(12)
            .fontColor(this.labelColor())
            .layoutWeight(1)
          Text('换一句')
            .fontSize(13)
            .fontColor('#2E6FD6')
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .backgroundColor('#1A2E6FD6')
            .borderRadius(14)
            .onClick(() => {
              this.changeQuote();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      ForEach(this.currentTemplate().slots, (slot: string) => {
        Column({ space: 5 }) {
          Text(this.slotLabel(slot))
            .fontSize(12)
            .fontColor(this.labelColor())
          if (slot === CoverSlot.PINYIN) {
            this.PinyinSyllableEditor()
          } else {
            TextInput({ text: this.slotValue(slot) })
              .height(40)
              .fontSize(14)
              .maxLength(this.slotMaxLength(slot))
              .backgroundColor(this.inputBg())
              .borderRadius(8)
              .onChange((value: string) => {
                this.onSlotChange(slot, value);
              })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }, (slot: string) => slot + this.currentTemplateId)
    }
    .width('100%')
    .padding({ top: 12 })
  }

  /** B5 拼音编辑：逐字音节 chips（点击展开该字候选读音选择），音节数=字数时可用 */
  @Builder
  PinyinSyllableEditor() {
    Column({ space: 8 }) {
      if (this.titleChars().length > 0 && this.pySyllables().length === this.titleChars().length) {
        Row({ space: 6 }) {
          ForEach(this.titleChars(), (ch: string, idx: number) => {
            Column({ space: 2 }) {
              Text(ch)
                .fontSize(16)
                .fontColor(this.pyEditIndex === idx ? '#2E6FD6' : this.chipText())
              Text(this.pySyllables()[idx])
                .fontSize(11)
                .maxFontSize(11)
                .minFontSize(7)
                .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
                .fontColor(this.pyEditIndex === idx ? '#2E6FD6' : this.labelColor())
                .maxLines(1)
            }
            .layoutWeight(1)
            .padding({ top: 6, bottom: 6 })
            .borderRadius(8)
            .backgroundColor(this.pyEditIndex === idx ? '#1A2E6FD6' : this.inputBg())
            .border({
              width: this.pyEditIndex === idx ? 1 : 0,
              color: '#2E6FD6',
            })
            .onClick(() => {
              this.pyEditIndex = this.pyEditIndex === idx ? -1 : idx;
            })
          }, (ch: string, idx: number) => ch + idx.toString() + this.pyEditIndex.toString() + this.content.pinyin)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.pyEditIndex >= 0 && this.pyEditIndex < this.pySyllables().length) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.pyCandidatesFor(this.pyEditIndex), (cand: string) => {
              Text(cand)
                .fontSize(13)
                .fontColor(cand === this.pySyllables()[this.pyEditIndex] ? '#FFFFFF' : '#2E6FD6')
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor(cand === this.pySyllables()[this.pyEditIndex] ? '#2E6FD6' : '#1A2E6FD6')
                .borderRadius(13)
                .margin(4)
                .onClick(() => {
                  this.applyPinyinSyllable(this.pyEditIndex, cand);
                })
            }, (cand: string, ci: number) => cand + ci.toString() + this.pyEditIndex.toString())
          }
          .width('100%')
        }

        if (this.content.pinyinLocked) {
          Row() {
            Text('已手动选择读音')
              .fontSize(11)
              .fontColor(this.labelColor())
              .layoutWeight(1)
            Text('恢复自动')
              .fontSize(12)
              .fontColor('#2E6FD6')
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor('#1A2E6FD6')
              .borderRadius(12)
              .onClick(() => {
                this.resetPinyin();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
      } else {
        Text(this.content.pinyin === '' ? '（输入生字后自动生成拼音）' : this.content.pinyin)
          .fontSize(13)
          .fontColor(this.labelColor())
          .width('100%')
          .padding({ left: 4, right: 4 })
          .onClick(() => {
            if (this.content.pinyinLocked) {
              this.resetPinyin();
            }
          })
        if (this.content.pinyinLocked) {
          Row() {
            Text('拼音与字数不一致，已暂停逐字编辑')
              .fontSize(11)
              .fontColor(this.labelColor())
              .layoutWeight(1)
            Text('恢复自动')
              .fontSize(12)
              .fontColor('#2E6FD6')
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor('#1A2E6FD6')
              .borderRadius(12)
              .onClick(() => {
                this.resetPinyin();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
      }
    }
    .width('100%')
  }

  @Builder
  StyleEditor() {
    Column({ space: 16 }) {
      PaletteSection({
        palettes: this.currentTemplate().palettes,
        selectedIndex: this.paletteIndex,
        accentColor: '#2E6FD6',
        labelColor: this.labelColor(),
        onSelect: (idx: number) => {
          this.paletteIndex = idx;
        },
      })

      Column({ space: 10 }) {
        Text('字体')
          .fontSize(12)
          .fontColor(this.labelColor())
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.currentTemplate().fonts, (f: string, idx: number) => {
            Text(CoverFont.label(f))
              .fontSize(13)
              .fontFamily(f)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .backgroundColor(this.fontIndex === idx ? '#2E6FD6' : this.chipBg())
              .fontColor(this.fontIndex === idx ? '#FFFFFF' : this.chipText())
              .borderRadius(14)
              .margin(4)
              .onClick(() => {
                this.fontIndex = idx;
              })
          }, (f: string, idx: number) => f + idx.toString())
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 12 })
  }

  @Builder
  HistorySection() {
    if (this.historyRecords.length > 0) {
      Column({ space: 8 }) {
        Row() {
          Text('最近制作')
            .fontSize(12)
            .fontColor(this.labelColor())
            .layoutWeight(1)
          Text('清空')
            .fontSize(12)
            .fontColor(this.labelColor())
            .padding(6)
            .onClick(() => {
              this.clearHistory();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        List({ space: 10 }) {
          ForEach(this.historyRecords, (r: CoverHistoryRecord) => {
            ListItem() {
              Column({ space: 4 }) {
                Image('file://' + CoverHistoryStore.filePath(this.context(), r.fileName))
                  .width(94)
                  .height(40)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(4)
                  .border({ width: 1, color: this.lineColor() })
                Text(CoverTemplates.getById(r.templateId).name)
                  .fontSize(10)
                  .fontColor(this.labelColor())
                  .maxLines(1)
              }
              .alignItems(HorizontalAlign.Center)
              .onClick(() => {
                this.restoreFromHistory(r);
              })
            }
          }, (r: CoverHistoryRecord) => r.id)
        }
        .listDirection(Axis.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .height(68)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .padding({ top: 8 })
      .border({ width: { top: 1 }, color: this.lineColor() })
    }
  }

  @Builder
  ExportBar() {
    Row({ space: 12 }) {
      Button(this.exporting ? '导出中…' : '保存到相册')
        .layoutWeight(1)
        .height(44)
        .fontSize(15)
        .backgroundColor('#2E6FD6')
        .enabled(this.canExport() && !this.exporting)
        .onClick(() => {
          this.doExport(true);
        })
      Button('分享')
        .layoutWeight(1)
        .height(44)
        .fontSize(15)
        .backgroundColor(this.chipBg())
        .fontColor(this.chipText())
        .enabled(this.canExport() && !this.exporting)
        .onClick(() => {
          this.doExport(false);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 12 })
    .border({ width: { top: 1 }, color: this.lineColor() })
  }
}
