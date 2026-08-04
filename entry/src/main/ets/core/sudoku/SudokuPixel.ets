/**
 * 数独 OCR 像素算法（纯逻辑，不依赖任何 @kit 系统 API）
 * 抽离到独立模块以便进行「本地单元测试」（无需模拟器/真机）。
 */

export interface DigitTemplate {
  digit: number;
  key: number[];
}

export interface BoardBBox {
  left: number;
  top: number;
  right: number;
  bottom: number;
  isDark: boolean;
}

// 数字模板 (10行 x 7列) — 由标准渲染图提取的真实数字签名，已做包围盒归一化
const tpl1: DigitTemplate = { digit: 1, key: [0,0,0,0,0,1,1,0,0,0,1,1,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1] };
const tpl2: DigitTemplate = { digit: 2, key: [0,0,0,1,1,0,0,0,1,1,1,1,1,1,0,1,1,1,1,1,1,0,0,0,0,0,1,1,0,0,0,0,1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1] };
const tpl3: DigitTemplate = { digit: 3, key: [0,1,1,1,1,1,0,0,1,1,1,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,0,1,1,1,1,1,0,0,0,1,1,1,1,1,0,0,0,0,0,1,1,0,0,0,0,0,1,1,1,1,1,1,1,1,1,0,1,1,1,1,0,0] };
const tpl4: DigitTemplate = { digit: 4, key: [0,0,0,0,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,0,0,0,1,1,1,1,0,0,1,1,0,1,1,0,0,1,1,0,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,0,0,0,0,0,1,1,0] };
const tpl5: DigitTemplate = { digit: 5, key: [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,1,1,1,0,1,1,1,1,1,1,1,0,0,0,0,0,1,1,1,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0] };
const tpl6: DigitTemplate = { digit: 6, key: [0,0,0,1,1,1,0,0,0,1,1,1,1,1,0,1,1,1,0,0,0,0,1,1,0,1,0,0,1,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,0,0,1,1,0,1,1,0,0,1,1,0,1,1,1,1,1,1,0,0,1,1,1,0,0] };
const tpl7: DigitTemplate = { digit: 7, key: [1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,0,0,0,0,0,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,0,0,0,0,0,1,1,0,0,0] };
const tpl8: DigitTemplate = { digit: 8, key: [0,0,0,1,1,0,0,0,1,1,1,1,1,0,0,1,1,0,1,1,1,0,1,1,0,0,1,1,0,1,1,1,1,1,0,0,1,1,1,1,1,0,1,1,1,0,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,0] };
const tpl9: DigitTemplate = { digit: 9, key: [0,0,1,1,1,0,0,0,1,1,1,1,1,0,1,1,1,0,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,0,0,0,0,0,1,1,0,0,0,0,1,1,1,0,1,1,1,1,1,0,0,1,1,1,1,0,0] };
export const TEMPLATES: DigitTemplate[] = [tpl1, tpl2, tpl3, tpl4, tpl5, tpl6, tpl7, tpl8, tpl9];

export function countInk(sig: number[]): number {
  let cnt: number = 0;
  for (let i: number = 0; i < sig.length; i++) {
    if (sig[i] === 1) { cnt++; }
  }
  return cnt;
}

const INK_THRESH: number = 50;

export function isInkPixel(g: number, bg: number, isDark: boolean): boolean {
  if (isDark) { return g > bg + INK_THRESH; }
  return g < bg - INK_THRESH;
}

/**
 * 通过行列墨迹投影定位棋盘外框（网格线贯穿整图，投影峰值即线位置）。
 */
export function findBoardBBox(pixels: Uint8Array, width: number, height: number, bg: number): BoardBBox {
  const isDark: boolean = bg < 128;
  const colInk: number[] = new Array<number>(width).fill(0);
  const rowInk: number[] = new Array<number>(height).fill(0);
  for (let x: number = 0; x < width; x++) {
    let c: number = 0;
    for (let y: number = 0; y < height; y += 2) {
      const g: number = 0.299 * pixels[(y * width + x) * 4] +
        0.587 * pixels[(y * width + x) * 4 + 1] +
        0.114 * pixels[(y * width + x) * 4 + 2];
      if (isInkPixel(g, bg, isDark)) { c++; }
    }
    colInk[x] = c;
  }
  for (let y: number = 0; y < height; y++) {
    let c: number = 0;
    for (let x: number = 0; x < width; x += 2) {
      const g: number = 0.299 * pixels[(y * width + x) * 4] +
        0.587 * pixels[(y * width + x) * 4 + 1] +
        0.114 * pixels[(y * width + x) * 4 + 2];
      if (isInkPixel(g, bg, isDark)) { c++; }
    }
    rowInk[y] = c;
  }
  let minX: number = width;
  let maxX: number = 0;
  let minY: number = height;
  let maxY: number = 0;
  let found: boolean = false;
  for (let x: number = 0; x < width; x++) {
    if (colInk[x] / (height / 2) > 0.3) {
      if (x < minX) { minX = x; }
      if (x > maxX) { maxX = x; }
      found = true;
    }
  }
  for (let y: number = 0; y < height; y++) {
    if (rowInk[y] / (width / 2) > 0.3) {
      if (y < minY) { minY = y; }
      if (y > maxY) { maxY = y; }
      found = true;
    }
  }
  if (!found || maxX - minX < width * 0.3 || maxY - minY < height * 0.3) {
    const full: BoardBBox = { left: 0, top: 0, right: width, bottom: height, isDark };
    return full;
  }
  const box: BoardBBox = { left: minX, top: minY, right: maxX, bottom: maxY, isDark };
  return box;
}

