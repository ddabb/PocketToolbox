import { Context } from '@kit.AbilityKit';
import { RawFileUtil } from '../../common/utils/RawFileUtil';

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
export const SIG_ROWS: number = 12;

export const SIG_COLS: number = 8;
const SIG_LEN: number = SIG_ROWS * SIG_COLS;

interface DigitTemplateEntry {
  digit: number;
  font: string;
  key: number[];
}

interface DigitTemplateFile {
  rows: number;
  cols: number;
  templates: DigitTemplateEntry[];
}

let g_templates: DigitTemplate[] = [];
let g_holeRows: number[] = [];
let g_loaded: boolean = false;

export function holeCenterRow(sig: number[]): number {
  const ROWS: number = SIG_ROWS;
  const COLS: number = SIG_COLS;
  const outside: boolean[] = new Array<boolean>(ROWS * COLS).fill(false);
  const stack: number[] = [];
  const pushIfBg: (i: number) => void = (i: number) => {
    if (!outside[i] && sig[i] === 0) { outside[i] = true; stack.push(i); }
  };
  for (let c: number = 0; c < COLS; c++) {
    pushIfBg(c);
    pushIfBg((ROWS - 1) * COLS + c);
  }
  for (let r: number = 0; r < ROWS; r++) {
    pushIfBg(r * COLS);
    pushIfBg(r * COLS + (COLS - 1));
  }
  while (stack.length > 0) {
    const i: number = stack.pop() as number;
    const r: number = Math.floor(i / COLS);
    const c: number = i % COLS;
    if (r > 0) { pushIfBg(i - COLS); }
    if (r < ROWS - 1) { pushIfBg(i + COLS); }
    if (c > 0) { pushIfBg(i - 1); }
    if (c < COLS - 1) { pushIfBg(i + 1); }
  }
  const visited: boolean[] = new Array<boolean>(ROWS * COLS).fill(false);
  const components: number[][] = [];
  for (let i: number = 0; i < ROWS * COLS; i++) {
    if (sig[i] === 0 && !outside[i] && !visited[i]) {
      const comp: number[] = [];
      const cs: number[] = [i];
      visited[i] = true;
      while (cs.length > 0) {
        const j: number = cs.pop() as number;
        comp.push(j);
        const r: number = Math.floor(j / COLS);
        const c: number = j % COLS;
        const push2: (n: number) => void = (n: number) => {
          if (!visited[n] && sig[n] === 0 && !outside[n]) { visited[n] = true; cs.push(n); }
        };
        if (r > 0) { push2(j - COLS); }
        if (r < ROWS - 1) { push2(j + COLS); }
        if (c > 0) { push2(j - 1); }
        if (c < COLS - 1) { push2(j + 1); }
      }
      components.push(comp);
    }
  }
  if (components.length === 0) { return -1; }
  components.sort((a: number[], b: number[]) => b.length - a.length);
  if (components.length >= 2 && components[1].length > components[0].length * 0.6) {
    return -1;
  }
  let sumRow: number = 0;
  for (const j of components[0]) { sumRow += Math.floor(j / COLS); }
  return sumRow / components[0].length;
}

export function inkCentroidRow(sig: number[]): number {
  let sumR: number = 0;
  let cnt: number = 0;
  for (let r: number = 0; r < SIG_ROWS; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) { sumR += r; cnt++; }
    }
  }
  return cnt > 0 ? sumR / cnt : -1;
}

export function topBottomInkRatio(sig: number[]): number {
  const halfRow: number = Math.floor(SIG_ROWS / 2);
  let topInk: number = 0;
  let bottomInk: number = 0;
  for (let r: number = 0; r < SIG_ROWS; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) {
        if (r < halfRow) { topInk++; } else { bottomInk++; }
      }
    }
  }
  if (topInk === 0 && bottomInk === 0) { return 0; }
  return topInk / (topInk + bottomInk);
}

function sigToAscii(sig: number[]): string {
  let s: string = '';
  for (let r: number = 0; r < SIG_ROWS; r++) {
    let line: string = '';
    for (let c: number = 0; c < SIG_COLS; c++) {
      line += sig[r * SIG_COLS + c] ? '#' : '.';
    }
    s += line + '\n';
  }
  return s;
}

export function initDigitTemplates(context: Context): boolean {
  if (g_loaded) { return true; }
  try {
    const file: DigitTemplateFile = RawFileUtil.readJson<DigitTemplateFile>(context, 'digit_templates.json');
    if (!file || !file.templates || file.templates.length === 0) {
      return false;
    }
    g_templates = [];
    for (let i: number = 0; i < file.templates.length; i++) {
      const e: DigitTemplateEntry = file.templates[i];
      g_templates.push({ digit: e.digit, key: e.key });
    }
    g_holeRows = g_templates.map((t: DigitTemplate) => holeCenterRow(t.key));
    g_loaded = true;
    console.info(`[SudokuPixel] 已加载 ${g_templates.length} 个数字模板 (${SIG_ROWS}x${SIG_COLS})`);
    return true;
  } catch (err) {
    console.error(`[SudokuPixel] 加载模板失败: ${(err as Error).message}`);
    return false;
  }
}

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

