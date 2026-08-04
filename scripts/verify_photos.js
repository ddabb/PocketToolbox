// 复刻 ArkTS SudokuPixel（硬编码模板版），用于本地复现/验证 photos.jpg 的 6/9 误识
// 依赖 canvas（已在项目 node_modules 中）
const { createCanvas, loadImage } = require('canvas');
const fs = require('fs');
const path = require('path');

const TEST_DIR = path.join(__dirname, '..', 'sudoku_test_images');
const TARGET = process.argv[2] || 'photos.jpg';

// 与 entry/src/main/ets/core/sudoku/SudokuPixel.ets 的 tpl1-9 完全一致
const TEMPLATES = [
  { digit: 1, key: [0,0,0,0,0,1,1,0,0,0,1,1,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1] },
  { digit: 2, key: [0,0,0,1,1,0,0,0,1,1,1,1,1,1,0,1,1,1,1,1,1,0,0,0,0,0,1,1,0,0,0,0,1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1] },
  { digit: 3, key: [0,1,1,1,1,1,0,0,1,1,1,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,0,1,1,1,1,1,0,0,0,1,1,1,1,1,0,0,0,0,0,1,1,0,0,0,0,0,1,1,1,1,1,1,1,1,1,0,1,1,1,1,0,0] },
  { digit: 4, key: [0,0,0,0,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,0,0,0,1,1,1,1,0,0,1,1,0,1,1,0,0,1,1,0,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,0,0,0,0,0,1,1,0] },
  { digit: 5, key: [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,1,1,1,0,1,1,1,1,1,1,1,0,0,0,0,0,1,1,1,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0] },
  { digit: 6, key: [0,0,0,1,1,1,0,0,0,1,1,1,1,1,0,1,1,1,0,0,0,0,1,1,0,1,0,0,1,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,0,0,1,1,0,1,1,0,0,1,1,0,1,1,1,1,1,1,0,0,1,1,1,0,0] },
  { digit: 7, key: [1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,0,0,0,0,0,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,0,0,0,0,0,1,1,0,0,0] },
  { digit: 8, key: [0,0,0,1,1,0,0,0,1,1,1,1,1,0,0,1,1,0,1,1,1,0,1,1,0,0,1,1,0,1,1,1,1,1,0,0,1,1,1,1,1,0,1,1,1,0,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,0] },
  { digit: 9, key: [0,0,1,1,1,0,0,0,1,1,1,1,1,0,1,1,1,0,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,0,0,0,0,0,1,1,0,0,0,0,1,1,1,0,1,1,1,1,1,0,0,1,1,1,1,0,0] },
];

const ROWS = 10, COLS = 7, INK_THRESH = 50;

function grayAt(px, i) { return 0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2]; }

async function loadPixels(imgPath) {
  const img = await loadImage(imgPath);
  const W = img.width, H = img.height;
  const cnv = createCanvas(W, H);
  const ctx = cnv.getContext('2d');
  ctx.drawImage(img, 0, 0);
  return { px: ctx.getImageData(0, 0, W, H).data, W, H };
}

function bgColor(px, W, H) {
  const margin = Math.max(2, Math.floor(Math.min(W, H) * 0.05));
  let sum = 0, cnt = 0;
  for (let y = 0; y < margin; y += 2) for (let x = 0; x < margin; x += 2) { sum += grayAt(px, (y * W + x) * 4); cnt++; }
  for (let y = 0; y < margin; y += 2) for (let x = W - margin; x < W; x += 2) { sum += grayAt(px, (y * W + x) * 4); cnt++; }
  return cnt > 0 ? sum / cnt : 200;
}

