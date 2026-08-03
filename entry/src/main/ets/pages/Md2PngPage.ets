import { TemplateInfo, Md2PngTemplates, HighlightKeyword, HighlightStats, HighlightResult, KeywordOccurrenceContext } from '../model/Md2PngModels';
import { image } from '@kit.ImageKit';
import { fileIo as fs, WriteOptions, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { Markdown, MarkdownController } from '@luvi/lv-markdown-in';
import { display } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { DecorPatternUtil } from '../common/utils/DecorPatternUtil';
import { shareImageViaPanel } from '../common/utils/ShareImageUtil';
import { KeywordUtil } from '../common/utils/KeywordUtil';
import { FontUtil } from '../common/utils/FontUtil';

const PREF_NAME: string = 'md2png_settings';
const KEY_HIGHLIGHT_CONFIG: string = 'highlight_config';

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
    let inlineCodeColor: string = isDark ? tpl.accentColor : tpl.headerColor;
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
      .setInlineCodeColor(inlineCodeColor)
      .setInlineCodeBackgroundColor(tpl.highlightBgColor || tpl.codeBgColor)
      .setInlineCodeBackgroundRadius(3)
      .setCodeBlockTheme(isDark ? 'dark' : 'light')
      .setCodeBlockBorderRadius(6)
      .setUlPointColor(tpl.accentColor)
      .setLineColor(tpl.accentColor)
      .setHyperlinkTextColor(tpl.accentColor)
      .setHtmlPreviewEnable(true)
      .setBlockSpacing(6)
      ;
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
  private cachedPixelMap: image.PixelMap | undefined = undefined;
  @State currentAccentColor: string = '#3182ce';
  // 当前生效的高亮关键字列表（auto + manual，按 source 字段区分）
  @State highlightKeywords: HighlightKeyword[] = [];
  @State keywordVersion: number = 0;
  @State highlightedTexts: string[] = [];
  // 用户主动移除的关键字黑名单（仅对 auto 提取有效，避免下次又被自动加回）
  @State removedKeywords: string[] = [];
  // 用户是否手动编辑过高亮词（添加/移除/调整位置），用于决定是否弹窗询问覆盖
  @State userEditedKeywords: boolean = false;
  // 关键字出现次数统计（用于 UI 显示 ·N）
  @State keywordStats: HighlightStats[] = [];
  @State isExtractingKeywords: boolean = false;
  @State customKeyword: string = '';
  // 位置选择浮层状态
  @State showPositionPanel: boolean = false;
  @State editingWord: string = '';
  @State editingWordOccurrences: KeywordOccurrenceContext[] = [];
  @State editingWordSelectedIndices: number[] = [];
  @State editingWordSource: string = 'auto';
  /** 位置面板是否有未保存的修改 */
  private positionPanelDirty: boolean = false;
  /** 高亮配置是否已从存储恢复 */
  private highlightConfigRestored: boolean = false;
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
  private generateTimer: number = -1;
  private readonly markdownExample: string = '# 欢迎使用文字转图片\n\n输入 **Markdown** 或普通文本，选择喜欢的模板，一键生成精美图片！\n\n## 功能特点\n\n- 支持多种精美模板\n- 支持Markdown语法\n- 一键保存到相册\n\n> 让文字更有表现力\n\n`代码片段` 也能高亮显示';
  private readonly textExample: string = '今天天气真好，阳光明媚，微风不燥。\n出门走走，看花开花落，心情格外舒畅。\n把生活里的美好，藏进最平凡的句子。';

  aboutToAppear(): void {
    this.inputText = '';
    this.currentAccentColor = this.templates[this.currentTemplateIndex].accentColor;
    FontUtil.registerAll(this.getUIContext());
    this.initAllControllers();
    this.calcCardSize();
    this.loadHighlightConfig();
    let heights: number[] = [];
    let texts: string[] = [];
    for (let i: number = 0; i < this.templates.length; i++) {
      heights.push(this.dynamicMinCardHeight);
      texts.push('');
    }
    this.cardHeights = heights;
    this.highlightedTexts = texts;
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
      this.dynamicTextSize = 22;
      this.dynamicTitleSize = [34, 30, 26, 24, 22, 20];
      this.dynamicLineHeight = 36;
      this.dynamicPaddingLeft = 32;
      this.dynamicPaddingRight = 32;
      this.dynamicPaddingTop = 28;
      this.dynamicPaddingBottom = 28;
      this.cardWidth = Math.min(this.baseCardWidth, 280);
      this.dynamicMinCardHeight = Math.max(this.cardWidth + 40, 320);
    } else if (len <= 80) {
      this.dynamicTextSize = 21;
      this.dynamicTitleSize = [32, 28, 24, 22, 20, 18];
      this.dynamicLineHeight = 34;
      this.dynamicPaddingLeft = 30;
      this.dynamicPaddingRight = 30;
      this.dynamicPaddingTop = 26;
      this.dynamicPaddingBottom = 26;
      this.cardWidth = Math.min(this.baseCardWidth, 300);
      this.dynamicMinCardHeight = Math.max(Math.floor(this.cardWidth * 0.9), 280);
    } else if (len <= 200) {
      this.dynamicTextSize = 20;
      this.dynamicTitleSize = [30, 26, 22, 20, 18, 17];
      this.dynamicLineHeight = 32;
      this.dynamicPaddingLeft = 28;
      this.dynamicPaddingRight = 28;
      this.dynamicPaddingTop = 24;
      this.dynamicPaddingBottom = 24;
      this.cardWidth = Math.min(this.baseCardWidth, 320);
      this.dynamicMinCardHeight = Math.max(Math.floor(this.cardWidth * 0.8), 260);
    } else if (len <= 500) {
      this.dynamicTextSize = 18;
      this.dynamicTitleSize = [26, 23, 20, 18, 16, 15];
      this.dynamicLineHeight = 28;
      this.dynamicPaddingLeft = 24;
      this.dynamicPaddingRight = 24;
      this.dynamicPaddingTop = 20;
      this.dynamicPaddingBottom = 20;
      this.cardWidth = this.baseCardWidth;
      this.dynamicMinCardHeight = Math.max(Math.floor(this.cardWidth * 0.7), 240);
    } else {
      this.dynamicTextSize = 17;
      this.dynamicTitleSize = [24, 21, 19, 17, 15, 14];
      this.dynamicLineHeight = 26;
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
    for (let i = 0; i < this.highlightKeywords.length; i++) {
      if (this.highlightKeywords[i].word === kw) {
        this.getUIContext().getPromptAction().showToast({ message: '该词已在高亮列表中', duration: 1000 });
        this.customKeyword = '';
        return;
      }
    }
    let newKw: HighlightKeyword = new HighlightKeyword(kw, 'manual', [0]);
    let newArr: HighlightKeyword[] = [];
    for (let i = 0; i < this.highlightKeywords.length; i++) {
      newArr.push(this.highlightKeywords[i]);
    }
    newArr.push(newKw);
    this.highlightKeywords = newArr;
    this.removeFromRemovedList(kw);
    this.userEditedKeywords = true;
    this.customKeyword = '';
    this.computeKeywordStats();
    this.refreshHighlightedTexts();
    this.generateImage();
    this.saveHighlightConfig();
  }

  /**
   * 重置所有高亮词：清除手动添加和自动提取的关键词、黑名单，重新提取
   */
  private resetHighlightWords(): void {
    this.highlightKeywords = [];
    this.removedKeywords = [];
    this.userEditedKeywords = false;
    this.keywordStats = [];
    this.highlightedTexts = [];
    this.keywordVersion++;
    this.saveHighlightConfig();
    // 重新触发自动提取
    this.scheduleRegenerate();
  }

  private removeFromRemovedList(word: string): void {
    let newArr: string[] = [];
    for (let i = 0; i < this.removedKeywords.length; i++) {
      if (this.removedKeywords[i] !== word) {
        newArr.push(this.removedKeywords[i]);
      }
    }
    this.removedKeywords = newArr;
  }

  private removeKeyword(word: string): void {
    let newArr: HighlightKeyword[] = [];
    let removedSource: string = '';
    for (let i = 0; i < this.highlightKeywords.length; i++) {
      if (this.highlightKeywords[i].word !== word) {
        newArr.push(this.highlightKeywords[i]);
      } else {
        removedSource = this.highlightKeywords[i].source;
      }
    }
    this.highlightKeywords = newArr;
    if (removedSource === 'auto') {
      let newRemoved: string[] = [];
      for (let i = 0; i < this.removedKeywords.length; i++) {
        newRemoved.push(this.removedKeywords[i]);
      }
      newRemoved.push(word);
      this.removedKeywords = newRemoved;
    }
    this.userEditedKeywords = true;
    this.computeKeywordStats();
    this.refreshHighlightedTexts();
    this.generateImage();
    this.saveHighlightConfig();
  }

  /**
   * 打开位置选择浮层，加载该关键字在当前文本中的所有出现位置
   */
  private openPositionPanel(word: string): void {
    let occurrences: KeywordOccurrenceContext[] = KeywordUtil.findOccurrences(this.inputText, word, 8);
    let selectedIndices: number[] = [];
    for (let i = 0; i < this.highlightKeywords.length; i++) {
      if (this.highlightKeywords[i].word === word) {
        selectedIndices = this.highlightKeywords[i].selectedIndices;
        this.editingWordSource = this.highlightKeywords[i].source;
        break;
      }
    }
    this.editingWord = word;
    this.editingWordOccurrences = occurrences;
    this.editingWordSelectedIndices = selectedIndices;
    this.positionPanelDirty = false;
    this.showPositionPanel = true;
  }

  /**
   * 关闭位置选择面板
   * @param skipDirtyCheck 跳过脏状态确认（用于"移除该词"等操作）
   */
  private closePositionPanel(skipDirtyCheck: boolean = false): void {
    if (this.positionPanelDirty && !skipDirtyCheck) {
      let uiCtx = this.getUIContext();
      uiCtx.getPromptAction().showDialog({
        title: '放弃修改？',
        message: '当前的位置选择尚未保存，是否放弃修改？',
        buttons: [
          { text: '继续编辑', color: '#666666' },
          { text: '放弃', color: '#dc2626' },
        ]
      }).then((result: Record<string, number>) => {
        if (result && result.index === 1) {
          this.showPositionPanel = false;
          this.positionPanelDirty = false;
        }
      });
    } else {
      this.showPositionPanel = false;
      this.positionPanelDirty = false;
    }
  }

  /**
   * 切换某个出现位置的选中状态
   */
  private toggleOccurrence(index: number): void {
    let newArr: number[] = [];
    let exists: boolean = false;
    for (let i = 0; i < this.editingWordSelectedIndices.length; i++) {
      if (this.editingWordSelectedIndices[i] === index) {
        exists = true;
      } else {
        newArr.push(this.editingWordSelectedIndices[i]);
      }
    }
    if (!exists) {
      newArr.push(index);
      newArr.sort((a: number, b: number) => a - b);
    }
    this.editingWordSelectedIndices = newArr;
    this.positionPanelDirty = true;
  }

  private applyEditingWordIndices(): void {
    let newArr: HighlightKeyword[] = [];
    for (let i = 0; i < this.highlightKeywords.length; i++) {
      if (this.highlightKeywords[i].word === this.editingWord) {
        newArr.push(new HighlightKeyword(
          this.highlightKeywords[i].word,
          this.highlightKeywords[i].source,
          this.editingWordSelectedIndices.slice()
        ));
      } else {
        newArr.push(this.highlightKeywords[i]);
      }
    }
    this.highlightKeywords = newArr;
    this.keywordVersion++;
    this.userEditedKeywords = true;
    this.computeKeywordStats();
    this.refreshHighlightedTexts();
  }

  private confirmEditingWord(): void {
    this.applyEditingWordIndices();
    this.positionPanelDirty = false;  // 已确认保存，清除脏标记
    this.closePositionPanel();
    this.generateImage();
    this.saveHighlightConfig();
  }

  private selectAllOccurrences(): void {
    let all: number[] = [];
    for (let i = 0; i < this.editingWordOccurrences.length; i++) {
      all.push(i);
    }
    this.editingWordSelectedIndices = all;
    this.positionPanelDirty = true;
  }

  private selectNoneOccurrences(): void {
    this.editingWordSelectedIndices = [];
    this.positionPanelDirty = true;
  }

  /**
   * 计算所有关键字在当前文本中的出现次数统计，用于 UI 显示
   */
  private computeKeywordStats(): void {
    let stats: HighlightStats[] = [];
    for (let i = 0; i < this.highlightKeywords.length; i++) {
      let kw: HighlightKeyword = this.highlightKeywords[i];
      let occ: number = KeywordUtil.countOccurrences(this.inputText, kw.word);
      let highlighted: number = 0;
      for (let k = 0; k < kw.selectedIndices.length; k++) {
        if (kw.selectedIndices[k] >= 0 && kw.selectedIndices[k] < occ) {
          highlighted++;
        }
      }
      stats.push(new HighlightStats(kw.word, occ, highlighted));
    }
    this.keywordStats = stats;
  }

  /**
   * 根据当前 inputText 截断各关键字中超出范围的 selectedIndices
   * 用于"保留当前高亮词"分支：文本变化后位置序号可能失效
   */
  private trimSelectedIndices(): void {
    let newArr: HighlightKeyword[] = [];
    for (let i = 0; i < this.highlightKeywords.length; i++) {
      let kw: HighlightKeyword = this.highlightKeywords[i];
      let occ: number = KeywordUtil.countOccurrences(this.inputText, kw.word);
      let newIndices: number[] = [];
      for (let k = 0; k < kw.selectedIndices.length; k++) {
        if (kw.selectedIndices[k] >= 0 && kw.selectedIndices[k] < occ) {
          newIndices.push(kw.selectedIndices[k]);
        }
      }
      // 若全部超出范围且仍有出现，降级为首次出现
      if (newIndices.length === 0 && occ > 0) {
        newIndices = [0];
      }
      newArr.push(new HighlightKeyword(kw.word, kw.source, newIndices));
    }
    this.highlightKeywords = newArr;
    this.computeKeywordStats();
    this.refreshHighlightedTexts();
  }

  /**
   * 弹窗询问用户是否用新提取结果覆盖已编辑的高亮词
   */
  private showOverwriteConfirmDialog(): void {
    this.getUIContext().showAlertDialog({
      title: '已手动调整过高亮词',
      message: '检测到当前高亮词已被手动调整。是否用新文本的提取结果覆盖？\n\n点击外部空白处取消（保持当前高亮词不变）。',
      primaryButton: {
        value: '保留当前（推荐）',
        action: () => {
          // 保留列表，基于新文本重新匹配位置，截断超出的 selectedIndices
          this.trimSelectedIndices();
          this.userEditedKeywords = true;
          this.generateImage();
          this.saveHighlightConfig();
        }
      },
      secondaryButton: {
        value: '用新结果覆盖',
        action: () => {
          this.userEditedKeywords = false;
          this.doExtractAndApply();
        }
      }
    });
  }

  private async regenerateImageOnly(): Promise<void> {
    if (!this.inputText || this.inputText.trim().length === 0) {
      this.generatedImageUri = '';
      return;
    }
    this.calcDynamicStyle();
    this.initAllControllers();
    this.computeKeywordStats();
    this.refreshHighlightedTexts();
    this.generateImage();
  }

  private async extractAndGenerate(): Promise<void> {
    if (!this.inputText || this.inputText.trim().length === 0) {
      this.highlightKeywords = [];
      this.removedKeywords = [];
      this.userEditedKeywords = false;
      this.keywordStats = [];
      this.highlightedTexts = [];
      this.generatedImageUri = '';
      this.saveHighlightConfig();
      return;
    }
    this.calcDynamicStyle();
    this.initAllControllers();
    // 若用户已手动编辑过高亮词，弹窗询问是否覆盖
    if (this.userEditedKeywords && this.highlightKeywords.length > 0) {
      this.showOverwriteConfirmDialog();
      return;
    }
    await this.doExtractAndApply();
  }

  /**
   * 执行自动提取并应用到 highlightKeywords（保留 manual 关键字，过滤黑名单）
   */
  private async doExtractAndApply(): Promise<void> {
    this.isExtractingKeywords = true;
    try {
      let topN: number = this.getKeywordTopN();
      let keywords: string[] = await KeywordUtil.extractKeywords(this.inputText, topN);
      // 保留 manual 关键字
      let manualList: HighlightKeyword[] = [];
      for (let i = 0; i < this.highlightKeywords.length; i++) {
        if (this.highlightKeywords[i].source === 'manual') {
          manualList.push(this.highlightKeywords[i]);
        }
      }
      // 新提取的 auto 关键字（过滤黑名单 + 已在 manual 中的去重）
      let autoList: HighlightKeyword[] = [];
      let existingWords: Set<string> = new Set<string>();
      for (let i = 0; i < manualList.length; i++) {
        existingWords.add(manualList[i].word);
      }
      for (let i = 0; i < keywords.length; i++) {
        let w: string = keywords[i];
        if (existingWords.has(w)) {
          continue;
        }
        let isRemoved: boolean = false;
        for (let r = 0; r < this.removedKeywords.length; r++) {
          if (this.removedKeywords[r] === w) {
            isRemoved = true;
            break;
          }
        }
        if (isRemoved) {
          continue;
        }
        autoList.push(new HighlightKeyword(w, 'auto', [0]));
        existingWords.add(w);
      }
      let combined: HighlightKeyword[] = [];
      for (let i = 0; i < manualList.length; i++) {
        combined.push(manualList[i]);
      }
      for (let i = 0; i < autoList.length; i++) {
        combined.push(autoList[i]);
      }
      this.highlightKeywords = combined;
    } catch (e) {
      let manualList: HighlightKeyword[] = [];
      for (let i = 0; i < this.highlightKeywords.length; i++) {
        if (this.highlightKeywords[i].source === 'manual') {
          manualList.push(this.highlightKeywords[i]);
        }
      }
      this.highlightKeywords = manualList;
    }
    this.isExtractingKeywords = false;
    this.computeKeywordStats();
    this.refreshHighlightedTexts();
    this.generateImage();
    this.saveHighlightConfig();
  }

  private generateImage(): void {
    if (this.generateTimer !== -1) {
      clearTimeout(this.generateTimer);
    }
    this.generateTimer = setTimeout(() => {
      this.generateTimer = -1;
      this.doGenerateImage();
    }, 300);
  }

  private async doGenerateImage(): Promise<void> {
    if (!this.inputText || this.inputText.trim().length === 0) {
      this.generatedImageUri = '';
      return;
    }
    this.isGenerating = true;
    try {
      await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 200); });
      let uiCtx: UIContext = this.getUIContext();
      let snapshot = uiCtx.getComponentSnapshot();
      let tpl: TemplateInfo = this.templates[this.currentTemplateIndex];
      let cardId: string = 'md_card_' + tpl.id;
      let pixelMap: image.PixelMap = await snapshot.get(cardId, { scale: 2, waitUntilRenderFinished: true });
      let packer: image.ImagePacker = image.createImagePacker();
      let packOpts: image.PackingOption = {
        format: 'image/png',
        quality: 100
      };
      let context: common.UIAbilityContext = uiCtx.getHostContext() as common.UIAbilityContext;
      let dir: string = context.cacheDir;
      let fileName: string = 'md2png_' + Date.now() + '.png';
      let filePath: string = dir + '/' + fileName;
      let file: fs.File = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        await packer.packToFile(pixelMap, file.fd, packOpts);
        this.cachedPixelMap = pixelMap;
      } finally {
        fs.closeSync(file.fd);
        packer.release();
      }
      this.generatedImageUri = file.path;
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[Md2Png] generate failed: ' + err.message);
      this.getUIContext().getPromptAction().showToast({ message: '生成失败', duration: 2000 });
    }
    this.isGenerating = false;
  }

  private getHighlightedText(index: number): string {
    if (index >= 0 && index < this.highlightedTexts.length) {
      return this.highlightedTexts[index];
    }
    return this.inputText;
  }

  private refreshHighlightedTexts(): void {
    let texts: string[] = [];
    for (let i = 0; i < this.templates.length; i++) {
      let tpl: TemplateInfo = this.templates[i];
      let isDark: boolean = this.isDarkBgColor(tpl.bgColor);
      let highlightTextColor: string = isDark ? tpl.accentColor : tpl.headerColor;
      let result: HighlightResult = KeywordUtil.highlightText(
        this.inputText, this.highlightKeywords, tpl.highlightFont, highlightTextColor, tpl.highlightBgColor
      );
      texts.push(result.text);
    }
    this.highlightedTexts = texts;
  }

  private isDarkBgColor(color: string): boolean {
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

  private getHighlightTagBgColor(): string {
    let tpl: TemplateInfo = this.templates[this.currentTemplateIndex];
    let bg: string = tpl.highlightBgColor;
    if (bg && bg.length > 0) {
      return bg;
    }
    return this.currentAccentColor + '18';
  }

  private getHighlightTagTextColor(): string {
    let tpl: TemplateInfo = this.templates[this.currentTemplateIndex];
    let isDark: boolean = this.isDarkBgColor(tpl.bgColor);
    if (isDark) {
      return tpl.accentColor;
    }
    return tpl.headerColor;
  }

  /**
   * 查询某个关键字的统计信息（出现次数、已高亮次数）
   */
  private getKeywordStats(word: string): HighlightStats {
    for (let i = 0; i < this.keywordStats.length; i++) {
      if (this.keywordStats[i].word === word) {
        return this.keywordStats[i];
      }
    }
    return new HighlightStats(word, 0, 0);
  }

  /**
   * 格式化选中的出现序号为显示文本，如 [0,2] -> "(1,3)"
   */
  private formatSelectedIndices(indices: number[]): string {
    if (indices.length === 0) {
      return '';
    }
    let parts: string[] = [];
    for (let i = 0; i < indices.length; i++) {
      parts.push((indices[i] + 1).toString());
    }
    return '(' + parts.join(',') + ')';
  }

  private async saveToAlbum(): Promise<void> {
    let pixelMap: image.PixelMap | undefined = this.cachedPixelMap;
    if (!pixelMap) {
      this.getUIContext().getPromptAction().showToast({ message: '请先生成图片', duration: 1500 });
      return;
    }
    let uiCtx: UIContext = this.getUIContext();
    try {
      let context: common.UIAbilityContext = uiCtx.getHostContext() as common.UIAbilityContext;
      let dir: string = context.cacheDir;
      let fileName: string = 'save_tmp_' + Date.now() + '.png';
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
      let helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      let srcFileUri: string = fileUri.getUriFromPath(filePath);
      let srcFileUris: Array<string> = [srcFileUri];
      let photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [{
        title: 'md2png_' + Date.now(),
        fileNameExtension: 'png',
        photoType: photoAccessHelper.PhotoType.IMAGE,
      }];
      let desFileUris: Array<string> = await helper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs);
      if (desFileUris.length > 0) {
        let srcFile: fs.File = await fs.open(filePath, fs.OpenMode.READ_ONLY);
        let desFile: fs.File = await fs.open(desFileUris[0], fs.OpenMode.WRITE_ONLY);
        await fs.copyFile(srcFile.fd, desFile.fd);
        await fs.close(srcFile);
        await fs.close(desFile.fd);
        uiCtx.getPromptAction().showToast({ message: '已保存到相册', duration: 1000 });
      }
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[Md2Png] save failed: ' + err.code + ' ' + err.message);
      uiCtx.getPromptAction().showToast({ message: '保存失败', duration: 2000 });
    }
  }

  private doShare(): void {
    if (!this.generatedImageUri) {
      return;
    }
    shareImageViaPanel(this.getUIContext(), this.generatedImageUri);
  }

  /**
   * 持久化保存高亮词配置
   */
  private saveHighlightConfig(): void {
    try {
      let context: common.Context = this.getUIContext().getHostContext()!;
      let pref: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_NAME });
      let config: Record<string, Object> = {
        'keywords': JSON.stringify(this.highlightKeywords),
        'removed': JSON.stringify(this.removedKeywords),
        'userEdited': this.userEditedKeywords,
      };
      pref.putSync(KEY_HIGHLIGHT_CONFIG, JSON.stringify(config));
      pref.flush();
      console.info('[Md2Png] highlight config saved');
    } catch (e) {
      console.warn('[Md2Png] saveHighlightConfig failed: ' + JSON.stringify(e));
    }
  }

  /**
   * 从持久化存储恢复高亮词配置
   */
  private loadHighlightConfig(): void {
    try {
      let context: common.Context = this.getUIContext().getHostContext()!;
      let pref: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_NAME });
      let raw: string = pref.getSync(KEY_HIGHLIGHT_CONFIG, '') as string;
      if (!raw || raw.length === 0) {
        return;
      }
      let config: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      if (config['keywords']) {
        let keywords: HighlightKeyword[] = JSON.parse(config['keywords'] as string) as HighlightKeyword[];
        if (keywords && keywords.length > 0) {
          this.highlightKeywords = keywords;
          this.highlightConfigRestored = true;
        }
      }
      if (config['removed']) {
        let removed: string[] = JSON.parse(config['removed'] as string) as string[];
        if (removed && removed.length > 0) {
          this.removedKeywords = removed;
        }
      }
      if (config['userEdited'] !== undefined) {
        this.userEditedKeywords = Boolean(config['userEdited']);
      }
      console.info('[Md2Png] highlight config restored, keywords: ' + this.highlightKeywords.length);
    } catch (e) {
      console.warn('[Md2Png] loadHighlightConfig failed: ' + JSON.stringify(e));
    }
  }

  build() {
    Stack() {
      Column() {
        this.InputSection()

        if (this.highlightKeywords.length > 0 || this.inputText.trim().length > 0) {
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

      if (this.showPositionPanel) {
        this.PositionPanel()
      }
    }
    .width('100%')
    .height('100%')
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
        // 快捷操作按钮
        Text('重置')
          .fontSize(12)
          .fontColor($r('app.color.idiom_blue'))
          .margin({ left: 12 })
          .onClick(() => {
            this.resetHighlightWords();
          })
        Blank()
        Text('轻点词调整位置  \u00D7移除')
          .fontSize(11)
          .fontColor($r('app.color.hint_text'))
      }
      .width('100%')
      .margin({ bottom: 8 })

      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        // 添加高亮词输入行
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

        ForEach(this.highlightKeywords, (kw: HighlightKeyword) => {
          Row() {
            // 点击词文本区域：打开位置选择面板
            Row() {
              if (kw.source === 'manual') {
                Text('\u2605')  // ★ 用户自定义标记
                  .fontSize(11)
                  .fontColor(this.getHighlightTagTextColor())
                  .margin({ right: 3 })
              }
              Text(kw.word)
                .fontSize(13)
                .fontColor(this.getHighlightTagTextColor())
                .fontWeight(FontWeight.Medium)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 120 })
              // 出现次数徽标（单次出现时不显示）
              if (this.buildOccurrenceBadge(kw.word).length > 0) {
                Text(this.buildOccurrenceBadge(kw.word))
                  .fontSize(11)
                  .fontColor(this.getHighlightTagTextColor())
                  .margin({ left: 4 })
              }
            }
            .onClick(() => {
              this.openPositionPanel(kw.word);
            })

            // × 移除按钮
            Text(' \u00D7')
              .fontSize(14)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ left: 2 })
              .onClick(() => {
                this.removeKeyword(kw.word);
              })
          }
          .backgroundColor(this.getHighlightTagBgColor())
          .borderRadius(14)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .margin({ right: 6, bottom: 6 })
          .alignItems(VerticalAlign.Center)
        }, (kw: HighlightKeyword) => kw.word + '_' + kw.source + '_' + this.keywordVersion.toString())
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.page_background'))
  }

  /**
   * 构建关键字出现次数与选中位置的徽标文本
   * - 无出现：'·0'（灰色提示）
   * - 单次出现：''（空串，不显示徽标）
   * - 多次出现：'·N (1,3)' 显示总数和选中的位置序号
   */
  private buildOccurrenceBadge(word: string): string {
    let stats: HighlightStats = this.getKeywordStats(word);
    let occ: number = stats.occurrences;
    if (occ === 0) {
      return '·0';
    }
    if (occ === 1) {
      return '';
    }
    // 查找该关键字的 selectedIndices
    let indices: number[] = [];
    for (let i = 0; i < this.highlightKeywords.length; i++) {
      if (this.highlightKeywords[i].word === word) {
        indices = this.highlightKeywords[i].selectedIndices;
        break;
      }
    }
    // 计算有效选中的序号（截断到 occ 范围内）
    let validSelected: number[] = [];
    for (let i = 0; i < indices.length; i++) {
      if (indices[i] >= 0 && indices[i] < occ) {
        validSelected.push(indices[i]);
      }
    }
    let badge: string = '·' + occ.toString();
    // 多次出现且选中了部分位置时，显示具体序号
    if (validSelected.length > 0) {
      badge += ' ' + this.formatSelectedIndices(validSelected);
    }
    return badge;
  }

  /**
   * 位置选择浮层：显示关键字在文本中的所有出现位置，支持勾选要高亮的位置
   */
  @Builder
  PositionPanel() {
    Stack() {
      // 半透明遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.4)')
        .onClick(() => {
          this.closePositionPanel();
        })

      // 面板内容
      Column() {
        // 标题行
        Row() {
          Text(this.editingWord)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 160 })
          Text('  共 ' + this.editingWordOccurrences.length.toString() + ' 次出现')
            .fontSize(13)
            .fontColor($r('app.color.tertiary_text'))
          Blank()
          Text('关闭')
            .fontSize(14)
            .fontColor($r('app.color.idiom_blue'))
            .onClick(() => {
              this.closePositionPanel();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 12 })

        if (this.editingWordOccurrences.length === 0) {
          Column() {
            Text('当前文本中未找到该关键字')
              .fontSize(13)
              .fontColor($r('app.color.hint_text'))
              .padding(20)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        } else {
          // 出现位置列表
          Scroll() {
            Column() {
              ForEach(this.editingWordOccurrences, (ctx: KeywordOccurrenceContext) => {
                Row() {
                  Checkbox()
                    .select(this.isOccurrenceSelected(ctx.index))
                    .onChange((checked: boolean) => {
                      this.toggleOccurrence(ctx.index);
                    })
                    .margin({ right: 10 })
                  Column() {
                    Text('第 ' + (ctx.index + 1).toString() + ' 次')
                      .fontSize(12)
                      .fontColor($r('app.color.tertiary_text'))
                    Text(ctx.context)
                      .fontSize(13)
                      .fontColor($r('app.color.primary_text'))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.toggleOccurrence(ctx.index);
                  })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              }, (ctx: KeywordOccurrenceContext) => ctx.index.toString())
            }
            .width('100%')
          }
          .width('100%')
          .layoutWeight(1)
          .scrollable(ScrollDirection.Vertical)
          .scrollBar(BarState.Auto)

          // 底部操作按钮
          Row({ space: 8 }) {
            Button('全选')
              .fontSize(13)
              .fontColor($r('app.color.idiom_blue'))
              .backgroundColor($r('app.color.idiom_blue') + '18')
              .borderRadius(16)
              .height(32)
              .layoutWeight(1)
              .onClick(() => {
                this.selectAllOccurrences();
              })
            Button('全不选')
              .fontSize(13)
              .fontColor($r('app.color.tertiary_text'))
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(16)
              .height(32)
              .layoutWeight(1)
              .onClick(() => {
                this.selectNoneOccurrences();
              })
            if (this.editingWordSource === 'manual') {
              Button('移除该词')
                .fontSize(13)
                .fontColor('#dc2626')
                .backgroundColor('rgba(220,38,38,0.12)')
                .borderRadius(16)
                .height(32)
                .layoutWeight(1)
                .onClick(() => {
                  let word: string = this.editingWord;
                  this.closePositionPanel(true);  // 跳过脏状态检查
                  this.removeKeyword(word);
                })
            }
          }
          Row() {
            Button('确定')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor('#ffffff')
              .backgroundColor($r('app.color.idiom_blue'))
              .borderRadius(20)
              .height(40)
              .width('100%')
              .onClick(() => {
                this.confirmEditingWord();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 16 })
        }
      }
      .width('100%')
      .height('60%')
      .backgroundColor($r('app.color.card_background'))
      .borderRadius({ topLeft: 16, topRight: 16 })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Bottom)
  }

  /**
   * 判断某个出现序号是否被选中（用于 Checkbox 显示状态）
   */
  private isOccurrenceSelected(index: number): boolean {
    for (let i = 0; i < this.editingWordSelectedIndices.length; i++) {
      if (this.editingWordSelectedIndices[i] === index) {
        return true;
      }
    }
    return false;
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
                Markdown({ controller: this.controllerStore.get(index), text: this.getHighlightedText(index) })
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

        Button('保存图片')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#ffffff')
          .backgroundColor(this.currentAccentColor)
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
