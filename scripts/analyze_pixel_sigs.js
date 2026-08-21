/**
 * Sudoku OCR Pixel Signature Analyzer
 * ====================================
 * 复刻 ArkTS SudokuPixel.ets 中的 cellSigFromGray + recognizeDigit 逻辑，
 * 用于在 Node.js 环境下提取测试图片的像素签名并诊断识别失败原因。
 *
 * 用法: node analyze_pixel_sigs.js [--image 07_light_gray_numbers] [--cell R5C9] [--all]
 *
 * 依赖: sharp (npm install sharp)
 *
 * 功能:
 *   1. 加载指定测试图片(或全部失败用例)
 *   2. 按照与 ArkTS 相同的逻辑提取每个格子的 28×20 二值签名
 *   3. 与模板匹配计算分数，输出最佳匹配及其分数
 *   4. 对失败格子输出签名可视化(ASCII art)和详细的分数表
 *   5. 对比 ArkTS 日志中的实际结果，分析偏差原因
 *
 * 关键参数(与 SudokuPixel.ets 保持一致):
 *   SIG_ROWS=28, SIG_COLS=20, INK_THRESH=50, CELL_MARGIN_RATIO=0.08
 *   MIN_CELL_INK_RATIO=0.025, MIN_INK_RATIO=0.25, MAX_INK_RATIO=0.75
 */

const sharp = require('sharp');
const path = require('path');
const fs = require('fs');

// ===== 常量 (与 SudokuPixel.ets 一致) =====
const SIG_ROWS = 28;
const SIG_COLS = 20;
const SIG_LEN = SIG_ROWS * SIG_COLS; // 560
const INK_THRESH = 50;
const GRID_LINE_GRAY_DIFF = INK_THRESH * 0.6; // 30
const CELL_MARGIN_RATIO = 0.08;
const MIN_CELL_INK_RATIO = 0.025;
const MIN_INK_RATIO = 0.25;
const MAX_INK_RATIO = 0.75;
const MIN_INK_COUNT = Math.floor(SIG_LEN * MIN_INK_RATIO); // 140
const MAX_INK_COUNT = Math.floor(SIG_LEN * MAX_INK_RATIO); // 420
const MIN_INK_COUNT_DIGIT1 = Math.floor(SIG_LEN * 0.12); // 67
const THIN1_MIN_INK_COUNT = Math.floor(SIG_LEN * 0.06); // 33
const MIN_DIGIT_SCORE = Math.floor(SIG_LEN * 0.65); // 364
const LOW_INK_FALLBACK_MIN_SCORE = Math.floor(SIG_LEN * 0.60); // 336
const LOW_INK_FALLBACK_MIN_RECALL = 0.35;
const TEMPLATE_MISMATCH_PENALTY = 0.5;
const TEMPLATE_F1_WEIGHT = 200;
const DISAMBIG_SCORE_GAP_SKIP = 150;
const DISAMBIG_HOLE_WEIGHT = 3;
const DISAMBIG_CENTROID_WEIGHT = 2;
const DISAMBIG_TOP_RATIO_WEIGHT = 2;
const DISAMBIG_HOG_WEIGHT = 1;
const DISAMBIG_SW_WEIGHT = 1;
const DISAMBIG_SCORE_WEIGHT = 3;

// 期望数独网格
const EXPECTED = [
  5, 3, 0, 0, 7, 0, 0, 0, 0,
  6, 0, 0, 1, 9, 5, 0, 0, 0,
  0, 9, 8, 0, 0, 0, 0, 6, 0,
  8, 0, 0, 0, 6, 0, 0, 0, 3,
  4, 0, 0, 8, 0, 3, 0, 0, 1,
  7, 0, 0, 0, 2, 0, 0, 0, 6,
  0, 6, 0, 0, 0, 0, 2, 8, 0,
  0, 0, 0, 4, 1, 9, 0, 0, 5,
  0, 0, 0, 0, 8, 0, 0, 7, 9,
];

// 测试图片配置
const TEST_IMAGES = {
  '01_standard_544': { file: '01_standard_544.png', origW: 544 },
  '02_small_300': { file: '02_small_300.png', origW: 300 },
  '03_large_800': { file: '03_large_800.png', origW: 800 },
  '04_blue_numbers': { file: '04_blue_numbers.png', origW: 544 },
  '05_red_theme': { file: '05_red_theme.png', origW: 544 },
  '06_green_theme': { file: '06_green_theme.png', origW: 544 },
  '07_light_gray_numbers': { file: '07_light_gray_numbers.png', origW: 544 },
  '08_gray_bg_dark_numbers': { file: '08_gray_bg_dark_numbers.png', origW: 544 },
  '09_serif_font': { file: '09_serif_font.png', origW: 544 },
  '10_italic_font': { file: '10_italic_font.png', origW: 544 },
  '11_thin_font': { file: '11_thin_font.png', origW: 544 },
  '12_all_thin_lines': { file: '12_all_thin_lines.png', origW: 544 },
  '13_no_outer_border': { file: '13_no_outer_border.png', origW: 544 },
  '14_tiny_200': { file: '14_tiny_200.png', origW: 200 },
  '15_huge_1000': { file: '15_huge_1000.png', origW: 1000 },
};

// ===== 工具函数 =====
function grayInkPixel(g, bg, isDark, thresh) {
  return isDark ? (g > bg + thresh) : (g < bg - thresh);
}

function countInk(sig) {
  let c = 0;
  for (let i = 0; i < sig.length; i++) if (sig[i] === 1) c++;
  return c;
}

