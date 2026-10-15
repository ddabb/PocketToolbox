export const DOMAIN: number = 0xA03D00;
export const TAG: string = 'SudokuPixel';

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


export interface GridLines {
  hLines: number[];
  vLines: number[];
}

export const SIG_ROWS: number = 28;

export const SIG_COLS: number = 20;
export const SIG_LEN: number = SIG_ROWS * SIG_COLS;

// --- Tunable constants for pixel-level digit recognition ---

// Ink ratio bounds: a valid digit signature must have ink ratio between
// MIN_INK_RATIO and MAX_INK_RATIO. Too little ink = noise; too much = smudge.
export const MIN_INK_RATIO: number = 0.25;
export const MAX_INK_RATIO: number = 0.75;
export const MIN_INK_COUNT: number = Math.floor(SIG_LEN * MIN_INK_RATIO);
export const MAX_INK_COUNT: number = Math.floor(SIG_LEN * MAX_INK_RATIO);
// Ink count boundary between "very thin" and "normal low ink" in the lowInk
// path of recognizeDigit. When inkCount is in [THIN1_MIN_INK_COUNT, this value),
// the detectThinOne fallback requires a stricter template-score gate
// (lowInkMinScore = 0.70×SIG_LEN) to avoid false positives on noise.
export const MIN_INK_COUNT_DIGIT1: number = Math.floor(SIG_LEN * 0.12);

// Absolute minimum ink count for recognizeDigit entry gate. Below this, the
// signature is treated as empty/noise and returns 0 immediately. Above this
// but below MIN_INK_COUNT_DIGIT1, only thin-"1" detection is attempted with a
// strict triple-gate (high template score + template recall + detectThinOne geometry).
// Also serves as the internal lower bound inside detectThinOne() itself.
export const THIN1_MIN_INK_COUNT: number = Math.floor(SIG_LEN * 0.06);

// Minimum template-match score (out of SIG_LEN) for a digit to be accepted.
// SIG_LEN * 0.65 ≈ 364 of 560 pixels must match template.
export const MIN_DIGIT_SCORE: number = Math.floor(SIG_LEN * 0.65);

// When inkCount is in the "low ink" range [MIN_INK_COUNT_DIGIT1, MIN_INK_COUNT),
// the primary path only matches digit "1". If that fails, we fall back to matching
// digits 2-9 with this score gate. Lower than MIN_DIGIT_SCORE (0.65) because
// low-ink signatures have fewer ink pixels to match, but must still be strict
// enough to reject noise and grid-line fragments. 0.60 ≈ 336 of 560 pixels.
export const LOW_INK_FALLBACK_MIN_SCORE: number = Math.floor(SIG_LEN * 0.60);

// Minimum recall (fraction of template ink pixels present in the signature)
// for low-ink fallback matches. Prevents partial matches where a few ink pixels
// happen to overlap a template by chance.
export const LOW_INK_FALLBACK_MIN_RECALL: number = 0.35;

// Ink detection threshold: a pixel is "ink" if its gray value differs from
// the background by at least INK_THRESH. Lower = more sensitive to faint ink;
// higher = more selective, avoids noise.
export const INK_THRESH: number = 50;
export const GRID_LINE_GRAY_DIFF: number = INK_THRESH * 0.6;

// Sauvola adaptive thresholding parameters:
//   k controls sensitivity to local variance (0.2 = moderate).
//   R is the dynamic range of standard deviation (128 for 8-bit images).
export const SAUVOLA_K: number = 0.2;
export const SAUVOLA_R: number = 128;

// Cell margin: when extracting a cell signature, skip the outer 8% of cell
// width/height on each side to avoid grid-line pixels bleeding in.
export const CELL_MARGIN_RATIO: number = 0.08;

// Minimum ink ratio (relative to cell area) for a cell to be considered
// occupied. Cells with ink ratio below this are treated as empty.
// Originally 0.025; lowered to 0.018 (log117) to catch very thin "1" digits
// whose ink ratio was ~0.022. This fixed digit-1 missing errors in tests
// 18,22,24,25 (log116→117: 22 FAIL→PASS, 24 FAIL→PASS, 25: 7→2 errors).
// 0.018 is still above noise floor (~0.005) so no false-positive regression.
export const MIN_CELL_INK_RATIO: number = 0.018;

