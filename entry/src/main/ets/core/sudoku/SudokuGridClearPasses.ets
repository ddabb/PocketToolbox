import { hilog } from '@kit.PerformanceAnalysisKit';
import { g_lastPixelConfidence, g_lastRawInkPerCell } from './SudokuOCRTypes';
import {
  DOMAIN, TAG, yieldThread, EXISTING_PIXEL_ONLY_OVERRIDE_CONF, CONFUSABLE_PIXEL_OVERRIDE_CONF
} from './SudokuOCRUtils';
import { findConflictCells, isConfusablePair } from './SudokuGridConflict';
import { recognizeDigitPixel } from './SudokuGridPixel';
import {
  BoardBBox, getLastConfidence, getLastRawInkRatio, getLastSigQualityFail,
  cellSigFromGrayLowThresh, countInk, MIN_CELL_INK_RATIO,
  ULTRA_LOW_INK_THRESH, SIG_ROWS, SIG_COLS
} from './SudokuPixel';

export async function applyPixelAdjudicationPass(
  grid: number[],
  cellConfidence: number[],
  gray: Float32Array,
  imgW: number,
  boardL: number,
  boardT: number,
  cellW: number,
  cellH: number,
  bbox: BoardBBox,
  bg: number
): Promise<number> {
  let pixelAdjFixCount: number = 0;
  for (let i: number = 0; i < 81; i++) {
    if (grid[i] === 0) { continue; }
    await yieldThread();
    const row: number = Math.floor(i / 9);
    const col: number = i % 9;
    const cLeft: number = boardL + col * cellW;
    const cTop: number = boardT + row * cellH;
    const pxlDigit: number | null = await recognizeDigitPixel(gray, imgW, cLeft, cTop, cellW, cellH, bbox.isDark, bg, row, col);
    if (pxlDigit === null || pxlDigit === grid[i]) { continue; }
    if (getLastSigQualityFail()) { continue; }
    const pxlDigitVal: number = pxlDigit as number;
    if (!isConfusablePair(grid[i], pxlDigitVal)) { continue; }
    const pxlConf: number = getLastConfidence();
    const isConflict: boolean = findConflictCells(grid).some((ci: number) => ci === i);
    if (isConflict && pxlConf > cellConfidence[i]) {
      hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 像素裁决候选(冲突) [%{public}d]=%{public}d→%{public}d pxlConf=%{public}.2f cellConf=%{public}.2f',
        i, grid[i], pxlDigitVal, pxlConf, cellConfidence[i]);
      const beforeConf: number = findConflictCells(grid).length;
      const orig: number = grid[i];
      grid[i] = pxlDigitVal;
      const afterConf: number = findConflictCells(grid).length;
      if (afterConf < beforeConf) {
        hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 像素裁决(冲突) [%{public}d]=%{public}d→%{public}d 冲突%{public}d→%{public}d pxlConf=%{public}.2f',
          i, orig, pxlDigitVal, beforeConf, afterConf, pxlConf);
        pixelAdjFixCount++;
      } else {
        grid[i] = orig;
      }
    } else if (pxlConf >= CONFUSABLE_PIXEL_OVERRIDE_CONF && pxlConf >= EXISTING_PIXEL_ONLY_OVERRIDE_CONF && pxlConf > cellConfidence[i]) {
      const orig: number = grid[i];
      grid[i] = pxlDigitVal;
      const cellStillInConflict: boolean = findConflictCells(grid).some((ci: number) => ci === i);
      if (!cellStillInConflict) {
        hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 像素裁决(置信%{public}.2f>%{public}.2f) [%{public}d]=%{public}d→%{public}d',
          pxlConf, cellConfidence[i], i, orig, pxlDigitVal);
        pixelAdjFixCount++;
      } else {
        grid[i] = orig;
      }
    }
  }
  if (pixelAdjFixCount > 0) {
    hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 像素裁决修正%{public}d个', pixelAdjFixCount);
  }
  return pixelAdjFixCount;
}

