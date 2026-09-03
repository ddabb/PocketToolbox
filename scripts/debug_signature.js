const fs = require('fs');
const path = require('path');
const { createCanvas, loadImage } = require('canvas');

const INK_THRESH = 50;
const LOW_INK_THRESH_RETRY = Math.floor(INK_THRESH / 2);
const CELL_MARGIN_RATIO = 0.08;
const SIG_ROWS = 7;
const SIG_COLS = 5;
const SIG_LEN = SIG_ROWS * SIG_COLS;
const GRID_LINE_GRAY_DIFF = INK_THRESH * 0.6;
const MIN_CELL_INK_RATIO = 0.03;

function grayInkPixel(g, bg, isDark, thresh) {
  return isDark ? g > (bg + thresh) : g < (bg - thresh);
}

function stripEdgeGridLines(sig) {
  for (let r = 0; r < SIG_ROWS; r++) {
    let ink = 0; for (let c = 0; c < SIG_COLS; c++) if (sig[r * SIG_COLS + c]) ink++;
    if (ink >= SIG_COLS * 0.7) for (let c = 0; c < SIG_COLS; c++) sig[r * SIG_COLS + c] = 0;
  }
  for (let c = 0; c < SIG_COLS; c++) {
    let ink = 0; for (let r = 0; r < SIG_ROWS; r++) if (sig[r * SIG_COLS + c]) ink++;
    if (ink >= SIG_ROWS * 0.7) for (let r = 0; r < SIG_ROWS; r++) sig[r * SIG_COLS + c] = 0;
  }
}

function stripFullHeightVerticalStrokes(sig) {
  for (let c = 0; c < SIG_COLS; c++) {
    let ink = 0; for (let r = 0; r < SIG_ROWS; r++) if (sig[r * SIG_COLS + c]) ink++;
    if (ink >= SIG_ROWS * 0.85) for (let r = 0; r < SIG_ROWS; r++) sig[r * SIG_COLS + c] = 0;
  }
}

