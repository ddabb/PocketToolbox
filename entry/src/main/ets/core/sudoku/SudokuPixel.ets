import { Context } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RawFileUtil } from '../../common/utils/RawFileUtil';
import { yieldThread } from './SudokuOCRUtils';

const DOMAIN: number = 0xA03D00;
const TAG: string = 'SudokuPixel';

export interface DigitTemplate {
  digit: number;
  key: number[];
  keyBytes: Int8Array;
  inkCount: number;
  centroidRow: number;
  centroidCol: number;
  topBottomRatio: number;
  leftRightRatio: number;
  hasHole: boolean;
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
// Ink count boundary between "very thin" and "normal low ink" in the lowInk
// path of recognizeDigit. When inkCount is in [THIN1_MIN_INK_COUNT, this value),
// the detectThinOne fallback requires a stricter template-score gate
// (lowInkMinScore = 0.70×SIG_LEN) to avoid false positives on noise.
const MIN_INK_COUNT_DIGIT1: number = Math.floor(SIG_LEN * 0.12);

// Absolute minimum ink count for recognizeDigit entry gate. Below this, the
// signature is treated as empty/noise and returns 0 immediately. Above this
// but below MIN_INK_COUNT_DIGIT1, only thin-"1" detection is attempted with a
// strict triple-gate (high template score + template recall + detectThinOne geometry).
// Also serves as the internal lower bound inside detectThinOne() itself.
const THIN1_MIN_INK_COUNT: number = Math.floor(SIG_LEN * 0.06);

// Minimum template-match score (out of SIG_LEN) for a digit to be accepted.
// SIG_LEN * 0.65 ≈ 364 of 560 pixels must match template.
const MIN_DIGIT_SCORE: number = Math.floor(SIG_LEN * 0.65);

// When inkCount is in the "low ink" range [MIN_INK_COUNT_DIGIT1, MIN_INK_COUNT),
// the primary path only matches digit "1". If that fails, we fall back to matching
// digits 2-9 with this score gate. Lower than MIN_DIGIT_SCORE (0.65) because
// low-ink signatures have fewer ink pixels to match, but must still be strict
// enough to reject noise and grid-line fragments. 0.60 ≈ 336 of 560 pixels.
const LOW_INK_FALLBACK_MIN_SCORE: number = Math.floor(SIG_LEN * 0.60);

// Minimum recall (fraction of template ink pixels present in the signature)
// for low-ink fallback matches. Prevents partial matches where a few ink pixels
// happen to overlap a template by chance.
const LOW_INK_FALLBACK_MIN_RECALL: number = 0.35;

// Ink detection threshold: a pixel is "ink" if its gray value differs from
// the background by at least INK_THRESH. Lower = more sensitive to faint ink;
// higher = more selective, avoids noise.
export const INK_THRESH: number = 50;
const GRID_LINE_GRAY_DIFF: number = INK_THRESH * 0.6;

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
// Originally 0.025; lowered to 0.018 (log117) to catch very thin "1" digits
// whose ink ratio was ~0.022. This fixed digit-1 missing errors in tests
// 18,22,24,25 (log116→117: 22 FAIL→PASS, 24 FAIL→PASS, 25: 7→2 errors).
// 0.018 is still above noise floor (~0.005) so no false-positive regression.
export const MIN_CELL_INK_RATIO: number = 0.018;

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

// findBoxLongRun: when the default threshold (bg ± 60) produces too many ink pixels
// (areaRatio > MAX_BOARD_AREA_RATIO), retry with progressively tighter offsets.
// Each offset is subtracted from bg (light-mode) or added to bg (dark-mode) to
// produce the binary ink threshold. Grid lines are significantly darker/lighter
// than background textures, so a tighter offset filters out faint wood grain,
// shadows, and other background noise while preserving the actual grid strokes.
const LONGRUN_TIGHTER_OFFSETS: number[] = [40, 25, 12];

// findBoxLongRun: minimum number of kept pixels for a valid board detection.
const LONGRUN_MIN_PIXELS: number = 50;

// findBoxLongRun: reject thresholds that generate too many long runs. In photos,
// wood grain and shadows can create thousands of long horizontal/vertical runs;
// a real Sudoku grid has only tens of long runs even after resizing.
const LONGRUN_MAX_RUN_COUNT_FRAC: number = 0.50;

// findBoxLongRun: aspect ratio bounds for a valid board. Portrait photos can
// compress the board vertically, but aspect≈0.51 in logs29 selected only the
// left half of photos.jpg and shifted all cells, while the good photo bbox was
// still about 0.69. Keep a stricter floor for long-run candidates.
const LONGRUN_MIN_ASPECT: number = 0.6;
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

// detectGridLineWidths: minimum ink percentage in a row/column scan to confirm a thick grid line.
const GRID_LINE_INK_EXIST_THRESH: number = 0.15;

// findPreciseGridLines: peak threshold as fraction of smoothed max.
const GRID_LINE_PEAK_THRESH_FRAC: number = 0.3;

// findPreciseGridLines: spacing tolerance as fraction of ideal spacing.
const GRID_LINE_SPACING_TOLERANCE: number = 0.3;

// Recognize digit 6/9 disambiguation voting weights.
const DISAMBIG_HOLE_WEIGHT: number = 2;
const DISAMBIG_CENTROID_WEIGHT: number = 1;
const DISAMBIG_TOP_RATIO_WEIGHT: number = 2;
const DISAMBIG_HOG_WEIGHT: number = 1;
const DISAMBIG_SW_WEIGHT: number = 1;
const DISAMBIG_SCORE_WEIGHT: number = 4;

const DISAMBIG_SCORE_GAP_SKIP: number = 80;

// Recognize digit: template scoring formula penalty multiplier for mismatches.
const TEMPLATE_MISMATCH_PENALTY: number = 0.5;

// Recognize digit: F1 score weight in template scoring formula.
const TEMPLATE_F1_WEIGHT: number = 500;

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

// Cache for per-channel background colors, computed by bgColor() and consumed by toGrayArray().
interface ChannelBg {
  bgR: number;
  bgG: number;
  bgB: number;
}
let g_cachedChannelBg: ChannelBg | null = null;

export function resetChannelBgCache(): void {
  g_cachedChannelBg = null;
}

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
let g_templatesByDigit: DigitTemplate[][] = [];
let g_holeRows: number[] = [];
let g_loaded: boolean = false;
let g_gridLineCropTop: number[] = new Array<number>(81).fill(0);
let g_gridLineCropBot: number[] = new Array<number>(81).fill(0);
let g_gridLineCropLeft: number[] = new Array<number>(81).fill(0);
let g_gridLineCropRight: number[] = new Array<number>(81).fill(0);
let g_gridLineDetected: boolean = false;
let g_lastConfidence: number = 0;
let g_lastBboxDiag: string = '';
let g_lastPixelDiag: string = '';
let g_lastRawInkRatio: number = 0;

export function getLastBboxDiag(): string {
  return g_lastBboxDiag;
}

export function getLastPixelDiag(): string {
  return g_lastPixelDiag;
}

export function getLastRawInkRatio(): number {
  return g_lastRawInkRatio;
}

export function resetLastPixelDiag(): void {
  g_lastPixelDiag = '';
  g_lastRawInkRatio = 0;
}

export function resetGridLineCrop(): void {
  g_gridLineCropTop = new Array<number>(81).fill(0);
  g_gridLineCropBot = new Array<number>(81).fill(0);
  g_gridLineCropLeft = new Array<number>(81).fill(0);
  g_gridLineCropRight = new Array<number>(81).fill(0);
  g_gridLineDetected = false;
}

export function isGridLineCropDetected(): boolean {
  return g_gridLineDetected;
}

export function detectGridLineWidths(
  gray: Float32Array,
  imgW: number,
  boardL: number, boardT: number,
  boardR: number, boardB: number,
  isDark: boolean, bg: number
): void {
  g_gridLineCropTop = new Array<number>(81).fill(0);
  g_gridLineCropBot = new Array<number>(81).fill(0);
  g_gridLineCropLeft = new Array<number>(81).fill(0);
  g_gridLineCropRight = new Array<number>(81).fill(0);
  const cellW: number = (boardR - boardL) / 9;
  const cellH: number = (boardB - boardT) / 9;
  const imgH: number = Math.floor(gray.length / imgW);
  const hLineInkDown: number[] = new Array<number>(10).fill(0);
  const hLineInkUp: number[] = new Array<number>(10).fill(0);
  const vLineInkRight: number[] = new Array<number>(10).fill(0);
  const vLineInkLeft: number[] = new Array<number>(10).fill(0);

  const innerX0: number = Math.floor(boardL + cellW * CENTERING_MARGIN);
  const innerX1: number = Math.floor(boardR - cellW * CENTERING_MARGIN);
  const innerY0: number = Math.floor(boardT + cellH * CENTERING_MARGIN);
  const innerY1: number = Math.floor(boardB - cellH * CENTERING_MARGIN);
  const hSpanLen: number = innerX1 - innerX0 + 1;
  const vSpanLen: number = innerY1 - innerY0 + 1;

  const scanBandH: number = Math.max(3, Math.floor(cellH * CENTERING_MARGIN));
  const scanBandW: number = Math.max(3, Math.floor(cellW * CENTERING_MARGIN));

  const inkBg: number = isDark ? bg + INK_THRESH : bg - INK_THRESH;
  const ink: Uint8Array = new Uint8Array(gray.length);
  if (isDark) {
    for (let k: number = 0; k < gray.length; k++) {
      ink[k] = gray[k] > inkBg ? 1 : 0;
    }
  } else {
    for (let k: number = 0; k < gray.length; k++) {
      ink[k] = gray[k] < inkBg ? 1 : 0;
    }
  }

  for (let i: number = 0; i < 10; i++) {
    const lineY: number = Math.round(boardT + i * cellH);
    if (lineY < 0 || lineY >= imgH) { continue; }
    const yStart: number = Math.max(0, lineY - scanBandH);
    const yEnd: number = Math.min(imgH - 1, lineY + scanBandH);
    if (hSpanLen < 5) { continue; }
    let maxInkPct: number = 0;
    let bestY: number = lineY;
    for (let y: number = yStart; y <= yEnd; y++) {
      const rowOff: number = y * imgW;
      let inkCount: number = 0;
      for (let x: number = innerX0; x <= innerX1; x++) {
        inkCount += ink[rowOff + x];
      }
      const pct: number = inkCount / hSpanLen;
      if (pct > maxInkPct) { maxInkPct = pct; bestY = y; }
    }
    if (maxInkPct < GRID_LINE_INK_EXIST_THRESH) { continue; }
    const threshPct: number = maxInkPct * 0.5;
    let topInkY: number = bestY;
    let botInkY: number = bestY;
    for (let y: number = bestY - 1; y >= yStart; y--) {
      const rowOff: number = y * imgW;
      let inkCount: number = 0;
      for (let x: number = innerX0; x <= innerX1; x++) {
        inkCount += ink[rowOff + x];
      }
      if (inkCount / hSpanLen < threshPct) { break; }
      topInkY = y;
    }
    for (let y: number = bestY + 1; y <= yEnd; y++) {
      const rowOff: number = y * imgW;
      let inkCount: number = 0;
      for (let x: number = innerX0; x <= innerX1; x++) {
        inkCount += ink[rowOff + x];
      }
      if (inkCount / hSpanLen < threshPct) { break; }
      botInkY = y;
    }
    hLineInkUp[i] = Math.max(0, lineY - topInkY);
    hLineInkDown[i] = Math.max(0, botInkY - lineY);
  }

  for (let j: number = 0; j < 10; j++) {
    const lineX: number = Math.round(boardL + j * cellW);
    if (lineX < 0 || lineX >= imgW) { continue; }
    const xStart: number = Math.max(0, lineX - scanBandW);
    const xEnd: number = Math.min(imgW - 1, lineX + scanBandW);
    if (vSpanLen < 5) { continue; }
    let maxInkPct: number = 0;
    let bestX: number = lineX;
    for (let x: number = xStart; x <= xEnd; x++) {
      let inkCount: number = 0;
      for (let y: number = innerY0; y <= innerY1; y++) {
        inkCount += ink[y * imgW + x];
      }
      const pct: number = inkCount / vSpanLen;
      if (pct > maxInkPct) { maxInkPct = pct; bestX = x; }
    }
    if (maxInkPct < GRID_LINE_INK_EXIST_THRESH) { continue; }
    const threshPct: number = maxInkPct * 0.5;
    let leftInkX: number = bestX;
    let rightInkX: number = bestX;
    for (let x: number = bestX - 1; x >= xStart; x--) {
      let inkCount: number = 0;
      for (let y: number = innerY0; y <= innerY1; y++) {
        inkCount += ink[y * imgW + x];
      }
      if (inkCount / vSpanLen < threshPct) { break; }
      leftInkX = x;
    }
    for (let x: number = bestX + 1; x <= xEnd; x++) {
      let inkCount: number = 0;
      for (let y: number = innerY0; y <= innerY1; y++) {
        inkCount += ink[y * imgW + x];
      }
      if (inkCount / vSpanLen < threshPct) { break; }
      rightInkX = x;
    }
    vLineInkLeft[j] = Math.max(0, lineX - leftInkX);
    vLineInkRight[j] = Math.max(0, rightInkX - lineX);
  }

  const minMargin: number = Math.max(1, Math.floor(Math.min(cellW, cellH) * GRID_LINE_MIN_MAX_FRAC));
  for (let row: number = 0; row < 9; row++) {
    for (let col: number = 0; col < 9; col++) {
      const idx: number = row * 9 + col;
      const rawTop: number = hLineInkDown[row] + 1;
      const rawBot: number = hLineInkUp[row + 1] + 1;
      const rawLeft: number = vLineInkRight[col] + 1;
      const rawRight: number = vLineInkLeft[col + 1] + 1;
      const maxM: number = Math.floor(Math.min(cellW, cellH) * 0.45);
      g_gridLineCropTop[idx] = Math.max(minMargin, Math.min(rawTop, maxM));
      g_gridLineCropBot[idx] = Math.max(minMargin, Math.min(rawBot, maxM));
      g_gridLineCropLeft[idx] = Math.max(minMargin, Math.min(rawLeft, maxM));
      g_gridLineCropRight[idx] = Math.max(minMargin, Math.min(rawRight, maxM));
    }
  }

  g_gridLineDetected = true;
  const diagH: string = hLineInkDown.map((d: number, i: number) => `${hLineInkUp[i]}+${d}`).join(',');
  const diagV: string = vLineInkRight.map((r: number, j: number) => `${vLineInkLeft[j]}+${r}`).join(',');
  g_lastPixelDiag = `gridLineCrop: hUp=[${hLineInkUp.join(',')}] hDown=[${hLineInkDown.join(',')}] vLeft=[${vLineInkLeft.join(',')}] vRight=[${vLineInkRight.join(',')}]`;
}

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
  return cnt > 0 ? sumR / cnt / (SIG_ROWS - 1) : 0.5;
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
  return bottomInk > 0 ? topInk / bottomInk : 999;
}

export function leftRightInkRatio(sig: number[]): number {
  const halfCol: number = Math.floor(SIG_COLS / 2);
  let leftInk: number = 0;
  let rightInk: number = 0;
  for (let r: number = 0; r < SIG_ROWS; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) {
        if (c < halfCol) { leftInk++; } else { rightInk++; }
      }
    }
  }
  return rightInk > 0 ? leftInk / rightInk : 0;
}

export function inkCentroidCol(sig: number[]): number {
  let sumC: number = 0;
  let cnt: number = 0;
  for (let r: number = 0; r < SIG_ROWS; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) { sumC += c; cnt++; }
    }
  }
  return cnt > 0 ? sumC / cnt : -1;
}

function templateMatchesFilter(
  tpl: DigitTemplate, sigInkCount: number,
  sigCentroidRow: number, sigCentroidCol: number,
  sigTopBottom: number, sigLeftRight: number,
  sigHasHole: boolean
): boolean {
  const inkRatio: number = sigInkCount / tpl.inkCount;
  if (inkRatio < 0.45 || inkRatio > 2.2) { return false; }
  if (Math.abs(sigCentroidRow - tpl.centroidRow) > 10) { return false; }
  if (Math.abs(sigCentroidCol - tpl.centroidCol) > 8) { return false; }
  const tbDiff: number = Math.abs(sigTopBottom - tpl.topBottomRatio);
  if (tbDiff > 3.5) { return false; }
  const lrDiff: number = Math.abs(sigLeftRight - tpl.leftRightRatio);
  if (lrDiff > 3.5) { return false; }
  if (sigHasHole && !tpl.hasHole) {
    const noHoleDigits: Set<number> = new Set<number>([1, 2, 3, 5, 7]);
    if (noHoleDigits.has(tpl.digit)) { return false; }
  }
  return true;
}

