import {
  BoardBBox, GridLines, SP, INK_THRESH,
  CONSERVATIVE_MIN_DIM, CENTERING_MARGIN, CENTERING_MIN_INK, CENTERING_MAX_OFFSET,
  GRID_LINE_MIN_MAX_FRAC, GRID_LINE_INK_EXIST_THRESH
} from './SudokuPixelKernel';
import { grayInkPixel } from './SudokuGrayOps';

export function detectGridLineWidths(
  gray: Float32Array,
  imgW: number,
  boardL: number, boardT: number,
  boardR: number, boardB: number,
  isDark: boolean, bg: number
): void {
  SP.gridLineCropTop = new Array<number>(81).fill(0);
  SP.gridLineCropBot = new Array<number>(81).fill(0);
  SP.gridLineCropLeft = new Array<number>(81).fill(0);
  SP.gridLineCropRight = new Array<number>(81).fill(0);
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
      SP.gridLineCropTop[idx] = Math.max(minMargin, Math.min(rawTop, maxM));
      SP.gridLineCropBot[idx] = Math.max(minMargin, Math.min(rawBot, maxM));
      SP.gridLineCropLeft[idx] = Math.max(minMargin, Math.min(rawLeft, maxM));
      SP.gridLineCropRight[idx] = Math.max(minMargin, Math.min(rawRight, maxM));
    }
  }

  SP.gridLineDetected = true;
  const diagH: string = hLineInkDown.map((d: number, i: number) => `${hLineInkUp[i]}+${d}`).join(',');
  const diagV: string = vLineInkRight.map((r: number, j: number) => `${vLineInkLeft[j]}+${r}`).join(',');
  SP.lastPixelDiag = `gridLineCrop: hUp=[${hLineInkUp.join(',')}] hDown=[${hLineInkDown.join(',')}] vLeft=[${vLineInkLeft.join(',')}] vRight=[${vLineInkRight.join(',')}]`;
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