// Otsu fallback: reject the Otsu threshold if it is too close to the
// background value (within OTSU_BG_MIN_DIFF gray levels).
export const OTSU_BG_MIN_DIFF: number = 12;

// Otsu fallback: minimum number of pixels in the bounding box to compute
// a meaningful Otsu threshold.
export const OTSU_MIN_PIXELS: number = 30;

// Background color sampling: use at most BG_SAMPLE_COUNT pixels (sampled
// uniformly) to build the histogram. Prevents slow histogram on large images.
export const BG_SAMPLE_COUNT: number = 20000;

// Board detection: minimum dimension (px) for a detected bounding box
// to be considered valid. Smaller regions are ignored.
export const MIN_BOARD_DIM: number = 10;

// Board detection: reject bounding boxes whose aspect ratio is outside
// [MIN_BOARD_ASPECT, MAX_BOARD_ASPECT]. A valid Sudoku board is roughly square.
export const MIN_BOARD_ASPECT: number = 0.3;
export const MAX_BOARD_ASPECT: number = 3.0;

// Board detection: reject bounding boxes whose area exceeds this fraction
// of the total image area (likely a degenerate full-image detection).
export const MAX_BOARD_AREA_RATIO: number = 0.88;

// Board detection: reject bounding boxes whose area is below this fraction
// of the total image area (likely noise or a tiny artifact).
export const MIN_BOARD_AREA_RATIO: number = 0.02;

// Board detection: minimum board dimension as fraction of image dimension
// for the board to be considered valid.
export const MIN_BOARD_SIZE_FRAC: number = 0.1;

// findBBoxAdaptive: contrast offsets tried when binarizing the image.
// Larger values = stricter threshold = cleaner but possibly incomplete binary.
export const ADAPTIVE_CONTRASTS: number[] = [8, 12, 5];

// findBBoxAdaptive: projection fraction thresholds tried to find ink regions.
export const ADAPTIVE_THRESHOLDS: number[] = [0.3, 0.25, 0.20, 0.15];

// findBBoxAdaptive: peak detection threshold for periodic grid-line analysis.
export const ADAPTIVE_PEAK_THRESH: number = 0.10;

// findBBoxConservative: delta offsets tried for global-threshold binarization.
// Starts strict (delta=90) and relaxes progressively.
export const CONSERVATIVE_DELTAS: number[] = [90, 80, 70, 60, 50, 40];

// findBBoxConservative: peak detection threshold for periodic grid-line analysis.
export const CONSERVATIVE_PEAK_THRESH: number = 0.05;

// findBBoxConservative: minimum peak count to consider a valid grid.
export const CONSERVATIVE_MIN_PEAKS: number = 7;

// findBBoxConservative: aspect ratio bounds for a valid board.
export const CONSERVATIVE_MIN_ASPECT: number = 0.45;
export const CONSERVATIVE_MAX_ASPECT: number = 2.2;

// findBBoxConservative: minimum board dimension in pixels.
export const CONSERVATIVE_MIN_DIM: number = 20;

// findBoxLongRun: minimum run length (px) for a horizontal/vertical stroke
// to be considered a grid line. Shorter runs are likely noise (wood grain, etc).
// Computed as max(20, imageMinDim * 0.10).
export const MINRUN_ABS_MIN: number = 20;
export const MINRUN_FRAC: number = 0.10;

// findBoxLongRun: when the default threshold (bg ± 60) produces too many ink pixels
// (areaRatio > MAX_BOARD_AREA_RATIO), retry with progressively tighter offsets.
// Each offset is subtracted from bg (light-mode) or added to bg (dark-mode) to
// produce the binary ink threshold. Grid lines are significantly darker/lighter
// than background textures, so a tighter offset filters out faint wood grain,
// shadows, and other background noise while preserving the actual grid strokes.
export const LONGRUN_TIGHTER_OFFSETS: number[] = [40, 25, 12];

