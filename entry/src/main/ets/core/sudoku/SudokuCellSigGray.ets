import {
  SP, SIG_ROWS, SIG_COLS, SIG_LEN,
  MAX_INK_COUNT, THIN1_MIN_INK_COUNT, INK_THRESH, GRID_LINE_GRAY_DIFF,
  CELL_MARGIN_RATIO, MIN_CELL_INK_RATIO, SAUVOLA_MIN_DIM
} from './SudokuPixelKernel';
import { countInk, sauvolaThreshold } from './SudokuGrayOps';
import { stripEdgeGridLines, stripFullHeightVerticalStrokes } from './SudokuCellSig';

export async function cellSigFromGray(
  gray: Float32Array,
  width: number,
  cellLeft: number,
  cellTop: number,
  cellW: number,
  cellH: number,
  isDark: boolean,
  bg: number,
  gridRow: number = -1,
  gridCol: number = -1
): Promise<number[] | null> {
  let mxLeft: number = cellW * CELL_MARGIN_RATIO;
  let mxRight: number = cellW * CELL_MARGIN_RATIO;
  let myTop: number = cellH * CELL_MARGIN_RATIO;
  let myBot: number = cellH * CELL_MARGIN_RATIO;
  if (SP.gridLineDetected && gridRow >= 0 && gridRow < 9 && gridCol >= 0 && gridCol < 9) {
    const idx: number = gridRow * 9 + gridCol;
    const maxMarginW: number = Math.floor(cellW * 0.45);
    const maxMarginH: number = Math.floor(cellH * 0.45);
    mxLeft = Math.max(mxLeft, Math.min(SP.gridLineCropLeft[idx], maxMarginW));
    mxRight = Math.max(mxRight, Math.min(SP.gridLineCropRight[idx], maxMarginW));
    myTop = Math.max(myTop, Math.min(SP.gridLineCropTop[idx], maxMarginH));
    myBot = Math.max(myBot, Math.min(SP.gridLineCropBot[idx], maxMarginH));
  }
  const x0: number = Math.floor(cellLeft + mxLeft);
  const y0: number = Math.floor(cellTop + myTop);
  const x1: number = Math.floor(cellLeft + cellW - mxRight);
  const y1: number = Math.floor(cellTop + cellH - myBot);
  const H: number = Math.floor(gray.length / width);
  const cellWInner: number = x1 - x0;
  const cellHInner: number = y1 - y0;

  let effectiveBg: number = bg;
  let effectiveIsDark: boolean = isDark;
  if (cellWInner > 0 && cellHInner > 0) {
    const histProbe: number[] = new Array<number>(256).fill(0);
    for (let y: number = y0; y < y1; y++) {
      for (let x: number = x0; x < x1; x++) {
        const gv: number = Math.floor(gray[y * width + x]);
        if (gv >= 0 && gv < 256) { histProbe[gv]++; }
      }
    }
    let peakVal: number = 0;
    let peakCount: number = 0;
    for (let i: number = 0; i < 256; i++) {
      if (histProbe[i] > peakCount) { peakCount = histProbe[i]; peakVal = i; }
    }
    let aboveCount: number = 0;
    let belowCount: number = 0;
    for (let y: number = y0; y < y1; y++) {
      for (let x: number = x0; x < x1; x++) {
        const gv: number = gray[y * width + x];
        if (gv > peakVal + INK_THRESH * 0.5) { aboveCount++; }
        if (gv < peakVal - INK_THRESH * 0.5) { belowCount++; }
      }
    }
    effectiveIsDark = aboveCount > belowCount;
    if (Math.abs(peakVal - bg) > INK_THRESH * 0.5) {
      effectiveBg = peakVal;
    }
    SP.lastLocalBgInfo = `localBg: peak=${peakVal} bg=${bg.toFixed(1)} above=${aboveCount} below=${belowCount} effBg=${effectiveBg.toFixed(1)} effDark=${effectiveIsDark ? 1 : 0}`;
    SP.lastLocalBgPeak = peakVal;
  } else {
    SP.lastLocalBgInfo = `localBg: skip cellWInner=${cellWInner} cellHInner=${cellHInner}`;
    SP.lastLocalBgPeak = 255;
  }

  let savedPixels: number[] = [];
  let savedPositions: number[] = [];

  {
    const rowAvg: Float32Array = new Float32Array(cellHInner);
    for (let dy: number = 0; dy < cellHInner; dy++) {
      let sum: number = 0;
      const y: number = y0 + dy;
      for (let dx: number = 0; dx < cellWInner; dx++) {
        sum += gray[y * width + x0 + dx];
      }
      rowAvg[dy] = sum / cellWInner;
    }
    const colAvg: Float32Array = new Float32Array(cellWInner);
    for (let dx: number = 0; dx < cellWInner; dx++) {
      let sum: number = 0;
      const x: number = x0 + dx;
      for (let dy: number = 0; dy < cellHInner; dy++) {
        sum += gray[(y0 + dy) * width + x];
      }
      colAvg[dx] = sum / cellHInner;
    }
    const isGridRow: boolean[] = new Array<boolean>(cellHInner).fill(false);
    let gridRowCount: number = 0;
    for (let dy: number = 0; dy < cellHInner; dy++) {
      const diff: number = effectiveIsDark ? (rowAvg[dy] - effectiveBg) : (effectiveBg - rowAvg[dy]);
      if (diff > GRID_LINE_GRAY_DIFF) {
        let variance: number = 0;
        let inkCols: number = 0;
        const y: number = y0 + dy;
        for (let dx: number = 0; dx < cellWInner; dx++) {
          const g: number = gray[y * width + x0 + dx];
          const d: number = g - rowAvg[dy];
          variance += d * d;
          if (effectiveIsDark ? g > (effectiveBg + INK_THRESH) : g < (effectiveBg - INK_THRESH)) { inkCols++; }
        }
        variance = Math.sqrt(variance / cellWInner);
        // fullSpan guard (log117): A real grid line spans the entire cell width,
        // while a digit stroke (e.g. digit-1 vertical bar) only covers ~30% of
        // columns. Requiring inkCols >= 70% prevents thin digit strokes from
        // being incorrectly neutralized as grid lines. This fixed digit-1
        // missing errors in tests 22 (FAIL→PASS), 24 (FAIL→PASS), and reduced
        // errors in test 25 from 7 to 2.
        const fullSpan: boolean = inkCols >= cellWInner * 0.7;
        if (variance < GRID_LINE_GRAY_DIFF * 2 && fullSpan) {
          isGridRow[dy] = true;
          gridRowCount++;
        }
      }
    }
    if (gridRowCount > Math.floor(cellHInner * 0.3)) {
      for (let dy: number = 0; dy < cellHInner; dy++) { isGridRow[dy] = false; }
    }
    const isGridCol: boolean[] = new Array<boolean>(cellWInner).fill(false);
    let gridColCount: number = 0;
    for (let dx: number = 0; dx < cellWInner; dx++) {
      const diff: number = effectiveIsDark ? (colAvg[dx] - effectiveBg) : (effectiveBg - colAvg[dx]);
      if (diff > GRID_LINE_GRAY_DIFF) {
        let variance: number = 0;
        let inkRows: number = 0;
        const x: number = x0 + dx;
        for (let dy: number = 0; dy < cellHInner; dy++) {
          const g: number = gray[(y0 + dy) * width + x];
          const d: number = g - colAvg[dx];
          variance += d * d;
          if (effectiveIsDark ? g > (effectiveBg + INK_THRESH) : g < (effectiveBg - INK_THRESH)) { inkRows++; }
        }
        variance = Math.sqrt(variance / cellHInner);
        // fullSpan guard for columns: same as rows — real grid lines span the
        // full cell height, digit strokes do not. Prevents digit-1 vertical bar
        // from being neutralized as a grid column.
        const fullSpan: boolean = inkRows >= cellHInner * 0.7;
        if (variance < GRID_LINE_GRAY_DIFF * 2 && fullSpan) {
          isGridCol[dx] = true;
          gridColCount++;
        }
      }
    }
    if (gridColCount > Math.floor(cellWInner * 0.3)) {
      for (let dx: number = 0; dx < cellWInner; dx++) { isGridCol[dx] = false; }
    }
    for (let dy: number = 0; dy < cellHInner; dy++) {
      if (!isGridRow[dy]) { continue; }
      const y: number = y0 + dy;
      for (let dx: number = 0; dx < cellWInner; dx++) {
        const pos: number = y * width + x0 + dx;
        savedPixels.push(gray[pos]);
        savedPositions.push(pos);
        gray[pos] = effectiveBg;
      }
    }
    for (let dx: number = 0; dx < cellWInner; dx++) {
      if (!isGridCol[dx]) { continue; }
      const x: number = x0 + dx;
      for (let dy: number = 0; dy < cellHInner; dy++) {
        const pos: number = (y0 + dy) * width + x;
        savedPixels.push(gray[pos]);
        savedPositions.push(pos);
        gray[pos] = effectiveBg;
      }
    }
  }

  let ink: number = 0;
  let area: number = 0;
  let bminX: number = 1000000;
  let bmaxX: number = -1;
  let bminY: number = 1000000;
  let bmaxY: number = -1;
  const inkBg: number = effectiveIsDark ? effectiveBg + INK_THRESH : effectiveBg - INK_THRESH;

  for (let y: number = y0; y < y1; y++) {
    for (let x: number = x0; x < x1; x++) {
      area++;
      const g: number = gray[y * width + x];
      if (effectiveIsDark ? g > inkBg : g < inkBg) {
        ink++;
        if (x < bminX) { bminX = x; }
        if (x > bmaxX) { bmaxX = x; }
        if (y < bminY) { bminY = y; }
        if (y > bmaxY) { bmaxY = y; }
      }
    }
  }

  SP.lastRawInkRatio = area > 0 ? ink / area : 0;

  let result: number[] | null = null;
  if (bmaxX >= 0) {
    const bw: number = bmaxX - bminX + 1;
    const bh: number = bmaxY - bminY + 1;

    if (bw >= SAUVOLA_MIN_DIM * 3 && bh >= SAUVOLA_MIN_DIM * 3) {
      const sauvBinary: Float32Array | null = await sauvolaThreshold(gray, width, H, bminX, bminY, bw, bh, effectiveIsDark);
      if (sauvBinary !== null) {
        const scale: number = Math.max(1, Math.ceil(SIG_COLS / bw), Math.ceil(SIG_ROWS / bh));
        const sbw: number = bw * scale;
        const sbh: number = bh * scale;
        const scaledBinary: Float32Array = new Float32Array(sbw * sbh);
        for (let r: number = 0; r < sbh; r++) {
          for (let c: number = 0; c < sbw; c++) {
            scaledBinary[r * sbw + c] = sauvBinary[Math.floor(r / scale) * bw + Math.floor(c / scale)];
          }
        }
        const sauvSig: number[] = new Array<number>(SIG_LEN).fill(0);
        for (let r: number = 0; r < SIG_ROWS; r++) {
          for (let c: number = 0; c < SIG_COLS; c++) {
            const sx0: number = Math.floor(sbw * c / SIG_COLS);
            const sx1: number = Math.floor(sbw * (c + 1) / SIG_COLS);
            const sy0: number = Math.floor(sbh * r / SIG_ROWS);
            const sy1: number = Math.floor(sbh * (r + 1) / SIG_ROWS);
            let s: number = 0;
            let n: number = 0;
            for (let ly: number = sy0; ly < sy1; ly++) {
              for (let lx: number = sx0; lx < sx1; lx++) {
                s += scaledBinary[ly * sbw + lx];
                n++;
              }
            }
            sauvSig[r * SIG_COLS + c] = (n > 0 && s / n > 0.5) ? 1 : 0;
          }
        }
        const sauvInk: number = countInk(sauvSig);
        const sauvPreStrip: number[] = new Array<number>(SIG_LEN).fill(0);
        for (let i: number = 0; i < SIG_LEN; i++) sauvPreStrip[i] = sauvSig[i];
        stripEdgeGridLines(sauvSig);
        stripFullHeightVerticalStrokes(sauvSig);
        const sauvInkStripped: number = countInk(sauvSig);
        if (sauvInkStripped >= THIN1_MIN_INK_COUNT && sauvInkStripped <= MAX_INK_COUNT) {
          result = sauvSig;
        } else if (sauvInk >= THIN1_MIN_INK_COUNT && sauvInk <= MAX_INK_COUNT) {
          stripEdgeGridLines(sauvPreStrip);
          const ink2: number = countInk(sauvPreStrip);
          if (ink2 >= THIN1_MIN_INK_COUNT && ink2 <= MAX_INK_COUNT) {
            result = sauvPreStrip;
          }
        }
      }
    }

    if (result === null) {
      const sig: number[] = new Array<number>(SIG_LEN).fill(0);
      const scale2: number = Math.max(1, Math.ceil(SIG_COLS / bw), Math.ceil(SIG_ROWS / bh));
      const sbw2: number = bw * scale2;
      const sbh2: number = bh * scale2;
      const scaledGray: Float32Array = new Float32Array(sbw2 * sbh2);
      for (let r: number = 0; r < sbh2; r++) {
        for (let c: number = 0; c < sbw2; c++) {
          const sy: number = bminY + Math.floor(r / scale2);
          const sx: number = bminX + Math.floor(c / scale2);
          scaledGray[r * sbw2 + c] = (sy >= 0 && sy < H && sx >= 0 && sx < width) ? gray[sy * width + sx] : effectiveBg;
        }
      }
      for (let r: number = 0; r < SIG_ROWS; r++) {
        for (let c: number = 0; c < SIG_COLS; c++) {
          const sx0: number = Math.floor(sbw2 * c / SIG_COLS);
          const sx1: number = Math.floor(sbw2 * (c + 1) / SIG_COLS);
          const sy0: number = Math.floor(sbh2 * r / SIG_ROWS);
          const sy1: number = Math.floor(sbh2 * (r + 1) / SIG_ROWS);
          let s: number = 0;
          let n: number = 0;
          for (let ly: number = sy0; ly < sy1; ly++) {
            for (let lx: number = sx0; lx < sx1; lx++) {
              s += scaledGray[ly * sbw2 + lx];
              n++;
            }
          }
          const avg: number = n > 0 ? s / n : effectiveBg;
          sig[r * SIG_COLS + c] = (effectiveIsDark ? avg > inkBg : avg < inkBg) ? 1 : 0;
        }
      }
      const inkCount: number = countInk(sig);
      const preStrip: number[] = new Array<number>(SIG_LEN).fill(0);
      for (let i: number = 0; i < SIG_LEN; i++) preStrip[i] = sig[i];
       stripEdgeGridLines(sig);
       stripFullHeightVerticalStrokes(sig);
       const inkCountStripped: number = countInk(sig);
       if (inkCountStripped >= THIN1_MIN_INK_COUNT && inkCountStripped <= MAX_INK_COUNT) {
         result = sig;
       } else if (inkCount >= THIN1_MIN_INK_COUNT && inkCount <= MAX_INK_COUNT) {
         stripEdgeGridLines(preStrip);
         const ink2: number = countInk(preStrip);
         if (ink2 >= THIN1_MIN_INK_COUNT && ink2 <= MAX_INK_COUNT) {
           result = preStrip;
         } else {
           SP.lastPixelDiag = `sigInk=${inkCountStripped} preStrip=${inkCount} edgeOnly=${ink2} gate=${THIN1_MIN_INK_COUNT}`;
         }
       } else {
         SP.lastPixelDiag = `sigInk=${inkCountStripped} preStrip=${inkCount} gate=${THIN1_MIN_INK_COUNT}`;
       }
    }
  } else {
    const ratio: number = SP.lastRawInkRatio;
    SP.lastPixelDiag = `rawInk=${ink}/${area} ratio=${ratio.toFixed(4)} gate=${MIN_CELL_INK_RATIO.toFixed(3)}`;
  }

  for (let i: number = 0; i < savedPositions.length; i++) {
    gray[savedPositions[i]] = savedPixels[i];
  }
  return result;
}

