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
  static readonly NONE: string = 'none';

  static label(kind: string): ResourceStr {
    if (kind === CharCardGridType.MI) {
      return $r('app.string.tmpl_grid_mi');
    }
    if (kind === CharCardGridType.NONE) {
      return $r('app.string.tmpl_grid_none');
    }
    return $r('app.string.tmpl_grid_tian');
  }
}

export class CharCardCharMode {
  static readonly READ: string = 'read';
  static readonly TRACE: string = 'trace';

  static label(mode: string): ResourceStr {
    return mode === CharCardCharMode.TRACE ? $r('app.string.tmpl_mode_trace') : $r('app.string.tmpl_mode_read');
  }
}

/** 输入模式：单字（传统 1-12 字） / 句子（分词后按词换行，最多 32 字） */
export class CharCardInputMode {
  static readonly CHARS: string = 'chars';
  static readonly SENTENCE: string = 'sentence';

  static label(mode: string): ResourceStr {
    return mode === CharCardInputMode.SENTENCE ?
      $r('app.string.char_mode_sentence') : $r('app.string.char_mode_chars');
  }
}

export class CharCards {
  static readonly MAX_CHARS: number = 12;
  /** 句子模式最大字数（方卡/练习卡） */
  static readonly MAX_SENTENCE_CHARS: number = 32;
  /** 单行最大字数（行拆分装箱上限） */
  static readonly MAX_ROW_CHARS: number = 8;
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
  /** 公众号首图单格边长上限（设计稿 px，拼音关闭时）：格子纵向 ≤ 383 */
  static readonly MAX_CELL_COVER: number = 280;
  /**
   * 公众号首图单格边长上限（设计稿 px，拼音行渲染时）：
   * 拼音行高（实测 ≈1.3×字号，字号=0.28×格）+ 间距 18 + 格子 ≤ 383
   */
  static readonly MAX_CELL_COVER_PINYIN: number =
    (CharCards.DESIGN_H_COVER - CharCards.GAP) / (1 + 0.28 * 1.3);

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

  /** 句子模式各尺寸最大字数：首图恒单行 12；方卡/练习卡 32 */
  static maxCharsFor(sizeKind: string, inputMode: string): number {
    if (sizeKind === CharCardSize.COVER) {
      return CharCards.MAX_CHARS;
    }
    return inputMode === CharCardInputMode.SENTENCE ?
      CharCards.MAX_SENTENCE_CHARS : CharCards.MAX_CHARS;
  }

  /** 句子模式词截断：去空白总字数 ≤ maxChars；整词溢出即丢弃，首词超长时截断首词 */
  static capWords(words: string[], maxChars: number): string[] {
    let out: string[] = [];
    let total: number = 0;
    for (let i = 0; i < words.length; i++) {
      let w: string = words[i];
      if (w.length === 0) {
        continue;
      }
      if (total + w.length <= maxChars) {
        out.push(w);
        total += w.length;
        continue;
      }
      if (total === 0 && w.length > maxChars) {
        out.push(w.substring(0, maxChars));
      }
      break;
    }
    return out;
  }

  /**
   * 句子模式行拆分：贪心装箱 ≤8 字/行，词不跨行（超 8 字长词按 8 切块独行）；
   * 公众号首图恒单行（全部词并入一行）
   */
  static splitRowsByWords(sizeKind: string, words: string[]): number[] {
    if (words.length === 0) {
      return [];
    }
    if (sizeKind === CharCardSize.COVER) {
      let total: number = 0;
      for (let i = 0; i < words.length; i++) {
        total += words[i].length;
      }
      return total > 0 ? [total] : [];
    }
    let lens: number[] = [];
    let cur: number = 0;
    for (let i = 0; i < words.length; i++) {
      let w: string = words[i];
      if (w.length === 0) {
        continue;
      }
      if (w.length > CharCards.MAX_ROW_CHARS) {
        if (cur > 0) {
          lens.push(cur);
          cur = 0;
        }
        while (w.length > CharCards.MAX_ROW_CHARS) {
          lens.push(CharCards.MAX_ROW_CHARS);
          w = w.substring(CharCards.MAX_ROW_CHARS);
        }
        cur = w.length;
        continue;
      }
      if (cur + w.length <= CharCards.MAX_ROW_CHARS) {
        cur += w.length;
      } else {
        lens.push(cur);
        cur = w.length;
      }
    }
    if (cur > 0) {
      lens.push(cur);
    }
    return lens;
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
