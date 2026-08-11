import { image } from '@kit.ImageKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { fileIo } from '@kit.CoreFileKit';
import { parseOCRToGrid } from './SudokuEngine';
import { BoardBBox, BoardCorners, GridLines, bgColor, cellSigFromGray, countInk, detectBoardCorners, findBoardBBox, findBoxLongRun, getLastBboxDiag, findPreciseGridLines, getLastConfidence, recognizeDigit, SIG_COLS, SIG_ROWS, toGrayArray, validateCellCentering, warpPerspectiveGray } from './SudokuPixel';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xA03D00;
const TAG: string = 'SudokuOCR';

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
const CELL_CROP_PAD_FACTOR: number = 0.30;

// Upscale factor applied to cropped cell images before VisionKit re-recognition.
// A 5x upscale helps VisionKit read small/faint digits.
const CELL_UPSCALE_FACTOR: number = 3;

// Minimum crop width/height (px) for a cell to be sent to VisionKit.
// Smaller crops are too low-resolution to be useful.
const MIN_CELL_CROP_DIM: number = 10;

// Resize thresholds: images larger than these are downscaled to the
// corresponding target to balance OCR quality and speed.
const RESIZE_LARGE_THRESHOLD: number = 2000;
const RESIZE_LARGE_TARGET: number = 1600;
const RESIZE_MEDIUM_THRESHOLD: number = 1280;
const RESIZE_SMALL_THRESHOLD: number = 800;
const RESIZE_SMALL_TARGET: number = 800;

// Confidence threshold: digits with VisionKit confidence below this are
// flagged as low-confidence and re-checked in fixAndFillGrid.
const LOW_CONFIDENCE_THRESHOLD: number = 0.5;

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

// Minimum ink ratio in a cell (relative to cell area) to consider it occupied.
// Cells with ink ratio < 0.04 (4%) are treated as empty.
const MIN_CELL_INK_RATIO: number = 0.04;

// Background sampling step divisor for warped image background estimation.
const WARP_BG_SAMPLE_DIV: number = 20000;

let g_lastPixelConfidence: number[] = new Array<number>(81).fill(0);

let g_debugInfo: OCRDebugInfo | null = null;

let g_lastDebugBbox: string = '';
let g_lastDebugResize: string = '';
let g_lastDebugRawDigits: number = 0;
let g_lastDebugConflicts: number[] = [];
let g_probeBbox: BoardBBox | null = null;
let g_probeResizeW: number = 0;
let g_probeResizeH: number = 0;
let g_lastDebugLowConf: number[] = [];
let g_lastDebugEmpty: number[] = [];
let g_lastDebugFixCount: number = 0;
let g_vkInited: boolean = false;

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
let g_lastDebugFixDetails: string = '';

// 逐格VK诊断统计（供调试面板展示）
interface PerCellVkDiag {
  cropFail: number;
  noBlock: number;
  noCenter: number;
  found: number;
  samples: string[];
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
    probeInfo: g_lastDebugProbeInfo,
    pixelBgInfo: g_lastDebugPixelBgInfo,
    pixelBboxLocator: g_lastDebugPixelBboxLocator,
    pixelWarpInfo: g_lastDebugPixelWarpInfo,
    pixelCellStats: g_lastDebugPixelCellStats,
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
  probeInfo: string;
  pixelBgInfo: string;
  pixelBboxLocator: string;
  pixelWarpInfo: string;
  pixelCellStats: string;
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
    const scale: number = RESIZE_SMALL_TARGET / maxDim;
    targetW = Math.round(origW * scale);
    targetH = Math.round(origH * scale);
  }

  const params: AdaptiveResizeParams = { targetW: targetW, targetH: targetH, targetCellPx: targetCellPx };
  return params;
}

function openImageSource(uri: string): image.ImageSource {
  if (uri.startsWith('file://media/') || uri.startsWith('content://')) {
    const file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    return image.createImageSource(file.fd);
  }
  return image.createImageSource(uri);
}

export async function recognizeSudokuFromImage(imagePath: string): Promise<OCRResult> {
  g_debugInfo = null;
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
  isDark: boolean, bg: number
): number | null {
  const sig: number[] | null = cellSigFromGray(
    gray, imgW,
    cellLeft, cellTop, cellW, cellH, isDark, bg
  );
  if (sig === null) {
    return null;
  }

  const inkCount: number = countInk(sig);
  return recognizeDigit(sig, inkCount);
}

