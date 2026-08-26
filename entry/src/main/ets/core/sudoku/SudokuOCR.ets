import { image } from '@kit.ImageKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { fileIo } from '@kit.CoreFileKit';
import { parseOCRToGrid } from './SudokuEngine';
 import { BoardBBox, BoardCorners, GridLines, bgColor, cellSigFromGray, cellSigFromGrayLowThresh, cellSigFromGrayThin, countInk, detectBoardCorners, detectGridLineWidths, findBoardBBox, findBoxLongRun, getLastBboxDiag, getLastPixelDiag, getLastRawInkRatio, MIN_CELL_INK_RATIO, resetChannelBgCache, resetGridLineCrop, resetLastPixelDiag, isGridLineCropDetected, findPreciseGridLines, getLastConfidence, recognizeDigit, SIG_COLS, SIG_ROWS, toGrayArray, validateCellCentering, warpPerspectiveGray, INK_THRESH } from './SudokuPixel';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xA03D00;
const TAG: string = 'SudokuOCR';
let g_lastRecognizeDiag: string = '';

// --- Tunable constants for OCR pipeline (extracted for easier debugging) ---

// Target pixels per cell when scaling the image for VisionKit OCR.
// Larger values improve OCR accuracy at the cost of performance.
// Previously 56; raised to 100 to fix sparse-grid misrecognition.
const TARGET_CELL_PX: number = 100;

// Maximum dimension (px) for the image sent to VisionKit after scaling.
// Prevents excessive memory use on very high-res photos.
const OCR_MAX_DIM: number = 4096;

// Minimum dimension (px) for the image sent to VisionKit.
// Ensures digits are large enough for reliable recognition.
const OCR_MIN_DIM: number = 360;

// Fraction of board width/height to add as padding when cropping the board
// region for VisionKit OCR. 0.10 = 10% padding on each side.
// Raised from 0.05 to avoid clipping edge digits.
const BOARD_CROP_PAD_RATIO: number = 0.10;

// Fraction of cell width/height to add as padding when cropping individual
// cells for per-cell VisionKit re-recognition in fixAndFillGrid.
const CELL_CROP_PAD_FACTOR: number = 0.50;

// Upscale factor applied to cropped cell images before VisionKit re-recognition.
// A 5x upscale helps VisionKit read small/faint digits.
const CELL_UPSCALE_FACTOR: number = 5;

// Retry parameters for empty cells where the first VK call returned null.
// A tighter crop (less padding) and higher upscale help VK detect thin digits
// like "1" that it misses with the default wide padding.
const CELL_CROP_PAD_FACTOR_RETRY: number = 0.15;
const CELL_UPSCALE_FACTOR_RETRY: number = 8;

// Minimum pixel confidence for filling an empty cell via pixel recognition.
// Keep this above the 0.55 geometry-only thin-"1" fallback: logs24 showed
// geometry-only pixel fills can add false positives in truly empty cells.
const EMPTY_FILL_PIXEL_CONF: number = 0.55;

// When full-page OCR produced no positional digits, pixel-only empty-cell fills
// are much riskier. Logs28 tiny_200 showed false fills at 0.56/0.60/0.69, so
// require stronger pixel evidence in that low-information path.
const EMPTY_FILL_PIXEL_CONF_NO_RAW_DIGITS: number = 0.72;

// Minimum crop width/height (px) for a cell to be sent to VisionKit.
// Smaller crops are too low-resolution to be useful.
const MIN_CELL_CROP_DIM: number = 10;

const PER_CELL_VK_TIMEOUT_MS: number = 2000;

// Maximum per-cell OCR calls in fixAndFillGrid. A single empty cell can use
// normal, tight, and wide retries, so keep the budget above 81 to avoid logs30
// later givens being skipped after early empty-cell nulls consume the quota.
const MAX_FIX_CELLS: number = 180;

// If a single VK call takes longer than this, subsequent VK calls are skipped
// to avoid native-layer blocking that can freeze the JS event loop.
const VK_SLOW_CALL_THRESHOLD_MS: number = 1500;

// Number of consecutive VK null results before giving up on VK entirely. Most
// remaining logs30 failures are false negatives in later empty cells; fast nulls
// should not stop before those cells get a chance to run wide-region OCR.
const VK_MAX_CONSECUTIVE_NULL: number = 36;

// Wide-region OCR retry crops the target cell plus horizontal neighbors, then
// accepts only words whose center falls back inside the target cell. This gives
// VisionKit grid context for thin "1" and missed "8" cells without using a
// majority vote that could pull in neighbor digits.
const WIDE_CELL_PAD_X_FACTOR: number = 1.10;
const WIDE_CELL_PAD_Y_FACTOR: number = 0.25;
const WIDE_CELL_UPSCALE_FACTOR: number = 5;

// Total pipeline timeout: if recognizeSudokuFromBuffer hasn't resolved within
// this many milliseconds, return a failure result instead of hanging forever.
const OCR_PIPELINE_TOTAL_TIMEOUT_MS: number = 30000;

function yieldThread(): Promise<void> {
  return new Promise<void>((resolve: Function) => { setTimeout(() => { resolve(); }, 0); });
}

// Resize thresholds: images larger than these are downscaled to the
// corresponding target to balance OCR quality and speed.
// Small images (<RESIZE_SMALL_THRESHOLD) are upscaled to at most RESIZE_SMALL_TARGET
// but with a cap of 2x to avoid destroying thin stroke signatures
// (e.g. 200px 4x upscale → ink=36 vs native → ink=328).
const RESIZE_LARGE_THRESHOLD: number = 2000;
const RESIZE_LARGE_TARGET: number = 1600;
const RESIZE_MEDIUM_THRESHOLD: number = 1280;
const RESIZE_SMALL_THRESHOLD: number = 800;
const RESIZE_SMALL_TARGET: number = 800;

// Confidence threshold: digits with VisionKit confidence below this are
// flagged as low-confidence and re-checked in fixAndFillGrid.
const LOW_CONFIDENCE_THRESHOLD: number = 0.5;

// Digits that are frequently confused with each other by both VisionKit and
// pixel recognition. These get extra scrutiny in fixAndFillGrid.
const CONFUSABLE_DIGITS: number[] = [2, 3, 4, 5, 6, 7, 8, 9];

// Upper confidence bound: a confusable digit with VK/pixel confidence below
// this is added to the fix set for VK re-recognition, even if it has no
// conflict. Targets the common 5↔6, 5↔9, 6↔9 misreads where VK reports a
// wrong digit with moderate (not low) confidence.
const CONFUSABLE_RECHECK_CONFIDENCE: number = 0.85;

// Confidence threshold for the pixel adjudication pass: when pixel recognition
// disagrees with the grid on a confusable digit pair and the pixel confidence
// is at least this value, the pixel answer overrides the grid (provided no new
// conflict is introduced). Lowered from 0.75 to 0.6 to catch moderate-confidence
// pixel corrections that were previously ignored.
const CONFUSABLE_PIXEL_OVERRIDE_CONF: number = 0.6;

// Pixel-only correction is much riskier than pixel+VK agreement. Logs24 showed
// faint inputs can bias pixel templates toward 5 or geometry-only 1, so an
// existing VK digit is overridden by pixel alone only at high confidence or
// when the change demonstrably reduces Sudoku conflicts.
const EXISTING_PIXEL_ONLY_OVERRIDE_CONF: number = 0.72;

// Moderate-confidence pixel-only confusable corrections are allowed only when
// the current grid is already conflict-free and full-page VK provided positional
// digits. This targets stable synthetic misses such as logs29 (7,5)=6 with
// pixel 9 at 0.67, while avoiding rawDigits=0 tiny/photo low-information paths.
const STABLE_PIXEL_ONLY_OVERRIDE_CONF: number = 0.66;

// Default confidence assigned to digits recognized via positional mapping
// (buildGridByPosition) and text-parsing fallback respectively.
const POSITIONAL_CONFIDENCE: number = 0.7;
const TEXT_FALLBACK_CONFIDENCE: number = 0.5;

// Board warp output size multiplier: warped image side = boardSize * 1.1,
// adding 10% margin around the board in the perspective-corrected image.
const WARP_SIZE_MULTIPLIER: number = 1.1;

// Background brightness threshold: if bgColor < 128, treat image as dark-mode
// (light ink on dark background), otherwise dark ink on light background.
const BG_DARK_THRESHOLD: number = 128;

// Occupancy gate for OCR-level cell statistics. Pixel signature extraction has
// its own lower raw-ink gate in SudokuPixel.ets for thin digit recall.
const OCR_CELL_OCCUPANCY_MIN_RATIO: number = 0.035;

// Background sampling step divisor for warped image background estimation.
const WARP_BG_SAMPLE_DIV: number = 20000;

let g_lastPixelConfidence: number[] = new Array<number>(81).fill(0);

interface CellCoordInfo {
  row: number;
  col: number;
  digit: number;
  left: number;
  top: number;
  w: number;
  h: number;
  conf: number;
  rawInk: number;
  imgW: number;
  imgH: number;
  source: string;
}
let g_lastCellCoords: CellCoordInfo[] = [];

let g_debugInfo: OCRDebugInfo | null = null;

let g_lastDebugBbox: string = '';
let g_lastDebugResize: string = '';
let g_lastDebugRawDigits: number = 0;
let g_lastDebugRawDigitPositions: string = '';
let g_lastDebugConflicts: number[] = [];
let g_probeBbox: BoardBBox | null = null;
let g_probeResizeW: number = 0;
let g_probeResizeH: number = 0;
let g_fittedBoardL: number = -1;
let g_fittedBoardT: number = -1;
let g_fittedBoardR: number = -1;
let g_fittedBoardB: number = -1;
let g_lastDebugLowConf: number[] = [];
let g_lastDebugEmpty: number[] = [];
let g_lastDebugFixCount: number = 0;
let g_vkInited: boolean = false;
let g_vkFailed: boolean = false;

let g_cachedPixels: Uint8Array = new Uint8Array(0);
let g_cachedImgW: number = 0;
let g_cachedImgH: number = 0;

let g_lastDebugVkRawText: string = '';
let g_lastDebugVkBlockCount: number = 0;
let g_lastDebugVkOcrSize: string = '';
let g_lastDebugVkOcrError: string = '';
let g_lastDebugVkBlockDetail: string = '';
let g_lastDebugProbeInfo: string = '';
let g_lastDebugPixelBgInfo: string = '';
let g_lastDebugPixelBboxLocator: string = '';
let g_lastDebugPixelWarpInfo: string = '';
let g_lastDebugPixelCellStats: string = '';
let g_lastDebugPixelCellCoords: string = '';
let g_lastDebugFixDetails: string = '';

// 逐格VK诊断统计（供调试面板展示）
interface PerCellVkDiag {
  cropFail: number;
  noBlock: number;
  noCenter: number;
  found: number;
  samples: string[];
}

// Pixel-only candidates that are too weak alone are queued for a paired
// conflict-resolution pass, avoiding order-dependent 6/9 over-correction.
interface PixelConflictCandidate {
  idx: number;
  digit: number;
  confidence: number;
}
let g_perCellVkDiag: PerCellVkDiag = {
  cropFail: 0, noBlock: 0, noCenter: 0, found: 0, samples: []
};

export function getOCRDebugInfo(): OCRDebugInfo | null {
  return g_debugInfo;
}

function formatGridStr(grid: number[] | null): string {
  if (grid === null) { return '(null)'; }
  let s: string = '';
  for (let r: number = 0; r < 9; r++) {
    let line: string = '';
    for (let c: number = 0; c < 9; c++) {
      const v: number = grid[r * 9 + c];
      line += (v === 0 ? '.' : v.toString()) + ' ';
    }
    s += line.trimEnd() + '\n';
  }
  return s;
}

function formatConfStr(conf: number[] | null): string {
  if (conf === null) { return '(null)'; }
  let s: string = '';
  for (let r: number = 0; r < 9; r++) {
    let line: string = '';
    for (let c: number = 0; c < 9; c++) {
      const v: number = conf[r * 9 + c];
      const digit: number = r * 9 + c;
      line += (digit < 10 ? ' ' : '') + v.toFixed(2) + ' ';
    }
    s += line.trimEnd() + '\n';
  }
  return s;
}

function buildDebugInfo(
  pipeline: string,
  steps: OCRDebugStep[],
  bboxInfo: string,
  resizeInfo: string,
  rawDigitCount: number,
  vkGrid: number[] | null,
  pixelGrid: number[] | null,
  finalGrid: number[] | null,
  conflictIndices: number[],
  lowConfIndices: number[],
  emptyIndices: number[],
  fixCount: number,
  confidence: number[] | null
): OCRDebugInfo {
  const info: OCRDebugInfo = {
    steps: steps,
    rawDigits: rawDigitCount,
    visionKitGrid: formatGridStr(vkGrid),
    pixelGrid: formatGridStr(pixelGrid),
    finalGrid: formatGridStr(finalGrid),
    bboxInfo: bboxInfo,
    resizeInfo: resizeInfo,
    conflictIndices: conflictIndices,
    lowConfIndices: lowConfIndices,
    emptyIndices: emptyIndices,
    fixCount: fixCount,
    confidence: formatConfStr(confidence),
    pipeline: pipeline,
    visionKitRawText: g_lastDebugVkRawText,
    visionKitBlockCount: g_lastDebugVkBlockCount,
    visionKitBlockDetail: g_lastDebugVkBlockDetail,
    visionKitOcrSize: g_lastDebugVkOcrSize,
    visionKitOcrError: g_lastDebugVkOcrError,
    visionKitRawDigitPositions: g_lastDebugRawDigitPositions,
    probeInfo: g_lastDebugProbeInfo,
    pixelBgInfo: g_lastDebugPixelBgInfo,
    pixelBboxLocator: g_lastDebugPixelBboxLocator,
    pixelWarpInfo: g_lastDebugPixelWarpInfo,
    pixelCellStats: g_lastDebugPixelCellStats,
    pixelCellCoords: g_lastDebugPixelCellCoords,
    fixDetails: g_lastDebugFixDetails,
    bboxDiag: getLastBboxDiag()
  };
  return info;
}

export function getLastPixelConfidence(): number[] {
  return g_lastPixelConfidence;
}

export interface OCRDebugStep {
  step: string;
  detail: string;
}

export interface OCRDebugInfo {
  steps: OCRDebugStep[];
  rawDigits: number;
  visionKitGrid: string;
  pixelGrid: string;
  finalGrid: string;
  bboxInfo: string;
  resizeInfo: string;
  conflictIndices: number[];
  lowConfIndices: number[];
  emptyIndices: number[];
  fixCount: number;
  confidence: string;
  pipeline: string;
  visionKitRawText: string;
  visionKitBlockCount: number;
  visionKitBlockDetail: string;
  visionKitOcrSize: string;
  visionKitOcrError: string;
  visionKitRawDigitPositions: string;
  probeInfo: string;
  pixelBgInfo: string;
  pixelBboxLocator: string;
  pixelWarpInfo: string;
  pixelCellStats: string;
  pixelCellCoords: string;
  fixDetails: string;
  bboxDiag: string;
}

export interface OCRResult {
  success: boolean;
  grid: number[] | null;
  rawText: string;
  error: string;
  confidence: number[] | null;
  debugInfo: OCRDebugInfo | null;
}

interface VisionKitGridResult {
  grid: number[];
  boardL: number;
  boardT: number;
  boardW: number;
  boardH: number;
  imgW: number;
  imgH: number;
}

interface RawDigit {
  cx: number;
  cy: number;
  digit: number;
}

interface AdaptiveResizeParams {
  targetW: number;
  targetH: number;
  targetCellPx: number;
}

function computeAdaptiveResize(origW: number, origH: number): AdaptiveResizeParams {
  const maxDim: number = Math.max(origW, origH);
  let targetW: number = origW;
  let targetH: number = origH;
  let targetCellPx: number = TARGET_CELL_PX;
  const MAX_UPSCALE: number = 2.0;

  if (maxDim > RESIZE_LARGE_THRESHOLD) {
    const scale: number = RESIZE_LARGE_TARGET / maxDim;
    targetW = Math.round(origW * scale);
    targetH = Math.round(origH * scale);
  } else if (maxDim >= RESIZE_SMALL_THRESHOLD) {
    if (maxDim > RESIZE_MEDIUM_THRESHOLD) {
      const scale: number = RESIZE_MEDIUM_THRESHOLD / maxDim;
      targetW = Math.round(origW * scale);
      targetH = Math.round(origH * scale);
    }
  } else {
    const scale: number = Math.min(MAX_UPSCALE, RESIZE_SMALL_TARGET / maxDim);
    targetW = Math.round(origW * scale);
    targetH = Math.round(origH * scale);
  }

  const params: AdaptiveResizeParams = { targetW: targetW, targetH: targetH, targetCellPx: targetCellPx };
  return params;
}

function openImageSource(uri: string): image.ImageSource {
  const file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
  return image.createImageSource(file.fd);
}

function openImageSourceFromBuffer(buf: ArrayBuffer): image.ImageSource {
  return image.createImageSource(buf);
}

export async function recognizeSudokuFromBuffer(buf: ArrayBuffer, pixelOnly: boolean = false): Promise<OCRResult> {
  g_debugInfo = null;
  g_fittedBoardL = -1;
  g_fittedBoardT = -1;
  g_fittedBoardR = -1;
  g_fittedBoardB = -1;
  g_cachedPixels = new Uint8Array(0);
  g_cachedImgW = 0;
  g_cachedImgH = 0;
  resetChannelBgCache();
  g_vkFailed = pixelOnly;
  const steps: OCRDebugStep[] = [];
  const pipelineStart: number = Date.now();
  try {
    hilog.info(DOMAIN, TAG, '=== recognizeSudokuFromBuffer START ===');
    hilog.info(DOMAIN, TAG, '=== 识别调试信息(buffer) ===');

    steps.push({ step: '1. 像素分析', detail: '开始(buffer)' });
    hilog.info(DOMAIN, TAG, '>>> tryPixelGridRecognition');
    hilog.info(DOMAIN, TAG, '>>> tryPixelGridRecognition 开始');
    const pixelResult: OCRResult = await tryPixelGridRecognition('', buf);
    const pixelDigits: number = pixelResult.grid !== null ? pixelResult.grid.filter((d: number) => d > 0).length : 0;
    hilog.info(DOMAIN, TAG, '<<< tryPixelGridRecognition success=%{public}d digits=%{public}d elapsed=%{public}dms',
      pixelResult.success ? 1 : 0, pixelDigits, Date.now() - pipelineStart);
    hilog.info(DOMAIN, TAG, '<<< tryPixelGridRecognition 返回 success=%{public}d digits=%{public}d', pixelResult.success ? 1 : 0, pixelDigits);

    if (pixelResult.success && pixelResult.grid && pixelDigits > 0) {
      steps.push({ step: '2. 像素分析结果', detail: `成功, ${pixelDigits}个数字` });
      const pixelGrid: number[] = [...pixelResult.grid];

      if (pixelDigits < 20 && !pixelOnly) {
        hilog.info(DOMAIN, TAG, 'pixelDigits=%{public}d < 20, trying VK full-page OCR', pixelDigits);
        hilog.info(DOMAIN, TAG, '【步骤详情】像素识别数不足%{public}d个，转VK全页识别', pixelDigits);
        const visionResult: OCRResult = await tryVisionKitRecognition('', buf);
        const vkDigits: number = visionResult.grid !== null ? visionResult.grid.filter((d: number) => d > 0).length : 0;
        hilog.info(DOMAIN, TAG, 'VK full-page: success=%{public}d digits=%{public}d', visionResult.success ? 1 : 0, vkDigits);
        hilog.info(DOMAIN, TAG, 'VK全页识别 success=%{public}d digits=%{public}d', visionResult.success ? 1 : 0, vkDigits);

        if (visionResult.success && visionResult.grid && vkDigits > pixelDigits) {
          hilog.info(DOMAIN, TAG, 'VK (%{public}d digits) better than pixel (%{public}d), using VK', vkDigits, pixelDigits);
          hilog.info(DOMAIN, TAG, 'VK结果更优，采用VK');
          const vkGrid: number[] = [...visionResult.grid];
          const corrected: OCRResult = await fixAndFillGrid(visionResult, '', buf);
          g_debugInfo = buildDebugInfo(
            'VK全页+修正',
            steps,
            g_lastDebugBbox,
            g_lastDebugResize,
            g_lastDebugRawDigits,
            vkGrid,
            null,
            corrected.grid,
            g_lastDebugConflicts,
            g_lastDebugLowConf,
            g_lastDebugEmpty,
            g_lastDebugFixCount,
            corrected.confidence
          );
          return corrected;
        }
      }

      const corrected: OCRResult = await fixAndFillGrid(pixelResult, '', buf);
      hilog.info(DOMAIN, TAG, '<<< fixAndFillGrid success=%{public}d elapsed=%{public}dms',
        corrected.success ? 1 : 0, Date.now() - pipelineStart);
      g_debugInfo = buildDebugInfo(
        '像素分析+修正',
        steps,
        g_lastDebugBbox,
        g_lastDebugResize,
        0,
        pixelGrid,
        null,
        corrected.grid,
        g_lastDebugConflicts,
        g_lastDebugLowConf,
        g_lastDebugEmpty,
        g_lastDebugFixCount,
        corrected.confidence
      );
      return corrected;
    }

    steps.push({ step: '2. 像素分析失败', detail: pixelResult.error });
      hilog.info(DOMAIN, TAG, '像素分析失败, 转VisionKit');
    hilog.info(DOMAIN, TAG, '【步骤详情】像素分析失败，转VisionKit识别');
    if (!pixelOnly) {
      hilog.info(DOMAIN, TAG, '>>> tryVisionKitRecognition 开始');
      const visionResult: OCRResult = await tryVisionKitRecognition('', buf);
      hilog.info(DOMAIN, TAG, '<<< tryVisionKitRecognition 返回 success=%{public}d', visionResult.success ? 1 : 0);
      if (visionResult.success && visionResult.grid) {
        const vkGrid: number[] = [...visionResult.grid];
        steps.push({ step: '3. VisionKit结果', detail: `成功, ${visionResult.grid.filter((d: number) => d > 0).length}个数字` });
        const corrected: OCRResult = await fixAndFillGrid(visionResult, '', buf);
        g_debugInfo = buildDebugInfo(
          'VisionKit+修正',
          steps,
          g_lastDebugBbox,
          g_lastDebugResize,
          g_lastDebugRawDigits,
          vkGrid,
          null,
          corrected.grid,
          g_lastDebugConflicts,
          g_lastDebugLowConf,
          g_lastDebugEmpty,
          g_lastDebugFixCount,
          corrected.confidence
        );
        return corrected;
      }
    }

    return pixelResult;
  } catch (_err) {
    hilog.error(DOMAIN, TAG, '异常: %{public}s', `${_err}`);
    hilog.error(DOMAIN, TAG, '异常: %{public}s', `${_err}`);
    return { success: false, grid: null, rawText: '', error: '图片处理异常，请尝试手动输入', confidence: null, debugInfo: null };
  }
}