export function otsuThreshold(hist: number[], total: number): number {
  let sumAll: number = 0;
  for (let i: number = 0; i < 256; i++) { sumAll += i * hist[i]; }
  let sumBg: number = 0;
  let wBg: number = 0;
  let maxVar: number = -1;
  let threshold: number = 128;
  for (let t: number = 0; t < 256; t++) {
    wBg += hist[t];
    if (wBg === 0) { continue; }
    const wFg: number = total - wBg;
    if (wFg === 0) { break; }
    sumBg += t * hist[t];
    const mBg: number = sumBg / wBg;
    const mFg: number = (sumAll - sumBg) / wFg;
    const diff: number = mBg - mFg;
    const varBetween: number = wBg * wFg * diff * diff;
    if (varBetween > maxVar) { maxVar = varBetween; threshold = t; }
  }
  return threshold;
}

export function bgColor(pixels: Uint8Array, width: number, height: number): number {
  const hist: number[] = new Array<number>(256).fill(0);
  const total: number = width * height;
  const step: number = Math.max(1, Math.floor(total / 20000));
  for (let i: number = 0; i < total; i += step) {
    const g: number = 0.299 * pixels[i * 4] +
      0.587 * pixels[i * 4 + 1] +
      0.114 * pixels[i * 4 + 2];
    let gi: number = Math.floor(g);
    if (gi < 0) { gi = 0; }
    if (gi > 255) { gi = 255; }
    hist[gi]++;
  }
  let mode: number = 0;
  let max: number = -1;
  for (let i: number = 0; i < 256; i++) {
    if (hist[i] > max) { max = hist[i]; mode = i; }
  }
  return mode;
}

export function toGrayArray(pixels: Uint8Array, width: number, height: number): Float32Array {
  const gray: Float32Array = new Float32Array(width * height);
  for (let i: number = 0; i < width * height; i++) {
    gray[i] = 0.299 * pixels[i * 4] + 0.587 * pixels[i * 4 + 1] + 0.114 * pixels[i * 4 + 2];
  }
  return gray;
}

function boxBlur(gray: Float32Array, W: number, H: number, radius: number): Float32Array {
  const out: Float32Array = new Float32Array(W * H);
  const tmp: Float32Array = new Float32Array(W * H);
  const k: number = 2 * radius + 1;
  for (let y: number = 0; y < H; y++) {
    let sum: number = 0;
    for (let x: number = 0; x < k; x++) {
      sum += gray[y * W + Math.min(x, W - 1)];
    }
    for (let x: number = 0; x < W; x++) {
      tmp[y * W + x] = sum / k;
      sum -= gray[y * W + Math.max(0, Math.min(W - 1, x - radius))];
      sum += gray[y * W + Math.max(0, Math.min(W - 1, x + radius + 1))];
    }
  }
  for (let x: number = 0; x < W; x++) {
    let sum: number = 0;
    for (let y: number = 0; y < k; y++) {
      sum += tmp[Math.min(y, H - 1) * W + x];
    }
    for (let y: number = 0; y < H; y++) {
      out[y * W + x] = sum / k;
      sum -= tmp[Math.max(0, Math.min(H - 1, y - radius)) * W + x];
      sum += tmp[Math.max(0, Math.min(H - 1, y + radius + 1)) * W + x];
    }
  }
  return out;
}

function dilate3x3(binary: Uint8Array, W: number, H: number): Uint8Array {
  const out: Uint8Array = new Uint8Array(W * H);
  for (let y: number = 0; y < H; y++) {
    for (let x: number = 0; x < W; x++) {
      let m: number = 0;
      const y0: number = Math.max(0, y - 1);
      const y1: number = Math.min(H - 1, y + 1);
      const x0: number = Math.max(0, x - 1);
      const x1: number = Math.min(W - 1, x + 1);
      for (let ny: number = y0; ny <= y1; ny++) {
        for (let nx: number = x0; nx <= x1; nx++) {
          if (binary[ny * W + nx] > m) { m = binary[ny * W + nx]; }
        }
      }
      out[y * W + x] = m;
    }
  }
  return out;
}

function erode3x3(binary: Uint8Array, W: number, H: number): Uint8Array {
  const out: Uint8Array = new Uint8Array(W * H);
  for (let y: number = 0; y < H; y++) {
    for (let x: number = 0; x < W; x++) {
      let m: number = 1;
      const y0: number = Math.max(0, y - 1);
      const y1: number = Math.min(H - 1, y + 1);
      const x0: number = Math.max(0, x - 1);
      const x1: number = Math.min(W - 1, x + 1);
      for (let ny: number = y0; ny <= y1; ny++) {
        for (let nx: number = x0; nx <= x1; nx++) {
          if (binary[ny * W + nx] < m) { m = binary[ny * W + nx]; }
        }
      }
      out[y * W + x] = m;
    }
  }
  return out;
}

function morphOpen3x3(binary: Uint8Array, W: number, H: number): Uint8Array {
  return dilate3x3(erode3x3(binary, W, H), W, H);
}

function grayInkPixel(g: number, bg: number, isDark: boolean, thresh: number): boolean {
  if (isDark) { return g > bg + thresh; }
  return g < bg - thresh;
}

interface ProjectionResult {
  colInk: number[];
  rowInk: number[];
  rw: number;
  rh: number;
}

