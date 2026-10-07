/**
 * 生字卡模板：尺寸/格型/字色模式/配色 + 格数自适应公式（设计稿 900px 基准）
 * 导出规格：方卡 1080x1080（1:1）、练习卡 1080x1440（3:4）、公众号首图 1080x460（2.35:1，恒单行）
 */
import { CoverPalette } from '../../model/CoverModels';

export class CharCardSize {
  static readonly SQUARE: string = 'square';
  static readonly PRACTICE: string = 'practice';
  static readonly COVER: string = 'cover';

  static label(kind: string): ResourceStr {
    if (kind === CharCardSize.PRACTICE) {
      return $r('app.string.tmpl_size_practice');
    }
    if (kind === CharCardSize.COVER) {
      return $r('app.string.tmpl_size_cover');
    }
    return $r('app.string.tmpl_size_square');
  }
}

export class CharCardGridType {
  static readonly TIAN: string = 'tian';
  static readonly MI: string = 'mi';

  static label(kind: string): ResourceStr {
    return kind === CharCardGridType.MI ? $r('app.string.tmpl_grid_mi') : $r('app.string.tmpl_grid_tian');
  }
}

export class CharCardCharMode {
  static readonly READ: string = 'read';
  static readonly TRACE: string = 'trace';

  static label(mode: string): ResourceStr {
    return mode === CharCardCharMode.TRACE ? $r('app.string.tmpl_mode_trace') : $r('app.string.tmpl_mode_read');
  }
}

export class CharCards {
  static readonly MAX_CHARS: number = 12;
  static readonly DESIGN_W: number = 900;
  static readonly DESIGN_H_SQUARE: number = 900;
  static readonly DESIGN_H_PRACTICE: number = 1200;
  static readonly DESIGN_H_COVER: number = 383;
  static readonly EXPORT_W: number = 1080;
  static readonly EXPORT_H_SQUARE: number = 1080;
  static readonly EXPORT_H_PRACTICE: number = 1440;
  static readonly EXPORT_H_COVER: number = 460;
  /** 设计稿内容区宽（左右边距各 80） */
  static readonly CONTENT_W: number = 740;
  /** 格间距（设计稿 px） */
  static readonly GAP: number = 20;
  /** 单格最大边长（设计稿 px） */
  static readonly MAX_CELL: number = 320;
  /** 公众号首图单格边长上限（设计稿 px）：拼音+格子纵向合计须 ≤ 383 */
  static readonly MAX_CELL_COVER: number = 280;

  static designHeight(sizeKind: string): number {
    if (sizeKind === CharCardSize.PRACTICE) {
      return CharCards.DESIGN_H_PRACTICE;
    }
    return sizeKind === CharCardSize.COVER ?
      CharCards.DESIGN_H_COVER : CharCards.DESIGN_H_SQUARE;
  }

  static exportHeight(sizeKind: string): number {
    if (sizeKind === CharCardSize.PRACTICE) {
      return CharCards.EXPORT_H_PRACTICE;
    }
    return sizeKind === CharCardSize.COVER ?
      CharCards.EXPORT_H_COVER : CharCards.EXPORT_H_SQUARE;
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

  /** 行拆分（按尺寸）：公众号首图高度仅 383，恒单行；其余尺寸走通用拆分 */
  static splitRowsFor(sizeKind: string, n: number): number[] {
    if (sizeKind === CharCardSize.COVER) {
      return n <= 0 ? [] : [n];
    }
    return CharCards.splitRows(n);
  }

  /** 单格边长上限（设计稿 px）：首图 280 防纵向溢出，其余 320 */
  static maxCellFor(sizeKind: string): number {
    return sizeKind === CharCardSize.COVER ? CharCards.MAX_CELL_COVER : CharCards.MAX_CELL;
  }

  /** 单行格边长（设计稿 px）：min(maxCell, (CONTENT_W-(rowLen-1)*GAP)/rowLen) */
  static cellSize(rowLen: number, maxCell: number): number {
    if (rowLen <= 0) {
      return 0;
    }
    return Math.min(maxCell,
      (CharCards.CONTENT_W - (rowLen - 1) * CharCards.GAP) / rowLen);
  }

  /** 拼音字号（设计稿 px）：随格边缩放，下限 30；chang/zhuang 等长音节由槽内自适应字号兜底 */
  static pinyinSize(cell: number): number {
    return Math.max(30, cell * 0.28);
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
      CoverPalette.of($r('app.string.tmpl_pal_blue_red'), '#2E6FD6', '#D8231A', '#1F1F1F', '#1F1F1F'),
      CoverPalette.of($r('app.string.tmpl_pal_cream_red'), '#FAF6EE', '#D8231A', '#1F1F1F', '#333333'),
      CoverPalette.of($r('app.string.tmpl_pal_board_green'), '#2F5D50', '#F0EAD8', '#F0EAD8', '#F0EAD8'),
      CoverPalette.of($r('app.string.tmpl_pal_maroon_cream'), '#8C2F2A', '#F0EAD8', '#F0EAD8', '#F0EAD8'),
      CoverPalette.of($r('app.string.tmpl_pal_cream_ink'), '#FAF6EE', '#2B2B2B', '#2B2B2B', '#2B2B2B'),
    ];
  }
}
