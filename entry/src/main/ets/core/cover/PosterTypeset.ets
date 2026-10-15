/**
 * 文案海报排版内核：按「容器可用宽度 + 行数预算 + 文案长度」计算主文案字号与实际行数。
 *
 * 设计目标（对应 docs/文案海报优化计划.md §2 根因 B）：
 *   1. 取消原先按字数分 5 档固定 px 的硬编码阶梯，改为连续函数，消除 32→33 字的字号跳变；
 *   2. 感知容器可用宽度（各模板 padding 不同，同样 20 字在 T1/T10 里可用宽度差近百 px）；
 *   3. 感知行数预算（三种比例宽度相同、高度不同，行数上限 8/12 不同）。
 *
 * 纯函数实现，不依赖 UI 上下文，可在无真机环境走查边界用例。
 * 计划：docs/文案海报优化计划.md §3 P0-2
 */

/** 排版结果 */
export class PosterLayout {
  /** 实际字号（设计稿 px） */
  fontPx: number = 0;
  /** 实际行数（不超出行数预算） */
  lines: number = 0;
  /** 是否发生截断 */
  truncated: boolean = false;
  /** 被截断掉的字数（未截断时为 0） */
  truncatedChars: number = 0;
  /** 该行数预算下能容纳的总字数 */
  capacity: number = 0;
}

/** 竖排排版结果（layoutVertical 专用） */
export class PosterVerticalLayout {
  /** 实际字号（设计稿 px） */
  fontPx: number = 0;
  /** 各列字符（阅读序：首列在前；渲染时自右向左） */
  columns: string[][] = [];
  /** 每列字数 */
  perCol: number = 0;
  /** 实际列数 */
  cols: number = 0;
  /** 是否发生截断（仅发生在 MIN_FONT_PX） */
  truncated: boolean = false;
  /** 被截断掉的字数（未截断时为 0） */
  truncatedChars: number = 0;
  /** 当前字号下列数上限下能容纳的总字数 */
  capacity: number = 0;
}

/** 字宽估算系数（相对字号 em） */
const HANZI_EM: number = 1.0;
/** 拉丁字母/数字按 0.55em 估（等宽近似，保守偏大以避免溢出） */
const LATIN_EM: number = 0.55;
/** 全角标点按 1.0em 估 */
const PUNCT_EM: number = 1.0;
/** 最小字号（设计稿 px），低于此值可读性太差，宁可截断 */
const MIN_FONT_PX: number = 20;
/** 行高倍数，与 CopyPosterPreview 的 lineHeight(字号*1.4) 保持一致 */
const LINE_HEIGHT_RATIO: number = 1.4;
/** 折行时避免行首标点：这些标点不允许作为一行的第一个字符 */
const NO_LINE_START: string = '，。、！？；：…—·）】》」』〉%,.!?;:)]}';

/** 汉字判定 */
const RE_HANZI: RegExp = new RegExp('[\\u4e00-\\u9fff]');
/** 全角标点判定 */
const RE_PUNCT: RegExp = new RegExp('[，。、！？；：…—·「」『』（）《》〈〉【】]');

/** 竖排列首避让：闭合标点不作为一列的开头（同横排 NO_LINE_START） */
const NO_COL_START: string = '，。、！？；：…—·）】》」』〉%,.!?;:)]}';
/** 竖排列尾避让：开放标点不作为一列的收尾（「」不断词验收项） */
const NO_COL_END: string = '「『（【《〈([';

export class PosterTypeset {
  /**
   * 计算单行宽度（以 em 为单位）。
   * 汉字与全角标点按 1.0em，拉丁/数字/半角按 0.55em，其余（emoji 等）按 1.2em 保守估计。
   */
  static measureEm(text: string): number {
    let em: number = 0;
    for (let i = 0; i < text.length; i++) {
      let ch: string = text.charAt(i);
      if (RE_HANZI.test(ch) || RE_PUNCT.test(ch)) {
        em += 1.0;
      } else if (ch.charCodeAt(0) < 128) {
        em += LATIN_EM;
      } else {
        // emoji / 生僻字 / 其他非 ASCII：按 1.2em 保守估计，避免低估导致顶格
        em += 1.2;
      }
    }
    return em;
  }