function computeProjectionsGray(
  gray: Float32Array, W: number, H: number,
  bg: number, isDark: boolean, thresh: number,
  rx0: number, ry0: number, rx1: number, ry1: number,
  step: number
): ProjectionResult {
  const rw: number = rx1 - rx0;
  const rh: number = ry1 - ry0;
  const colInk: number[] = new Array<number>(rw).fill(0);
  const rowInk: number[] = new Array<number>(rh).fill(0);
  for (let x: number = 0; x < rw; x++) {
    let c: number = 0;
    for (let y: number = 0; y < rh; y += step) {
      const g: number = gray[(y + ry0) * W + (x + rx0)];
      if (grayInkPixel(g, bg, isDark, thresh)) { c++; }
    }
    colInk[x] = c;
  }
  for (let y: number = 0; y < rh; y++) {
    let c: number = 0;
    for (let x: number = 0; x < rw; x += step) {
      const g: number = gray[(y + ry0) * W + (x + rx0)];
      if (grayInkPixel(g, bg, isDark, thresh)) { c++; }
    }
    rowInk[y] = c;
  }
  const result: ProjectionResult = { colInk: colInk, rowInk: rowInk, rw: rw, rh: rh };
  return result;
}

function findBBoxFromProjections(
  colInk: number[], rowInk: number[],
  rw: number, rh: number,
  rx0: number, ry0: number,
  threshold: number, minFrac: number,
  sampleStep: number,
  isDark: boolean
): BoardBBox | null {
  let minX: number = rw;
  let maxX: number = 0;
  let minY: number = rh;
  let maxY: number = 0;
  let found: boolean = false;
  for (let x: number = 0; x < rw; x++) {
    if (colInk[x] / (rh / sampleStep) > threshold) {
      if (x < minX) { minX = x; }
      if (x > maxX) { maxX = x; }
      found = true;
    }
  }
  for (let y: number = 0; y < rh; y++) {
    if (rowInk[y] / (rw / sampleStep) > threshold) {
      if (y < minY) { minY = y; }
      if (y > maxY) { maxY = y; }
      found = true;
    }
  }
  if (!found || maxX - minX < rw * minFrac || maxY - minY < rh * minFrac) {
    return null;
  }
  const bw: number = maxX - minX + 1;
  const bh: number = maxY - minY + 1;
  if (bw < 10 || bh < 10) { return null; }
  return { left: minX + rx0, top: minY + ry0, right: maxX + rx0, bottom: maxY + ry0, isDark };
}

function findBBoxInRectGray(
  gray: Float32Array, W: number, H: number,
  bg: number, isDark: boolean,
  rx0: number, ry0: number, rx1: number, ry1: number,
  threshold: number, minFrac: number
): BoardBBox | null {
  const rw: number = rx1 - rx0;
  const rh: number = ry1 - ry0;
  if (rw < 10 || rh < 10) { return null; }
  const proj = computeProjectionsGray(gray, W, H, bg, isDark, INK_THRESH, rx0, ry0, rx1, ry1, 2);
  return findBBoxFromProjections(proj.colInk, proj.rowInk, proj.rw, proj.rh, rx0, ry0, threshold, minFrac, 2, isDark);
}

function findBBoxInRect(
  pixels: Uint8Array, width: number, height: number,
  bg: number, isDark: boolean,
  rx0: number, ry0: number, rx1: number, ry1: number,
  threshold: number, minFrac: number
): BoardBBox | null {
  const rw: number = rx1 - rx0;
  const rh: number = ry1 - ry0;
  if (rw < 10 || rh < 10) { return null; }
  const colInk: number[] = new Array<number>(rw).fill(0);
  const rowInk: number[] = new Array<number>(rh).fill(0);
  for (let x: number = 0; x < rw; x++) {
    let c: number = 0;
    for (let y: number = 0; y < rh; y += 2) {
      const g: number = 0.299 * pixels[((y + ry0) * width + (x + rx0)) * 4] +
        0.587 * pixels[((y + ry0) * width + (x + rx0)) * 4 + 1] +
        0.114 * pixels[((y + ry0) * width + (x + rx0)) * 4 + 2];
      if (isInkPixel(g, bg, isDark)) { c++; }
    }
    colInk[x] = c;
  }
  for (let y: number = 0; y < rh; y++) {
    let c: number = 0;
    for (let x: number = 0; x < rw; x += 2) {
      const g: number = 0.299 * pixels[((y + ry0) * width + (x + rx0)) * 4] +
        0.587 * pixels[((y + ry0) * width + (x + rx0)) * 4 + 1] +
        0.114 * pixels[((y + ry0) * width + (x + rx0)) * 4 + 2];
      if (isInkPixel(g, bg, isDark)) { c++; }
    }
    rowInk[y] = c;
  }
  return findBBoxFromProjections(colInk, rowInk, rw, rh, rx0, ry0, threshold, minFrac, 2, isDark);
}

function isValidBoardAspect(bbox: BoardBBox, W: number, H: number): boolean {
  const bw: number = bbox.right - bbox.left;
  const bh: number = bbox.bottom - bbox.top;
  if (bw < 10 || bh < 10) { return false; }
  const aspect: number = bw / bh;
  if (aspect < 0.3 || aspect > 3.0) { return false; }
  if (bw < W * 0.1 || bh < H * 0.1) { return false; }
  return true;
}