function findBoardBBox(px, W, H, bg, forceLight = null) {
  const isDark = forceLight !== null ? (!forceLight) : (bg < 128);
  const isInk = (g) => isDark ? (g > bg + INK_THRESH) : (g < bg - INK_THRESH);
  const colInk = new Array(W).fill(0), rowInk = new Array(H).fill(0);
  for (let x = 0; x < W; x++) { let c = 0; for (let y = 0; y < H; y += 2) if (isInk(grayAt(px, (y * W + x) * 4))) c++; colInk[x] = c; }
  for (let y = 0; y < H; y++) { let c = 0; for (let x = 0; x < W; x += 2) if (isInk(grayAt(px, (y * W + x) * 4))) c++; rowInk[y] = c; }
  const colFrac = colInk.map(c => c / (H / 2)), rowFrac = rowInk.map(c => c / (W / 2));
  let minX = W, maxX = 0, minY = H, maxY = 0, found = false;
  for (let x = 0; x < W; x++) if (colFrac[x] > 0.3) { if (x < minX) minX = x; if (x > maxX) maxX = x; found = true; }
  for (let y = 0; y < H; y++) if (rowFrac[y] > 0.3) { if (y < minY) minY = y; if (y > maxY) maxY = y; found = true; }
  if (!found || maxX - minX < W * 0.3 || maxY - minY < H * 0.3) return { left: 0, top: 0, right: W, bottom: H, isDark };
  return { left: minX, top: minY, right: maxX, bottom: maxY, isDark };
}

function cellSig(px, W, left, top, cw, ch, isDark, bg, forceLight = null) {
  const mx = cw * 0.08, my = ch * 0.08;
  const x0 = Math.floor(left + mx), y0 = Math.floor(top + my);
  const x1 = Math.floor(left + cw - mx), y1 = Math.floor(top + ch - my);
  const effectiveDark = forceLight !== null ? (!forceLight) : isDark;
  const isInk = (g) => effectiveDark ? (g > bg + INK_THRESH) : (g < bg - INK_THRESH);
  let ink = 0, area = 0;
  let bminX = 1e9, bmaxX = -1, bminY = 1e9, bmaxY = -1;
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) {
    area++; const g = grayAt(px, (y * W + x) * 4);
    if (isInk(g)) { ink++; if (x < bminX) bminX = x; if (x > bmaxX) bmaxX = x; if (y < bminY) bminY = y; if (y > bmaxY) bmaxY = y; }
  }
  if (ink < area * 0.02 || bmaxX < 0) return null;
  const bw = bmaxX - bminX + 1, bh = bmaxY - bminY + 1;
  const sig = new Array(ROWS * COLS).fill(0);
  for (let r = 0; r < ROWS; r++) for (let c = 0; c < COLS; c++) {
    const sx0 = bminX + Math.floor(bw * c / COLS), sx1 = bminX + Math.floor(bw * (c + 1) / COLS);
    const sy0 = bminY + Math.floor(bh * r / ROWS), sy1 = bminY + Math.floor(bh * (r + 1) / ROWS);
    let s = 0, n = 0;
    for (let y = sy0; y < sy1; y++) for (let x = sx0; x < sx1; x++) { s += grayAt(px, (y * W + x) * 4); n++; }
    sig[r * COLS + c] = isInk(n > 0 ? s / n : bg) ? 1 : 0;
  }
  const inkCount = sig.reduce((a, v) => a + v, 0);
  if (inkCount < 6 || inkCount > ROWS * COLS - 4) return null;
  return sig;
}

// 增强版 recognize：与 ArkTS recognizeDigit 逻辑一致，并加入 6/9 垂直重心辅助判别
function recognize(sig, useCentroid = true) {
  const inkCount = sig.reduce((a, v) => a + v, 0);
  // 诊断特征：上下半区墨迹 + 垂直重心
  let top = 0, bottom = 0, weighted = 0;
  for (let r = 0; r < ROWS; r++) for (let c = 0; c < COLS; c++) {
    const v = sig[r * COLS + c];
    if (r < ROWS / 2) top += v; else bottom += v;
    weighted += r * v;
  }
  const cy = inkCount > 0 ? weighted / inkCount : 0;
  let best = 0, bestScore = -1e9; const scores = [];
  for (const t of TEMPLATES) {
    let match = 0, tplInk = 0, tp = 0;
    for (let i = 0; i < ROWS * COLS; i++) {
      if (t.key[i] === 1) { tplInk++; if (sig[i] === 1) tp++; }
      if (sig[i] === t.key[i]) match++;
    }
    const recall = tplInk > 0 ? tp / tplInk : 0, prec = inkCount > 0 ? tp / inkCount : 0;
    const f1 = (recall + prec > 0) ? 2 * recall * prec / (recall + prec) : 0;
    const score = match - (ROWS * COLS - match) * 0.5 + f1 * 40;
    scores.push({ d: t.digit, score: Math.round(score) });
    if (score > bestScore) { bestScore = score; best = t.digit; }
  }
  scores.sort((a, b) => b.score - a.score);

  // 6/9 视觉辅助：模板评分接近时，用垂直重心裁决
  if (useCentroid && (best === 6 || best === 9)) {
    const s6 = scores.find(s => s.d === 6).score;
    const s9 = scores.find(s => s.d === 9).score;
    const gap = Math.abs(s6 - s9);
    if (gap <= 15) {
      // 模板重心：6≈4.6（偏下），9≈4.2（偏上）
      if (cy > 4.8 && best !== 6) best = 6;
      else if (cy < 4.2 && best !== 9) best = 9;
    }
  }

  return { digit: bestScore >= 12 ? best : 0, scores, top, bottom, cy };
}