// Lower ink threshold for retry when initial signature has low inkCount.
// Half of INK_THRESH, used to recover faint strokes in small cells.
const LOW_INK_THRESH_RETRY: number = Math.floor(INK_THRESH / 2);
export const ULTRA_LOW_INK_THRESH: number = Math.floor(INK_THRESH / 4);

export async function cellSigFromGrayLowThresh(
  gray: Float32Array,
  width: number,
  cellLeft: number,
  cellTop: number,
  cellW: number,
  cellH: number,
  isDark: boolean,
  bg: number,
  gridRow: number = -1,
  gridCol: number = -1,
  inkThresh: number = LOW_INK_THRESH_RETRY
): Promise<number[] | null> {
  let mxLeft: number = cellW * CELL_MARGIN_RATIO;
  let mxRight: number = cellW * CELL_MARGIN_RATIO;
  let myTop: number = cellH * CELL_MARGIN_RATIO;
  let myBot: number = cellH * CELL_MARGIN_RATIO;
  if (SP.gridLineDetected && gridRow >= 0 && gridRow < 9 && gridCol >= 0 && gridCol < 9) {
    const idx: number = gridRow * 9 + gridCol;
    const maxMarginW: number = Math.floor(cellW * 0.45);
    const maxMarginH: number = Math.floor(cellH * 0.45);
    mxLeft = Math.max(mxLeft, Math.min(SP.gridLineCropLeft[idx], maxMarginW));
    mxRight = Math.max(mxRight, Math.min(SP.gridLineCropRight[idx], maxMarginW));
    myTop = Math.max(myTop, Math.min(SP.gridLineCropTop[idx], maxMarginH));
    myBot = Math.max(myBot, Math.min(SP.gridLineCropBot[idx], maxMarginH));
  }
  const x0: number = Math.floor(cellLeft + mxLeft);
  const y0: number = Math.floor(cellTop + myTop);
  const x1: number = Math.floor(cellLeft + cellW - mxRight);
  const y1: number = Math.floor(cellTop + cellH - myBot);
  const H: number = Math.floor(gray.length / width);
  const cellWInner: number = x1 - x0;
  const cellHInner: number = y1 - y0;

  let effectiveBg: number = bg;
  let effectiveIsDark: boolean = isDark;
  if (cellWInner > 0 && cellHInner > 0) {
    const histProbe: number[] = new Array<number>(256).fill(0);
    for (let y: number = y0; y < y1; y++) {
      for (let x: number = x0; x < x1; x++) {
        const gv: number = Math.floor(gray[y * width + x]);
        if (gv >= 0 && gv < 256) { histProbe[gv]++; }
      }
    }
    let peakVal: number = 0;
    let peakCount: number = 0;
    for (let i: number = 0; i < 256; i++) {
      if (histProbe[i] > peakCount) { peakCount = histProbe[i]; peakVal = i; }
    }
    let aboveCount: number = 0;
    let belowCount: number = 0;
    for (let y: number = y0; y < y1; y++) {
      for (let x: number = x0; x < x1; x++) {
        const gv: number = gray[y * width + x];
        if (gv > peakVal + INK_THRESH * 0.5) { aboveCount++; }
        if (gv < peakVal - INK_THRESH * 0.5) { belowCount++; }
      }
    }
    effectiveIsDark = aboveCount > belowCount;
    if (Math.abs(peakVal - bg) > INK_THRESH * 0.5) {
      effectiveBg = peakVal;
    }
    SP.lastLocalBgInfo = `localBg: peak=${peakVal} bg=${bg.toFixed(1)} above=${aboveCount} below=${belowCount} effBg=${effectiveBg.toFixed(1)} effDark=${effectiveIsDark ? 1 : 0}`;
    SP.lastLocalBgPeak = peakVal;
  } else {
    SP.lastLocalBgInfo = `localBg: skip cellWInner=${cellWInner} cellHInner=${cellHInner}`;
    SP.lastLocalBgPeak = 255;
  }

  const rowAvg: number[] = new Array<number>(cellHInner).fill(0);
  for (let dy: number = 0; dy < cellHInner; dy++) {
    let s: number = 0;
    for (let dx: number = 0; dx < cellWInner; dx++) {
      s += gray[(y0 + dy) * width + x0 + dx];
    }
    rowAvg[dy] = s / cellWInner;
  }
  const isGridRow: boolean[] = new Array<boolean>(cellHInner).fill(false);
  for (let dy: number = 0; dy < cellHInner; dy++) {
    const diff: number = effectiveIsDark ? (rowAvg[dy] - effectiveBg) : (effectiveBg - rowAvg[dy]);
    if (diff > GRID_LINE_GRAY_DIFF) {
      let variance: number = 0;
      let inkCols: number = 0;
      const y: number = y0 + dy;
      for (let dx: number = 0; dx < cellWInner; dx++) {
        const g: number = gray[y * width + x0 + dx];
        const d: number = g - rowAvg[dy];
        variance += d * d;
        if (effectiveIsDark ? g > (effectiveBg + INK_THRESH) : g < (effectiveBg - INK_THRESH)) { inkCols++; }
      }
      variance = Math.sqrt(variance / cellWInner);
      if (variance < GRID_LINE_GRAY_DIFF * 2 && inkCols >= cellWInner * 0.7) {
        isGridRow[dy] = true;
      }
    }
  }
  const colAvg: number[] = new Array<number>(cellWInner).fill(0);
  for (let dx: number = 0; dx < cellWInner; dx++) {
    let s: number = 0;
    for (let dy: number = 0; dy < cellHInner; dy++) {
      s += gray[(y0 + dy) * width + x0 + dx];
    }
    colAvg[dx] = s / cellHInner;
  }
  const isGridCol: boolean[] = new Array<boolean>(cellWInner).fill(false);
  for (let dx: number = 0; dx < cellWInner; dx++) {
    const diff: number = effectiveIsDark ? (colAvg[dx] - effectiveBg) : (effectiveBg - colAvg[dx]);
    if (diff > GRID_LINE_GRAY_DIFF) {
      let variance: number = 0;
      let inkRows: number = 0;
      const x: number = x0 + dx;
      for (let dy: number = 0; dy < cellHInner; dy++) {
        const g: number = gray[(y0 + dy) * width + x];
        const d: number = g - colAvg[dx];
        variance += d * d;
        if (effectiveIsDark ? g > (effectiveBg + INK_THRESH) : g < (effectiveBg - INK_THRESH)) { inkRows++; }
      }
      variance = Math.sqrt(variance / cellHInner);
      if (variance < GRID_LINE_GRAY_DIFF * 2 && inkRows >= cellHInner * 0.7) {
        isGridCol[dx] = true;
      }
    }
  }

  const savedPixels: number[] = [];
  const savedPositions: number[] = [];
  for (let dy: number = 0; dy < cellHInner; dy++) {
    if (!isGridRow[dy]) { continue; }
    const y: number = y0 + dy;
    for (let dx: number = 0; dx < cellWInner; dx++) {
      const pos: number = y * width + x0 + dx;
      savedPixels.push(gray[pos]);
      savedPositions.push(pos);
      gray[pos] = effectiveBg;
    }
  }
  for (let dx: number = 0; dx < cellWInner; dx++) {
    if (!isGridCol[dx]) { continue; }
    const x: number = x0 + dx;
    for (let dy: number = 0; dy < cellHInner; dy++) {
      const pos: number = (y0 + dy) * width + x;
      savedPixels.push(gray[pos]);
      savedPositions.push(pos);
      gray[pos] = effectiveBg;
    }
  }

  let bminX: number = 1000000;
  let bmaxX: number = -1;
  let bminY: number = 1000000;
  let bmaxY: number = -1;
  let inkCount: number = 0;
  const lowInkBg: number = effectiveIsDark ? effectiveBg + inkThresh : effectiveBg - inkThresh;

  for (let y: number = y0; y < y1; y++) {
    for (let x: number = x0; x < x1; x++) {
      const g: number = gray[y * width + x];
      if (effectiveIsDark ? g > lowInkBg : g < lowInkBg) {
        inkCount++;
        if (x < bminX) { bminX = x; }
        if (x > bmaxX) { bmaxX = x; }
        if (y < bminY) { bminY = y; }
        if (y > bmaxY) { bmaxY = y; }
      }
    }
  }

  let result: number[] | null = null;
  if (bmaxX >= 0) {
    const bw: number = bmaxX - bminX + 1;
    const bh: number = bmaxY - bminY + 1;
    const area: number = (x1 - x0) * (y1 - y0);
    SP.lastRawInkRatio = area > 0 ? inkCount / area : 0;

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
        const avg: number = n > 0 ? s / n : effectiveBg;
        sig[r * SIG_COLS + c] = (effectiveIsDark ? avg > lowInkBg : avg < lowInkBg) ? 1 : 0;
      }
    }

    const sigInk: number = countInk(sig);
    const preStrip: number[] = new Array<number>(SIG_LEN).fill(0);
    for (let i: number = 0; i < SIG_LEN; i++) preStrip[i] = sig[i];
    stripEdgeGridLines(sig);
    stripFullHeightVerticalStrokes(sig);
    const sigInkStripped: number = countInk(sig);
    if (sigInkStripped >= THIN1_MIN_INK_COUNT && sigInkStripped <= MAX_INK_COUNT) {
      result = sig;
    } else if (sigInk >= THIN1_MIN_INK_COUNT && sigInk <= MAX_INK_COUNT) {
      stripEdgeGridLines(preStrip);
      const ink2: number = countInk(preStrip);
      if (ink2 >= THIN1_MIN_INK_COUNT && ink2 <= MAX_INK_COUNT) {
        result = preStrip;
      }
    }
  }

  for (let i: number = 0; i < savedPositions.length; i++) {
    gray[savedPositions[i]] = savedPixels[i];
  }
  return result;
}