function findPeriodicPeaks(frac: number[], threshold: number): number[] {
  const peaks: number[] = [];
  for (let i: number = 0; i < frac.length; i++) {
    if (frac[i] > threshold) {
      let end: number = i;
      while (end + 1 < frac.length && frac[end + 1] > threshold) { end++; }
      peaks.push(Math.floor((i + end) / 2));
      i = end;
    }
  }
  if (peaks.length < 5) { return peaks; }
  let bestSpacing: number = 0;
  let bestConf: number = 0;
  const minSpacing: number = Math.max(3, Math.floor(frac.length / 15));
  const maxSpacing: number = Math.floor(frac.length / 5);
  for (let sp: number = minSpacing; sp <= maxSpacing; sp++) {
    let count: number = 0;
    let sumDiff: number = 0;
    let lastPeak: number = -sp * 2;
    for (const p of peaks) {
      const diff: number = p - lastPeak;
      if (diff >= sp * 0.7 && diff <= sp * 1.3) {
        count++;
        sumDiff += Math.abs(diff - sp);
        lastPeak = p;
      } else if (diff > sp * 1.3) {
        lastPeak = p;
      }
    }
    if (count >= 5) {
      const avgDev: number = count > 0 ? sumDiff / count / sp : 1;
      const conf: number = count - avgDev * 2;
      if (conf > bestConf) { bestConf = conf; bestSpacing = sp; }
    }
  }
  if (bestSpacing > 0) {
    const selected: number[] = [];
    let lastPeak: number = -bestSpacing * 2;
    for (const p of peaks) {
      const diff: number = p - lastPeak;
      if (diff >= bestSpacing * 0.7 && diff <= bestSpacing * 1.3) {
        selected.push(p);
        lastPeak = p;
      } else if (diff > bestSpacing * 1.3) {
        selected.length = 0;
        selected.push(p);
        lastPeak = p;
      }
    }
    if (selected.length >= 5) { return selected; }
  }
  let bestStart: number = 0;
  let bestCount: number = 0;
  for (let i: number = 0; i < peaks.length - 1; i++) {
    const spacing: number = peaks[i + 1] - peaks[i];
    if (spacing < 3) { continue; }
    let count: number = 2;
    let lastPos: number = peaks[i + 1];
    for (let j: number = i + 2; j < peaks.length; j++) {
      if (peaks[j] - lastPos <= spacing * 1.3 && peaks[j] - lastPos >= spacing * 0.7) {
        count++;
        lastPos = peaks[j];
      }
    }
    if (count > bestCount) { bestCount = count; bestStart = i; }
  }
  if (bestCount >= 5) { return peaks.slice(bestStart, bestStart + bestCount); }
  return peaks;
}

function findBBoxAdaptive(gray: Float32Array, W: number, H: number, isDark: boolean): BoardBBox | null {
  const winR: number = Math.max(5, Math.floor(Math.min(W, H) / 25));
  const blurred: Float32Array = boxBlur(gray, W, H, winR);

  for (const C of [8, 12, 5]) {
    let binary: Uint8Array = new Uint8Array(W * H);
    for (let i: number = 0; i < W * H; i++) {
      if (isDark) {
        binary[i] = (gray[i] > blurred[i] + C) ? 1 : 0;
      } else {
        binary[i] = (gray[i] < blurred[i] - C) ? 1 : 0;
      }
    }
    binary = morphOpen3x3(binary, W, H);
    binary = dilate3x3(dilate3x3(binary, W, H), W, H);

    const colInk: number[] = new Array<number>(W).fill(0);
    const rowInk: number[] = new Array<number>(H).fill(0);
    for (let x: number = 0; x < W; x++) {
      let c: number = 0;
      for (let y: number = 0; y < H; y += 2) {
        if (binary[y * W + x] === 1) { c++; }
      }
      colInk[x] = c;
    }
    for (let y: number = 0; y < H; y++) {
      let c: number = 0;
      for (let x: number = 0; x < W; x += 2) {
        if (binary[y * W + x] === 1) { c++; }
      }
      rowInk[y] = c;
    }
    const colFrac: number[] = colInk.map((c: number) => c / (H / 2));
    const rowFrac: number[] = rowInk.map((c: number) => c / (W / 2));

    for (const thresh of [0.3, 0.25, 0.20, 0.15]) {
      let minX: number = W;
      let maxX: number = 0;
      let minY: number = H;
      let maxY: number = 0;
      let found: boolean = false;
      for (let x: number = 0; x < W; x++) {
        if (colFrac[x] > thresh) { if (x < minX) { minX = x; } if (x > maxX) { maxX = x; } found = true; }
      }
      for (let y: number = 0; y < H; y++) {
        if (rowFrac[y] > thresh) { if (y < minY) { minY = y; } if (y > maxY) { maxY = y; } found = true; }
      }
      if (found) {
        const bbox: BoardBBox = { left: minX, top: minY, right: maxX, bottom: maxY, isDark };
        if (isValidBoardAspect(bbox, W, H) && maxX - minX >= W * 0.1 && maxY - minY >= H * 0.1) {
          return bbox;
        }
      }
    }

    const colPeaks: number[] = findPeriodicPeaks(colFrac, 0.10);
    const rowPeaks: number[] = findPeriodicPeaks(rowFrac, 0.10);
    if (colPeaks.length >= 5 && rowPeaks.length >= 5) {
      const bbox: BoardBBox = {
        left: colPeaks[0], top: rowPeaks[0],
        right: colPeaks[colPeaks.length - 1], bottom: rowPeaks[rowPeaks.length - 1], isDark
      };
      if (isValidBoardAspect(bbox, W, H)) {
        return bbox;
      }
    }
  }
  return null;
}

