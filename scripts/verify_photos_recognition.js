// verify_photos_recognition.js
// 端到端验证：移植 SudokuPixel.ets 的核心算法
// 处理 photos.jpg -> findBoardBBox -> 81 格 cellSig -> recognizeDigit
//
// 用法: node scripts/verify_photos_recognition.js [图片路径]

const fs = require('fs');
const path = require('path');
const { createCanvas, loadImage } = require('canvas');

const SIG_ROWS = 12;
const SIG_COLS = 8;
const SIG_LEN = SIG_ROWS * SIG_COLS;
const INK_THRESH = 50;

// ---------- 从 SudokuPixel.ets 移植 ----------
function grayInkPixel(g, bg, isDark, thresh) {
  return isDark ? (g > bg + thresh) : (g < bg - thresh);
}

function countInk(sig) {
  let n = 0;
  for (let i = 0; i < sig.length; i++) if (sig[i] === 1) n++;
  return n;
}

function otsuThreshold(hist, total) {
  let sum = 0;
  for (let i = 0; i < 256; i++) sum += i * hist[i];
  let sumB = 0, wB = 0, max = 0, threshold = 127;
  for (let i = 0; i < 256; i++) {
    wB += hist[i];
    if (wB === 0) continue;
    const wF = total - wB;
    if (wF === 0) break;
    sumB += i * hist[i];
    const mB = sumB / wB;
    const mF = (sum - sumB) / wF;
    const between = wB * wF * (mB - mF) * (mB - mF);
    if (between > max) { max = between; threshold = i; }
  }
  return threshold;
}

// ---------- findBoxLongRun（长行程检测，从 SudokuPixel.ets 移植）----------
function findBoxLongRun(gray, W, H, isDark, bg) {
  const abs = isDark ? Math.max(150, bg + 60) : Math.min(80, bg - 60);
  const ink = new Uint8Array(W * H);
  for (let i = 0; i < W * H; i++) {
    ink[i] = isDark ? (gray[i] > abs ? 1 : 0) : (gray[i] < abs ? 1 : 0);
  }
  const keep = new Uint8Array(W * H);
  const MINRUN = Math.max(20, Math.floor(Math.min(W, H) * 0.10));
  // 水平长行程
  for (let y = 0; y < H; y++) {
    let run = 0, start = 0;
    for (let x = 0; x <= W; x++) {
      if (x < W && ink[y * W + x] === 1) {
        if (run === 0) { start = x; }
        run++;
      } else {
        if (run >= MINRUN && start > 0 && x < W) {
          for (let xx = start; xx < x; xx++) { keep[y * W + xx] = 1; }
        }
        run = 0;
      }
    }
  }
  // 垂直长行程
  for (let x = 0; x < W; x++) {
    let run = 0, start = 0;
    for (let y = 0; y <= H; y++) {
      if (y < H && ink[y * W + x] === 1) {
        if (run === 0) { start = y; }
        run++;
      } else {
        if (run >= MINRUN && start > 0 && y < H) {
          for (let yy = start; yy < y; yy++) { keep[yy * W + x] = 1; }
        }
        run = 0;
      }
    }
  }
  let minX = W, maxX = 0, minY = H, maxY = 0, n = 0;
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      if (keep[y * W + x] === 1) {
        n++;
        if (x < minX) { minX = x; }
        if (x > maxX) { maxX = x; }
        if (y < minY) { minY = y; }
        if (y > maxY) { maxY = y; }
      }
    }
  }
  if (n < 50) { return null; }
  const bw = maxX - minX + 1;
  const bh = maxY - minY + 1;
  if (bw < 20 || bh < 20) { return null; }
  const aspect = bw / bh;
  if (aspect < 0.5 || aspect > 2.0) { return null; }
  const areaRatio = (bw * bh) / (W * H);
  if (areaRatio < 0.02 || areaRatio > 0.85) { return null; }
  return { left: minX, top: minY, right: maxX, bottom: maxY, isDark };
}