export async function recognizeSudokuFromImage(imagePath: string): Promise<OCRResult> {
  g_debugInfo = null;
  g_fittedBoardL = -1;
  g_fittedBoardT = -1;
  g_fittedBoardR = -1;
  g_fittedBoardB = -1;
  resetChannelBgCache();
  const steps: OCRDebugStep[] = [];
  try {
    hilog.info(DOMAIN, TAG, '=== 识别调试信息 ===');
    hilog.info(DOMAIN, TAG, '【流水线】VisionKit+修正 (首次尝试)');
    steps.push({ step: '1. VisionKit识别', detail: '开始' });
    const visionResult: OCRResult = await tryVisionKitRecognition(imagePath);
    hilog.info(DOMAIN, TAG, '【步骤详情】VisionKit识别 success=%{public}d error=%{public}s', visionResult.success ? 1 : 0, visionResult.error);
    if (visionResult.success && visionResult.grid) {
      const vkGrid: number[] = [...visionResult.grid];
      steps.push({ step: '2. VisionKit结果', detail: `成功, ${visionResult.grid.filter((d: number) => d > 0).length}个数字` });
      const corrected: OCRResult = await fixAndFillGrid(visionResult, imagePath);
      g_debugInfo = buildDebugInfo(
        'VisionKit+修正',
        steps,
        g_lastDebugBbox,
        g_lastDebugResize,
        g_lastDebugRawDigits,
        vkGrid,
        null,
        corrected.grid,
        g_lastDebugConflicts,
        g_lastDebugLowConf,
        g_lastDebugEmpty,
        g_lastDebugFixCount,
        corrected.confidence
      );
    return corrected;
    }
    steps.push({ step: '2. VisionKit失败', detail: visionResult.error });
    hilog.info(DOMAIN, TAG, '【步骤详情】VisionKit失败，转像素分析');
    const pixelResult: OCRResult = await tryPixelGridRecognition(imagePath);
    g_debugInfo = buildDebugInfo(
      '像素分析',
      steps,
      g_lastDebugBbox,
      g_lastDebugResize,
      0,
      null,
      pixelResult.grid,
      pixelResult.grid,
      [],
      [],
      [],
      0,
      pixelResult.confidence
    );
    return pixelResult;
  } catch (_err) {
    hilog.error(DOMAIN, TAG, '异常: %{public}s', `${_err}`);
    return { success: false, grid: null, rawText: '', error: '图片处理异常，请尝试手动输入', confidence: null, debugInfo: null };
  }
}

function findConflictCells(grid: number[]): number[] {
  const conflicts: Set<number> = new Set<number>();

  for (let r: number = 0; r < 9; r++) {
    for (let c: number = 0; c < 9; c++) {
      const val: number = grid[r * 9 + c];
      if (val === 0) { continue; }
      for (let j: number = 0; j < 9; j++) {
        if (j !== c && grid[r * 9 + j] === val) {
          conflicts.add(r * 9 + c);
          conflicts.add(r * 9 + j);
        }
        if (j !== r && grid[j * 9 + c] === val) {
          conflicts.add(r * 9 + c);
          conflicts.add(j * 9 + c);
        }
      }
      const boxR: number = Math.floor(r / 3) * 3;
      const boxC: number = Math.floor(c / 3) * 3;
      for (let br: number = boxR; br < boxR + 3; br++) {
        for (let bc: number = boxC; bc < boxC + 3; bc++) {
          if (!(br === r && bc === c) && grid[br * 9 + bc] === val) {
            conflicts.add(r * 9 + c);
            conflicts.add(br * 9 + bc);
          }
        }
      }
    }
  }

  const result: number[] = [];
  conflicts.forEach((idx: number) => { result.push(idx); });
  return result.sort((a: number, b: number) => a - b);
}

function isConfusablePair(a: number, b: number): boolean {
  if (a === b || a <= 0 || b <= 0) { return false; }
  if ((a === 5 || a === 6 || a === 9) && (b === 5 || b === 6 || b === 9)) { return true; }
  if ((a === 7 && b === 9) || (a === 9 && b === 7)) { return true; }
  if ((a === 8 && b === 9) || (a === 9 && b === 8)) { return true; }
  if ((a === 1 && b === 7) || (a === 7 && b === 1)) { return true; }
  if ((a === 3 && b === 8) || (a === 8 && b === 3)) { return true; }
  if ((a === 2 && b === 8) || (a === 8 && b === 2)) { return true; }
  if ((a === 4 && b === 9) || (a === 9 && b === 4)) { return true; }
  if ((a === 3 && b === 5) || (a === 5 && b === 3)) { return true; }
  if ((a === 1 && b === 4) || (a === 4 && b === 1)) { return true; }
  if ((a === 1 && b === 8) || (a === 8 && b === 1)) { return true; }
  if ((a === 1 && b === 6) || (a === 6 && b === 1)) { return true; }
  if ((a === 5 && b === 8) || (a === 8 && b === 5)) { return true; }
  if ((a === 2 && b === 4) || (a === 4 && b === 2)) { return true; }
  if ((a === 3 && b === 7) || (a === 7 && b === 3)) { return true; }
  return false;
}

function conflictCountAfterSet(grid: number[], idx: number, digit: number): number {
  const copyGrid: number[] = [...grid];
  copyGrid[idx] = digit;
  return findConflictCells(copyGrid).length;
}

// Apply the best two-cell pixel correction only when the pair reduces total
// Sudoku conflicts; this recovers all-thin/no-border cases where a correct
// single-cell 6/9 change may temporarily keep or slightly increase conflicts.
function applyBestPixelConflictPair(grid: number[], candidates: PixelConflictCandidate[]): string {
  const beforeConflicts: number = findConflictCells(grid).length;
  if (beforeConflicts === 0 || candidates.length < 2) { return ''; }
  let bestI: number = -1;
  let bestJ: number = -1;
  let bestConflicts: number = beforeConflicts;
  let bestScore: number = 0;
  for (let i: number = 0; i < candidates.length; i++) {
    for (let j: number = i + 1; j < candidates.length; j++) {
      const ci: PixelConflictCandidate = candidates[i];
      const cj: PixelConflictCandidate = candidates[j];
      const copyGrid: number[] = [...grid];
      copyGrid[ci.idx] = ci.digit;
      copyGrid[cj.idx] = cj.digit;
      const afterConflicts: number = findConflictCells(copyGrid).length;
      const score: number = ci.confidence + cj.confidence;
      if (afterConflicts < bestConflicts || (afterConflicts === bestConflicts && score > bestScore)) {
        bestI = i;
        bestJ = j;
        bestConflicts = afterConflicts;
        bestScore = score;
      }
    }
  }
  if (bestI < 0 || bestJ < 0 || bestConflicts >= beforeConflicts) { return ''; }
  const a: PixelConflictCandidate = candidates[bestI];
  const b: PixelConflictCandidate = candidates[bestJ];
  const oldA: number = grid[a.idx];
  const oldB: number = grid[b.idx];
  grid[a.idx] = a.digit;
  grid[b.idx] = b.digit;
  return `像素成对解冲突 [${a.idx}]${oldA}→${a.digit}(conf=${a.confidence.toFixed(2)}) [${b.idx}]${oldB}→${b.digit}(conf=${b.confidence.toFixed(2)}) c=${beforeConflicts}→${bestConflicts}`;
}

// 从已加载的像素缓冲区中裁剪单格区域，上采样后返回 PixelMap
function cropCellFromBuffer(
  pixels: Uint8Array, imgW: number, imgH: number,
  cropX: number, cropY: number, cropW: number, cropH: number,
  upscale: number
): image.PixelMap | null {
  try {
    const srcStride: number = imgW * 4;
    const dstStride: number = cropW * 4;
    const bufSize: number = dstStride * cropH;
    const buf: ArrayBuffer = new ArrayBuffer(bufSize);
    const dst: Uint8Array = new Uint8Array(buf);

    // 逐行拷贝裁剪区域
    for (let y: number = 0; y < cropH; y++) {
      const srcRowOff: number = ((cropY + y) * imgW + cropX) * 4;
      const dstRowOff: number = y * dstStride;
      for (let x: number = 0; x < dstStride; x++) {
        dst[dstRowOff + x] = pixels[srcRowOff + x];
      }
    }

    const opts: image.InitializationOptions = {
      editable: true,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      size: { height: cropH, width: cropW }
    };
    const snapshot: image.PixelMap = image.createPixelMapSync(opts);
    const destArea: image.PositionArea = {
      pixels: buf,
      offset: 0,
      stride: dstStride,
      region: { size: { width: cropW, height: cropH }, x: 0, y: 0 }
    };
    snapshot.writePixelsSync(destArea);
    snapshot.scaleSync(upscale, upscale);
    return snapshot;
  } catch (_e) {
    return null;
  }
}

async function recognizeDigitVisionKit(cellPm: image.PixelMap): Promise<number | null> {
  try {
    const visionInfo: textRecognition.VisionInfo = { pixelMap: cellPm };
    const recogResult: textRecognition.TextRecognitionResult =
      await textRecognition.recognizeText(visionInfo, {
        isDirectionDetectionSupported: false
      });

    const rawText: string = recogResult.value || '';
    const digits: string[] = rawText.replace(/[^0-9]/g, '').split('');
    if (digits.length === 0) { return null; }

    const digitCounts: Map<number, number> = new Map<number, number>();
    for (const ch of digits) {
      const d: number = parseInt(ch, 10);
      const prev: number | undefined = digitCounts.get(d);
      digitCounts.set(d, prev !== undefined ? prev + 1 : 1);
    }

    let bestDigit: number = parseInt(digits[0], 10);
    let bestCount: number = 0;
    digitCounts.forEach((count: number, digit: number) => {
      if (count > bestCount) {
        bestCount = count;
        bestDigit = digit;
      }
    });

    hilog.info(DOMAIN, TAG, '【逐格修正详情】单格识别 rawText="%{public}s" bestDigit=%{public}d', rawText, bestDigit);
    return bestDigit;
  } catch (_e) {
    hilog.error(DOMAIN, TAG, 'VisionKit重识异常: %{public}s', `${_e}`);
    return null;
  }
}

// 宽区域识别：裁剪目标格+左右邻格（提供网格线上下文），用 VisionKit word 位置定位中心格数字
async function recognizeDigitInWideRegion(
  cellPm: image.PixelMap,
  upscale: number,
  centerCellX: number, centerCellY: number,
  centerCellW: number, centerCellH: number
): Promise<number | null> {
  try {
    const visionInfo: textRecognition.VisionInfo = { pixelMap: cellPm };
    const recogResult: textRecognition.TextRecognitionResult =
      await textRecognition.recognizeText(visionInfo, {
        isDirectionDetectionSupported: false
      });

    const rawText: string = recogResult.value || '';
    if (g_perCellVkDiag.samples.length < 3) {
      g_perCellVkDiag.samples.push(`raw="${rawText.slice(0,30)}" blocks=${(recogResult.blocks || []).length}`);
    }
    hilog.info(DOMAIN, TAG, '【逐格修正详情】宽域识 raw="%{public}s" blocks=%{public}d',
      rawText, (recogResult.blocks || []).length);

    const blocks: Array<textRecognition.TextBlock> = recogResult.blocks || [];
    if (blocks.length === 0) {
      g_perCellVkDiag.noBlock++;
      if (rawText.length === 0) { return null; }
      // 无 block 无位置信息 → 留空，不回退多数投票
      hilog.info(DOMAIN, TAG, '【逐格修正详情】宽域识无block 留空 raw="%{public}s"', rawText);
      return null;
    }

    // 中心格在 upscaled 坐标系中的范围
    const cxMin: number = centerCellX * upscale;
    const cxMax: number = (centerCellX + centerCellW) * upscale;
    const cyMin: number = centerCellY * upscale;
    const cyMax: number = (centerCellY + centerCellH) * upscale;

    const centerCandidates: number[] = [];
    let wordCount: number = 0;
    let cpCount: number = 0;

    for (const block of blocks) {
      const lines: Array<textRecognition.TextLine> = block.lines || [];
      for (const line of lines) {
        const words: Array<textRecognition.TextWord> = line.words || [];
        for (const word of words) {
          wordCount++;
          const text: string = word.value.trim();
          const cp: Array<textRecognition.PixelPoint> = word.cornerPoints;
          if (cp.length < 4) { continue; }
          cpCount++;

          // word 中心点（对角线中点）
          const wcx: number = (cp[0].x + cp[2].x) / 2;
          const wcy: number = (cp[0].y + cp[2].y) / 2;

          const inCenter: boolean = (wcx >= cxMin && wcx < cxMax && wcy >= cyMin && wcy < cyMax);

          // 提取 word 中的数字
          const ds: string[] = text.replace(/[^0-9]/g, '').split('');
          for (const ch of ds) {
            const d: number = parseInt(ch, 10);
            if (d >= 1 && d <= 9) {
              if (inCenter) {
                centerCandidates.push(d);
              }
            }
          }
        }
      }
    }

    // 优先用位置精确定位的中心格候选
    if (centerCandidates.length > 0) {
      const cntMap: Map<number, number> = new Map();
      for (const d of centerCandidates) {
        cntMap.set(d, (cntMap.get(d) || 0) + 1);
      }
      let best: number = 0; let bestCnt: number = 0;
      cntMap.forEach((c: number, d: number) => { if (c > bestCnt) { bestCnt = c; best = d; } });
      hilog.info(DOMAIN, TAG, '【逐格修正详情】宽域识定位成功 centerCandidates=%{public}s best=%{public}d',
        centerCandidates.join(','), best);
      g_perCellVkDiag.found++;
      return best;
    }

    // 中心格无定位 word → 留空（避免把邻格数字误填进来）
    g_perCellVkDiag.noCenter++;
    hilog.info(DOMAIN, TAG, '【逐格修正详情】宽域识定位失败 留空 words=%{public}d cpWords=%{public}d center=[%.0f-%.0f, %.0f-%.0f] upscale=%{public}d',
      wordCount, cpCount, cxMin, cxMax, cyMin, cyMax, upscale);
    return null;
  } catch (_e) {
    hilog.error(DOMAIN, TAG, 'VisionKit宽域识异常: %{public}s', `${_e}`);
    g_perCellVkDiag.noBlock++;
    return null;
  }
}

function recognizeDigitPixel(
  gray: Float32Array,
  imgW: number,
  cellLeft: number, cellTop: number,
  cellW: number, cellH: number,
  isDark: boolean, bg: number,
  gridRow: number = -1,
  gridCol: number = -1
): number | null {
  resetLastPixelDiag();
  let sig: number[] | null = cellSigFromGray(
    gray, imgW,
    cellLeft, cellTop, cellW, cellH, isDark, bg, gridRow, gridCol
  );
  if (sig === null) {
    const d: string = getLastPixelDiag();
    const ri: number = getLastRawInkRatio();
    const lowSig: number[] | null = cellSigFromGrayLowThresh(
      gray, imgW, cellLeft, cellTop, cellW, cellH, isDark, bg, gridRow, gridCol
    );
    if (lowSig !== null) {
      sig = lowSig;
      const lowInk: number = countInk(lowSig);
      const lowDigit: number = recognizeDigit(lowSig, lowInk);
      if (lowDigit > 0) {
        const lowD: string = getLastPixelDiag();
        g_lastRecognizeDiag = `retryLowThresh: digit=${lowDigit} ink=${lowInk} diag=[${lowD}] rawInk=${ri.toFixed(4)}`;
        return lowDigit;
      }
    }
    if (ri < MIN_CELL_INK_RATIO) {
      const thinSig: number[] | null = cellSigFromGrayThin(
        gray, imgW, cellLeft, cellTop, cellW, cellH, isDark, bg, gridRow, gridCol
      );
      if (thinSig !== null) {
        sig = thinSig;
        const thinInk: number = countInk(thinSig);
        const thinDigit: number = recognizeDigit(thinSig, thinInk);
        if (thinDigit > 0) {
          const thinD: string = getLastPixelDiag();
          g_lastRecognizeDiag = `retryThin: digit=${thinDigit} ink=${thinInk} diag=[${thinD}] rawInk=${ri.toFixed(4)}`;
          return thinDigit;
        }
      }
    }
    g_lastRecognizeDiag = `sigNull diag=[${d}] rawInk=${ri.toFixed(4)}`;
    return null;
  }

  const inkCount: number = countInk(sig);
  const digit: number = recognizeDigit(sig, inkCount);
  if (digit > 0) {
    const d: string = getLastPixelDiag();
    g_lastRecognizeDiag = `digit=${digit} ink=${inkCount} diag=[${d}]`;
    return digit;
  }

  const ri2: number = getLastRawInkRatio();
  const lowSig: number[] | null = cellSigFromGrayLowThresh(
    gray, imgW, cellLeft, cellTop, cellW, cellH, isDark, bg, gridRow, gridCol
  );
  if (lowSig !== null) {
    const lowInk: number = countInk(lowSig);
    const lowDigit: number = recognizeDigit(lowSig, lowInk);
    if (lowDigit > 0) {
      const lowD: string = getLastPixelDiag();
      g_lastRecognizeDiag = `retryLowThresh: digit=${lowDigit} ink=${lowInk} diag=[${lowD}] rawInk=${ri2.toFixed(4)}`;
      return lowDigit;
    }
  }
  if (ri2 < MIN_CELL_INK_RATIO) {
    const thinSig: number[] | null = cellSigFromGrayThin(
      gray, imgW, cellLeft, cellTop, cellW, cellH, isDark, bg, gridRow, gridCol
    );
    if (thinSig !== null) {
      const thinInk: number = countInk(thinSig);
      const thinDigit: number = recognizeDigit(thinSig, thinInk);
      if (thinDigit > 0) {
        const thinD: string = getLastPixelDiag();
        g_lastRecognizeDiag = `retryThin: digit=${thinDigit} ink=${thinInk} diag=[${thinD}] rawInk=${ri2.toFixed(4)}`;
        return thinDigit;
      }
    }
  }

  const d: string = getLastPixelDiag();
  g_lastRecognizeDiag = `digit=0 ink=${inkCount} diag=[${d}]`;
  return null;
}

