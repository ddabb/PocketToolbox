import {
  SIG_ROWS, SIG_COLS, SIG_LEN, MAX_INK_COUNT,
  THIN1_MIN_INK_COUNT, CELL_MARGIN_RATIO, MIN_CELL_INK_RATIO, OTSU_BG_MIN_DIFF,
  OTSU_MIN_PIXELS
} from './SudokuPixelKernel';
import { countInk, isInkPixel, otsuThreshold } from './SudokuGrayOps';

// Detect and strip grid lines from signature edges.
// Grid lines intrude into cells as near-solid rows (horizontal) or columns (vertical)
// at the edge of the signature. A real digit never has ink in >=80% of positions
// along an entire edge row or column. If detected, clear that edge to prevent
// the grid line from corrupting the digit signature.
// Also checks the second row/column inward — a thick grid line may span 2 bins.
const GRID_LINE_RATIO: number = 0.80;

export function stripEdgeGridLines(sig: number[]): void {
  const minCount: number = Math.floor(Math.min(SIG_ROWS, SIG_COLS) * GRID_LINE_RATIO);

  // Top edge rows (row 0, row 1)
  for (let row: number = 0; row <= 1 && row < SIG_ROWS; row++) {
    let inkCount: number = 0;
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[row * SIG_COLS + c] === 1) { inkCount++; }
    }
    if (inkCount >= minCount) {
      for (let c: number = 0; c < SIG_COLS; c++) {
        sig[row * SIG_COLS + c] = 0;
      }
    }
  }

  // Bottom edge rows (last row, second-to-last row)
  for (let row: number = SIG_ROWS - 1; row >= SIG_ROWS - 2 && row >= 0; row--) {
    let inkCount: number = 0;
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[row * SIG_COLS + c] === 1) { inkCount++; }
    }
    if (inkCount >= minCount) {
      for (let c: number = 0; c < SIG_COLS; c++) {
        sig[row * SIG_COLS + c] = 0;
      }
    }
  }

  // Left edge columns (col 0, col 1)
  for (let col: number = 0; col <= 1 && col < SIG_COLS; col++) {
    let inkCount: number = 0;
    for (let r: number = 0; r < SIG_ROWS; r++) {
      if (sig[r * SIG_COLS + col] === 1) { inkCount++; }
    }
    if (inkCount >= minCount) {
      for (let r: number = 0; r < SIG_ROWS; r++) {
        sig[r * SIG_COLS + col] = 0;
      }
    }
  }

  // Right edge columns (last col, second-to-last col)
  for (let col: number = SIG_COLS - 1; col >= SIG_COLS - 2 && col >= 0; col--) {
    let inkCount: number = 0;
    for (let r: number = 0; r < SIG_ROWS; r++) {
      if (sig[r * SIG_COLS + col] === 1) { inkCount++; }
    }
    if (inkCount >= minCount) {
      for (let r: number = 0; r < SIG_ROWS; r++) {
        sig[r * SIG_COLS + col] = 0;
      }
    }
  }
}

export function stripFullHeightVerticalStrokes(sig: number[]): void {
  const FULL_HEIGHT_THRESH: number = SIG_ROWS * 0.70;
  const colInk: number[] = new Array<number>(SIG_COLS).fill(0);
  for (let c: number = 0; c < SIG_COLS; c++) {
    for (let r: number = 0; r < SIG_ROWS; r++) {
      if (sig[r * SIG_COLS + c] === 1) { colInk[c]++; }
    }
  }
  let rightMostHigh: number = -1;
  for (let c: number = SIG_COLS - 1; c >= 0; c--) {
    if (colInk[c] >= FULL_HEIGHT_THRESH) { rightMostHigh = c; break; }
  }
  let c: number = 0;
  while (c < SIG_COLS) {
    if (colInk[c] >= FULL_HEIGHT_THRESH) {
      let clusterEnd: number = c;
      while (clusterEnd + 1 < SIG_COLS && colInk[clusterEnd + 1] >= FULL_HEIGHT_THRESH * 0.5) {
        clusterEnd++;
      }
      const clusterW: number = clusterEnd - c + 1;
      if (clusterW <= 4 && c < rightMostHigh - 2) {
        for (let cc: number = c; cc <= clusterEnd; cc++) {
          for (let r: number = 0; r < SIG_ROWS; r++) {
            sig[r * SIG_COLS + cc] = 0;
          }
        }
      }
      c = clusterEnd + 1;
    } else {
      c++;
    }
  }
}