function templateMatchesInkFilter(tpl: DigitTemplate, sigInkCount: number): boolean {
  const inkRatio: number = sigInkCount / tpl.inkCount;
  if (inkRatio < 0.45 || inkRatio > 2.2) { return false; }
  return true;
}

function sigComputeLeftRightRatio(sig: number[]): number {
  const halfCol2: number = Math.floor(SIG_COLS / 2);
  let lInk: number = 0;
  let rInk: number = 0;
  for (let i: number = 0; i < SIG_LEN; i++) {
    if (sig[i] === 1) {
      if (i % SIG_COLS < halfCol2) { lInk++; } else { rInk++; }
    }
  }
  return rInk > 0 ? lInk / rInk : 0;
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
    let file: DigitTemplateFile = RawFileUtil.readJson<DigitTemplateFile>(context, 'digit_templates_extended.json');
    if (!file || !file.templates || file.templates.length === 0) {
      file = RawFileUtil.readJson<DigitTemplateFile>(context, 'digit_templates.json');
    }
    if (!file || !file.templates || file.templates.length === 0) {
      return false;
    }
    g_templates = [];
    g_templatesByDigit = new Array<DigitTemplate[]>(10);
    for (let d: number = 0; d < 10; d++) {
      g_templatesByDigit[d] = [];
    }
    for (let i: number = 0; i < file.templates.length; i++) {
      const e: DigitTemplateEntry = file.templates[i];
      const kb: Int8Array = new Int8Array(e.key.length);
      let inkC: number = 0;
      for (let j: number = 0; j < e.key.length; j++) {
        kb[j] = e.key[j];
        if (e.key[j] === 1) { inkC++; }
      }
      const tpl: DigitTemplate = {
        digit: e.digit, key: e.key, keyBytes: kb, inkCount: inkC,
        centroidRow: 0, centroidCol: 0, topBottomRatio: 0, leftRightRatio: 0, hasHole: false
      };
      let sumR: number = 0;
      let sumC: number = 0;
      for (let j2: number = 0; j2 < e.key.length; j2++) {
        if (e.key[j2] === 1) {
          sumR += Math.floor(j2 / SIG_COLS);
          sumC += j2 % SIG_COLS;
        }
      }
      tpl.centroidRow = inkC > 0 ? sumR / inkC : -1;
      tpl.centroidCol = inkC > 0 ? sumC / inkC : -1;
      const halfRowT: number = Math.floor(SIG_ROWS / 2);
      const halfColT: number = Math.floor(SIG_COLS / 2);
      let topInkT: number = 0;
      let botInkT: number = 0;
      let leftInkT: number = 0;
      let rightInkT: number = 0;
      for (let j3: number = 0; j3 < e.key.length; j3++) {
        if (e.key[j3] === 1) {
          const rT: number = Math.floor(j3 / SIG_COLS);
          const cT: number = j3 % SIG_COLS;
          if (rT < halfRowT) { topInkT++; } else { botInkT++; }
          if (cT < halfColT) { leftInkT++; } else { rightInkT++; }
        }
      }
      tpl.topBottomRatio = botInkT > 0 ? topInkT / botInkT : 0;
      tpl.leftRightRatio = rightInkT > 0 ? leftInkT / rightInkT : 0;
      tpl.hasHole = holeCenterRow(e.key) >= 0;
      g_templates.push(tpl);
      if (e.digit >= 0 && e.digit <= 9) {
        g_templatesByDigit[e.digit].push(tpl);
      }
    }
    g_holeRows = g_templates.map((t: DigitTemplate) => holeCenterRow(t.key));
    g_loaded = true;
    hilog.info(DOMAIN, TAG, '已加载 %{public}d 个数字模板 (%{public}dx%{public}d)', g_templates.length, SIG_ROWS, SIG_COLS);
    return true;
  } catch (err) {
    hilog.error(DOMAIN, TAG, '加载模板失败: %{public}s', `${(err as Error).message}`);
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

export async function sauvolaThreshold(
  gray: Float32Array, width: number, height: number,
  cx0: number, cy0: number, cw: number, ch: number,
  isDark: boolean
): Promise<Float32Array | null> {
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

  const intSum: Float32Array = new Float32Array((w + 1) * (h + 1));
  const intSq: Float32Array = new Float32Array((w + 1) * (h + 1));
  const stride: number = w + 1;
  for (let ly: number = 0; ly < h; ly++) {
    const sy: number = y0 + ly;
    let rSum: number = 0;
    let rSq: number = 0;
    for (let lx: number = 0; lx < w; lx++) {
      const sx: number = x0 + lx;
      let v: number = 0;
      if (sy >= 0 && sy < height && sx >= 0 && sx < width) {
        v = gray[sy * width + sx];
      }
      rSum += v;
      rSq += v * v;
      intSum[(ly + 1) * stride + lx + 1] = rSum + intSum[ly * stride + lx + 1];
      intSq[(ly + 1) * stride + lx + 1] = rSq + intSq[ly * stride + lx + 1];
    }
    if (ly % 16 === 15) { await yieldThread(); }
  }

  const out: Float32Array = new Float32Array(w * h);
  for (let ly: number = 0; ly < h; ly++) {
    for (let lx: number = 0; lx < w; lx++) {
      const top: number = Math.max(0, ly - halfWin);
      const bot: number = Math.min(h - 1, ly + halfWin);
      const left: number = Math.max(0, lx - halfWin);
      const right: number = Math.min(w - 1, lx + halfWin);
      const cnt: number = (bot - top + 1) * (right - left + 1);
      const tR: number = top;
      const tC: number = left;
      const bR: number = bot + 1;
      const bC: number = right + 1;
      const s: number = intSum[bR * stride + bC] - intSum[tR * stride + bC]
        - intSum[bR * stride + tC] + intSum[tR * stride + tC];
      const sq: number = intSq[bR * stride + bC] - intSq[tR * stride + bC]
        - intSq[bR * stride + tC] + intSq[tR * stride + tC];
      const mean: number = s / cnt;
      const variance: number = sq / cnt - mean * mean;
      const std: number = Math.sqrt(Math.max(0, variance));
      const t: number = mean * (1 + k * (std / R - 1));
      const pixelVal: number = gray[(y0 + ly) * width + (x0 + lx)];
      out[ly * w + lx] = isDark ? (pixelVal > t ? 1 : 0) : (pixelVal < t ? 1 : 0);
    }
    if (ly % 16 === 15) { await yieldThread(); }
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

function clamp255(v: number): number { if (v < 0) { return 0; } if (v > 255) { return 255; } return v; }

// 使用缓存的通道背景色计算单像素的颜色对比度灰度值
function computeContrastPixel(pixels: Uint8Array, off: number): number {
  let bgR: number = 128; let bgG: number = 128; let bgB: number = 128;
  if (g_cachedChannelBg !== null) {
    bgR = g_cachedChannelBg.bgR;
    bgG = g_cachedChannelBg.bgG;
    bgB = g_cachedChannelBg.bgB;
  }
  const dr: number = pixels[off] - bgR;
  const dg: number = pixels[off + 1] - bgG;
  const db: number = pixels[off + 2] - bgB;
  const contrast: number = Math.max(Math.abs(dr), Math.abs(dg), Math.abs(db));
  return clamp255(255 - contrast);
}

export function bgColor(pixels: Uint8Array, width: number, height: number): number {
  // 使用分通道颜色对比度：对每个通道分别统计直方图，取众数作为该通道的背景色。
  // 相比单一亮度值（0.299R+0.587G+0.114B），分通道背景色能正确处理彩色主题
  // （如红色数字浅色背景、蓝色数字深色背景等），避免亮度公式丢失颜色对比度信息。
  const histR: number[] = new Array<number>(256).fill(0);
  const histG: number[] = new Array<number>(256).fill(0);
  const histB: number[] = new Array<number>(256).fill(0);
  const total: number = width * height;
  const step: number = Math.max(1, Math.floor(total / BG_SAMPLE_COUNT));
  for (let i: number = 0; i < total; i += step) {
    const off: number = i * 4;
    let ri: number = pixels[off];
    let gi: number = pixels[off + 1];
    let bi: number = pixels[off + 2];
    if (ri < 0) { ri = 0; } if (ri > 255) { ri = 255; }
    if (gi < 0) { gi = 0; } if (gi > 255) { gi = 255; }
    if (bi < 0) { bi = 0; } if (bi > 255) { bi = 255; }
    histR[ri]++; histG[gi]++; histB[bi]++;
  }
  // 跳过 bin 0 找众数（透明区域/黑边累积在 bin 0）
  let modeR: number = 0; let maxR: number = 0;
  let modeG: number = 0; let maxG: number = 0;
  let modeB: number = 0; let maxB: number = 0;
  for (let i: number = 1; i < 256; i++) {
    if (histR[i] > maxR) { maxR = histR[i]; modeR = i; }
    if (histG[i] > maxG) { maxG = histG[i]; modeG = i; }
    if (histB[i] > maxB) { maxB = histB[i]; modeB = i; }
  }
  // 缓存供 toGrayArray 复用
  g_cachedChannelBg = { bgR: modeR, bgG: modeG, bgB: modeB };
  // 返回反转对比度的 bg：在颜色对比度方案中，所有背景像素映射到接近255的位置
  return 255;
}

export function toGrayArray(pixels: Uint8Array, width: number, height: number): Float32Array {
  let bgR: number = 128; let bgG: number = 128; let bgB: number = 128;
  if (g_cachedChannelBg !== null) {
    bgR = g_cachedChannelBg.bgR;
    bgG = g_cachedChannelBg.bgG;
    bgB = g_cachedChannelBg.bgB;
  }
  const len: number = width * height;
  const gray: Float32Array = new Float32Array(len);
  for (let i: number = 0; i < len; i++) {
    const off: number = i * 4;
    let dr: number = pixels[off] - bgR;
    let dg: number = pixels[off + 1] - bgG;
    let db: number = pixels[off + 2] - bgB;
    if (dr < 0) { dr = -dr; }
    if (dg < 0) { dg = -dg; }
    if (db < 0) { db = -db; }
    let contrast: number = dr;
    if (dg > contrast) { contrast = dg; }
    if (db > contrast) { contrast = db; }
    let v: number = 255 - contrast;
    if (v < 0) { v = 0; } else if (v > 255) { v = 255; }
    gray[i] = v;
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
  const inkBg: number = isDark ? bg + thresh : bg - thresh;
  for (let x: number = 0; x < rw; x++) {
    let c: number = 0;
    for (let y: number = 0; y < rh; y += step) {
      const g: number = gray[(y + ry0) * W + (x + rx0)];
      if (isDark ? g > inkBg : g < inkBg) { c++; }
    }
    colInk[x] = c;
  }
  for (let y: number = 0; y < rh; y++) {
    let c: number = 0;
    for (let x: number = 0; x < rw; x += step) {
      const g: number = gray[(y + ry0) * W + (x + rx0)];
      if (isDark ? g > inkBg : g < inkBg) { c++; }
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
      const off: number = ((y + ry0) * width + (x + rx0)) * 4;
      const g: number = computeContrastPixel(pixels, off);
      if (isInkPixel(g, bg, isDark)) { c++; }
    }
    colInk[x] = c;
  }
  for (let y: number = 0; y < rh; y++) {
    let c: number = 0;
    for (let x: number = 0; x < rw; x += 2) {
      const off: number = ((y + ry0) * width + (x + rx0)) * 4;
      const g: number = computeContrastPixel(pixels, off);
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

const ADAPTIVE_MAX_DIM: number = 400;

function findBBoxAdaptive(gray: Float32Array, W: number, H: number, isDark: boolean): BoardBBox | null {
  let workGray: Float32Array = gray;
  let workW: number = W;
  let workH: number = H;
  let scale: number = 1;
  const maxDim: number = Math.max(W, H);
  if (maxDim > ADAPTIVE_MAX_DIM) {
    scale = ADAPTIVE_MAX_DIM / maxDim;
    workW = Math.max(1, Math.round(W * scale));
    workH = Math.max(1, Math.round(H * scale));
    workGray = new Float32Array(workW * workH);
    for (let y: number = 0; y < workH; y++) {
      const srcY: number = Math.min(Math.floor(y / scale), H - 1);
      for (let x: number = 0; x < workW; x++) {
        const srcX: number = Math.min(Math.floor(x / scale), W - 1);
        workGray[y * workW + x] = gray[srcY * W + srcX];
      }
    }
  }
  const invScale: number = 1 / scale;
  const winR: number = Math.max(5, Math.floor(Math.min(workW, workH) / 25));
  const blurred: Float32Array = boxBlur(workGray, workW, workH, winR);

  for (const C of ADAPTIVE_CONTRASTS) {
    let binary: Uint8Array = new Uint8Array(workW * workH);
    for (let i: number = 0; i < workW * workH; i++) {
      if (isDark) {
        binary[i] = (workGray[i] > blurred[i] + C) ? 1 : 0;
      } else {
        binary[i] = (workGray[i] < blurred[i] - C) ? 1 : 0;
      }
    }
    binary = morphOpen3x3(binary, workW, workH);
    binary = dilate3x3(dilate3x3(binary, workW, workH), workW, workH);

    const colInk: number[] = new Array<number>(workW).fill(0);
    const rowInk: number[] = new Array<number>(workH).fill(0);
    for (let x: number = 0; x < workW; x++) {
      let c: number = 0;
      for (let y: number = 0; y < workH; y += 2) {
        if (binary[y * workW + x] === 1) { c++; }
      }
      colInk[x] = c;
    }
    for (let y: number = 0; y < workH; y++) {
      let c: number = 0;
      for (let x: number = 0; x < workW; x += 2) {
        if (binary[y * workW + x] === 1) { c++; }
      }
      rowInk[y] = c;
    }
    const colFrac: number[] = colInk.map((c: number) => c / (workH / 2));
    const rowFrac: number[] = rowInk.map((c: number) => c / (workW / 2));

    for (const thresh of ADAPTIVE_THRESHOLDS) {
      let minX: number = workW;
      let maxX: number = 0;
      let minY: number = workH;
      let maxY: number = 0;
      let found: boolean = false;
      for (let x: number = 0; x < workW; x++) {
        if (colFrac[x] > thresh) { if (x < minX) { minX = x; } if (x > maxX) { maxX = x; } found = true; }
      }
      for (let y: number = 0; y < workH; y++) {
        if (rowFrac[y] > thresh) { if (y < minY) { minY = y; } if (y > maxY) { maxY = y; } found = true; }
      }
      if (found) {
        const bbox: BoardBBox = {
          left: Math.round(minX * invScale),
          top: Math.round(minY * invScale),
          right: Math.round(maxX * invScale),
          bottom: Math.round(maxY * invScale),
          isDark
        };
        if (isValidBoardAspect(bbox, W, H) && bbox.right - bbox.left >= W * MIN_BOARD_SIZE_FRAC && bbox.bottom - bbox.top >= H * MIN_BOARD_SIZE_FRAC) {
          return bbox;
        }
      }
    }

    const colPeaks: number[] = findPeriodicPeaks(colFrac, ADAPTIVE_PEAK_THRESH);
    const rowPeaks: number[] = findPeriodicPeaks(rowFrac, ADAPTIVE_PEAK_THRESH);
    if (colPeaks.length >= PERIODIC_MIN_PEAKS && rowPeaks.length >= PERIODIC_MIN_PEAKS) {
      const bbox: BoardBBox = {
        left: Math.round(colPeaks[0] * invScale),
        top: Math.round(rowPeaks[0] * invScale),
        right: Math.round(colPeaks[colPeaks.length - 1] * invScale),
        bottom: Math.round(rowPeaks[rowPeaks.length - 1] * invScale),
        isDark
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
  let workGray: Float32Array = gray;
  let workW: number = W;
  let workH: number = H;
  let scale: number = 1;
  const maxDim: number = Math.max(W, H);
  if (maxDim > ADAPTIVE_MAX_DIM) {
    scale = ADAPTIVE_MAX_DIM / maxDim;
    workW = Math.max(1, Math.round(W * scale));
    workH = Math.max(1, Math.round(H * scale));
    workGray = new Float32Array(workW * workH);
    for (let y: number = 0; y < workH; y++) {
      const srcY: number = Math.min(Math.floor(y / scale), H - 1);
      for (let x: number = 0; x < workW; x++) {
        const srcX: number = Math.min(Math.floor(x / scale), W - 1);
        workGray[y * workW + x] = gray[srcY * W + srcX];
      }
    }
  }
  const invScale: number = 1 / scale;
  for (const delta of CONSERVATIVE_DELTAS) {
    const thr: number = isDark ? bg + delta : bg - delta;
    const binary: Uint8Array = new Uint8Array(workW * workH);
    for (let i: number = 0; i < workW * workH; i++) {
      binary[i] = isDark ? (workGray[i] > thr ? 1 : 0)
        : (workGray[i] < thr ? 1 : 0);
    }

    const colInk: number[] = new Array(workW).fill(0);
    const rowInk: number[] = new Array(workH).fill(0);
    for (let x: number = 0; x < workW; x++) {
      let c: number = 0;
      for (let y: number = 0; y < workH; y += 2) {
        if (binary[y * workW + x] === 1) { c++; }
      }
      colInk[x] = c;
    }
    for (let y: number = 0; y < workH; y++) {
      let c: number = 0;
      for (let x: number = 0; x < workW; x += 2) {
        if (binary[y * workW + x] === 1) { c++; }
      }
      rowInk[y] = c;
    }
    const colFrac: number[] = colInk.map((c: number) => c / (workH / 2));
    const rowFrac: number[] = rowInk.map((c: number) => c / (workW / 2));

    const colPeaks: number[] = findPeriodicPeaks(colFrac, CONSERVATIVE_PEAK_THRESH);
    const rowPeaks: number[] = findPeriodicPeaks(rowFrac, CONSERVATIVE_PEAK_THRESH);

    if (colPeaks.length >= CONSERVATIVE_MIN_PEAKS && rowPeaks.length >= CONSERVATIVE_MIN_PEAKS) {
      const bbox: BoardBBox = {
        left: Math.round(colPeaks[0] * invScale),
        top: Math.round(rowPeaks[0] * invScale),
        right: Math.round(colPeaks[colPeaks.length - 1] * invScale),
        bottom: Math.round(rowPeaks[rowPeaks.length - 1] * invScale),
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
function findBoxLongRunWithThresh(
  gray: Float32Array, W: number, H: number, isDark: boolean, absThresh: number
): BoardBBox | null {
  let workGray: Float32Array = gray;
  let workW: number = W;
  let workH: number = H;
  let scale: number = 1;
  const maxDim: number = Math.max(W, H);
  if (maxDim > ADAPTIVE_MAX_DIM) {
    scale = ADAPTIVE_MAX_DIM / maxDim;
    workW = Math.max(1, Math.round(W * scale));
    workH = Math.max(1, Math.round(H * scale));
    workGray = new Float32Array(workW * workH);
    for (let y: number = 0; y < workH; y++) {
      const srcY: number = Math.min(Math.floor(y / scale), H - 1);
      for (let x: number = 0; x < workW; x++) {
        const srcX: number = Math.min(Math.floor(x / scale), W - 1);
        workGray[y * workW + x] = gray[srcY * W + srcX];
      }
    }
  }
  const invScale: number = 1 / scale;
  const ink: Uint8Array = new Uint8Array(workW * workH);
  for (let i: number = 0; i < workW * workH; i++) {
    ink[i] = isDark ? (workGray[i] > absThresh ? 1 : 0) : (workGray[i] < absThresh ? 1 : 0);
  }
  const keep: Uint8Array = new Uint8Array(workW * workH);
  const MINRUN: number = Math.max(MINRUN_ABS_MIN, Math.floor(Math.min(workW, workH) * MINRUN_FRAC));
  let hRunCount: number = 0;
  let hKeepCount: number = 0;
  for (let y: number = 0; y < workH; y++) {
    let run: number = 0;
    let start: number = 0;
    for (let x: number = 0; x <= workW; x++) {
      if (x < workW && ink[y * workW + x] === 1) {
        if (run === 0) { start = x; }
        run++;
      } else {
        if (run >= MINRUN && start > 0 && x < workW) {
          for (let xx: number = start; xx < x; xx++) { keep[y * workW + xx] = 1; }
          hRunCount++;
          hKeepCount += run;
        }
        run = 0;
      }
    }
  }
  let vRunCount: number = 0;
  let vKeepCount: number = 0;
  for (let x: number = 0; x < workW; x++) {
    let run: number = 0;
    let start: number = 0;
    for (let y: number = 0; y < workH; y++) {
      if (ink[y * workW + x] === 1) {
        if (run === 0) { start = y; }
        run++;
      } else {
        if (run >= MINRUN && start > 0 && y < workH) {
          for (let yy: number = start; yy < y; yy++) { keep[yy * workW + x] = 1; }
          vRunCount++;
          vKeepCount += run;
        }
        run = 0;
      }
    }
  }
  let minX: number = workW, maxX: number = 0, minY: number = workH, maxY: number = 0, n: number = 0;
  for (let y: number = 0; y < workH; y++) {
    for (let x: number = 0; x < workW; x++) {
      if (keep[y * workW + x] === 1) {
        n++;
        if (x < minX) { minX = x; }
        if (x > maxX) { maxX = x; }
        if (y < minY) { minY = y; }
        if (y > maxY) { maxY = y; }
      }
    }
  }
  minX = Math.round(minX * invScale);
  maxX = Math.round(maxX * invScale);
  minY = Math.round(minY * invScale);
  maxY = Math.round(maxY * invScale);
  const bw: number = maxX - minX + 1;
  const bh: number = maxY - minY + 1;
  const aspect: number = bh > 0 ? bw / bh : 0;
  const areaRatio: number = (bw * bh) / (W * H);
  const diag: string = `longRun(abs=${absThresh}): MINRUN=${MINRUN} hRuns=${hRunCount} hPx=${hKeepCount} vRuns=${vRunCount} vPx=${vKeepCount} n=${n} bbox=[${minX},${minY},${maxX},${maxY}] ${bw}x${bh} aspect=${aspect.toFixed(2)} areaRatio=${areaRatio.toFixed(3)}`;
  g_lastBboxDiag += (g_lastBboxDiag.length > 0 ? '\n' : '') + diag;
  if (n < LONGRUN_MIN_PIXELS) {
    g_lastBboxDiag += `\n  → n<MIN(${LONGRUN_MIN_PIXELS}) null`;
    return null;
  }
  if (hRunCount > workH * LONGRUN_MAX_RUN_COUNT_FRAC || vRunCount > workW * LONGRUN_MAX_RUN_COUNT_FRAC) {
    g_lastBboxDiag += `\n  → runs>${LONGRUN_MAX_RUN_COUNT_FRAC.toFixed(2)}dim null`;
    return null;
  }
  if (bw < CONSERVATIVE_MIN_DIM || bh < CONSERVATIVE_MIN_DIM) {
    g_lastBboxDiag += `\n  → dim<MIN(${CONSERVATIVE_MIN_DIM}) null`;
    return null;
  }
  if (aspect < LONGRUN_MIN_ASPECT || aspect > LONGRUN_MAX_ASPECT) {
    g_lastBboxDiag += `\n  → aspect∉[${LONGRUN_MIN_ASPECT},${LONGRUN_MAX_ASPECT}] null`;
    return null;
  }
  if (areaRatio < MIN_BOARD_AREA_RATIO || areaRatio > MAX_BOARD_AREA_RATIO) {
    g_lastBboxDiag += `\n  → areaRatio∉[${MIN_BOARD_AREA_RATIO},${MAX_BOARD_AREA_RATIO.toFixed(2)}] null`;
    return null;
  }
  g_lastBboxDiag += `\n  → ✓`;
  return { left: minX, top: minY, right: maxX, bottom: maxY, isDark };
}

export function findBoxLongRun(
  gray: Float32Array, W: number, H: number, isDark: boolean, bg: number
): BoardBBox | null {
  const baseOffset: number = 60;
  const baseAbs: number = isDark ? bg + baseOffset : bg - baseOffset;
  const result: BoardBBox | null = findBoxLongRunWithThresh(gray, W, H, isDark, baseAbs);
  if (result !== null) { return result; }
  for (const offset of LONGRUN_TIGHTER_OFFSETS) {
    if (offset >= baseOffset) { continue; }
    const tighterAbs: number = isDark ? bg + offset : bg - offset;
    const r2: BoardBBox | null = findBoxLongRunWithThresh(gray, W, H, isDark, tighterAbs);
    if (r2 !== null) { return r2; }
  }
  return null;
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
  g_lastBboxDiag = '';
  const isDark: boolean = bg < BG_DARK_THRESHOLD;
  const gray: Float32Array = toGrayArray(pixels, width, height);
  const imgArea: number = width * height;
  const addDiag = (s: string): void => { g_lastBboxDiag += (g_lastBboxDiag.length > 0 ? '\n' : '') + s; };

  const longRun: BoardBBox | null = findBoxLongRun(gray, width, height, isDark, bg);
  if (longRun !== null) {
    addDiag(`路径=longRun ✓ [${longRun.left},${longRun.top},${longRun.right},${longRun.bottom}]`);
    return longRun;
  }
  addDiag('longRun → null, trying primary');

  const isDegenerate = (b: BoardBBox): boolean => {
    return ((b.right - b.left) * (b.bottom - b.top)) > imgArea * MAX_BOARD_AREA_RATIO;
  };

  const primary: BoardBBox | null = findBBoxInRectGray(
    gray, width, height, bg, isDark, 0, 0, width, height, BBOX_PRIMARY_THRESH, BBOX_PRIMARY_MIN_FRAC
  );
  if (primary !== null && isValidBoardAspect(primary, width, height) && !isDegenerate(primary)) {
    addDiag(`路径=primary ✓ [${primary.left},${primary.top},${primary.right},${primary.bottom}]`);
    return primary;
  }
  if (primary !== null) {
    addDiag(`primary found but invalid aspect=${((primary.right - primary.left) / (primary.bottom - primary.top)).toFixed(2)} or degenerate`);
  } else {
    addDiag('primary → null');
  }

  for (const thresh of BBOX_RELAXED_THRESHOLDS) {
    const res: BoardBBox | null = findBBoxInRectGray(
      gray, width, height, bg, isDark, 0, 0, width, height, thresh, BBOX_RELAXED_MIN_FRAC
    );
    if (res !== null && isValidBoardAspect(res, width, height) && !isDegenerate(res)) {
      addDiag(`路径=relaxed(thresh=${thresh}) ✓ [${res.left},${res.top},${res.right},${res.bottom}]`);
      return res;
    }
  }
  addDiag('relaxed → no valid result, trying regions');

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
  let bestRegionIdx: number = -1;
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
          if (area > bestArea) { bestArea = area; bestBox = res; bestRegionIdx = ri; }
        }
        break;
      }
    }
  }
  if (bestBox !== null) {
    addDiag(`region[${bestRegionIdx}] bestBox [${bestBox.left},${bestBox.top},${bestBox.right},${bestBox.bottom}] area=${bestArea}`);
  }

  // Adaptive check BEFORE conservative/bestBox: when the image has no padding
  // around the board, adaptive often finds a bbox covering >=85% of the image.
  // If that bbox is >1.5x the bestBox area, it's likely a better result for
  // no-padding images where region search only finds a sub-region.
  const adaptive: BoardBBox | null = findBBoxAdaptive(gray, width, height, isDark);
  if (adaptive !== null) {
    const aArea: number = (adaptive.right - adaptive.left) * (adaptive.bottom - adaptive.top);
    if (aArea < imgArea * MAX_BOARD_AREA_RATIO) {
      addDiag(`路径=adaptive ✓ [${adaptive.left},${adaptive.top},${adaptive.right},${adaptive.bottom}]`);
      return adaptive;
    }
    if (aArea >= imgArea * 0.85 && isValidBoardAspect(adaptive, width, height)) {
      if (bestBox === null || aArea > bestArea * 1.5) {
        addDiag(`路径=adaptive(large-no-pad) ✓ [${adaptive.left},${adaptive.top},${adaptive.right},${adaptive.bottom}] aArea=${aArea} bestArea=${bestArea}`);
        return adaptive;
      }
    }
  }
  addDiag('adaptive → null or no fallback');

  const conservative: BoardBBox | null = findBBoxConservative(gray, width, height, isDark, bg);
  if (conservative !== null) {
    addDiag(`路径=conservative ✓ [${conservative.left},${conservative.top},${conservative.right},${conservative.bottom}]`);
    return conservative;
  }
  addDiag('conservative → null');

  if (bestBox !== null) {
    addDiag(`路径=region(bestBox) [${bestBox.left},${bestBox.top},${bestBox.right},${bestBox.bottom}]`);
    return bestBox;
  }

  addDiag('全部失败 → 全图退化bbox');
  return { left: 0, top: 0, right: width, bottom: height, isDark };
}

// Detect and strip grid lines from signature edges.
// Grid lines intrude into cells as near-solid rows (horizontal) or columns (vertical)
// at the edge of the signature. A real digit never has ink in >=80% of positions
// along an entire edge row or column. If detected, clear that edge to prevent
// the grid line from corrupting the digit signature.
// Also checks the second row/column inward — a thick grid line may span 2 bins.
const GRID_LINE_RATIO: number = 0.80;

function stripEdgeGridLines(sig: number[]): void {
  const minCount: number = Math.floor(Math.min(SIG_ROWS, SIG_COLS) * GRID_LINE_RATIO);

  // Top edge rows (row 0, row 1)
  for (let row: number = 0; row <= 1 && row < SIG_ROWS; row++) {
    let inkCount: number = 0;
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[row * SIG_COLS + c] === 1) { inkCount++; }
    }
    if (inkCount >= minCount) {
      for (let c: number = 0; c < SIG_COLS; c++) {
        sig[row * SIG_COLS + c] = 0;
      }
    }
  }

  // Bottom edge rows (last row, second-to-last row)
  for (let row: number = SIG_ROWS - 1; row >= SIG_ROWS - 2 && row >= 0; row--) {
    let inkCount: number = 0;
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[row * SIG_COLS + c] === 1) { inkCount++; }
    }
    if (inkCount >= minCount) {
      for (let c: number = 0; c < SIG_COLS; c++) {
        sig[row * SIG_COLS + c] = 0;
      }
    }
  }

  // Left edge columns (col 0, col 1)
  for (let col: number = 0; col <= 1 && col < SIG_COLS; col++) {
    let inkCount: number = 0;
    for (let r: number = 0; r < SIG_ROWS; r++) {
      if (sig[r * SIG_COLS + col] === 1) { inkCount++; }
    }
    if (inkCount >= minCount) {
      for (let r: number = 0; r < SIG_ROWS; r++) {
        sig[r * SIG_COLS + col] = 0;
      }
    }
  }

  // Right edge columns (last col, second-to-last col)
  for (let col: number = SIG_COLS - 1; col >= SIG_COLS - 2 && col >= 0; col--) {
    let inkCount: number = 0;
    for (let r: number = 0; r < SIG_ROWS; r++) {
      if (sig[r * SIG_COLS + col] === 1) { inkCount++; }
    }
    if (inkCount >= minCount) {
      for (let r: number = 0; r < SIG_ROWS; r++) {
        sig[r * SIG_COLS + col] = 0;
      }
    }
  }
}

function stripFullHeightVerticalStrokes(sig: number[]): void {
  const FULL_HEIGHT_THRESH: number = SIG_ROWS * 0.70;
  const colInk: number[] = new Array<number>(SIG_COLS).fill(0);
  for (let c: number = 0; c < SIG_COLS; c++) {
    for (let r: number = 0; r < SIG_ROWS; r++) {
      if (sig[r * SIG_COLS + c] === 1) { colInk[c]++; }
    }
  }
  let rightMostHigh: number = -1;
  for (let c: number = SIG_COLS - 1; c >= 0; c--) {
    if (colInk[c] >= FULL_HEIGHT_THRESH) { rightMostHigh = c; break; }
  }
  let c: number = 0;
  while (c < SIG_COLS) {
    if (colInk[c] >= FULL_HEIGHT_THRESH) {
      let clusterEnd: number = c;
      while (clusterEnd + 1 < SIG_COLS && colInk[clusterEnd + 1] >= FULL_HEIGHT_THRESH * 0.5) {
        clusterEnd++;
      }
      const clusterW: number = clusterEnd - c + 1;
      if (clusterW <= 4 && c < rightMostHigh - 2) {
        for (let cc: number = c; cc <= clusterEnd; cc++) {
          for (let r: number = 0; r < SIG_ROWS; r++) {
            sig[r * SIG_COLS + cc] = 0;
          }
        }
      }
      c = clusterEnd + 1;
    } else {
      c++;
    }
  }
}

export async function cellSigFromGray(
  gray: Float32Array,
  width: number,
  cellLeft: number,
  cellTop: number,
  cellW: number,
  cellH: number,
  isDark: boolean,
  bg: number,
  gridRow: number = -1,
  gridCol: number = -1
): Promise<number[] | null> {
  let mxLeft: number = cellW * CELL_MARGIN_RATIO;
  let mxRight: number = cellW * CELL_MARGIN_RATIO;
  let myTop: number = cellH * CELL_MARGIN_RATIO;
  let myBot: number = cellH * CELL_MARGIN_RATIO;
  if (g_gridLineDetected && gridRow >= 0 && gridRow < 9 && gridCol >= 0 && gridCol < 9) {
    const idx: number = gridRow * 9 + gridCol;
    const maxMarginW: number = Math.floor(cellW * 0.45);
    const maxMarginH: number = Math.floor(cellH * 0.45);
    mxLeft = Math.max(mxLeft, Math.min(g_gridLineCropLeft[idx], maxMarginW));
    mxRight = Math.max(mxRight, Math.min(g_gridLineCropRight[idx], maxMarginW));
    myTop = Math.max(myTop, Math.min(g_gridLineCropTop[idx], maxMarginH));
    myBot = Math.max(myBot, Math.min(g_gridLineCropBot[idx], maxMarginH));
  }
  const x0: number = Math.floor(cellLeft + mxLeft);
  const y0: number = Math.floor(cellTop + myTop);
  const x1: number = Math.floor(cellLeft + cellW - mxRight);
  const y1: number = Math.floor(cellTop + cellH - myBot);
  const H: number = Math.floor(gray.length / width);
  const cellWInner: number = x1 - x0;
  const cellHInner: number = y1 - y0;

  let savedPixels: number[] = [];
  let savedPositions: number[] = [];

  {
    const rowAvg: Float32Array = new Float32Array(cellHInner);
    for (let dy: number = 0; dy < cellHInner; dy++) {
      let sum: number = 0;
      const y: number = y0 + dy;
      for (let dx: number = 0; dx < cellWInner; dx++) {
        sum += gray[y * width + x0 + dx];
      }
      rowAvg[dy] = sum / cellWInner;
    }
    const colAvg: Float32Array = new Float32Array(cellWInner);
    for (let dx: number = 0; dx < cellWInner; dx++) {
      let sum: number = 0;
      const x: number = x0 + dx;
      for (let dy: number = 0; dy < cellHInner; dy++) {
        sum += gray[(y0 + dy) * width + x];
      }
      colAvg[dx] = sum / cellHInner;
    }
    const isGridRow: boolean[] = new Array<boolean>(cellHInner).fill(false);
    let gridRowCount: number = 0;
    for (let dy: number = 0; dy < cellHInner; dy++) {
      const diff: number = isDark ? (rowAvg[dy] - bg) : (bg - rowAvg[dy]);
      if (diff > GRID_LINE_GRAY_DIFF) {
        let variance: number = 0;
        let inkCols: number = 0;
        const y: number = y0 + dy;
        for (let dx: number = 0; dx < cellWInner; dx++) {
          const g: number = gray[y * width + x0 + dx];
          const d: number = g - rowAvg[dy];
          variance += d * d;
          if (isDark ? g > (bg + INK_THRESH) : g < (bg - INK_THRESH)) { inkCols++; }
        }
        variance = Math.sqrt(variance / cellWInner);
        // fullSpan guard (log117): A real grid line spans the entire cell width,
        // while a digit stroke (e.g. digit-1 vertical bar) only covers ~30% of
        // columns. Requiring inkCols >= 70% prevents thin digit strokes from
        // being incorrectly neutralized as grid lines. This fixed digit-1
        // missing errors in tests 22 (FAIL→PASS), 24 (FAIL→PASS), and reduced
        // errors in test 25 from 7 to 2.
        const fullSpan: boolean = inkCols >= cellWInner * 0.7;
        if (variance < GRID_LINE_GRAY_DIFF * 2 && fullSpan) {
          isGridRow[dy] = true;
          gridRowCount++;
        }
      }
    }
    if (gridRowCount > Math.floor(cellHInner * 0.3)) {
      for (let dy: number = 0; dy < cellHInner; dy++) { isGridRow[dy] = false; }
    }
    const isGridCol: boolean[] = new Array<boolean>(cellWInner).fill(false);
    let gridColCount: number = 0;
    for (let dx: number = 0; dx < cellWInner; dx++) {
      const diff: number = isDark ? (colAvg[dx] - bg) : (bg - colAvg[dx]);
      if (diff > GRID_LINE_GRAY_DIFF) {
        let variance: number = 0;
        let inkRows: number = 0;
        const x: number = x0 + dx;
        for (let dy: number = 0; dy < cellHInner; dy++) {
          const g: number = gray[(y0 + dy) * width + x];
          const d: number = g - colAvg[dx];
          variance += d * d;
          if (isDark ? g > (bg + INK_THRESH) : g < (bg - INK_THRESH)) { inkRows++; }
        }
        variance = Math.sqrt(variance / cellHInner);
        // fullSpan guard for columns: same as rows — real grid lines span the
        // full cell height, digit strokes do not. Prevents digit-1 vertical bar
        // from being neutralized as a grid column.
        const fullSpan: boolean = inkRows >= cellHInner * 0.7;
        if (variance < GRID_LINE_GRAY_DIFF * 2 && fullSpan) {
          isGridCol[dx] = true;
          gridColCount++;
        }
      }
    }
    if (gridColCount > Math.floor(cellWInner * 0.3)) {
      for (let dx: number = 0; dx < cellWInner; dx++) { isGridCol[dx] = false; }
    }
    for (let dy: number = 0; dy < cellHInner; dy++) {
      if (!isGridRow[dy]) { continue; }
      const y: number = y0 + dy;
      for (let dx: number = 0; dx < cellWInner; dx++) {
        const pos: number = y * width + x0 + dx;
        savedPixels.push(gray[pos]);
        savedPositions.push(pos);
        gray[pos] = bg;
      }
    }
    for (let dx: number = 0; dx < cellWInner; dx++) {
      if (!isGridCol[dx]) { continue; }
      const x: number = x0 + dx;
      for (let dy: number = 0; dy < cellHInner; dy++) {
        const pos: number = (y0 + dy) * width + x;
        savedPixels.push(gray[pos]);
        savedPositions.push(pos);
        gray[pos] = bg;
      }
    }
  }

  let ink: number = 0;
  let area: number = 0;
  let bminX: number = 1000000;
  let bmaxX: number = -1;
  let bminY: number = 1000000;
  let bmaxY: number = -1;
  const inkBg: number = isDark ? bg + INK_THRESH : bg - INK_THRESH;

  for (let y: number = y0; y < y1; y++) {
    for (let x: number = x0; x < x1; x++) {
      area++;
      const g: number = gray[y * width + x];
      if (isDark ? g > inkBg : g < inkBg) {
        ink++;
        if (x < bminX) { bminX = x; }
        if (x > bmaxX) { bmaxX = x; }
        if (y < bminY) { bminY = y; }
        if (y > bmaxY) { bmaxY = y; }
      }
    }
  }

  g_lastRawInkRatio = area > 0 ? ink / area : 0;

  let result: number[] | null = null;
  if (ink >= area * MIN_CELL_INK_RATIO && bmaxX >= 0) {
    const bw: number = bmaxX - bminX + 1;
    const bh: number = bmaxY - bminY + 1;

    if (bw >= SAUVOLA_MIN_DIM * 3 && bh >= SAUVOLA_MIN_DIM * 3) {
      const sauvBinary: Float32Array | null = await sauvolaThreshold(gray, width, H, bminX, bminY, bw, bh, isDark);
      if (sauvBinary !== null) {
        const scale: number = Math.max(1, Math.ceil(SIG_COLS / bw), Math.ceil(SIG_ROWS / bh));
        const sbw: number = bw * scale;
        const sbh: number = bh * scale;
        const scaledBinary: Float32Array = new Float32Array(sbw * sbh);
        for (let r: number = 0; r < sbh; r++) {
          for (let c: number = 0; c < sbw; c++) {
            scaledBinary[r * sbw + c] = sauvBinary[Math.floor(r / scale) * bw + Math.floor(c / scale)];
          }
        }
        const sauvSig: number[] = new Array<number>(SIG_LEN).fill(0);
        for (let r: number = 0; r < SIG_ROWS; r++) {
          for (let c: number = 0; c < SIG_COLS; c++) {
            const sx0: number = Math.floor(sbw * c / SIG_COLS);
            const sx1: number = Math.floor(sbw * (c + 1) / SIG_COLS);
            const sy0: number = Math.floor(sbh * r / SIG_ROWS);
            const sy1: number = Math.floor(sbh * (r + 1) / SIG_ROWS);
            let s: number = 0;
            let n: number = 0;
            for (let ly: number = sy0; ly < sy1; ly++) {
              for (let lx: number = sx0; lx < sx1; lx++) {
                s += scaledBinary[ly * sbw + lx];
                n++;
              }
            }
            sauvSig[r * SIG_COLS + c] = (n > 0 && s / n > 0.5) ? 1 : 0;
          }
        }
        const sauvInk: number = countInk(sauvSig);
        stripEdgeGridLines(sauvSig);
        stripFullHeightVerticalStrokes(sauvSig);
        const sauvInkStripped: number = countInk(sauvSig);
        if (sauvInkStripped >= THIN1_MIN_INK_COUNT && sauvInkStripped <= MAX_INK_COUNT) {
          result = sauvSig;
        }
      }
    }

    if (result === null) {
      const sig: number[] = new Array<number>(SIG_LEN).fill(0);
      const scale2: number = Math.max(1, Math.ceil(SIG_COLS / bw), Math.ceil(SIG_ROWS / bh));
      const sbw2: number = bw * scale2;
      const sbh2: number = bh * scale2;
      const scaledGray: Float32Array = new Float32Array(sbw2 * sbh2);
      for (let r: number = 0; r < sbh2; r++) {
        for (let c: number = 0; c < sbw2; c++) {
          const sy: number = bminY + Math.floor(r / scale2);
          const sx: number = bminX + Math.floor(c / scale2);
          scaledGray[r * sbw2 + c] = (sy >= 0 && sy < H && sx >= 0 && sx < width) ? gray[sy * width + sx] : bg;
        }
      }
      for (let r: number = 0; r < SIG_ROWS; r++) {
        for (let c: number = 0; c < SIG_COLS; c++) {
          const sx0: number = Math.floor(sbw2 * c / SIG_COLS);
          const sx1: number = Math.floor(sbw2 * (c + 1) / SIG_COLS);
          const sy0: number = Math.floor(sbh2 * r / SIG_ROWS);
          const sy1: number = Math.floor(sbh2 * (r + 1) / SIG_ROWS);
          let s: number = 0;
          let n: number = 0;
          for (let ly: number = sy0; ly < sy1; ly++) {
            for (let lx: number = sx0; lx < sx1; lx++) {
              s += scaledGray[ly * sbw2 + lx];
              n++;
            }
          }
          const avg: number = n > 0 ? s / n : bg;
          sig[r * SIG_COLS + c] = (isDark ? avg > inkBg : avg < inkBg) ? 1 : 0;
        }
      }
      const inkCount: number = countInk(sig);
       stripEdgeGridLines(sig);
      stripFullHeightVerticalStrokes(sig);
      const inkCountStripped: number = countInk(sig);
      if (inkCountStripped >= THIN1_MIN_INK_COUNT && inkCountStripped <= MAX_INK_COUNT) {
        result = sig;
      } else {
        g_lastPixelDiag = `sigInk=${inkCountStripped} gate=${THIN1_MIN_INK_COUNT}`;
      }
    }
  } else {
    const ratio: number = g_lastRawInkRatio;
    g_lastPixelDiag = `rawInk=${ink}/${area} ratio=${ratio.toFixed(4)} gate=${MIN_CELL_INK_RATIO.toFixed(3)}`;
  }

  for (let i: number = 0; i < savedPositions.length; i++) {
    gray[savedPositions[i]] = savedPixels[i];
  }
  return result;
}

// Lower ink threshold for retry when initial signature has low inkCount.
// Half of INK_THRESH, used to recover faint strokes in small cells.
const LOW_INK_THRESH_RETRY: number = Math.floor(INK_THRESH / 2);

export async function cellSigFromGrayLowThresh(
  gray: Float32Array,
  width: number,
  cellLeft: number,
  cellTop: number,
  cellW: number,
  cellH: number,
  isDark: boolean,
  bg: number,
  gridRow: number = -1,
  gridCol: number = -1
): Promise<number[] | null> {
  let mxLeft: number = cellW * CELL_MARGIN_RATIO;
  let mxRight: number = cellW * CELL_MARGIN_RATIO;
  let myTop: number = cellH * CELL_MARGIN_RATIO;
  let myBot: number = cellH * CELL_MARGIN_RATIO;
  if (g_gridLineDetected && gridRow >= 0 && gridRow < 9 && gridCol >= 0 && gridCol < 9) {
    const idx: number = gridRow * 9 + gridCol;
    const maxMarginW: number = Math.floor(cellW * 0.45);
    const maxMarginH: number = Math.floor(cellH * 0.45);
    mxLeft = Math.max(mxLeft, Math.min(g_gridLineCropLeft[idx], maxMarginW));
    mxRight = Math.max(mxRight, Math.min(g_gridLineCropRight[idx], maxMarginW));
    myTop = Math.max(myTop, Math.min(g_gridLineCropTop[idx], maxMarginH));
    myBot = Math.max(myBot, Math.min(g_gridLineCropBot[idx], maxMarginH));
  }
  const x0: number = Math.floor(cellLeft + mxLeft);
  const y0: number = Math.floor(cellTop + myTop);
  const x1: number = Math.floor(cellLeft + cellW - mxRight);
  const y1: number = Math.floor(cellTop + cellH - myBot);
  const H: number = Math.floor(gray.length / width);
  const cellWInner: number = x1 - x0;
  const cellHInner: number = y1 - y0;

  const rowAvg: number[] = new Array<number>(cellHInner).fill(0);
  for (let dy: number = 0; dy < cellHInner; dy++) {
    let s: number = 0;
    for (let dx: number = 0; dx < cellWInner; dx++) {
      s += gray[(y0 + dy) * width + x0 + dx];
    }
    rowAvg[dy] = s / cellWInner;
  }
  const isGridRow: boolean[] = new Array<boolean>(cellHInner).fill(false);
  for (let dy: number = 0; dy < cellHInner; dy++) {
    const diff: number = isDark ? (rowAvg[dy] - bg) : (bg - rowAvg[dy]);
    if (diff > GRID_LINE_GRAY_DIFF) {
      let variance: number = 0;
      let inkCols: number = 0;
      const y: number = y0 + dy;
      for (let dx: number = 0; dx < cellWInner; dx++) {
        const g: number = gray[y * width + x0 + dx];
        const d: number = g - rowAvg[dy];
        variance += d * d;
        if (isDark ? g > (bg + INK_THRESH) : g < (bg - INK_THRESH)) { inkCols++; }
      }
      variance = Math.sqrt(variance / cellWInner);
      // fullSpan guard (lowThresh path): same as cellSigFromGray — prevents
      // thin digit strokes from being neutralized in low-threshold retry path
      if (variance < GRID_LINE_GRAY_DIFF * 2 && inkCols >= cellWInner * 0.7) {
        isGridRow[dy] = true;
      }
    }
  }
  const colAvg: number[] = new Array<number>(cellWInner).fill(0);
  for (let dx: number = 0; dx < cellWInner; dx++) {
    let s: number = 0;
    for (let dy: number = 0; dy < cellHInner; dy++) {
      s += gray[(y0 + dy) * width + x0 + dx];
    }
    colAvg[dx] = s / cellHInner;
  }
  const isGridCol: boolean[] = new Array<boolean>(cellWInner).fill(false);
  for (let dx: number = 0; dx < cellWInner; dx++) {
    const diff: number = isDark ? (colAvg[dx] - bg) : (bg - colAvg[dx]);
    if (diff > GRID_LINE_GRAY_DIFF) {
      let variance: number = 0;
      let inkRows: number = 0;
      const x: number = x0 + dx;
      for (let dy: number = 0; dy < cellHInner; dy++) {
        const g: number = gray[(y0 + dy) * width + x];
        const d: number = g - colAvg[dx];
        variance += d * d;
        if (isDark ? g > (bg + INK_THRESH) : g < (bg - INK_THRESH)) { inkRows++; }
      }
      variance = Math.sqrt(variance / cellHInner);
      // fullSpan guard for columns (lowThresh path)
      if (variance < GRID_LINE_GRAY_DIFF * 2 && inkRows >= cellHInner * 0.7) {
        isGridCol[dx] = true;
      }
    }
  }

  const savedPixels: number[] = [];
  const savedPositions: number[] = [];
  for (let dy: number = 0; dy < cellHInner; dy++) {
    if (!isGridRow[dy]) { continue; }
    const y: number = y0 + dy;
    for (let dx: number = 0; dx < cellWInner; dx++) {
      const pos: number = y * width + x0 + dx;
      savedPixels.push(gray[pos]);
      savedPositions.push(pos);
      gray[pos] = bg;
    }
  }
  for (let dx: number = 0; dx < cellWInner; dx++) {
    if (!isGridCol[dx]) { continue; }
    const x: number = x0 + dx;
    for (let dy: number = 0; dy < cellHInner; dy++) {
      const pos: number = (y0 + dy) * width + x;
      savedPixels.push(gray[pos]);
      savedPositions.push(pos);
      gray[pos] = bg;
    }
  }

  let bminX: number = 1000000;
  let bmaxX: number = -1;
  let bminY: number = 1000000;
  let bmaxY: number = -1;
  let inkCount: number = 0;
  const lowInkBg: number = isDark ? bg + LOW_INK_THRESH_RETRY : bg - LOW_INK_THRESH_RETRY;

  for (let y: number = y0; y < y1; y++) {
    for (let x: number = x0; x < x1; x++) {
      const g: number = gray[y * width + x];
      if (isDark ? g > lowInkBg : g < lowInkBg) {
        inkCount++;
        if (x < bminX) { bminX = x; }
        if (x > bmaxX) { bmaxX = x; }
        if (y < bminY) { bminY = y; }
        if (y > bmaxY) { bmaxY = y; }
      }
    }
  }

  let result: number[] | null = null;
  if (bmaxX >= 0) {
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
        sig[r * SIG_COLS + c] = (isDark ? avg > lowInkBg : avg < lowInkBg) ? 1 : 0;
      }
    }

    const sigInk: number = countInk(sig);
    stripEdgeGridLines(sig);
    stripFullHeightVerticalStrokes(sig);
    const sigInkStripped: number = countInk(sig);
    if (sigInkStripped >= THIN1_MIN_INK_COUNT && sigInkStripped <= MAX_INK_COUNT) {
      result = sig;
    }
  }

  for (let i: number = 0; i < savedPositions.length; i++) {
    gray[savedPositions[i]] = savedPixels[i];
  }
  return result;
}

export async function cellSigFromGrayThin(
  gray: Float32Array,
  width: number,
  cellLeft: number,
  cellTop: number,
  cellW: number,
  cellH: number,
  isDark: boolean,
  bg: number,
  gridRow: number = -1,
  gridCol: number = -1
): Promise<number[] | null> {
  const THIN_MARGIN: number = 0.02;
  const LOW_GRID_DIFF: number = LOW_INK_THRESH_RETRY * 0.4;
  let mxLeft: number = cellW * THIN_MARGIN;
  let mxRight: number = cellW * THIN_MARGIN;
  let myTop: number = cellH * THIN_MARGIN;
  let myBot: number = cellH * THIN_MARGIN;
  if (g_gridLineDetected && gridRow >= 0 && gridRow < 9 && gridCol >= 0 && gridCol < 9) {
    const idx: number = gridRow * 9 + gridCol;
    const maxMarginW: number = Math.floor(cellW * 0.45);
    const maxMarginH: number = Math.floor(cellH * 0.45);
    mxLeft = Math.max(mxLeft, Math.min(g_gridLineCropLeft[idx], maxMarginW));
    mxRight = Math.max(mxRight, Math.min(g_gridLineCropRight[idx], maxMarginW));
    myTop = Math.max(myTop, Math.min(g_gridLineCropTop[idx], maxMarginH));
    myBot = Math.max(myBot, Math.min(g_gridLineCropBot[idx], maxMarginH));
  }
  const x0: number = Math.floor(cellLeft + mxLeft);
  const y0: number = Math.floor(cellTop + myTop);
  const x1: number = Math.floor(cellLeft + cellW - mxRight);
  const y1: number = Math.floor(cellTop + cellH - myBot);
  const H: number = Math.floor(gray.length / width);
  const cellWInner: number = x1 - x0;
  const cellHInner: number = y1 - y0;

  const rowAvg: number[] = new Array<number>(cellHInner).fill(0);
  for (let dy: number = 0; dy < cellHInner; dy++) {
    let s: number = 0;
    for (let dx: number = 0; dx < cellWInner; dx++) {
      s += gray[(y0 + dy) * width + x0 + dx];
    }
    rowAvg[dy] = s / cellWInner;
  }
  const isGridRow: boolean[] = new Array<boolean>(cellHInner).fill(false);
  let gridRowCount: number = 0;
  for (let dy: number = 0; dy < cellHInner; dy++) {
    const diff: number = isDark ? (rowAvg[dy] - bg) : (bg - rowAvg[dy]);
    if (diff > LOW_GRID_DIFF) {
      let variance: number = 0;
      const y: number = y0 + dy;
      for (let dx: number = 0; dx < cellWInner; dx++) {
        const g: number = gray[y * width + x0 + dx];
        const d: number = g - rowAvg[dy];
        variance += d * d;
      }
      variance = Math.sqrt(variance / cellWInner);
      if (variance < LOW_GRID_DIFF * 3) {
        isGridRow[dy] = true;
        gridRowCount++;
      }
    }
  }
  if (gridRowCount > Math.floor(cellHInner * 0.3)) {
    for (let dy: number = 0; dy < cellHInner; dy++) { isGridRow[dy] = false; }
  }
  const colAvg: number[] = new Array<number>(cellWInner).fill(0);
  for (let dx: number = 0; dx < cellWInner; dx++) {
    let s: number = 0;
    for (let dy: number = 0; dy < cellHInner; dy++) {
      s += gray[(y0 + dy) * width + x0 + dx];
    }
    colAvg[dx] = s / cellHInner;
  }
  const isGridCol: boolean[] = new Array<boolean>(cellWInner).fill(false);
  let gridColCount: number = 0;
  for (let dx: number = 0; dx < cellWInner; dx++) {
    const diff: number = isDark ? (colAvg[dx] - bg) : (bg - colAvg[dx]);
    if (diff > LOW_GRID_DIFF) {
      let variance: number = 0;
      const x: number = x0 + dx;
      for (let dy: number = 0; dy < cellHInner; dy++) {
        const g: number = gray[(y0 + dy) * width + x];
        const d: number = g - colAvg[dx];
        variance += d * d;
      }
      variance = Math.sqrt(variance / cellHInner);
      if (variance < LOW_GRID_DIFF * 3) {
        isGridCol[dx] = true;
        gridColCount++;
      }
    }
  }
  if (gridColCount > Math.floor(cellWInner * 0.3)) {
    for (let dx: number = 0; dx < cellWInner; dx++) { isGridCol[dx] = false; }
  }

  const savedPixels: number[] = [];
  const savedPositions: number[] = [];
  for (let dy: number = 0; dy < cellHInner; dy++) {
    if (!isGridRow[dy]) { continue; }
    const y: number = y0 + dy;
    for (let dx: number = 0; dx < cellWInner; dx++) {
      const pos: number = y * width + x0 + dx;
      savedPixels.push(gray[pos]);
      savedPositions.push(pos);
      gray[pos] = bg;
    }
  }
  for (let dx: number = 0; dx < cellWInner; dx++) {
    if (!isGridCol[dx]) { continue; }
    const x: number = x0 + dx;
    for (let dy: number = 0; dy < cellHInner; dy++) {
      const pos: number = (y0 + dy) * width + x;
      savedPixels.push(gray[pos]);
      savedPositions.push(pos);
      gray[pos] = bg;
    }
  }

  let bminX: number = 1000000;
  let bmaxX: number = -1;
  let bminY: number = 1000000;
  let bmaxY: number = -1;
  let inkCount: number = 0;
  const lowInkBg: number = isDark ? bg + LOW_INK_THRESH_RETRY : bg - LOW_INK_THRESH_RETRY;
  for (let y: number = y0; y < y1; y++) {
    for (let x: number = x0; x < x1; x++) {
      const g: number = gray[y * width + x];
      if (isDark ? g > lowInkBg : g < lowInkBg) {
        inkCount++;
        if (x < bminX) { bminX = x; }
        if (x > bmaxX) { bmaxX = x; }
        if (y < bminY) { bminY = y; }
        if (y > bmaxY) { bmaxY = y; }
      }
    }
  }

  let result: number[] | null = null;
  if (bmaxX >= 0) {
    const bw: number = bmaxX - bminX + 1;
    const bh: number = bmaxY - bminY + 1;
    if (bw >= 3 && bh >= 3) {
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
          sig[r * SIG_COLS + c] = (isDark ? avg > lowInkBg : avg < lowInkBg) ? 1 : 0;
        }
      }
      const sigInk: number = countInk(sig);
      stripEdgeGridLines(sig);
      stripFullHeightVerticalStrokes(sig);
      const sigInkStripped: number = countInk(sig);
      if (sigInkStripped >= THIN1_MIN_INK_COUNT && sigInkStripped <= MAX_INK_COUNT) {
        result = sig;
      }
    }
  }

  for (let i: number = 0; i < savedPositions.length; i++) {
    gray[savedPositions[i]] = savedPixels[i];
  }
  return result;
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
  if (inkCount < THIN1_MIN_INK_COUNT || inkCount > MAX_INK_COUNT) { return null; }
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
  if (inkCount < THIN1_MIN_INK_COUNT || inkCount > MAX_INK_COUNT) {
    const fallbackSig: number[] | null = cellSigOtsuFallback(
      pixels, width, bminX, bminY, bw, bh, isDark, bg
    );
    if (fallbackSig !== null) {
      const fbInk: number = countInk(fallbackSig);
      if (fbInk >= THIN1_MIN_INK_COUNT && fbInk <= MAX_INK_COUNT) {
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
  if (inkCount < THIN1_MIN_INK_COUNT || inkCount > MAX_INK_COUNT) { return null; }
  return sig;
}

export function hogVerticalGradient(sig: number[]): number {
  let posGrad: number = 0;
  let negGrad: number = 0;
  for (let r: number = 1; r < SIG_ROWS; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      const d: number = sig[r * SIG_COLS + c] - sig[(r - 1) * SIG_COLS + c];
      if (d > 0) { posGrad += d; } else { negGrad += d; }
    }
  }
  return posGrad + negGrad > 0 ? posGrad / (posGrad - negGrad) : 0.5;
}

export function strokeWidthRatio(sig: number[]): number {
  let maxH: number = 0;
  for (let r: number = 0; r < SIG_ROWS; r++) {
    let run: number = 0;
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) { run++; }
      else {
        if (run > maxH) { maxH = run; }
        run = 0;
      }
    }
    if (run > maxH) { maxH = run; }
  }
  let maxV: number = 0;
  for (let c: number = 0; c < SIG_COLS; c++) {
    let run: number = 0;
    for (let r: number = 0; r < SIG_ROWS; r++) {
      if (sig[r * SIG_COLS + c] === 1) { run++; }
      else {
        if (run > maxV) { maxV = run; }
        run = 0;
      }
    }
    if (run > maxV) { maxV = run; }
  }
  return maxV > 0 ? maxH / maxV : 0;
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

function detectThinOne(sig: number[], inkCount: number): boolean {
  if (inkCount < THIN1_MIN_INK_COUNT) { return false; }
  let minCol: number = SIG_COLS;
  let maxCol: number = -1;
  let minRow: number = SIG_ROWS;
  let maxRow: number = -1;
  const colInk: number[] = new Array<number>(SIG_COLS).fill(0);
  const rowInk: number[] = new Array<number>(SIG_ROWS).fill(0);

  for (let r: number = 0; r < SIG_ROWS; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) {
        if (c < minCol) { minCol = c; }
        if (c > maxCol) { maxCol = c; }
        if (r < minRow) { minRow = r; }
        if (r > maxRow) { maxRow = r; }
        colInk[c]++;
        rowInk[r]++;
      }
    }
  }

  if (maxCol < 0) { return false; }

  const inkWidth: number = maxCol - minCol + 1;
  const inkHeight: number = maxRow - minRow + 1;

  if (inkWidth > SIG_COLS * 0.50) { return false; }
  if (inkHeight < SIG_ROWS * 0.50) { return false; }
  if (inkWidth === 0 || inkHeight / inkWidth < 1.8) { return false; }

  const bboxArea: number = inkWidth * inkHeight;
  if (bboxArea === 0) { return false; }
  const density: number = inkCount / bboxArea;
  if (density < 0.30) { return false; }

  const startRow: number = Math.floor(SIG_ROWS * 0.2);
  const endRow: number = Math.floor(SIG_ROWS * 0.8);
  let rowsWithInk: number = 0;
  const totalMidRows: number = endRow - startRow;
  for (let r: number = startRow; r < endRow; r++) {
    if (rowInk[r] > 0) { rowsWithInk++; }
  }
  if (rowsWithInk < totalMidRows * 0.65) { return false; }

  let colSum: number = 0;
  for (let c: number = 0; c < SIG_COLS; c++) {
    colSum += c * colInk[c];
  }
  const colCenter: number = inkCount > 0 ? colSum / inkCount : SIG_COLS / 2;
  if (colCenter < SIG_COLS * 0.20 || colCenter > SIG_COLS * 0.80) { return false; }

  return true;
}

function tryStripLeftEdgeAs1(sig: number[], inkCount: number, origBestDigit: number, origBestScore: number): number {
  if (origBestDigit !== 4) { return 0; }

  let leftColInk: number = 0;
  for (let r: number = 0; r < SIG_ROWS; r++) {
    if (sig[r * SIG_COLS] === 1) { leftColInk++; }
  }
  if (leftColInk < 3) {
    g_lastPixelDiag = `stripLeftSkip: col0=${leftColInk}`;
    return 0;
  }

  const midTop: number = Math.floor(SIG_ROWS * 0.35);
  const midBot: number = Math.floor(SIG_ROWS * 0.65);
  let maxMidRowSpan: number = 0;
  for (let r: number = midTop; r < midBot; r++) {
    let span: number = 0;
    let start: number = -1;
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) {
        if (start < 0) { start = c; }
        span = c - start + 1;
      } else if (start >= 0) {
        break;
      }
    }
    if (span > maxMidRowSpan) { maxMidRowSpan = span; }
  }
  if (maxMidRowSpan >= SIG_COLS * 0.40) {
    g_lastPixelDiag = `stripLeftSkip: hasHBar span=${maxMidRowSpan}`;
    return 0;
  }

  const cleaned: number[] = new Array<number>(SIG_LEN).fill(0);
  let cleanInk: number = 0;
  const cleanedInkPos: number[] = [];
  for (let r: number = 0; r < SIG_ROWS; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      const idx: number = r * SIG_COLS + c;
      if (c >= 2) {
        cleaned[idx] = sig[idx];
        if (sig[idx] === 1) { cleanInk++; cleanedInkPos.push(idx); }
      }
    }
  }
  const cleanedInkLen: number = cleanedInkPos.length;
  if (cleanInk < THIN1_MIN_INK_COUNT) {
    g_lastPixelDiag = `stripLeftCleanInkLow: cleanInk=${cleanInk}`;
    return 0;
  }

  const digitBestScore: number[] = new Array<number>(10).fill(-100000);
  const digitBestRecall: number[] = new Array<number>(10).fill(0);
  for (let d: number = 1; d <= 9; d++) {
    const tplsD: DigitTemplate[] = g_templatesByDigit[d];
    for (let ti: number = 0; ti < tplsD.length; ti++) {
      const t: DigitTemplate = tplsD[ti];
      if (!templateMatchesInkFilter(t, inkCount)) { continue; }
      const kb: Int8Array = t.keyBytes;
      let tp: number = 0;
      for (let j: number = 0; j < cleanedInkLen; j++) {
        if (kb[cleanedInkPos[j]] === 1) { tp++; }
      }
      const match: number = SIG_LEN - cleanedInkLen - t.inkCount + 2 * tp;
      const score: number = match - (SIG_LEN - match) * TEMPLATE_MISMATCH_PENALTY;
      if (score > digitBestScore[t.digit]) {
        digitBestScore[t.digit] = score;
        digitBestRecall[t.digit] = t.inkCount > 0 ? tp / t.inkCount : 0;
      }
    }
  }

  const score1: number = digitBestScore[1];
  const recall1: number = digitBestRecall[1];
  const geoMinScore: number = Math.floor(SIG_LEN * 0.55);

  let bestCleanDigit: number = 0;
  let bestCleanScore: number = -100000;
  for (let d: number = 1; d <= 9; d++) {
    if (digitBestScore[d] > bestCleanScore) {
      bestCleanDigit = d;
      bestCleanScore = digitBestScore[d];
    }
  }

  hilog.info(DOMAIN, TAG, 'stripLeftMatch: score1=%{public}.1f recall1=%{public}.2f bestClean=%{public}d(%{public}.1f) orig=4(%{public}.1f) cleanInk=%{public}d hBar=${maxMidRowSpan}',
    score1, recall1, bestCleanDigit, bestCleanScore, origBestScore, cleanInk, maxMidRowSpan);

  if (score1 < geoMinScore || recall1 < 0.30) {
    g_lastPixelDiag = `stripLeftFail: score1=${score1} recall1=${recall1.toFixed(2)}`;
    return 0;
  }

  if (bestCleanDigit !== 1) {
    g_lastPixelDiag = `stripLeftFail: bestClean=${bestCleanDigit}(${bestCleanScore.toFixed(0)})>1`;
    return 0;
  }

  g_lastPixelDiag = `stripLeft→1: score1=${score1} recall1=${recall1.toFixed(2)} cleanInk=${cleanInk}`;
  g_lastConfidence = 0.55;
  return 1;
}

