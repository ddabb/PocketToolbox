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

export interface BoardCorners {
  topLeftX: number;
  topLeftY: number;
  topRightX: number;
  topRightY: number;
  bottomRightX: number;
  bottomRightY: number;
  bottomLeftX: number;
  bottomLeftY: number;
  isDark: boolean;
  confidence: number;
}

export interface HoughLine {
  rho: number;
  theta: number;
  votes: number;
}

export interface GridLines {
  hLines: number[];
  vLines: number[];
}
export const SIG_ROWS: number = 28;

export const SIG_COLS: number = 20;
const SIG_LEN: number = SIG_ROWS * SIG_COLS;

// --- Tunable constants for pixel-level digit recognition ---

// Ink ratio bounds: a valid digit signature must have ink ratio between
// MIN_INK_RATIO and MAX_INK_RATIO. Too little ink = noise; too much = smudge.
const MIN_INK_RATIO: number = 0.25;
const MAX_INK_RATIO: number = 0.75;
const MIN_INK_COUNT: number = Math.floor(SIG_LEN * MIN_INK_RATIO);
const MAX_INK_COUNT: number = Math.floor(SIG_LEN * MAX_INK_RATIO);

// Minimum template-match score (out of SIG_LEN) for a digit to be accepted.
// SIG_LEN * 0.65 ≈ 364 of 560 pixels must match template.
const MIN_DIGIT_SCORE: number = Math.floor(SIG_LEN * 0.65);

// Ink detection threshold: a pixel is "ink" if its gray value differs from
// the background by at least INK_THRESH. Lower = more sensitive to faint ink;
// higher = more selective, avoids noise.
const INK_THRESH: number = 50;

// Sauvola adaptive thresholding parameters:
//   k controls sensitivity to local variance (0.2 = moderate).
//   R is the dynamic range of standard deviation (128 for 8-bit images).
const SAUVOLA_K: number = 0.2;
const SAUVOLA_R: number = 128;

// Cell margin: when extracting a cell signature, skip the outer 8% of cell
// width/height on each side to avoid grid-line pixels bleeding in.
const CELL_MARGIN_RATIO: number = 0.08;

// Minimum ink ratio (relative to cell area) for a cell to be considered
// occupied. Cells with ink ratio below this are treated as empty.
const MIN_CELL_INK_RATIO: number = 0.04;

// Otsu fallback: reject the Otsu threshold if it is too close to the
// background value (within OTSU_BG_MIN_DIFF gray levels).
const OTSU_BG_MIN_DIFF: number = 12;

// Otsu fallback: minimum number of pixels in the bounding box to compute
// a meaningful Otsu threshold.
const OTSU_MIN_PIXELS: number = 30;

// Background color sampling: use at most BG_SAMPLE_COUNT pixels (sampled
// uniformly) to build the histogram. Prevents slow histogram on large images.
const BG_SAMPLE_COUNT: number = 20000;

// Board detection: minimum dimension (px) for a detected bounding box
// to be considered valid. Smaller regions are ignored.
const MIN_BOARD_DIM: number = 10;

// Board detection: reject bounding boxes whose aspect ratio is outside
// [MIN_BOARD_ASPECT, MAX_BOARD_ASPECT]. A valid Sudoku board is roughly square.
const MIN_BOARD_ASPECT: number = 0.3;
const MAX_BOARD_ASPECT: number = 3.0;

// Board detection: reject bounding boxes whose area exceeds this fraction
// of the total image area (likely a degenerate full-image detection).
const MAX_BOARD_AREA_RATIO: number = 0.88;

// Board detection: reject bounding boxes whose area is below this fraction
// of the total image area (likely noise or a tiny artifact).
const MIN_BOARD_AREA_RATIO: number = 0.02;

// Board detection: minimum board dimension as fraction of image dimension
// for the board to be considered valid.
const MIN_BOARD_SIZE_FRAC: number = 0.1;

// findBBoxAdaptive: contrast offsets tried when binarizing the image.
// Larger values = stricter threshold = cleaner but possibly incomplete binary.
const ADAPTIVE_CONTRASTS: number[] = [8, 12, 5];

// findBBoxAdaptive: projection fraction thresholds tried to find ink regions.
const ADAPTIVE_THRESHOLDS: number[] = [0.3, 0.25, 0.20, 0.15];

// findBBoxAdaptive: peak detection threshold for periodic grid-line analysis.
const ADAPTIVE_PEAK_THRESH: number = 0.10;

// findBBoxConservative: delta offsets tried for global-threshold binarization.
// Starts strict (delta=90) and relaxes progressively.
const CONSERVATIVE_DELTAS: number[] = [90, 80, 70, 60, 50, 40];

// findBBoxConservative: peak detection threshold for periodic grid-line analysis.
const CONSERVATIVE_PEAK_THRESH: number = 0.05;

// findBBoxConservative: minimum peak count to consider a valid grid.
const CONSERVATIVE_MIN_PEAKS: number = 7;

// findBBoxConservative: aspect ratio bounds for a valid board.
const CONSERVATIVE_MIN_ASPECT: number = 0.45;
const CONSERVATIVE_MAX_ASPECT: number = 2.2;

// findBBoxConservative: minimum board dimension in pixels.
const CONSERVATIVE_MIN_DIM: number = 20;

// findBoxLongRun: minimum run length (px) for a horizontal/vertical stroke
// to be considered a grid line. Shorter runs are likely noise (wood grain, etc).
// Computed as max(20, imageMinDim * 0.10).
const MINRUN_ABS_MIN: number = 20;
const MINRUN_FRAC: number = 0.10;

// findBoxLongRun: minimum number of kept pixels for a valid board detection.
const LONGRUN_MIN_PIXELS: number = 50;

// findBoxLongRun: aspect ratio bounds for a valid board.
const LONGRUN_MIN_ASPECT: number = 0.5;
const LONGRUN_MAX_ASPECT: number = 2.0;

// Hough transform: edge magnitude threshold. Pixels with gradient below
// this are skipped during voting.
const HOUGH_EDGE_THRESH: number = 30;

// Hough transform: number of theta (angle) bins in the accumulator.
const HOUGH_THETA_STEPS: number = 180;

// Hough transform: maximum pixels to sample for voting (performance control).
const HOUGH_MAX_SAMPLES: number = 50000;

// Hough transform: minimum votes for a line to be considered.
const HOUGH_MIN_VOTES_DIVISOR: number = 50;

// Hough transform: non-maximum suppression rho radius.
const HOUGH_NMS_RHO_DIVISOR: number = 40;

// Hough transform: non-maximum suppression theta radius (bins).
const HOUGH_NMS_THETA_RADIUS: number = 3;

// Hough transform: maximum number of lines returned after NMS.
const HOUGH_MAX_LINES: number = 60;

// Hough line angle tolerance (radians) for clustering lines as horizontal/vertical.
const HOUGH_ANGLE_TOLERANCE: number = Math.PI / 18;

// Board corner detection: minimum number of Hough lines required.
const CORNER_MIN_LINES: number = 8;

// Board corner detection: maximum number of candidate lines per side used
// for intersection computation.
const CORNER_MAX_SIDE_LINES: number = 5;

// Board corner detection: minimum board size as fraction of image dimension.
const CORNER_MIN_SIZE_FRAC: number = 0.08;

// Board corner detection: diagonal ratio bounds (prevents degenerate quadrilaterals).
const CORNER_MIN_DIAG_RATIO: number = 0.5;
const CORNER_MAX_DIAG_RATIO: number = 2.0;

// Board corner detection: confidence = min(horizCount, vertCount) / CORNER_CONFIDENCE_DIV.
const CORNER_CONFIDENCE_DIV: number = 10;

