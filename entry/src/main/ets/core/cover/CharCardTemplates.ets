/**
 * 生字卡模板：尺寸/格型/字色模式/配色 + 格数自适应公式（设计稿 900px 基准）
 * 导出规格：方卡 1080x1080（1:1）、练习卡 1080x1440（3:4）
 */
import { CoverPalette } from '../../model/CoverModels';

export class CharCardSize {
  static readonly SQUARE: string = 'square';
  static readonly PRACTICE: string = 'practice';

  static label(kind: string): string {
    return kind === CharCardSize.PRACTICE ? '练习卡 3:4' : '方卡 1:1';
  }
}

export class CharCardGridType {
  static readonly TIAN: string = 'tian';
  static readonly MI: string = 'mi';

  static label(kind: string): string {
    return kind === CharCardGridType.MI ? '米字格' : '田字格';
  }
}

export class CharCardCharMode {
  static readonly READ: string = 'read';
  static readonly TRACE: string = 'trace';

  static label(mode: string): string {
    return mode === CharCardCharMode.TRACE ? '描红' : '认读';
  }
}

export class CharCards {
  static readonly MAX_CHARS: number = 12;
  static readonly DESIGN_W: number = 900;
  static readonly DESIGN_H_SQUARE: number = 900;
  static readonly DESIGN_H_PRACTICE: number = 1200;
  static readonly EXPORT_W: number = 1080;
  static readonly EXPORT_H_SQUARE: number = 1080;
  static readonly EXPORT_H_PRACTICE: number = 1440;
  /** 设计稿内容区宽（左右边距各 80） */
  static readonly CONTENT_W: number = 740;
  /** 格间距（设计稿 px） */
  static readonly GAP: number = 20;
  /** 单格最大边长（设计稿 px） */
  static readonly MAX_CELL: number = 320;

  static designHeight(sizeKind: string): number {
    return sizeKind === CharCardSize.PRACTICE ?
      CharCards.DESIGN_H_PRACTICE : CharCards.DESIGN_H_SQUARE;
  }

  static exportHeight(sizeKind: string): number {
    return sizeKind === CharCardSize.PRACTICE ?
      CharCards.EXPORT_H_PRACTICE : CharCards.EXPORT_H_SQUARE;
  }

  /** 清洗输入：去空白、截断到 12 字 */
  static cleanChars(raw: string): string {
    let clean: string = raw.replace(new RegExp('\\s', 'g'), '');
    return clean.length > CharCards.MAX_CHARS ?
      clean.substring(0, CharCards.MAX_CHARS) : clean;
  }

  /** 行拆分：<=8 字一行；>8 字两行（前多后少，如 9->[5,4]、12->[6,6]） */
  static splitRows(n: number): number[] {
    if (n <= 0) {
      return [];
    }
    if (n <= 8) {
      return [n];
    }
    let first: number = Math.ceil(n / 2);
    return [first, n - first];
  }

  /** 单行格边长（设计稿 px）：min(MAX_CELL, (CONTENT_W-(rowLen-1)*GAP)/rowLen) */
  static cellSize(rowLen: number): number {
    if (rowLen <= 0) {
      return 0;
    }
    return Math.min(CharCards.MAX_CELL,
      (CharCards.CONTENT_W - (rowLen - 1) * CharCards.GAP) / rowLen);
  }

  /** 拼音字号（设计稿 px）：随格边缩放，下限 28 */
  static pinyinSize(cell: number): number {
    return Math.max(28, cell * 0.22);
  }

  /** 拼音按行分配：音节数与字数一致时逐行对齐，否则整串置于首行上方 */
  static splitPinyinRows(pinyinText: string, rowLen: number[]): string[] {
    let parts: string[] = pinyinText.trim().split(new RegExp('\\s+', 'g')).filter((s: string) => s !== '');
    let total: number = 0;
    for (let i = 0; i < rowLen.length; i++) {
      total += rowLen[i];
    }
    if (parts.length !== total) {
      let rows: string[] = [pinyinText.trim()];
      for (let i = 1; i < rowLen.length; i++) {
        rows.push('');
      }
      return rows;
    }
    let rows: string[] = [];
    let idx: number = 0;
    for (let i = 0; i < rowLen.length; i++) {
      let seg: string[] = parts.slice(idx, idx + rowLen[i]);
      rows.push(seg.join(' '));
      idx += rowLen[i];
    }
    return rows;
  }

  /** 配色 5 套：bg=底色 accent=格线 title=字色 sub=拼音色 */
  static palettes(): CoverPalette[] {
    return [
      CoverPalette.of('蓝底红格黑字', '#2E6FD6', '#D8231A', '#1F1F1F', '#1F1F1F'),
      CoverPalette.of('米白底红格', '#FAF6EE', '#D8231A', '#1F1F1F', '#333333'),
      CoverPalette.of('黑板绿底米格', '#2F5D50', '#F0EAD8', '#F0EAD8', '#F0EAD8'),
      CoverPalette.of('暗红底米格', '#8C2F2A', '#F0EAD8', '#F0EAD8', '#F0EAD8'),
      CoverPalette.of('米白底墨格', '#FAF6EE', '#2B2B2B', '#2B2B2B', '#2B2B2B'),
    ];
  }
}
