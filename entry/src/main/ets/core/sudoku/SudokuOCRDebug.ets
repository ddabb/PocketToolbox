import { OCRDebugInfo, OCRDebugStep, g_lastDebugVkRawText, g_lastDebugVkBlockCount, g_lastDebugVkBlockDetail, g_lastDebugVkOcrSize, g_lastDebugVkOcrError, g_lastDebugRawDigitPositions, g_lastDebugProbeInfo, g_lastDebugPixelBgInfo, g_lastDebugPixelBboxLocator, g_lastDebugPixelWarpInfo, g_lastDebugPixelCellStats, g_lastDebugPixelCellCoords, g_lastDebugFixDetails } from './SudokuOCRTypes';
import { getLastBboxDiag } from './SudokuPixel';

export function formatGridStr(grid: number[] | null): string {
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

export function formatConfStr(conf: number[] | null): string {
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

export function buildDebugInfo(
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