  /** 有效字数（去空白），与 CopyPosterPreview.bodyLen 口径一致 */
  static countChars(text: string): number {
    return text.replace(new RegExp('\\s', 'g'), '').length;
  }

  /**
   * 核心算法。
   *
   * @param text           主文案
   * @param availWidthPx   容器可用宽度（设计稿 px）。<=0 表示不感知宽度，退化为纯长度模式
   * @param maxLines       行数预算（8 方图 / 12 竖图 / 模板自定义）
   * @param basePx         该模板的基准字号（设计稿 px）
   * @param big            是否大字模板（大字模板观感优先，行数预算更宽松）
   * @returns 排版结果
   */
  static layout(text: string, availWidthPx: number, maxLines: number, basePx: number, big: boolean): PosterLayout {
    let result: PosterLayout = new PosterLayout();
    let chars: number = PosterTypeset.countChars(text);
    if (chars === 0) {
      result.fontPx = basePx;
      result.lines = 0;
      result.capacity = 0;
      return result;
    }

    let budget: number = maxLines > 0 ? maxLines : 1;
    let font: number = PosterTypeset.startFont(chars, basePx, big);

    // 宽度下限：字号不能大到一行连 2 个字都放不下（那样不像「一列字」而是「一根竖线」）。
    // 同时不能超过该模板基准字号，故取两者较小值。
    if (availWidthPx > 0) {
      let widthFloor: number = Math.floor(availWidthPx / 2);
      font = Math.max(MIN_FONT_PX, Math.min(font, Math.min(widthFloor, basePx)));
    }

    // 行数约束：超预算则连续收缩（无阶梯跳变）
    let lines: number = PosterTypeset.estimateLines(text, font, availWidthPx, budget);
    let guard: number = 0;
    while (lines > budget && font > MIN_FONT_PX && guard < 60) {
      let ratio: number = budget / lines;
      let next: number = Math.floor(font * Math.max(0.9, ratio));
      if (next >= font) {
        next = font - 1;
      }
      font = Math.max(MIN_FONT_PX, next);
      lines = PosterTypeset.estimateLines(text, font, availWidthPx, budget);
      guard++;
    }

    result.fontPx = font;
    result.lines = Math.min(lines, budget);
    result.capacity = PosterTypeset.estimateCapacity(font, availWidthPx, budget);

    // 截断判定：到了最小字号 / 满行数仍放不下才算截断
    if (availWidthPx > 0 && chars > result.capacity) {
      result.truncated = true;
      result.truncatedChars = chars - result.capacity;
    }

    // 大字模板给下限保护，避免长文案把大字压成小字（观感崩塌）
    if (big) {
      let bigFloor: number = Math.floor(basePx * 0.5);
      if (font < bigFloor) {
        // 触发下限时重新核算容量与截断数
        font = Math.max(MIN_FONT_PX, bigFloor);
        result.fontPx = font;
        result.lines = Math.min(lines, budget);
        let cap2: number = PosterTypeset.estimateCapacity(font, availWidthPx, budget);
        result.capacity = cap2;
        if (chars > cap2) {
          result.truncated = true;
          result.truncatedChars = chars - cap2;
        }
      }
    }
    return result;
  }

  /**
   * 起始字号：按字数连续递减，替代原先的 5 档硬编码阶梯。
   * 曲线分段线性，取值经边界用例走查（T1 容器 base=72）：
   *   4字72 / 8字72 / 12字68 / 16字64 / 20字61 / 24字58 / 32字53 / 40字47 / 50字45
   * 无 32→33 式的骤降。
   */
  private static startFont(chars: number, basePx: number, big: boolean): number {
    let font: number;
    if (chars <= 8) {
      font = basePx;
    } else if (chars <= 20) {
      font = basePx * (1 - (chars - 8) / 12 * 0.15);
    } else if (chars <= 40) {
      font = basePx * 0.85 * (1 - (chars - 20) / 20 * 0.22);
    } else {
      font = basePx * 0.63;
    }
    // 大字模板整体放大一档，保住「大字冲击」的观感
    if (big) {
      font = font * 1.15;
    }
    return Math.floor(font);
  }