function cellSigOtsuFallbackGray(
  gray: Float32Array, width: number,
  bminX: number, bminY: number, bw: number, bh: number,
  isDark: boolean, bg: number
): number[] | null {
  const H: number = Math.floor(gray.length / width);
  const bboxHist: number[] = new Array<number>(256).fill(0);
  let bboxTotal: number = 0;
  for (let y: number = bminY; y < bminY + bh; y++) {
    for (let x: number = bminX; x < bminX + bw; x++) {
      if (y >= 0 && y < H && x >= 0 && x < width) {
        const g: number = gray[y * width + x];
        const gi: number = Math.floor(g);
        if (gi >= 0 && gi <= 255) {
          bboxHist[gi]++;
          bboxTotal++;
        }
      }
    }
  }
  if (bboxTotal < OTSU_MIN_PIXELS) { return null; }

  const otsuT: number = otsuThreshold(bboxHist, bboxTotal);
  if (Math.abs(otsuT - bg) < OTSU_BG_MIN_DIFF) { return null; }

  const sig: number[] = new Array<number>(SIG_LEN).fill(0);
  for (let r: number = 0; r < SIG_ROWS; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      const sx0: number = bminX + Math.floor(bw * c / SIG_COLS);
      const sx1: number = bminX + Math.floor(bw * (c + 1) / SIG_COLS);
      const sy0: number = bminY + Math.floor(bh * r / SIG_ROWS);
      const sy1: number = bminY + Math.floor(bh * (r + 1) / SIG_ROWS);
      let s: number = 0;
      let n: number = 0;
      for (let y: number = sy0; y < sy1; y++) {
        for (let x: number = sx0; x < sx1; x++) {
          if (y >= 0 && y < H && x >= 0 && x < width) {
            s += gray[y * width + x];
            n++;
          }
        }
      }
      const avg: number = n > 0 ? s / n : bg;
      sig[r * SIG_COLS + c] = isDark ? (avg > otsuT ? 1 : 0) : (avg < otsuT ? 1 : 0);
    }
  }

  const inkCount: number = countInk(sig);
  if (inkCount < THIN1_MIN_INK_COUNT || inkCount > MAX_INK_COUNT) { return null; }
  return sig;
}