export async function cellSigFromGrayThin(
  gray: Float32Array,
  width: number,
  cellLeft: number,
  cellTop: number,
  cellW: number,
  cellH: number,
  isDark: boolean,
  bg: number,
  gridRow: number = -1,
  gridCol: number = -1
): Promise<number[] | null> {
  const THIN_MARGIN: number = 0.02;
  let mxLeft: number = cellW * THIN_MARGIN;
  let mxRight: number = cellW * THIN_MARGIN;
  let myTop: number = cellH * THIN_MARGIN;
  let myBot: number = cellH * THIN_MARGIN;
  if (SP.gridLineDetected && gridRow >= 0 && gridRow < 9 && gridCol >= 0 && gridCol < 9) {
    const idx: number = gridRow * 9 + gridCol;
    const maxMarginW: number = Math.floor(cellW * 0.45);
    const maxMarginH: number = Math.floor(cellH * 0.45);
    mxLeft = Math.max(mxLeft, Math.min(SP.gridLineCropLeft[idx], maxMarginW));
    mxRight = Math.max(mxRight, Math.min(SP.gridLineCropRight[idx], maxMarginW));
    myTop = Math.max(myTop, Math.min(SP.gridLineCropTop[idx], maxMarginH));
    myBot = Math.max(myBot, Math.min(SP.gridLineCropBot[idx], maxMarginH));
  }
  const x0: number = Math.floor(cellLeft + mxLeft);
  const y0: number = Math.floor(cellTop + myTop);
  const x1: number = Math.floor(cellLeft + cellW - mxRight);
  const y1: number = Math.floor(cellTop + cellH - myBot);
  const H: number = Math.floor(gray.length / width);
  const cellWInner: number = x1 - x0;
  const cellHInner: number = y1 - y0;

  let effectiveBg: number = bg;
  let effectiveIsDark: boolean = isDark;
  if (cellWInner > 0 && cellHInner > 0) {
    const histProbe: number[] = new Array<number>(256).fill(0);
    for (let y: number = y0; y < y1; y++) {
      for (let x: number = x0; x < x1; x++) {
        const gv: number = Math.floor(gray[y * width + x]);
        if (gv >= 0 && gv < 256) { histProbe[gv]++; }
      }
    }
    let peakVal: number = 0;
    let peakCount: number = 0;
    for (let i: number = 0; i < 256; i++) {
      if (histProbe[i] > peakCount) { peakCount = histProbe[i]; peakVal = i; }
    }
    let aboveCount: number = 0;
    let belowCount: number = 0;
    for (let y: number = y0; y < y1; y++) {
      for (let x: number = x0; x < x1; x++) {
        const gv: number = gray[y * width + x];
        if (gv > peakVal + INK_THRESH * 0.5) { aboveCount++; }
        if (gv < peakVal - INK_THRESH * 0.5) { belowCount++; }
      }
    }
    effectiveIsDark = aboveCount > belowCount;
    if (Math.abs(peakVal - bg) > INK_THRESH * 0.5) {
      effectiveBg = peakVal;
    }
    SP.lastLocalBgInfo = `localBg: peak=${peakVal} bg=${bg.toFixed(1)} above=${aboveCount} below=${belowCount} effBg=${effectiveBg.toFixed(1)} effDark=${effectiveIsDark ? 1 : 0}`;
    SP.lastLocalBgPeak = peakVal;
  } else {
    SP.lastLocalBgInfo = `localBg: skip cellWInner=${cellWInner} cellHInner=${cellHInner}`;
    SP.lastLocalBgPeak = 255;
  }

  const LOW_GRID_DIFF: number = LOW_INK_THRESH_RETRY * 0.4;
  const rowAvg: number[] = new Array<number>(cellHInner).fill(0);
  for (let dy: number = 0; dy < cellHInner; dy++) {
    let s: number = 0;
    for (let dx: number = 0; dx < cellWInner; dx++) {
      s += gray[(y0 + dy) * width + x0 + dx];
    }
    rowAvg[dy] = s / cellWInner;
  }
  const isGridRow: boolean[] = new Array<boolean>(cellHInner).fill(false);
  let gridRowCount: number = 0;
  for (let dy: number = 0; dy < cellHInner; dy++) {
    const diff: number = effectiveIsDark ? (rowAvg[dy] - effectiveBg) : (effectiveBg - rowAvg[dy]);
    if (diff > LOW_GRID_DIFF) {
      let variance: number = 0;
      const y: number = y0 + dy;
      for (let dx: number = 0; dx < cellWInner; dx++) {
        const g: number = gray[y * width + x0 + dx];
        const d: number = g - rowAvg[dy];
        variance += d * d;
      }
      variance = Math.sqrt(variance / cellWInner);
      if (variance < LOW_GRID_DIFF * 3) {
        isGridRow[dy] = true;
        gridRowCount++;
      }
    }
  }
  if (gridRowCount > Math.floor(cellHInner * 0.3)) {
    for (let dy: number = 0; dy < cellHInner; dy++) { isGridRow[dy] = false; }
  }
  const colAvg: number[] = new Array<number>(cellWInner).fill(0);
  for (let dx: number = 0; dx < cellWInner; dx++) {
    let s: number = 0;
    for (let dy: number = 0; dy < cellHInner; dy++) {
      s += gray[(y0 + dy) * width + x0 + dx];
    }
    colAvg[dx] = s / cellHInner;
  }
  const isGridCol: boolean[] = new Array<boolean>(cellWInner).fill(false);
  let gridColCount: number = 0;
  for (let dx: number = 0; dx < cellWInner; dx++) {
    const diff: number = effectiveIsDark ? (colAvg[dx] - effectiveBg) : (effectiveBg - colAvg[dx]);
    if (diff > LOW_GRID_DIFF) {
      let variance: number = 0;
      const x: number = x0 + dx;
      for (let dy: number = 0; dy < cellHInner; dy++) {
        const g: number = gray[(y0 + dy) * width + x];
        const d: number = g - colAvg[dx];
        variance += d * d;
      }
      variance = Math.sqrt(variance / cellHInner);
      if (variance < LOW_GRID_DIFF * 3) {
        isGridCol[dx] = true;
        gridColCount++;
      }
    }
  }
  if (gridColCount > Math.floor(cellWInner * 0.3)) {
    for (let dx: number = 0; dx < cellWInner; dx++) { isGridCol[dx] = false; }
  }

  const savedPixels: number[] = [];
  const savedPositions: number[] = [];
  for (let dy: number = 0; dy < cellHInner; dy++) {
    if (!isGridRow[dy]) { continue; }
    const y: number = y0 + dy;
    for (let dx: number = 0; dx < cellWInner; dx++) {
      const pos: number = y * width + x0 + dx;
      savedPixels.push(gray[pos]);
      savedPositions.push(pos);
      gray[pos] = effectiveBg;
    }
  }
  for (let dx: number = 0; dx < cellWInner; dx++) {
    if (!isGridCol[dx]) { continue; }
    const x: number = x0 + dx;
    for (let dy: number = 0; dy < cellHInner; dy++) {
      const pos: number = (y0 + dy) * width + x;
      savedPixels.push(gray[pos]);
      savedPositions.push(pos);
      gray[pos] = effectiveBg;
    }
  }

  let bminX: number = 1000000;
  let bmaxX: number = -1;
  let bminY: number = 1000000;
  let bmaxY: number = -1;
  let inkCount: number = 0;
  const lowInkBg: number = effectiveIsDark ? effectiveBg + LOW_INK_THRESH_RETRY : effectiveBg - LOW_INK_THRESH_RETRY;
  for (let y: number = y0; y < y1; y++) {
    for (let x: number = x0; x < x1; x++) {
      const g: number = gray[y * width + x];
      if (effectiveIsDark ? g > lowInkBg : g < lowInkBg) {
        inkCount++;
        if (x < bminX) { bminX = x; }
        if (x > bmaxX) { bmaxX = x; }
        if (y < bminY) { bminY = y; }
        if (y > bmaxY) { bmaxY = y; }
      }
    }
  }

  let result: number[] | null = null;
  if (bmaxX >= 0) {
    const bw: number = bmaxX - bminX + 1;
    const bh: number = bmaxY - bminY + 1;
    const thinArea: number = (x1 - x0) * (y1 - y0);
    SP.lastRawInkRatio = thinArea > 0 ? inkCount / thinArea : 0;
    if (bw >= 3 && bh >= 3) {
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
          const avg: number = n > 0 ? s / n : effectiveBg;
          sig[r * SIG_COLS + c] = (effectiveIsDark ? avg > lowInkBg : avg < lowInkBg) ? 1 : 0;
        }
      }
      const sigInk: number = countInk(sig);
      const preStrip: number[] = new Array<number>(SIG_LEN).fill(0);
      for (let i: number = 0; i < SIG_LEN; i++) preStrip[i] = sig[i];
      stripEdgeGridLines(sig);
      stripFullHeightVerticalStrokes(sig);
      const sigInkStripped: number = countInk(sig);
      if (sigInkStripped >= THIN1_MIN_INK_COUNT && sigInkStripped <= MAX_INK_COUNT) {
        result = sig;
      } else if (sigInk >= THIN1_MIN_INK_COUNT && sigInk <= MAX_INK_COUNT) {
        stripEdgeGridLines(preStrip);
        const ink2: number = countInk(preStrip);
        if (ink2 >= THIN1_MIN_INK_COUNT && ink2 <= MAX_INK_COUNT) {
          result = preStrip;
        }
      }
    }
  }

  for (let i: number = 0; i < savedPositions.length; i++) {
    gray[savedPositions[i]] = savedPixels[i];
  }
  return result;
}