// ---------- findBBoxInRectGray（区域搜索，从 SudokuPixel.ets 移植）----------
function findBBoxInRectGray(gray, W, H, bg, isDark, x0, y0, x1, y1, thresh, padRatio) {
  const rowInk = new Array(H).fill(0);
  const colInk = new Array(W).fill(0);
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      if (grayInkPixel(gray[y * W + x], bg, isDark, INK_THRESH)) {
        rowInk[y]++;
        colInk[x]++;
      }
    }
  }
  const rowMax = Math.max(...rowInk);
  const colMax = Math.max(...colInk);
  const rowTh = rowMax * thresh;
  const colTh = colMax * thresh;
  let top = y0, bottom = y1 - 1, left = x0, right = x1 - 1;
  while (top < y1 && rowInk[top] < rowTh) top++;
  while (bottom > top && rowInk[bottom] < rowTh) bottom--;
  while (left < x1 && colInk[left] < colTh) left++;
  while (right > left && colInk[right] < colTh) right--;
  if (right <= left || bottom <= top) { return null; }
  const padX = Math.floor((right - left) * padRatio);
  const padY = Math.floor((bottom - top) * padRatio);
  return { left: Math.max(0, left - padX), top: Math.max(0, top - padY),
    right: Math.min(W, right + padX), bottom: Math.min(H, bottom + padY), isDark };
}

function isValidBoardAspect(b, W, H) {
  const bw = b.right - b.left;
  const bh = b.bottom - b.top;
  if (bw < 20 || bh < 20) { return false; }
  const aspect = bw / bh;
  if (aspect < 0.7 || aspect > 1.4) { return false; }
  return true;
}

function findBoardBBox(gray, W, H, bg) {
  const isDark = bg < 128;
  const imgArea = W * H;

  const longRun = findBoxLongRun(gray, W, H, isDark, bg);
  if (longRun !== null) { return longRun; }

  const isDegenerate = (b) => ((b.right - b.left) * (b.bottom - b.top)) > imgArea * 0.88;

  const primary = findBBoxInRectGray(gray, W, H, bg, isDark, 0, 0, W, H, 0.3, 0.3);
  if (primary !== null && isValidBoardAspect(primary, W, H) && !isDegenerate(primary)) { return primary; }

  for (const thresh of [0.20, 0.15]) {
    const res = findBBoxInRectGray(gray, W, H, bg, isDark, 0, 0, W, H, thresh, 0.15);
    if (res !== null && isValidBoardAspect(res, W, H) && !isDegenerate(res)) { return res; }
  }

  const regions = [
    [0, 0, Math.floor(W * 0.6), Math.floor(H * 0.6)],
    [Math.floor(W * 0.4), 0, W, Math.floor(H * 0.6)],
    [0, Math.floor(H * 0.4), Math.floor(W * 0.6), H],
    [Math.floor(W * 0.4), Math.floor(H * 0.4), W, H],
  ];
  let bestArea = 0;
  let bestBox = null;
  for (const r of regions) {
    for (const thresh of [0.30, 0.20, 0.15]) {
      const res = findBBoxInRectGray(gray, W, H, bg, isDark, r[0], r[1], r[2], r[3], thresh, 0.10);
      if (res !== null && isValidBoardAspect(res, W, H)) {
        const area = (res.right - res.left) * (res.bottom - res.top);
        if (area < W * H * 0.88 && area > bestArea) { bestArea = area; bestBox = res; }
        break;
      }
    }
  }
  if (bestBox !== null) { return bestBox; }
  return { left: 0, top: 0, right: W, bottom: H, isDark };
}