function stripEdgeGridLines(sig) {
  const rows = SIG_ROWS, cols = SIG_COLS;
  // Strip top rows
  for (let row = 0; row <= 1 && row < rows; row++) {
    let rowInk = 0;
    for (let c = 0; c < cols; c++) if (sig[row * cols + c] === 1) rowInk++;
    if (rowInk >= cols * 0.5) {
      for (let c = 0; c < cols; c++) sig[row * cols + c] = 0;
    }
  }
  // Strip bottom rows
  for (let row = rows - 1; row >= rows - 2 && row >= 0; row--) {
    let rowInk = 0;
    for (let c = 0; c < cols; c++) if (sig[row * cols + c] === 1) rowInk++;
    if (rowInk >= cols * 0.5) {
      for (let c = 0; c < cols; c++) sig[row * cols + c] = 0;
    }
  }
  // Strip left cols
  for (let col = 0; col <= 1 && col < cols; col++) {
    let colInk = 0;
    for (let r = 0; r < rows; r++) if (sig[r * cols + col] === 1) colInk++;
    if (colInk >= rows * 0.5) {
      for (let r = 0; r < rows; r++) sig[r * cols + col] = 0;
    }
  }
  // Strip right cols
  for (let col = cols - 1; col >= cols - 2 && col >= 0; col--) {
    let colInk = 0;
    for (let r = 0; r < rows; r++) if (sig[r * cols + col] === 1) colInk++;
    if (colInk >= rows * 0.5) {
      for (let r = 0; r < rows; r++) sig[r * cols + col] = 0;
    }
  }
  return countInk(sig);
}

function sigToVisual(sig) {
  const lines = [];
  for (let r = 0; r < SIG_ROWS; r++) {
    let line = '';
    for (let c = 0; c < SIG_COLS; c++) line += sig[r * SIG_COLS + c] ? '#' : '.';
    lines.push(line);
  }
  return lines.join('\n');
}

// ===== holeCenterRow (复刻 ArkTS) =====
function holeCenterRow(sig) {
  const R = SIG_ROWS, C = SIG_COLS;
  const outer = new Array(R * C).fill(false);
  const stack = [];
  const push = (i) => {
    if (!outer[i] && sig[i] === 0) { outer[i] = true; stack.push(i); }
  };
  for (let c = 0; c < C; c++) { push(c); push((R - 1) * C + c); }
  for (let r = 0; r < R; r++) { push(r * C); push(r * C + (C - 1)); }
  while (stack.length) {
    const i = stack.pop(), r = Math.floor(i / C), c = i % C;
    if (r > 0) push(i - C); if (r < R - 1) push(i + C);
    if (c > 0) push(i - 1); if (c < C - 1) push(i + 1);
  }
  const visited = new Array(R * C).fill(false);
  const components = [];
  for (let i = 0; i < R * C; i++) {
    if (sig[i] === 0 && !outer[i] && !visited[i]) {
      const area = [i]; visited[i] = true;
      while (area.length) {
        const j = area.pop(), r = Math.floor(j / C), c = j % C;
        const q = (n) => { if (!visited[n] && sig[n] === 0 && !outer[n]) { visited[n] = true; area.push(n); } };
        if (r > 0) q(j - C); if (r < R - 1) q(j + C);
        if (c > 0) q(j - 1); if (c < C - 1) q(j + 1);
      }
      components.push(area);
    }
  }
  if (!components.length) return -1;
  components.sort((a, b) => b.length - a.length);
  if (components.length >= 2 && components[1].length > components[0].length * 0.4) return -1;
  let s = 0;
  for (const j of components[0]) s += Math.floor(j / C);
  return s / components[0].length;
}

function inkCentroidRow(sig) {
  let sumR = 0, cnt = 0;
  for (let r = 0; r < SIG_ROWS; r++) {
    for (let c = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) { sumR += r; cnt++; }
    }
  }
  return cnt > 0 ? sumR / cnt : -1;
}

function topBottomInkRatio(sig) {
  const halfRow = Math.floor(SIG_ROWS / 2);
  let topInk = 0, botInk = 0;
  for (let r = 0; r < SIG_ROWS; r++) {
    for (let c = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) {
        if (r < halfRow) topInk++; else botInk++;
      }
    }
  }
  const total = topInk + botInk;
  return total > 0 ? topInk / total : 0.5;
}

function hogVerticalGradient(sig) {
  const halfRow = Math.floor(SIG_ROWS / 2);
  let topInk = 0, botInk = 0;
  for (let r = 0; r < halfRow; r++) {
    for (let c = 0; c < SIG_COLS; c++) if (sig[r * SIG_COLS + c] === 1) topInk++;
  }
  for (let r = halfRow; r < SIG_ROWS; r++) {
    for (let c = 0; c < SIG_COLS; c++) if (sig[r * SIG_COLS + c] === 1) botInk++;
  }
  const total = topInk + botInk;
  return total > 0 ? topInk / total : 0.5;
}

function strokeWidthRatio(sig) {
  const midCol = Math.floor(SIG_COLS / 2);
  let topWidth = 0, botWidth = 0;
  const topRow = Math.floor(SIG_ROWS * 0.3);
  const botRow = Math.floor(SIG_ROWS * 0.7);
  for (let c = 0; c < SIG_COLS; c++) {
    if (sig[topRow * SIG_COLS + c] === 1) topWidth++;
    if (sig[botRow * SIG_COLS + c] === 1) botWidth++;
  }
  return topWidth > 0 ? botWidth / topWidth : 1;
}

function maxHorizontalSpan(sig, r0, r1) {
  let maxSpan = 0;
  for (let r = r0; r < r1 && r < SIG_ROWS; r++) {
    let first = -1, last = -1;
    for (let c = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) {
        if (first < 0) first = c;
        last = c;
      }
    }
    if (first >= 0) maxSpan = Math.max(maxSpan, last - first + 1);
  }
  return maxSpan;
}

function isLikelyNot4(sig) {
  const midTop = Math.floor(SIG_ROWS * 0.25);
  const midBot = Math.floor(SIG_ROWS * 0.60);
  const hSpan = maxHorizontalSpan(sig, midTop, midBot);
  if (hSpan < SIG_COLS * 0.30) return true;
  const topRow = Math.floor(SIG_ROWS * 0.15);
  const midRow = Math.floor(SIG_ROWS * 0.45);
  let topLeftInk = 0, topRightInk = 0;
  for (let r = topRow; r < midRow; r++) {
    for (let c = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) {
        if (c < SIG_COLS / 2) topLeftInk++; else topRightInk++;
      }
    }
  }
  if (topLeftInk === 0 && topRightInk > 0) return true;
  return false;
}