function withTimeout<T>(promise: Promise<T>, ms: number, fallback: T): Promise<T> {
  return new Promise<T>((resolve: Function) => {
    let settled: boolean = false;
    const timer: number = setTimeout(() => {
      if (!settled) {
        settled = true;
        hilog.warn(DOMAIN, TAG, 'withTimeout: %{public}dms超时', ms);
        resolve(fallback);
      }
    }, ms);
    promise.then((result: T) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        resolve(result);
      }
    }).catch((_err: Object) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        hilog.warn(DOMAIN, TAG, 'withTimeout: 异常 %{public}s', `${_err}`);
        resolve(fallback);
      }
    });
  });
}

async function fixAndFillGrid(ocrResult: OCRResult, imagePath: string, imageBuf: ArrayBuffer | null = null): Promise<OCRResult> {
  if (!ocrResult.success || !ocrResult.grid) { return ocrResult; }
  const grid: number[] = [...ocrResult.grid];

  const conflictIndices: number[] = findConflictCells(grid);

  const lowConfIndices: number[] = [];
  if (ocrResult.confidence !== null) {
    for (let i: number = 0; i < 81; i++) {
      if (ocrResult.confidence[i] < LOW_CONFIDENCE_THRESHOLD && grid[i] > 0) {
        lowConfIndices.push(i);
      }
    }
  }

  // Confusable digits (5/6/9) with moderate confidence: these are the most
  // common misrecognition pairs. Even without conflicts, re-check them via VK
  // to catch 5↔6, 5↔9, 6↔9 errors that slip through conflict detection.
  const confusableIndices: number[] = [];
  if (ocrResult.confidence !== null) {
    for (let i: number = 0; i < 81; i++) {
      if (grid[i] > 0 && CONFUSABLE_DIGITS.indexOf(grid[i]) >= 0 &&
        ocrResult.confidence[i] < CONFUSABLE_RECHECK_CONFIDENCE) {
        confusableIndices.push(i);
      }
    }
  } else {
    // No confidence info (pixel path): re-check all confusable digits.
    for (let i: number = 0; i < 81; i++) {
      if (grid[i] > 0 && CONFUSABLE_DIGITS.indexOf(grid[i]) >= 0) {
        confusableIndices.push(i);
      }
    }
  }

  const emptyIndices: number[] = [];
  for (let i: number = 0; i < 81; i++) {
    if (grid[i] === 0) {
      emptyIndices.push(i);
    }
  }

  const fixSet: Set<number> = new Set<number>();
  for (const idx of conflictIndices) { fixSet.add(idx); }
  for (const idx of lowConfIndices) { fixSet.add(idx); }
  for (const idx of confusableIndices) { fixSet.add(idx); }
  for (const idx of emptyIndices) { fixSet.add(idx); }

  const allFixIndices: number[] = [];
  fixSet.forEach((idx: number) => { allFixIndices.push(idx); });

  if (conflictIndices.length > 0) {
    hilog.info(DOMAIN, TAG, '【冲突格子】%{public}d个', conflictIndices.length);
  }
  if (lowConfIndices.length > 0) {
    hilog.info(DOMAIN, TAG, '【低置信格子】%{public}d个', lowConfIndices.length);
  }
  if (confusableIndices.length > 0) {
    hilog.info(DOMAIN, TAG, '【易混数字格子】%{public}d个 (5/6/9)', confusableIndices.length);
  }
  if (emptyIndices.length > 0) {
    hilog.info(DOMAIN, TAG, '【空格子待修正】%{public}d个待填充', emptyIndices.length);
  }
  hilog.info(DOMAIN, TAG, '【步骤详情】共需修正%{public}d格 (%{public}d冲突+%{public}d低置信+%{public}d易混+%{public}d空)',
    allFixIndices.length, conflictIndices.length, lowConfIndices.length, confusableIndices.length, emptyIndices.length);
  hilog.info(DOMAIN, TAG, 'fixAndFillGrid: allFixIndices=%{public}d', allFixIndices.length);

  if (allFixIndices.length === 0) {
    hilog.info(DOMAIN, TAG, '【实际修正】无冲突且无空格，直接采用结果');
    g_lastDebugFixDetails = '';
    g_lastDebugConflicts = conflictIndices;
    g_lastDebugLowConf = lowConfIndices;
    g_lastDebugEmpty = emptyIndices;
    g_lastDebugFixCount = 0;
    return ocrResult;
  }

  let pixels: Uint8Array;
  let imgW: number = 0;
  let imgH: number = 0;
  let pixelMap: image.PixelMap | null = null;

  if (g_cachedPixels.length > 0 && g_cachedImgW > 0 && g_cachedImgH > 0 &&
      g_probeBbox !== null) {
    pixels = g_cachedPixels;
    imgW = g_cachedImgW;
    imgH = g_cachedImgH;
    hilog.info(DOMAIN, TAG, '【步骤详情】校正复用缓存像素 %{public}dx%{public}d', imgW, imgH);
  } else {
    const imageSource = imageBuf !== null
      ? openImageSourceFromBuffer(imageBuf)
      : openImageSource(imagePath);
    const srcInfo: image.ImageInfo = await withTimeout<image.ImageInfo>(imageSource.getImageInfo(), 5000,
      { size: { width: 0, height: 0 } } as image.ImageInfo);
    if (srcInfo.size.width === 0 || srcInfo.size.height === 0) {
      hilog.error(DOMAIN, TAG, '【步骤详情】getImageInfo超时或失败');
      imageSource.release();
      return ocrResult;
    }
    const origW: number = srcInfo.size.width;
    const origH: number = srcInfo.size.height;

    const resize: AdaptiveResizeParams = computeAdaptiveResize(origW, origH);
    let targetW: number = resize.targetW;
    let targetH: number = resize.targetH;
    const maxDim: number = Math.max(targetW, targetH);
    if (maxDim > PIXEL_MAX_DIM) {
      const scaleDown: number = PIXEL_MAX_DIM / maxDim;
      targetW = Math.round(targetW * scaleDown);
      targetH = Math.round(targetH * scaleDown);
    }

    pixelMap = await withTimeout<image.PixelMap | null>(
      imageSource.createPixelMap({
        desiredSize: { width: targetW, height: targetH },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      }), 5000, null);
    imageSource.release();

    if (pixelMap === null) {
      hilog.error(DOMAIN, TAG, '【步骤详情】createPixelMap超时');
      return ocrResult;
    }

    const info: image.ImageInfo = await withTimeout<image.ImageInfo>(pixelMap.getImageInfo(), 5000,
      { size: { width: 0, height: 0 } } as image.ImageInfo);
    if (info.size.width === 0 || info.size.height === 0) {
      hilog.error(DOMAIN, TAG, '【步骤详情】fixAndFillGrid getImageInfo超时或失败');
      pixelMap.release();
      return ocrResult;
    }
    imgW = info.size.width;
    imgH = info.size.height;

    const buffer: ArrayBuffer = new ArrayBuffer(imgW * imgH * 4);
    pixelMap.readPixelsToBuffer(buffer);
    pixels = new Uint8Array(buffer);
  }

  hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 像素加载完成 %{public}dx%{public}d', imgW, imgH);
  const bg: number = bgColor(pixels, imgW, imgH);
  const gray: Float32Array = toGrayArray(pixels, imgW, imgH);

  // 优先复用 VisionKit 探测阶段的 bbox，确保逐格修正时 cell 定位与 VK 主识别对齐
  let bbox: BoardBBox;
  if (g_probeBbox !== null && g_probeResizeW === imgW && g_probeResizeH === imgH) {
    bbox = g_probeBbox;
    hilog.info(DOMAIN, TAG, '【图片与棋盘】校正复用探测bbox [%{public}d,%{public}d,%{public}d,%{public}d] isDark=%{public}d',
      bbox.left, bbox.top, bbox.right, bbox.bottom, bbox.isDark ? 1 : 0);
  } else {
    bbox = findBoardBBox(pixels, imgW, imgH, bg);
    hilog.info(DOMAIN, TAG, '【图片与棋盘】校正重新探测bbox [%{public}d,%{public}d,%{public}d,%{public}d] isDark=%{public}d',
      bbox.left, bbox.top, bbox.right, bbox.bottom, bbox.isDark ? 1 : 0);
  }

  let boardL: number = bbox.left;
  let boardT: number = bbox.top;
  let boardR: number = bbox.right;
  let boardB: number = bbox.bottom;
  if (g_fittedBoardL >= 0 && g_probeResizeW === imgW && g_probeResizeH === imgH) {
    boardL = g_fittedBoardL;
    boardT = g_fittedBoardT;
    boardR = g_fittedBoardR;
    boardB = g_fittedBoardB;
    hilog.info(DOMAIN, TAG, '【图片与棋盘】校正复用拟合bbox [%.1f,%.1f,%.1f,%.1f]',
      boardL, boardT, boardR, boardB);
  }

  const cellW: number = (boardR - boardL) / 9;
  const cellH: number = (boardB - boardT) / 9;
  const padFactor: number = CELL_CROP_PAD_FACTOR;
  const upscale: number = CELL_UPSCALE_FACTOR;

  resetGridLineCrop();
  if (gray.length > 0) {
    detectGridLineWidths(gray, imgW, boardL, boardT, boardR, boardB, bbox.isDark, bg);
    hilog.info(DOMAIN, TAG, '【GridLineCrop】%{public}s', getLastPixelDiag());
  }

  hilog.info(DOMAIN, TAG, '【步骤详情】校正图=%{public}dx%{public}d cell=%.1fx%.1f upscale=%{public}d',
    imgW, imgH, cellW, cellH, upscale);

  let vkInitOk: boolean = false;
  let fixCount: number = 0;
  let vkCellCount: number = 0;
  let vkConsecutiveNull: number = 0;
  let vkSlowMs: number = 0;
  const vkMaxCalls: number = Math.min(allFixIndices.length * 3, MAX_FIX_CELLS);
  let vkCallCount: number = 0;

  if (vkMaxCalls > 0 && pixels.length > 0 && !g_vkFailed) {
    hilog.info(DOMAIN, TAG, 'fixAndFillGrid: VK init attempt, vkMaxCalls=%{public}d pixelsLen=%{public}d vkFailed=%{public}d',
      vkMaxCalls, pixels.length, g_vkFailed ? 1 : 0);
    try {
      const vkInit: boolean = await withTimeout<boolean>(textRecognition.init(), 3000, false);
      vkInitOk = vkInit;
      hilog.info(DOMAIN, TAG, 'fixAndFillGrid: VK init=%{public}d', vkInitOk ? 1 : 0);
      hilog.info(DOMAIN, TAG, 'fixAndFillGrid: VK init=%{public}d', vkInitOk ? 1 : 0);
    } catch (_e) {
      hilog.warn(DOMAIN, TAG, 'fixAndFillGrid: VK init异常 %{public}s', `${_e}`);
      hilog.warn(DOMAIN, TAG, 'fixAndFillGrid: VK init exception: %{public}s', `${_e}`);
    }
  } else {
    hilog.info(DOMAIN, TAG, 'fixAndFillGrid: VK skipped, vkMaxCalls=%{public}d pixelsLen=%{public}d vkFailed=%{public}d',
      vkMaxCalls, pixels.length, g_vkFailed ? 1 : 0);
  }

  g_perCellVkDiag = { cropFail: 0, noBlock: 0, noCenter: 0, found: 0, samples: [] };
  const fixDetailLines: string[] = [];
  const pixelConflictCandidates: PixelConflictCandidate[] = [];

  for (const idx of allFixIndices) {
    const origDigit: number = grid[idx];
    const row: number = Math.floor(idx / 9);
    const col: number = idx % 9;
    const cellLeft: number = boardL + col * cellW;
    const cellTop: number = boardT + row * cellH;
    const cellLabel: string = `(${row},${col})`;

    let pixelDigit: number | null = null;
    if (gray.length > 0) {
      pixelDigit = recognizeDigitPixel(gray, imgW, cellLeft, cellTop, cellW, cellH, bbox.isDark, bg, row, col);
    }
    const pixelDiag: string = g_lastRecognizeDiag;

    let vkDigit: number | null = null;
    let vkCropInfo: string = 'skip';
    const cellRawInk: number = getLastRawInkRatio();
    const cellHasInk: boolean = origDigit !== 0 || pixelDigit !== null || cellRawInk > 0;
    const vkAllowRetry: boolean = cellHasInk;

    if (vkInitOk && vkCallCount < vkMaxCalls && vkConsecutiveNull < VK_MAX_CONSECUTIVE_NULL && vkSlowMs < VK_SLOW_CALL_THRESHOLD_MS * 3) {
      const padW: number = Math.round(cellW * padFactor);
      const padH: number = Math.round(cellH * padFactor);
      const cropX: number = Math.max(Math.floor(cellLeft - padW), 0);
      const cropY: number = Math.max(Math.floor(cellTop - padH), 0);
      const cropX2: number = Math.min(Math.floor(cellLeft + cellW + padW), imgW);
      const cropY2: number = Math.min(Math.floor(cellTop + cellH + padH), imgH);
      const cW: number = cropX2 - cropX;
      const cH: number = cropY2 - cropY;

      if (cW >= MIN_CELL_CROP_DIM && cH >= MIN_CELL_CROP_DIM) {
        const cellPm: image.PixelMap | null = cropCellFromBuffer(pixels, imgW, imgH, cropX, cropY, cW, cH, upscale);
        if (cellPm !== null) {
          const t0: number = Date.now();
          const vkResult: number | null = await withTimeout<number | null>(
            recognizeDigitVisionKit(cellPm), PER_CELL_VK_TIMEOUT_MS, null
          );
          const elapsed: number = Date.now() - t0;
          vkSlowMs = elapsed > VK_SLOW_CALL_THRESHOLD_MS ? elapsed : 0;
          cellPm.release();
          vkCallCount++;
          if (vkResult !== null) {
            vkDigit = vkResult;
            vkConsecutiveNull = 0;
            vkCropInfo = `VK=${vkResult}(${elapsed}ms)`;
          } else {
            if (cellRawInk > 0) {
              vkConsecutiveNull++;
            }
            vkCropInfo = `VK=null(${elapsed}ms)`;
          }
        } else {
          g_perCellVkDiag.cropFail++;
          vkCropInfo = 'cropFail';
        }
      } else {
        vkCropInfo = `tooSmall=${cW}x${cH}`;
      }
    }

    const pStr: string = pixelDigit !== null && pixelDigit > 0 ? `${pixelDigit}` : '-';
    const vStr: string = vkDigit !== null && vkDigit > 0 ? `${vkDigit}` : '-';
    const pixelConf: number = pixelDigit !== null && pixelDigit > 0 ? getLastConfidence() : 0;
    const rawInkRatio: number = getLastRawInkRatio();

    if (origDigit === 0) {
      let fillDigit: number | null = null;
      let fillSource: string = '';
      // Graduated pixel-ink gate: allow VK/Vretry/Vwide to fill empty cells when
      // the pixel path detected ANY ink (rawInkRatio > 0), even if the ink was
      // below the signature gate (MIN_CELL_INK_RATIO=0.025). INK_THRESH=50 already
      // filters noise, so rawInkRatio > 0 indicates real digit ink. This recovers
      // faint/thin/colored digits that cellSigFromGray rejects, while still blocking
      // VK on truly empty cells (rawInkRatio == 0) to prevent hallucinated fills.
      const pixelHasInk: boolean = pixelDigit !== null || rawInkRatio > 0;
      if (vkDigit !== null && vkDigit > 0 && pixelHasInk) {
        fillDigit = vkDigit;
        fillSource = 'V';
      } else if (pixelHasInk && vkInitOk && vkCallCount < vkMaxCalls && vkConsecutiveNull < VK_MAX_CONSECUTIVE_NULL &&
        vkSlowMs < VK_SLOW_CALL_THRESHOLD_MS * 3) {
        const retryPadW: number = Math.round(cellW * CELL_CROP_PAD_FACTOR_RETRY);
        const retryPadH: number = Math.round(cellH * CELL_CROP_PAD_FACTOR_RETRY);
        const rcX: number = Math.max(Math.floor(cellLeft - retryPadW), 0);
        const rcY: number = Math.max(Math.floor(cellTop - retryPadH), 0);
        const rcX2: number = Math.min(Math.floor(cellLeft + cellW + retryPadW), imgW);
        const rcY2: number = Math.min(Math.floor(cellTop + cellH + retryPadH), imgH);
        const rcW: number = rcX2 - rcX;
        const rcH: number = rcY2 - rcY;
        if (rcW >= MIN_CELL_CROP_DIM && rcH >= MIN_CELL_CROP_DIM) {
          const retryPm: image.PixelMap | null = cropCellFromBuffer(pixels, imgW, imgH, rcX, rcY, rcW, rcH, CELL_UPSCALE_FACTOR_RETRY);
          if (retryPm !== null) {
            const rt0: number = Date.now();
            const retryResult: number | null = await withTimeout<number | null>(
              recognizeDigitVisionKit(retryPm), PER_CELL_VK_TIMEOUT_MS, null
            );
            const rtElapsed: number = Date.now() - rt0;
            vkSlowMs = rtElapsed > VK_SLOW_CALL_THRESHOLD_MS ? rtElapsed : 0;
            retryPm.release();
            vkCallCount++;
            if (retryResult !== null) {
              vkDigit = retryResult;
              vkConsecutiveNull = 0;
              if (pixelHasInk) {
                fillDigit = retryResult;
                fillSource = `Vretry(${rtElapsed}ms)`;
              }
              vkCropInfo += ` Vretry=${retryResult}(${rtElapsed}ms)`;
            } else {
              vkConsecutiveNull++;
              vkCropInfo += ` Vretry=null(${rtElapsed}ms)`;
            }
          }
        }
      }
      if (fillDigit === null && pixelHasInk && vkInitOk && vkCallCount < vkMaxCalls &&
        vkConsecutiveNull < VK_MAX_CONSECUTIVE_NULL && vkSlowMs < VK_SLOW_CALL_THRESHOLD_MS * 3) {
        const widePadW: number = Math.round(cellW * WIDE_CELL_PAD_X_FACTOR);
        const widePadH: number = Math.round(cellH * WIDE_CELL_PAD_Y_FACTOR);
        const wideX: number = Math.max(Math.floor(cellLeft - widePadW), 0);
        const wideY: number = Math.max(Math.floor(cellTop - widePadH), 0);
        const wideX2: number = Math.min(Math.floor(cellLeft + cellW + widePadW), imgW);
        const wideY2: number = Math.min(Math.floor(cellTop + cellH + widePadH), imgH);
        const wideW: number = wideX2 - wideX;
        const wideH: number = wideY2 - wideY;
        if (wideW >= MIN_CELL_CROP_DIM && wideH >= MIN_CELL_CROP_DIM) {
          const widePm: image.PixelMap | null = cropCellFromBuffer(pixels, imgW, imgH, wideX, wideY, wideW, wideH, WIDE_CELL_UPSCALE_FACTOR);
          if (widePm !== null) {
            const wt0: number = Date.now();
            const wideResult: number | null = await withTimeout<number | null>(
              recognizeDigitInWideRegion(
                widePm, WIDE_CELL_UPSCALE_FACTOR,
                cellLeft - wideX, cellTop - wideY, cellW, cellH
              ), PER_CELL_VK_TIMEOUT_MS, null
            );
            const wtElapsed: number = Date.now() - wt0;
            vkSlowMs = wtElapsed > VK_SLOW_CALL_THRESHOLD_MS ? wtElapsed : 0;
            widePm.release();
            vkCallCount++;
            if (wideResult !== null) {
              vkDigit = wideResult;
              vkConsecutiveNull = 0;
              if (pixelHasInk) {
                fillDigit = wideResult;
                fillSource = `Vwide(${wtElapsed}ms)`;
              }
              vkCropInfo += ` Vwide=${wideResult}(${wtElapsed}ms)`;
            } else {
              vkConsecutiveNull++;
              vkCropInfo += ` Vwide=null(${wtElapsed}ms)`;
            }
          }
        }
      }
      if (fillDigit === null && pixelDigit !== null && pixelDigit > 0) {
        const emptyFillPixelConf: number = g_lastDebugRawDigits === 0 ? EMPTY_FILL_PIXEL_CONF_NO_RAW_DIGITS : EMPTY_FILL_PIXEL_CONF;
        if (rawInkRatio > 0.75) {
          fillDigit = null;
        } else if (pixelConf >= emptyFillPixelConf) {
          fillDigit = pixelDigit;
          fillSource = `P(conf=${pixelConf.toFixed(2)})`;
        } else if (pixelDigit === 1 && pixelConf >= 0.10) {
          if (rawInkRatio > 0.015 && rawInkRatio < 0.50) {
            fillDigit = 1;
            fillSource = `P_1_ink(ratio=${rawInkRatio.toFixed(4)})`;
          }
        }
      }
      if (fillDigit !== null) {
        grid[idx] = fillDigit;
        const newConflicts: number[] = findConflictCells(grid);
        const selfConflict: boolean = newConflicts.some((ci: number) => ci === idx);
        if (selfConflict) {
          grid[idx] = 0;
          let fallbackDigit: number | null = null;
          let fallbackSource: string = '';
          if (fillSource.startsWith('V') && pixelDigit !== null && pixelDigit > 0 && pixelDigit !== fillDigit) {
            grid[idx] = pixelDigit;
            const fbConflicts: number[] = findConflictCells(grid);
            const fbSelf: boolean = fbConflicts.some((ci: number) => ci === idx);
            if (!fbSelf) {
              fallbackDigit = pixelDigit;
              fallbackSource = `P_fb(V=${fillDigit}冲突)`;
            } else {
              grid[idx] = 0;
            }
          }
          if (fallbackDigit === null && fillDigit > 0) {
            const confusableSwaps: number[][] = [[6, 9], [9, 6], [5, 9], [9, 5], [5, 6], [6, 5], [5, 8], [8, 5], [1, 8], [8, 1], [1, 6], [6, 1], [7, 1], [1, 7], [2, 4], [4, 2], [3, 7], [7, 3]];
            for (const pair of confusableSwaps) {
              if (fillDigit === pair[0]) {
                grid[idx] = pair[1];
                const swConflicts: number[] = findConflictCells(grid);
                if (!swConflicts.some((ci: number) => ci === idx)) {
                  fallbackDigit = pair[1];
                  fallbackSource = `swap(${fillDigit}→${pair[1]})`;
                  break;
                }
                grid[idx] = 0;
              }
            }
          }
          if (fallbackDigit !== null) {
            fixCount++;
            hilog.info(DOMAIN, TAG, '【逐格修正详情】VK冲突回退Pixel %{public}s V=%{public}d冲突→P=%{public}d',
              cellLabel, fillDigit, fallbackDigit);
            fixDetailLines.push(`VK冲突回P${cellLabel} V=${fillDigit}冲突→P=${fallbackDigit} P=${pStr} crop=${vkCropInfo}`);
          } else {
            hilog.info(DOMAIN, TAG, '【逐格修正详情】填充冲突回退 %{public}s %{public}s=%{public}d',
              cellLabel, fillSource, fillDigit);
            fixDetailLines.push(`冲突回填${cellLabel} ${fillSource}=${fillDigit}冲突→留空 P=${pStr} crop=${vkCropInfo}`);
          }
        } else {
          hilog.info(DOMAIN, TAG, '【逐格修正详情】填充 %{public}s 空→%{public}d %{public}s',
            cellLabel, fillDigit, fillSource);
          fixCount++;
          fixDetailLines.push(`填充${cellLabel} 空→${fillDigit} ${fillSource} P=${pStr} V=${vStr} crop=${vkCropInfo}`);
        }
      } else {
        if (pixelHasInk) {
          hilog.info(DOMAIN, TAG, '【留空有墨】%{public}s P=%{public}s V=%{public}s rawInk=%{public}s crop=%{public}s',
            cellLabel, pStr, vStr, rawInkRatio.toFixed(4), vkCropInfo);
        } else if (vkDigit !== null && vkDigit > 0) {
          hilog.info(DOMAIN, TAG, '【VK无墨填充】%{public}s V=%{public}d P=%{public}s rawInk=%{public}s',
            cellLabel, vkDigit, pStr, rawInkRatio.toFixed(4));
        }
        if (rawInkRatio > 0.05 && vkDigit === null && (pixelDigit === null || pixelDigit === 0)) {
          fixDetailLines.push(`高墨VK全null${cellLabel} cell=(${cellLeft.toFixed(0)},${cellTop.toFixed(0)},${cellW.toFixed(0)}x${cellH.toFixed(0)}) board=(${boardL.toFixed(0)},${boardT.toFixed(0)}) probeBbox=(${g_probeBbox?.left},${g_probeBbox?.top}) fitted=(${g_fittedBoardL.toFixed(0)},${g_fittedBoardT.toFixed(0)}) cellSize=(${cellW.toFixed(1)}x${cellH.toFixed(1)})`);
        }
        fixDetailLines.push(`留空${cellLabel} V=${vStr} P=${pStr} ink=${pixelHasInk ? 1 : 0} rawInk=${rawInkRatio.toFixed(4)} pxDiag=[${pixelDiag}] crop=${vkCropInfo}`);
      }
      continue;
    }

    let finalDigit: number | null = null;
    let decision: string = '';
    const beforeConflicts: number = findConflictCells(grid).length;
    const origIsConflict: boolean = conflictIndices.some((ci: number) => ci === idx);
    if (pixelDigit !== null && pixelDigit > 0 && vkDigit !== null && vkDigit > 0) {
      if (pixelDigit === vkDigit) {
        finalDigit = pixelDigit;
        decision = 'P=V';
      } else {
        const pConflicts: number = conflictCountAfterSet(grid, idx, pixelDigit);
        const vConflicts: number = conflictCountAfterSet(grid, idx, vkDigit);
        if (vConflicts < pConflicts) {
          finalDigit = vkDigit;
          decision = `P≠V→V(pC=${pConflicts} vC=${vConflicts})`;
        } else if (pConflicts < vConflicts || pixelConf >= EXISTING_PIXEL_ONLY_OVERRIDE_CONF) {
          finalDigit = pixelDigit;
          decision = `P≠V→P(pC=${pConflicts} vC=${vConflicts} conf=${pixelConf.toFixed(2)})`;
        } else if (isConfusablePair(pixelDigit, vkDigit) && pixelConf < EXISTING_PIXEL_ONLY_OVERRIDE_CONF) {
          finalDigit = vkDigit;
          decision = `P≠V→V_confusable(pC=${pConflicts} vC=${vConflicts} conf=${pixelConf.toFixed(2)})`;
        } else {
          finalDigit = origDigit;
          decision = `P≠V→keep(pC=${pConflicts} vC=${vConflicts} conf=${pixelConf.toFixed(2)})`;
        }
      }
    } else if (pixelDigit !== null && pixelDigit > 0) {
      const pConflicts: number = conflictCountAfterSet(grid, idx, pixelDigit);
      const reducesConflict: boolean = pConflicts < beforeConflicts;
      const highConfidence: boolean = pixelConf >= EXISTING_PIXEL_ONLY_OVERRIDE_CONF;
      const likelyCorrection: boolean = isConfusablePair(origDigit, pixelDigit) || ocrResult.confidence === null || origIsConflict;
      const stableConfusableCorrection: boolean = beforeConflicts === 0 && g_lastDebugRawDigits > 0 &&
        ocrResult.confidence !== null && isConfusablePair(origDigit, pixelDigit) &&
        pixelConf >= STABLE_PIXEL_ONLY_OVERRIDE_CONF;
      const hasInk: boolean = rawInkRatio >= MIN_CELL_INK_RATIO;
      const allowLowInk: boolean = isConfusablePair(origDigit, pixelDigit);
      if ((hasInk || (allowLowInk && pixelConf >= 0.40)) && (reducesConflict || highConfidence || stableConfusableCorrection) && likelyCorrection) {
        finalDigit = pixelDigit;
        decision = `P_only(conf=${pixelConf.toFixed(2)} c=${beforeConflicts}→${pConflicts})`;
      } else if ((hasInk || (allowLowInk && pixelConf >= 0.40)) && likelyCorrection && beforeConflicts > 0 && pConflicts <= beforeConflicts + 1) {
        const candidate: PixelConflictCandidate = { idx: idx, digit: pixelDigit, confidence: pixelConf };
        pixelConflictCandidates.push(candidate);
        finalDigit = origDigit;
        decision = `P_only_pair(conf=${pixelConf.toFixed(2)} c=${beforeConflicts}→${pConflicts})`;
      } else {
        finalDigit = origDigit;
        decision = `P_only_keep(conf=${pixelConf.toFixed(2)} c=${beforeConflicts}→${pConflicts})`;
      }
    } else if (vkDigit !== null && vkDigit > 0) {
      if (origDigit > 0 && vkDigit !== origDigit && isConfusablePair(origDigit, vkDigit)) {
        const vConflicts: number = conflictCountAfterSet(grid, idx, vkDigit);
        const oConflicts: number = conflictCountAfterSet(grid, idx, origDigit);
        if (vConflicts < oConflicts) {
          finalDigit = vkDigit;
          decision = `V_only_confusable(c=${oConflicts}→${vConflicts})`;
        } else {
          finalDigit = origDigit;
          decision = `V_only_skip(V=${vkDigit} c=${oConflicts}→${vConflicts})`;
        }
      } else {
        finalDigit = vkDigit;
        decision = 'V_only';
      }
    }

    if (finalDigit !== null && finalDigit > 0 && finalDigit !== origDigit) {
      hilog.info(DOMAIN, TAG, '【逐格修正详情】修正 %{public}s %{public}d -> %{public}d', cellLabel, origDigit, finalDigit);
      grid[idx] = finalDigit;
      fixCount++;

      const newConflicts: number[] = findConflictCells(grid);
      const stillConflict: boolean = newConflicts.some((ci: number) => ci === idx);
      let swapNote: string = '';
      if (stillConflict && (finalDigit === 6 || finalDigit === 9)) {
        const swapped: number = finalDigit === 6 ? 9 : 6;
        grid[idx] = swapped;
        const afterSwap: number[] = findConflictCells(grid);
        const swapConflict: boolean = afterSwap.some((ci: number) => ci === idx);
        if (swapConflict) {
          grid[idx] = finalDigit;
          swapNote = ' 6/9交换仍冲突';
          hilog.info(DOMAIN, TAG, '【逐格修正详情】6/9翻转后仍冲突 保留%{public}d', finalDigit);
        } else {
          hilog.info(DOMAIN, TAG, '【逐格修正详情】6/9翻转 %{public}d -> %{public}d 冲突消除', finalDigit, swapped);
          swapNote = ` 6/9→${swapped}消除`;
        }
      }
      if (stillConflict && (finalDigit === 5 || finalDigit === 9)) {
        const swapped: number = finalDigit === 5 ? 9 : 5;
        grid[idx] = swapped;
        const afterSwap: number[] = findConflictCells(grid);
        const swapConflict: boolean = afterSwap.some((ci: number) => ci === idx);
        if (swapConflict) {
          grid[idx] = finalDigit;
          swapNote += ' 5/9交换仍冲突';
        } else {
          swapNote += ` 5/9→${swapped}消除`;
        }
      }
      if (stillConflict && (finalDigit === 5 || finalDigit === 6)) {
        const swapped: number = finalDigit === 5 ? 6 : 5;
        grid[idx] = swapped;
        const afterSwap: number[] = findConflictCells(grid);
        const swapConflict: boolean = afterSwap.some((ci: number) => ci === idx);
        if (swapConflict) {
          grid[idx] = finalDigit;
          swapNote += ' 5/6交换仍冲突';
        } else {
          swapNote += ` 5/6→${swapped}消除`;
        }
      }

      if (stillConflict && (finalDigit === 7 || finalDigit === 9)) {
        const swapped: number = finalDigit === 7 ? 9 : 7;
        grid[idx] = swapped;
        const afterSwap: number[] = findConflictCells(grid);
        const swapConflict: boolean = afterSwap.some((ci: number) => ci === idx);
        if (swapConflict) {
          grid[idx] = finalDigit;
          swapNote += ' 7/9交换仍冲突';
        } else {
          swapNote += ` 7/9→${swapped}消除`;
        }
      }



      fixDetailLines.push(`修正${cellLabel} ${origDigit}→${finalDigit} P=${pStr} V=${vStr} ${decision}${swapNote} pxDiag=[${pixelDiag}]`);
    } else if (finalDigit === null && (origDigit === 6 || origDigit === 9)) {
      const isConflict: boolean = conflictIndices.some((ci: number) => ci === idx);
      if (isConflict && rawInkRatio < MIN_CELL_INK_RATIO && pixelDigit === null) {
        grid[idx] = 0;
        fixCount++;
        hilog.info(DOMAIN, TAG, '【逐格修正详情】冲突无墨清除 %{public}s %{public}d→0', cellLabel, origDigit);
        fixDetailLines.push(`清除${cellLabel} ${origDigit}→0 P=${pStr} V=${vStr} 冲突无墨 pxDiag=[${pixelDiag}]`);
      } else if (isConflict && rawInkRatio >= MIN_CELL_INK_RATIO) {
        const swapped: number = origDigit === 6 ? 9 : 6;
        grid[idx] = swapped;
        const afterSwap: number[] = findConflictCells(grid);
        const swapConflict: boolean = afterSwap.some((ci: number) => ci === idx);
        if (swapConflict) {
          grid[idx] = origDigit;
          fixDetailLines.push(`不变${cellLabel}=${origDigit} P=${pStr} V=${vStr} ${decision} 6/9冲突交换失败 pxDiag=[${pixelDiag}]`);
        } else {
          fixCount++;
          hilog.info(DOMAIN, TAG, '【逐格修正详情】6/9冲突交换 %{public}s %{public}d -> %{public}d', cellLabel, origDigit, swapped);
          fixDetailLines.push(`修正${cellLabel} ${origDigit}→${swapped} P=${pStr} V=${vStr} 冲突6/9交换 pxDiag=[${pixelDiag}]`);
        }
      } else {
        fixDetailLines.push(`不变${cellLabel}=${origDigit} P=${pStr} V=${vStr} ${decision} pxDiag=[${pixelDiag}]`);
      }
    } else if (finalDigit === null && origDigit > 0) {
      const isConflict: boolean = conflictIndices.some((ci: number) => ci === idx);
      if (isConflict && rawInkRatio < MIN_CELL_INK_RATIO && pixelDigit === null) {
        grid[idx] = 0;
        fixCount++;
        hilog.info(DOMAIN, TAG, '【逐格修正详情】冲突无墨清除 %{public}s %{public}d→0', cellLabel, origDigit);
        fixDetailLines.push(`清除${cellLabel} ${origDigit}→0 P=${pStr} V=${vStr} 冲突无墨 pxDiag=[${pixelDiag}]`);
      } else if (isConflict && rawInkRatio >= MIN_CELL_INK_RATIO) {
        let swappedOk: boolean = false;
        let swapDigit: number = origDigit;
        const confusableSwaps: number[][] = [[5, 9], [9, 5], [5, 6], [6, 5], [7, 9], [9, 7]];
        for (const pair of confusableSwaps) {
          if (origDigit === pair[0]) {
            grid[idx] = pair[1];
            const afterSwap: number[] = findConflictCells(grid);
            if (!afterSwap.some((ci: number) => ci === idx)) {
              swapDigit = pair[1];
              swappedOk = true;
              break;
            }
            grid[idx] = origDigit;
          }
        }
        if (swappedOk) {
          fixCount++;
          hilog.info(DOMAIN, TAG, '【逐格修正详情】冲突交换 %{public}s %{public}d -> %{public}d', cellLabel, origDigit, swapDigit);
          fixDetailLines.push(`修正${cellLabel} ${origDigit}→${swapDigit} P=${pStr} V=${vStr} 冲突交换 pxDiag=[${pixelDiag}]`);
        } else {
          fixDetailLines.push(`不变${cellLabel}=${origDigit} P=${pStr} V=${vStr} ${decision} 冲突交换失败 pxDiag=[${pixelDiag}]`);
        }
      } else {
        fixDetailLines.push(`不变${cellLabel}=${origDigit} P=${pStr} V=${vStr} ${decision} pxDiag=[${pixelDiag}]`);
      }
    } else {
      fixDetailLines.push(`不变${cellLabel}=${origDigit} P=${pStr} V=${vStr} ${decision} pxDiag=[${pixelDiag}]`);
    }
    if (col === 8) { await yieldThread(); }
  }

  const pairFixDetail: string = applyBestPixelConflictPair(grid, pixelConflictCandidates);
  if (pairFixDetail.length > 0) {
    fixCount += 2;
    fixDetailLines.push(pairFixDetail);
  }

  // After pair fix resolved conflicts, apply remaining 6/9 pixel-conflict candidates
  // that are conflict-free. These are cells where pixel detected 9 but grid has 6 (or
  // vice versa) with moderate confidence, skipped earlier because they didn't reduce
  // conflicts as a pair. With conflicts now resolved, a standalone 6/9 swap that
  // introduces no new conflict is safe.
  const remainingCandidates: PixelConflictCandidate[] = [];
  for (const cand of pixelConflictCandidates) {
    if (grid[cand.idx] === cand.digit) { continue; }
    if (!isConfusablePair(grid[cand.idx], cand.digit)) { continue; }
    const gv: number = grid[cand.idx];
    const only69: boolean = (gv === 6 && cand.digit === 9) || (gv === 9 && cand.digit === 6);
    if (!only69 && cand.confidence < EXISTING_PIXEL_ONLY_OVERRIDE_CONF) { continue; }
    remainingCandidates.push(cand);
  }
  if (remainingCandidates.length > 0) {
    remainingCandidates.sort((a: PixelConflictCandidate, b: PixelConflictCandidate): number => {
      return b.confidence - a.confidence;
    });
    for (const rc of remainingCandidates) {
      const origVal: number = grid[rc.idx];
      grid[rc.idx] = rc.digit;
      const afterConflicts: number[] = findConflictCells(grid);
      const selfConflict: boolean = afterConflicts.some((ci: number) => ci === rc.idx);
      if (!selfConflict) {
        fixCount++;
        const rcRow: number = Math.floor(rc.idx / 9);
        const rcCol: number = rc.idx % 9;
        hilog.info(DOMAIN, TAG, '【逐格修正详情】剩余6/9修正 (%{public}d,%{public}d) %{public}d→%{public}d conf=%{public}.2f',
          rcRow, rcCol, origVal, rc.digit, rc.confidence);
        fixDetailLines.push(`剩余6/9修正(${rcRow},${rcCol}) ${origVal}→${rc.digit} conf=${rc.confidence.toFixed(2)}`);
      } else {
        grid[rc.idx] = origVal;
      }
    }
  }

  // 加入逐格VK诊断摘要
  const diag: PerCellVkDiag = g_perCellVkDiag;
  const diagTotal: number = diag.cropFail + diag.noBlock + diag.noCenter + diag.found;
  hilog.info(DOMAIN, TAG, '【逐格VK诊断】尝试%{public}d次 成功%{public}d 裁剪失败%{public}d 无block%{public}d 无中心%{public}d',
    diagTotal, diag.found, diag.cropFail, diag.noBlock, diag.noCenter);
  if (diagTotal > 0) {
    const diagLines: string[] = [];
    diagLines.push(`【逐格VK诊断】尝试${diagTotal}次 成功${diag.found} 裁剪失败${diag.cropFail} 无block${diag.noBlock} 无中心${diag.noCenter}`);
    if (diag.samples.length > 0) {
      diagLines.push(`  样本: ${diag.samples.join(' | ')}`);
    }
    fixDetailLines.unshift(diagLines.join('\n'), '');
  }
  g_lastDebugFixDetails = fixDetailLines.join('\n');
  for (let fi: number = 0; fi < fixDetailLines.length; fi += 10) {
    const chunkEnd: number = Math.min(fi + 10, fixDetailLines.length);
    hilog.info(DOMAIN, TAG, '【逐格修正详情】%{public}d-%{public}d/%{public}d %{public}s',
      fi, chunkEnd - 1, fixDetailLines.length,
      fixDetailLines.slice(fi, chunkEnd).join(' | '));
  }

  hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 循环结束 fixCount=%{public}d', fixCount);

  if (gray.length > 0) {
    let pixelAdjFixCount: number = 0;
    for (let i: number = 0; i < 81; i++) {
      if (grid[i] === 0) { continue; }
      await yieldThread();
      const row: number = Math.floor(i / 9);
      const col: number = i % 9;
      const cLeft: number = boardL + col * cellW;
      const cTop: number = boardT + row * cellH;
      const pixelDigit: number | null = recognizeDigitPixel(gray, imgW, cLeft, cTop, cellW, cellH, bbox.isDark, bg, row, col);
      if (pixelDigit === null || pixelDigit === grid[i]) { continue; }
      if (!isConfusablePair(grid[i], pixelDigit)) { continue; }
      const pixelConf: number = getLastConfidence();
      const isConflict: boolean = findConflictCells(grid).some((ci: number) => ci === i);
      if (isConflict) {
        const beforeConflicts: number = findConflictCells(grid).length;
        const orig: number = grid[i];
        grid[i] = pixelDigit;
        const afterConflicts: number = findConflictCells(grid).length;
        if (afterConflicts < beforeConflicts) {
          hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 像素裁决(冲突) [%{public}d]=%{public}d→%{public}d 冲突%{public}d→%{public}d',
            i, orig, pixelDigit, beforeConflicts, afterConflicts);
          pixelAdjFixCount++;
        } else {
          grid[i] = orig;
        }
      } else if (pixelConf >= CONFUSABLE_PIXEL_OVERRIDE_CONF && pixelConf >= EXISTING_PIXEL_ONLY_OVERRIDE_CONF) {
        const orig: number = grid[i];
        grid[i] = pixelDigit;
        const cellStillInConflict: boolean = findConflictCells(grid).some((ci: number) => ci === i);
        if (!cellStillInConflict) {
          hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 像素裁决(置信%{public}.2f) [%{public}d]=%{public}d→%{public}d',
            pixelConf, i, orig, pixelDigit);
          pixelAdjFixCount++;
        } else {
          grid[i] = orig;
        }
      }
    }
    if (pixelAdjFixCount > 0) {
      fixCount += pixelAdjFixCount;
      hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 像素裁决修正%{public}d个', pixelAdjFixCount);
    }
  }

  let remainingConflicts: number[] = findConflictCells(grid);
  const conflictGuessSwaps: number[][] = [
    [6, 9], [9, 6], [5, 9], [9, 5], [5, 6], [6, 5],
    [5, 8], [8, 5], [1, 8], [8, 1], [1, 6], [6, 1],
    [7, 1], [1, 7], [2, 4], [4, 2], [3, 7], [7, 3],
    [1, 4], [4, 1], [2, 8], [8, 2], [3, 8], [8, 3],
    [7, 9], [9, 7], [4, 9], [9, 4], [3, 5], [5, 3],
  ];
  let guessFixCount: number = 0;
  for (const ci of remainingConflicts) {
    await yieldThread();
    const origVal: number = grid[ci];
    if (origVal === 0) { continue; }
    const beforeConflicts: number = findConflictCells(grid).length;
    for (const pair of conflictGuessSwaps) {
      if (origVal === pair[0]) {
        grid[ci] = pair[1];
        const afterSwap: number[] = findConflictCells(grid);
        if (afterSwap.length < beforeConflicts && !afterSwap.some((ac: number) => ac === ci)) {
          guessFixCount++;
          hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 冲突猜测交换(%{public}d,%{public}d) %{public}d→%{public}d 冲突%{public}d→%{public}d',
            Math.floor(ci / 9), ci % 9, origVal, pair[1], beforeConflicts, afterSwap.length);
          break;
        }
        grid[ci] = origVal;
      }
    }
  }
  if (guessFixCount > 0) {
    fixCount += guessFixCount;
    hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 冲突猜测交换修正%{public}d个', guessFixCount);
  }

  remainingConflicts = findConflictCells(grid);
  const finalClearNoInk: number[] = [];
  for (const ci of remainingConflicts) {
    await yieldThread();
    const ciRow: number = Math.floor(ci / 9);
    const ciCol: number = ci % 9;
    const ciLeft: number = boardL + ciCol * cellW;
    const ciTop: number = boardT + ciRow * cellH;
    const ciDigit: number | null = recognizeDigitPixel(gray, imgW, ciLeft, ciTop, cellW, cellH, bbox.isDark, bg, ciRow, ciCol);
    const ciInk: number = getLastRawInkRatio();
    if (ciDigit === null && ciInk < MIN_CELL_INK_RATIO) {
      finalClearNoInk.push(ci);
    } else if (ciInk > 0.75) {
      finalClearNoInk.push(ci);
    }
  }
  if (finalClearNoInk.length > 0) {
    for (const ci of finalClearNoInk) {
      const origVal: number = grid[ci];
      grid[ci] = 0;
      hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 最终冲突无墨清除(%{public}d,%{public}d) %{public}d→0',
        Math.floor(ci / 9), ci % 9, origVal);
    }
    fixCount += finalClearNoInk.length;
    remainingConflicts = findConflictCells(grid);
  }

  let conflictSwapRounds: number = 0;
  while (remainingConflicts.length > 0 && conflictSwapRounds < 3) {
    conflictSwapRounds++;
    let swappedAny: boolean = false;
    for (const ci of remainingConflicts) {
      await yieldThread();
      const origVal: number = grid[ci];
      if (origVal === 0) { continue; }
      const confusableSwaps: number[][] = [[6, 9], [9, 6], [5, 9], [9, 5], [5, 6], [6, 5], [5, 8], [8, 5], [1, 8], [8, 1], [1, 6], [6, 1], [7, 1], [1, 7], [2, 4], [4, 2], [3, 7], [7, 3], [1, 4], [4, 1], [2, 8], [8, 2], [3, 8], [8, 3], [7, 9], [9, 7], [4, 9], [9, 4], [3, 5], [5, 3]];
      for (const pair of confusableSwaps) {
        if (origVal === pair[0]) {
          grid[ci] = pair[1];
          const afterSwap: number[] = findConflictCells(grid);
          if (afterSwap.length < remainingConflicts.length && !afterSwap.some((ac: number) => ac === ci)) {
            fixCount++;
            const r: number = Math.floor(ci / 9);
            const c: number = ci % 9;
            hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 最终冲突交换(%{public}d,%{public}d) %{public}d→%{public}d 冲突%{public}d→%{public}d',
              r, c, origVal, pair[1], remainingConflicts.length, afterSwap.length);
            swappedAny = true;
            break;
          }
          grid[ci] = origVal;
        }
      }
      if (swappedAny) { break; }
    }
    if (!swappedAny) { break; }
    remainingConflicts = findConflictCells(grid);
  }

  if (remainingConflicts.length > 0 && gray.length > 0) {
    const lowConfClear: number[] = [];
    for (const ci of remainingConflicts) {
      await yieldThread();
      const ciRow: number = Math.floor(ci / 9);
      const ciCol: number = ci % 9;
      const ciLeft: number = boardL + ciCol * cellW;
      const ciTop: number = boardT + ciRow * cellH;
      const ciConf: number = g_lastPixelConfidence[ci];
      recognizeDigitPixel(gray, imgW, ciLeft, ciTop, cellW, cellH, bbox.isDark, bg, ciRow, ciCol);
      const ciRawInk: number = getLastRawInkRatio();
      if (ciConf < 0.50 || ciRawInk > 0.75) {
        lowConfClear.push(ci);
      }
    }
    for (const ci of lowConfClear) {
      const origVal: number = grid[ci];
      grid[ci] = 0;
      hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 冲突低置信清除(%{public}d,%{public}d) %{public}d→0 conf=%{public}.2f',
        Math.floor(ci / 9), ci % 9, origVal, g_lastPixelConfidence[ci]);
    }
    if (lowConfClear.length > 0) {
      fixCount += lowConfClear.length;
      remainingConflicts = findConflictCells(grid);
    }
  }

  if (remainingConflicts.length > 0) {
    hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 最终冲突%{public}d个(无法交换)', remainingConflicts.length);
  }

  if (pixelMap !== null) {
    pixelMap.release();
  }

  g_lastDebugConflicts = conflictIndices;
  g_lastDebugLowConf = lowConfIndices;
  g_lastDebugEmpty = emptyIndices;
  g_lastDebugFixCount = fixCount;

  if (fixCount > 0) {
    hilog.info(DOMAIN, TAG, '【实际修正】修正了%{public}d个格子', fixCount);
    return { success: true, grid: grid, rawText: ocrResult.rawText + '+conflictFix', error: '', confidence: ocrResult.confidence, debugInfo: null };
  }
  return ocrResult;
}