function findBBoxConservative(
  gray: Float32Array, W: number, H: number, isDark: boolean, bg: number
): BoardBBox | null {
  // 全局阈值策略：直接用 bg 值做全局二值化，保留细网格线（不使用形态学开运算，
  // 因为开运算会擦除 1-2px 宽的网格线）。然后通过周期性峰检测定位棋盘。
  // 从大 delta 开始（严格阈值→干净二值图），逐步放宽。
  for (const delta of [90, 80, 70, 60, 50, 40]) {
    const thr: number = isDark ? bg + delta : bg - delta;
    const binary: Uint8Array = new Uint8Array(W * H);
    for (let i: number = 0; i < W * H; i++) {
      binary[i] = isDark ? (gray[i] > thr ? 1 : 0)
        : (gray[i] < thr ? 1 : 0);
    }

    // 列投影和行投影
    const colInk: number[] = new Array(W).fill(0);
    const rowInk: number[] = new Array(H).fill(0);
    for (let x: number = 0; x < W; x++) {
      let c: number = 0;
      for (let y: number = 0; y < H; y += 2) {
        if (binary[y * W + x] === 1) { c++; }
      }
      colInk[x] = c;
    }
    for (let y: number = 0; y < H; y++) {
      let c: number = 0;
      for (let x: number = 0; x < W; x += 2) {
        if (binary[y * W + x] === 1) { c++; }
      }
      rowInk[y] = c;
    }
    const colFrac: number[] = colInk.map((c: number) => c / (H / 2));
    const rowFrac: number[] = rowInk.map((c: number) => c / (W / 2));

    // 周期性峰检测：数独棋盘有 9 个等间距格子 → 10 条网格线 → 投影上出现周期性峰
    const colPeaks: number[] = findPeriodicPeaks(colFrac, 0.05);
    const rowPeaks: number[] = findPeriodicPeaks(rowFrac, 0.05);

    // 数独棋盘应有接近 10 条网格线（9 格子）→ 峰数应在 7~14 范围
    if (colPeaks.length >= 7 && rowPeaks.length >= 7) {
      const bbox: BoardBBox = {
        left: colPeaks[0], top: rowPeaks[0],
        right: colPeaks[colPeaks.length - 1], bottom: rowPeaks[rowPeaks.length - 1],
        isDark
      };
      const bw: number = bbox.right - bbox.left + 1;
      const bh: number = bbox.bottom - bbox.top + 1;
      if (bw < 20 || bh < 20) { continue; }
      const aspect: number = bw / bh;
      if (aspect < 0.45 || aspect > 2.2) { continue; }
      const areaRatio: number = (bw * bh) / (W * H);
      if (areaRatio > 0.88) { continue; }  // 拒绝退化到全图
      return bbox;
    }
  }

  return null;
}

// 长行程棋盘定位：数独棋盘的 10 条横线与 10 条竖线都是贯穿整张棋盘的长直线，
// 而木纹/阴影等背景噪声多为短促笔画或渐变，不构成贯穿直线。
// 对"严格阈值二值图"做长行程(run-length)过滤并排除贴图像边缘的行程，
// 仅保留属于长水平/垂直笔画的像素，其包围盒即为棋盘。
// 该方法对 photos.jpg（浅木纹桌面 + 顶部阴影）这类复杂背景鲁棒。
function findBoxLongRun(
  gray: Float32Array, W: number, H: number, isDark: boolean, bg: number
): BoardBBox | null {
  const abs: number = isDark ? Math.max(150, bg + 60) : Math.min(80, bg - 60);
  const ink: Uint8Array = new Uint8Array(W * H);
  for (let i: number = 0; i < W * H; i++) {
    ink[i] = isDark ? (gray[i] > abs ? 1 : 0) : (gray[i] < abs ? 1 : 0);
  }
  const keep: Uint8Array = new Uint8Array(W * H);
  const MINRUN: number = Math.max(20, Math.floor(Math.min(W, H) * 0.10));
  // 水平长行程（跳过贴图像边缘的行程 → 排除边缘木纹/暗角）
  for (let y: number = 0; y < H; y++) {
    let run: number = 0;
    let start: number = 0;
    for (let x: number = 0; x <= W; x++) {
      if (x < W && ink[y * W + x] === 1) {
        if (run === 0) { start = x; }
        run++;
      } else {
        if (run >= MINRUN && start > 0 && x < W) {
          for (let xx: number = start; xx < x; xx++) { keep[y * W + xx] = 1; }
        }
        run = 0;
      }
    }
  }
  // 垂直长行程
  for (let x: number = 0; x < W; x++) {
    let run: number = 0;
    let start: number = 0;
    for (let y: number = 0; y < H; y++) {
      if (ink[y * W + x] === 1) {
        if (run === 0) { start = y; }
        run++;
      } else {
        if (run >= MINRUN && start > 0 && y < H) {
          for (let yy: number = start; yy < y; yy++) { keep[yy * W + x] = 1; }
        }
        run = 0;
      }
    }
  }
  let minX: number = W, maxX: number = 0, minY: number = H, maxY: number = 0, n: number = 0;
  for (let y: number = 0; y < H; y++) {
    for (let x: number = 0; x < W; x++) {
      if (keep[y * W + x] === 1) {
        n++;
        if (x < minX) { minX = x; }
        if (x > maxX) { maxX = x; }
        if (y < minY) { minY = y; }
        if (y > maxY) { maxY = y; }
      }
    }
  }
  if (n < 50) { return null; }
  const bw: number = maxX - minX + 1;
  const bh: number = maxY - minY + 1;
  if (bw < 20 || bh < 20) { return null; }
  const aspect: number = bw / bh;
  if (aspect < 0.5 || aspect > 2.0) { return null; }
  const areaRatio: number = (bw * bh) / (W * H);
  if (areaRatio < 0.02 || areaRatio > 0.85) { return null; }
  return { left: minX, top: minY, right: maxX, bottom: maxY, isDark };
}

