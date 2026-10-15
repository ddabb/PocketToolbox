import {
  DOMAIN, TAG, DigitTemplate, SP,
  SIG_ROWS, SIG_COLS, SIG_LEN, THIN1_MIN_INK_COUNT,
  TEMPLATE_MISMATCH_PENALTY
} from './SudokuPixelKernel';
import { templateMatchesInkFilter } from './SudokuSigAnalysis';

import { hilog } from '@kit.PerformanceAnalysisKit';

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

export function detectThinOne(sig: number[], inkCount: number): boolean {
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

// Loose "1" detector: allows a foot serif that widens the bbox, but requires
// a dominant vertical stem, no wide top bar (7), and solid mid-height coverage.
export function detectLooseOne(sig: number[], inkCount: number): boolean {
  if (inkCount < THIN1_MIN_INK_COUNT) { return false; }
  const rowInk: number[] = new Array<number>(SIG_ROWS).fill(0);
  let minRow: number = SIG_ROWS;
  let maxRow: number = -1;
  for (let r: number = 0; r < SIG_ROWS; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) {
        rowInk[r]++;
        if (r < minRow) { minRow = r; }
        if (r > maxRow) { maxRow = r; }
      }
    }
  }
  if (maxRow < 0) { return false; }
  const inkHeight: number = maxRow - minRow + 1;
  if (inkHeight < SIG_ROWS * 0.50) { return false; }

  const topRowL: number = Math.floor(SIG_ROWS * 0.08);
  const topEndL: number = Math.floor(SIG_ROWS * 0.28);
  let topMaxSpanL: number = 0;
  for (let rL: number = topRowL; rL < topEndL; rL++) {
    let spanL: number = 0;
    let rowMaxL: number = 0;
    for (let cL: number = 0; cL < SIG_COLS; cL++) {
      if (sig[rL * SIG_COLS + cL] === 1) {
        spanL++;
        if (spanL > rowMaxL) { rowMaxL = spanL; }
      } else {
        spanL = 0;
      }
    }
    if (rowMaxL > topMaxSpanL) { topMaxSpanL = rowMaxL; }
  }
  if (topMaxSpanL >= SIG_COLS * 0.6) { return false; }

  let bestColContig: number = 0;
  for (let cS: number = 0; cS < SIG_COLS; cS++) {
    let curS: number = 0;
    let bestS: number = 0;
    for (let rS: number = 0; rS < SIG_ROWS; rS++) {
      if (sig[rS * SIG_COLS + cS] === 1) {
        curS++;
        if (curS > bestS) { bestS = curS; }
      } else {
        curS = 0;
      }
    }
    if (bestS > bestColContig) { bestColContig = bestS; }
  }
  if (bestColContig < inkHeight * 0.55) { return false; }

  const startRowL: number = Math.floor(SIG_ROWS * 0.2);
  const endRowL: number = Math.floor(SIG_ROWS * 0.8);
  let rowsWithInkL: number = 0;
  const totalMidRowsL: number = endRowL - startRowL;
  for (let rL2: number = startRowL; rL2 < endRowL; rL2++) {
    if (rowInk[rL2] > 0) { rowsWithInkL++; }
  }
  if (rowsWithInkL < totalMidRowsL * 0.60) { return false; }

  return true;
}

export function tryStripLeftEdgeAs1(sig: number[], inkCount: number, origBestDigit: number, origBestScore: number): number {
  if (origBestDigit !== 4) { return 0; }

  let leftColInk: number = 0;
  for (let r: number = 0; r < SIG_ROWS; r++) {
    if (sig[r * SIG_COLS] === 1) { leftColInk++; }
  }
  if (leftColInk < 3) {
    const botTop: number = Math.floor(SIG_ROWS * 0.50);
    let colSum: number = 0;
    let inkCnt: number = 0;
    for (let r2: number = botTop; r2 < SIG_ROWS; r2++) {
      for (let c2: number = 0; c2 < SIG_COLS; c2++) {
        if (sig[r2 * SIG_COLS + c2] === 1) { colSum += c2; inkCnt++; }
      }
    }
    const colCent: number = inkCnt > 0 ? colSum / inkCnt : SIG_COLS / 2;
    if (colCent > SIG_COLS * 0.55) {
      SP.lastPixelDiag = `stripLeft→1: colCent=${colCent.toFixed(1)} col0=${leftColInk}`;
      return 1;
    }
    SP.lastPixelDiag = `stripLeftSkip: col0=${leftColInk} colCent=${colCent.toFixed(1)}`;
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
    SP.lastPixelDiag = `stripLeftSkip: hasHBar span=${maxMidRowSpan}`;
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
    SP.lastPixelDiag = `stripLeftCleanInkLow: cleanInk=${cleanInk}`;
    return 0;
  }

  const digitBestScore: number[] = new Array<number>(10).fill(-100000);
  const digitBestRecall: number[] = new Array<number>(10).fill(0);
  for (let d: number = 1; d <= 9; d++) {
    const tplsD: DigitTemplate[] = SP.templatesByDigit[d];
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
    SP.lastPixelDiag = `stripLeftFail: score1=${score1} recall1=${recall1.toFixed(2)}`;
    return 0;
  }

  if (bestCleanDigit !== 1) {
    SP.lastPixelDiag = `stripLeftFail: bestClean=${bestCleanDigit}(${bestCleanScore.toFixed(0)})>1`;
    return 0;
  }

  SP.lastPixelDiag = `stripLeft→1: score1=${score1} recall1=${recall1.toFixed(2)} cleanInk=${cleanInk}`;
  SP.lastConfidence = 0.55;
  return 1;
}

export function sigToCompactStr(sig: number[]): string {
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

export function isLikelyNot4(sig: number[]): boolean {
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