function sigToCompactStr(sig: number[]): string {
  let s: string = '';
  for (let r: number = 0; r < SIG_ROWS; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      s += sig[r * SIG_COLS + c] === 1 ? '#' : '.';
    }
    if (r < SIG_ROWS - 1) { s += '|'; }
  }
  return s;
}

function maxHorizontalSpan(sig: number[], rowStart: number, rowEnd: number): number {
  let maxSpan: number = 0;
  for (let r: number = rowStart; r < rowEnd; r++) {
    let start: number = -1;
    let span: number = 0;
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) {
        if (start < 0) { start = c; }
        span = c - start + 1;
      } else if (start >= 0) {
        break;
      }
    }
    if (span > maxSpan) { maxSpan = span; }
  }
  return maxSpan;
}

function isLikelyNot4(sig: number[]): boolean {
  const lowerTop: number = Math.floor(SIG_ROWS * 0.60);
  const lowerBot: number = Math.floor(SIG_ROWS * 0.85);
  const lowerSpan: number = maxHorizontalSpan(sig, lowerTop, lowerBot);
  if (lowerSpan >= SIG_COLS * 0.40) { return false; }

  const midTop: number = Math.floor(SIG_ROWS * 0.25);
  const midBot: number = Math.floor(SIG_ROWS * 0.60);
  const hSpan: number = maxHorizontalSpan(sig, midTop, midBot);
  if (hSpan < SIG_COLS * 0.30) { return true; }

  const topRow: number = Math.floor(SIG_ROWS * 0.15);
  const midRow: number = Math.floor(SIG_ROWS * 0.45);
  let topLeftInk: number = 0;
  let topRightInk: number = 0;
  for (let r: number = topRow; r < midRow; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) {
        if (c < SIG_COLS / 2) { topLeftInk++; } else { topRightInk++; }
      }
    }
  }
  if (topLeftInk === 0 && topRightInk > 0) { return true; }

  return false;
}