// findBoxLongRun: minimum number of kept pixels for a valid board detection.
export const LONGRUN_MIN_PIXELS: number = 50;

// findBoxLongRun: reject thresholds that generate too many long runs. In photos,
// wood grain and shadows can create thousands of long horizontal/vertical runs;
// a real Sudoku grid has only tens of long runs even after resizing.
export const LONGRUN_MAX_RUN_COUNT_FRAC: number = 0.50;

// findBoxLongRun: aspect ratio bounds for a valid board. Portrait photos can
// compress the board vertically, but aspect≈0.51 in logs29 selected only the
// left half of photos.jpg and shifted all cells, while the good photo bbox was
// still about 0.69. Keep a stricter floor for long-run candidates.
export const LONGRUN_MIN_ASPECT: number = 0.6;
export const LONGRUN_MAX_ASPECT: number = 2.0;

// findBoxLongRun lattice fitting: when raw long-run extents are polluted by
// table shadows / paper edges outside the grid (photos), fit an equal-spacing
// lattice (9 cells, 10 lines) to the clustered run lines of each axis. If both
// axes yield a confident lattice, the bbox is built from lattice phase +
// spacing (expanded by median half line thickness) instead of raw extents.
export const LATTICE_MIN_LINES: number = 7;
export const LATTICE_CELLS: number = 9;
export const LATTICE_CLUSTER_GAP: number = 2;
export const LATTICE_MAX_MISSES: number = 2;
export const LATTICE_TOL_FRAC: number = 0.22;
export const LATTICE_STEP_TOL_FRAC: number = 0.15;
// fitLattice: scan range for candidate cell spacing, as fractions of the
// smaller work-image dimension (board cell = boardDim/9, board between ~28%
// and ~112% of min dim).
export const LATTICE_S_MIN_DIV: number = 32;
export const LATTICE_S_MAX_DIV: number = 8;

// findBoxLongRun cascade: a raw-extent bbox whose aspect is inside this range
// is trusted and returned immediately (confidently square board); outside it
// the bbox is only kept as fallback and the cascade keeps scanning remaining
// thresholds for a lattice fit, because table shadows / paper edges stretch
// one axis of the raw extents (e.g. photos.jpg raw aspect 0.67).
export const LONGRAW_CONFIDENT_ASPECT_MIN: number = 0.72;
export const LONGRAW_CONFIDENT_ASPECT_MAX: number = 1.39;

// Hough transform: edge magnitude threshold. Pixels with gradient below
// this are skipped during voting.
export const HOUGH_EDGE_THRESH: number = 30;

// Hough transform: number of theta (angle) bins in the accumulator.
export const HOUGH_THETA_STEPS: number = 180;

// Hough transform: maximum pixels to sample for voting (performance control).
export const HOUGH_MAX_SAMPLES: number = 50000;

// Hough transform: minimum votes for a line to be considered.
export const HOUGH_MIN_VOTES_DIVISOR: number = 50;

// Hough transform: non-maximum suppression rho radius.
export const HOUGH_NMS_RHO_DIVISOR: number = 40;

// Hough transform: non-maximum suppression theta radius (bins).
export const HOUGH_NMS_THETA_RADIUS: number = 3;

// Hough transform: maximum number of lines returned after NMS.
export const HOUGH_MAX_LINES: number = 60;

// Hough line angle tolerance (radians) for clustering lines as horizontal/vertical.
export const HOUGH_ANGLE_TOLERANCE: number = Math.PI / 18;

// Board corner detection: minimum number of Hough lines required.
export const CORNER_MIN_LINES: number = 8;

// Board corner detection: maximum number of candidate lines per side used
// for intersection computation.
export const CORNER_MAX_SIDE_LINES: number = 5;

// Board corner detection: minimum board size as fraction of image dimension.
export const CORNER_MIN_SIZE_FRAC: number = 0.08;