async function tryVisionKitRecognition(imagePath: string, imageBuf: ArrayBuffer | null = null): Promise<OCRResult> {
  let pixelMap: image.PixelMap | null = null;
  g_lastDebugVkRawText = '';
  g_lastDebugVkBlockCount = 0;
  g_lastDebugVkOcrSize = '';
  g_lastDebugVkOcrError = '';
  g_lastDebugProbeInfo = '';
  if (g_vkFailed) {
    hilog.warn(DOMAIN, TAG, 'VK: skip (g_vkFailed=true)');
    g_lastDebugVkOcrError = 'VK previously failed, skipped';
    return { success: false, grid: null, rawText: '', error: 'VisionKit skipped (previous failure)', confidence: null, debugInfo: null };
  }
  try {
    hilog.info(DOMAIN, TAG, 'VK: await textRecognition.init()');
    hilog.info(DOMAIN, TAG, 'VK: await textRecognition.init()');
    const initOk: boolean = await withTimeout<boolean>(textRecognition.init(), 5000, false);
    hilog.info(DOMAIN, TAG, 'VK: init() returned %{public}d', initOk ? 1 : 0);
    hilog.info(DOMAIN, TAG, 'VK: init() 返回 %{public}d', initOk ? 1 : 0);
    g_vkInited = initOk;
    if (!initOk) {
      g_lastDebugVkOcrError = 'VisionKit init() returned false';
      return { success: false, grid: null, rawText: '', error: 'VisionKit init failed', confidence: null, debugInfo: null };
    }

    const imageSource: image.ImageSource = imageBuf !== null ? openImageSourceFromBuffer(imageBuf) : openImageSource(imagePath);
    hilog.info(DOMAIN, TAG, 'VK: await imageSource.getImageInfo()');
    const srcInfo: image.ImageInfo = await withTimeout<image.ImageInfo>(imageSource.getImageInfo(), 5000,
      { size: { width: 0, height: 0 } } as image.ImageInfo);
    const origW: number = srcInfo.size.width;
    const origH: number = srcInfo.size.height;

    const resize: AdaptiveResizeParams = computeAdaptiveResize(origW, origH);
    const probeW: number = resize.targetW;
    const probeH: number = resize.targetH;

    const probePm: image.PixelMap | null = await withTimeout<image.PixelMap | null>(imageSource.createPixelMap({
      desiredSize: { width: probeW, height: probeH },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    }), 5000, null);
    hilog.info(DOMAIN, TAG, 'VK: createPixelMap(probe) 返回 %{public}s', probePm !== null ? 'OK' : 'null');
    if (probePm === null) {
      imageSource.release();
      g_lastDebugVkOcrError = 'createPixelMap(probe)超时';
      return { success: false, grid: null, rawText: '', error: 'createPixelMap超时', confidence: null, debugInfo: null };
    }
    const probeImgInfo: image.ImageInfo = await probePm.getImageInfo();
    const probeImgW: number = probeImgInfo.size.width;
    const probeImgH: number = probeImgInfo.size.height;

    const probeBuf: ArrayBuffer = new ArrayBuffer(probeImgW * probeImgH * 4);
    probePm.readPixelsToBuffer(probeBuf);
    const probePixels: Uint8Array = new Uint8Array(probeBuf);
    probePm.release();

    g_cachedPixels = probePixels;
    g_cachedImgW = probeImgW;
    g_cachedImgH = probeImgH;

    const bg: number = bgColor(probePixels, probeImgW, probeImgH);
    const isDark: boolean = bg < BG_DARK_THRESHOLD;
    const bbox: BoardBBox = findBoardBBox(probePixels, probeImgW, probeImgH, bg);
    const boardW: number = bbox.right - bbox.left;
    const boardH: number = bbox.bottom - bbox.top;
    const cellW: number = boardW / 9;
    const cellH: number = boardH / 9;
    const isFullImage: boolean = bbox.left === 0 && bbox.top === 0 &&
      bbox.right === probeImgW && bbox.bottom === probeImgH;
    // 保存探测 bbox，供 fixAndFillGrid 复用确保 cell 定位一致
    g_probeBbox = { left: bbox.left, top: bbox.top, right: bbox.right, bottom: bbox.bottom, isDark: bbox.isDark };
    g_probeResizeW = probeImgW;
    g_probeResizeH = probeImgH;
    const bgHist: number[] = new Array<number>(256).fill(0);
    const bgSampleStep: number = Math.max(1, Math.floor(probeImgW * probeImgH / 20000));
    let bgMin: number = 255;
    let bgMax: number = 0;
    for (let i: number = 0; i < probeImgW * probeImgH; i += bgSampleStep) {
      const g: number = Math.floor(0.299 * probePixels[i * 4] + 0.587 * probePixels[i * 4 + 1] + 0.114 * probePixels[i * 4 + 2]);
      if (g >= 0 && g <= 255) { bgHist[g]++; }
      if (g < bgMin) { bgMin = g; }
      if (g > bgMax) { bgMax = g; }
    }
    let bgHistTop3: string = '';
    let tmpMax: number = -1;
    for (let pass: number = 0; pass < 3; pass++) {
      let topI: number = 0;
      let topV: number = 0;
      for (let i: number = 0; i < 256; i++) {
        if (bgHist[i] > topV && bgHist[i] > 0) {
          let already: boolean = false;
          for (const ch of bgHistTop3) {
          }
          topV = bgHist[i];
          topI = i;
        }
      }
      if (topV > 0) {
        bgHistTop3 += (bgHistTop3.length > 0 ? ', ' : '') + `${topI}(${topV})`;
        bgHist[topI] = 0;
      }
    }
    const boardAreaRatio: number = (boardW * boardH) / (probeImgW * probeImgH);
    const boardAspect: number = boardH > 0 ? boardW / boardH : 0;

    g_lastDebugProbeInfo = `实际探测图=${probeImgW}x${probeImgH} bg=${bg.toFixed(1)} isDark=${isDark ? 1 : 0} bgRange=[${bgMin},${bgMax}] bgHistTop3=[${bgHistTop3}]`;
    g_lastDebugBbox = `原图${origW}x${origH}→探测${probeImgW}x${probeImgH} bbox=[${bbox.left},${bbox.top},${bbox.right},${bbox.bottom}] board=${boardW}x${boardH} cell=${cellW.toFixed(1)}x${cellH.toFixed(1)} isDark=${bbox.isDark ? 1 : 0} isFullImageFallback=${isFullImage ? 1 : 0} areaRatio=${boardAreaRatio.toFixed(3)} aspect=${boardAspect.toFixed(2)}`;
    g_lastDebugResize = `resize: ${origW}x${origH} → ${resize.targetW}x${resize.targetH} targetCellPx=${resize.targetCellPx}`;

    hilog.info(DOMAIN, TAG, '【探测图详情】%{public}s', g_lastDebugProbeInfo);
    hilog.info(DOMAIN, TAG, '【图片与棋盘】%{public}s', g_lastDebugBbox);

    if (isFullImage) {
      hilog.warn(DOMAIN, TAG, 'VisionKit: 警告 - findBoardBBox返回全图退化bbox，棋盘定位可能失败');
    }

    const TARGET_CELL_PX_LOCAL: number = resize.targetCellPx;
    const boardScale: number = TARGET_CELL_PX_LOCAL / Math.min(cellW, cellH);
    const cropL: number = Math.max(Math.floor(bbox.left - boardW * BOARD_CROP_PAD_RATIO), 0);
    const cropT: number = Math.max(Math.floor(bbox.top - boardH * BOARD_CROP_PAD_RATIO), 0);
    const cropR: number = Math.min(Math.floor(bbox.right + boardW * BOARD_CROP_PAD_RATIO), probeImgW);
    const cropB: number = Math.min(Math.floor(bbox.bottom + boardH * BOARD_CROP_PAD_RATIO), probeImgH);
    const cropW: number = cropR - cropL;
    const cropH: number = cropB - cropT;

    const targetW: number = Math.round(cropW * boardScale);
    const targetH: number = Math.round(cropH * boardScale);
    const maxDim: number = OCR_MAX_DIM;
    let finalW: number = targetW;
    let finalH: number = targetH;
    if (finalW > maxDim || finalH > maxDim) {
      const ms: number = maxDim / Math.max(finalW, finalH);
      finalW = Math.round(finalW * ms);
      finalH = Math.round(finalH * ms);
    }
    const minDim: number = OCR_MIN_DIM;
    if (Math.min(finalW, finalH) < minDim) {
      const ms2: number = minDim / Math.min(finalW, finalH);
      finalW = Math.round(finalW * ms2);
      finalH = Math.round(finalH * ms2);
    }

    hilog.info(DOMAIN, TAG, '【缩放参数】探测图%{public}dx%{public}d 棋盘[%{public}d,%{public}d,%{public}d,%{public}d] 每格=%{public}.1f 放大=%{public}.2f clip->target %{public}dx%{public}d',
      probeImgW, probeImgH, bbox.left, bbox.top, bbox.right, bbox.bottom,
      Math.min(cellW, cellH), boardScale, finalW, finalH);

    // cropL/cropT/cropW/cropH 基于探测图（probeImgW×probeImgH）坐标，但 imageSource 是原始大图。
    // 必须将裁剪坐标缩放到原始图像空间，否则裁剪区域只有正确范围的 1/scale 大小。
    const probeToOrigScaleX: number = origW / probeImgW;
    const probeToOrigScaleY: number = origH / probeImgH;
    const origCropL: number = Math.round(cropL * probeToOrigScaleX);
    const origCropT: number = Math.round(cropT * probeToOrigScaleY);
    const origCropW: number = Math.round(cropW * probeToOrigScaleX);
    const origCropH: number = Math.round(cropH * probeToOrigScaleY);

    hilog.info(DOMAIN, TAG, '【缩放参数】probe→orig scaleX=%{public}.2f scaleY=%{public}.2f crop(...)->orig(%{public}d,%{public}d,%{public}d,%{public}d)',
      probeToOrigScaleX, probeToOrigScaleY, origCropL, origCropT, origCropW, origCropH);

    pixelMap = await withTimeout<image.PixelMap | null>(imageSource.createPixelMap({
      desiredRegion: { size: { width: origCropW, height: origCropH }, x: origCropL, y: origCropT },
      desiredSize: { width: finalW, height: finalH },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST
    }), 5000, null);
    imageSource.release();

    if (pixelMap === null) {
      g_lastDebugVkOcrError = 'createPixelMap(OCR)超时';
      return { success: false, grid: null, rawText: '', error: 'createPixelMap超时', confidence: null, debugInfo: null };
    }

    const imageInfo: image.ImageInfo = await pixelMap.getImageInfo();
    const imgW: number = imageInfo.size.width;
    const imgH: number = imageInfo.size.height;
    g_lastDebugVkOcrSize = `${imgW}x${imgH}`;
    hilog.info(DOMAIN, TAG, '【VisionKit OCR图尺寸】%{public}dx%{public}d', imgW, imgH);

    // Pre-process: soft contrast stretch on ink-intensity before VK recognition.
    // Instead of hard binarization (which creates jagged artifacts that VK
    // misreads as letters like "M"), we compute per-pixel ink intensity and
    // apply a smooth contrast curve. This makes colored digits (red, green,
    // blue) consistently dark on a white background, without harsh edges.
    const ocrBuf: ArrayBuffer = new ArrayBuffer(imgW * imgH * 4);
    pixelMap.readPixelsToBuffer(ocrBuf);
    const ocrPx: Uint8Array = new Uint8Array(ocrBuf);
    let ocrBgSum: number = 0;
    const ocrBgStep: number = Math.max(1, Math.floor(imgW * imgH / 10000));
    let ocrBgCnt: number = 0;
    for (let i: number = 0; i < imgW * imgH; i += ocrBgStep) {
      ocrBgSum += Math.floor(0.299 * ocrPx[i * 4] + 0.587 * ocrPx[i * 4 + 1] + 0.114 * ocrPx[i * 4 + 2]);
      ocrBgCnt++;
    }
    const ocrBg: number = ocrBgCnt > 0 ? ocrBgSum / ocrBgCnt : 128;
    for (let i: number = 0; i < imgW * imgH; i++) {
      const rv: number = ocrPx[i * 4];
      const gv: number = ocrPx[i * 4 + 1];
      const bv: number = ocrPx[i * 4 + 2];
      const gray: number = 0.299 * rv + 0.587 * gv + 0.114 * bv;
      const ink: number = ocrBg >= 128
        ? Math.max(0, (ocrBg - gray) / ocrBg)
        : Math.max(0, (gray - ocrBg) / (255 - ocrBg));
      // Soft contrast stretch: ink 0→1 maps to pixel 255→0 via a smooth S-curve.
      // Low ink (<0.1) → near-white, high ink (>0.3) → near-black, smooth transition.
      const contrastInk: number = Math.min(1, Math.max(0, (ink - 0.1) / 0.2));
      const outVal: number = Math.round(255 * (1 - contrastInk));
      ocrPx[i * 4] = outVal;
      ocrPx[i * 4 + 1] = outVal;
      ocrPx[i * 4 + 2] = outVal;
    }
    const destArea: image.PositionArea = {
      pixels: ocrBuf,
      offset: 0,
      stride: imgW * 4,
      region: { size: { width: imgW, height: imgH }, x: 0, y: 0 }
    };
    pixelMap.writePixelsSync(destArea);
    hilog.info(DOMAIN, TAG, '【VisionKit预处理】软对比度拉伸 ocrBg=%{public}.1f', ocrBg);

    const visionInfo: textRecognition.VisionInfo = { pixelMap: pixelMap };
    hilog.info(DOMAIN, TAG, 'VK: await recognizeText() main OCR');
    hilog.info(DOMAIN, TAG, 'VK: await recognizeText() 主识别');
    const recogResult: textRecognition.TextRecognitionResult =
      await withTimeout<textRecognition.TextRecognitionResult>(
        textRecognition.recognizeText(visionInfo, {
          isDirectionDetectionSupported: true
        }), 10000,
        { value: '', blocks: [] } as textRecognition.TextRecognitionResult
      );
    hilog.info(DOMAIN, TAG, 'VK: recognizeText() blocks=%{public}d', (recogResult.blocks || []).length);
    hilog.info(DOMAIN, TAG, 'VK: recognizeText() 返回 blocks=%{public}d', (recogResult.blocks || []).length);

    // 不释放 VK，留给 fixAndFillGrid 复用
    // await textRecognition.release();

    const rawText: string = recogResult.value || '';
    const vkBlocks: Array<textRecognition.TextBlock> = recogResult.blocks || [];
    g_lastDebugVkRawText = rawText.substring(0, 500);
    g_lastDebugVkBlockCount = vkBlocks.length;
    hilog.info(DOMAIN, TAG, '【VisionKit原始文本】(%{public}d chars) "%{public}s"', rawText.length, rawText.substring(0, 200));
    hilog.info(DOMAIN, TAG, '【VisionKit Block数】%{public}d', vkBlocks.length);

    let vkLineCount: number = 0;
    let vkWordCount: number = 0;
    let vkDigitWordCount: number = 0;
    let vkBlockDetails: string = '';
    for (let bi: number = 0; bi < vkBlocks.length; bi++) {
      const block: textRecognition.TextBlock = vkBlocks[bi];
      const lines: Array<textRecognition.TextLine> = block.lines || [];
      vkLineCount += lines.length;
      for (let li: number = 0; li < lines.length; li++) {
        const line: textRecognition.TextLine = lines[li];
        const words: Array<textRecognition.TextWord> = line.words || [];
        vkWordCount += words.length;
        for (let wi: number = 0; wi < words.length; wi++) {
          const word: textRecognition.TextWord = words[wi];
          const hasDigit: boolean = new RegExp('[0-9]').test(word.value);
          if (hasDigit) { vkDigitWordCount++; }
          if (vkBlockDetails.length < 2000) {
            const cp: Array<textRecognition.PixelPoint> = word.cornerPoints;
            let posStr: string = '';
            if (cp.length >= 4) {
              const cx: number = Math.round((cp[0].x + cp[1].x + cp[2].x + cp[3].x) / 4);
              const cy: number = Math.round((cp[0].y + cp[1].y + cp[2].y + cp[3].y) / 4);
              posStr = ` xy=(${cx},${cy})`;
            }
            vkBlockDetails += `B${bi}L${li}W${wi}="${word.value}" cp=${cp.length}${posStr}`;
            if (wi < words.length - 1) { vkBlockDetails += ' | '; }
          }
        }
      }
      if (bi < vkBlocks.length - 1 && vkBlockDetails.length < 2000) { vkBlockDetails += '\n'; }
    }
    hilog.info(DOMAIN, TAG, '【VisionKit Block详情】blocks=%{public}d lines=%{public}d words=%{public}d digitWords=%{public}d\n%{public}s',
      vkBlocks.length, vkLineCount, vkWordCount, vkDigitWordCount, vkBlockDetails);
    g_lastDebugVkBlockDetail = vkBlockDetails;
    g_lastDebugVkOcrError = vkBlocks.length === 0 ? 'blocks为空，VisionKit未检测到任何文字' : (vkDigitWordCount === 0 ? `有${vkBlocks.length}个block但无数字word` : '');

    const cropToOcrScaleX: number = imgW / cropW;
    const cropToOcrScaleY: number = imgH / cropH;
    // 记录位置映射参数，方便调试定位偏差
    const mapL: number = (bbox.left - cropL) * cropToOcrScaleX;
    const mapT: number = (bbox.top - cropT) * cropToOcrScaleY;
    const mapR: number = (bbox.right - cropL) * cropToOcrScaleX;
    const mapB: number = (bbox.bottom - cropT) * cropToOcrScaleY;
    const mapCellW: number = (mapR - mapL) / 9;
    const mapCellH: number = (mapB - mapT) / 9;
    g_lastDebugVkOcrSize += ` boardOcr=[${mapL.toFixed(0)},${mapT.toFixed(0)},${mapR.toFixed(0)},${mapB.toFixed(0)}] cellOcr=${mapCellW.toFixed(1)}x${mapCellH.toFixed(1)}`;
    const posResult: VisionKitGridResult | null = buildGridByPosition(
      recogResult, imgW, imgH, bbox, cropL, cropT, cropToOcrScaleX, cropToOcrScaleY
    );
    if (posResult !== null) {
      const fittedL: number = posResult.boardL / cropToOcrScaleX + cropL;
      const fittedT: number = posResult.boardT / cropToOcrScaleY + cropT;
      const fittedR: number = (posResult.boardL + posResult.boardW) / cropToOcrScaleX + cropL;
      const fittedB: number = (posResult.boardT + posResult.boardH) / cropToOcrScaleY + cropT;
      g_fittedBoardL = fittedL;
      g_fittedBoardT = fittedT;
      g_fittedBoardR = fittedR;
      g_fittedBoardB = fittedB;
      hilog.info(DOMAIN, TAG, '【VisionKit Block详情】fittedBoard detect=[%{public}.1f,%{public}.1f,%{public}.1f,%{public}.1f]',
        fittedL, fittedT, fittedR, fittedB);
    }
    g_lastDebugRawDigits = posResult !== null ? posResult.grid.filter((d: number) => d > 0).length : 0;
    if (posResult && posResult.grid.some((d: number) => d > 0)) {
      const givenCount: number = posResult.grid.filter((d: number) => d > 0).length;
      let gridStr: string = '';
      for (let r: number = 0; r < 9; r++) {
        let line: string = '';
        for (let c: number = 0; c < 9; c++) {
          line += (posResult.grid[r * 9 + c] === 0 ? '.' : posResult.grid[r * 9 + c].toString()) + ' ';
        }
        gridStr += line + '\n';
      }
      hilog.info(DOMAIN, TAG, '【VisionKit网格】%{public}d digits\n%{public}s', givenCount, gridStr);
      return { success: true, grid: posResult.grid, rawText: 'positional', error: '', confidence: new Array<number>(81).fill(POSITIONAL_CONFIDENCE), debugInfo: null };
    }

    const gridByText: number[] | null = parseOCRToGrid(rawText);
    if (gridByText && gridByText.some((d: number) => d > 0)) {
      hilog.info(DOMAIN, TAG, '【步骤详情】text fallback OK raw="%{public}s"', rawText);
      return { success: true, grid: gridByText, rawText, error: '', confidence: new Array<number>(81).fill(TEXT_FALLBACK_CONFIDENCE), debugInfo: null };
    }

    const structuredText: string = extractStructuredText(recogResult);
    if (structuredText.length > rawText.length) {
      const grid2: number[] | null = parseOCRToGrid(structuredText);
      if (grid2 && grid2.some((d: number) => d > 0)) {
        hilog.info(DOMAIN, TAG, '【步骤详情】structured text fallback OK\n%{public}s', structuredText);
        return { success: true, grid: grid2, rawText: structuredText, error: '', confidence: new Array<number>(81).fill(TEXT_FALLBACK_CONFIDENCE), debugInfo: null };
      }
    }

    g_lastDebugVkOcrError = `rawText="${rawText.substring(0, 100)}" blocks=${vkBlocks.length} lines=${vkLineCount} words=${vkWordCount} digitWords=${vkDigitWordCount} positionalDigits=${g_lastDebugRawDigits}`;
    return {
      success: false, grid: null, rawText,
      error: '识别文本中未检测到数独数字，请确保图片清晰、棋盘端正',
      confidence: null,
      debugInfo: null
    };
  } catch (_e) {
    g_lastDebugVkOcrError = `异常: ${_e}`;
    g_vkInited = false;
    g_vkFailed = true;
    hilog.error(DOMAIN, TAG, 'VK exception: %{public}s, setting g_vkFailed=true', `${_e}`);
    textRecognition.release().catch((_ee: Object) => { /* ignore */ });
    return { success: false, grid: null, rawText: '', error: 'VisionKit unavailable', confidence: null, debugInfo: null };
  } finally {
    if (pixelMap !== null) { pixelMap.release(); }
  }
}