export async function recognizeDigit(sig: number[], inkCount: number): Promise<number> {
  if (inkCount < THIN1_MIN_INK_COUNT) { return 0; }
  if (g_templates.length === 0) { return 0; }
  const sigInkPos: number[] = [];
  for (let i: number = 0; i < SIG_LEN; i++) {
    if (sig[i] === 1) { sigInkPos.push(i); }
  }
  const sigInkLen: number = sigInkPos.length;
  const lowInk: boolean = inkCount < MIN_INK_COUNT;
  if (lowInk) {
    let best1Score: number = -100000;
    let best1Key: Int8Array | null = null;
    const tpls1: DigitTemplate[] = g_templatesByDigit[1];
    for (let ti: number = 0; ti < tpls1.length; ti++) {
      if (ti % 30 === 0) { await yieldThread(); }
      const t: DigitTemplate = tpls1[ti];
      if (!templateMatchesInkFilter(t, inkCount)) { continue; }
      const kb: Int8Array = t.keyBytes;
      let tp: number = 0;
      for (let j: number = 0; j < sigInkLen; j++) {
        if (kb[sigInkPos[j]] === 1) { tp++; }
      }
      const match: number = SIG_LEN - sigInkLen - t.inkCount + 2 * tp;
      const score: number = match - (SIG_LEN - match) * TEMPLATE_MISMATCH_PENALTY;
      if (score > best1Score) { best1Score = score; best1Key = kb; }
    }
    const lowInkMinScore: number = Math.floor(SIG_LEN * 0.57);
    const geoMinScore: number = Math.floor(SIG_LEN * 0.55);
    const veryThinInk: boolean = inkCount < MIN_INK_COUNT_DIGIT1;
    if (veryThinInk) {
      if (best1Key !== null) {
        let tp: number = 0;
        let tplInkC: number = 0;
        for (let i: number = 0; i < SIG_LEN; i++) {
          if (best1Key[i] === 1) {
            tplInkC++;
            if (sig[i] === 1) { tp++; }
          }
        }
        const recall: number = tplInkC > 0 ? tp / tplInkC : 0;
        const thinOk: boolean = detectThinOne(sig, inkCount);
      g_lastPixelDiag = `ink=${inkCount} score=${best1Score} recall=${recall.toFixed(2)} thinOk=${thinOk ? 1 : 0} tp=${tp}/${tplInkC}`;
        if (best1Score >= lowInkMinScore && recall >= 0.25 && thinOk) {
          g_lastConfidence = 0.50;
          return 1;
        }
      }
    }
    if (best1Score >= lowInkMinScore && best1Key !== null) {
      const inkCentroid: number = inkCentroidRow(sig);
      let tSumR: number = 0;
      let tCnt: number = 0;
      for (let r: number = 0; r < SIG_ROWS; r++) {
        for (let c: number = 0; c < SIG_COLS; c++) {
          if (best1Key[r * SIG_COLS + c] === 1) { tSumR += r; tCnt++; }
        }
      }
      const tplCentroid: number = tCnt > 0 ? tSumR / tCnt : -1;
      if (Math.abs(inkCentroid - tplCentroid) <= SIG_ROWS * 0.4) {
        // Check if this might be 7 not 1: 7 has wide top bar with solid rows
        const topRow: number = Math.floor(SIG_ROWS * 0.10);
        const topEnd: number = Math.floor(SIG_ROWS * 0.30);
        let topMinC: number = SIG_COLS;
        let topMaxC: number = 0;
        for (let r: number = topRow; r < topEnd; r++) {
          for (let c: number = 0; c < SIG_COLS; c++) {
            if (sig[r * SIG_COLS + c] === 1) {
              if (c < topMinC) { topMinC = c; }
              if (c > topMaxC) { topMaxC = c; }
            }
          }
        }
        const topSpan: number = topMaxC >= topMinC ? topMaxC - topMinC + 1 : 0;
        if (topSpan >= SIG_COLS * 0.6) {
          let solidTopRows: number = 0;
          for (let r: number = topRow; r < topEnd; r++) {
            let inkInRow: number = 0;
            for (let c: number = 0; c < SIG_COLS; c++) {
              if (sig[r * SIG_COLS + c] === 1) { inkInRow++; }
            }
            if (inkInRow >= SIG_COLS * 0.5) { solidTopRows++; }
          }
          if (solidTopRows >= 2) {
            let best7Score: number = -100000;
            const tpls7: DigitTemplate[] = g_templatesByDigit[7];
            for (let ti2: number = 0; ti2 < tpls7.length; ti2++) {
              if (ti2 % 30 === 0) { await yieldThread(); }
              const t7: DigitTemplate = tpls7[ti2];
              if (!templateMatchesInkFilter(t7, inkCount)) { continue; }
              const kb7: Int8Array = t7.keyBytes;
              let tp7: number = 0;
              for (let j: number = 0; j < sigInkLen; j++) {
                if (kb7[sigInkPos[j]] === 1) { tp7++; }
              }
              const m7: number = SIG_LEN - sigInkLen - t7.inkCount + 2 * tp7;
              const s7: number = m7 - (SIG_LEN - m7) * TEMPLATE_MISMATCH_PENALTY;
              if (s7 > best7Score) { best7Score = s7; }
            }
            if (best7Score >= lowInkMinScore - 50) {
              if (best1Score > best7Score + 30) {
                g_lastPixelDiag = `lowInk7→1: s1=${best1Score}>s7=${best7Score}+30 topSpan=${topSpan} solidTop=${solidTopRows}`;
                const rawConf1: number = best1Score / (SIG_LEN + 200);
                g_lastConfidence = rawConf1 > 1 ? 1 : (rawConf1 < 0 ? 0 : rawConf1);
                return 1;
              }
              g_lastPixelDiag = `lowInk7-over-1: topSpan=${topSpan} solidTop=${solidTopRows} s7=${best7Score} s1=${best1Score}`;
              const rawConf7: number = best7Score / (SIG_LEN + 200);
              g_lastConfidence = rawConf7 > 1 ? 1 : (rawConf7 < 0 ? 0 : rawConf7);
              return 7;
            }
          }
        }
        const rawConf: number = best1Score / (SIG_LEN + 200);
        g_lastConfidence = rawConf > 1 ? 1 : (rawConf < 0 ? 0 : rawConf);
        let bestNon1ScoreLow: number = -100000;
        let bestNon1DigitLow: number = 0;
        for (let d: number = 2; d <= 9; d++) {
          const tplsN1: DigitTemplate[] = g_templatesByDigit[d];
          for (let tiN1: number = 0; tiN1 < tplsN1.length; tiN1++) {
            if (tiN1 % 30 === 0) { await yieldThread(); }
            const tN1: DigitTemplate = tplsN1[tiN1];
            if (!templateMatchesInkFilter(tN1, inkCount)) { continue; }
            const kbN1: Int8Array = tN1.keyBytes;
            let tpN1: number = 0;
            for (let jN1: number = 0; jN1 < sigInkLen; jN1++) {
              if (kbN1[sigInkPos[jN1]] === 1) { tpN1++; }
            }
            const mN1: number = SIG_LEN - sigInkLen - tN1.inkCount + 2 * tpN1;
            const rN1: number = tN1.inkCount > 0 ? tpN1 / tN1.inkCount : 0;
            const pN1: number = inkCount > 0 ? tpN1 / inkCount : 0;
            const fN1: number = (rN1 + pN1) > 0 ? (2 * rN1 * pN1) / (rN1 + pN1) : 0;
            const sN1: number = mN1 - (SIG_LEN - mN1) * TEMPLATE_MISMATCH_PENALTY + fN1 * TEMPLATE_F1_WEIGHT;
            if (sN1 > bestNon1ScoreLow) { bestNon1ScoreLow = sN1; bestNon1DigitLow = d; }
          }
        }
        if (bestNon1ScoreLow > best1Score + 50) {
          g_lastPixelDiag = `lowInk1→${bestNon1DigitLow}: s${bestNon1DigitLow}=${bestNon1ScoreLow.toFixed(0)} s1=${best1Score}`;
          const rawConfN1: number = bestNon1ScoreLow / (SIG_LEN + 200);
          g_lastConfidence = rawConfN1 > 1 ? 1 : (rawConfN1 < 0 ? 0 : rawConfN1);
          return bestNon1DigitLow;
        }
        return 1;
      }
    }
    if (best1Score >= geoMinScore && detectThinOne(sig, inkCount)) {
      g_lastConfidence = 0.55;
      return 1;
    }
    const digitBestScore: number[] = new Array<number>(10).fill(-100000);
    const digitBestIdx: number[] = new Array<number>(10).fill(-1);
    const digitBestRecall: number[] = new Array<number>(10).fill(0);
    for (let d: number = 2; d <= 9; d++) {
      const tplsD: DigitTemplate[] = g_templatesByDigit[d];
      for (let ti: number = 0; ti < tplsD.length; ti++) {
        if (ti % 30 === 0) { await yieldThread(); }
        const t: DigitTemplate = tplsD[ti];
        if (!templateMatchesInkFilter(t, inkCount)) { continue; }
        const kb: Int8Array = t.keyBytes;
        let tp: number = 0;
        for (let j: number = 0; j < sigInkLen; j++) {
          if (kb[sigInkPos[j]] === 1) { tp++; }
        }
        const match: number = SIG_LEN - sigInkLen - t.inkCount + 2 * tp;
        const recall: number = t.inkCount > 0 ? tp / t.inkCount : 0;
        const prec: number = inkCount > 0 ? tp / inkCount : 0;
        const f1: number = (recall + prec) > 0 ? (2 * recall * prec) / (recall + prec) : 0;
        const score: number = match - (SIG_LEN - match) * TEMPLATE_MISMATCH_PENALTY + f1 * TEMPLATE_F1_WEIGHT;
        if (score > digitBestScore[t.digit]) {
          digitBestScore[t.digit] = score;
          digitBestIdx[t.digit] = ti;
          digitBestRecall[t.digit] = recall;
        }
      }
    }
    let lowBestDigit: number = 0;
    let lowBestScore: number = -100000;
    let lowBestRecall: number = 0;
    for (let d: number = 2; d <= 9; d++) {
      if (digitBestScore[d] > lowBestScore) {
        lowBestDigit = d;
        lowBestScore = digitBestScore[d];
        lowBestRecall = digitBestRecall[d];
      }
    }
    const lowMinScore: number = LOW_INK_FALLBACK_MIN_SCORE;
    if (lowBestDigit > 0 && lowBestScore >= lowMinScore && lowBestRecall >= LOW_INK_FALLBACK_MIN_RECALL) {
      if (lowBestDigit === 4 && isLikelyNot4(sig)) {
        let best1Score2: number = -100000;
        const tpls1b: DigitTemplate[] = g_templatesByDigit[1];
        for (let ti: number = 0; ti < tpls1b.length; ti++) {
          if (ti % 30 === 0) { await yieldThread(); }
          const t: DigitTemplate = tpls1b[ti];
          if (!templateMatchesInkFilter(t, inkCount)) { continue; }
          const kb: Int8Array = t.keyBytes;
          let tp2: number = 0;
          for (let j: number = 0; j < sigInkLen; j++) {
            if (kb[sigInkPos[j]] === 1) { tp2++; }
          }
          const match2: number = SIG_LEN - sigInkLen - t.inkCount + 2 * tp2;
          const score: number = match2 - (SIG_LEN - match2) * TEMPLATE_MISMATCH_PENALTY;
          if (score > best1Score2) { best1Score2 = score; }
        }
        const geoGate1: number = Math.floor(SIG_LEN * 0.55);
        if (best1Score2 >= geoGate1) {
          g_lastPixelDiag = `not4→1: score1=${best1Score2} ink=${inkCount} sig=${sigToCompactStr(sig)}`;
          g_lastConfidence = 0.55;
          return 1;
        }
      }
      if (lowBestDigit === 4 || lowBestDigit === 7) {
        const stripResult: number = tryStripLeftEdgeAs1(sig, inkCount, lowBestDigit, lowBestScore);
        const stripDiag: string = g_lastPixelDiag;
        if (stripResult === 1) { return 1; }
        if (lowBestDigit === 7) {
          if (best1Score > digitBestScore[7] + 30) {
            g_lastPixelDiag = `lowInkFallback7→1: s1=${best1Score}>s7=${digitBestScore[7]}+30 ink=${inkCount}`;
            const rawConf1: number = best1Score / (SIG_LEN + 200);
            g_lastConfidence = rawConf1 > 1 ? 1 : (rawConf1 < 0 ? 0 : rawConf1);
            return 1;
          }
          const topRow7: number = Math.floor(SIG_ROWS * 0.05);
          const topEnd7: number = Math.floor(SIG_ROWS * 0.35);
          let topSolid7: number = 0;
          let topTotal7: number = 0;
          for (let r: number = topRow7; r < topEnd7; r++) {
            let inkInRow7: number = 0;
            for (let c: number = 0; c < SIG_COLS; c++) {
              if (sig[r * SIG_COLS + c] === 1) { inkInRow7++; }
            }
            topTotal7++;
            if (inkInRow7 >= SIG_COLS * 0.4) { topSolid7++; }
          }
          g_lastPixelDiag = `lowInk7check: s1=${best1Score} s7=${digitBestScore[7]} topSolid=${topSolid7}/${topTotal7} ink=${inkCount}`;
          if (topSolid7 === 0) {
            g_lastPixelDiag = `lowInkFallback7→1: noSolidTop ink=${inkCount} topSolid=${topSolid7}/${topTotal7}`;
            const rawConf1: number = best1Score / (SIG_LEN + 200);
            g_lastConfidence = rawConf1 > 1 ? 1 : (rawConf1 < 0 ? 0 : rawConf1);
            return 1;
          }
        }
        const sigDump: string = sigToCompactStr(sig);
        g_lastPixelDiag = `lowInk fallback: best=${lowBestDigit} score=${lowBestScore.toFixed(0)} recall=${lowBestRecall.toFixed(2)} gate=${lowMinScore} ink=${inkCount} [${stripDiag}] sig=${sigDump}`;
      } else {
        g_lastPixelDiag = `lowInk fallback: best=${lowBestDigit} score=${lowBestScore.toFixed(0)} recall=${lowBestRecall.toFixed(2)} gate=${lowMinScore} ink=${inkCount}`;
      }
      const rawConf: number = lowBestScore / (SIG_LEN + 200);
      g_lastConfidence = rawConf > 1 ? 1 : (rawConf < 0 ? 0 : rawConf);
      return lowBestDigit;
    }
    g_lastPixelDiag = `lowInk no1: best=${lowBestDigit} score=${lowBestScore.toFixed(0)} recall=${lowBestRecall.toFixed(2)} gate=${lowMinScore} ink=${inkCount}`;
    if (lowBestDigit === 4 && isLikelyNot4(sig)) {
      let best1Score4: number = -100000;
      const tpls1c: DigitTemplate[] = g_templatesByDigit[1];
      for (let ti: number = 0; ti < tpls1c.length; ti++) {
        if (ti % 30 === 0) { await yieldThread(); }
        const t: DigitTemplate = tpls1c[ti];
        if (!templateMatchesInkFilter(t, inkCount)) { continue; }
        const kb: Int8Array = t.keyBytes;
        let tp4: number = 0;
        for (let j: number = 0; j < sigInkLen; j++) {
          if (kb[sigInkPos[j]] === 1) { tp4++; }
        }
        const match4: number = SIG_LEN - sigInkLen - t.inkCount + 2 * tp4;
        const score: number = match4 - (SIG_LEN - match4) * TEMPLATE_MISMATCH_PENALTY;
        if (score > best1Score4) { best1Score4 = score; }
      }
      const geoGate3: number = Math.floor(SIG_LEN * 0.50);
      if (best1Score4 >= geoGate3) {
        g_lastPixelDiag = `not4→1(no1path): score1=${best1Score4} ink=${inkCount}`;
        g_lastConfidence = 0.50;
        return 1;
      }
    }
    g_lastConfidence = 0;
    return 0;
  }
  const qHole: number = holeCenterRow(sig);

  const sigCentroidRow: number = inkCentroidRow(sig);
  const sigCentroidCol2: number = inkCentroidCol(sig);
  const sigTopBottom: number = topBottomInkRatio(sig);
  const sigHasHole: boolean = qHole >= 0;
  const sigLeftRight: number = sigComputeLeftRightRatio(sig);

  const digitBestScore: number[] = new Array<number>(10).fill(-100000);
  const digitBestIdx: number[] = new Array<number>(10).fill(-1);
  for (let d: number = 1; d <= 9; d++) {
    const tplsD: DigitTemplate[] = g_templatesByDigit[d];
    for (let ti: number = 0; ti < tplsD.length; ti++) {
      if (ti % 30 === 0) { await yieldThread(); }
      const t: DigitTemplate = tplsD[ti];
      const kb: Int8Array = t.keyBytes;
      let tp: number = 0;
      for (let j: number = 0; j < sigInkLen; j++) {
        if (kb[sigInkPos[j]] === 1) { tp++; }
      }
      const match: number = SIG_LEN - sigInkLen - t.inkCount + 2 * tp;
      const recall: number = t.inkCount > 0 ? tp / t.inkCount : 0;
      const prec: number = inkCount > 0 ? tp / inkCount : 0;
      const f1: number = (recall + prec) > 0 ? (2 * recall * prec) / (recall + prec) : 0;
      const score: number = match - (SIG_LEN - match) * TEMPLATE_MISMATCH_PENALTY + f1 * TEMPLATE_F1_WEIGHT;
      if (score > digitBestScore[t.digit]) {
        digitBestScore[t.digit] = score;
        digitBestIdx[t.digit] = ti;
      }
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

  if (bestDigit === 1 && inkCount > 0) {
    const leftCol: number = Math.floor(SIG_COLS * 0.4);
    const midRow: number = Math.floor(SIG_ROWS * 0.35);
    let leftLowerInk: number = 0;
    for (let r2: number = midRow; r2 < SIG_ROWS; r2++) {
      for (let c2: number = 0; c2 < leftCol; c2++) {
        if (sig[r2 * SIG_COLS + c2] === 1) { leftLowerInk++; }
      }
    }
    if (leftLowerInk > inkCount * 0.18) {
      let bestNon1: number = 0;
      let bestNon1Score: number = -100000;
      for (let d: number = 2; d <= 9; d++) {
        if (digitBestScore[d] > bestNon1Score) { bestNon1Score = digitBestScore[d]; bestNon1 = d; }
      }
      if (bestNon1 > 0) {
        hilog.info(DOMAIN, TAG, 'digit1 left-lower-ink reject: lowerLeftInk=%{public}d/%{public}d(%.0f%%) => %{public}d',
          leftLowerInk, inkCount, leftLowerInk / inkCount * 100, bestNon1);
        bestDigit = bestNon1;
        bestScore = bestNon1Score;
        if (bestNon1 !== 7) { secondDigit = 7; secondScore = digitBestScore[7]; }
      }
    }
  }

  if (bestDigit === 1 && secondDigit === 7) {
    const topRow17: number = Math.floor(SIG_ROWS * 0.05);
    const topEnd17: number = Math.floor(SIG_ROWS * 0.30);
    let topMinC17: number = SIG_COLS;
    let topMaxC17: number = 0;
    let solidTopRows17: number = 0;
    for (let r: number = topRow17; r < topEnd17; r++) {
      let inkInRow17: number = 0;
      for (let c: number = 0; c < SIG_COLS; c++) {
        if (sig[r * SIG_COLS + c] === 1) {
          inkInRow17++;
          if (c < topMinC17) { topMinC17 = c; }
          if (c > topMaxC17) { topMaxC17 = c; }
        }
      }
      if (inkInRow17 >= SIG_COLS * 0.4) { solidTopRows17++; }
    }
    const topSpan17: number = topMaxC17 >= topMinC17 ? topMaxC17 - topMinC17 + 1 : 0;
    if (topSpan17 >= SIG_COLS * 0.55 && solidTopRows17 >= 1) {
      bestDigit = 7;
      bestScore = digitBestScore[7];
    }
  }

  const rawConf: number = bestScore / (SIG_LEN + 200);
  g_lastConfidence = rawConf > 1 ? 1 : (rawConf < 0 ? 0 : rawConf);

  if (bestDigit === 6 || bestDigit === 9) {
    const score6: number = digitBestScore[6];
    const score9: number = digitBestScore[9];
    const scoreGap: number = Math.abs(score6 - score9);

    if (scoreGap >= DISAMBIG_SCORE_GAP_SKIP) {
      const r69skip: number = score6 > score9 ? 6 : 9;
      g_lastPixelDiag = `69skip: s6=${score6.toFixed(0)} s9=${score9.toFixed(0)} gap=${scoreGap.toFixed(0)}>=${DISAMBIG_SCORE_GAP_SKIP} =>${r69skip}`;
      return r69skip;
    }

    const iCentroid: number = sigCentroidRow;
    const ratio: number = sigTopBottom;
    const hogGrad: number = hogVerticalGradient(sig);
    const swRatio: number = strokeWidthRatio(sig);

    hilog.info(DOMAIN, TAG, '6/9消歧: score6=%{public}.1f score9=%{public}.1f gap=%{public}.1f qHole=%{public}.2f centroid=%{public}.2f topRatio=%{public}.2f hogGrad=%{public}.2f swRatio=%{public}.2f',
      score6, score9, scoreGap, qHole, iCentroid, ratio, hogGrad, swRatio);

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
    if (score6 > score9 + 50) { vote6 += DISAMBIG_SCORE_WEIGHT; }
    else if (score9 > score6 + 50) { vote9 += DISAMBIG_SCORE_WEIGHT; }
    else if (score6 > score9) { vote6 += 1; }
    else { vote9 += 1; }

    const result69: number = vote6 === vote9 ? (score6 >= score9 ? 6 : 9) : (vote6 > vote9 ? 6 : 9);
    g_lastPixelDiag = `69disambig: s6=${score6.toFixed(0)} s9=${score9.toFixed(0)} gap=${scoreGap.toFixed(0)} hole=${qHole.toFixed(1)} cent=${iCentroid.toFixed(1)} ratio=${ratio.toFixed(2)} hog=${hogGrad.toFixed(2)} sw=${swRatio.toFixed(2)} v6=${vote6} v9=${vote9} =>${result69}`;
    hilog.info(DOMAIN, TAG, 'vote6=%{public}d vote9=%{public}d => %{public}d', vote6, vote9, result69);
    if (vote6 === vote9) { return score6 >= score9 ? 6 : 9; }
    return vote6 > vote9 ? 6 : 9;
  }

  // 5/6 disambiguation
  if (bestDigit === 5 || bestDigit === 6) {
    const score5: number = digitBestScore[5];
    const score6d: number = digitBestScore[6];
    const hole56: number = holeCenterRow(sig);
    if (hole56 >= 0 && hole56 > SIG_ROWS * 0.45) {
      return 6;
    }
    let topInkCols56: number = 0;
    let botInkCols56: number = 0;
    for (let c: number = 0; c < SIG_COLS; c++) {
      let topHas: boolean = false;
      let botHas: boolean = false;
      for (let r: number = 0; r < SIG_ROWS / 2; r++) {
        if (sig[r * SIG_COLS + c] === 1) { topHas = true; }
      }
      for (let r2: number = Math.floor(SIG_ROWS / 2); r2 < SIG_ROWS; r2++) {
        if (sig[r2 * SIG_COLS + c] === 1) { botHas = true; }
      }
      if (topHas) { topInkCols56++; }
      if (botHas) { botInkCols56++; }
    }
    if (botInkCols56 > topInkCols56 + 2) {
      return 6;
    }
    return score5 >= score6d ? 5 : 6;
  }

  // 5/9 disambiguation
  if (bestDigit === 5 || bestDigit === 9) {
    const score5b: number = digitBestScore[5];
    const score9b: number = digitBestScore[9];
    const hole59: number = holeCenterRow(sig);
    if (hole59 >= 0 && hole59 < SIG_ROWS * 0.45) {
      return 9;
    }
    const botRow59: number = Math.floor(SIG_ROWS * 0.7);
    const endRow59: number = Math.floor(SIG_ROWS * 0.9);
    let botLeftInk59: number = 0;
    let botRightInk59: number = 0;
    for (let r: number = botRow59; r < endRow59; r++) {
      for (let c: number = 0; c < SIG_COLS / 2; c++) {
        if (sig[r * SIG_COLS + c] === 1) { botLeftInk59++; }
      }
      for (let c2: number = Math.floor(SIG_COLS / 2); c2 < SIG_COLS; c2++) {
        if (sig[r * SIG_COLS + c2] === 1) { botRightInk59++; }
      }
    }
    if (botLeftInk59 > botRightInk59 * 1.5) {
      return 5;
    }
    const topInkRatio59: number = topBottomInkRatio(sig);
    if (topInkRatio59 > 0.55) {
      return 9;
    }
    return score5b >= score9b ? 5 : 9;
  }

  // 5/8 disambiguation (log117): 5 and 8 are topologically similar in small
  // images. Key discriminators: 8 has a hole (enclosed region) while 5 does
  // not; 8 has roughly equal left/right ink in the middle band, while 5's
  // middle band ink is left-skewed; 8 has roughly equal top/bottom ink, while
  // 5 has more bottom ink. Affects tests 18 (7→8, 3→8), 32 (8↔5 ×3).
  if (bestDigit === 5 || bestDigit === 8) {
    const score5c: number = digitBestScore[5];
    const score8c: number = digitBestScore[8];
    const hole58: number = holeCenterRow(sig);
    if (hole58 >= 0) {
      return 8;
    }
    const midTop58: number = Math.floor(SIG_ROWS * 0.3);
    const midBot58: number = Math.floor(SIG_ROWS * 0.7);
    let midLeftInk58: number = 0;
    let midRightInk58: number = 0;
    for (let r: number = midTop58; r < midBot58; r++) {
      for (let c: number = 0; c < SIG_COLS / 2; c++) {
        if (sig[r * SIG_COLS + c] === 1) { midLeftInk58++; }
      }
      for (let c2: number = Math.floor(SIG_COLS / 2); c2 < SIG_COLS; c2++) {
        if (sig[r * SIG_COLS + c2] === 1) { midRightInk58++; }
      }
    }
    const totalMid58: number = midLeftInk58 + midRightInk58;
    const leftMidRatio58: number = totalMid58 > 0 ? midLeftInk58 / totalMid58 : 0.5;
    if (leftMidRatio58 > 0.55) {
      return 5;
    }
    if (leftMidRatio58 < 0.48) {
      return 8;
    }
    return score5c >= score8c ? 5 : 8;
  }

  // 3/8 disambiguation
  if (bestDigit === 3 || bestDigit === 8) {
    const score3: number = digitBestScore[3];
    const score8: number = digitBestScore[8];
    const midTop38: number = Math.floor(SIG_ROWS * 0.3);
    const midBot38: number = Math.floor(SIG_ROWS * 0.7);
    let leftInk38: number = 0;
    let rightInk38: number = 0;
    for (let r: number = midTop38; r < midBot38; r++) {
      for (let c: number = 0; c < SIG_COLS / 2; c++) {
        if (sig[r * SIG_COLS + c] === 1) { leftInk38++; }
      }
      for (let c2: number = Math.floor(SIG_COLS / 2); c2 < SIG_COLS; c2++) {
        if (sig[r * SIG_COLS + c2] === 1) { rightInk38++; }
      }
    }
    const leftRatio38: number = (leftInk38 + rightInk38) > 0 ? leftInk38 / (leftInk38 + rightInk38) : 0.5;
    if (leftRatio38 > 0.30) {
      return 8;
    }
    return score3 >= score8 ? 3 : 8;
  }

  if (bestDigit === 2 || bestDigit === 8) {
    const score2: number = digitBestScore[2];
    const score8b: number = digitBestScore[8];
    const midTop28: number = Math.floor(SIG_ROWS * 0.3);
    const midBot28: number = Math.floor(SIG_ROWS * 0.7);
    let leftInk28: number = 0;
    let rightInk28: number = 0;
    for (let r: number = midTop28; r < midBot28; r++) {
      for (let c: number = 0; c < SIG_COLS / 2; c++) {
        if (sig[r * SIG_COLS + c] === 1) { leftInk28++; }
      }
      for (let c2: number = Math.floor(SIG_COLS / 2); c2 < SIG_COLS; c2++) {
        if (sig[r * SIG_COLS + c2] === 1) { rightInk28++; }
      }
    }
    const leftRatio28: number = (leftInk28 + rightInk28) > 0 ? leftInk28 / (leftInk28 + rightInk28) : 0.5;
    if (leftRatio28 > 0.28) {
      return 8;
    }
    return score2 >= score8b ? 2 : 8;
  }

  if (bestDigit === 4 || bestDigit === 5) {
    const score4: number = digitBestScore[4];
    const score5: number = digitBestScore[5];
    if (score4 > score5) {
      g_lastPixelDiag = `4/5→4: s4=${score4.toFixed(0)}>s5=${score5.toFixed(0)}`;
      return 4;
    }
    const topRow45: number = Math.floor(SIG_ROWS * 0.05);
    const topEnd45: number = Math.floor(SIG_ROWS * 0.30);
    let topSolidRows45: number = 0;
    for (let r: number = topRow45; r < topEnd45; r++) {
      let inkCols45: number = 0;
      for (let c: number = 0; c < SIG_COLS; c++) {
        if (sig[r * SIG_COLS + c] === 1) { inkCols45++; }
      }
      if (inkCols45 >= SIG_COLS * 0.6) { topSolidRows45++; }
    }
    if (topSolidRows45 >= 2) {
      g_lastPixelDiag = `4/5→5: topSolid=${topSolidRows45} s4=${score4.toFixed(0)} s5=${score5.toFixed(0)}`;
      return 5;
    }
    g_lastPixelDiag = `4/5→4: topSolid=${topSolidRows45} s4=${score4.toFixed(0)} s5=${score5.toFixed(0)}`;
    return 4;
  }

  // 1/4 disambiguation: Digit 1 with a serif or slanted top can be
  // misrecognized as 4. Key discriminator: 1 has a narrow vertical stroke
  // (avg row width ≤ ~6 pixels), while 4 has a wider cross-stroke structure
  // (avg row width > ~8). No score-gap gate: structural check is sufficient.
  if (bestDigit === 4) {
    const score4b: number = digitBestScore[4];
    const score1b: number = digitBestScore[1];
    if (score1b > 0) {
      const midTop14: number = Math.floor(SIG_ROWS * 0.25);
      const midBot14: number = Math.floor(SIG_ROWS * 0.75);
      let totalRowWidth14: number = 0;
      let rowCount14: number = 0;
      for (let r: number = midTop14; r < midBot14; r++) {
        let minC: number = SIG_COLS;
        let maxC: number = -1;
        for (let c: number = 0; c < SIG_COLS; c++) {
          if (sig[r * SIG_COLS + c] === 1) {
            if (c < minC) { minC = c; }
            if (c > maxC) { maxC = c; }
          }
        }
        if (maxC >= minC) { totalRowWidth14 += maxC - minC + 1; rowCount14++; }
      }
      const avgRowWidth14: number = rowCount14 > 0 ? totalRowWidth14 / rowCount14 : 0;
      // A narrow stroke (width ≤ 6) means this is likely 1, not 4
      if (avgRowWidth14 <= 6) {
        g_lastPixelDiag = `4→1: avgRowW=${avgRowWidth14.toFixed(1)} s4=${score4b} s1=${score1b}`;
        bestDigit = 1;
        bestScore = score1b;
      }
    }
  }

  // 4/6 disambiguation (log117): Digit 4 with thick strokes can be
  // misrecognized as 6. Key discriminator: 4 has no enclosed hole, 6 has one.
  // Also 6 has more ink in the bottom half, 4 has more in the top half.
  // Affects tests 23,29 (R8C4: got=6 want=4).
  if (bestDigit === 6) {
    const score6b: number = digitBestScore[6];
    const score4c: number = digitBestScore[4];
    if (score4c > 0) {
      const hole46: number = holeCenterRow(sig);
      if (hole46 < 0) {
        const topRatio46: number = topBottomInkRatio(sig);
        if (topRatio46 > 0.5) {
          g_lastPixelDiag = `6→4: noHole topRatio=${topRatio46.toFixed(2)} s6=${score6b} s4=${score4c}`;
          bestDigit = 4;
          bestScore = score4c;
        }
      }
    }
  }

  // 1/8 and 1/7 disambiguation (log117): A very faint digit can collapse
  // into a narrow vertical stroke after thresholding, causing misrecognition
  // as "1". Key discriminators:
  //   - 8 has ink on both left and right sides in the middle band; 1 is narrow
  //   - 7 has a wide top bar; 1 does not
  // Affects test 25 (R3C3: got=1 want=8; R9C8: got=1 want=7).
  if (bestDigit === 1) {
    const score1c: number = digitBestScore[1];
    const score8d: number = digitBestScore[8];
    const score7d: number = digitBestScore[7];
    const score6d: number = digitBestScore[6];
    if (score6d > 0 && score6d > score1c + 50) {
      const botRow16: number = Math.floor(SIG_ROWS * 0.6);
      const botEnd16: number = Math.floor(SIG_ROWS * 0.95);
      let botRowWidth16: number = 0;
      let botRowCount16: number = 0;
      for (let r: number = botRow16; r < botEnd16; r++) {
        let minC16: number = SIG_COLS;
        let maxC16: number = -1;
        for (let c: number = 0; c < SIG_COLS; c++) {
          if (sig[r * SIG_COLS + c] === 1) {
            if (c < minC16) { minC16 = c; }
            if (c > maxC16) { maxC16 = c; }
          }
        }
        if (maxC16 >= minC16) { botRowWidth16 += maxC16 - minC16 + 1; botRowCount16++; }
      }
      const avgBotWidth16: number = botRowCount16 > 0 ? botRowWidth16 / botRowCount16 : 0;
      if (avgBotWidth16 > SIG_COLS * 0.35) {
        g_lastPixelDiag = `1→6: avgBotW=${avgBotWidth16.toFixed(1)} s1=${score1c} s6=${score6d}`;
        bestDigit = 6;
        bestScore = score6d;
      }
    }
    const midTop1: number = Math.floor(SIG_ROWS * 0.3);
    const midBot1: number = Math.floor(SIG_ROWS * 0.7);
    let midLeft1: number = 0;
    let midRight1: number = 0;
    for (let r: number = midTop1; r < midBot1; r++) {
      for (let c: number = 0; c < SIG_COLS / 2; c++) {
        if (sig[r * SIG_COLS + c] === 1) { midLeft1++; }
      }
      for (let c2: number = Math.floor(SIG_COLS / 2); c2 < SIG_COLS; c2++) {
        if (sig[r * SIG_COLS + c2] === 1) { midRight1++; }
      }
    }
    const totalMid1: number = midLeft1 + midRight1;
    // Check 1→8: if middle band has balanced ink on both sides.
    // No score-gap gate: faint digits collapse to thin strokes that
    // score very high as "1" but structurally resemble 8 when ink is
    // distributed on both sides.
    if (score8d > 0 && totalMid1 > 0) {
      const leftRatio1: number = midLeft1 / totalMid1;
      if (leftRatio1 > 0.3 && leftRatio1 < 0.7 && midLeft1 > 3 && midRight1 > 3) {
        g_lastPixelDiag = `1→8: midL=${midLeft1} midR=${midRight1} lr=${leftRatio1.toFixed(2)} s1=${score1c} s8=${score8d}`;
        bestDigit = 8;
        bestScore = score8d;
      }
    }
    // Check 1→7: if top area has a wide horizontal bar.
    // No score-gap gate for the same reason as 1→8.
    if (bestDigit === 1 && score7d > 0) {
      const topRow1: number = Math.floor(SIG_ROWS * 0.05);
      const topEnd1: number = Math.floor(SIG_ROWS * 0.25);
      let topMinC1: number = SIG_COLS;
      let topMaxC1: number = 0;
      let solidTopRows1: number = 0;
      for (let r: number = topRow1; r < topEnd1; r++) {
        let inkInRow1: number = 0;
        let rMinC: number = SIG_COLS;
        let rMaxC: number = 0;
        for (let c: number = 0; c < SIG_COLS; c++) {
          if (sig[r * SIG_COLS + c] === 1) {
            inkInRow1++;
            if (c < rMinC) { rMinC = c; }
            if (c > rMaxC) { rMaxC = c; }
          }
        }
        if (inkInRow1 >= SIG_COLS * 0.4) { solidTopRows1++; }
        if (rMaxC >= rMinC) {
          if (rMinC < topMinC1) { topMinC1 = rMinC; }
          if (rMaxC > topMaxC1) { topMaxC1 = rMaxC; }
        }
      }
      const topSpan1: number = topMaxC1 >= topMinC1 ? topMaxC1 - topMinC1 + 1 : 0;
      if (topSpan1 >= SIG_COLS * 0.5 && solidTopRows1 >= 2) {
        g_lastPixelDiag = `1→7: topSpan=${topSpan1} solidTop=${solidTopRows1} s1=${score1c} s7=${score7d}`;
        bestDigit = 7;
        bestScore = score7d;
      }
    }
  }

  // 7/1 disambiguation: only check if 7 might actually be 1 (never flip 1→7)
  if (bestDigit === 7) {
    const score7: number = digitBestScore[7];
    const score1: number = digitBestScore[1];
    if (score1 > 0) {
      const midTop71: number = Math.floor(SIG_ROWS * 0.30);
      const midBot71: number = Math.floor(SIG_ROWS * 0.70);
      let totalRowWidth71: number = 0;
      let rowCount71: number = 0;
      for (let r: number = midTop71; r < midBot71; r++) {
        let minC: number = SIG_COLS;
        let maxC: number = -1;
        for (let c: number = 0; c < SIG_COLS; c++) {
          if (sig[r * SIG_COLS + c] === 1) {
            if (c < minC) { minC = c; }
            if (c > maxC) { maxC = c; }
          }
        }
        if (maxC >= minC) { totalRowWidth71 += maxC - minC + 1; rowCount71++; }
      }
      const avgRowWidth71: number = rowCount71 > 0 ? totalRowWidth71 / rowCount71 : 0;
      if (avgRowWidth71 > 8 && inkCount > 200) {
        g_lastPixelDiag = `7→1: avgRowW=${avgRowWidth71.toFixed(1)} ink=${inkCount} s7=${score7} s1=${score1}`;
        bestDigit = 1;
        bestScore = score1;
      }
    }
    if (bestDigit === 7) {
      const topRow71: number = Math.floor(SIG_ROWS * 0.10);
      const topEnd71: number = Math.floor(SIG_ROWS * 0.30);
      let topMinC71: number = SIG_COLS;
      let topMaxC71: number = 0;
      for (let r: number = topRow71; r < topEnd71; r++) {
        for (let c: number = 0; c < SIG_COLS; c++) {
          if (sig[r * SIG_COLS + c] === 1) {
            if (c < topMinC71) { topMinC71 = c; }
            if (c > topMaxC71) { topMaxC71 = c; }
          }
        }
      }
      const topSpan71: number = topMaxC71 >= topMinC71 ? topMaxC71 - topMinC71 + 1 : 0;
      if (topSpan71 >= SIG_COLS * 0.6) {
        let solidTopRows71: number = 0;
        for (let r: number = topRow71; r < topEnd71; r++) {
          let inkInRow71: number = 0;
          for (let c: number = 0; c < SIG_COLS; c++) {
            if (sig[r * SIG_COLS + c] === 1) { inkInRow71++; }
          }
          if (inkInRow71 >= SIG_COLS * 0.5) { solidTopRows71++; }
        }
        if (solidTopRows71 >= 2 && score7 >= score1) {
          return 7;
        }
        if (solidTopRows71 >= 2 && score1 > score7) {
          g_lastPixelDiag = `7→1: solidTop=${solidTopRows71} but s1=${score1}>s7=${score7} topSpan=${topSpan71}`;
          return 1;
        }
      }
      // No solid top bar + score very close → might be 1 not 7
      const botRow71: number = Math.floor(SIG_ROWS * 0.60);
      const botEnd71: number = Math.floor(SIG_ROWS * 0.85);
      let botMinC71: number = SIG_COLS;
      let botMaxC71: number = 0;
      for (let r: number = botRow71; r < botEnd71; r++) {
        for (let c: number = 0; c < SIG_COLS; c++) {
          if (sig[r * SIG_COLS + c] === 1) {
            if (c < botMinC71) { botMinC71 = c; }
            if (c > botMaxC71) { botMaxC71 = c; }
          }
        }
      }
      const botSpan71: number = botMaxC71 >= botMinC71 ? botMaxC71 - botMinC71 + 1 : 0;
      if (botSpan71 <= 6 && topSpan71 < SIG_COLS * 0.6) {
        g_lastPixelDiag = `7→1: botSpan=${botSpan71} topSpan=${topSpan71} s7=${score7} s1=${score1}`;
        return 1;
      }
    }
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

  if (bestScore >= MIN_DIGIT_SCORE) {
    if (bestDigit === 4 && isLikelyNot4(sig)) {
      let best1Score3: number = -100000;
      const tpls1d: DigitTemplate[] = g_templatesByDigit[1];
      for (let ti: number = 0; ti < tpls1d.length; ti++) {
        if (ti % 30 === 0) { await yieldThread(); }
        const t: DigitTemplate = tpls1d[ti];
        if (!templateMatchesInkFilter(t, inkCount)) { continue; }
        const kb: Int8Array = t.keyBytes;
        let tp3: number = 0;
        for (let j: number = 0; j < sigInkLen; j++) {
          if (kb[sigInkPos[j]] === 1) { tp3++; }
        }
        const match3: number = SIG_LEN - sigInkLen - t.inkCount + 2 * tp3;
        const score: number = match3 - (SIG_LEN - match3) * TEMPLATE_MISMATCH_PENALTY;
        if (score > best1Score3) { best1Score3 = score; }
      }
      const geoGate2: number = Math.floor(SIG_LEN * 0.55);
      if (best1Score3 >= geoGate2) {
        g_lastPixelDiag = `not4→1: score1=${best1Score3} ink=${inkCount} sig=${sigToCompactStr(sig)}`;
        g_lastConfidence = 0.55;
        return 1;
      }
    }
    if (bestDigit === 4 || bestDigit === 7) {
      const stripResult: number = tryStripLeftEdgeAs1(sig, inkCount, bestDigit, bestScore);
      const stripDiag: string = g_lastPixelDiag;
      if (stripResult === 1) { return 1; }
      g_lastPixelDiag = `best=${bestDigit} score=${bestScore.toFixed(0)} ink=${inkCount} [${stripDiag}] sig=${sigToCompactStr(sig)}`;
    } else {
      g_lastPixelDiag = `best=${bestDigit} score=${bestScore.toFixed(0)} ink=${inkCount}`;
    }
    return bestDigit;
  }
  g_lastPixelDiag = `bestDigit=${bestDigit} bestScore=${bestScore.toFixed(0)} second=${secondDigit}(${secondScore.toFixed(0)}) minGate=${MIN_DIGIT_SCORE} ink=${inkCount}`;
  return 0;
}

export function getLastConfidence(): number {
  return g_lastConfidence;
}

export interface DigitResult {
  digit: number;
  confidence: number;
}

export async function recognizeDigitWithConfidence(sig: number[], inkCount: number): Promise<DigitResult> {
  const digit: number = await recognizeDigit(sig, inkCount);
  const result: DigitResult = { digit, confidence: g_lastConfidence };
  return result;
}

// findPreciseGridLines (log117): Replaced old single-scan approach with
// per-band search: each grid line scans a ±30% cell-width band to find the
// column/row with maximum ink, falling back to the approximate position if
// ink is below PRECISE_GRID_MIN_INK_FRAC. Added spacing consistency check
// (GRID_MAX_SPACING_DEV=0.25): if any line spacing deviates >25% from the
// expected cell size, the entire result is rejected (returns null), falling
// back to uniform grid positions. This prevents jagged/wrong grid lines from
// producing garbled digit signatures, especially in thick-lined boards.
export function findPreciseGridLines(
  gray: Float32Array, width: number, height: number, bbox: BoardBBox, bg: number
): GridLines | null {
  const isDark: boolean = bbox.isDark;
  const boardL: number = bbox.left;
  const boardT: number = bbox.top;
  const boardR: number = bbox.right;
  const boardB: number = bbox.bottom;
  const boardW: number = boardR - boardL;
  const boardH: number = boardB - boardT;
  if (boardW < CONSERVATIVE_MIN_DIM || boardH < CONSERVATIVE_MIN_DIM) { return null; }

  const cellW: number = boardW / 9;
  const cellH: number = boardH / 9;
  const PRECISE_GRID_MIN_INK_FRAC: number = 0.15;

  const vLines: number[] = new Array<number>(10).fill(0);
  for (let i: number = 0; i < 10; i++) {
    const approxX: number = Math.round(boardL + i * cellW);
    const bandHalf: number = Math.max(3, Math.floor(cellW * 0.3));
    const x0: number = Math.max(0, approxX - bandHalf);
    const x1: number = Math.min(width - 1, approxX + bandHalf);
    const innerY0: number = Math.floor(boardT + cellH * 0.2);
    const innerY1: number = Math.floor(boardB - cellH * 0.2);
    const spanLen: number = innerY1 - innerY0 + 1;
    let bestX: number = approxX;
    let bestInk: number = 0;
    for (let x: number = x0; x <= x1; x++) {
      let ic: number = 0;
      for (let y: number = innerY0; y <= innerY1; y++) {
        if (y < 0 || y >= height) { continue; }
        if (grayInkPixel(gray[y * width + x], bg, isDark, INK_THRESH)) { ic++; }
      }
      if (ic > bestInk) { bestInk = ic; bestX = x; }
    }
    vLines[i] = (bestInk >= spanLen * PRECISE_GRID_MIN_INK_FRAC) ? bestX : approxX;
  }

  const hLines: number[] = new Array<number>(10).fill(0);
  for (let i: number = 0; i < 10; i++) {
    const approxY: number = Math.round(boardT + i * cellH);
    const bandHalf: number = Math.max(3, Math.floor(cellH * 0.3));
    const y0: number = Math.max(0, approxY - bandHalf);
    const y1: number = Math.min(height - 1, approxY + bandHalf);
    const innerX0: number = Math.floor(boardL + cellW * 0.2);
    const innerX1: number = Math.floor(boardR - cellW * 0.2);
    const spanLen: number = innerX1 - innerX0 + 1;
    let bestY: number = approxY;
    let bestInk: number = 0;
    for (let y: number = y0; y <= y1; y++) {
      let ic: number = 0;
      for (let x: number = innerX0; x <= innerX1; x++) {
        if (x < 0 || x >= width) { continue; }
        if (grayInkPixel(gray[y * width + x], bg, isDark, INK_THRESH)) { ic++; }
      }
      if (ic > bestInk) { bestInk = ic; bestY = y; }
    }
    hLines[i] = (bestInk >= spanLen * PRECISE_GRID_MIN_INK_FRAC) ? bestY : approxY;
  }

  let foundLine: boolean = false;
  for (let i: number = 0; i < 10; i++) {
    if (vLines[i] !== Math.round(boardL + i * cellW) || hLines[i] !== Math.round(boardT + i * cellH)) {
      foundLine = true;
      break;
    }
  }
  if (!foundLine) { return null; }

  const GRID_MAX_SPACING_DEV: number = 0.25;
  let vOk: boolean = true;
  for (let i: number = 1; i < 10; i++) {
    const sp: number = vLines[i] - vLines[i - 1];
    if (Math.abs(sp - cellW) / cellW > GRID_MAX_SPACING_DEV) { vOk = false; break; }
  }
  let hOk: boolean = true;
  for (let i: number = 1; i < 10; i++) {
    const sp: number = hLines[i] - hLines[i - 1];
    if (Math.abs(sp - cellH) / cellH > GRID_MAX_SPACING_DEV) { hOk = false; break; }
  }
  if (!vOk || !hOk) { return null; }

  const result: GridLines = { hLines: hLines, vLines: vLines };
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
  const inkBg: number = isDark ? bg + INK_THRESH : bg - INK_THRESH;

  for (let y: number = y0; y < y1; y++) {
    for (let x: number = x0; x < x1; x++) {
      if (y < 0 || y >= height || x < 0 || x >= width) { continue; }
      const g: number = gray[y * width + x];
      if (isDark ? g > inkBg : g < inkBg) {
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
