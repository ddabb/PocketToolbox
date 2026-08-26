import { BoardBBox } from './SudokuPixel';

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

export interface CellCoordInfo {
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

export interface PerCellVkDiag {
  cropFail: number;
  noBlock: number;
  noCenter: number;
  found: number;
  samples: string[];
}

export interface PixelConflictCandidate {
  idx: number;
  digit: number;
  confidence: number;
}

export interface VisionKitGridResult {
  grid: number[];
  boardL: number;
  boardT: number;
  boardW: number;
  boardH: number;
  imgW: number;
  imgH: number;
}

export interface RawDigit {
  cx: number;
  cy: number;
  digit: number;
}

export interface AdaptiveResizeParams {
  targetW: number;
  targetH: number;
  targetCellPx: number;
}

export let g_lastPixelConfidence: number[] = new Array<number>(81).fill(0);
export let g_lastCellCoords: CellCoordInfo[] = [];
export let g_debugInfo: OCRDebugInfo | null = null;
export let g_lastDebugBbox: string = '';
export let g_lastDebugResize: string = '';
export let g_lastDebugRawDigits: number = 0;
export let g_lastDebugRawDigitPositions: string = '';
export let g_lastDebugConflicts: number[] = [];
export let g_probeBbox: BoardBBox | null = null;
export let g_probeResizeW: number = 0;
export let g_probeResizeH: number = 0;
export let g_fittedBoardL: number = -1;
export let g_fittedBoardT: number = -1;
export let g_fittedBoardR: number = -1;
export let g_fittedBoardB: number = -1;
export let g_lastDebugLowConf: number[] = [];
export let g_lastDebugEmpty: number[] = [];
export let g_lastDebugFixCount: number = 0;
export let g_vkInited: boolean = false;
export let g_vkFailed: boolean = false;
export let g_cachedPixels: Uint8Array = new Uint8Array(0);
export let g_cachedImgW: number = 0;
export let g_cachedImgH: number = 0;
export let g_lastDebugVkRawText: string = '';
export let g_lastDebugVkBlockCount: number = 0;
export let g_lastDebugVkOcrSize: string = '';
export let g_lastDebugVkOcrError: string = '';
export let g_lastDebugVkBlockDetail: string = '';
export let g_lastDebugProbeInfo: string = '';
export let g_lastDebugPixelBgInfo: string = '';
export let g_lastDebugPixelBboxLocator: string = '';
export let g_lastDebugPixelWarpInfo: string = '';
export let g_lastDebugPixelCellStats: string = '';
export let g_lastDebugPixelCellCoords: string = '';
export let g_lastDebugFixDetails: string = '';
export let g_lastRecognizeDiag: string = '';
export let g_perCellVkDiag: PerCellVkDiag = {
  cropFail: 0, noBlock: 0, noCenter: 0, found: 0, samples: []
};

export function getOCRDebugInfo(): OCRDebugInfo | null {
  return g_debugInfo;
}

export function getLastPixelConfidence(): number[] {
  return g_lastPixelConfidence;
}