// Board corner detection: diagonal ratio bounds (prevents degenerate quadrilaterals).
export const CORNER_MIN_DIAG_RATIO: number = 0.5;
export const CORNER_MAX_DIAG_RATIO: number = 2.0;

// Board corner detection: confidence = min(horizCount, vertCount) / CORNER_CONFIDENCE_DIV.
export const CORNER_CONFIDENCE_DIV: number = 10;

// Board corner detection: how far outside the image a corner can be (as fraction of dimension).
export const CORNER_OUT_OF_BOUNDS_FRAC: number = 0.1;

// validateCellCentering: margin to exclude from centroid computation (as fraction of cell size).
export const CENTERING_MARGIN: number = 0.15;

// validateCellCentering: minimum ink pixels needed to judge centering.
export const CENTERING_MIN_INK: number = 5;

// validateCellCentering: maximum centroid offset (as fraction of cell size) for valid centering.
export const CENTERING_MAX_OFFSET: number = 0.25;

// Hough line detection (findBoardByHoughLines): minimum number of horizontal
// and vertical lines required for board detection.
export const HOUGH_BOARD_MIN_HORIZ: number = 4;
export const HOUGH_BOARD_MIN_VERT: number = 4;

// findPeriodicPeaks: minimum number of peaks for a valid periodic pattern.
export const PERIODIC_MIN_PEAKS: number = 5;

// findPreciseGridLines: smoothing window radius as fraction of profile length.
export const GRID_LINE_SMOOTH_DIV: number = 60;

// findPreciseGridLines: minimum max-ink-fraction for profile to be usable.
export const GRID_LINE_MIN_MAX_FRAC: number = 0.05;

// detectGridLineWidths: minimum ink percentage in a row/column scan to confirm a thick grid line.
export const GRID_LINE_INK_EXIST_THRESH: number = 0.15;

// findPreciseGridLines: peak threshold as fraction of smoothed max.
export const GRID_LINE_PEAK_THRESH_FRAC: number = 0.3;

// findPreciseGridLines: spacing tolerance as fraction of ideal spacing.
export const GRID_LINE_SPACING_TOLERANCE: number = 0.3;

// Recognize digit 6/9 disambiguation voting weights.
export const DISAMBIG_HOLE_WEIGHT: number = 2;
export const DISAMBIG_CENTROID_WEIGHT: number = 1;
export const DISAMBIG_TOP_RATIO_WEIGHT: number = 2;
export const DISAMBIG_HOG_WEIGHT: number = 1;
export const DISAMBIG_SW_WEIGHT: number = 1;
export const DISAMBIG_SCORE_WEIGHT: number = 4;

export const DISAMBIG_SCORE_GAP_SKIP: number = 80;

// Recognize digit: template scoring formula penalty multiplier for mismatches.
export const TEMPLATE_MISMATCH_PENALTY: number = 0.5;

// Recognize digit: F1 score weight in template scoring formula.
export const TEMPLATE_F1_WEIGHT: number = 500;

// findBoardBBox: projection ink-fraction thresholds for primary detection.
export const BBOX_PRIMARY_THRESH: number = 0.3;
export const BBOX_PRIMARY_MIN_FRAC: number = 0.3;

// findBoardBBox: relaxed thresholds tried when primary fails.
export const BBOX_RELAXED_THRESHOLDS: number[] = [0.20, 0.15];
export const BBOX_RELAXED_MIN_FRAC: number = 0.15;

// findBoardBBox: sub-region search thresholds.
export const BBOX_REGION_THRESHOLDS: number[] = [0.30, 0.20, 0.15];
export const BBOX_REGION_MIN_FRAC: number = 0.10;

// findBoardBBox: sub-region definitions (as fractions of image dimensions).
export const BBOX_REGIONS: number[][] = [
  [0, 0, 0.6, 0.6],
  [0.4, 0, 1.0, 0.6],
  [0, 0.4, 0.6, 1.0],
  [0.4, 0.4, 1.0, 1.0],
  [0.15, 0.15, 0.85, 0.85],
];