function cellSigFromGrayLowThresh(gray, width, cellLeft, cellTop, cellW, cellH, isDark, bg) {
  const H = Math.floor(gray.length / width);
  let mxLeft = cellW * CELL_MARGIN_RATIO, mxRight = cellW * CELL_MARGIN_RATIO;
  let myTop = cellH * CELL_MARGIN_RATIO, myBot = cellH * CELL_MARGIN_RATIO;
  const x0 = Math.floor(cellLeft + mxLeft), y0 = Math.floor(cellTop + myTop);
  const x1 = Math.floor(cellLeft + cellW - mxRight), y1 = Math.floor(cellTop + cellH - myBot);
  const cellWInner = x1 - x0, cellHInner = y1 - y0;

  let effectiveBg = bg, effectiveIsDark = isDark;
  if (cellWInner > 0 && cellHInner > 0) {
    const histProbe = new Array(256).fill(0);
    for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) { const gv = Math.floor(gray[y * width + x]); if (gv >= 0 && gv < 256) histProbe[gv]++; }
    let peakVal = 0, peakCount = 0;
    for (let i = 0; i < 256; i++) if (histProbe[i] > peakCount) { peakCount = histProbe[i]; peakVal = i; }
    let aboveCount = 0, belowCount = 0;
    for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) { const gv = gray[y * width + x]; if (gv > peakVal + INK_THRESH * 0.5) aboveCount++; if (gv < peakVal - INK_THRESH * 0.5) belowCount++; }
    effectiveIsDark = aboveCount > belowCount;
    if (Math.abs(peakVal - bg) > INK_THRESH * 0.5) effectiveBg = peakVal;
  }

  const LOW_GRID_DIFF = LOW_INK_THRESH_RETRY * 0.6;
  const rowAvg = new Array(cellHInner).fill(0);
  for (let dy = 0; dy < cellHInner; dy++) { let s = 0; for (let dx = 0; dx < cellWInner; dx++) s += gray[(y0 + dy) * width + x0 + dx]; rowAvg[dy] = s / cellWInner; }
  const isGridRow = new Array(cellHInner).fill(false);
  for (let dy = 0; dy < cellHInner; dy++) {
    const diff = effectiveIsDark ? (rowAvg[dy] - effectiveBg) : (effectiveBg - rowAvg[dy]);
    if (diff > LOW_GRID_DIFF) {
      let v = 0, inkCols = 0; const y = y0 + dy;
      for (let dx = 0; dx < cellWInner; dx++) { const g = gray[y * width + x0 + dx]; v += (g - rowAvg[dy]) ** 2; if (effectiveIsDark ? g > (effectiveBg + INK_THRESH) : g < (effectiveBg - INK_THRESH)) inkCols++; }
      v = Math.sqrt(v / cellWInner);
      if (v < LOW_GRID_DIFF * 2 && inkCols >= cellWInner * 0.7) isGridRow[dy] = true;
    }
  }
  const colAvg = new Array(cellWInner).fill(0);
  for (let dx = 0; dx < cellWInner; dx++) { let s = 0; for (let dy = 0; dy < cellHInner; dy++) s += gray[(y0 + dy) * width + x0 + dx]; colAvg[dx] = s / cellHInner; }
  const isGridCol = new Array(cellWInner).fill(false);
  for (let dx = 0; dx < cellWInner; dx++) {
    const diff = effectiveIsDark ? (colAvg[dx] - effectiveBg) : (effectiveBg - colAvg[dx]);
    if (diff > LOW_GRID_DIFF) {
      let v = 0, inkRows = 0; const x = x0 + dx;
      for (let dy = 0; dy < cellHInner; dy++) { const g = gray[(y0 + dy) * width + x]; v += (g - colAvg[dx]) ** 2; if (effectiveIsDark ? g > (effectiveBg + INK_THRESH) : g < (effectiveBg - INK_THRESH)) inkRows++; }
      v = Math.sqrt(v / cellHInner);
      if (v < LOW_GRID_DIFF * 2 && inkRows >= cellHInner * 0.7) isGridCol[dx] = true;
    }
  }
  const savedPixels = [], savedPositions = [];
  for (let dy = 0; dy < cellHInner; dy++) { if (!isGridRow[dy]) continue; const y = y0 + dy; for (let dx = 0; dx < cellWInner; dx++) { const pos = y * width + x0 + dx; savedPixels.push(gray[pos]); savedPositions.push(pos); gray[pos] = effectiveBg; } }
  for (let dx = 0; dx < cellWInner; dx++) { if (!isGridCol[dx]) continue; const x = x0 + dx; for (let dy = 0; dy < cellHInner; dy++) { const pos = (y0 + dy) * width + x; savedPixels.push(gray[pos]); savedPositions.push(pos); gray[pos] = effectiveBg; } }

  let bminX = 1e6, bmaxX = -1, bminY = 1e6, bmaxY = -1, inkCount = 0;
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) { const g = gray[y * width + x]; if (grayInkPixel(g, effectiveBg, effectiveIsDark, LOW_INK_THRESH_RETRY)) { inkCount++; if (x < bminX) bminX = x; if (x > bmaxX) bmaxX = x; if (y < bminY) bminY = y; if (y > bmaxY) bmaxY = y; } }

  let result = null;
  if (bmaxX >= 0) {
    const bw = bmaxX - bminX + 1, bh = bmaxY - bminY + 1;
    const scale = Math.max(1, Math.ceil(SIG_COLS / bw), Math.ceil(SIG_ROWS / bh));
    const sbw = bw * scale, sbh = bh * scale;
    const scaledGray = new Float32Array(sbw * sbh);
    for (let r = 0; r < sbh; r++) for (let c = 0; c < sbw; c++) {
      const sy = bminY + Math.floor(r / scale), sx = bminX + Math.floor(c / scale);
      scaledGray[r * sbw + c] = (sy >= 0 && sy < H && sx >= 0 && sx < width) ? gray[sy * width + sx] : effectiveBg;
    }
    const sig = new Array(SIG_LEN).fill(0);
    for (let r = 0; r < SIG_ROWS; r++) for (let c = 0; c < SIG_COLS; c++) {
      const sx0 = Math.floor(sbw * c / SIG_COLS), sx1 = Math.floor(sbw * (c + 1) / SIG_COLS);
      const sy0 = Math.floor(sbh * r / SIG_ROWS), sy1 = Math.floor(sbh * (r + 1) / SIG_ROWS);
      let s = 0, n = 0;
      for (let ly = sy0; ly < sy1; ly++) for (let lx = sx0; lx < sx1; lx++) { s += scaledGray[ly * sbw + lx]; n++; }
      const avg = n > 0 ? s / n : effectiveBg;
      sig[r * SIG_COLS + c] = grayInkPixel(avg, effectiveBg, effectiveIsDark, LOW_INK_THRESH_RETRY) ? 1 : 0;
    }
    stripEdgeGridLines(sig); stripFullHeightVerticalStrokes(sig);
    result = sig;
  }

  for (let i = 0; i < savedPositions.length; i++) gray[savedPositions[i]] = savedPixels[i];
  return result;
}