// ===== Sauvola 阈值 (简化版) =====
function sauvolaThreshold(gray, W, H, x0, y0, bw, bh, isDark) {
  const winSize = 15;
  const half = Math.floor(winSize / 2);
  const result = new Float32Array(bw * bh);
  for (let ly = 0; ly < bh; ly++) {
    for (let lx = 0; lx < bw; lx++) {
      const iy = y0 + ly, ix = x0 + lx;
      let sum = 0, sum2 = 0, n = 0;
      for (let dy = -half; dy <= half; dy++) {
        for (let dx = -half; dx <= half; dx++) {
          const py = iy + dy, px = ix + dx;
          if (py >= 0 && py < H && px >= 0 && px < W) {
            const g = gray[py * W + px];
            sum += g; sum2 += g * g; n++;
          }
        }
      }
      const mean = n > 0 ? sum / n : 128;
      const variance = n > 0 ? (sum2 / n - mean * mean) : 0;
      const std = Math.sqrt(Math.max(0, variance));
      const t = mean * (1 + 0.2 * (std / 128 - 1));
      result[ly * bw + lx] = isDark ? (gray[iy * W + ix] > t ? 1 : 0) : (gray[iy * W + ix] < t ? 1 : 0);
    }
  }
  return result;
}

// ===== 核心签名提取 (复刻 cellSigFromGray) =====
function cellSigFromGray(gray, W, H, cellLeft, cellTop, cellW, cellH, isDark, bg) {
  const mx = cellW * CELL_MARGIN_RATIO;
  const my = cellH * CELL_MARGIN_RATIO;
  const x0 = Math.floor(cellLeft + mx);
  const y0 = Math.floor(cellTop + my);
  const x1 = Math.floor(cellLeft + cellW - mx);
  const y1 = Math.floor(cellTop + cellH - my);

  const cellWInner = x1 - x0;
  const cellHInner = y1 - y0;

  // Detect grid lines
  const rowAvg = new Float32Array(cellHInner);
  for (let dy = 0; dy < cellHInner; dy++) {
    let sum = 0;
    const y = y0 + dy;
    for (let dx = 0; dx < cellWInner; dx++) sum += gray[y * W + x0 + dx];
    rowAvg[dy] = sum / cellWInner;
  }
  const colAvg = new Float32Array(cellWInner);
  for (let dx = 0; dx < cellWInner; dx++) {
    let sum = 0;
    const x = x0 + dx;
    for (let dy = 0; dy < cellHInner; dy++) sum += gray[(y0 + dy) * W + x];
    colAvg[dx] = sum / cellHInner;
  }

  const isGridRow = new Array(cellHInner).fill(false);
  for (let dy = 0; dy < cellHInner; dy++) {
    const diff = isDark ? (rowAvg[dy] - bg) : (bg - rowAvg[dy]);
    if (diff > GRID_LINE_GRAY_DIFF) {
      let variance = 0;
      const y = y0 + dy;
      for (let dx = 0; dx < cellWInner; dx++) {
        const g = gray[y * W + x0 + dx];
        const d = g - rowAvg[dy];
        variance += d * d;
      }
      variance = Math.sqrt(variance / cellWInner);
      if (variance < GRID_LINE_GRAY_DIFF * 2) isGridRow[dy] = true;
    }
  }
  const isGridCol = new Array(cellWInner).fill(false);
  for (let dx = 0; dx < cellWInner; dx++) {
    const diff = isDark ? (colAvg[dx] - bg) : (bg - colAvg[dx]);
    if (diff > GRID_LINE_GRAY_DIFF) {
      let variance = 0;
      const x = x0 + dx;
      for (let dy = 0; dy < cellHInner; dy++) {
        const g = gray[(y0 + dy) * W + x];
        const d = g - colAvg[dx];
        variance += d * d;
      }
      variance = Math.sqrt(variance / cellHInner);
      if (variance < GRID_LINE_GRAY_DIFF * 2) isGridCol[dx] = true;
    }
  }

  // Neutralize grid lines
  const savedPixels = [];
  const savedPositions = [];
  for (let dy = 0; dy < cellHInner; dy++) {
    if (!isGridRow[dy]) continue;
    const y = y0 + dy;
    for (let dx = 0; dx < cellWInner; dx++) {
      const pos = y * W + x0 + dx;
      savedPixels.push(gray[pos]);
      savedPositions.push(pos);
      gray[pos] = bg;
    }
  }
  for (let dx = 0; dx < cellWInner; dx++) {
    if (!isGridCol[dx]) continue;
    const x = x0 + dx;
    for (let dy = 0; dy < cellHInner; dy++) {
      const pos = (y0 + dy) * W + x;
      savedPixels.push(gray[pos]);
      savedPositions.push(pos);
      gray[pos] = bg;
    }
  }

  // Count ink
  let ink = 0, area = 0;
  let bminX = 1e6, bmaxX = -1, bminY = 1e6, bmaxY = -1;
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      area++;
      if (grayInkPixel(gray[y * W + x], bg, isDark, INK_THRESH)) {
        ink++;
        if (x < bminX) bminX = x; if (x > bmaxX) bmaxX = x;
        if (y < bminY) bminY = y; if (y > bmaxY) bmaxY = y;
      }
    }
  }

  const rawInkRatio = area > 0 ? ink / area : 0;

  let result = null;
  let sigSource = '';

  if (ink >= area * MIN_CELL_INK_RATIO && bmaxX >= 0) {
    const bw = bmaxX - bminX + 1;
    const bh = bmaxY - bminY + 1;

    // Try Sauvola first
    if (bw >= 5 && bh >= 5) {
      const sauvBinary = sauvolaThreshold(gray, W, H, bminX, bminY, bw, bh, isDark);
      const sauvSig = new Array(SIG_LEN).fill(0);
      for (let r = 0; r < SIG_ROWS; r++) {
        for (let c = 0; c < SIG_COLS; c++) {
          const sx0 = Math.floor(bw * c / SIG_COLS);
          const sx1 = Math.floor(bw * (c + 1) / SIG_COLS);
          const sy0 = Math.floor(bh * r / SIG_ROWS);
          const sy1 = Math.floor(bh * (r + 1) / SIG_ROWS);
          let s = 0, n = 0;
          for (let ly = sy0; ly < sy1; ly++) {
            for (let lx = sx0; lx < sx1; lx++) {
              s += sauvBinary[ly * bw + lx]; n++;
            }
          }
          sauvSig[r * SIG_COLS + c] = (n > 0 && s / n > 0.5) ? 1 : 0;
        }
      }
      stripEdgeGridLines(sauvSig);
      const sauvInk = countInk(sauvSig);
      if (sauvInk >= THIN1_MIN_INK_COUNT && sauvInk <= MAX_INK_COUNT) {
        result = sauvSig;
        sigSource = `sauvola(ink=${sauvInk})`;
      }
    }

    // Fallback to fixed threshold
    if (result === null) {
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
      stripEdgeGridLines(sig);
      const inkCount = countInk(sig);
      if (inkCount >= THIN1_MIN_INK_COUNT && inkCount <= MAX_INK_COUNT) {
        result = sig;
        sigSource = `fixed(ink=${inkCount})`;
      }
    }
  }

  // Restore grid line pixels
  for (let i = 0; i < savedPositions.length; i++) {
    gray[savedPositions[i]] = savedPixels[i];
  }

  return { sig: result, rawInkRatio, inkCount: result ? countInk(result) : 0, sigSource };
}