function extractStructuredText(result: textRecognition.TextRecognitionResult): string {
  const parts: string[] = [];
  const blocks: Array<textRecognition.TextBlock> = result.blocks || [];
  for (let bi = 0; bi < blocks.length; bi++) {
    const lines: Array<textRecognition.TextLine> = blocks[bi].lines || [];
    for (let li = 0; li < lines.length; li++) {
      parts.push(lines[li].value);
    }
  }
  return parts.join('\n');
}

interface CellCandidate {
  digit: number;
  dist: number;
}

interface BoardBoundsOCR {
  boardL: number;
  boardT: number;
  boardR: number;
  boardB: number;
}

function estimateBoardBoundsFromDigits(
  rawDigits: RawDigit[], imgW: number, imgH: number
): BoardBoundsOCR | null {
  if (rawDigits.length === 0) { return null; }

  let minX: number = imgW;
  let maxX: number = 0;
  let minY: number = imgH;
  let maxY: number = 0;
  for (let i: number = 0; i < rawDigits.length; i++) {
    const d: RawDigit = rawDigits[i];
    if (d.cx < minX) { minX = d.cx; }
    if (d.cx > maxX) { maxX = d.cx; }
    if (d.cy < minY) { minY = d.cy; }
    if (d.cy > maxY) { maxY = d.cy; }
  }

  const colBuckets: number[] = new Array<number>(9).fill(0);
  const rowBuckets: number[] = new Array<number>(9).fill(0);
  const digitSpanX: number = maxX - minX;
  const digitSpanY: number = maxY - minY;
  if (digitSpanX <= 0 || digitSpanY <= 0) { return null; }

  for (let i: number = 0; i < rawDigits.length; i++) {
    const d: RawDigit = rawDigits[i];
    const colIdx: number = Math.min(Math.max(Math.floor((d.cx - minX) / digitSpanX * 8.999), 0), 8);
    const rowIdx: number = Math.min(Math.max(Math.floor((d.cy - minY) / digitSpanY * 8.999), 0), 8);
    colBuckets[colIdx]++;
    rowBuckets[rowIdx]++;
  }

  let firstCol: number = 0;
  let lastCol: number = 8;
  for (let c: number = 0; c < 9; c++) {
    if (colBuckets[c] > 0) { firstCol = c; break; }
  }
  for (let c: number = 8; c >= 0; c--) {
    if (colBuckets[c] > 0) { lastCol = c; break; }
  }
  let firstRow: number = 0;
  let lastRow: number = 8;
  for (let r: number = 0; r < 9; r++) {
    if (rowBuckets[r] > 0) { firstRow = r; break; }
  }
  for (let r: number = 8; r >= 0; r--) {
    if (rowBuckets[r] > 0) { lastRow = r; break; }
  }

  const cellWEst: number = digitSpanX / Math.max(lastCol - firstCol, 1);
  const cellHEst: number = digitSpanY / Math.max(lastRow - firstRow, 1);
  const boardL: number = Math.max(minX - firstCol * cellWEst - cellWEst * 0.5, 0);
  const boardR: number = Math.min(maxX + (8 - lastCol) * cellWEst + cellWEst * 0.5, imgW);
  const boardT: number = Math.max(minY - firstRow * cellHEst - cellHEst * 0.5, 0);
  const boardB: number = Math.min(maxY + (8 - lastRow) * cellHEst + cellHEst * 0.5, imgH);

  const result: BoardBoundsOCR = { boardL: boardL, boardT: boardT, boardR: boardR, boardB: boardB };
  return result;
}