export function findBoardBBox(pixels: Uint8Array, width: number, height: number, bg: number): BoardBBox {
  const isDark: boolean = bg < 128;
  const gray: Float32Array = toGrayArray(pixels, width, height);
  const imgArea: number = width * height;

  // 长行程检测优先：对木纹/阴影等复杂背景鲁棒，能稳定定位棋盘（如 photos.jpg）。
  // 若找到合法的方形棋盘包围盒则直接返回，避免后续区域搜索返回退化包围盒。
  const longRun: BoardBBox | null = findBoxLongRun(gray, width, height, isDark, bg);
  if (longRun !== null) { return longRun; }

  const isDegenerate = (b: BoardBBox): boolean => {
    return ((b.right - b.left) * (b.bottom - b.top)) > imgArea * 0.88;
  };

  const primary: BoardBBox | null = findBBoxInRectGray(
    gray, width, height, bg, isDark, 0, 0, width, height, 0.3, 0.3
  );
  if (primary !== null && isValidBoardAspect(primary, width, height) && !isDegenerate(primary)) { return primary; }

  for (const thresh of [0.20, 0.15]) {
    const res: BoardBBox | null = findBBoxInRectGray(
      gray, width, height, bg, isDark, 0, 0, width, height, thresh, 0.15
    );
    if (res !== null && isValidBoardAspect(res, width, height) && !isDegenerate(res)) { return res; }
  }

  const regions: number[][] = [
    [0, 0, Math.floor(width * 0.6), Math.floor(height * 0.6)],
    [Math.floor(width * 0.4), 0, width, Math.floor(height * 0.6)],
    [0, Math.floor(height * 0.4), Math.floor(width * 0.6), height],
    [Math.floor(width * 0.4), Math.floor(height * 0.4), width, height],
    [Math.floor(width * 0.15), Math.floor(height * 0.15), Math.floor(width * 0.85), Math.floor(height * 0.85)],
  ];
  if (height > width * 1.3) {
    regions.push(
      [0, 0, width, Math.floor(height * 0.5)],
      [0, Math.floor(height * 0.1), width, Math.floor(height * 0.6)],
      [Math.floor(width * 0.1), 0, Math.floor(width * 0.9), Math.floor(height * 0.45)]
    );
  }
  if (width > height * 1.3) {
    regions.push(
      [0, 0, Math.floor(width * 0.5), height],
      [Math.floor(width * 0.1), 0, Math.floor(width * 0.6), height],
      [0, Math.floor(height * 0.1), Math.floor(width * 0.45), Math.floor(height * 0.9)]
    );
  }
  let bestArea: number = 0;
  let bestBox: BoardBBox | null = null;
  for (let ri: number = 0; ri < regions.length; ri++) {
    const r: number[] = regions[ri];
    for (const thresh of [0.30, 0.20, 0.15]) {
      const res: BoardBBox | null = findBBoxInRectGray(
        gray, width, height, bg, isDark,
        r[0], r[1], r[2], r[3], thresh, 0.10
      );
      if (res !== null && isValidBoardAspect(res, width, height)) {
        const area: number = (res.right - res.left) * (res.bottom - res.top);
        // 拒绝接近全图的退化 bbox（面积 > 88% 说明背景噪声污染）
        if (area < width * height * 0.88) {
          if (area > bestArea) { bestArea = area; bestBox = res; }
        }
        break;
      }
    }
  }

  // 保守检测：全局阈值 + 周期性峰检测（保留细网格线，不使用形态学开运算）
  // 针对照片等复杂背景（木纹/纹理/阴影），在区域搜索结果返回之前尝试
  const conservative: BoardBBox | null = findBBoxConservative(gray, width, height, isDark, bg);
  if (conservative !== null) { return conservative; }

  if (bestBox !== null) { return bestBox; }

  const adaptive: BoardBBox | null = findBBoxAdaptive(gray, width, height, isDark);
  if (adaptive !== null) {
    const aArea: number = (adaptive.right - adaptive.left) * (adaptive.bottom - adaptive.top);
    // 拦截退化 bbox（接近全图 → 说明投影法被背景噪声污染）
    if (aArea < width * height * 0.88) { return adaptive; }
    // adaptive 返回了疑似退化结果，继续尝试保守检测
  }

  return { left: 0, top: 0, right: width, bottom: height, isDark };
}