// findBoardBBox: extra regions for portrait images (height > width * 1.3).
export const BBOX_PORTRAIT_REGIONS: number[][] = [
  [0, 0, 1.0, 0.5],
  [0, 0.1, 1.0, 0.6],
  [0.1, 0, 0.9, 0.45],
];

// findBoardBBox: extra regions for landscape images (width > height * 1.3).
export const BBOX_LANDSCAPE_REGIONS: number[][] = [
  [0, 0, 0.5, 1.0],
  [0.1, 0, 0.6, 1.0],
  [0, 0.1, 0.45, 0.9],
];

// findBoardBBox: aspect ratio for triggering portrait/landscape extra regions.
export const PORTRAIT_ASPECT_THRESHOLD: number = 1.3;

// Sauvola threshold: minimum cell dimension for computing adaptive threshold.
export const SAUVOLA_MIN_DIM: number = 4;

// Background sampling step divisor for warped image background estimation.
export const WARP_BG_SAMPLE_DIV: number = 20000;

// Hole detection: reject if second-largest hole component > this fraction of largest.
export const HOLE_SECOND_RATIO: number = 0.6;

// Background brightness threshold: if bgColor < 128, treat image as dark-mode
// (light ink on dark background), otherwise dark ink on light background.
export const BG_DARK_THRESHOLD: number = 128;


export const ADAPTIVE_MAX_DIM: number = 400;

export class SudokuPixelState {
  templates: DigitTemplate[] = [];
  templatesByDigit: DigitTemplate[][] = [];
  holeRows: number[] = [];
  loaded: boolean = false;
  gridLineCropTop: number[] = new Array<number>(81).fill(0);
  gridLineCropBot: number[] = new Array<number>(81).fill(0);
  gridLineCropLeft: number[] = new Array<number>(81).fill(0);
  gridLineCropRight: number[] = new Array<number>(81).fill(0);
  gridLineDetected: boolean = false;
  lastConfidence: number = 0;
  lastBboxDiag: string = '';
  lastPixelDiag: string = '';
  lastRawInkRatio: number = 0;
  lastLocalBgInfo: string = '';
  lastSigMetrics: string = '';
  lastSigQualityFail: boolean = false;
  lastSigCompCount: number = 0;
  lastSigLrgRatio: number = 0;
  lastSigHoles: number = 0;
  lastSigInk: number = 0;
  lastLocalBgPeak: number = 255;
}

export const SP: SudokuPixelState = new SudokuPixelState();

export function getLastBboxDiag(): string {
  return SP.lastBboxDiag;
}

export function getLastPixelDiag(): string {
  return SP.lastPixelDiag;
}

export function getLastSigMetrics(): string {
  return SP.lastSigMetrics;
}

export function getLastSigQualityFail(): boolean {
  return SP.lastSigQualityFail;
}

export function getLastSigCompCount(): number {
  return SP.lastSigCompCount;
}

export function getLastSigLrgRatio(): number {
  return SP.lastSigLrgRatio;
}

export function getLastSigHoles(): number {
  return SP.lastSigHoles;
}

export function getLastSigInk(): number {
  return SP.lastSigInk;
}

export function getLastLocalBgPeak(): number {
  return SP.lastLocalBgPeak;
}

export function getLastRawInkRatio(): number {
  return SP.lastRawInkRatio;
}

export function getLastLocalBgInfo(): string {
  return SP.lastLocalBgInfo;
}

export function resetLastPixelDiag(): void {
  SP.lastPixelDiag = '';
  SP.lastRawInkRatio = 0;
  SP.lastLocalBgInfo = '';
  SP.lastLocalBgPeak = 255;
}

export function resetGridLineCrop(): void {
  SP.gridLineCropTop = new Array<number>(81).fill(0);
  SP.gridLineCropBot = new Array<number>(81).fill(0);
  SP.gridLineCropLeft = new Array<number>(81).fill(0);
  SP.gridLineCropRight = new Array<number>(81).fill(0);
  SP.gridLineDetected = false;
}

export function isGridLineCropDetected(): boolean {
  return SP.gridLineDetected;
}