function buildGridByPosition(
  result: textRecognition.TextRecognitionResult,
  imgW: number, imgH: number,
  pixelBbox: BoardBBox | null,
  cropOffsetX: number, cropOffsetY: number,
  cropToOcrScaleX: number, cropToOcrScaleY: number
): VisionKitGridResult | null {
  const blocks: Array<textRecognition.TextBlock> = result.blocks || [];
  if (blocks.length === 0) { return null; }

  const rawDigits: RawDigit[] = [];

  for (let bi = 0; bi < blocks.length; bi++) {
    const lines: Array<textRecognition.TextLine> = blocks[bi].lines || [];
    for (let li = 0; li < lines.length; li++) {
      const line: textRecognition.TextLine = lines[li];
      const words: Array<textRecognition.TextWord> = line.words || [];
      for (let wi = 0; wi < words.length; wi++) {
        const word: textRecognition.TextWord = words[wi];
        const text: string = word.value.trim();
        if (text.length === 0) { continue; }
        const cp: Array<textRecognition.PixelPoint> = word.cornerPoints;
        if (cp.length < 4) { continue; }

        const topLeftX: number = cp[0].x;
        const topLeftY: number = cp[0].y;
        const topRightX: number = cp[1].x;
        const bottomRightX: number = cp[2].x;
        const bottomRightY: number = cp[2].y;
        const cy: number = (topLeftY + bottomRightY) / 2;

        const charSpanX: number = (topRightX - topLeftX + bottomRightX - cp[3].x) / 2;
        const charWidth: number = charSpanX / text.length;

        for (let ci: number = 0; ci < text.length; ci++) {
          const ch: string = text[ci];
          if (!new RegExp('^[0-9]$').test(ch)) { continue; }
          const charCx: number = topLeftX + charWidth * (ci + 0.5);
          rawDigits.push({ cx: charCx, cy: cy, digit: parseInt(ch, 10) });
        }
      }
    }
  }

  if (rawDigits.length === 0) { return null; }

  let posStr: string = '';
  for (let di2: number = 0; di2 < rawDigits.length; di2++) {
    if (posStr.length > 0) { posStr += ' '; }
    posStr += `${rawDigits[di2].digit}@(${rawDigits[di2].cx.toFixed(0)},${rawDigits[di2].cy.toFixed(0)})`;
  }
  g_lastDebugRawDigitPositions = posStr;

  let boardL: number = 0;
  let boardT: number = 0;
  let boardR: number = imgW;
  let boardB: number = imgH;

  if (pixelBbox !== null) {
    boardL = (pixelBbox.left - cropOffsetX) * cropToOcrScaleX;
    boardT = (pixelBbox.top - cropOffsetY) * cropToOcrScaleY;
    boardR = (pixelBbox.right - cropOffsetX) * cropToOcrScaleX;
    boardB = (pixelBbox.bottom - cropOffsetY) * cropToOcrScaleY;
    boardL = Math.max(boardL, 0);
    boardT = Math.max(boardT, 0);
    boardR = Math.min(boardR, imgW);
    boardB = Math.min(boardB, imgH);
    hilog.info(DOMAIN, TAG, '【VisionKit Block详情】buildGrid pixelBoard ocr=[%{public}.1f,%{public}.1f,%{public}.1f,%{public}.1f]',
      boardL, boardT, boardR, boardB);
    // pixelBbox includes the outer border lines, which can shift the 9x9 grid
    // relative to actual digit centers. When enough digits are detected, refine
    // board boundaries by fitting to digit center positions.
    if (rawDigits.length >= 8) {
      // --- Row fitting ---
      const sortedY: number[] = [];
      for (let di: number = 0; di < rawDigits.length; di++) {
        sortedY.push(rawDigits[di].cy);
      }
      sortedY.sort((a: number, b: number) => a - b);
      const rowCenters: number[] = [];
      let rowStart: number = 0;
      for (let si: number = 1; si <= sortedY.length; si++) {
        const isGap: boolean = si < sortedY.length && (sortedY[si] - sortedY[si - 1]) > (sortedY[sortedY.length - 1] - sortedY[0]) / 12;
        if (isGap || si === sortedY.length) {
          let sum: number = 0;
          let cnt: number = 0;
          for (let j: number = rowStart; j < si; j++) { sum += sortedY[j]; cnt++; }
          rowCenters.push(sum / cnt);
          rowStart = si;
        }
      }
      if (rowCenters.length >= 2) {
        const yGaps: number[] = [];
        for (let ri: number = 1; ri < rowCenters.length; ri++) {
          yGaps.push(rowCenters[ri] - rowCenters[ri - 1]);
        }
        yGaps.sort((a: number, b: number) => a - b);
        const medianCellH: number = yGaps[Math.floor(yGaps.length / 2)];
        const firstGridRow: number = Math.round((rowCenters[0] - boardT) / medianCellH - 0.5);
        const clampedFirstRow: number = Math.max(0, Math.min(firstGridRow, 8 - rowCenters.length + 1));
        const refinedBoardT: number = rowCenters[0] - (clampedFirstRow + 0.5) * medianCellH;
        const refinedBoardB: number = refinedBoardT + 9 * medianCellH;
        if (refinedBoardT >= 0 && refinedBoardB <= imgH) {
          hilog.info(DOMAIN, TAG, '【VisionKit Block详情】buildGrid rowFit medianCellH=%{public}.1f firstGridRow=%{public}d refinedT=%.1f refinedB=%.1f',
            medianCellH, clampedFirstRow, refinedBoardT, refinedBoardB);
          boardT = refinedBoardT;
          boardB = refinedBoardB;
        }
      }
      // --- Column fitting ---
      const sortedX: number[] = [];
      for (let di: number = 0; di < rawDigits.length; di++) {
        sortedX.push(rawDigits[di].cx);
      }
      sortedX.sort((a: number, b: number) => a - b);
      const colCenters: number[] = [];
      let colStart: number = 0;
      for (let si: number = 1; si <= sortedX.length; si++) {
        const isGap: boolean = si < sortedX.length && (sortedX[si] - sortedX[si - 1]) > (sortedX[sortedX.length - 1] - sortedX[0]) / 12;
        if (isGap || si === sortedX.length) {
          let sum: number = 0;
          let cnt: number = 0;
          for (let j: number = colStart; j < si; j++) { sum += sortedX[j]; cnt++; }
          colCenters.push(sum / cnt);
          colStart = si;
        }
      }
      if (colCenters.length >= 2) {
        const xGaps: number[] = [];
        for (let ci: number = 1; ci < colCenters.length; ci++) {
          xGaps.push(colCenters[ci] - colCenters[ci - 1]);
        }
        xGaps.sort((a: number, b: number) => a - b);
        const medianCellW: number = xGaps[Math.floor(xGaps.length / 2)];
        const firstGridCol: number = Math.round((colCenters[0] - boardL) / medianCellW - 0.5);
        const clampedFirstCol: number = Math.max(0, Math.min(firstGridCol, 8 - colCenters.length + 1));
        const refinedBoardL: number = colCenters[0] - (clampedFirstCol + 0.5) * medianCellW;
        const refinedBoardR: number = refinedBoardL + 9 * medianCellW;
        if (refinedBoardL >= 0 && refinedBoardR <= imgW) {
          hilog.info(DOMAIN, TAG, '【VisionKit Block详情】buildGrid colFit medianCellW=%{public}.1f firstGridCol=%{public}d refinedL=%.1f refinedR=%.1f',
            medianCellW, clampedFirstCol, refinedBoardL, refinedBoardR);
          boardL = refinedBoardL;
          boardR = refinedBoardR;
        }
      }
    }
  } else {
    const estimated: BoardBoundsOCR | null =
      estimateBoardBoundsFromDigits(rawDigits, imgW, imgH);
    if (estimated !== null) {
      boardL = estimated.boardL;
      boardT = estimated.boardT;
      boardR = estimated.boardR;
      boardB = estimated.boardB;
    }
    hilog.info(DOMAIN, TAG, '【VisionKit Block详情】buildGrid digitEst ocr=[%{public}.1f,%{public}.1f,%{public}.1f,%{public}.1f]',
      boardL, boardT, boardR, boardB);
  }

  const boardW: number = boardR - boardL;
  const boardH: number = boardB - boardT;

  if (boardW <= 0 || boardH <= 0) { return null; }

  const cellW: number = boardW / 9;
  const cellH: number = boardH / 9;

  const candidates: CellCandidate[] = new Array<CellCandidate>(81);
  for (let i: number = 0; i < 81; i++) {
    candidates[i] = { digit: 0, dist: Number.MAX_VALUE };
  }

  for (let i: number = 0; i < rawDigits.length; i++) {
    const d: RawDigit = rawDigits[i];
    const normX: number = (d.cx - boardL) / boardW;
    const normY: number = (d.cy - boardT) / boardH;
    const gridCol: number = Math.min(Math.max(Math.floor(normX * 9), 0), 8);
    const gridRow: number = Math.min(Math.max(Math.floor(normY * 9), 0), 8);
    const idx: number = gridRow * 9 + gridCol;

    const cellCx: number = boardL + (gridCol + 0.5) * cellW;
    const cellCy: number = boardT + (gridRow + 0.5) * cellH;
    const dist: number = Math.sqrt((d.cx - cellCx) * (d.cx - cellCx) + (d.cy - cellCy) * (d.cy - cellCy));

    if (dist < candidates[idx].dist) {
      candidates[idx] = { digit: d.digit, dist: dist };
    }
  }

  const grid: number[] = new Array<number>(81).fill(0);
  for (let i: number = 0; i < 81; i++) {
    grid[i] = candidates[i].digit;
  }
  const gridResult: VisionKitGridResult = { grid: grid, boardL: boardL, boardT: boardT, boardW: boardW, boardH: boardH, imgW: imgW, imgH: imgH };
  return gridResult;
}

