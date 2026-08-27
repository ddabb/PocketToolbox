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

export function setDebugInfo(v: OCRDebugInfo | null): void { g_debugInfo = v; }

export function getLastPixelConfidence(): number[] {
  return g_lastPixelConfidence;
}

export function setLastDebugVkRawText(v: string): void { g_lastDebugVkRawText = v; }
export function setLastDebugVkBlockCount(v: number): void { g_lastDebugVkBlockCount = v; }
export function setLastDebugVkOcrSize(v: string): void { g_lastDebugVkOcrSize = v; }
export function setLastDebugVkOcrError(v: string): void { g_lastDebugVkOcrError = v; }
export function setLastDebugProbeInfo(v: string): void { g_lastDebugProbeInfo = v; }
export function setVkInited(v: boolean): void { g_vkInited = v; }
export function setVkFailed(v: boolean): void { g_vkFailed = v; }
export function setCachedPixels(v: Uint8Array): void { g_cachedPixels = v; }
export function setCachedImgW(v: number): void { g_cachedImgW = v; }
export function setCachedImgH(v: number): void { g_cachedImgH = v; }
export function setProbeBbox(v: BoardBBox | null): void { g_probeBbox = v; }
export function setProbeResizeW(v: number): void { g_probeResizeW = v; }
export function setProbeResizeH(v: number): void { g_probeResizeH = v; }
export function setLastDebugBbox(v: string): void { g_lastDebugBbox = v; }
export function setLastDebugResize(v: string): void { g_lastDebugResize = v; }
export function setLastDebugRawDigits(v: number): void { g_lastDebugRawDigits = v; }
export function setLastDebugRawDigitPositions(v: string): void { g_lastDebugRawDigitPositions = v; }
export function setLastDebugVkBlockDetail(v: string): void { g_lastDebugVkBlockDetail = v; }
export function setFittedBoardL(v: number): void { g_fittedBoardL = v; }
export function setFittedBoardT(v: number): void { g_fittedBoardT = v; }
export function setFittedBoardR(v: number): void { g_fittedBoardR = v; }
export function setFittedBoardB(v: number): void { g_fittedBoardB = v; }
export function setLastRecognizeDiag(v: string): void { g_lastRecognizeDiag = v; }
export function setLastDebugFixDetails(v: string): void { g_lastDebugFixDetails = v; }
export function setLastDebugConflicts(v: number[]): void { g_lastDebugConflicts = v; }
export function setLastDebugLowConf(v: number[]): void { g_lastDebugLowConf = v; }
export function setLastDebugEmpty(v: number[]): void { g_lastDebugEmpty = v; }
export function setLastDebugFixCount(v: number): void { g_lastDebugFixCount = v; }
export function setPerPixelVkDiag(v: PerCellVkDiag): void { g_perCellVkDiag = v; }
export function setLastPixelConfidence(v: number[]): void { g_lastPixelConfidence = v; }
export function setLastCellCoords(v: CellCoordInfo[]): void { g_lastCellCoords = v; }
export function setLastDebugPixelBgInfo(v: string): void { g_lastDebugPixelBgInfo = v; }
export function setLastDebugPixelBboxLocator(v: string): void { g_lastDebugPixelBboxLocator = v; }
export function setLastDebugPixelWarpInfo(v: string): void { g_lastDebugPixelWarpInfo = v; }
export function setLastDebugPixelCellStats(v: string): void { g_lastDebugPixelCellStats = v; }
export function setLastDebugPixelCellCoords(v: string): void { g_lastDebugPixelCellCoords = v; }