// Board corner detection: how far outside the image a corner can be (as fraction of dimension).
const CORNER_OUT_OF_BOUNDS_FRAC: number = 0.1;

// validateCellCentering: margin to exclude from centroid computation (as fraction of cell size).
const CENTERING_MARGIN: number = 0.15;

// validateCellCentering: minimum ink pixels needed to judge centering.
const CENTERING_MIN_INK: number = 5;

// validateCellCentering: maximum centroid offset (as fraction of cell size) for valid centering.
const CENTERING_MAX_OFFSET: number = 0.25;

// Hough line detection (findBoardByHoughLines): minimum number of horizontal
// and vertical lines required for board detection.
const HOUGH_BOARD_MIN_HORIZ: number = 4;
const HOUGH_BOARD_MIN_VERT: number = 4;

// findPeriodicPeaks: minimum number of peaks for a valid periodic pattern.
const PERIODIC_MIN_PEAKS: number = 5;

// findPreciseGridLines: smoothing window radius as fraction of profile length.
const GRID_LINE_SMOOTH_DIV: number = 60;

// findPreciseGridLines: minimum max-ink-fraction for profile to be usable.
const GRID_LINE_MIN_MAX_FRAC: number = 0.05;

// findPreciseGridLines: peak threshold as fraction of smoothed max.
const GRID_LINE_PEAK_THRESH_FRAC: number = 0.3;

// findPreciseGridLines: spacing tolerance as fraction of ideal spacing.
const GRID_LINE_SPACING_TOLERANCE: number = 0.3;

// Recognize digit 6/9 disambiguation voting weights.
const DISAMBIG_HOLE_WEIGHT: number = 3;
const DISAMBIG_CENTROID_WEIGHT: number = 2;
const DISAMBIG_TOP_RATIO_WEIGHT: number = 2;
const DISAMBIG_HOG_WEIGHT: number = 1;
const DISAMBIG_SW_WEIGHT: number = 1;
const DISAMBIG_SCORE_WEIGHT: number = 1;

// Recognize digit: template scoring formula penalty multiplier for mismatches.
const TEMPLATE_MISMATCH_PENALTY: number = 0.5;

// Recognize digit: F1 score weight in template scoring formula.
const TEMPLATE_F1_WEIGHT: number = 200;

// findBoardBBox: projection ink-fraction thresholds for primary detection.
const BBOX_PRIMARY_THRESH: number = 0.3;
const BBOX_PRIMARY_MIN_FRAC: number = 0.3;

// findBoardBBox: relaxed thresholds tried when primary fails.
const BBOX_RELAXED_THRESHOLDS: number[] = [0.20, 0.15];
const BBOX_RELAXED_MIN_FRAC: number = 0.15;

// findBoardBBox: sub-region search thresholds.
const BBOX_REGION_THRESHOLDS: number[] = [0.30, 0.20, 0.15];
const BBOX_REGION_MIN_FRAC: number = 0.10;

// findBoardBBox: sub-region definitions (as fractions of image dimensions).
const BBOX_REGIONS: number[][] = [
  [0, 0, 0.6, 0.6],
  [0.4, 0, 1.0, 0.6],
  [0, 0.4, 0.6, 1.0],
  [0.4, 0.4, 1.0, 1.0],
  [0.15, 0.15, 0.85, 0.85],
];

// findBoardBBox: extra regions for portrait images (height > width * 1.3).
const BBOX_PORTRAIT_REGIONS: number[][] = [
  [0, 0, 1.0, 0.5],
  [0, 0.1, 1.0, 0.6],
  [0.1, 0, 0.9, 0.45],
];

// findBoardBBox: extra regions for landscape images (width > height * 1.3).
const BBOX_LANDSCAPE_REGIONS: number[][] = [
  [0, 0, 0.5, 1.0],
  [0.1, 0, 0.6, 1.0],
  [0, 0.1, 0.45, 0.9],
];

// findBoardBBox: aspect ratio for triggering portrait/landscape extra regions.
const PORTRAIT_ASPECT_THRESHOLD: number = 1.3;

// Sauvola threshold: minimum cell dimension for computing adaptive threshold.
const SAUVOLA_MIN_DIM: number = 4;

// Background sampling step divisor for warped image background estimation.
const WARP_BG_SAMPLE_DIV: number = 20000;

// Hole detection: reject if second-largest hole component > this fraction of largest.
const HOLE_SECOND_RATIO: number = 0.6;