const PIXEL_MAX_DIM: number = 1200;

async function tryPixelGridRecognition(imagePath: string, imageBuf: ArrayBuffer | null = null): Promise<OCRResult> {
  let pixelMap: image.PixelMap | null = null;
  try {
    hilog.info(DOMAIN, TAG, 'Pixel: start');
    const imageSource: image.ImageSource = imageBuf !== null ? openImageSourceFromBuffer(imageBuf) : openImageSource(imagePath);

    hilog.info(DOMAIN, TAG, 'Pixel: await imageSource.getImageInfo()');
    const srcInfo: image.ImageInfo = await withTimeout<image.ImageInfo>(imageSource.getImageInfo(), 5000,
      { size: { width: 0, height: 0 } } as image.ImageInfo);
    if (srcInfo.size.width === 0 || srcInfo.size.height === 0) {
      hilog.warn(DOMAIN, TAG, 'Pixel: getImageInfo timeout or failed');
      hilog.error(DOMAIN, TAG, 'Pixel: getImageInfo超时或失败');
      imageSource.release();
      return { success: false, grid: null, rawText: '', error: 'getImageInfo超时', confidence: null, debugInfo: null };
    }
    const origW: number = srcInfo.size.width;
    const origH: number = srcInfo.size.height;

    const resize: AdaptiveResizeParams = computeAdaptiveResize(origW, origH);
    let targetW: number = resize.targetW;
    let targetH: number = resize.targetH;
    const maxDim: number = Math.max(targetW, targetH);
    if (maxDim > PIXEL_MAX_DIM) {
      const scaleDown: number = PIXEL_MAX_DIM / maxDim;
      targetW = Math.round(targetW * scaleDown);
      targetH = Math.round(targetH * scaleDown);
    }
    hilog.info(DOMAIN, TAG, '【缩放参数】原图%{public}dx%{public}d -> %{public}dx%{public}d', origW, origH, targetW, targetH);

    hilog.info(DOMAIN, TAG, 'Pixel: await createPixelMap()');
    pixelMap = await withTimeout<image.PixelMap | null>(imageSource.createPixelMap({
      desiredSize: { width: targetW, height: targetH },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    }), 5000, null);
    imageSource.release();

    if (pixelMap === null) {
      hilog.error(DOMAIN, TAG, 'Pixel: createPixelMap超时');
      return { success: false, grid: null, rawText: '', error: 'createPixelMap超时', confidence: null, debugInfo: null };
    }
    hilog.info(DOMAIN, TAG, 'Pixel: createPixelMap OK');

    const imageInfo: image.ImageInfo = await pixelMap.getImageInfo();
    const width: number = imageInfo.size.width;
    const height: number = imageInfo.size.height;

    const pixelBuf: ArrayBuffer = new ArrayBuffer(width * height * 4);
    pixelMap.readPixelsToBuffer(pixelBuf);
    const pixelBytes: Uint8Array = new Uint8Array(pixelBuf);
    g_cachedPixels = pixelBytes;
    g_cachedImgW = width;
    g_cachedImgH = height;

    const pxBg: number = bgColor(pixelBytes, width, height);
    const pxBbox: BoardBBox = findBoardBBox(pixelBytes, width, height, pxBg);
    g_probeBbox = { left: pxBbox.left, top: pxBbox.top, right: pxBbox.right, bottom: pxBbox.bottom, isDark: pxBbox.isDark };
    g_probeResizeW = width;
    g_probeResizeH = height;

    hilog.info(DOMAIN, TAG, 'Pixel: 开始 analyzePixelGrid');
    const grid: number[] = await analyzePixelGridFromBufferAsync(pixelBytes, width, height);
    const givenCount: number = grid.filter((d: number) => d > 0).length;
    hilog.info(DOMAIN, TAG, 'Pixel: analyzePixelGrid done digits=%{public}d', givenCount);
    hilog.info(DOMAIN, TAG, 'Pixel: analyzePixelGrid 完成 digits=%{public}d', givenCount);
    pixelMap.release();
    pixelMap = null;

    hilog.info(DOMAIN, TAG, '【步骤详情】像素分析完成 识别到%{public}d个数字', givenCount);
    if (givenCount > 0) {
      return { success: true, grid: grid, rawText: 'pixel analysis', error: '', confidence: [...g_lastPixelConfidence], debugInfo: null };
    }
    hilog.warn(DOMAIN, TAG, 'Pixel: no digits found');
    return {
      success: false, grid: null, rawText: '',
      error: '未能识别数独，请确保图片清晰或手动输入',
      confidence: null,
      debugInfo: null
    };
  } catch (_err) {
    hilog.error(DOMAIN, TAG, '像素分析异常: %{public}s', `${_err}`);
    if (pixelMap !== null) { pixelMap.release(); }
    return { success: false, grid: null, rawText: '', error: '图片分析失败', confidence: null, debugInfo: null };
  }
}

export function analyzePixelGridFromBuffer(pixels: Uint8Array, width: number, height: number): number[] {
  const grid: number[] = new Array<number>(81).fill(0);
  g_lastPixelConfidence = new Array<number>(81).fill(0);

  const bg: number = bgColor(pixels, width, height);
  const gray: Float32Array = toGrayArray(pixels, width, height);
  const isDark: boolean = bg < BG_DARK_THRESHOLD;

  const bgHist: number[] = new Array<number>(256).fill(0);
  const bgSampleStep2: number = Math.max(1, Math.floor(width * height / 20000));
  let bgMin2: number = 255;
  let bgMax2: number = 0;
  for (let i: number = 0; i < width * height; i += bgSampleStep2) {
    const g: number = Math.floor(gray[i]);
    if (g >= 0 && g <= 255) { bgHist[g]++; }
    if (g < bgMin2) { bgMin2 = g; }
    if (g > bgMax2) { bgMax2 = g; }
  }
  let bgHistTop3Str: string = '';
  let tmpMax2: number = -1;
  const bgHistCopy: number[] = [...bgHist];
  for (let pass: number = 0; pass < 3; pass++) {
    let topI: number = 0;
    let topV: number = 0;
    for (let i: number = 0; i < 256; i++) {
      if (bgHistCopy[i] > topV) {
        topV = bgHistCopy[i];
        topI = i;
      }
    }
    if (topV > 0) {
      bgHistTop3Str += (bgHistTop3Str.length > 0 ? ', ' : '') + `${topI}(${topV})`;
      bgHistCopy[topI] = 0;
    }
  }
  g_lastDebugPixelBgInfo = `size=${width}x${height} bg=${bg.toFixed(1)} isDark=${isDark ? 1 : 0} bgRange=[${bgMin2},${bgMax2}] bgHistTop3=[${bgHistTop3Str}] threshold=${BG_DARK_THRESHOLD}`;

  const bbox: BoardBBox = findBoardBBox(pixels, width, height, bg);
  const cellW: number = (bbox.right - bbox.left) / 9;
  const cellH: number = (bbox.bottom - bbox.top) / 9;
  const isFullImage: boolean = bbox.left === 0 && bbox.top === 0 &&
    bbox.right === width && bbox.bottom === height;
  const boardAreaRatio2: number = (bbox.right - bbox.left) * (bbox.bottom - bbox.top) / (width * height);

  const longRunResult: BoardBBox | null = findBoxLongRun(gray, width, height, isDark, bg);
  const longRunInfo: string = longRunResult !== null
    ? `OK [${longRunResult.left},${longRunResult.top},${longRunResult.right},${longRunResult.bottom}]`
    : '失败';
  g_lastDebugPixelBboxLocator = `longRun=${longRunInfo} final=[${bbox.left},${bbox.top},${bbox.right},${bbox.bottom}] isFullImage=${isFullImage ? 1 : 0} areaRatio=${boardAreaRatio2.toFixed(3)} cell=${cellW.toFixed(1)}x${cellH.toFixed(1)}`;

  hilog.info(DOMAIN, TAG, '【图片与棋盘】%{public}dx%{public}d bg=%{public}.1f isDark=%{public}d 棋盘=[%{public}d,%{public}d,%{public}d,%{public}d] 每格=%{public}.1f',
    width, height, bg, isDark ? 1 : 0, bbox.left, bbox.top, bbox.right, bbox.bottom,
    Math.min(cellW, cellH));
  hilog.info(DOMAIN, TAG, '【像素背景分析】%{public}s', g_lastDebugPixelBgInfo);
  hilog.info(DOMAIN, TAG, '【像素棋盘定位】%{public}s', g_lastDebugPixelBboxLocator);

  if (isFullImage) {
    hilog.warn(DOMAIN, TAG, '像素分析: 警告 - findBoardBBox返回全图退化bbox，棋盘定位可能失败');
  }

  const corners: BoardCorners | null = detectBoardCorners(gray, width, height, isDark, bg);
  if (corners !== null) {
    const boardSize: number = Math.max(bbox.right - bbox.left, bbox.bottom - bbox.top);
    const outSize: number = Math.round(boardSize * WARP_SIZE_MULTIPLIER);
    const warpedGray: Float32Array = warpPerspectiveGray(gray, width, height, corners, outSize, bg);
    const warpCellW: number = outSize / 9;
    const warpCellH: number = outSize / 9;
    let warpBgSum: number = 0;
    const warpSampleStep: number = Math.max(1, Math.floor(outSize * outSize / WARP_BG_SAMPLE_DIV));
    let warpBgCnt: number = 0;
    for (let i: number = 0; i < outSize * outSize; i += warpSampleStep) {
      warpBgSum += warpedGray[i];
      warpBgCnt++;
    }
    const warpBg: number = warpBgCnt > 0 ? warpBgSum / warpBgCnt : BG_DARK_THRESHOLD;
    const warpIsDark: boolean = warpBg < BG_DARK_THRESHOLD;
    resetGridLineCrop();
    detectGridLineWidths(warpedGray, outSize, 0, 0, outSize, outSize, warpIsDark, warpBg);
    g_lastDebugPixelWarpInfo = `透视校正 outSize=${outSize} confidence=${corners.confidence.toFixed(2)} warpBg=${warpBg.toFixed(1)} warpIsDark=${warpIsDark ? 1 : 0} corners=[${corners.topLeftX.toFixed(0)},${corners.topLeftY.toFixed(0)}]-[${corners.topRightX.toFixed(0)},${corners.topRightY.toFixed(0)}]-[${corners.bottomRightX.toFixed(0)},${corners.bottomRightY.toFixed(0)}]-[${corners.bottomLeftX.toFixed(0)},${corners.bottomLeftY.toFixed(0)}]`;
    hilog.info(DOMAIN, TAG, '【像素透视/网格】outSize=%{public}d confidence=%{public}.2f', outSize, corners.confidence);

    let sigCount: number = 0;
    let digitCount: number = 0;
    for (let r: number = 0; r < 9; r++) {
      for (let c: number = 0; c < 9; c++) {
        let sig: number[] | null = cellSigFromGray(
          warpedGray, outSize,
          c * warpCellW, r * warpCellH,
          warpCellW, warpCellH, warpIsDark, warpBg, r, c
        );
        let digit: number = 0;
        if (sig !== null) {
          digit = recognizeDigit(sig, countInk(sig));
        }
        if (digit === 0) {
          const lowSig: number[] | null = cellSigFromGrayLowThresh(
            warpedGray, outSize,
            c * warpCellW, r * warpCellH,
            warpCellW, warpCellH, warpIsDark, warpBg, r, c
          );
          if (lowSig !== null) {
            sig = lowSig;
            digit = recognizeDigit(lowSig, countInk(lowSig));
          }
        }
        if (digit === 0 && getLastRawInkRatio() < MIN_CELL_INK_RATIO * 0.5) {
          const thinSig: number[] | null = cellSigFromGrayThin(
            warpedGray, outSize,
            c * warpCellW, r * warpCellH,
            warpCellW, warpCellH, warpIsDark, warpBg, r, c
          );
          if (thinSig !== null) {
            sig = thinSig;
            digit = recognizeDigit(thinSig, countInk(thinSig));
          }
        }
        if (sig !== null) {
          sigCount++;
          grid[r * 9 + c] = digit;
          g_lastPixelConfidence[r * 9 + c] = getLastConfidence();
          if (digit > 0) { digitCount++; }
        }
      }
    }
    g_lastDebugPixelCellStats = `warp路径: sigOK=${sigCount}/81 digits=${digitCount}/81`;
  } else {
    hilog.info(DOMAIN, TAG, '【像素透视/网格】角点检测失败 使用AABB');
    g_lastDebugPixelWarpInfo = '角点检测失败，使用AABB';

    const gridLines: GridLines | null = findPreciseGridLines(gray, width, height, bbox, bg);
    if (gridLines !== null) {
      hilog.info(DOMAIN, TAG, '【像素透视/网格】精确网格线OK');
      g_lastDebugPixelWarpInfo += ' → 精确网格线OK';
      resetGridLineCrop();
      detectGridLineWidths(gray, width, bbox.left, bbox.top, bbox.right, bbox.bottom, isDark, bg);
      let sigCount2: number = 0;
      let digitCount2: number = 0;
      for (let r: number = 0; r < 9; r++) {
        for (let c: number = 0; c < 9; c++) {
          const cLeft: number = gridLines.vLines[c];
          const cTop: number = gridLines.hLines[r];
          const cW: number = gridLines.vLines[c + 1] - cLeft;
          const cH: number = gridLines.hLines[r + 1] - cTop;
          let sig: number[] | null = cellSigFromGray(
            gray, width, cLeft, cTop, cW, cH, bbox.isDark, bg, r, c
          );
          let digit: number = 0;
          if (sig !== null) {
            digit = recognizeDigit(sig, countInk(sig));
          }
          if (digit === 0) {
            const lowSig: number[] | null = cellSigFromGrayLowThresh(
              gray, width, cLeft, cTop, cW, cH, bbox.isDark, bg, r, c
            );
            if (lowSig !== null) {
              sig = lowSig;
              digit = recognizeDigit(lowSig, countInk(lowSig));
            }
          }
          if (digit === 0 && getLastRawInkRatio() < MIN_CELL_INK_RATIO * 0.5) {
            const thinSig: number[] | null = cellSigFromGrayThin(
              gray, width, cLeft, cTop, cW, cH, bbox.isDark, bg, r, c
            );
            if (thinSig !== null) {
              sig = thinSig;
              digit = recognizeDigit(thinSig, countInk(thinSig));
            }
          }
          if (sig !== null) {
            sigCount2++;
            g_lastPixelConfidence[r * 9 + c] = getLastConfidence();
            if (digit > 0 && !validateCellCentering(gray, width, height, cLeft, cTop, cW, cH, bbox.isDark, bg)) {
              const fallbackW: number = (bbox.right - bbox.left) / 9;
              const fallbackH: number = (bbox.bottom - bbox.top) / 9;
              const fallbackLeft: number = bbox.left + c * fallbackW;
              const fallbackTop: number = bbox.top + r * fallbackH;
              const fallbackSig: number[] | null = cellSigFromGray(
                gray, width, fallbackLeft, fallbackTop, fallbackW, fallbackH, bbox.isDark, bg, r, c
              );
              if (fallbackSig !== null) {
                const fbDigit: number = recognizeDigit(fallbackSig, countInk(fallbackSig));
                g_lastPixelConfidence[r * 9 + c] = getLastConfidence();
                if (fbDigit > 0) {
                  grid[r * 9 + c] = fbDigit;
                  digitCount2++;
                  continue;
                }
              }
            }
            grid[r * 9 + c] = digit;
            if (digit > 0) { digitCount2++; }
          }
        }
      }
      g_lastDebugPixelCellStats = `gridLines路径: sigOK=${sigCount2}/81 digits=${digitCount2}/81 vLines=${gridLines.vLines.length} hLines=${gridLines.hLines.length}`;
    } else {
      g_lastDebugPixelWarpInfo += ' → AABB均匀分格';
      resetGridLineCrop();
      detectGridLineWidths(gray, width, bbox.left, bbox.top, bbox.right, bbox.bottom, isDark, bg);
      let sigCount3: number = 0;
      let digitCount3: number = 0;
      for (let r: number = 0; r < 9; r++) {
        for (let c: number = 0; c < 9; c++) {
          let sig: number[] | null = cellSigFromGray(
            gray, width,
            bbox.left + c * cellW, bbox.top + r * cellH,
            cellW, cellH, bbox.isDark, bg, r, c
          );
          let digit: number = 0;
          if (sig !== null) {
            digit = recognizeDigit(sig, countInk(sig));
          }
          if (digit === 0) {
            const lowSig: number[] | null = cellSigFromGrayLowThresh(
              gray, width,
              bbox.left + c * cellW, bbox.top + r * cellH,
              cellW, cellH, bbox.isDark, bg, r, c
            );
            if (lowSig !== null) {
              sig = lowSig;
              digit = recognizeDigit(lowSig, countInk(lowSig));
            }
          }
          if (digit === 0 && getLastRawInkRatio() < MIN_CELL_INK_RATIO * 0.5) {
            const thinSig: number[] | null = cellSigFromGrayThin(
              gray, width,
              bbox.left + c * cellW, bbox.top + r * cellH,
              cellW, cellH, bbox.isDark, bg, r, c
            );
            if (thinSig !== null) {
              sig = thinSig;
              digit = recognizeDigit(thinSig, countInk(thinSig));
            }
          }
          if (sig !== null) {
            sigCount3++;
            grid[r * 9 + c] = digit;
            g_lastPixelConfidence[r * 9 + c] = getLastConfidence();
            if (digit > 0) { digitCount3++; }
          }
        }
      }
      g_lastDebugPixelCellStats = `AABB路径: sigOK=${sigCount3}/81 digits=${digitCount3}/81`;
    }
  }

  let gridStr: string = '[SudokuOCR] 像素分析结果:\n';
  for (let r: number = 0; r < 9; r++) {
    let line: string = '  ';
    for (let c: number = 0; c < 9; c++) {
      line += (grid[r * 9 + c] === 0 ? '.' : grid[r * 9 + c].toString()) + ' ';
    }
    gridStr += line + '\n';
  }
  hilog.info(DOMAIN, TAG, '【像素分析网格】\n%{public}s', gridStr);

  return grid;
}

