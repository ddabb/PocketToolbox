/**
 * 生字卡卡面渲染组件：设计稿 900x900（方卡）/ 900x1200（练习卡）等比渲染
 * 结构：拼音（可关，逐字对齐：每音节对准其上方格子） + 田字格/米字格格区（1-12 字，>8 字两行）
 */
import { CoverPalette } from '../../model/CoverModels';
import { CharCards, CharCardCharMode, CharCardGridType } from '../../core/cover/CharCardTemplates';

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

  private chars(): string[] {
    return CharCards.cleanChars(this.charsText).split('');
  }

  private rowLens(): number[] {
    return CharCards.splitRows(this.chars().length);
  }

  private lineW(): number {
    return Math.max(0.4, this.f(1));
  }

  private outerW(): number {
    return Math.max(1, this.f(3));
  }

  build() {
    Column({ space: this.f(26) }) {
      if (this.pinyinOn) {
        ForEach(this.pinyinRows(), (py: string, ri: number) => {
          this.GridRow(ri, py)
        }, (py: string, ri: number) => 'py' + ri.toString() + py)
      } else {
        ForEach(this.rowLens(), (len: number, ri: number) => {
          this.GridRow(ri, '')
        }, (len: number, ri: number) => 'row' + ri.toString() + len.toString())
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.pal().bg)
  }

  private pinyinRows(): string[] {
    return CharCards.splitPinyinRows(this.pinyinText, this.rowLens());
  }

  /** 单行：拼音（可选，逐字对齐）+ 格子行 */
  @Builder
  GridRow(rowIndex: number, pinyinRow: string) {
    Column({ space: this.f(18) }) {
      if (pinyinRow !== '') {
        if (this.rowSyllables(rowIndex, pinyinRow).length > 0) {
          this.PinyinSlots(rowIndex, this.rowSyllables(rowIndex, pinyinRow))
        } else {
          Text(pinyinRow)
            .fontSize(this.f(CharCards.pinyinSize(CharCards.cellSize(this.rowLens()[rowIndex]))))
            .fontColor(this.pal().sub)
            .fontFamily(KAI_FONT)
            .maxLines(1)
        }
      }
      Row({ space: this.f(CharCards.GAP) }) {
        ForEach(this.rowChars(rowIndex), (ch: string, ci: number) => {
          this.GridCell(this.f(CharCards.cellSize(this.rowLens()[rowIndex])), ch)
        }, (ch: string, ci: number) => ch + ci.toString())
      }
      .alignItems(VerticalAlign.Center)
    }
    .alignItems(HorizontalAlign.Center)
  }

  /** 行内音节数与字数一致时返回逐字音节，否则返回空数组（回退整行居中） */
  private rowSyllables(rowIndex: number, pinyinRow: string): string[] {
    let len: number = this.rowLens()[rowIndex];
    let parts: string[] = pinyinRow.split(' ');
    if (parts.length !== len) {
      return [];
    }
    return parts;
  }

  /** 逐字拼音槽：每音节槽宽=格边长、槽距=格间距，与格子行几何一致实现一一对应 */
  @Builder
  PinyinSlots(rowIndex: number, syllables: string[]) {
    Row({ space: this.f(CharCards.GAP) }) {
      ForEach(syllables, (sy: string, ci: number) => {
        Text(sy)
          .width(this.f(CharCards.cellSize(this.rowLens()[rowIndex])))
          .fontSize(this.f(CharCards.pinyinSize(CharCards.cellSize(this.rowLens()[rowIndex]))))
          .minFontSize(this.f(16))
          .maxFontSize(this.f(CharCards.pinyinSize(CharCards.cellSize(this.rowLens()[rowIndex]))))
          .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
          .fontColor(this.pal().sub)
          .fontFamily(KAI_FONT)
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

  /** 田字格/米字格单元格：外框实线 + 十字虚线（米字格加对角虚线）+ 居中楷体字 */
  @Builder
  GridCell(size: number, ch: string) {
    Stack({ alignContent: Alignment.Center }) {
      Text(ch)
        .fontSize(size * 0.7)
        .fontColor(this.pal().title)
        .fontFamily(KAI_FONT)
        .opacity(this.charMode === CharCardCharMode.TRACE ? 0.3 : 1)
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
    .width(size)
    .height(size)
    .border({ width: this.outerW(), color: this.pal().accent })
  }
}