export function cellSig(
  pixels: Uint8Array,
  width: number,
  cellLeft: number,
  cellTop: number,
  cellW: number,
  cellH: number,
  isDark: boolean,
  bg: number
): number[] | null {
  const mx: number = cellW * CELL_MARGIN_RATIO;
  const my: number = cellH * CELL_MARGIN_RATIO;
  const x0: number = Math.floor(cellLeft + mx);
  const y0: number = Math.floor(cellTop + my);
  const x1: number = Math.floor(cellLeft + cellW - mx);
  const y1: number = Math.floor(cellTop + cellH - my);

  let ink: number = 0;
  let area: number = 0;
  let bminX: number = 1000000;
  let bmaxX: number = -1;
  let bminY: number = 1000000;
  let bmaxY: number = -1;

  for (let y: number = y0; y < y1; y++) {
    for (let x: number = x0; x < x1; x++) {
      area++;
      const g: number = 0.299 * pixels[(y * width + x) * 4] +
        0.587 * pixels[(y * width + x) * 4 + 1] +
        0.114 * pixels[(y * width + x) * 4 + 2];
      if (isInkPixel(g, bg, isDark)) {
        ink++;
        if (x < bminX) { bminX = x; }
        if (x > bmaxX) { bmaxX = x; }
        if (y < bminY) { bminY = y; }
        if (y > bmaxY) { bmaxY = y; }
      }
    }
  }

  if (ink < area * MIN_CELL_INK_RATIO || bmaxX < 0) {
    return null;
  }

  const bw: number = bmaxX - bminX + 1;
  const bh: number = bmaxY - bminY + 1;

  const sig: number[] = new Array<number>(SIG_LEN).fill(0);
  for (let r: number = 0; r < SIG_ROWS; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      const sx0: number = bminX + Math.floor(bw * c / SIG_COLS);
      const sx1: number = bminX + Math.floor(bw * (c + 1) / SIG_COLS);
      const sy0: number = bminY + Math.floor(bh * r / SIG_ROWS);
      const sy1: number = bminY + Math.floor(bh * (r + 1) / SIG_ROWS);
      let s: number = 0;
      let n: number = 0;
      for (let y: number = sy0; y < sy1; y++) {
        for (let x: number = sx0; x < sx1; x++) {
          s += 0.299 * pixels[(y * width + x) * 4] +
            0.587 * pixels[(y * width + x) * 4 + 1] +
            0.114 * pixels[(y * width + x) * 4 + 2];
          n++;
        }
      }
      const avg: number = n > 0 ? s / n : bg;
      sig[r * SIG_COLS + c] = isInkPixel(avg, bg, isDark) ? 1 : 0;
    }
  }

  const inkCount: number = countInk(sig);
  if (inkCount < THIN1_MIN_INK_COUNT || inkCount > MAX_INK_COUNT) {
    const fallbackSig: number[] | null = cellSigOtsuFallback(
      pixels, width, bminX, bminY, bw, bh, isDark, bg
    );
    if (fallbackSig !== null) {
      const fbInk: number = countInk(fallbackSig);
      if (fbInk >= THIN1_MIN_INK_COUNT && fbInk <= MAX_INK_COUNT) {
        return fallbackSig;
      }
    }
    return null;
  }
  return sig;
}

function cellSigOtsuFallback(
  pixels: Uint8Array, width: number,
  bminX: number, bminY: number, bw: number, bh: number,
  isDark: boolean, bg: number
): number[] | null {
  const bboxHist: number[] = new Array<number>(256).fill(0);
  let bboxTotal: number = 0;
  for (let y: number = bminY; y < bminY + bh; y++) {
    for (let x: number = bminX; x < bminX + bw; x++) {
      const g: number = 0.299 * pixels[(y * width + x) * 4] +
        0.587 * pixels[(y * width + x) * 4 + 1] +
        0.114 * pixels[(y * width + x) * 4 + 2];
      const gi: number = Math.floor(g);
      bboxHist[gi]++;
      bboxTotal++;
    }
  }
  if (bboxTotal < OTSU_MIN_PIXELS) { return null; }

  const otsuT: number = otsuThreshold(bboxHist, bboxTotal);
  if (Math.abs(otsuT - bg) < OTSU_BG_MIN_DIFF) { return null; }

  const sig: number[] = new Array<number>(SIG_LEN).fill(0);
  for (let r: number = 0; r < SIG_ROWS; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      const sx0: number = bminX + Math.floor(bw * c / SIG_COLS);
      const sx1: number = bminX + Math.floor(bw * (c + 1) / SIG_COLS);
      const sy0: number = bminY + Math.floor(bh * r / SIG_ROWS);
      const sy1: number = bminY + Math.floor(bh * (r + 1) / SIG_ROWS);
      let s: number = 0;
      let n: number = 0;
      for (let y: number = sy0; y < sy1; y++) {
        for (let x: number = sx0; x < sx1; x++) {
          s += 0.299 * pixels[(y * width + x) * 4] +
            0.587 * pixels[(y * width + x) * 4 + 1] +
            0.114 * pixels[(y * width + x) * 4 + 2];
          n++;
        }
      }
      const avg: number = n > 0 ? s / n : bg;
      sig[r * SIG_COLS + c] = isDark ? (avg > otsuT ? 1 : 0) : (avg < otsuT ? 1 : 0);
    }
  }

  const inkCount: number = countInk(sig);
  if (inkCount < THIN1_MIN_INK_COUNT || inkCount > MAX_INK_COUNT) { return null; }
  return sig;
}