async function fixAndFillGrid(ocrResult: OCRResult, imagePath: string): Promise<OCRResult> {
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

  const emptyIndices: number[] = [];
  for (let i: number = 0; i < 81; i++) {
    if (grid[i] === 0) {
      emptyIndices.push(i);
    }
  }

  const fixSet: Set<number> = new Set<number>();
  for (const idx of conflictIndices) { fixSet.add(idx); }
  for (const idx of lowConfIndices) { fixSet.add(idx); }
  for (const idx of emptyIndices) { fixSet.add(idx); }

  const allFixIndices: number[] = [];
  fixSet.forEach((idx: number) => { allFixIndices.push(idx); });

  if (conflictIndices.length > 0) {
    hilog.info(DOMAIN, TAG, '【冲突格子】%{public}d个', conflictIndices.length);
  }
  if (lowConfIndices.length > 0) {
    hilog.info(DOMAIN, TAG, '【低置信格子】%{public}d个', lowConfIndices.length);
  }
  if (emptyIndices.length > 0) {
    hilog.info(DOMAIN, TAG, '【空格子待修正】%{public}d个待填充', emptyIndices.length);
  }
  hilog.info(DOMAIN, TAG, '【步骤详情】共需修正%{public}d格 (%{public}d冲突+%{public}d低置信+%{public}d空)',
    allFixIndices.length, conflictIndices.length, lowConfIndices.length, emptyIndices.length);

  if (allFixIndices.length === 0) {
    hilog.info(DOMAIN, TAG, '【实际修正】无冲突且无空格，直接采用结果');
    g_lastDebugFixDetails = '';
    g_lastDebugConflicts = conflictIndices;
    g_lastDebugLowConf = lowConfIndices;
    g_lastDebugEmpty = emptyIndices;
    g_lastDebugFixCount = 0;
    return ocrResult;
  }

  const imageSource: image.ImageSource = openImageSource(imagePath);
  const srcInfo: image.ImageInfo = await imageSource.getImageInfo();
  const origW: number = srcInfo.size.width;
  const origH: number = srcInfo.size.height;

  const resize: AdaptiveResizeParams = computeAdaptiveResize(origW, origH);

  const pixelMap: image.PixelMap = await imageSource.createPixelMap({
    desiredSize: { width: resize.targetW, height: resize.targetH },
    desiredPixelFormat: image.PixelMapFormat.RGBA_8888
  });
  imageSource.release();

  const info: image.ImageInfo = await pixelMap.getImageInfo();
  const imgW: number = info.size.width;
  const imgH: number = info.size.height;

  const buffer: ArrayBuffer = new ArrayBuffer(imgW * imgH * 4);
  pixelMap.readPixelsToBuffer(buffer);
  const pixels: Uint8Array = new Uint8Array(buffer);

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

  const cellW: number = (bbox.right - bbox.left) / 9;
  const cellH: number = (bbox.bottom - bbox.top) / 9;
  const padFactor: number = CELL_CROP_PAD_FACTOR;
  const upscale: number = CELL_UPSCALE_FACTOR;

  hilog.info(DOMAIN, TAG, '【步骤详情】校正图=%{public}dx%{public}d cell=%.1fx%.1f upscale=%{public}d',
    imgW, imgH, cellW, cellH, upscale);

  let vkInited: boolean = false;
  let vkInitFailed: boolean = false;
  let fixCount: number = 0;

  g_perCellVkDiag = { cropFail: 0, noBlock: 0, noCenter: 0, found: 0, samples: [] };
  const fixDetailLines: string[] = [];

  for (const idx of allFixIndices) {
    const origDigit: number = grid[idx];
    const row: number = Math.floor(idx / 9);
    const col: number = idx % 9;
    const cellLeft: number = bbox.left + col * cellW;
    const cellTop: number = bbox.top + row * cellH;
    const cellLabel: string = `(${row},${col})`;

    let pixelDigit: number | null = null;
    if (gray.length > 0) {
      pixelDigit = recognizeDigitPixel(gray, imgW, cellLeft, cellTop, cellW, cellH, bbox.isDark, bg);
    }

    // VisionKit 逐格识别：
    // 空格子 → 宽区域裁剪（目标格±邻格），用位置定位中心格数字，提高上下文识别率
    // 非空格子（冲突/低置信）→ 单格裁剪，仅作重验证
    let vkDigit: number | null = null;
    let vkCropInfo: string = `${cellW.toFixed(0)}x${cellH.toFixed(0)}`;
    if (!vkInitFailed) {
      let cropX: number = 0; let cropY: number = 0;
      let cropW: number = 0; let cropH: number = 0;
      let centerCellX: number = 0; let centerCellY: number = 0;
      let useWideCrop: boolean = false;

      if (origDigit === 0) {
        // 空格子：宽区域裁剪（3格宽），提供网格线/邻格上下文
        const startCol: number = Math.max(0, col - 1);
        const endCol: number = Math.min(8, col + 1);
        cropX = Math.max(Math.floor(bbox.left + startCol * cellW - cellW * padFactor), 0);
        cropY = Math.max(Math.floor(bbox.top + row * cellH - cellH * padFactor), 0);
        const cropR: number = Math.min(Math.floor(bbox.left + (endCol + 1) * cellW + cellW * padFactor), imgW);
        const cropB: number = Math.min(Math.floor(bbox.top + (row + 1) * cellH + cellH * padFactor), imgH);
        cropW = cropR - cropX;
        cropH = cropB - cropY;
        // 中心格在裁剪区域（未上采样）中的坐标
        centerCellX = (col - startCol) * cellW + cellW * padFactor;
        centerCellY = cellH * padFactor;
        useWideCrop = true;
      } else {
        // 非空格子：单格裁剪
        cropX = Math.max(Math.floor(cellLeft - cellW * padFactor), 0);
        cropY = Math.max(Math.floor(cellTop - cellH * padFactor), 0);
        const cropR: number = Math.min(Math.floor(cellLeft + cellW + cellW * padFactor), imgW);
        const cropB: number = Math.min(Math.floor(cellTop + cellH + cellH * padFactor), imgH);
        cropW = cropR - cropX;
        cropH = cropB - cropY;
      }

      vkCropInfo = useWideCrop
        ? `宽${cropW}x${cropH}→${Math.round(cropW * upscale)}x${Math.round(cropH * upscale)}`
        : `${cropW}x${cropH}→${Math.round(cropW * upscale)}x${Math.round(cropH * upscale)}`;

      if (cropW >= MIN_CELL_CROP_DIM && cropH >= MIN_CELL_CROP_DIM) {
        const cellPm: image.PixelMap | null = cropCellFromBuffer(pixels, imgW, imgH, cropX, cropY, cropW, cropH, upscale);
        if (cellPm !== null) {
          const doRecognize = async (pm: image.PixelMap): Promise<number | null> => {
            if (useWideCrop) {
              return await recognizeDigitInWideRegion(pm, upscale, centerCellX, centerCellY, cellW, cellH);
            } else {
              return await recognizeDigitVisionKit(pm);
            }
          };
          if (!vkInited) {
            if (g_vkInited) {
              vkInited = true;
              vkDigit = await doRecognize(cellPm);
              cellPm.release();
            } else {
              vkInited = true;
              const initOk: boolean = await textRecognition.init();
              g_vkInited = initOk;
              if (!initOk) {
                vkInitFailed = true;
                cellPm.release();
                hilog.info(DOMAIN, TAG, '【步骤详情】VisionKit init失败');
              } else {
                vkDigit = await doRecognize(cellPm);
                cellPm.release();
              }
            }
          } else {
            vkDigit = await doRecognize(cellPm);
            cellPm.release();
          }
        } else {
          if (useWideCrop) {
            g_perCellVkDiag.cropFail++;
            hilog.info(DOMAIN, TAG, '【逐格修正详情】cropCellFromBuffer失败 crop=%{public}dx%{public}d→%{public}dx%{public}d',
              cropW, cropH, Math.round(cropW * upscale), Math.round(cropH * upscale));
          }
        }
      }
    }

    const pStr: string = pixelDigit !== null && pixelDigit > 0 ? `${pixelDigit}` : '-';
    const vStr: string = vkDigit !== null && vkDigit > 0 ? `${vkDigit}` : '-';

    if (origDigit === 0) {
      if (vkDigit !== null && vkDigit > 0) {
        grid[idx] = vkDigit;
        const newConflicts: number[] = findConflictCells(grid);
        const selfConflict: boolean = newConflicts.some((ci: number) => ci === idx);
        if (selfConflict) {
          grid[idx] = 0;
          hilog.info(DOMAIN, TAG, '【逐格修正详情】填充冲突回退 %{public}s V=%{public}d', cellLabel, vkDigit);
          fixDetailLines.push(`冲突回填${cellLabel} V=${vkDigit}冲突→留空 P=${pStr} crop=${vkCropInfo}`);
        } else {
          hilog.info(DOMAIN, TAG, '【逐格修正详情】填充 %{public}s 空→%{public}d V=%{public}d P=%{public}s',
            cellLabel, vkDigit, vkDigit, pStr);
          fixCount++;
          fixDetailLines.push(`填充${cellLabel} 空→${vkDigit} V=${vStr} P=${pStr} crop=${vkCropInfo}`);
        }
      } else {
        fixDetailLines.push(`留空${cellLabel} V=${vStr} P=${pStr} crop=${vkCropInfo}`);
      }
      continue;
    }

    let finalDigit: number | null = null;
    let decision: string = '';
    if (pixelDigit !== null && pixelDigit > 0) {
      if (vkDigit === null || vkDigit === pixelDigit) {
        finalDigit = pixelDigit;
        decision = 'P=V';
      } else {
        finalDigit = pixelDigit;
        decision = 'P≠V→P';
      }
    } else if (vkDigit !== null && vkDigit > 0) {
      finalDigit = vkDigit;
      decision = 'V_only';
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
      fixDetailLines.push(`修正${cellLabel} ${origDigit}→${finalDigit} P=${pStr} V=${vStr} ${decision}${swapNote}`);
    } else {
      fixDetailLines.push(`不变${cellLabel}=${origDigit} P=${pStr} V=${vStr} ${decision}`);
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

  if (vkInited) {
    try { await textRecognition.release(); } catch (_ee) { /* ignore */ }
    g_vkInited = false;
  }
  pixelMap.release();

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

async function tryVisionKitRecognition(imagePath: string): Promise<OCRResult> {
  let pixelMap: image.PixelMap | null = null;
  g_lastDebugVkRawText = '';
  g_lastDebugVkBlockCount = 0;
  g_lastDebugVkOcrSize = '';
  g_lastDebugVkOcrError = '';
  g_lastDebugProbeInfo = '';
  try {
    const initOk: boolean = await textRecognition.init();
    g_vkInited = initOk;
    if (!initOk) {
      g_lastDebugVkOcrError = 'VisionKit init() returned false';
      return { success: false, grid: null, rawText: '', error: 'VisionKit init failed', confidence: null, debugInfo: null };
    }

    const imageSource: image.ImageSource = openImageSource(imagePath);
    const srcInfo: image.ImageInfo = await imageSource.getImageInfo();
    const origW: number = srcInfo.size.width;
    const origH: number = srcInfo.size.height;

    const resize: AdaptiveResizeParams = computeAdaptiveResize(origW, origH);
    const probeW: number = resize.targetW;
    const probeH: number = resize.targetH;

    const probePm: image.PixelMap = await imageSource.createPixelMap({
      desiredSize: { width: probeW, height: probeH },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    });
    const probeImgInfo: image.ImageInfo = await probePm.getImageInfo();
    const probeImgW: number = probeImgInfo.size.width;
    const probeImgH: number = probeImgInfo.size.height;

    const probeBuf: ArrayBuffer = new ArrayBuffer(probeImgW * probeImgH * 4);
    probePm.readPixelsToBuffer(probeBuf);
    const probePixels: Uint8Array = new Uint8Array(probeBuf);
    probePm.release();

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

    pixelMap = await imageSource.createPixelMap({
      desiredRegion: { size: { width: origCropW, height: origCropH }, x: origCropL, y: origCropT },
      desiredSize: { width: finalW, height: finalH },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST
    });
    imageSource.release();

    const imageInfo: image.ImageInfo = await pixelMap.getImageInfo();
    const imgW: number = imageInfo.size.width;
    const imgH: number = imageInfo.size.height;
    g_lastDebugVkOcrSize = `${imgW}x${imgH}`;
    hilog.info(DOMAIN, TAG, '【VisionKit OCR图尺寸】%{public}dx%{public}d', imgW, imgH);

    const visionInfo: textRecognition.VisionInfo = { pixelMap: pixelMap };
    const recogResult: textRecognition.TextRecognitionResult =
      await textRecognition.recognizeText(visionInfo, {
        isDirectionDetectionSupported: true
      });

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
    try { await textRecognition.release(); } catch (_ee) { /* ignore */ }
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

async function tryPixelGridRecognition(imagePath: string): Promise<OCRResult> {
  let pixelMap: image.PixelMap | null = null;
  try {
    const imageSource: image.ImageSource = openImageSource(imagePath);

    const srcInfo: image.ImageInfo = await imageSource.getImageInfo();
    const origW: number = srcInfo.size.width;
    const origH: number = srcInfo.size.height;

    const resize: AdaptiveResizeParams = computeAdaptiveResize(origW, origH);
    const targetW: number = resize.targetW;
    const targetH: number = resize.targetH;
    hilog.info(DOMAIN, TAG, '【缩放参数】原图%{public}dx%{public}d -> %{public}dx%{public}d', origW, origH, targetW, targetH);

    pixelMap = await imageSource.createPixelMap({
      desiredSize: { width: targetW, height: targetH },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    });
    imageSource.release();

    const imageInfo: image.ImageInfo = await pixelMap.getImageInfo();
    const width: number = imageInfo.size.width;
    const height: number = imageInfo.size.height;

    const grid: number[] = analyzePixelGrid(pixelMap, width, height);
    pixelMap.release();
    pixelMap = null;

    const givenCount: number = grid.filter((d: number) => d > 0).length;
    hilog.info(DOMAIN, TAG, '【步骤详情】像素分析完成 识别到%{public}d个数字', givenCount);
    if (givenCount > 0) {
      return { success: true, grid: grid, rawText: 'pixel analysis', error: '', confidence: [...g_lastPixelConfidence], debugInfo: null };
    }
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
    g_lastDebugPixelWarpInfo = `透视校正 outSize=${outSize} confidence=${corners.confidence.toFixed(2)} warpBg=${warpBg.toFixed(1)} warpIsDark=${warpIsDark ? 1 : 0} corners=[${corners.topLeftX.toFixed(0)},${corners.topLeftY.toFixed(0)}]-[${corners.topRightX.toFixed(0)},${corners.topRightY.toFixed(0)}]-[${corners.bottomRightX.toFixed(0)},${corners.bottomRightY.toFixed(0)}]-[${corners.bottomLeftX.toFixed(0)},${corners.bottomLeftY.toFixed(0)}]`;
    hilog.info(DOMAIN, TAG, '【像素透视/网格】outSize=%{public}d confidence=%{public}.2f', outSize, corners.confidence);

    let sigCount: number = 0;
    let digitCount: number = 0;
    for (let r: number = 0; r < 9; r++) {
      for (let c: number = 0; c < 9; c++) {
        const sig: number[] | null = cellSigFromGray(
          warpedGray, outSize,
          c * warpCellW, r * warpCellH,
          warpCellW, warpCellH, warpIsDark, warpBg
        );
        if (sig !== null) {
          sigCount++;
          grid[r * 9 + c] = recognizeDigit(sig, countInk(sig));
          g_lastPixelConfidence[r * 9 + c] = getLastConfidence();
          if (grid[r * 9 + c] > 0) { digitCount++; }
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
      let sigCount2: number = 0;
      let digitCount2: number = 0;
      for (let r: number = 0; r < 9; r++) {
        for (let c: number = 0; c < 9; c++) {
          const cLeft: number = gridLines.vLines[c];
          const cTop: number = gridLines.hLines[r];
          const cW: number = gridLines.vLines[c + 1] - cLeft;
          const cH: number = gridLines.hLines[r + 1] - cTop;
          const sig: number[] | null = cellSigFromGray(
            gray, width, cLeft, cTop, cW, cH, bbox.isDark, bg
          );
          if (sig !== null) {
            sigCount2++;
            const inkCount: number = countInk(sig);
            const digit: number = recognizeDigit(sig, inkCount);
            g_lastPixelConfidence[r * 9 + c] = getLastConfidence();
            if (digit > 0 && !validateCellCentering(gray, width, height, cLeft, cTop, cW, cH, bbox.isDark, bg)) {
              const fallbackW: number = (bbox.right - bbox.left) / 9;
              const fallbackH: number = (bbox.bottom - bbox.top) / 9;
              const fallbackLeft: number = bbox.left + c * fallbackW;
              const fallbackTop: number = bbox.top + r * fallbackH;
              const fallbackSig: number[] | null = cellSigFromGray(
                gray, width, fallbackLeft, fallbackTop, fallbackW, fallbackH, bbox.isDark, bg
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
      let sigCount3: number = 0;
      let digitCount3: number = 0;
      for (let r: number = 0; r < 9; r++) {
        for (let c: number = 0; c < 9; c++) {
          const sig: number[] | null = cellSigFromGray(
            gray, width,
            bbox.left + c * cellW, bbox.top + r * cellH,
            cellW, cellH, bbox.isDark, bg
          );
          if (sig !== null) {
            sigCount3++;
            grid[r * 9 + c] = recognizeDigit(sig, countInk(sig));
            g_lastPixelConfidence[r * 9 + c] = getLastConfidence();
            if (grid[r * 9 + c] > 0) { digitCount3++; }
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