// ---------- cellSig ----------
function cellSigFromGray(gray, width, cellLeft, cellTop, cellW, cellH, isDark, bg) {
  const mx = cellW * 0.08;
  const my = cellH * 0.08;
  const x0 = Math.floor(cellLeft + mx);
  const y0 = Math.floor(cellTop + my);
  const x1 = Math.floor(cellLeft + cellW - mx);
  const y1 = Math.floor(cellTop + cellH - my);
  const H = Math.floor(gray.length / width);

  let ink = 0, area = 0;
  let bminX = 1e9, bmaxX = -1, bminY = 1e9, bmaxY = -1;
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      area++;
      const g = gray[y * width + x];
      if (grayInkPixel(g, bg, isDark, INK_THRESH)) {
        ink++;
        if (x < bminX) bminX = x;
        if (x > bmaxX) bmaxX = x;
        if (y < bminY) bminY = y;
        if (y > bmaxY) bmaxY = y;
      }
    }
  }
  if (ink < area * 0.02 || bmaxX < 0) return null;

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
          if (y >= 0 && y < H && x >= 0 && x < width) {
            s += gray[y * width + x];
            n++;
          }
        }
      }
      const avg = n > 0 ? s / n : bg;
      sig[r * SIG_COLS + c] = grayInkPixel(avg, bg, isDark, INK_THRESH) ? 1 : 0;
    }
  }
  const inkCount = countInk(sig);
  if (inkCount < 6 || inkCount > 90) {
    return cellSigOtsuFallbackGray(gray, width, bminX, bminY, bw, bh, isDark, bg);
  }
  return sig;
}

function cellSigOtsuFallbackGray(gray, width, bminX, bminY, bw, bh, isDark, bg) {
  const H = Math.floor(gray.length / width);
  const bboxHist = new Array(256).fill(0);
  let bboxTotal = 0;
  for (let y = bminY; y < bminY + bh; y++) {
    for (let x = bminX; x < bminX + bw; x++) {
      if (y >= 0 && y < H && x >= 0 && x < width) {
        const g = gray[y * width + x];
        const gi = Math.floor(g);
        if (gi >= 0 && gi <= 255) { bboxHist[gi]++; bboxTotal++; }
      }
    }
  }
  if (bboxTotal < 30) return null;
  const otsuT = otsuThreshold(bboxHist, bboxTotal);
  if (Math.abs(otsuT - bg) < 12) return null;

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
          if (y >= 0 && y < H && x >= 0 && x < width) {
            s += gray[y * width + x];
            n++;
          }
        }
      }
      const avg = n > 0 ? s / n : bg;
      sig[r * SIG_COLS + c] = isDark ? (avg > otsuT ? 1 : 0) : (avg < otsuT ? 1 : 0);
    }
  }
  const inkCount = countInk(sig);
  if (inkCount < 6 || inkCount > 90) return null;
  return sig;
}

// ---------- hole/centroid/ratio ----------
function holeCenterRow(sig) {
  const ROWS = SIG_ROWS, COLS = SIG_COLS;
  const outside = new Array(ROWS * COLS).fill(false);
  const stack = [];
  const pushIfBg = (i) => { if (!outside[i] && sig[i] === 0) { outside[i] = true; stack.push(i); } };
  for (let c = 0; c < COLS; c++) { pushIfBg(c); pushIfBg((ROWS - 1) * COLS + c); }
  for (let r = 0; r < ROWS; r++) { pushIfBg(r * COLS); pushIfBg(r * COLS + (COLS - 1)); }
  while (stack.length > 0) {
    const i = stack.pop();
    const r = Math.floor(i / COLS), c = i % COLS;
    if (r > 0) pushIfBg(i - COLS);
    if (r < ROWS - 1) pushIfBg(i + COLS);
    if (c > 0) pushIfBg(i - 1);
    if (c < COLS - 1) pushIfBg(i + 1);
  }
  const visited = new Array(ROWS * COLS).fill(false);
  const components = [];
  for (let i = 0; i < ROWS * COLS; i++) {
    if (sig[i] === 0 && !outside[i] && !visited[i]) {
      const comp = [];
      const cs = [i];
      visited[i] = true;
      while (cs.length > 0) {
        const j = cs.pop();
        comp.push(j);
        const r = Math.floor(j / COLS), c = j % COLS;
        const push2 = (n) => { if (!visited[n] && sig[n] === 0 && !outside[n]) { visited[n] = true; cs.push(n); } };
        if (r > 0) push2(j - COLS);
        if (r < ROWS - 1) push2(j + COLS);
        if (c > 0) push2(j - 1);
        if (c < COLS - 1) push2(j + 1);
      }
      components.push(comp);
    }
  }
  if (components.length === 0) return -1;
  components.sort((a, b) => b.length - a.length);
  if (components.length >= 2 && components[1].length > components[0].length * 0.6) return -1;
  let sumRow = 0;
  for (const j of components[0]) sumRow += Math.floor(j / COLS);
  return sumRow / components[0].length;
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
  let topInk = 0, bottomInk = 0;
  for (let r = 0; r < SIG_ROWS; r++) {
    for (let c = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) {
        if (r < halfRow) topInk++; else bottomInk++;
      }
    }
  }
  if (topInk === 0 && bottomInk === 0) return 0;
  return topInk / (topInk + bottomInk);
}