// Background brightness threshold: if bgColor < 128, treat image as dark-mode
// (light ink on dark background), otherwise dark ink on light background.
const BG_DARK_THRESHOLD: number = 128;

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
let g_lastConfidence: number = 0;

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
  if (components.length >= 2 && components[1].length > components[0].length * HOLE_SECOND_RATIO) {
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

export function isInkPixel(g: number, bg: number, isDark: boolean): boolean {
  if (isDark) { return g > bg + INK_THRESH; }
  return g < bg - INK_THRESH;
}

export function sauvolaThreshold(
  gray: Float32Array, width: number, height: number,
  cx0: number, cy0: number, cw: number, ch: number,
  isDark: boolean
): Float32Array | null {
  const k: number = SAUVOLA_K;
  const R: number = SAUVOLA_R;
  const halfWin: number = Math.max(2, Math.floor(Math.min(cw, ch) / 4));
  const x0: number = Math.floor(cx0);
  const y0: number = Math.floor(cy0);
  const x1: number = Math.floor(cx0 + cw);
  const y1: number = Math.floor(cy0 + ch);
  const w: number = x1 - x0;
  const h: number = y1 - y0;
  if (w < SAUVOLA_MIN_DIM || h < SAUVOLA_MIN_DIM) { return null; }

  const sumBuf: Float32Array = new Float32Array(w * h);
  const sqBuf: Float32Array = new Float32Array(w * h);
  for (let ly: number = 0; ly < h; ly++) {
    const sy: number = y0 + ly;
    if (sy < 0 || sy >= height) { continue; }
    let rowSum: number = 0;
    let rowSq: number = 0;
    for (let lx: number = 0; lx < w; lx++) {
      const sx: number = x0 + lx;
      if (sx < 0 || sx >= width) { continue; }
      const v: number = gray[sy * width + sx];
      rowSum += v;
      rowSq += v * v;
      sumBuf[ly * w + lx] = rowSum;
      sqBuf[ly * w + lx] = rowSq;
    }
  }

  const out: Float32Array = new Float32Array(w * h);
  for (let ly: number = 0; ly < h; ly++) {
    for (let lx: number = 0; lx < w; lx++) {
      const top: number = Math.max(0, ly - halfWin);
      const bot: number = Math.min(h - 1, ly + halfWin);
      const left: number = Math.max(0, lx - halfWin);
      const right: number = Math.min(w - 1, lx + halfWin);
      const cnt: number = (bot - top + 1) * (right - left + 1);
      let s: number = 0;
      let sq: number = 0;
      for (let ry: number = top; ry <= bot; ry++) {
        const prevLeft: number = left > 0 ? sumBuf[ry * w + left - 1] : 0;
        const prevSqLeft: number = left > 0 ? sqBuf[ry * w + left - 1] : 0;
        s += sumBuf[ry * w + right] - prevLeft;
        sq += sqBuf[ry * w + right] - prevSqLeft;
      }
      const mean: number = s / cnt;
      const variance: number = sq / cnt - mean * mean;
      const std: number = Math.sqrt(Math.max(0, variance));
      const t: number = mean * (1 + k * (std / R - 1));
      const pixelVal: number = gray[(y0 + ly) * width + (x0 + lx)];
      out[ly * w + lx] = isDark ? (pixelVal > t ? 1 : 0) : (pixelVal < t ? 1 : 0);
    }
  }
  return out;
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
  const step: number = Math.max(1, Math.floor(total / BG_SAMPLE_COUNT));
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
  if (bw < MIN_BOARD_DIM || bh < MIN_BOARD_DIM) { return null; }
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
  if (rw < MIN_BOARD_DIM || rh < MIN_BOARD_DIM) { return null; }
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
  if (rw < MIN_BOARD_DIM || rh < MIN_BOARD_DIM) { return null; }
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
  if (bw < MIN_BOARD_DIM || bh < MIN_BOARD_DIM) { return false; }
  const aspect: number = bw / bh;
  if (aspect < MIN_BOARD_ASPECT || aspect > MAX_BOARD_ASPECT) { return false; }
  if (bw < W * MIN_BOARD_SIZE_FRAC || bh < H * MIN_BOARD_SIZE_FRAC) { return false; }
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
  if (peaks.length < PERIODIC_MIN_PEAKS) { return peaks; }
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
    if (count >= PERIODIC_MIN_PEAKS) {
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
    if (selected.length >= PERIODIC_MIN_PEAKS) { return selected; }
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
  if (bestCount >= PERIODIC_MIN_PEAKS) { return peaks.slice(bestStart, bestStart + bestCount); }
  return peaks;
}

function findBBoxAdaptive(gray: Float32Array, W: number, H: number, isDark: boolean): BoardBBox | null {
  const winR: number = Math.max(5, Math.floor(Math.min(W, H) / 25));
  const blurred: Float32Array = boxBlur(gray, W, H, winR);

  for (const C of ADAPTIVE_CONTRASTS) {
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

    for (const thresh of ADAPTIVE_THRESHOLDS) {
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
        if (isValidBoardAspect(bbox, W, H) && maxX - minX >= W * MIN_BOARD_SIZE_FRAC && maxY - minY >= H * MIN_BOARD_SIZE_FRAC) {
          return bbox;
        }
      }
    }

    const colPeaks: number[] = findPeriodicPeaks(colFrac, ADAPTIVE_PEAK_THRESH);
    const rowPeaks: number[] = findPeriodicPeaks(rowFrac, ADAPTIVE_PEAK_THRESH);
    if (colPeaks.length >= PERIODIC_MIN_PEAKS && rowPeaks.length >= PERIODIC_MIN_PEAKS) {
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
  for (const delta of CONSERVATIVE_DELTAS) {
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
    const colPeaks: number[] = findPeriodicPeaks(colFrac, CONSERVATIVE_PEAK_THRESH);
    const rowPeaks: number[] = findPeriodicPeaks(rowFrac, CONSERVATIVE_PEAK_THRESH);

    if (colPeaks.length >= CONSERVATIVE_MIN_PEAKS && rowPeaks.length >= CONSERVATIVE_MIN_PEAKS) {
      const bbox: BoardBBox = {
        left: colPeaks[0], top: rowPeaks[0],
        right: colPeaks[colPeaks.length - 1], bottom: rowPeaks[rowPeaks.length - 1],
        isDark
      };
      const bw: number = bbox.right - bbox.left + 1;
      const bh: number = bbox.bottom - bbox.top + 1;
      if (bw < CONSERVATIVE_MIN_DIM || bh < CONSERVATIVE_MIN_DIM) { continue; }
      const aspect: number = bw / bh;
      if (aspect < CONSERVATIVE_MIN_ASPECT || aspect > CONSERVATIVE_MAX_ASPECT) { continue; }
      const areaRatio: number = (bw * bh) / (W * H);
      if (areaRatio > MAX_BOARD_AREA_RATIO) { continue; }
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
export function findBoxLongRun(
  gray: Float32Array, W: number, H: number, isDark: boolean, bg: number
): BoardBBox | null {
  const abs: number = isDark ? Math.max(150, bg + 60) : Math.min(80, bg - 60);
  const ink: Uint8Array = new Uint8Array(W * H);
  for (let i: number = 0; i < W * H; i++) {
    ink[i] = isDark ? (gray[i] > abs ? 1 : 0) : (gray[i] < abs ? 1 : 0);
  }
  const keep: Uint8Array = new Uint8Array(W * H);
  const MINRUN: number = Math.max(MINRUN_ABS_MIN, Math.floor(Math.min(W, H) * MINRUN_FRAC));
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
  if (n < LONGRUN_MIN_PIXELS) { return null; }
  const bw: number = maxX - minX + 1;
  const bh: number = maxY - minY + 1;
  if (bw < CONSERVATIVE_MIN_DIM || bh < CONSERVATIVE_MIN_DIM) { return null; }
  const aspect: number = bw / bh;
  if (aspect < LONGRUN_MIN_ASPECT || aspect > LONGRUN_MAX_ASPECT) { return null; }
  const areaRatio: number = (bw * bh) / (W * H);
  if (areaRatio < MIN_BOARD_AREA_RATIO || areaRatio > MAX_BOARD_AREA_RATIO - 0.03) { return null; }
  return { left: minX, top: minY, right: maxX, bottom: maxY, isDark };
}

function houghLines(gray: Float32Array, W: number, H: number, isDark: boolean, bg: number): HoughLine[] {
  const edgeThresh: number = HOUGH_EDGE_THRESH;
  const dx: Float32Array = new Float32Array(W * H);
  const dy: Float32Array = new Float32Array(W * H);
  const mag: Float32Array = new Float32Array(W * H);
  for (let y: number = 1; y < H - 1; y++) {
    for (let x: number = 1; x < W - 1; x++) {
      const idx: number = y * W + x;
      const l: number = gray[idx - 1];
      const r: number = gray[idx + 1];
      const t: number = gray[idx - W];
      const b: number = gray[idx + W];
      dx[idx] = r - l;
      dy[idx] = b - t;
      mag[idx] = Math.abs(dx[idx]) + Math.abs(dy[idx]);
    }
  }
  const diagonal: number = Math.floor(Math.sqrt(W * W + H * H));
  const thetaSteps: number = HOUGH_THETA_STEPS;
  const accSize: number = (diagonal * 2 + 1) * thetaSteps;
  const acc: number[] = new Array<number>(accSize).fill(0);
  const cosLut: number[] = new Array<number>(thetaSteps);
  const sinLut: number[] = new Array<number>(thetaSteps);
  for (let t: number = 0; t < thetaSteps; t++) {
    const rad: number = t * Math.PI / thetaSteps;
    cosLut[t] = Math.cos(rad);
    sinLut[t] = Math.sin(rad);
  }
  const step: number = Math.max(1, Math.floor(W * H / HOUGH_MAX_SAMPLES));
  for (let y: number = 2; y < H - 2; y += step) {
    for (let x: number = 2; x < W - 2; x += step) {
      const idx: number = y * W + x;
      if (mag[idx] < edgeThresh) { continue; }
      for (let t: number = 0; t < thetaSteps; t++) {
        const rho: number = Math.round(x * cosLut[t] + y * sinLut[t]) + diagonal;
        if (rho >= 0 && rho <= diagonal * 2) {
          acc[rho * thetaSteps + t]++;
        }
      }
    }
  }
  const threshold: number = Math.max(8, Math.floor(Math.min(W, H) / HOUGH_MIN_VOTES_DIVISOR));
  const lines: HoughLine[] = [];
  const nmsRho: number = Math.max(5, Math.floor(diagonal / HOUGH_NMS_RHO_DIVISOR));
  for (let rho: number = 1; rho < diagonal * 2; rho++) {
    for (let t: number = 0; t < thetaSteps; t++) {
      const val: number = acc[rho * thetaSteps + t];
      if (val < threshold) { continue; }
      let isMax: boolean = true;
      for (let dr: number = -nmsRho; dr <= nmsRho && isMax; dr++) {
        for (let dt: number = -HOUGH_NMS_THETA_RADIUS; dt <= HOUGH_NMS_THETA_RADIUS && isMax; dt++) {
          if (dr === 0 && dt === 0) { continue; }
          const nr: number = rho + dr;
          const nt: number = (t + dt + thetaSteps) % thetaSteps;
          if (nr >= 0 && nr <= diagonal * 2) {
            if (acc[nr * thetaSteps + nt] > val) { isMax = false; }
          }
        }
      }
      if (isMax) {
        lines.push({ rho: rho - diagonal, theta: t * Math.PI / thetaSteps, votes: val });
      }
    }
  }
  lines.sort((a: HoughLine, b: HoughLine) => b.votes - a.votes);
  return lines.slice(0, Math.min(lines.length, HOUGH_MAX_LINES));
}

function lineIntersection(r1: number, t1: number, r2: number, t2: number): [number, number] | null {
  const c1: number = Math.cos(t1);
  const s1: number = Math.sin(t1);
  const c2: number = Math.cos(t2);
  const s2: number = Math.sin(t2);
  const det: number = c1 * s2 - c2 * s1;
  if (Math.abs(det) < 1e-8) { return null; }
  const x: number = (r1 * s2 - r2 * s1) / det;
  const y: number = (r2 * c1 - r1 * c2) / det;
  return [x, y];
}

function clusterLinesByAngle(lines: HoughLine[], targetAngle: number, tolerance: number): HoughLine[] {
  const result: HoughLine[] = [];
  for (const line of lines) {
    let angle: number = line.theta;
    let diff: number = Math.abs(angle - targetAngle);
    if (diff > Math.PI / 2) { diff = Math.PI - diff; }
    if (diff < tolerance) { result.push(line); }
  }
  return result;
}

export function detectBoardCorners(gray: Float32Array, W: number, H: number, isDark: boolean, bg: number): BoardCorners | null {
  const lines: HoughLine[] = houghLines(gray, W, H, isDark, bg);
  if (lines.length < CORNER_MIN_LINES) { return null; }
  const horizLines: HoughLine[] = clusterLinesByAngle(lines, Math.PI / 2, HOUGH_ANGLE_TOLERANCE);
  const vertLines: HoughLine[] = clusterLinesByAngle(lines, 0, HOUGH_ANGLE_TOLERANCE);
  if (horizLines.length < 2 || vertLines.length < 2) { return null; }
  const topLines: HoughLine[] = horizLines.slice(0, Math.min(horizLines.length, CORNER_MAX_SIDE_LINES));
  const bottomLines: HoughLine[] = horizLines.slice(Math.max(0, horizLines.length - CORNER_MAX_SIDE_LINES));
  const leftLines: HoughLine[] = vertLines.slice(0, Math.min(vertLines.length, CORNER_MAX_SIDE_LINES));
  const rightLines: HoughLine[] = vertLines.slice(Math.max(0, vertLines.length - CORNER_MAX_SIDE_LINES));
  const candidates: Array<[number, number]> = [];
  for (const h of topLines) {
    for (const v of leftLines) {
      const pt: [number, number] | null = lineIntersection(h.rho, h.theta, v.rho, v.theta);
      if (pt !== null && pt[0] >= -W * CORNER_OUT_OF_BOUNDS_FRAC && pt[0] < W * (1 + CORNER_OUT_OF_BOUNDS_FRAC) && pt[1] >= -H * CORNER_OUT_OF_BOUNDS_FRAC && pt[1] < H * (1 + CORNER_OUT_OF_BOUNDS_FRAC)) {
        candidates.push(pt);
      }
    }
  }
  if (candidates.length === 0) { return null; }
  let tlX: number = W; let tlY: number = H;
  for (const pt of candidates) {
    const d: number = pt[0] * pt[0] + pt[1] * pt[1];
    const cd: number = tlX * tlX + tlY * tlY;
    if (d < cd) { tlX = pt[0]; tlY = pt[1]; }
  }
  const trCandidates: Array<[number, number]> = [];
  for (const h of topLines) {
    for (const v of rightLines) {
      const pt: [number, number] | null = lineIntersection(h.rho, h.theta, v.rho, v.theta);
      if (pt !== null && pt[0] >= -W * CORNER_OUT_OF_BOUNDS_FRAC && pt[0] < W * (1 + CORNER_OUT_OF_BOUNDS_FRAC) && pt[1] >= -H * CORNER_OUT_OF_BOUNDS_FRAC && pt[1] < H * (1 + CORNER_OUT_OF_BOUNDS_FRAC)) {
        trCandidates.push(pt);
      }
    }
  }
  if (trCandidates.length === 0) { return null; }
  let trX: number = 0; let trY: number = H;
  for (const pt of trCandidates) {
    const d: number = (W - pt[0]) * (W - pt[0]) + pt[1] * pt[1];
    const cd: number = (W - trX) * (W - trX) + trY * trY;
    if (d < cd) { trX = pt[0]; trY = pt[1]; }
  }
  const brCandidates: Array<[number, number]> = [];
  for (const h of bottomLines) {
    for (const v of rightLines) {
      const pt: [number, number] | null = lineIntersection(h.rho, h.theta, v.rho, v.theta);
      if (pt !== null && pt[0] >= -W * CORNER_OUT_OF_BOUNDS_FRAC && pt[0] < W * (1 + CORNER_OUT_OF_BOUNDS_FRAC) && pt[1] >= -H * CORNER_OUT_OF_BOUNDS_FRAC && pt[1] < H * (1 + CORNER_OUT_OF_BOUNDS_FRAC)) {
        brCandidates.push(pt);
      }
    }
  }
  if (brCandidates.length === 0) { return null; }
  let brX: number = 0; let brY: number = 0;
  for (const pt of brCandidates) {
    const d: number = (W - pt[0]) * (W - pt[0]) + (H - pt[1]) * (H - pt[1]);
    const cd: number = (W - brX) * (W - brX) + (H - brY) * (H - brY);
    if (d < cd) { brX = pt[0]; brY = pt[1]; }
  }
  const blCandidates: Array<[number, number]> = [];
  for (const h of bottomLines) {
    for (const v of leftLines) {
      const pt: [number, number] | null = lineIntersection(h.rho, h.theta, v.rho, v.theta);
      if (pt !== null && pt[0] >= -W * CORNER_OUT_OF_BOUNDS_FRAC && pt[0] < W * (1 + CORNER_OUT_OF_BOUNDS_FRAC) && pt[1] >= -H * CORNER_OUT_OF_BOUNDS_FRAC && pt[1] < H * (1 + CORNER_OUT_OF_BOUNDS_FRAC)) {
        blCandidates.push(pt);
      }
    }
  }
  if (blCandidates.length === 0) { return null; }
  let blX: number = W; let blY: number = 0;
  for (const pt of blCandidates) {
    const d: number = pt[0] * pt[0] + (H - pt[1]) * (H - pt[1]);
    const cd: number = blX * blX + (H - blY) * (H - blY);
    if (d < cd) { blX = pt[0]; blY = pt[1]; }
  }
  const boardW: number = (trX - tlX + brX - blX) / 2;
  const boardH: number = (blY - tlY + brY - trY) / 2;
  if (boardW < W * CORNER_MIN_SIZE_FRAC || boardH < H * CORNER_MIN_SIZE_FRAC) { return null; }
  const aspect: number = boardW / boardH;
  if (aspect < MIN_BOARD_ASPECT || aspect > MAX_BOARD_ASPECT) { return null; }
  const area: number = boardW * boardH;
  if (area > W * H * MAX_BOARD_AREA_RATIO || area < W * H * MIN_BOARD_AREA_RATIO) { return null; }
  const diag1Sq: number = (trX - blX) * (trX - blX) + (trY - blY) * (trY - blY);
  const diag2Sq: number = (tlX - brX) * (tlX - brX) + (tlY - brY) * (tlY - brY);
  const diagRatio: number = Math.sqrt(diag1Sq) / (Math.sqrt(diag2Sq) + 0.01);
  if (diagRatio < CORNER_MIN_DIAG_RATIO || diagRatio > CORNER_MAX_DIAG_RATIO) { return null; }
  const confidence: number = Math.min(horizLines.length, vertLines.length) / CORNER_CONFIDENCE_DIV;
  return {
    topLeftX: tlX, topLeftY: tlY,
    topRightX: trX, topRightY: trY,
    bottomRightX: brX, bottomRightY: brY,
    bottomLeftX: blX, bottomLeftY: blY,
    isDark: isDark,
    confidence: confidence
  };
}

export function warpPerspectiveGray(
  gray: Float32Array, W: number, H: number,
  corners: BoardCorners, outSize: number, bgVal: number
): Float32Array {
  const out: Float32Array = new Float32Array(outSize * outSize);
  const srcX: number[] = [corners.topLeftX, corners.topRightX, corners.bottomRightX, corners.bottomLeftX];
  const srcY: number[] = [corners.topLeftY, corners.topRightY, corners.bottomRightY, corners.bottomLeftY];
  const dstX: number[] = [0, outSize - 1, outSize - 1, 0];
  const dstY: number[] = [0, 0, outSize - 1, outSize - 1];
  const A: number[][] = [];
  const bVec: number[] = [];
  for (let i: number = 0; i < 4; i++) {
    A.push([dstX[i], dstY[i], 1, 0, 0, 0, -srcX[i] * dstX[i], -srcX[i] * dstY[i]]);
    bVec.push(srcX[i]);
    A.push([0, 0, 0, dstX[i], dstY[i], 1, -srcY[i] * dstX[i], -srcY[i] * dstY[i]]);
    bVec.push(srcY[i]);
  }
  const n: number = 8;
  for (let col: number = 0; col < n; col++) {
    let maxRow: number = col;
    let maxVal: number = Math.abs(A[col][col]);
    for (let row: number = col + 1; row < n; row++) {
      if (Math.abs(A[row][col]) > maxVal) { maxVal = Math.abs(A[row][col]); maxRow = row; }
    }
    const tmpA: number[] = A[col]; A[col] = A[maxRow]; A[maxRow] = tmpA;
    const tmpB: number = bVec[col]; bVec[col] = bVec[maxRow]; bVec[maxRow] = tmpB;
    const pivot: number = A[col][col];
    if (Math.abs(pivot) < 1e-12) { break; }
    for (let j: number = col; j < n; j++) { A[col][j] /= pivot; }
    bVec[col] /= pivot;
    for (let row: number = 0; row < n; row++) {
      if (row === col) { continue; }
      const factor: number = A[row][col];
      for (let j: number = col; j < n; j++) { A[row][j] -= factor * A[col][j]; }
      bVec[row] -= factor * bVec[col];
    }
  }
  const h: number[] = bVec;
  for (let oy: number = 0; oy < outSize; oy++) {
    for (let ox: number = 0; ox < outSize; ox++) {
      const denom: number = h[6] * ox + h[7] * oy + 1;
      if (Math.abs(denom) < 1e-8) { out[oy * outSize + ox] = 128; continue; }
      const sx: number = (h[0] * ox + h[1] * oy + h[2]) / denom;
      const sy: number = (h[3] * ox + h[4] * oy + h[5]) / denom;
      const ix: number = Math.floor(sx);
      const iy: number = Math.floor(sy);
      const fx: number = sx - ix;
      const fy: number = sy - iy;
      if (ix >= 0 && ix + 1 < W && iy >= 0 && iy + 1 < H) {
        const v00: number = gray[iy * W + ix];
        const v10: number = gray[iy * W + ix + 1];
        const v01: number = gray[(iy + 1) * W + ix];
        const v11: number = gray[(iy + 1) * W + ix + 1];
        out[oy * outSize + ox] = v00 * (1 - fx) * (1 - fy) + v10 * fx * (1 - fy) + v01 * (1 - fx) * fy + v11 * fx * fy;
      } else {
        const cx: number = Math.round(sx);
        const cy: number = Math.round(sy);
        if (cx >= 0 && cx < W && cy >= 0 && cy < H) {
          out[oy * outSize + ox] = gray[cy * W + cx];
        } else {
          out[oy * outSize + ox] = bgVal;
        }
      }
    }
  }
  return out;
}

function findBoardByHoughLines(gray: Float32Array, W: number, H: number, isDark: boolean, bg: number): BoardBBox | null {
  const lines: HoughLine[] = houghLines(gray, W, H, isDark, bg);
  if (lines.length < HOUGH_BOARD_MIN_HORIZ) { return null; }

  const horizLines: HoughLine[] = clusterLinesByAngle(lines, Math.PI / 2, HOUGH_ANGLE_TOLERANCE);
  const vertLines: HoughLine[] = clusterLinesByAngle(lines, 0, HOUGH_ANGLE_TOLERANCE);
  if (horizLines.length < HOUGH_BOARD_MIN_HORIZ || vertLines.length < HOUGH_BOARD_MIN_VERT) { return null; }

  horizLines.sort((a: HoughLine, b: HoughLine) => a.rho - b.rho);
  vertLines.sort((a: HoughLine, b: HoughLine) => a.rho - b.rho);

  const clusterEquidistant = (sorted: HoughLine[], targetCount: number): HoughLine[] | null => {
    if (sorted.length < targetCount) { return null; }
    let bestSet: HoughLine[] = [];
    let bestScore: number = 0;
    const minGap: number = Math.max(3, Math.floor(Math.min(W, H) / 25));
    for (let startIdx: number = 0; startIdx < sorted.length; startIdx++) {
      const selected: HoughLine[] = [sorted[startIdx]];
      let lastRho: number = sorted[startIdx].rho;
      for (let i: number = startIdx + 1; i < sorted.length; i++) {
        const gap: number = sorted[i].rho - lastRho;
        if (selected.length === 1) {
          if (gap < minGap) { continue; }
          selected.push(sorted[i]);
          lastRho = sorted[i].rho;
        } else {
          const avgGap: number = (selected[selected.length - 1].rho - selected[0].rho) / (selected.length - 1);
          if (gap >= avgGap * 0.6 && gap <= avgGap * 1.5) {
            selected.push(sorted[i]);
            lastRho = sorted[i].rho;
          }
        }
        if (selected.length >= targetCount) { break; }
      }
      if (selected.length >= targetCount) {
        const span: number = selected[selected.length - 1].rho - selected[0].rho;
        const avgGap2: number = span / (selected.length - 1);
        let devSum: number = 0;
        for (let j: number = 1; j < selected.length; j++) {
          devSum += Math.abs((selected[j].rho - selected[j - 1].rho) - avgGap2);
        }
        const score: number = selected.length * 100 - devSum / avgGap2;
        if (score > bestScore) {
          bestScore = score;
          bestSet = selected;
        }
      }
    }
    return bestSet.length >= targetCount ? bestSet : null;
  };

  const hSet: HoughLine[] | null = clusterEquidistant(horizLines, 10);
  const vSet: HoughLine[] | null = clusterEquidistant(vertLines, 10);

  let topRho: number = 0;
  let bottomRho: number = 0;
  let leftRho: number = 0;
  let rightRho: number = 0;

  if (hSet !== null && hSet.length >= 10) {
    topRho = hSet[0].rho;
    bottomRho = hSet[hSet.length - 1].rho;
  } else if (horizLines.length >= 2) {
    topRho = horizLines[0].rho;
    bottomRho = horizLines[horizLines.length - 1].rho;
  } else {
    return null;
  }

  if (vSet !== null && vSet.length >= 10) {
    leftRho = vSet[0].rho;
    rightRho = vSet[vSet.length - 1].rho;
  } else if (vertLines.length >= 2) {
    leftRho = vertLines[0].rho;
    rightRho = vertLines[vertLines.length - 1].rho;
  } else {
    return null;
  }

  let minX: number = W;
  let maxX: number = 0;
  let minY: number = H;
  let maxY: number = 0;

  const corners: Array<[number, number]> = [];
  const hBounds: HoughLine[] = [hSet !== null && hSet.length >= 2 ? hSet[0] : horizLines[0],
    hSet !== null && hSet.length >= 2 ? hSet[hSet.length - 1] : horizLines[horizLines.length - 1]];
  const vBounds: HoughLine[] = [vSet !== null && vSet.length >= 2 ? vSet[0] : vertLines[0],
    vSet !== null && vSet.length >= 2 ? vSet[vSet.length - 1] : vertLines[vertLines.length - 1]];

  for (const h of hBounds) {
    for (const v of vBounds) {
      const pt: [number, number] | null = lineIntersection(h.rho, h.theta, v.rho, v.theta);
      if (pt !== null && pt[0] >= 0 && pt[0] < W && pt[1] >= 0 && pt[1] < H) {
        corners.push(pt);
        if (pt[0] < minX) { minX = pt[0]; }
        if (pt[0] > maxX) { maxX = pt[0]; }
        if (pt[1] < minY) { minY = pt[1]; }
        if (pt[1] > maxY) { maxY = pt[1]; }
      }
    }
  }

  if (corners.length < 3) { return null; }
  const bw: number = maxX - minX;
  const bh: number = maxY - minY;
  if (bw < 20 || bh < 20) { return null; }
  const aspect: number = bw / bh;
  if (aspect < 0.3 || aspect > 3.0) { return null; }
  const areaRatio: number = (bw * bh) / (W * H);
  if (areaRatio > 0.88 || areaRatio < 0.02) { return null; }

  return { left: Math.floor(minX), top: Math.floor(minY), right: Math.floor(maxX), bottom: Math.floor(maxY), isDark };
}

export function findBoardBBox(pixels: Uint8Array, width: number, height: number, bg: number): BoardBBox {
  const isDark: boolean = bg < BG_DARK_THRESHOLD;
  const gray: Float32Array = toGrayArray(pixels, width, height);
  const imgArea: number = width * height;

  const longRun: BoardBBox | null = findBoxLongRun(gray, width, height, isDark, bg);
  if (longRun !== null) { return longRun; }

  const isDegenerate = (b: BoardBBox): boolean => {
    return ((b.right - b.left) * (b.bottom - b.top)) > imgArea * MAX_BOARD_AREA_RATIO;
  };

  const primary: BoardBBox | null = findBBoxInRectGray(
    gray, width, height, bg, isDark, 0, 0, width, height, BBOX_PRIMARY_THRESH, BBOX_PRIMARY_MIN_FRAC
  );
  if (primary !== null && isValidBoardAspect(primary, width, height) && !isDegenerate(primary)) { return primary; }

  for (const thresh of BBOX_RELAXED_THRESHOLDS) {
    const res: BoardBBox | null = findBBoxInRectGray(
      gray, width, height, bg, isDark, 0, 0, width, height, thresh, BBOX_RELAXED_MIN_FRAC
    );
    if (res !== null && isValidBoardAspect(res, width, height) && !isDegenerate(res)) { return res; }
  }

  const regions: number[][] = [];
  for (let i: number = 0; i < BBOX_REGIONS.length; i++) {
    const br: number[] = BBOX_REGIONS[i];
    regions.push([
      Math.floor(width * br[0]), Math.floor(height * br[1]),
      Math.floor(width * br[2]), Math.floor(height * br[3])
    ]);
  }
  if (height > width * PORTRAIT_ASPECT_THRESHOLD) {
    for (let i: number = 0; i < BBOX_PORTRAIT_REGIONS.length; i++) {
      const br: number[] = BBOX_PORTRAIT_REGIONS[i];
      regions.push([
        Math.floor(width * br[0]), Math.floor(height * br[1]),
        Math.floor(width * br[2]), Math.floor(height * br[3])
      ]);
    }
  }
  if (width > height * PORTRAIT_ASPECT_THRESHOLD) {
    for (let i: number = 0; i < BBOX_LANDSCAPE_REGIONS.length; i++) {
      const br: number[] = BBOX_LANDSCAPE_REGIONS[i];
      regions.push([
        Math.floor(width * br[0]), Math.floor(height * br[1]),
        Math.floor(width * br[2]), Math.floor(height * br[3])
      ]);
    }
  }
  let bestArea: number = 0;
  let bestBox: BoardBBox | null = null;
  for (let ri: number = 0; ri < regions.length; ri++) {
    const r: number[] = regions[ri];
    for (const thresh of BBOX_REGION_THRESHOLDS) {
      const res: BoardBBox | null = findBBoxInRectGray(
        gray, width, height, bg, isDark,
        r[0], r[1], r[2], r[3], thresh, BBOX_REGION_MIN_FRAC
      );
      if (res !== null && isValidBoardAspect(res, width, height)) {
        const area: number = (res.right - res.left) * (res.bottom - res.top);
        if (area < width * height * MAX_BOARD_AREA_RATIO) {
          if (area > bestArea) { bestArea = area; bestBox = res; }
        }
        break;
      }
    }
  }

  const conservative: BoardBBox | null = findBBoxConservative(gray, width, height, isDark, bg);
  if (conservative !== null) { return conservative; }

  if (bestBox !== null) { return bestBox; }

  const adaptive: BoardBBox | null = findBBoxAdaptive(gray, width, height, isDark);
  if (adaptive !== null) {
    const aArea: number = (adaptive.right - adaptive.left) * (adaptive.bottom - adaptive.top);
    if (aArea < width * height * MAX_BOARD_AREA_RATIO) { return adaptive; }
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
  const mx: number = cellW * CELL_MARGIN_RATIO;
  const my: number = cellH * CELL_MARGIN_RATIO;
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

  if (ink < area * MIN_CELL_INK_RATIO || bmaxX < 0) {
    return null;
  }

  const bw: number = bmaxX - bminX + 1;
  const bh: number = bmaxY - bminY + 1;

  const sauvBinary: Float32Array | null = sauvolaThreshold(gray, width, H, bminX, bminY, bw, bh, isDark);
  if (sauvBinary !== null) {
    const sauvSig: number[] = new Array<number>(SIG_LEN).fill(0);
    for (let r: number = 0; r < SIG_ROWS; r++) {
      for (let c: number = 0; c < SIG_COLS; c++) {
        const sx0: number = Math.floor(bw * c / SIG_COLS);
        const sx1: number = Math.floor(bw * (c + 1) / SIG_COLS);
        const sy0: number = Math.floor(bh * r / SIG_ROWS);
        const sy1: number = Math.floor(bh * (r + 1) / SIG_ROWS);
        let s: number = 0;
        let n: number = 0;
        for (let ly: number = sy0; ly < sy1; ly++) {
          for (let lx: number = sx0; lx < sx1; lx++) {
            s += sauvBinary[ly * bw + lx];
            n++;
          }
        }
        sauvSig[r * SIG_COLS + c] = (n > 0 && s / n > 0.5) ? 1 : 0;
      }
    }
    const sauvInk: number = countInk(sauvSig);
    if (sauvInk >= MIN_INK_COUNT && sauvInk <= MAX_INK_COUNT) {
      return sauvSig;
    }
  }

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
  if (inkCount < MIN_INK_COUNT || inkCount > MAX_INK_COUNT) {
    const fallbackSig: number[] | null = cellSigOtsuFallbackGray(
      gray, width, bminX, bminY, bw, bh, isDark, bg
    );
    if (fallbackSig !== null) {
      const fbInk: number = countInk(fallbackSig);
      if (fbInk >= MIN_INK_COUNT && fbInk <= MAX_INK_COUNT) {
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
  if (bboxTotal < OTSU_MIN_PIXELS) { return null; }

  const otsuT: number = otsuThreshold(bboxHist, bboxTotal);
  if (Math.abs(otsuT - bg) < OTSU_BG_MIN_DIFF) { return null; }

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
  if (inkCount < MIN_INK_COUNT || inkCount > MAX_INK_COUNT) { return null; }
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
  const mx: number = cellW * CELL_MARGIN_RATIO;
  const my: number = cellH * CELL_MARGIN_RATIO;
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

  if (ink < area * MIN_CELL_INK_RATIO || bmaxX < 0) {
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
  if (inkCount < MIN_INK_COUNT || inkCount > MAX_INK_COUNT) {
    const fallbackSig: number[] | null = cellSigOtsuFallback(
      pixels, width, bminX, bminY, bw, bh, isDark, bg
    );
    if (fallbackSig !== null) {
      const fbInk: number = countInk(fallbackSig);
      if (fbInk >= MIN_INK_COUNT && fbInk <= MAX_INK_COUNT) {
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
  if (bboxTotal < OTSU_MIN_PIXELS) { return null; }

  const otsuT: number = otsuThreshold(bboxHist, bboxTotal);
  if (Math.abs(otsuT - bg) < OTSU_BG_MIN_DIFF) { return null; }

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
  if (inkCount < MIN_INK_COUNT || inkCount > MAX_INK_COUNT) { return null; }
  return sig;
}

export function hogVerticalGradient(sig: number[]): number {
  let topDown: number = 0;
  let bottomUp: number = 0;
  const quarterRow: number = Math.floor(SIG_ROWS / 4);
  const midRow: number = Math.floor(SIG_ROWS / 2);
  const threeQRow: number = Math.floor(SIG_ROWS * 3 / 4);
  for (let r: number = quarterRow; r < midRow; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) {
        if (c > 0 && sig[r * SIG_COLS + c - 1] === 0) { bottomUp++; }
        if (c < SIG_COLS - 1 && sig[r * SIG_COLS + c + 1] === 0) { bottomUp++; }
      }
    }
  }
  for (let r: number = midRow; r < threeQRow; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) {
        if (c > 0 && sig[r * SIG_COLS + c - 1] === 0) { topDown++; }
        if (c < SIG_COLS - 1 && sig[r * SIG_COLS + c + 1] === 0) { topDown++; }
      }
    }
  }
  const total: number = topDown + bottomUp;
  if (total === 0) { return 0.5; }
  return topDown / total;
}

export function strokeWidthRatio(sig: number[]): number {
  const halfRow: number = Math.floor(SIG_ROWS / 2);
  let topWidth: number = 0;
  let bottomWidth: number = 0;
  for (let r: number = 0; r < halfRow; r++) {
    let runLen: number = 0;
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) { runLen++; }
      else {
        if (runLen > topWidth) { topWidth = runLen; }
        runLen = 0;
      }
    }
    if (runLen > topWidth) { topWidth = runLen; }
  }
  for (let r: number = halfRow; r < SIG_ROWS; r++) {
    let runLen: number = 0;
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) { runLen++; }
      else {
        if (runLen > bottomWidth) { bottomWidth = runLen; }
        runLen = 0;
      }
    }
    if (runLen > bottomWidth) { bottomWidth = runLen; }
  }
  if (bottomWidth === 0) { return topWidth > 0 ? 999 : 1; }
  return topWidth / bottomWidth;
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
  if (inkCount < MIN_INK_COUNT) { return 0; }
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
    const score: number = match - (SIG_LEN - match) * TEMPLATE_MISMATCH_PENALTY + f1 * TEMPLATE_F1_WEIGHT;
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

  const rawConf: number = bestScore / (SIG_LEN + 200);
  g_lastConfidence = rawConf > 1 ? 1 : (rawConf < 0 ? 0 : rawConf);

  if (bestDigit === 6 || bestDigit === 9) {
    const qHole: number = holeCenterRow(sig);
    const iCentroid: number = inkCentroidRow(sig);
    const ratio: number = topBottomInkRatio(sig);
    const hogGrad: number = hogVerticalGradient(sig);
    const swRatio: number = strokeWidthRatio(sig);
    const score6: number = digitBestScore[6];
    const score9: number = digitBestScore[9];

    console.info(`[SudokuPixel] 6/9消歧: score6=${score6.toFixed(1)} score9=${score9.toFixed(1)} qHole=${qHole.toFixed(2)} centroid=${iCentroid.toFixed(2)} topRatio=${ratio.toFixed(2)} hogGrad=${hogGrad.toFixed(2)} swRatio=${swRatio.toFixed(2)}`);
    console.info(`[SudokuPixel] sig:\n${sigToAscii(sig)}`);

    let vote6: number = 0;
    let vote9: number = 0;

    if (qHole >= 0) {
      if (qHole > SIG_ROWS / 2) { vote6 += DISAMBIG_HOLE_WEIGHT; } else { vote9 += DISAMBIG_HOLE_WEIGHT; }
    }
    if (iCentroid >= 0) {
      if (iCentroid > SIG_ROWS / 2) { vote6 += DISAMBIG_CENTROID_WEIGHT; } else { vote9 += DISAMBIG_CENTROID_WEIGHT; }
    }
    if (ratio > 0.5) { vote9 += DISAMBIG_TOP_RATIO_WEIGHT; } else { vote6 += DISAMBIG_TOP_RATIO_WEIGHT; }
    if (hogGrad > 0.5) { vote9 += DISAMBIG_HOG_WEIGHT; } else { vote6 += DISAMBIG_HOG_WEIGHT; }
    if (swRatio > 1.1) { vote9 += DISAMBIG_SW_WEIGHT; } else if (swRatio < 0.9) { vote6 += DISAMBIG_SW_WEIGHT; }
    if (score6 > score9) { vote6 += DISAMBIG_SCORE_WEIGHT; } else { vote9 += DISAMBIG_SCORE_WEIGHT; }

    console.info(`[SudokuPixel] vote6=${vote6} vote9=${vote9} => ${vote6 >= vote9 ? 6 : 9}`);
    return vote6 >= vote9 ? 6 : 9;
  }

  if (qHole >= 0 && bestScore >= MIN_DIGIT_SCORE && secondDigit > 0) {
    const halfRow: number = SIG_ROWS / 2;
    const halfOf: (h: number) => number = (h: number) => (h < 0 ? 0 : (h <= halfRow ? 1 : 2));
    const bh: number = halfOf(g_holeRows[digitBestIdx[bestDigit]]);
    const sh: number = halfOf(g_holeRows[digitBestIdx[secondDigit]]);
    if (bh !== 0 && sh !== 0 && bh !== sh) {
      const qh: number = halfOf(qHole);
      if (qh !== 0 && qh === sh) { bestDigit = secondDigit; }
    }
  }

  return bestScore >= MIN_DIGIT_SCORE ? bestDigit : 0;
}

export function getLastConfidence(): number {
  return g_lastConfidence;
}

export interface DigitResult {
  digit: number;
  confidence: number;
}

export function recognizeDigitWithConfidence(sig: number[], inkCount: number): DigitResult {
  const digit: number = recognizeDigit(sig, inkCount);
  const result: DigitResult = { digit, confidence: g_lastConfidence };
  return result;
}

export function findPreciseGridLines(
  gray: Float32Array, width: number, height: number, bbox: BoardBBox, bg: number
): GridLines | null {
  const isDark: boolean = bbox.isDark;
  const boardLeft: number = bbox.left;
  const boardTop: number = bbox.top;
  const boardRight: number = bbox.right;
  const boardBottom: number = bbox.bottom;
  const boardW: number = boardRight - boardLeft;
  const boardH: number = boardBottom - boardTop;
  if (boardW < CONSERVATIVE_MIN_DIM || boardH < CONSERVATIVE_MIN_DIM) { return null; }

  const hInkProfile: number[] = new Array<number>(boardH).fill(0);
  for (let dy: number = 0; dy < boardH; dy++) {
    const y: number = boardTop + dy;
    if (y < 0 || y >= height) { continue; }
    let inkCount: number = 0;
    const step: number = Math.max(1, Math.floor(boardW / 100));
    for (let dx: number = 0; dx < boardW; dx += step) {
      const x: number = boardLeft + dx;
      if (x < 0 || x >= width) { continue; }
      const g: number = gray[y * width + x];
      if (grayInkPixel(g, bg, isDark, INK_THRESH)) { inkCount++; }
    }
    hInkProfile[dy] = inkCount / Math.floor(boardW / step);
  }

  // Vertical line detection: scan each column for ink spikes
  const vInkProfile: number[] = new Array<number>(boardW).fill(0);
  for (let dx: number = 0; dx < boardW; dx++) {
    const x: number = boardLeft + dx;
    if (x < 0 || x >= width) { continue; }
    let inkCount: number = 0;
    const step: number = Math.max(1, Math.floor(boardH / 100));
    for (let dy: number = 0; dy < boardH; dy += step) {
      const y: number = boardTop + dy;
      if (y < 0 || y >= height) { continue; }
      const g: number = gray[y * width + x];
      if (grayInkPixel(g, bg, isDark, INK_THRESH)) { inkCount++; }
    }
    vInkProfile[dx] = inkCount / Math.floor(boardH / step);
  }

  // Find 10 peaks (9 cells → 10 grid lines) in each profile
  const findPeaks = (profile: number[], expectedCount: number, totalLen: number): number[] | null => {
    const smoothed: number[] = new Array<number>(profile.length).fill(0);
    const winR: number = Math.max(1, Math.floor(totalLen / GRID_LINE_SMOOTH_DIV));
    for (let i: number = 0; i < profile.length; i++) {
      let s: number = 0;
      let n: number = 0;
      for (let j: number = Math.max(0, i - winR); j <= Math.min(profile.length - 1, i + winR); j++) {
        s += profile[j];
        n++;
      }
      smoothed[i] = s / n;
    }
    let maxVal: number = 0;
    for (let i: number = 0; i < smoothed.length; i++) {
      if (smoothed[i] > maxVal) { maxVal = smoothed[i]; }
    }
    if (maxVal < GRID_LINE_MIN_MAX_FRAC) { return null; }
    const thresh: number = maxVal * GRID_LINE_PEAK_THRESH_FRAC;
    const rawPeaks: number[] = [];
    for (let i: number = 0; i < smoothed.length; i++) {
      if (smoothed[i] > thresh) {
        let end: number = i;
        let bestI: number = i;
        let bestV: number = smoothed[i];
        while (end + 1 < smoothed.length && smoothed[end + 1] > thresh) {
          end++;
          if (smoothed[end] > bestV) { bestV = smoothed[end]; bestI = end; }
        }
        rawPeaks.push(bestI);
        i = end;
      }
    }
    if (rawPeaks.length < 3) { return null; }

    // Try to find evenly-spaced subset matching expected grid lines
    const idealSpacing: number = totalLen / (expectedCount - 1);
    const tolerance: number = idealSpacing * GRID_LINE_SPACING_TOLERANCE;
    let bestSet: number[] = [];
    let bestScore2: number = 0;
    for (let startIdx: number = 0; startIdx < rawPeaks.length; startIdx++) {
      const selected: number[] = [rawPeaks[startIdx]];
      let lastPos: number = rawPeaks[startIdx];
      for (let j: number = startIdx + 1; j < rawPeaks.length; j++) {
        const gap: number = rawPeaks[j] - lastPos;
        if (gap >= idealSpacing - tolerance && gap <= idealSpacing + tolerance) {
          selected.push(rawPeaks[j]);
          lastPos = rawPeaks[j];
        }
      }
      if (selected.length >= expectedCount) {
        const span: number = selected[selected.length - 1] - selected[0];
        const avgGap: number = span / (selected.length - 1);
        let devSum: number = 0;
        for (let k: number = 1; k < selected.length; k++) {
          devSum += Math.abs((selected[k] - selected[k - 1]) - avgGap);
        }
        const score: number = selected.length * 100 - devSum / (avgGap + 1);
        if (score > bestScore2) { bestScore2 = score; bestSet = selected.slice(0, expectedCount); }
      }
    }
    if (bestSet.length >= expectedCount) { return bestSet; }
    if (rawPeaks.length >= expectedCount) {
      return rawPeaks.slice(0, Math.min(rawPeaks.length, expectedCount + 2));
    }
    // Fallback: uniform spacing
    const uniformLines: number[] = [];
    for (let i: number = 0; i < expectedCount; i++) {
      uniformLines.push(Math.round(i * totalLen / (expectedCount - 1)));
    }
    return uniformLines;
  };

  const hLines: number[] | null = findPeaks(hInkProfile, 10, boardH);
  const vLines: number[] | null = findPeaks(vInkProfile, 10, boardW);
  if (hLines === null || vLines === null) { return null; }
  if (hLines.length < 2 || vLines.length < 2) { return null; }

  // Convert from board-local to image-global coordinates
  const globalHLines: number[] = hLines.map((l: number) => boardTop + l);
  const globalVLines: number[] = vLines.map((l: number) => boardLeft + l);
  const result: GridLines = { hLines: globalHLines, vLines: globalVLines };
  return result;
}

export function validateCellCentering(
  gray: Float32Array, width: number, height: number,
  cellLeft: number, cellTop: number, cellW: number, cellH: number,
  isDark: boolean, bg: number
): boolean {
  // Check if ink mass is reasonably centered within the cell.
  // Off-center ink usually means the grid line was mispositioned and we're
  // capturing part of an adjacent cell's digit.
  const margin: number = CENTERING_MARGIN;
  const x0: number = Math.floor(cellLeft + cellW * margin);
  const y0: number = Math.floor(cellTop + cellH * margin);
  const x1: number = Math.floor(cellLeft + cellW * (1 - margin));
  const y1: number = Math.floor(cellTop + cellH * (1 - margin));

  let inkSumX: number = 0;
  let inkSumY: number = 0;
  let inkTotal: number = 0;

  for (let y: number = y0; y < y1; y++) {
    for (let x: number = x0; x < x1; x++) {
      if (y < 0 || y >= height || x < 0 || x >= width) { continue; }
      const g: number = gray[y * width + x];
      if (grayInkPixel(g, bg, isDark, INK_THRESH)) {
        inkSumX += x;
        inkSumY += y;
        inkTotal++;
      }
    }
  }

  if (inkTotal < CENTERING_MIN_INK) { return true; }

  const centroidX: number = inkSumX / inkTotal;
  const centroidY: number = inkSumY / inkTotal;
  const centerX: number = (x0 + x1) / 2;
  const centerY: number = (y0 + y1) / 2;
  const offX: number = Math.abs(centroidX - centerX) / cellW;
  const offY: number = Math.abs(centroidY - centerY) / cellH;

  // If centroid is too far off-center, the cell positioning is likely wrong
  return offX < CENTERING_MAX_OFFSET && offY < CENTERING_MAX_OFFSET;
}