  /**
   * 估算行数：按可用宽度折行，受 maxLines 预算限制（超出只记到预算即可）。
   * availWidthPx <= 0 时按「每行容量 = chars / budget」估算。
   */
  private static estimateLines(text: string, font: number, availWidthPx: number, budget: number): number {
    let perLineEm: number = budget > 0 && availWidthPx <= 0
      ? PosterTypeset.countChars(text) / budget
      : (availWidthPx > 0 ? availWidthPx / font : PosterTypeset.countChars(text));
    if (perLineEm <= 0) {
      return 1;
    }
    // 逐字符累加，遇到标点做行首避让
    let lines: number = 1;
    let lineEm: number = 0;
    for (let i = 0; i < text.length; i++) {
      let ch: string = text.charAt(i);
      if (ch === ' ' || ch === '\n') {
        if (ch === '\n') {
          lines++;
          lineEm = 0;
        }
        continue;
      }
      let w: number = PosterTypeset.charEm(ch);
      // 避免标点落在行首：把标点挤进上一行
      if (NO_LINE_START.indexOf(ch) >= 0 && lineEm + w > perLineEm && lines < budget) {
        lines++;
        lineEm = 0;
      }
      if (lineEm + w > perLineEm) {
        lines++;
        lineEm = w;
      } else {
        lineEm += w;
      }
      if (lines > budget) {
        // 已超预算，后续不再细分（只用于「是否需要继续缩字号」的判断）
        return lines;
      }
    }
    return lines;
  }

  /** 单字符宽度（em） */
  private static charEm(ch: string): number {
    if (RE_HANZI.test(ch) || RE_PUNCT.test(ch)) {
      return PUNCT_EM;
    }
    if (ch.charCodeAt(0) < 128) {
      return LATIN_EM;
    }
    return 1.2;
  }

  /**
   * 估算行数预算下能容纳的总字数。
   * availWidthPx <= 0 时退化为「有效字数」（等价于纯长度模式）。
   */
  static estimateCapacity(font: number, availWidthPx: number, budget: number): number {
    if (availWidthPx <= 0) {
      return 0;
    }
    let perLine: number = Math.floor(availWidthPx / font);
    if (perLine < 1) {
      perLine = 1;
    }
    return perLine * (budget > 0 ? budget : 1);
  }

  /** 行高（设计稿 px），供内容层排布用 */
  static lineHeight(fontPx: number): number {
    return Math.round(fontPx * LINE_HEIGHT_RATIO);
  }

  /**
   * 供内容层做纵向居中/分配时使用：内容块总高度（设计稿 px）。
   */
  static blockHeight(fontPx: number, lines: number): number {
    return PosterTypeset.lineHeight(fontPx) * Math.max(1, lines);
  }