/**
 * 提取单元格数字签名: 在数字墨迹的包围盒上做 10x7 归一化采样。
 * 包围盒归一化使识别对数字在格内位置、尺寸不敏感，且对字体较鲁棒。
 * 返回 null 表示该格为空。
 */
export function cellSig(
  pixels: Uint8Array,
  width: number,
  cellLeft: number,
  cellTop: number,
  cellW: number,
  cellH: number,
  isDark: boolean,
  bg: number
): number[] | null {
  const mx: number = cellW * 0.08;
  const my: number = cellH * 0.08;
  const x0: number = Math.floor(cellLeft + mx);
  const y0: number = Math.floor(cellTop + my);
  const x1: number = Math.floor(cellLeft + cellW - mx);
  const y1: number = Math.floor(cellTop + cellH - my);

  let ink: number = 0;
  let area: number = 0;
  let bminX: number = 1000000;
  let bmaxX: number = -1;
  let bminY: number = 1000000;
  let bmaxY: number = -1;

  for (let y: number = y0; y < y1; y++) {
    for (let x: number = x0; x < x1; x++) {
      area++;
      const g: number = 0.299 * pixels[(y * width + x) * 4] +
        0.587 * pixels[(y * width + x) * 4 + 1] +
        0.114 * pixels[(y * width + x) * 4 + 2];
      if (isInkPixel(g, bg, isDark)) {
        ink++;
        if (x < bminX) { bminX = x; }
        if (x > bmaxX) { bmaxX = x; }
        if (y < bminY) { bminY = y; }
        if (y > bmaxY) { bmaxY = y; }
      }
    }
  }

  if (ink < area * 0.02 || bmaxX < 0) {
    return null;
  }

  const bw: number = bmaxX - bminX + 1;
  const bh: number = bmaxY - bminY + 1;
  const sig: number[] = new Array<number>(70).fill(0);
  for (let r: number = 0; r < 10; r++) {
    for (let c: number = 0; c < 7; c++) {
      const sx0: number = bminX + Math.floor(bw * c / 7);
      const sx1: number = bminX + Math.floor(bw * (c + 1) / 7);
      const sy0: number = bminY + Math.floor(bh * r / 10);
      const sy1: number = bminY + Math.floor(bh * (r + 1) / 10);
      let s: number = 0;
      let n: number = 0;
      for (let y: number = sy0; y < sy1; y++) {
        for (let x: number = sx0; x < sx1; x++) {
          s += 0.299 * pixels[(y * width + x) * 4] +
            0.587 * pixels[(y * width + x) * 4 + 1] +
            0.114 * pixels[(y * width + x) * 4 + 2];
          n++;
        }
      }
      const avg: number = n > 0 ? s / n : bg;
      sig[r * 7 + c] = isInkPixel(avg, bg, isDark) ? 1 : 0;
    }
  }

  const inkCount: number = countInk(sig);
  if (inkCount < 6 || inkCount > 66) {
    return null;
  }
  return sig;
}

/**
 * 模板匹配识别数字（F1 + 位置重合评分）
 */
export function recognizeDigit(sig: number[], inkCount: number): number {
  // 墨迹太少不可能是有内容的格子（与 cellSig 中的过滤策略一致）
  if (inkCount < 6) { return 0; }
  let best: number = 0;
  let bestScore: number = -100000;
  for (let ti: number = 0; ti < TEMPLATES.length; ti++) {
    const t: DigitTemplate = TEMPLATES[ti];
    let match: number = 0;
    let tplInk: number = 0;
    let tp: number = 0;
    for (let i: number = 0; i < 70; i++) {
      if (t.key[i] === 1) {
        tplInk++;
        if (sig[i] === 1) { tp++; }
      }
      if (sig[i] === t.key[i]) { match++; }
    }
    const recall: number = tplInk > 0 ? tp / tplInk : 0;
    const prec: number = inkCount > 0 ? tp / inkCount : 0;
    const f1: number = (recall + prec) > 0 ? (2 * recall * prec) / (recall + prec) : 0;
    const score: number = match - (70 - match) * 0.5 + f1 * 40;
    if (score > bestScore) {
      bestScore = score;
      best = t.digit;
    }
  }
  return bestScore >= 12 ? best : 0;
}
