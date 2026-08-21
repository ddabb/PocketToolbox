const sharp = require('sharp');
const path = require('path');

const SIG_ROWS = 28;
const SIG_COLS = 20;
const SIG_LEN = SIG_ROWS * SIG_COLS;
const INK_THRESH = 50;
const CELL_MARGIN_RATIO = 0.1;
const MIN_CELL_INK_RATIO = 0.025;

function grayInkPixel(g, bg, isDark, thresh) {
  if (isDark) return g > bg + thresh;
  return g < bg - thresh;
}

function countInk(sig) {
  let c = 0;
  for (let i = 0; i < sig.length; i++) if (sig[i] === 1) c++;
  return c;
}

function stripEdgeGridLines(sig) {
  let inkCount = countInk(sig);
  for (let row = 0; row <= 1 && row < SIG_ROWS; row++) {
    let rowInk = 0;
    for (let c = 0; c < SIG_COLS; c++) if (sig[row * SIG_COLS + c] === 1) rowInk++;
    if (rowInk >= SIG_COLS * 0.5) {
      for (let c = 0; c < SIG_COLS; c++) { if (sig[row * SIG_COLS + c] === 1) inkCount--; sig[row * SIG_COLS + c] = 0; }
    }
  }
  for (let row = SIG_ROWS - 1; row >= SIG_ROWS - 2 && row >= 0; row--) {
    let rowInk = 0;
    for (let c = 0; c < SIG_COLS; c++) if (sig[row * SIG_COLS + c] === 1) rowInk++;
    if (rowInk >= SIG_COLS * 0.5) {
      for (let c = 0; c < SIG_COLS; c++) { if (sig[row * SIG_COLS + c] === 1) inkCount--; sig[row * SIG_COLS + c] = 0; }
    }
  }
  for (let col = 0; col <= 1 && col < SIG_COLS; col++) {
    let colInk = 0;
    for (let r = 0; r < SIG_ROWS; r++) if (sig[r * SIG_COLS + col] === 1) colInk++;
    if (colInk >= SIG_ROWS * 0.5) {
      for (let r = 0; r < SIG_ROWS; r++) { if (sig[r * SIG_COLS + col] === 1) inkCount--; sig[r * SIG_COLS + col] = 0; }
    }
  }
  for (let col = SIG_COLS - 1; col >= SIG_COLS - 2 && col >= 0; col--) {
    let colInk = 0;
    for (let r = 0; r < SIG_ROWS; r++) if (sig[r * SIG_COLS + col] === 1) colInk++;
    if (colInk >= SIG_ROWS * 0.5) {
      for (let r = 0; r < SIG_ROWS; r++) { if (sig[r * SIG_COLS + col] === 1) inkCount--; sig[r * SIG_COLS + col] = 0; }
    }
  }
  return inkCount;
}

function sigToVisual(sig) {
  let lines = [];
  for (let r = 0; r < SIG_ROWS; r++) {
    let line = '';
    for (let c = 0; c < SIG_COLS; c++) line += sig[r * SIG_COLS + c] ? '#' : '.';
    lines.push(line);
  }
  return lines.join('\n');
}