  /**
   * 竖排内核（设计稿 px）：字号自 basePx 连续 -1px 收缩至文本恰入 ≤maxCols 列；
   * 最小字号仍放不下则截断并报 truncatedChars。
   *
   * 1.4.6 P0-1 A 类（T16/T18/T20）专用，Phase 0 Python spike 锁定方案
   * （scripts/spike_layout_vertical.py + spike_layout_vertical_geo.py 全绿）：
   *   - 竖排列数即预算，容量驱动连续收缩，不套用横排 startFont 曲线；
   *   - 列首避让 NO_COL_START + 列尾避让 NO_COL_END（「」不断词）；
   *   - 截断仅发生在 MIN_FONT_PX，提示复用 poster_truncated_hint（替代旧 '…' 截断）；
   *   - 相邻字数最大跌落 12px（T20 1:1 19 字处），旧分档悬崖 21%-26% 已消除。
   *
   * @param text           主文案
   * @param availHeightPx  每列可用高度（设计稿 px，横排基准 f()：perCol = availHeightPx / (font×lhRatio)）
   * @param maxCols        列数硬上限（与 availWidthPx/pitchRatio 取小）
   * @param basePx         基准字号（设计稿 px）
   * @param big            大字模式（字号整体 ×1.15）
   * @param lhRatio        行高比（T16 1.30 / T18 1.36 / T20 1.32）
   * @param availWidthPx   可用宽度（设计稿 px；<=0 表示不感知宽度，仅用硬上限）
   * @param pitchRatio     列距比 = 列宽 + 列间距 / 字号（T16 1.63 / T18 1.90 / T20 1.80）
   */
  static layoutVertical(text: string, availHeightPx: number, maxCols: number, basePx: number,
    big: boolean, lhRatio: number, availWidthPx: number, pitchRatio: number): PosterVerticalLayout {
    let result: PosterVerticalLayout = new PosterVerticalLayout();
    let chars: string[] = PosterTypeset.vertChars(text);
    let n: number = chars.length;
    if (n === 0) {
      result.fontPx = basePx;
      return result;
    }
    let font: number = Math.floor(basePx * (big ? 1.15 : 1.0));
    while (font >= MIN_FONT_PX) {
      let perCol: number = Math.max(1, Math.floor(availHeightPx / (font * lhRatio)));
      let cap: number = PosterTypeset.colsWidthCap(font, availWidthPx, pitchRatio, maxCols);
      let cols: string[][] | null = PosterTypeset.simulateColumns(chars, perCol, cap);
      if (cols !== null) {
        result.fontPx = font;
        result.columns = cols;
        result.perCol = perCol;
        result.cols = cols.length;
        result.capacity = perCol * cap;
        return result;
      }
      font--;
    }
    // 最小字号仍放不下：按容量截断，报 truncatedChars
    font = MIN_FONT_PX;
    let perCol: number = Math.max(1, Math.floor(availHeightPx / (font * lhRatio)));
    let cap: number = PosterTypeset.colsWidthCap(font, availWidthPx, pitchRatio, maxCols);
    let total: number = perCol * cap;
    while (total > 0) {
      let kept: string[] = chars.slice(0, total);
      let cols: string[][] | null = PosterTypeset.simulateColumns(kept, perCol, cap);
      if (cols !== null) {
        result.fontPx = font;
        result.columns = cols;
        result.perCol = perCol;
        result.cols = cols.length;
        result.truncated = true;
        result.truncatedChars = n - total;
        result.capacity = total;
        return result;
      }
      total--;
    }
    result.fontPx = font;
    result.truncated = true;
    result.truncatedChars = n;
    return result;
  }

  /** 竖排字符序列：去空白逐字拆分（与 CopyPosterPreview.vertChars 同口径） */
  private static vertChars(text: string): string[] {
    return Array.from(text.replace(new RegExp('\\s', 'g'), ''));
  }

  /**
   * 列数上限 = min(硬上限, 可用宽/列距)；availWidthPx<=0 时只用硬上限。
   */
  private static colsWidthCap(font: number, availWidthPx: number, pitchRatio: number, hardCap: number): number {
    let cap: number = hardCap;
    if (availWidthPx > 0) {
      cap = Math.min(cap, Math.max(1, Math.floor(availWidthPx / (font * pitchRatio))));
    }
    return Math.max(1, cap);
  }

  /**
   * 按阅读序切列（首列在前，渲染时自右向左）；超列预算返回 null。
   * 列首避让：下一字符是闭合标点时不让它开新列（当前列提前 1 字收列）；
   * 列尾避让：当前列末字是开放标点时把它带到下一列（「」不断词）。
   */
  private static simulateColumns(chars: string[], perCol: number, maxCols: number): string[][] | null {
    let per: number = perCol < 1 ? 1 : perCol;
    let cols: string[][] = [];
    let cur: string[] = [];
    let i: number = 0;
    let n: number = chars.length;
    while (i < n) {
      cur.push(chars[i]);
      i++;
      if (cur.length >= per || i >= n) {
        let pulled: boolean = false;
        if (per >= 2 && i < n && cur.length >= per && NO_COL_START.indexOf(chars[i]) >= 0) {
          cur.pop();
          i--;
          pulled = true;
        }
        if (!pulled && per >= 2 && i < n && cur.length > 0 && NO_COL_END.indexOf(cur[cur.length - 1]) >= 0) {
          cur.pop();
          i--;
        }
        cols.push(cur);
        cur = [];
        if (cols.length > maxCols) {
          return null;
        }
      }
    }
    return cols;
  }
}
