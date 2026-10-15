import { hilog } from '@kit.PerformanceAnalysisKit';
import { OCRResult, PixelConflictCandidate, g_lastRawInkPerCell } from './SudokuOCRTypes';
import {
  DOMAIN, TAG, LOW_CONFIDENCE_THRESHOLD, CONFUSABLE_DIGITS, CONFUSABLE_RECHECK_CONFIDENCE
} from './SudokuOCRUtils';

export function findConflictCells(grid: number[]): number[] {
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

export function isConfusablePair(a: number, b: number): boolean {
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
  if ((a === 1 && b === 3) || (a === 3 && b === 1)) { return true; }
  return false;
}

export function conflictCountAfterSet(grid: number[], idx: number, digit: number): number {
  const copyGrid: number[] = [...grid];
  copyGrid[idx] = digit;
  return findConflictCells(copyGrid).length;
}

export function applyBestPixelConflictPair(grid: number[], candidates: PixelConflictCandidate[]): string {
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

export class GridFixTargets {
  conflictIndices: number[] = [];
  lowConfIndices: number[] = [];
  confusableIndices: number[] = [];
  emptyIndices: number[] = [];
  lowInkConfusableIndices: number[] = [];
  highInkSuspiciousIndices: number[] = [];
  allFixIndices: number[] = [];
}

export function computeGridFixTargets(ocrResult: OCRResult, grid: number[]): GridFixTargets {
  const targets: GridFixTargets = new GridFixTargets();

  const conflictIndices: number[] = findConflictCells(grid);
  targets.conflictIndices = conflictIndices;

  const lowConfIndices: number[] = [];
  if (ocrResult.confidence !== null) {
    for (let i: number = 0; i < 81; i++) {
      if (ocrResult.confidence[i] < LOW_CONFIDENCE_THRESHOLD && grid[i] > 0) {
        lowConfIndices.push(i);
      }
    }
  }
  targets.lowConfIndices = lowConfIndices;

  const confusableIndices: number[] = [];
  if (ocrResult.confidence !== null) {
    for (let i: number = 0; i < 81; i++) {
      if (grid[i] > 0 && CONFUSABLE_DIGITS.indexOf(grid[i]) >= 0 &&
        ocrResult.confidence[i] < CONFUSABLE_RECHECK_CONFIDENCE) {
        confusableIndices.push(i);
      }
    }
  } else {
    for (let i: number = 0; i < 81; i++) {
      if (grid[i] > 0 && CONFUSABLE_DIGITS.indexOf(grid[i]) >= 0) {
        confusableIndices.push(i);
      }
    }
  }
  targets.confusableIndices = confusableIndices;

  const emptyIndices: number[] = [];
  for (let i: number = 0; i < 81; i++) {
    if (grid[i] === 0) {
      emptyIndices.push(i);
    }
  }
  targets.emptyIndices = emptyIndices;

  const LOW_INK_CONFUSABLE_DIGITS: number[] = [1, 4, 7, 8];
  const lowInkConfusableIndices: number[] = [];
  for (let i: number = 0; i < 81; i++) {
    if (grid[i] > 0 && LOW_INK_CONFUSABLE_DIGITS.indexOf(grid[i]) >= 0) {
      const rawInkI: number = g_lastRawInkPerCell.length > i ? g_lastRawInkPerCell[i] : 0;
      if (rawInkI < 0.040) {
        lowInkConfusableIndices.push(i);
      }
    }
  }
  targets.lowInkConfusableIndices = lowInkConfusableIndices;

  const HIGH_INK_SUSPICIOUS_RATIO: number = 0.60;
  const highInkSuspiciousIndices: number[] = [];
  for (let i: number = 0; i < 81; i++) {
    if (grid[i] > 0) {
      const rawInkHi: number = g_lastRawInkPerCell.length > i ? g_lastRawInkPerCell[i] : 0;
      if (rawInkHi > HIGH_INK_SUSPICIOUS_RATIO) {
        highInkSuspiciousIndices.push(i);
      }
    }
  }
  targets.highInkSuspiciousIndices = highInkSuspiciousIndices;

  const fixSet: Set<number> = new Set<number>();
  for (const idx of conflictIndices) { fixSet.add(idx); }
  for (const idx of lowConfIndices) { fixSet.add(idx); }
  for (const idx of confusableIndices) { fixSet.add(idx); }
  for (const idx of emptyIndices) { fixSet.add(idx); }
  for (const idx of lowInkConfusableIndices) { fixSet.add(idx); }
  for (const idx of highInkSuspiciousIndices) { fixSet.add(idx); }

  const allFixIndices: number[] = [];
  fixSet.forEach((idx: number) => { allFixIndices.push(idx); });
  targets.allFixIndices = allFixIndices;

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

  return targets;
}
