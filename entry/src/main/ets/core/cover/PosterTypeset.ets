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
}