function sigToAscii(sig) {
  let s = '';
  for (let r = 0; r < SIG_ROWS; r++) {
    let line = '';
    for (let c = 0; c < SIG_COLS; c++) {
      line += sig[r * SIG_COLS + c] ? '#' : '.';
    }
    s += line + '\n';
  }
  return s;
}

// ---------- 模板加载 ----------
function loadTemplates() {
  const file = JSON.parse(fs.readFileSync(
    path.join(__dirname, '..', 'entry/src/main/resources/rawfile/digit_templates.json'), 'utf8'
  ));
  return file.templates.map(e => ({ digit: e.digit, key: e.key }));
}

// ---------- recognizeDigit（与 SudokuPixel.ets 完全一致）----------
function recognizeDigit(sig, inkCount, templates) {
  if (inkCount < 6) return { digit: 0, debug: {} };
  if (templates.length === 0) return { digit: 0, debug: {} };

  const digitBestScore = new Array(10).fill(-100000);
  const digitBestIdx = new Array(10).fill(-1);
  for (let ti = 0; ti < templates.length; ti++) {
    const t = templates[ti];
    let match = 0, tplInk = 0, tp = 0;
    for (let i = 0; i < SIG_LEN; i++) {
      if (t.key[i] === 1) {
        tplInk++;
        if (sig[i] === 1) tp++;
      }
      if (sig[i] === t.key[i]) match++;
    }
    const recall = tplInk > 0 ? tp / tplInk : 0;
    const prec = inkCount > 0 ? tp / inkCount : 0;
    const f1 = (recall + prec) > 0 ? (2 * recall * prec) / (recall + prec) : 0;
    const score = match - (SIG_LEN - match) * 0.5 + f1 * 40;
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

  if (bestDigit === 6 || bestDigit === 9) {
    const qHole = holeCenterRow(sig);
    const iCentroid = inkCentroidRow(sig);
    const ratio = topBottomInkRatio(sig);
    const score6 = digitBestScore[6];
    const score9 = digitBestScore[9];

    let vote6 = 0, vote9 = 0;
    if (qHole >= 0) {
      if (qHole > SIG_ROWS / 2) vote6 += 2; else vote9 += 2;
    }
    if (iCentroid >= 0) {
      if (iCentroid > SIG_ROWS / 2) vote6++; else vote9++;
    }
    if (ratio > 0.5) vote9++; else vote6++;
    if (score6 > score9) vote6++; else vote9++;

    return {
      digit: vote6 >= vote9 ? 6 : 9,
      debug: { qHole, iCentroid, ratio, score6, score9, vote6, vote9,
        scoreAll: [1,2,3,4,5,6,7,8,9].map(d => d + ':' + digitBestScore[d].toFixed(0)).join(' ') }
    };
  }

  return { digit: bestScore >= 12 ? bestDigit : 0, debug: { scoreAll: [1,2,3,4,5,6,7,8,9].map(d => d + ':' + digitBestScore[d].toFixed(0)).join(' ') } };
}

// ---------- 主流程 ----------
async function main() {
  const imgPath = process.argv[2] ||
    path.join(__dirname, '..', 'entry/src/main/resources/rawfile/sudoku_test_images/photos.jpg');
  console.log('加载图片:', imgPath);
  const img = await loadImage(imgPath);
  console.log('图片尺寸:', img.width, 'x', img.height);

  const maxDim = 1280;
  const scale = Math.min(1, maxDim / Math.max(img.width, img.height));
  const W = Math.floor(img.width * scale);
  const H = Math.floor(img.height * scale);
  const canvas = createCanvas(W, H);
  const ctx = canvas.getContext('2d');
  ctx.drawImage(img, 0, 0, W, H);
  const data = ctx.getImageData(0, 0, W, H).data;

  const gray = new Float32Array(W * H);
  for (let i = 0; i < W * H; i++) {
    gray[i] = 0.299 * data[i * 4] + 0.587 * data[i * 4 + 1] + 0.114 * data[i * 4 + 2];
  }

  // 背景：四角 50x50 区域平均
  const cs = 50;
  function cornerAvg(x0, y0) {
    let s = 0, n = 0;
    for (let y = y0; y < y0 + cs && y < H; y++) {
      for (let x = x0; x < x0 + cs && x < W; x++) { s += gray[y * W + x]; n++; }
    }
    return s / n;
  }
  const bg = (cornerAvg(0, 0) + cornerAvg(W - cs, 0) + cornerAvg(0, H - cs) + cornerAvg(W - cs, H - cs)) / 4;
  const isDark = bg < 128;
  console.log('背景灰度:', bg.toFixed(1), 'isDark:', isDark);

  // 用真实的 findBoardBBox 检测棋盘
  const board = findBoardBBox(gray, W, H, bg);
  console.log('棋盘范围:', board, '尺寸:', board.right - board.left, 'x', board.bottom - board.top);

  const bw = board.right - board.left;
  const bh = board.bottom - board.top;
  const cellW = bw / 9;
  const cellH = bh / 9;

  const templates = loadTemplates();
  console.log('加载模板数:', templates.length, '\n');

  // 9x9 识别结果
  console.log('=== 识别结果 ===');
  const grid = [];
  for (let r = 0; r < 9; r++) {
    const row = [];
    let line = '';
    for (let c = 0; c < 9; c++) {
      const cellLeft = board.left + c * cellW;
      const cellTop = board.top + r * cellH;
      const sig = cellSigFromGray(gray, W, cellLeft, cellTop, cellW, cellH, isDark, bg);
      let result;
      if (sig === null) {
        result = { digit: 0, debug: {}, sig: null };
        line += '. ';
      } else {
        const ink = countInk(sig);
        result = recognizeDigit(sig, ink, templates);
        result.sig = sig;
        line += (result.digit === 0 ? '.' : result.digit) + ' ';
      }
      row.push(result);
    }
    grid.push(row);
    console.log(line);
  }

  // 输出 6/9 单元格的详细信息
  console.log('\n=== 6/9 相关单元格详情 ===');
  for (let r = 0; r < 9; r++) {
    for (let c = 0; c < 9; c++) {
      const cell = grid[r][c];
      if (!cell.sig) continue;
      if (cell.digit !== 6 && cell.digit !== 9) continue;
      console.log(`\n--- [${r},${c}] digit=${cell.digit} ink=${countInk(cell.sig)} ---`);
      console.log('  scores:', cell.debug.scoreAll);
      if (cell.debug.qHole !== undefined) {
        console.log(`  qHole=${cell.debug.qHole.toFixed(2)} centroid=${cell.debug.iCentroid.toFixed(2)} ratio=${cell.debug.ratio.toFixed(2)} v6=${cell.debug.vote6} v9=${cell.debug.vote9}`);
      }
      console.log(sigToAscii(cell.sig));
    }
  }

  // 输出所有非空单元格
  console.log('\n=== 所有非空单元格 ===');
  for (let r = 0; r < 9; r++) {
    for (let c = 0; c < 9; c++) {
      const cell = grid[r][c];
      if (!cell.sig) continue;
      console.log(`\n[${r},${c}] digit=${cell.digit} ink=${countInk(cell.sig)}`);
      if (cell.debug.scoreAll) console.log('  scores:', cell.debug.scoreAll);
      console.log(sigToAscii(cell.sig));
    }
  }
}

main().catch(e => { console.error(e); process.exit(1); });