export function cellSigFromGray(
  gray: Float32Array,
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
  const H: number = Math.floor(gray.length / width);

  let ink: number = 0;
  let area: number = 0;
  let bminX: number = 1000000;
  let bmaxX: number = -1;
  let bminY: number = 1000000;
  let bmaxY: number = -1;

  for (let y: number = y0; y < y1; y++) {
    for (let x: number = x0; x < x1; x++) {
      area++;
      const g: number = gray[y * width + x];
      if (grayInkPixel(g, bg, isDark, INK_THRESH)) {
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

  const sig: number[] = new Array<number>(SIG_LEN).fill(0);
  for (let r: number = 0; r < SIG_ROWS; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      const sx0: number = bminX + Math.floor(bw * c / SIG_COLS);
      const sx1: number = bminX + Math.floor(bw * (c + 1) / SIG_COLS);
      const sy0: number = bminY + Math.floor(bh * r / SIG_ROWS);
      const sy1: number = bminY + Math.floor(bh * (r + 1) / SIG_ROWS);
      let s: number = 0;
      let n: number = 0;
      for (let y: number = sy0; y < sy1; y++) {
        for (let x: number = sx0; x < sx1; x++) {
          if (y >= 0 && y < H && x >= 0 && x < width) {
            s += gray[y * width + x];
            n++;
          }
        }
      }
      const avg: number = n > 0 ? s / n : bg;
      sig[r * SIG_COLS + c] = grayInkPixel(avg, bg, isDark, INK_THRESH) ? 1 : 0;
    }
  }

  const inkCount: number = countInk(sig);
  if (inkCount < 6 || inkCount > 90) {
    const fallbackSig: number[] | null = cellSigOtsuFallbackGray(
      gray, width, bminX, bminY, bw, bh, isDark, bg
    );
    if (fallbackSig !== null) {
      const fbInk: number = countInk(fallbackSig);
      if (fbInk >= 6 && fbInk <= 90) {
        return fallbackSig;
      }
    }
    return null;
  }
  return sig;
}

function cellSigOtsuFallbackGray(
  gray: Float32Array, width: number,
  bminX: number, bminY: number, bw: number, bh: number,
  isDark: boolean, bg: number
): number[] | null {
  const H: number = Math.floor(gray.length / width);
  const bboxHist: number[] = new Array<number>(256).fill(0);
  let bboxTotal: number = 0;
  for (let y: number = bminY; y < bminY + bh; y++) {
    for (let x: number = bminX; x < bminX + bw; x++) {
      if (y >= 0 && y < H && x >= 0 && x < width) {
        const g: number = gray[y * width + x];
        const gi: number = Math.floor(g);
        if (gi >= 0 && gi <= 255) {
          bboxHist[gi]++;
          bboxTotal++;
        }
      }
    }
  }
  if (bboxTotal < 30) { return null; }

  const otsuT: number = otsuThreshold(bboxHist, bboxTotal);
  if (Math.abs(otsuT - bg) < 12) { return null; }

  const sig: number[] = new Array<number>(SIG_LEN).fill(0);
  for (let r: number = 0; r < SIG_ROWS; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      const sx0: number = bminX + Math.floor(bw * c / SIG_COLS);
      const sx1: number = bminX + Math.floor(bw * (c + 1) / SIG_COLS);
      const sy0: number = bminY + Math.floor(bh * r / SIG_ROWS);
      const sy1: number = bminY + Math.floor(bh * (r + 1) / SIG_ROWS);
      let s: number = 0;
      let n: number = 0;
      for (let y: number = sy0; y < sy1; y++) {
        for (let x: number = sx0; x < sx1; x++) {
          if (y >= 0 && y < H && x >= 0 && x < width) {
            s += gray[y * width + x];
            n++;
          }
        }
      }
      const avg: number = n > 0 ? s / n : bg;
      sig[r * SIG_COLS + c] = isDark ? (avg > otsuT ? 1 : 0) : (avg < otsuT ? 1 : 0);
    }
  }

  const inkCount: number = countInk(sig);
  if (inkCount < 6 || inkCount > 90) { return null; }
  return sig;
}

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

  const sig: number[] = new Array<number>(SIG_LEN).fill(0);
  for (let r: number = 0; r < SIG_ROWS; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      const sx0: number = bminX + Math.floor(bw * c / SIG_COLS);
      const sx1: number = bminX + Math.floor(bw * (c + 1) / SIG_COLS);
      const sy0: number = bminY + Math.floor(bh * r / SIG_ROWS);
      const sy1: number = bminY + Math.floor(bh * (r + 1) / SIG_ROWS);
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
      sig[r * SIG_COLS + c] = isInkPixel(avg, bg, isDark) ? 1 : 0;
    }
  }

  const inkCount: number = countInk(sig);
  if (inkCount < 6 || inkCount > 90) {
    const fallbackSig: number[] | null = cellSigOtsuFallback(
      pixels, width, bminX, bminY, bw, bh, isDark, bg
    );
    if (fallbackSig !== null) {
      const fbInk: number = countInk(fallbackSig);
      if (fbInk >= 6 && fbInk <= 90) {
        return fallbackSig;
      }
    }
    return null;
  }
  return sig;
}