function boxNum(r, c) { return Math.floor(r / 3) * 3 + Math.floor(c / 3) + 1; }

// 标准数独谜面（与 ocr_test.js 一致，也是 photos.jpg 的真实内容）
const EXPECTED = [
  5,3,0,0,7,0,0,0,0,
  6,0,0,1,9,5,0,0,0,
  0,9,8,0,0,0,0,6,0,
  8,0,0,0,6,0,0,0,3,
  4,0,0,8,0,3,0,0,1,
  7,0,0,0,2,0,0,0,6,
  0,6,0,0,0,0,2,8,0,
  0,0,0,4,1,9,0,0,5,
  0,0,0,0,8,0,0,7,9
];

function findConflicts(grid) {
  const conflicts = [];
  const groups = [];
  for (let r = 0; r < 9; r++) { const g = []; for (let c = 0; c < 9; c++) if (grid[r * 9 + c] !== 0) g.push({ p: [r, c], v: grid[r * 9 + c] }); groups.push(['row' + r, g]); }
  for (let c = 0; c < 9; c++) { const g = []; for (let r = 0; r < 9; r++) if (grid[r * 9 + c] !== 0) g.push({ p: [r, c], v: grid[r * 9 + c] }); groups.push(['col' + c, g]); }
  for (let b = 0; b < 9; b++) { const g = []; for (let r = 0; r < 9; r++) for (let c = 0; c < 9; c++) if (boxNum(r, c) - 1 === b && grid[r * 9 + c] !== 0) g.push({ p: [r, c], v: grid[r * 9 + c] }); groups.push(['box' + (b + 1), g]); }
  for (const [name, g] of groups) {
    const seen = {};
    for (const e of g) { if (seen[e.v]) conflicts.push({ group: name, val: e.v, at: e.p, dup: seen[e.v] }); else seen[e.v] = e.p; }
  }
  return conflicts;
}

function countConflicts(grid) {
  let conflicts = 0;
  for (let r = 0; r < 9; r++) { const seen = new Array(10).fill(0); for (let c = 0; c < 9; c++) { const d = grid[r * 9 + c]; if (d > 0) { if (seen[d] > 0) conflicts++; seen[d]++; } } }
  for (let c = 0; c < 9; c++) { const seen = new Array(10).fill(0); for (let r = 0; r < 9; r++) { const d = grid[r * 9 + c]; if (d > 0) { if (seen[d] > 0) conflicts++; seen[d]++; } } }
  for (let br = 0; br < 3; br++) for (let bc = 0; bc < 3; bc++) { const seen = new Array(10).fill(0); for (let r = br * 3; r < br * 3 + 3; r++) for (let c = bc * 3; c < bc * 3 + 3; c++) { const d = grid[r * 9 + c]; if (d > 0) { if (seen[d] > 0) conflicts++; seen[d]++; } } }
  return conflicts;
}