async function analyzeCell(imgPath, row, col, targetSize = 800) {
  const imgBuf = await sharp(imgPath).resize(targetSize, targetSize, { fit: 'fill' }).raw().toBuffer();
  const W = targetSize, H = targetSize;
  
  // Compute grayscale
  const gray = new Float32Array(W * H);
  for (let i = 0; i < W * H; i++) {
    gray[i] = (imgBuf[i * 4] * 0.299 + imgBuf[i * 4 + 1] * 0.587 + imgBuf[i * 4 + 2] * 0.114);
  }
  
  // Find bg (most common gray value in histogram top)
  const hist = new Int32Array(256);
  for (let i = 0; i < W * H; i++) hist[Math.round(gray[i])]++;
  let bgMax = 0, bg = 255;
  for (let g = 0; g < 256; g++) { if (hist[g] > bgMax) { bgMax = hist[g]; bg = g; } }
  const isDark = bg < 128;
  
  // Compute board bbox (assume full image with slight padding)
  const pad = Math.round(targetSize * 0.03);
  const boardL = pad, boardT = pad;
  const boardR = targetSize - pad, boardB = targetSize - pad;
  const cellW = (boardR - boardL) / 9;
  const cellH = (boardB - boardT) / 9;
  
  const cellLeft = boardL + col * cellW;
  const cellTop = boardT + row * cellH;
  
  // Extract signature (simplified - no grid line removal)
  const mx = cellW * CELL_MARGIN_RATIO;
  const my = cellH * CELL_MARGIN_RATIO;
  const x0 = Math.floor(cellLeft + mx);
  const y0 = Math.floor(cellTop + my);
  const x1 = Math.floor(cellLeft + cellW - mx);
  const y1 = Math.floor(cellTop + cellH - my);
  
  let ink = 0, area = 0;
  let bminX = 1e6, bmaxX = -1, bminY = 1e6, bmaxY = -1;
  
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      area++;
      const g = gray[y * W + x];
      if (grayInkPixel(g, bg, isDark, INK_THRESH)) {
        ink++;
        if (x < bminX) bminX = x;
        if (x > bmaxX) bmaxX = x;
        if (y < bminY) bminY = y;
        if (y > bmaxY) bmaxY = y;
      }
    }
  }
  
  const rawInkRatio = area > 0 ? ink / area : 0;
  
  if (ink < area * MIN_CELL_INK_RATIO || bmaxX < 0) {
    return { digit: 0, ink, area, rawInkRatio, sig: null, sigVisual: 'EMPTY' };
  }
  
  const bw = bmaxX - bminX + 1;
  const bh = bmaxY - bminY + 1;
  
  const sig = new Array(SIG_LEN).fill(0);
  for (let r = 0; r < SIG_ROWS; r++) {
    for (let c = 0; c < SIG_COLS; c++) {
      const sx0 = bminX + Math.floor(bw * c / SIG_COLS);
      const sx1 = bminX + Math.floor(bw * (c + 1) / SIG_COLS);
      const sy0 = bminY + Math.floor(bh * r / SIG_ROWS);
      const sy1 = bminY + Math.floor(bh * (r + 1) / SIG_ROWS);
      let s = 0, n = 0;
      for (let y = sy0; y < sy1; y++) {
        for (let x = sx0; x < sx1; x++) {
          if (y >= 0 && y < H && x >= 0 && x < W) { s += gray[y * W + x]; n++; }
        }
      }
      const avg = n > 0 ? s / n : bg;
      sig[r * SIG_COLS + c] = grayInkPixel(avg, bg, isDark, INK_THRESH) ? 1 : 0;
    }
  }
  
  const inkBefore = countInk(sig);
  const inkAfter = stripEdgeGridLines(sig);
  
  return {
    digit: -1,
    ink, area, rawInkRatio,
    bminX, bmaxX, bminY, bmaxY, bw, bh,
    inkBefore, inkAfter,
    sig,
    sigVisual: sigToVisual(sig)
  };
}

async function main() {
  const testCases = [
    { file: '14_tiny_200.png', cells: [[1,0,'6'],[2,1,'9'],[2,7,'6'],[3,4,'6'],[5,8,'6'],[6,1,'6'],[7,5,'9'],[8,8,'9']] },
    { file: '07_light_gray_numbers.png', cells: [[1,0,'6'],[2,1,'9'],[2,7,'6'],[3,0,'8'],[4,3,'8'],[5,8,'6'],[6,7,'8'],[7,5,'9'],[8,4,'8']] },
    { file: '10_italic_font.png', cells: [[1,3,'1'],[4,8,'1'],[7,4,'1']] },
    { file: '12_all_thin_lines.png', cells: [[7,5,'9']] },
    { file: '15_huge_1000.png', cells: [[4,8,'1']] },
  ];
  
  for (const tc of testCases) {
    console.log(`\n========== ${tc.file} ==========`);
    for (const [row, col, want] of tc.cells) {
      const result = await analyzeCell(
        path.join('entry/src/main/resources/rawfile/sudoku_test_images', tc.file),
        row, col
      );
      console.log(`\n--- R${row+1}C${col+1} (want=${want}) ink=${result.ink} area=${result.area} ratio=${result.rawInkRatio.toFixed(4)} sigInk=${result.inkAfter} ---`);
      if (result.sig) {
        console.log(result.sigVisual);
      } else {
        console.log('NO SIGNATURE (ink below threshold)');
      }
    }
  }
}

main().catch(console.error);