export async function clearFinalNoInkConflicts(
  grid: number[],
  gray: Float32Array,
  imgW: number,
  boardL: number,
  boardT: number,
  cellW: number,
  cellH: number,
  bbox: BoardBBox,
  bg: number
): Promise<number> {
  const remainingConflicts: number[] = findConflictCells(grid);
  const finalClearNoInk: number[] = [];
  for (const ci of remainingConflicts) {
    await yieldThread();
    const ciRow: number = Math.floor(ci / 9);
    const ciCol: number = ci % 9;
    const ciLeft: number = boardL + ciCol * cellW;
    const ciTop: number = boardT + ciRow * cellH;
    const ciDigit: number | null = await recognizeDigitPixel(gray, imgW, ciLeft, ciTop, cellW, cellH, bbox.isDark, bg, ciRow, ciCol);
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
  }
  return finalClearNoInk.length;
}

export async function clearLowConfConflicts(
  grid: number[],
  remainingConflicts: number[],
  gray: Float32Array,
  imgW: number,
  boardL: number,
  boardT: number,
  cellW: number,
  cellH: number,
  bbox: BoardBBox,
  bg: number
): Promise<number> {
  const lowConfClear: number[] = [];
  for (const ci of remainingConflicts) {
    await yieldThread();
    const ciRow: number = Math.floor(ci / 9);
    const ciCol: number = ci % 9;
    const ciLeft: number = boardL + ciCol * cellW;
    const ciTop: number = boardT + ciRow * cellH;
    const ciConf: number = g_lastPixelConfidence[ci];
    const ciFirstInk: number = g_lastRawInkPerCell.length > ci ? g_lastRawInkPerCell[ci] : 0;
    await recognizeDigitPixel(gray, imgW, ciLeft, ciTop, cellW, cellH, bbox.isDark, bg, ciRow, ciCol);
    const ciRawInk: number = getLastRawInkRatio();
    hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 冲突清洗检查(%{public}d,%{public}d)=%{public}d conf=%{public}.2f recInk=%{public}.4f firstInk=%{public}.4f',
      ciRow, ciCol, grid[ci], ciConf, ciRawInk, ciFirstInk);
    if (ciConf < 0.50 || ciRawInk > 0.75 || ciFirstInk > 0.60) {
      lowConfClear.push(ci);
    }
  }
  for (const ci of lowConfClear) {
    const origVal: number = grid[ci];
    grid[ci] = 0;
    hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 冲突低置信清除(%{public}d,%{public}d) %{public}d→0 conf=%{public}.2f firstInk=%{public}.4f',
      Math.floor(ci / 9), ci % 9, origVal, g_lastPixelConfidence[ci],
      g_lastRawInkPerCell.length > ci ? g_lastRawInkPerCell[ci] : 0);
  }
  return lowConfClear.length;
}

export async function clearHighInkSolidBlocks(
  grid: number[],
  remainingConflicts: number[],
  gray: Float32Array,
  imgW: number,
  boardL: number,
  boardT: number,
  cellW: number,
  cellH: number,
  bbox: BoardBBox,
  bg: number
): Promise<number> {
  const conflictSet: Set<number> = new Set<number>(remainingConflicts);
  const solidClear: number[] = [];
  for (let si: number = 0; si < 81; si++) {
    if (grid[si] === 0 || conflictSet.has(si)) { continue; }
    const siRawInk: number = g_lastRawInkPerCell[si];
    if (siRawInk <= 0.75) { continue; }
    await yieldThread();
    const siRow: number = Math.floor(si / 9);
    const siCol: number = si % 9;
    const siLeft: number = boardL + siCol * cellW;
    const siTop: number = boardT + siRow * cellH;
    const solidSig: number[] | null = await cellSigFromGrayLowThresh(
      gray, imgW, siLeft, siTop, cellW, cellH, bbox.isDark, bg, siRow, siCol,
      ULTRA_LOW_INK_THRESH
    );
    if (solidSig === null) { continue; }
    const solidInk: number = countInk(solidSig);
    if (solidInk < SIG_ROWS * SIG_COLS * 0.6) { continue; }
    solidClear.push(si);
  }
  if (solidClear.length > 0) {
    for (const si of solidClear) {
      const origVal: number = grid[si];
      grid[si] = 0;
      hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 高墨实心块清除(%{public}d,%{public}d) %{public}d→0 rawInk=%{public}.4f',
        Math.floor(si / 9), si % 9, origVal, g_lastRawInkPerCell[si]);
    }
  }
  return solidClear.length;
}