// ===== 模板匹配 (复刻 recognizeDigit 核心逻辑) =====
let g_templates = [];

function initTemplates() {
  // 使用 gen_digit_templates.js 生成的模板
  // 如果没有模板文件，使用内置简化模板
  const tplPath = path.join(__dirname, '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'digit_templates.json');
  if (fs.existsSync(tplPath)) {
    const raw = JSON.parse(fs.readFileSync(tplPath, 'utf8'));
    g_templates = raw.templates || raw;
    console.log(`加载了 ${g_templates.length} 个模板 from ${tplPath}`);
  } else {
    console.log(`警告: ${tplPath} 不存在，使用空模板列表`);
    console.log(`请先运行 node gen_digit_templates.js 生成模板`);
    process.exit(1);
  }
}

function recognizeDigit(sig, inkCount) {
  if (inkCount < THIN1_MIN_INK_COUNT) return { digit: 0, confidence: 0, details: `ink=${inkCount} < gate=${THIN1_MIN_INK_COUNT}` };
  if (g_templates.length === 0) return { digit: 0, confidence: 0, details: 'no templates' };

  const lowInk = inkCount < MIN_INK_COUNT;

  if (lowInk) {
    // Low-ink path: try digit-1 first
    let best1Score = -100000, best1Key = null, best1Tpl = null;
    for (const t of g_templates) {
      if (t.digit !== 1) continue;
      let match = 0;
      for (let i = 0; i < SIG_LEN; i++) if (sig[i] === t.key[i]) match++;
      const score = match - (SIG_LEN - match) * TEMPLATE_MISMATCH_PENALTY;
      if (score > best1Score) { best1Score = score; best1Key = t.key; best1Tpl = t; }
    }
    const lowInkMinScore = Math.floor(SIG_LEN * 0.70);
    const geoMinScore = Math.floor(SIG_LEN * 0.55);
    const veryThinInk = inkCount < MIN_INK_COUNT_DIGIT1;

    if (veryThinInk) {
      if (best1Key !== null) {
        let tplInk = 0, tp = 0;
        for (let i = 0; i < SIG_LEN; i++) {
          if (best1Key[i] === 1) { tplInk++; if (sig[i] === 1) tp++; }
        }
        const recall = tplInk > 0 ? tp / tplInk : 0;
        const veryThin1Gate = Math.floor(SIG_LEN * 0.57);
        if (best1Score >= veryThin1Gate && recall >= 0.25) {
          const conf = best1Score / (SIG_LEN + 200);
          return { digit: 1, confidence: Math.min(1, Math.max(0, conf)), details: `veryThin1: score=${best1Score} recall=${recall.toFixed(2)} ink=${inkCount}` };
        }
      }
      return { digit: 0, confidence: 0, details: `veryThinInk=${inkCount} no1: score=${best1Score} gate=${Math.floor(SIG_LEN * 0.60)}` };
    }

    // Normal low ink: try 1 first, then 2-9 fallback
    if (best1Score >= lowInkMinScore && best1Key !== null) {
      const inkC = inkCentroidRow(sig);
      const tplC = inkCentroidRow(best1Key);
      if (Math.abs(inkC - tplC) <= SIG_ROWS * 0.4) {
        // Check if this might actually be a 7: 7 has wide top horizontal bar
        const topRow = Math.floor(SIG_ROWS * 0.15);
        const midTopRow = Math.floor(SIG_ROWS * 0.35);
        let topSpan = 0;
        for (let r = topRow; r < midTopRow; r++) {
          let first = -1, last = -1;
          for (let c = 0; c < SIG_COLS; c++) {
            if (sig[r * SIG_COLS + c] === 1) { if (first < 0) first = c; last = c; }
          }
          if (first >= 0) topSpan = Math.max(topSpan, last - first + 1);
        }
        const isWideTop = topSpan >= SIG_COLS * 0.5;
        if (isWideTop) {
          // Likely 7 not 1 - check 7 template score
          let best7Score = -100000;
          for (const t of g_templates) {
            if (t.digit !== 7) continue;
            let match = 0;
            for (let i = 0; i < SIG_LEN; i++) if (sig[i] === t.key[i]) match++;
            const score = match - (SIG_LEN - match) * TEMPLATE_MISMATCH_PENALTY;
            if (score > best7Score) best7Score = score;
          }
          if (best7Score >= lowInkMinScore - 50) {
            const rawConf = best7Score / (SIG_LEN + 200);
            return { digit: 7, confidence: Math.min(1, Math.max(0, rawConf)), details: `lowInk7-over-1: topSpan=${topSpan} s7=${best7Score} s1=${best1Score} ink=${inkCount}` };
          }
        }
        const rawConf = best1Score / (SIG_LEN + 200);
        return { digit: 1, confidence: Math.min(1, Math.max(0, rawConf)), details: `lowInk1: score=${best1Score} ink=${inkCount} topSpan=${topSpan}` };
      }
    }

    // Fallback: match digits 2-9
    const digitBestScore = new Array(10).fill(-100000);
    const digitBestRecall = new Array(10).fill(0);
    for (const t of g_templates) {
      if (t.digit === 1) continue;
      let match = 0, tplInk = 0, tp = 0;
      for (let i = 0; i < SIG_LEN; i++) {
        if (t.key[i] === 1) { tplInk++; if (sig[i] === 1) tp++; }
        if (sig[i] === t.key[i]) match++;
      }
      const recall = tplInk > 0 ? tp / tplInk : 0;
      const prec = inkCount > 0 ? tp / inkCount : 0;
      const f1 = (recall + prec) > 0 ? (2 * recall * prec) / (recall + prec) : 0;
      const score = match - (SIG_LEN - match) * TEMPLATE_MISMATCH_PENALTY + f1 * TEMPLATE_F1_WEIGHT;
      if (score > digitBestScore[t.digit]) {
        digitBestScore[t.digit] = score;
        digitBestRecall[t.digit] = recall;
      }
    }
    let lowBestDigit = 0, lowBestScore = -100000, lowBestRecall = 0;
    for (let d = 2; d <= 9; d++) {
      if (digitBestScore[d] > lowBestScore) {
        lowBestDigit = d; lowBestScore = digitBestScore[d]; lowBestRecall = digitBestRecall[d];
      }
    }
    if (lowBestDigit > 0 && lowBestScore >= LOW_INK_FALLBACK_MIN_SCORE && lowBestRecall >= LOW_INK_FALLBACK_MIN_RECALL) {
      const rawConf = lowBestScore / (SIG_LEN + 200);
      return { digit: lowBestDigit, confidence: Math.min(1, Math.max(0, rawConf)), details: `lowInk fallback: best=${lowBestDigit} score=${lowBestScore.toFixed(0)} recall=${lowBestRecall.toFixed(2)} ink=${inkCount}` };
    }
    return { digit: 0, confidence: 0, details: `lowInk noMatch: best=${lowBestDigit} score=${lowBestScore.toFixed(0)} recall=${lowBestRecall.toFixed(2)} ink=${inkCount}` };
  }

  // Normal ink path
  const digitBestScore = new Array(10).fill(-100000);
  const digitBestIdx = new Array(10).fill(-1);
  for (let ti = 0; ti < g_templates.length; ti++) {
    const t = g_templates[ti];
    let match = 0, tplInk = 0, tp = 0;
    for (let i = 0; i < SIG_LEN; i++) {
      if (t.key[i] === 1) { tplInk++; if (sig[i] === 1) tp++; }
      if (sig[i] === t.key[i]) match++;
    }
    const recall = tplInk > 0 ? tp / tplInk : 0;
    const prec = inkCount > 0 ? tp / inkCount : 0;
    const f1 = (recall + prec) > 0 ? (2 * recall * prec) / (recall + prec) : 0;
    const score = match - (SIG_LEN - match) * TEMPLATE_MISMATCH_PENALTY + f1 * TEMPLATE_F1_WEIGHT;
    if (score > digitBestScore[t.digit]) {
      digitBestScore[t.digit] = score;
      digitBestIdx[t.digit] = ti;
    }
  }

  let bestDigit = 0, bestScore = -100000;
  let secondDigit = 0, secondScore = -100000;
  for (let d = 1; d <= 9; d++) {
    if (digitBestScore[d] > bestScore) {
      secondDigit = bestDigit; secondScore = bestScore;
      bestDigit = d; bestScore = digitBestScore[d];
    } else if (digitBestScore[d] > secondScore) {
      secondDigit = d; secondScore = digitBestScore[d];
    }
  }

  const rawConf = bestScore / (SIG_LEN + 200);
  const confidence = Math.min(1, Math.max(0, rawConf));

  // 6/9 disambiguation
  if (bestDigit === 6 || bestDigit === 9) {
    const score6 = digitBestScore[6];
    const score9 = digitBestScore[9];
    const scoreGap = Math.abs(score6 - score9);
    if (scoreGap >= DISAMBIG_SCORE_GAP_SKIP) {
      const d = score6 > score9 ? 6 : 9;
      return { digit: d, confidence, details: `6/9 gap skip: score6=${score6.toFixed(0)} score9=${score9.toFixed(0)} gap=${scoreGap.toFixed(0)} →${d}` };
    }
    const qHole = holeCenterRow(sig);
    const iCentroid = inkCentroidRow(sig);
    const ratio = topBottomInkRatio(sig);
    const hogGrad = hogVerticalGradient(sig);
    const swRatio = strokeWidthRatio(sig);
    let vote6 = 0, vote9 = 0;
    if (qHole >= 0) {
      if (qHole > SIG_ROWS / 2) vote6 += DISAMBIG_HOLE_WEIGHT; else vote9 += DISAMBIG_HOLE_WEIGHT;
    }
    if (iCentroid >= 0) {
      if (iCentroid > SIG_ROWS / 2) vote6 += DISAMBIG_CENTROID_WEIGHT; else vote9 += DISAMBIG_CENTROID_WEIGHT;
    }
    if (ratio > 0.5) vote9 += DISAMBIG_TOP_RATIO_WEIGHT; else vote6 += DISAMBIG_TOP_RATIO_WEIGHT;
    if (hogGrad > 0.5) vote9 += DISAMBIG_HOG_WEIGHT; else vote6 += DISAMBIG_HOG_WEIGHT;
    if (swRatio > 1.1) vote9 += DISAMBIG_SW_WEIGHT; else if (swRatio < 0.9) vote6 += DISAMBIG_SW_WEIGHT;
    if (score6 > score9 + 50) vote6 += DISAMBIG_SCORE_WEIGHT;
    else if (score9 > score6 + 50) vote9 += DISAMBIG_SCORE_WEIGHT;
    else if (score6 > score9) vote6 += 1; else vote9 += 1;
    const d = vote6 === vote9 ? (score6 >= score9 ? 6 : 9) : (vote6 > vote9 ? 6 : 9);
    return {
      digit: d, confidence,
      details: `6/9: s6=${score6.toFixed(0)} s9=${score9.toFixed(0)} gap=${scoreGap.toFixed(0)} qHole=${qHole.toFixed(1)} cent=${iCentroid.toFixed(1)} ratio=${ratio.toFixed(2)} hog=${hogGrad.toFixed(2)} sw=${swRatio.toFixed(2)} v6=${vote6} v9=${vote9} →${d}`
    };
  }

  // 5/9 disambiguation: 9 has a top loop + descending tail; 5 has top horizontal bar + bottom left-curving loop
  if (bestDigit === 5 || bestDigit === 9) {
    const score5 = digitBestScore[5];
    const score9 = digitBestScore[9];
    const scoreGap = Math.abs(score5 - score9);
    if (scoreGap >= 80) {
      const d = score5 > score9 ? 5 : 9;
      return { digit: d, confidence, details: `5/9 gap skip: s5=${score5.toFixed(0)} s9=${score9.toFixed(0)} gap=${scoreGap.toFixed(0)} →${d}` };
    }
    // Geometric: 9 has ink at top-left forming a loop; 5 has top-right horizontal bar
    // Check if top has enclosed area (loop) → 9
    const hole = holeCenterRow(sig);
    if (hole >= 0 && hole < SIG_ROWS * 0.45) {
      // Hole in top half → likely 9
      return { digit: 9, confidence, details: `5/9: s5=${score5.toFixed(0)} s9=${score9.toFixed(0)} hole=${hole.toFixed(1)} →9` };
    }
    // Check bottom-right ink: 9's tail goes right, 5's bottom goes left
    const botRow = Math.floor(SIG_ROWS * 0.7);
    const endRow = Math.floor(SIG_ROWS * 0.9);
    let botLeftInk = 0, botRightInk = 0;
    for (let r = botRow; r < endRow; r++) {
      for (let c = 0; c < SIG_COLS / 2; c++) if (sig[r * SIG_COLS + c] === 1) botLeftInk++;
      for (let c = Math.floor(SIG_COLS / 2); c < SIG_COLS; c++) if (sig[r * SIG_COLS + c] === 1) botRightInk++;
    }
    // 5 has more bottom-left ink (curved loop); 9 has more bottom-right (straight tail)
    if (botLeftInk > botRightInk * 1.5 && score5 >= score9 - 20) {
      return { digit: 5, confidence, details: `5/9: s5=${score5.toFixed(0)} s9=${score9.toFixed(0)} hole=${hole >= 0 ? hole.toFixed(1) : 'none'} bL=${botLeftInk} bR=${botRightInk} →5` };
    }
    // If score gap is small and no clear geometric signal, lean toward 9 if top ink is heavier
    const topInkRatio = topBottomInkRatio(sig);
    if (topInkRatio > 0.55 && score9 >= score5 - 30) {
      return { digit: 9, confidence, details: `5/9: s5=${score5.toFixed(0)} s9=${score9.toFixed(0)} topRatio=${topInkRatio.toFixed(2)} →9` };
    }
    const d = score5 >= score9 ? 5 : 9;
    return { digit: d, confidence, details: `5/9: s5=${score5.toFixed(0)} s9=${score9.toFixed(0)} hole=${hole >= 0 ? hole.toFixed(1) : 'none'} →${d}` };
  }

  // 5/6 disambiguation
  if (bestDigit === 5 || bestDigit === 6) {
    const score5 = digitBestScore[5];
    const score6 = digitBestScore[6];
    const scoreGap = Math.abs(score5 - score6);
    if (scoreGap >= 80) {
      const d = score5 > score6 ? 5 : 6;
      return { digit: d, confidence, details: `5/6 gap skip: s5=${score5.toFixed(0)} s6=${score6.toFixed(0)} gap=${scoreGap.toFixed(0)} →${d}` };
    }
    // 6 has a bottom loop (enclosed hole in bottom half); 5 does not
    const hole = holeCenterRow(sig);
    if (hole >= 0 && hole > SIG_ROWS * 0.45) {
      // Hole in bottom half → likely 6
      const d = 6;
      return { digit: d, confidence, details: `5/6: s5=${score5.toFixed(0)} s6=${score6.toFixed(0)} hole=${hole.toFixed(1)} →${d}` };
    }
    // Check bottom loop enclosure: 6's bottom is wider than top, 5 is opposite
    const topMidRow = Math.floor(SIG_ROWS * 0.25);
    const botMidRow = Math.floor(SIG_ROWS * 0.75);
    let topInkCols = 0, botInkCols = 0;
    for (let c = 0; c < SIG_COLS; c++) {
      let topHas = false, botHas = false;
      for (let r = 0; r < SIG_ROWS / 2; r++) if (sig[r * SIG_COLS + c] === 1) topHas = true;
      for (let r = Math.floor(SIG_ROWS / 2); r < SIG_ROWS; r++) if (sig[r * SIG_COLS + c] === 1) botHas = true;
      if (topHas) topInkCols++;
      if (botHas) botInkCols++;
    }
    // 6 tends to have more ink columns in bottom half (loop), 5 is more top-heavy
    if (botInkCols > topInkCols + 2 && score6 >= score5 - 30) {
      return { digit: 6, confidence, details: `5/6: s5=${score5.toFixed(0)} s6=${score6.toFixed(0)} hole=${hole.toFixed(1)} topCols=${topInkCols} botCols=${botInkCols} →6` };
    }
    const d = score5 >= score6 ? 5 : 6;
    return { digit: d, confidence, details: `5/6: s5=${score5.toFixed(0)} s6=${score6.toFixed(0)} hole=${hole.toFixed(1)} topCols=${topInkCols} botCols=${botInkCols} →${d}` };
  }

  // 3/8 disambiguation: 8 has enclosed holes in both halves; 3 only has right-side curves
  if (bestDigit === 3 || bestDigit === 8) {
    const score3 = digitBestScore[3];
    const score8 = digitBestScore[8];
    const scoreGap = Math.abs(score3 - score8);
    if (scoreGap >= 80) {
      const d = score3 > score8 ? 3 : 8;
      return { digit: d, confidence, details: `3/8 gap skip: s3=${score3.toFixed(0)} s8=${score8.toFixed(0)} gap=${scoreGap.toFixed(0)} →${d}` };
    }
    // Check left-side ink in middle rows: 8 has ink on both sides, 3 only on right
    const midTop = Math.floor(SIG_ROWS * 0.3);
    const midBot = Math.floor(SIG_ROWS * 0.7);
    let leftInk = 0, rightInk = 0;
    for (let r = midTop; r < midBot; r++) {
      for (let c = 0; c < SIG_COLS / 2; c++) if (sig[r * SIG_COLS + c] === 1) leftInk++;
      for (let c = Math.floor(SIG_COLS / 2); c < SIG_COLS; c++) if (sig[r * SIG_COLS + c] === 1) rightInk++;
    }
    const leftRatio = (leftInk + rightInk) > 0 ? leftInk / (leftInk + rightInk) : 0.5;
    // 8 has left ink ratio > 0.35, 3 has < 0.25
    if (leftRatio > 0.30) {
      return { digit: 8, confidence, details: `3/8: s3=${score3.toFixed(0)} s8=${score8.toFixed(0)} leftRatio=${leftRatio.toFixed(2)} →8` };
    }
    const d = score3 >= score8 ? 3 : 8;
    return { digit: d, confidence, details: `3/8: s3=${score3.toFixed(0)} s8=${score8.toFixed(0)} leftRatio=${leftRatio.toFixed(2)} →${d}` };
  }

  // 7/1 disambiguation: ONLY check if 7 might actually be 1 (never flip 1→7)
  // Rationale: flipping 1→7 causes more fp regressions than flipping 7→1
  if (bestDigit === 7) {
    const score7 = digitBestScore[7];
    const score1 = digitBestScore[1];
    const gap71 = score7 - score1;
    if (gap71 < 20) {
      const topRow = Math.floor(SIG_ROWS * 0.10);
      const topEnd = Math.floor(SIG_ROWS * 0.30);
      let topMinC = SIG_COLS, topMaxC = 0;
      for (let r = topRow; r < topEnd; r++) {
        for (let c = 0; c < SIG_COLS; c++) {
          if (sig[r * SIG_COLS + c] === 1) {
            if (c < topMinC) topMinC = c;
            if (c > topMaxC) topMaxC = c;
          }
        }
      }
      const topSpan = topMaxC >= topMinC ? topMaxC - topMinC + 1 : 0;
      if (topSpan >= SIG_COLS * 0.6) {
        let solidTopRows = 0;
        for (let r = topRow; r < topEnd; r++) {
          let inkInRow = 0;
          for (let c = 0; c < SIG_COLS; c++) if (sig[r * SIG_COLS + c] === 1) inkInRow++;
          if (inkInRow >= SIG_COLS * 0.5) solidTopRows++;
        }
        if (solidTopRows >= 2 && score7 >= score1) {
          return { digit: 7, confidence, details: `7/1: s7=${score7.toFixed(0)} s1=${score1.toFixed(0)} topSpan=${topSpan} solidTop=${solidTopRows} →7(confirmed)` };
        }
        if (solidTopRows >= 2 && score1 > score7) {
          return { digit: 1, confidence, details: `7→1: solidTop=${solidTopRows} but s1=${score1.toFixed(0)}>s7=${score7.toFixed(0)} topSpan=${topSpan}` };
        }
      }
      const botRow = Math.floor(SIG_ROWS * 0.60);
      const botEnd = Math.floor(SIG_ROWS * 0.85);
      let botMinC = SIG_COLS, botMaxC = 0;
      for (let r = botRow; r < botEnd; r++) {
        for (let c = 0; c < SIG_COLS; c++) {
          if (sig[r * SIG_COLS + c] === 1) {
            if (c < botMinC) botMinC = c;
            if (c > botMaxC) botMaxC = c;
          }
        }
      }
      const botSpan = botMaxC >= botMinC ? botMaxC - botMinC + 1 : 0;
      if (botSpan <= 6 && topSpan < SIG_COLS * 0.6) {
        return { digit: 1, confidence, details: `7→1: s7=${score7.toFixed(0)} s1=${score1.toFixed(0)} botSpan=${botSpan} topSpan=${topSpan}` };
      }
    }
  }

  if (bestDigit === 4 && isLikelyNot4(sig)) {
    let best1Score3 = -100000;
    for (const t of g_templates) {
      if (t.digit !== 1) continue;
      let match = 0;
      for (let i = 0; i < SIG_LEN; i++) if (sig[i] === t.key[i]) match++;
      const score = match - (SIG_LEN - match) * TEMPLATE_MISMATCH_PENALTY;
      if (score > best1Score3) best1Score3 = score;
    }
    const geoGate2 = Math.floor(SIG_LEN * 0.55);
    if (best1Score3 >= geoGate2) {
      return { digit: 1, confidence: 0.55, details: `not4→1: score1=${best1Score3} ink=${inkCount}` };
    }
  }

  if (bestScore >= MIN_DIGIT_SCORE) {
    return { digit: bestDigit, confidence, details: `best=${bestDigit} score=${bestScore.toFixed(0)} second=${secondDigit}(${secondScore.toFixed(0)}) ink=${inkCount}` };
  }
  return { digit: 0, confidence: 0, details: `below gate: best=${bestDigit} score=${bestScore.toFixed(0)} gate=${MIN_DIGIT_SCORE} ink=${inkCount}` };
}

// ===== 主分析流程 =====
async function analyzeImage(imageName, specificCells) {
  const cfg = TEST_IMAGES[imageName];
  if (!cfg) { console.error(`未知图片: ${imageName}`); return; }

  const imgPath = path.join(__dirname, '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'sudoku_test_images', cfg.file);
  if (!fs.existsSync(imgPath)) { console.error(`文件不存在: ${imgPath}`); return; }

  // Compute resize target (匹配 ArkTS computeAdaptiveResize)
  const origW = cfg.origW;
  const origH = origW; // 正方形
  const targetCellPx = 100;
  const targetW = Math.max(targetCellPx * 9, origW);
  const targetH = targetW;
  const PIXEL_MAX_DIM = 1200;
  let finalW = targetW, finalH = targetH;
  const maxDim = Math.max(finalW, finalH);
  if (maxDim > PIXEL_MAX_DIM) {
    const scaleDown = PIXEL_MAX_DIM / maxDim;
    finalW = Math.round(finalW * scaleDown);
    finalH = Math.round(finalH * scaleDown);
  }

  console.log(`\n${'='.repeat(70)}`);
  console.log(`图片: ${imageName} (原图${origW}×${origH} → 分析${finalW}×${finalH})`);
  console.log(`${'='.repeat(70)}`);

  const { data, info } = await sharp(imgPath)
    .resize(finalW, finalH, { fit: 'fill' })
    .raw()
    .toBuffer({ resolveWithObject: true });

  const W = info.width, H = info.height;
  const gray = new Float32Array(W * H);
  for (let i = 0; i < W * H; i++) {
    gray[i] = data[i * 4] * 0.299 + data[i * 4 + 1] * 0.587 + data[i * 4 + 2] * 0.114;
  }

  // Detect background
  const hist = new Int32Array(256);
  for (let i = 0; i < W * H; i++) hist[Math.round(gray[i])]++;
  let bgMax = 0, bg = 255;
  for (let g = 0; g < 256; g++) { if (hist[g] > bgMax) { bgMax = hist[g]; bg = g; } }
  const isDark = bg < 128;

  console.log(`背景: bg=${bg} isDark=${isDark}`);

  // Board bbox (假设满图)
  const pad = Math.round(W * 0.03);
  const boardL = pad, boardT = pad, boardR = W - pad, boardB = H - pad;
  const cellW = (boardR - boardL) / 9;
  const cellH = (boardB - boardT) / 9;

  // Determine which cells to analyze
  const cells = specificCells || [];
  if (cells.length === 0) {
    // Analyze only cells where EXPECTED != 0
    for (let i = 0; i < 81; i++) {
      if (EXPECTED[i] !== 0) cells.push(i);
    }
  }

  console.log(`\n分析 ${cells.length} 个格子...\n`);

  let correct = 0, wrong = 0, missed = 0;
  const errors = [];

  for (const idx of cells) {
    const row = Math.floor(idx / 9);
    const col = idx % 9;
    const want = EXPECTED[idx];
    const cellLeft = boardL + col * cellW;
    const cellTop = boardT + row * cellH;

    const { sig, rawInkRatio, inkCount, sigSource } = cellSigFromGray(
      gray.slice(), W, H, cellLeft, cellTop, cellW, cellH, isDark, bg
    );

    if (sig === null) {
      missed++;
      errors.push({ row, col, want, got: 0, reason: `sigNull rawInk=${rawInkRatio.toFixed(4)}` });
      console.log(`  R${row + 1}C${col + 1} want=${want} got=0  [sigNull rawInk=${rawInkRatio.toFixed(4)}]`);
      continue;
    }

    const result = recognizeDigit(sig, inkCount);

    if (result.digit === want) {
      correct++;
    } else {
      wrong++;
      errors.push({ row, col, want, got: result.digit, reason: result.details, sig, sigSource, inkCount });
    }

    const marker = result.digit === want ? '✓' : '✗';
    console.log(`  R${row + 1}C${col + 1} want=${want} got=${result.digit} ${marker}  conf=${result.confidence.toFixed(2)} [${result.details}] src=${sigSource}`);
  }

  console.log(`\n--- 汇总 ---`);
  console.log(`正确: ${correct}  错误: ${wrong}  漏识: ${missed}  准确率(given): ${cells.length > 0 ? (correct / cells.length * 100).toFixed(0) : 0}%`);

  if (errors.length > 0) {
    console.log(`\n--- 错误详情 ---`);
    for (const e of errors) {
      console.log(`\nR${e.row + 1}C${e.col + 1}: want=${e.want} got=${e.got}`);
      console.log(`  原因: ${e.reason}`);
      if (e.sig) {
        console.log(`  签名 (${e.sigSource} ink=${e.inkCount}):`);
        console.log(sigToVisual(e.sig));
      }
    }
  }
}

// ===== CLI =====
async function main() {
  const args = process.argv.slice(2);
  initTemplates();

  if (args.includes('--all')) {
    // Analyze all failing test images
    const failingImages = ['07_light_gray_numbers', '10_italic_font', '12_all_thin_lines', '14_tiny_200', '15_huge_1000'];
    for (const name of failingImages) {
      await analyzeImage(name);
    }
  } else if (args.includes('--image')) {
    const idx = args.indexOf('--image');
    const name = args[idx + 1];
    let cells = null;
    if (args.includes('--cell')) {
      const cellIdx = args.indexOf('--cell');
      const cellSpec = args[cellIdx + 1]; // e.g. R5C9
      const match = cellSpec.match(/R(\d+)C(\d+)/i);
      if (match) {
        const r = parseInt(match[1]) - 1;
        const c = parseInt(match[2]) - 1;
        cells = [r * 9 + c];
      }
    }
    await analyzeImage(name, cells);
  } else {
    // Default: analyze failing images
    console.log('用法: node analyze_pixel_sigs.js --image <name> [--cell R5C9] | --all');
    console.log('\n可用图片: ' + Object.keys(TEST_IMAGES).join(', '));
    console.log('\n默认分析所有失败用例...\n');
    const failingImages = ['07_light_gray_numbers', '10_italic_font', '12_all_thin_lines', '14_tiny_200', '15_huge_1000'];
    for (const name of failingImages) {
      await analyzeImage(name);
    }
  }
}

main().catch(console.error);