async function main() {
  const img = await loadImage('F:/PocketToolbox/sudoku_test_images/07_light_gray_numbers.png');
  const bg = 255;
  const isDark = false;

  // Test on 544x544 original
  {
    const canvas = createCanvas(img.width, img.height);
    const ctx = canvas.getContext('2d');
    ctx.drawImage(img, 0, 0);
    const imgData = ctx.getImageData(0, 0, img.width, img.height);
    const W = img.width, H = img.height;
    const gray = new Float32Array(W * H);
    for (let i = 0; i < W * H; i++) gray[i] = 0.299 * imgData.data[i * 4] + 0.587 * imgData.data[i * 4 + 1] + 0.114 * imgData.data[i * 4 + 2];

    const cellL = 187, cellT = 74, cellW = 56, cellH = 57;
    const sig = cellSigFromGrayLowThresh(gray, W, cellL, cellT, cellW, cellH, isDark, bg);
    console.log('544x544 R1C3 lowThresh sig:');
    if (sig) {
      for (let r = 0; r < SIG_ROWS; r++) {
        let row = '';
        for (let c = 0; c < SIG_COLS; c++) row += sig[r * SIG_COLS + c] + ' ';
        console.log('  ' + row);
      }
      const ink = sig.reduce((a, b) => a + b, 0);
      console.log('  ink count:', ink);
    } else {
      console.log('  null');
    }
  }

  // Test on 800x800 scaled
  {
    const canvas = createCanvas(800, 800);
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, 800, 800);
    ctx.drawImage(img, 0, 0, 800, 800);
    const imgData = ctx.getImageData(0, 0, 800, 800);
    const W = 800, H = 800;
    const gray = new Float32Array(W * H);
    for (let i = 0; i < W * H; i++) gray[i] = 0.299 * imgData.data[i * 4] + 0.587 * imgData.data[i * 4 + 1] + 0.114 * imgData.data[i * 4 + 2];

    const cellL = 275, cellT = 109, cellW = 83, cellH = 83;
    const sig = cellSigFromGrayLowThresh(gray, W, cellL, cellT, cellW, cellH, isDark, bg);
    console.log('800x800 R1C3 lowThresh sig:');
    if (sig) {
      for (let r = 0; r < SIG_ROWS; r++) {
        let row = '';
        for (let c = 0; c < SIG_COLS; c++) row += sig[r * SIG_COLS + c] + ' ';
        console.log('  ' + row);
      }
      const ink = sig.reduce((a, b) => a + b, 0);
      console.log('  ink count:', ink);
    } else {
      console.log('  null');
    }
  }
}
main().catch(e => console.error(e));
