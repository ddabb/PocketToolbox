/**
 * 生字卡卡面渲染组件：设计稿 900x900（方卡）/ 900x1200（练习卡）/ 900x383（公众号首图，恒单行）等比渲染
 * 结构：拼音（可关，逐字槽位对齐：汉字按序取音节，无音节字顶上留空白槽，槽宽恒等格边长不迁移；系统字体防部分设备声调字符渲染异常） + 田字格/米字格格区（1-12 字，>8 字两行）；
 * 标点字格不注音不出格线（标点非练字对象），仅居中渲染，占位保持行几何对齐
 */
import { CoverPalette } from '../../model/CoverModels';
import { CharCardCharMode, CharCardGridType, CharCardInputMode, CharCardSize, CharCards } from '../../core/cover/CharCardTemplates';
import { WordSegmentUtil } from '../../common/utils/WordSegmentUtil';

const KAI_FONT: string = 'LXGWWenKai';

@Component
export struct CharCardPreview {
  @Prop charsText: string;
  @Prop pinyinText: string;
  @Prop pinyinOn: boolean;
  @Prop paletteIndex: number;
  @Prop gridType: string;
  @Prop charMode: string;
  @Prop sizeKind: string;
  @Prop previewWidth: number;
  /** 输入模式：chars（单字）/ sentence（句子分词） */
  @Prop inputMode: string;
  /** 句子模式：空格分隔的词串（词内不含空格，可无损还原） */
  @Prop wordsText: string;

  /** 设计稿 px -> vp */
  private f(px: number): number {
    return this.previewWidth * px / CharCards.DESIGN_W;
  }

  private h(): number {
    return this.previewWidth * CharCards.designHeight(this.sizeKind) / CharCards.DESIGN_W;
  }

  private pal(): CoverPalette {
    let list: CoverPalette[] = CharCards.palettes();
    if (this.paletteIndex >= 0 && this.paletteIndex < list.length) {
      return list[this.paletteIndex];
    }
    return list[0];
  }

  /** 句子模式词数组（空格分隔串还原） */
  private words(): string[] {
    let t: string = this.wordsText.trim();
    if (t === '') {
      return [];
    }
    return t.split(new RegExp('\\s+', 'g')).filter((s: string) => s !== '');
  }

  private isSentence(): boolean {
    return this.inputMode === CharCardInputMode.SENTENCE;
  }

  private chars(): string[] {
    if (this.isSentence()) {
      return this.words().join('').split('');
    }
    return CharCards.cleanChars(this.charsText).split('');
  }

  private rowLens(): number[] {
    if (this.isSentence()) {
      return CharCards.splitRowsByWords(this.sizeKind, this.words());
    }
    return CharCards.splitRowsFor(this.sizeKind, this.chars().length);
  }

  private maxCell(rowIndex: number): number {
    let cap: number = CharCards.maxCellFor(this.sizeKind);
    if (this.sizeKind === CharCardSize.COVER && this.hasPinyin()) {
      cap = Math.min(cap, CharCards.MAX_CELL_COVER_PINYIN);
    }
    return cap;
  }

  private cellOf(rowIndex: number): number {
    return CharCards.cellSize(this.rowLens()[rowIndex], this.maxCell(rowIndex));
  }

  private lineW(): number {
    return Math.max(0.4, this.f(1));
  }

  private outerW(): number {
    if (this.gridType === CharCardGridType.NONE) {
      return 0;
    }
    return Math.max(1, this.f(3));
  }

  build() {
    Column({ space: this.f(26) }) {
      ForEach(this.rowLens(), (len: number, ri: number) => {
        this.GridRow(ri)
      }, (len: number, ri: number) => 'row' + ri.toString() + len.toString())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.pal().bg)
  }

  /** 压缩音节列表（仅汉字有音节，顺序与汉字序列一一对应） */
  private allSyllables(): string[] {
    return this.pinyinText.trim().split(new RegExp('\\s+', 'g')).filter((s: string) => s !== '');
  }

  /** 是否存在可注音内容（拼音开且音节非空） */
  private hasPinyin(): boolean {
    return this.pinyinOn && this.allSyllables().length > 0;
  }