export async function analyzePixelGridFromBufferAsync(pixels: Uint8Array, width: number, height: number): Promise<number[]> {
  const grid: number[] = new Array<number>(81).fill(0);
  g_lastPixelConfidence = new Array<number>(81).fill(0);
  g_lastCellCoords = [];

  const bg: number = bgColor(pixels, width, height);
  const gray: Float32Array = toGrayArray(pixels, width, height);
  const isDark: boolean = bg < BG_DARK_THRESHOLD;
  await yieldThread();

  const bgHist: number[] = new Array<number>(256).fill(0);
  const bgSampleStep2: number = Math.max(1, Math.floor(width * height / 20000));
  let bgMin2: number = 255;
  let bgMax2: number = 0;
  for (let i: number = 0; i < width * height; i += bgSampleStep2) {
    const g: number = Math.floor(gray[i]);
    if (g >= 0 && g <= 255) { bgHist[g]++; }
    if (g < bgMin2) { bgMin2 = g; }
    if (g > bgMax2) { bgMax2 = g; }
  }
  let bgHistTop3Str: string = '';
  const bgHistCopy: number[] = [...bgHist];
  for (let pass: number = 0; pass < 3; pass++) {
    let topI: number = 0;
    let topV: number = 0;
    for (let i: number = 0; i < 256; i++) {
      if (bgHistCopy[i] > topV) {
        topV = bgHistCopy[i];
        topI = i;
      }
    }
    if (topV > 0) {
      bgHistTop3Str += (bgHistTop3Str.length > 0 ? ', ' : '') + `${topI}(${topV})`;
      bgHistCopy[topI] = 0;
    }
  }
  g_lastDebugPixelBgInfo = `size=${width}x${height} bg=${bg.toFixed(1)} isDark=${isDark ? 1 : 0} bgRange=[${bgMin2},${bgMax2}] bgHistTop3=[${bgHistTop3Str}] threshold=${BG_DARK_THRESHOLD}`;

  const bbox: BoardBBox = findBoardBBox(pixels, width, height, bg);
  const cellW: number = (bbox.right - bbox.left) / 9;
  const cellH: number = (bbox.bottom - bbox.top) / 9;
  const isFullImage: boolean = bbox.left === 0 && bbox.top === 0 &&
    bbox.right === width && bbox.bottom === height;
  const boardAreaRatio2: number = (bbox.right - bbox.left) * (bbox.bottom - bbox.top) / (width * height);
  await yieldThread();

  const longRunResult: BoardBBox | null = findBoxLongRun(gray, width, height, isDark, bg);
  const longRunInfo: string = longRunResult !== null
    ? `OK [${longRunResult.left},${longRunResult.top},${longRunResult.right},${longRunResult.bottom}]`
    : '失败';
  g_lastDebugPixelBboxLocator = `longRun=${longRunInfo} final=[${bbox.left},${bbox.top},${bbox.right},${bbox.bottom}] isFullImage=${isFullImage ? 1 : 0} areaRatio=${boardAreaRatio2.toFixed(3)} cell=${cellW.toFixed(1)}x${cellH.toFixed(1)}`;

  hilog.info(DOMAIN, TAG, '【图片与棋盘】%{public}dx%{public}d bg=%{public}.1f isDark=%{public}d 棋盘=[%{public}d,%{public}d,%{public}d,%{public}d] 每格=%{public}.1f',
    width, height, bg, isDark ? 1 : 0, bbox.left, bbox.top, bbox.right, bbox.bottom,
    Math.min(cellW, cellH));
  hilog.info(DOMAIN, TAG, '【像素背景分析】%{public}s', g_lastDebugPixelBgInfo);
  hilog.info(DOMAIN, TAG, '【像素棋盘定位】%{public}s', g_lastDebugPixelBboxLocator);

  if (isFullImage) {
    hilog.warn(DOMAIN, TAG, '像素分析: 警告 - findBoardBBox返回全图退化bbox，棋盘定位可能失败');
  }
  await yieldThread();

  const corners: BoardCorners | null = detectBoardCorners(gray, width, height, isDark, bg);
  if (corners !== null) {
    const boardSize: number = Math.max(bbox.right - bbox.left, bbox.bottom - bbox.top);
    const outSize: number = Math.round(boardSize * WARP_SIZE_MULTIPLIER);
    const warpedGray: Float32Array = warpPerspectiveGray(gray, width, height, corners, outSize, bg);
    const warpCellW: number = outSize / 9;
    const warpCellH: number = outSize / 9;
    const warpInkBg: number = isDark ? bg + INK_THRESH : bg - INK_THRESH;
    let warpBgSum: number = 0;
    let warpBgCnt: number = 0;
    const warpSampleStep: number = Math.max(1, Math.floor(outSize * outSize / WARP_BG_SAMPLE_DIV));
    for (let sy: number = 0; sy < outSize; sy += warpSampleStep) {
      for (let sx: number = 0; sx < outSize; sx += warpSampleStep) {
        const g: number = warpedGray[sy * outSize + sx];
        if (isDark ? g < warpInkBg : g > warpInkBg) {
          warpBgSum += g;
          warpBgCnt++;
        }
      }
    }
    const warpBg: number = warpBgCnt > 0 ? warpBgSum / warpBgCnt : bg;
    const warpIsDark: boolean = warpBg < BG_DARK_THRESHOLD;
    resetGridLineCrop();
    const warpBBox: BoardBBox = { left: 0, top: 0, right: outSize, bottom: outSize, isDark: warpIsDark };
    const warpGridLines: GridLines | null = findPreciseGridLines(warpedGray, outSize, outSize, warpBBox, warpBg);
    if (warpGridLines !== null) {
      detectGridLineWidths(warpedGray, outSize, 0, 0, outSize, outSize, warpIsDark, warpBg);
    }
    g_lastDebugPixelWarpInfo = `透视校正 outSize=${outSize} confidence=${corners.confidence.toFixed(2)} warpBg=${warpBg.toFixed(1)} warpIsDark=${warpIsDark ? 1 : 0} warpGridLines=${warpGridLines !== null ? 'OK' : 'null'} corners=[${corners.topLeftX.toFixed(0)},${corners.topLeftY.toFixed(0)}]-[${corners.topRightX.toFixed(0)},${corners.topRightY.toFixed(0)}]-[${corners.bottomRightX.toFixed(0)},${corners.bottomRightY.toFixed(0)}]-[${corners.bottomLeftX.toFixed(0)},${corners.bottomLeftY.toFixed(0)}]`;
    hilog.info(DOMAIN, TAG, '【像素透视/网格】outSize=%{public}d confidence=%{public}.2f warpBg=%{public}.1f gridLines=%{public}s', outSize, corners.confidence, warpBg, warpGridLines !== null ? 'OK' : 'null');
    await yieldThread();

    let sigCount: number = 0;
    let digitCount: number = 0;
    for (let r: number = 0; r < 9; r++) {
      for (let c: number = 0; c < 9; c++) {
        let cellL: number = 0;
        let cellT: number = 0;
        let cellW: number = warpCellW;
        let cellH: number = warpCellH;
        if (warpGridLines !== null) {
          cellL = warpGridLines.vLines[c];
          cellT = warpGridLines.hLines[r];
          cellW = warpGridLines.vLines[c + 1] - cellL;
          cellH = warpGridLines.hLines[r + 1] - cellT;
        } else {
          cellL = c * warpCellW;
          cellT = r * warpCellH;
        }
        let sig: number[] | null = cellSigFromGray(
          warpedGray, outSize,
          cellL, cellT,
          cellW, cellH, warpIsDark, warpBg, r, c
        );
        let digit: number = 0;
        if (sig !== null) {
          digit = recognizeDigit(sig, countInk(sig));
        }
        if (digit === 0) {
          const lowSig: number[] | null = cellSigFromGrayLowThresh(
            warpedGray, outSize,
            cellL, cellT,
            cellW, cellH, warpIsDark, warpBg, r, c
          );
          if (lowSig !== null) {
            sig = lowSig;
            digit = recognizeDigit(lowSig, countInk(lowSig));
          }
        }
        if (digit === 0 && getLastRawInkRatio() < MIN_CELL_INK_RATIO * 0.5) {
          const thinSig: number[] | null = cellSigFromGrayThin(
            warpedGray, outSize,
            cellL, cellT,
            cellW, cellH, warpIsDark, warpBg, r, c
          );
          if (thinSig !== null) {
            sig = thinSig;
            digit = recognizeDigit(thinSig, countInk(thinSig));
          }
        }
        if (sig !== null) {
          sigCount++;
          grid[r * 9 + c] = digit;
          g_lastPixelConfidence[r * 9 + c] = getLastConfidence();
          if (digit > 0) { digitCount++; }
          g_lastCellCoords.push({
            row: r, col: c, digit: digit,
            left: Math.round(cellL), top: Math.round(cellT),
            w: Math.round(cellW), h: Math.round(cellH),
            conf: getLastConfidence(), rawInk: getLastRawInkRatio(),
            imgW: outSize, imgH: outSize,
            source: warpGridLines !== null ? 'warp+grid' : 'warp'
          });
        }
        await yieldThread();
      }
    }
    g_lastDebugPixelCellStats = `warp路径: sigOK=${sigCount}/81 digits=${digitCount}/81`;
  } else {
    hilog.info(DOMAIN, TAG, '【像素透视/网格】角点检测失败 使用AABB');
    g_lastDebugPixelWarpInfo = '角点检测失败，使用AABB';
    await yieldThread();

    const gridLines: GridLines | null = findPreciseGridLines(gray, width, height, bbox, bg);
    if (gridLines !== null) {
      hilog.info(DOMAIN, TAG, '【像素透视/网格】精确网格线OK');
      g_lastDebugPixelWarpInfo += ' → 精确网格线OK';
      resetGridLineCrop();
      detectGridLineWidths(gray, width, bbox.left, bbox.top, bbox.right, bbox.bottom, isDark, bg);
      await yieldThread();
      let sigCount2: number = 0;
      let digitCount2: number = 0;
      for (let r: number = 0; r < 9; r++) {
        for (let c: number = 0; c < 9; c++) {
          const cLeft: number = gridLines.vLines[c];
          const cTop: number = gridLines.hLines[r];
          const cW: number = gridLines.vLines[c + 1] - cLeft;
          const cH: number = gridLines.hLines[r + 1] - cTop;
          let sig: number[] | null = cellSigFromGray(
            gray, width, cLeft, cTop, cW, cH, bbox.isDark, bg, r, c
          );
          let digit: number = 0;
          if (sig !== null) {
            digit = recognizeDigit(sig, countInk(sig));
          }
          if (digit === 0) {
            const lowSig: number[] | null = cellSigFromGrayLowThresh(
              gray, width, cLeft, cTop, cW, cH, bbox.isDark, bg, r, c
            );
            if (lowSig !== null) {
              sig = lowSig;
              digit = recognizeDigit(lowSig, countInk(lowSig));
            }
          }
          if (digit === 0 && getLastRawInkRatio() < MIN_CELL_INK_RATIO * 0.5) {
            const thinSig: number[] | null = cellSigFromGrayThin(
              gray, width, cLeft, cTop, cW, cH, bbox.isDark, bg, r, c
            );
            if (thinSig !== null) {
              sig = thinSig;
              digit = recognizeDigit(thinSig, countInk(thinSig));
            }
          }
          if (sig !== null) {
            sigCount2++;
            g_lastPixelConfidence[r * 9 + c] = getLastConfidence();
            if (digit > 0 && !validateCellCentering(gray, width, height, cLeft, cTop, cW, cH, bbox.isDark, bg)) {
              const fallbackW: number = (bbox.right - bbox.left) / 9;
              const fallbackH: number = (bbox.bottom - bbox.top) / 9;
              const fallbackLeft: number = bbox.left + c * fallbackW;
              const fallbackTop: number = bbox.top + r * fallbackH;
              const fallbackSig: number[] | null = cellSigFromGray(
                gray, width, fallbackLeft, fallbackTop, fallbackW, fallbackH, bbox.isDark, bg, r, c
              );
              if (fallbackSig !== null) {
                const fbDigit: number = recognizeDigit(fallbackSig, countInk(fallbackSig));
                g_lastPixelConfidence[r * 9 + c] = getLastConfidence();
                if (fbDigit > 0) {
                  grid[r * 9 + c] = fbDigit;
                  digitCount2++;
                  g_lastCellCoords.push({
                    row: r, col: c, digit: fbDigit,
                    left: Math.round(fallbackLeft), top: Math.round(fallbackTop),
                    w: Math.round(fallbackW), h: Math.round(fallbackH),
                    conf: getLastConfidence(), rawInk: getLastRawInkRatio(),
                    imgW: width, imgH: height,
                    source: 'gridLines_fallback'
                  });
                  continue;
                }
              }
            }
            grid[r * 9 + c] = digit;
            if (digit > 0) { digitCount2++; }
            g_lastCellCoords.push({
              row: r, col: c, digit: digit,
              left: Math.round(cLeft), top: Math.round(cTop),
              w: Math.round(cW), h: Math.round(cH),
              conf: getLastConfidence(), rawInk: getLastRawInkRatio(),
              imgW: width, imgH: height,
              source: 'gridLines'
            });
          }
          await yieldThread();
        }
      }
      g_lastDebugPixelCellStats = `gridLines路径: sigOK=${sigCount2}/81 digits=${digitCount2}/81 vLines=${gridLines.vLines.length} hLines=${gridLines.hLines.length}`;
    } else {
      g_lastDebugPixelWarpInfo += ' → AABB均匀分格';
      resetGridLineCrop();
      detectGridLineWidths(gray, width, bbox.left, bbox.top, bbox.right, bbox.bottom, isDark, bg);
      await yieldThread();
      let sigCount3: number = 0;
      let digitCount3: number = 0;
      for (let r: number = 0; r < 9; r++) {
        for (let c: number = 0; c < 9; c++) {
          let sig: number[] | null = cellSigFromGray(
            gray, width,
            bbox.left + c * cellW, bbox.top + r * cellH,
            cellW, cellH, bbox.isDark, bg, r, c
          );
          let digit: number = 0;
          if (sig !== null) {
            digit = recognizeDigit(sig, countInk(sig));
          }
          if (digit === 0) {
            const lowSig: number[] | null = cellSigFromGrayLowThresh(
              gray, width,
              bbox.left + c * cellW, bbox.top + r * cellH,
              cellW, cellH, bbox.isDark, bg, r, c
            );
            if (lowSig !== null) {
              sig = lowSig;
              digit = recognizeDigit(lowSig, countInk(lowSig));
            }
          }
          if (digit === 0 && getLastRawInkRatio() < MIN_CELL_INK_RATIO * 0.5) {
            const thinSig: number[] | null = cellSigFromGrayThin(
              gray, width,
              bbox.left + c * cellW, bbox.top + r * cellH,
              cellW, cellH, bbox.isDark, bg, r, c
            );
            if (thinSig !== null) {
              sig = thinSig;
              digit = recognizeDigit(thinSig, countInk(thinSig));
            }
          }
          if (sig !== null) {
            sigCount3++;
            grid[r * 9 + c] = digit;
            g_lastPixelConfidence[r * 9 + c] = getLastConfidence();
            if (digit > 0) { digitCount3++; }
            const aabbLeft: number = bbox.left + c * cellW;
            const aabbTop: number = bbox.top + r * cellH;
            g_lastCellCoords.push({
              row: r, col: c, digit: digit,
              left: Math.round(aabbLeft), top: Math.round(aabbTop),
              w: Math.round(cellW), h: Math.round(cellH),
              conf: getLastConfidence(), rawInk: getLastRawInkRatio(),
              imgW: width, imgH: height,
              source: 'AABB'
            });
          }
          await yieldThread();
        }
      }
      g_lastDebugPixelCellStats = `AABB路径: sigOK=${sigCount3}/81 digits=${digitCount3}/81`;
    }
  }

  let coordLines: string[] = [];
  for (const ci of g_lastCellCoords) {
    coordLines.push(`R${ci.row}C${ci.col}:d=${ci.digit} rect=[${ci.left},${ci.top},${ci.w}x${ci.h}] conf=${ci.conf.toFixed(2)} ink=${ci.rawInk.toFixed(4)} imgSize=${ci.imgW}x${ci.imgH} src=${ci.source}`);
  }
  g_lastDebugPixelCellCoords = coordLines.join('\n');

  let gridStr: string = '[SudokuOCR] 像素分析结果:\n';
  for (let r: number = 0; r < 9; r++) {
    let line: string = '  ';
    for (let c: number = 0; c < 9; c++) {
      line += (grid[r * 9 + c] === 0 ? '.' : grid[r * 9 + c].toString()) + ' ';
    }
    gridStr += line + '\n';
  }
  hilog.info(DOMAIN, TAG, '【像素分析网格】\n%{public}s', gridStr);

  return grid;
}

function analyzePixelGrid(pixelMap: image.PixelMap, width: number, height: number): number[] {
  try {
    const buffer: ArrayBuffer = new ArrayBuffer(width * height * 4);
    pixelMap.readPixelsToBuffer(buffer);
    const pixels: Uint8Array = new Uint8Array(buffer);
    return analyzePixelGridFromBuffer(pixels, width, height);
  } catch (_e) {
    return new Array<number>(81).fill(0);
  }
}