function cellSigOtsuFallback(
  pixels: Uint8Array, width: number,
  bminX: number, bminY: number, bw: number, bh: number,
  isDark: boolean, bg: number
): number[] | null {
  const bboxHist: number[] = new Array<number>(256).fill(0);
  let bboxTotal: number = 0;
  for (let y: number = bminY; y < bminY + bh; y++) {
    for (let x: number = bminX; x < bminX + bw; x++) {
      const g: number = 0.299 * pixels[(y * width + x) * 4] +
        0.587 * pixels[(y * width + x) * 4 + 1] +
        0.114 * pixels[(y * width + x) * 4 + 2];
      const gi: number = Math.floor(g);
      bboxHist[gi]++;
      bboxTotal++;
    }
  }
  if (bboxTotal < 30) { return null; }

  const otsuT: number = otsuThreshold(bboxHist, bboxTotal);
  if (Math.abs(otsuT - bg) < 12) { return null; }

  const sig: number[] = new Array<number>(SIG_LEN).fill(0);
  for (let r: number = 0; r < SIG_ROWS; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      const sx0: number = bminX + Math.floor(bw * c / SIG_COLS);
      const sx1: number = bminX + Math.floor(bw * (c + 1) / SIG_COLS);
      const sy0: number = bminY + Math.floor(bh * r / SIG_ROWS);
      const sy1: number = bminY + Math.floor(bh * (r + 1) / SIG_ROWS);
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
      sig[r * SIG_COLS + c] = isDark ? (avg > otsuT ? 1 : 0) : (avg < otsuT ? 1 : 0);
    }
  }

  const inkCount: number = countInk(sig);
  if (inkCount < 6 || inkCount > 90) { return null; }
  return sig;
}

function loopVerticalCenter(sig: number[]): number {
  let sumR: number = 0;
  let cnt: number = 0;
  const startRow: number = Math.floor(SIG_ROWS * 0.2);
  const endRow: number = Math.floor(SIG_ROWS * 0.8);
  for (let r: number = startRow; r < endRow; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) { sumR += r; cnt++; }
    }
  }
  return cnt > 0 ? sumR / cnt : SIG_ROWS / 2;
}

export function recognizeDigit(sig: number[], inkCount: number): number {
  if (inkCount < 6) { return 0; }
  if (g_templates.length === 0) { return 0; }
  const qHole: number = holeCenterRow(sig);

  const digitBestScore: number[] = new Array<number>(10).fill(-100000);
  const digitBestIdx: number[] = new Array<number>(10).fill(-1);
  for (let ti: number = 0; ti < g_templates.length; ti++) {
    const t: DigitTemplate = g_templates[ti];
    let match: number = 0;
    let tplInk: number = 0;
    let tp: number = 0;
    for (let i: number = 0; i < SIG_LEN; i++) {
      if (t.key[i] === 1) {
        tplInk++;
        if (sig[i] === 1) { tp++; }
      }
      if (sig[i] === t.key[i]) { match++; }
    }
    const recall: number = tplInk > 0 ? tp / tplInk : 0;
    const prec: number = inkCount > 0 ? tp / inkCount : 0;
    const f1: number = (recall + prec) > 0 ? (2 * recall * prec) / (recall + prec) : 0;
    const score: number = match - (SIG_LEN - match) * 0.5 + f1 * 40;
    if (score > digitBestScore[t.digit]) {
      digitBestScore[t.digit] = score;
      digitBestIdx[t.digit] = ti;
    }
  }

  let bestDigit: number = 0;
  let bestScore: number = -100000;
  let secondDigit: number = 0;
  let secondScore: number = -100000;
  for (let d: number = 1; d <= 9; d++) {
    if (digitBestScore[d] > bestScore) {
      secondDigit = bestDigit; secondScore = bestScore;
      bestDigit = d; bestScore = digitBestScore[d];
    } else if (digitBestScore[d] > secondScore) {
      secondDigit = d; secondScore = digitBestScore[d];
    }
  }

  if (bestDigit === 6 || bestDigit === 9) {
    const qHole: number = holeCenterRow(sig);
    const iCentroid: number = inkCentroidRow(sig);
    const ratio: number = topBottomInkRatio(sig);
    const score6: number = digitBestScore[6];
    const score9: number = digitBestScore[9];

    console.info(`[SudokuPixel] 6/9消歧: score6=${score6.toFixed(1)} score9=${score9.toFixed(1)} qHole=${qHole.toFixed(2)} centroid=${iCentroid.toFixed(2)} topRatio=${ratio.toFixed(2)}`);
    console.info(`[SudokuPixel] sig:\n${sigToAscii(sig)}`);

    let vote6: number = 0;
    let vote9: number = 0;

    if (qHole >= 0) {
      if (qHole > SIG_ROWS / 2) { vote6 += 2; } else { vote9 += 2; }
    }
    if (iCentroid >= 0) {
      if (iCentroid > SIG_ROWS / 2) { vote6++; } else { vote9++; }
    }
    if (ratio > 0.5) { vote9++; } else { vote6++; }
    if (score6 > score9) { vote6++; } else { vote9++; }

    console.info(`[SudokuPixel] vote6=${vote6} vote9=${vote9} => ${vote6 >= vote9 ? 6 : 9}`);
    return vote6 >= vote9 ? 6 : 9;
  }

  if (qHole >= 0 && bestScore >= 12 && secondDigit > 0) {
    const halfRow: number = SIG_ROWS / 2;
    const halfOf: (h: number) => number = (h: number) => (h < 0 ? 0 : (h <= halfRow ? 1 : 2));
    const bh: number = halfOf(g_holeRows[digitBestIdx[bestDigit]]);
    const sh: number = halfOf(g_holeRows[digitBestIdx[secondDigit]]);
    if (bh !== 0 && sh !== 0 && bh !== sh) {
      const qh: number = halfOf(qHole);
      if (qh !== 0 && qh === sh) { bestDigit = secondDigit; }
    }
  }

  return bestScore >= 12 ? bestDigit : 0;
}