function correctGridByConstraints(grid) {
  const result = [...grid];
  let current = countConflicts(result);
  let improved = true;
  while (improved && current > 0) {
    improved = false;
    let bestIdx = -1, bestVal = 0, bestImprovement = 0;
    for (let i = 0; i < 81; i++) {
      const v = result[i];
      if (v !== 6 && v !== 9) continue;
      const other = 15 - v;
      result[i] = other;
      const after = countConflicts(result);
      result[i] = v;
      const improvement = current - after;
      if (improvement > bestImprovement) { bestImprovement = improvement; bestIdx = i; bestVal = other; }
    }
    if (bestImprovement > 0) { result[bestIdx] = bestVal; current -= bestImprovement; improved = true; }
  }
  return result;
}

function run(px, W, H, forceLight = null) {
  const bg = bgColor(px, W, H);
  const bbox = findBoardBBox(px, W, H, bg, forceLight);
  const cw = (bbox.right - bbox.left) / 9, ch = (bbox.bottom - bbox.top) / 9;
  const grid = new Array(81).fill(0);
  const cells = [];
  for (let r = 0; r < 9; r++) for (let c = 0; c < 9; c++) {
    const sig = cellSig(px, W, bbox.left + c * cw, bbox.top + r * ch, cw, ch, bbox.isDark, bg, forceLight);
    if (sig) { const rec = recognize(sig); grid[r * 9 + c] = rec.digit; cells.push({ r, c, box: boxNum(r, c), ...rec }); }
  }
  return { grid, cells, bbox, bg };
}

function printResult(res, label) {
  console.log('=== ' + label + ' ===  bbox=' + JSON.stringify(res.bbox) + ' bg=' + res.bg.toFixed(0));
  for (let r = 0; r < 9; r++) console.log(res.grid.slice(r * 9, r * 9 + 9).map(v => v === 0 ? '.' : v).join(' '));
  console.log('--- 6/9 格子诊断 ---');
  for (const x of res.cells.filter(c => c.digit === 6 || c.digit === 9)) {
    const s6 = x.scores.find(s => s.d === 6).score, s9 = x.scores.find(s => s.d === 9).score;
    console.log(`r${x.r}c${x.c} box${x.box} => ${x.digit} | s6=${s6} s9=${s9} | top=${x.top} bottom=${x.bottom} cy=${x.cy.toFixed(2)}`);
  }
  const conf = findConflicts(res.grid);
  console.log('--- 冲突（合法数独谜面不应有）---');
  if (conf.length === 0) console.log('(无冲突)');
  for (const cf of conf) console.log(`group=${cf.group} val=${cf.val} at r${cf.at[0]}c${cf.at[1]} dup r${cf.dup[0]}c${cf.dup[1]}`);
}

function runCorrectionUnitTest() {
  console.log('=== 6/9 约束消歧单元测试 ===');
  let grid = [...EXPECTED];
  // 模拟系统 OCR 把 box3(r2c7=6) 和 box7(r6c1=6) 都错成 9
  grid[2 * 9 + 7] = 9;
  grid[6 * 9 + 1] = 9;
  console.log('构造错误 grid 冲突数:', countConflicts(grid));
  const corrected = correctGridByConstraints(grid);
  console.log('修正后冲突数:', countConflicts(corrected));
  let ok = true;
  for (let i = 0; i < 81; i++) if (corrected[i] !== EXPECTED[i]) { ok = false; console.log('差异 at', i, 'expected', EXPECTED[i], 'got', corrected[i]); }
  console.log('修正结果:', ok ? '通过（与标准谜面一致）' : '失败');
  return ok;
}

(async () => {
  runCorrectionUnitTest();
  console.log('');

  const imgPath = path.isAbsolute(TARGET) ? TARGET : path.join(TEST_DIR, TARGET);
  if (!fs.existsSync(imgPath)) { console.log('NOT FOUND', imgPath); return; }
  const { px, W, H } = await loadPixels(imgPath);
  let res = run(px, W, H);
  const degenerated = (res.bbox.right - res.bbox.left) >= W * 0.9 && (res.bbox.bottom - res.bbox.top) >= H * 0.9;
  if (degenerated || process.env.FORCE_LIGHT === '1') {
    if (process.env.FORCE_LIGHT !== '1') console.log('默认模式 bbox 退化，自动重试 light 模式');
    res = run(px, W, H, true);
  }
  printResult(res, TARGET);
})();