  /**
   * 行内逐字拼音槽：汉字按序消费音节（不足留空），非汉字槽恒留空——
   * 槽位与格子行几何一致（槽宽=格边长），无对应拼音的字顶上空白呈现，拼音不迁移
   */
  private rowPinyinSlots(rowIndex: number): string[] {
    let syllables: string[] = this.allSyllables();
    let chars: string[] = this.chars();
    let lens: number[] = this.rowLens();
    let start: number = 0;
    for (let i = 0; i < rowIndex; i++) {
      start += lens[i];
    }
    let han: RegExp = new RegExp('[\\u4e00-\\u9fff]');
    let si: number = 0;
    for (let i = 0; i < start && i < chars.length; i++) {
      if (han.test(chars[i])) {
        si++;
      }
    }
    let slots: string[] = [];
    for (let i = start; i < start + lens[rowIndex] && i < chars.length; i++) {
      if (han.test(chars[i])) {
        slots.push(si < syllables.length ? syllables[si] : '\u00A0');
        si++;
      } else {
        slots.push('\u00A0');
      }
    }
    return slots;
  }

  /** 单行：拼音（可选，逐字槽位对齐）+ 格子行 */
  @Builder
  GridRow(rowIndex: number) {
    Column({ space: this.f(18) }) {
      if (this.hasPinyin()) {
        this.PinyinSlots(rowIndex)
      }
      Row({ space: this.f(CharCards.GAP) }) {
        ForEach(this.rowChars(rowIndex), (ch: string, ci: number) => {
          this.GridCell(this.f(this.cellOf(rowIndex)), ch)
        }, (ch: string, ci: number) => ch + ci.toString())
      }
      .alignItems(VerticalAlign.Center)
    }
    .alignItems(HorizontalAlign.Center)
  }

  /** 逐字拼音槽：每槽宽=格边长、槽距=格间距，与格子行几何一致实现一一对应；空槽用不换行空格占位保持行高 */
  @Builder
  PinyinSlots(rowIndex: number) {
    Row({ space: this.f(CharCards.GAP) }) {
      ForEach(this.rowPinyinSlots(rowIndex), (sy: string, ci: number) => {
        Text(sy)
          .width(this.f(this.cellOf(rowIndex)))
          .fontSize(this.f(CharCards.pinyinSize(this.cellOf(rowIndex))))
          .minFontSize(this.f(16))
          .maxFontSize(this.f(CharCards.pinyinSize(this.cellOf(rowIndex))))
          .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
          .fontColor(this.pal().sub)
          .maxLines(1)
          .textAlign(TextAlign.Center)
      }, (sy: string, ci: number) => sy + ci.toString())
    }
    .alignItems(VerticalAlign.Center)
  }

  private rowChars(rowIndex: number): string[] {
    let all: string[] = this.chars();
    let lens: number[] = this.rowLens();
    let start: number = 0;
    for (let i = 0; i < rowIndex; i++) {
      start += lens[i];
    }
    return all.slice(start, start + lens[rowIndex]);
  }

  /** 田字格/米字格/无边框单元格：外框实线 + 十字虚线（米字格加对角虚线，无边框仅保留字）+ 居中楷体字（字在最上层压住格线）
   *  标点字格不出格线（标点非练字对象），仅居中渲染 */
  @Builder
  GridCell(size: number, ch: string) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.gridType !== CharCardGridType.NONE && !WordSegmentUtil.isPunctuation(ch)) {
        Row()
          .width('100%')
          .height(this.lineW())
          .border({ width: { top: this.lineW() }, color: this.pal().accent, style: BorderStyle.Dashed })
        Column()
          .height('100%')
          .width(this.lineW())
          .border({ width: { left: this.lineW() }, color: this.pal().accent, style: BorderStyle.Dashed })
        if (this.gridType === CharCardGridType.MI) {
          Row()
            .width(size * 1.4142)
            .height(this.lineW())
            .border({ width: { top: this.lineW() }, color: this.pal().accent, style: BorderStyle.Dashed })
            .opacity(0.6)
            .rotate({ angle: 45, centerX: '50%', centerY: '50%' })
          Row()
            .width(size * 1.4142)
            .height(this.lineW())
            .border({ width: { top: this.lineW() }, color: this.pal().accent, style: BorderStyle.Dashed })
            .opacity(0.6)
            .rotate({ angle: -45, centerX: '50%', centerY: '50%' })
        }
      }
      Text(ch)
        .fontSize(size * 0.7)
        .fontColor(this.pal().title)
        .fontFamily(KAI_FONT)
        .opacity(this.charMode === CharCardCharMode.TRACE ? 0.3 : 1)
    }
    .width(size)
    .height(size)
    .border({ width: WordSegmentUtil.isPunctuation(ch) ? 0 : this.outerW(), color: this.pal().accent })
  }
}
