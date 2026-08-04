// 特征码方案验证：直方图众数背景 + 封闭空洞拓扑裁决（6/9 区分）
// 不依赖约束冲突、不硬编码规则。仅用于本地复现/验证，不进 App 包。
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

// ---- 直方图众数背景（与 ArkTS bgColor 一致）----
function bgColor(px, W, H) {
  const hist = new Array(256).fill(0);
  const total = W * H;
  const step = Math.max(1, Math.floor(total / 20000));
  for (let i = 0; i < total; i += step) {
    let g = grayAt(px, i * 4); let gi = g < 0 ? 0 : (g > 255 ? 255 : Math.floor(g));
    hist[gi]++;
  }
  let mode = 0, max = -1;
  for (let i = 0; i < 256; i++) if (hist[i] > max) { max = hist[i]; mode = i; }
  return mode;
}

// ---- 封闭空洞纵向中心（与 ArkTS holeCenterRow 一致）----
function holeCenterRow(sig) {
  const outside = new Array(ROWS * COLS).fill(false);
  const stack = [];
  const pushIfBg = (i) => { if (!outside[i] && sig[i] === 0) { outside[i] = true; stack.push(i); } };
  for (let c = 0; c < COLS; c++) { pushIfBg(c); pushIfBg((ROWS - 1) * COLS + c); }
  for (let r = 0; r < ROWS; r++) { pushIfBg(r * COLS); pushIfBg(r * COLS + (COLS - 1)); }
  while (stack.length) {
    const i = stack.pop(); const r = Math.floor(i / COLS), c = i % COLS;
    if (r > 0) pushIfBg(i - COLS);
    if (r < ROWS - 1) pushIfBg(i + COLS);
    if (c > 0) pushIfBg(i - 1);
    if (c < COLS - 1) pushIfBg(i + 1);
  }
  const visited = new Array(ROWS * COLS).fill(false);
  const comps = [];
  for (let i = 0; i < ROWS * COLS; i++) {
    if (sig[i] === 0 && !outside[i] && !visited[i]) {
      const comp = []; const cs = [i]; visited[i] = true;
      while (cs.length) {
        const j = cs.pop(); comp.push(j);
        const r = Math.floor(j / COLS), c = j % COLS;
        const p2 = (n) => { if (!visited[n] && sig[n] === 0 && !outside[n]) { visited[n] = true; cs.push(n); } };
        if (r > 0) p2(j - COLS);
        if (r < ROWS - 1) p2(j + COLS);
        if (c > 0) p2(j - 1);
        if (c < COLS - 1) p2(j + 1);
      }
      comps.push(comp);
    }
  }
  if (comps.length === 0) return -1;
  comps.sort((a, b) => b.length - a.length);
  if (comps.length >= 2 && comps[1].length > comps[0].length * 0.4) return -1;
  let s = 0; for (const j of comps[0]) s += Math.floor(j / COLS);
  return s / comps[0].length;
}
const TPL_HOLE = TEMPLATES.map(t => holeCenterRow(t.key));
const HOLE_W = 18, HOLE_P = 18;

function scoresOf(sig) {
  const inkCount = sig.reduce((a, v) => a + v, 0);
  const out = [];
  for (let ti = 0; ti < TEMPLATES.length; ti++) {
    const t = TEMPLATES[ti];
    let match = 0, tplInk = 0, tp = 0;
    for (let i = 0; i < 70; i++) {
      if (t.key[i] === 1) { tplInk++; if (sig[i] === 1) tp++; }
      if (sig[i] === t.key[i]) match++;
    }
    const recall = tplInk > 0 ? tp / tplInk : 0, prec = inkCount > 0 ? tp / inkCount : 0;
    const f1 = (recall + prec > 0) ? 2 * recall * prec / (recall + prec) : 0;
    out.push({ d: t.digit, score: match - (70 - match) * 0.5 + f1 * 40 });
  }
  return out;
}

// 旧识别（纯轮廓，无空洞特征）
function recognizeOld(sig) {
  const s = scoresOf(sig);
  let best = 0, bs = -1e9;
  for (const x of s) { if (x.score > bs) { bs = x.score; best = x.d; } }
  return bs >= 12 ? best : 0;
}

// 新识别（轮廓 + 空洞拓扑裁决）
function recognizeNew(sig) {
  const s = scoresOf(sig);
  const qHole = holeCenterRow(sig);
  let best = 0, bs = -1e9;
  for (let ti = 0; ti < s.length; ti++) {
    let score = s[ti].score;
    const tHole = TPL_HOLE[ti];
    if (qHole >= 0 && tHole >= 0) {
      const sameHalf = (qHole < 4.5) === (tHole < 4.5);
      score += sameHalf ? HOLE_W : -HOLE_P;
    }
    if (score > bs) { bs = score; best = s[ti].d; }
  }
  return bs >= 12 ? best : 0;
}

// ---- 图像管线（与 ArkTS 一致，仅用于实测）----
async function loadPixels(imgPath) {
  const img = await loadImage(imgPath);
  const W = img.width, H = img.height;
  const cnv = createCanvas(W, H);
  const ctx = cnv.getContext('2d');
  ctx.drawImage(img, 0, 0);
  return { px: ctx.getImageData(0, 0, W, H).data, W, H };
}
function findBoardBBox(px, W, H, bg) {
  const isDark = bg < 128;
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
function cellSig(px, W, left, top, cw, ch, isDark, bg) {
  const mx = cw * 0.08, my = ch * 0.08;
  const x0 = Math.floor(left + mx), y0 = Math.floor(top + my);
  const x1 = Math.floor(left + cw - mx), y1 = Math.floor(top + ch - my);
  const isInk = (g) => isDark ? (g > bg + INK_THRESH) : (g < bg - INK_THRESH);
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

// ---- 合成抖动/噪声压力测试：模拟边界框抖动 + 拍照噪声 ----
function perturb(sig, rowShift, noiseP, rng) {
  const out = new Array(ROWS * COLS).fill(0);
  for (let r = 0; r < ROWS; r++) for (let c = 0; c < COLS; c++) {
    if (sig[r * COLS + c] === 1) {
      let r2 = r + rowShift;
      if (r2 < 0) r2 = 0; if (r2 > ROWS - 1) r2 = ROWS - 1;
      out[r2 * COLS + c] = 1;
    }
  }
  for (let i = 0; i < ROWS * COLS; i++) {
    if (rng() < noiseP) out[i] = out[i] ? 0 : 1;
  }
  return out;
}
function mulberry32(a) { return function () { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }

function jitterStressTest() {
  console.log('=== 合成抖动/噪声压力测试（6/9 互换率）===');
  console.log('（模拟真实拍照：边界框上下抖动 ±1 行 + 极小椒盐噪声，保留"圈"结构）');
  const rng = mulberry32(20260804);
  const shifts = [-1, 0, 1];
  const noises = [0.0, 0.01, 0.02];
  for (const truth of [6, 9]) {
    let oldWrong = 0, newWrong = 0, total = 0;
    for (const sh of shifts) for (const np of noises) {
      for (let t = 0; t < 500; t++) {
        const sig = perturb(TEMPLATES[truth - 1].key, sh, np, rng);
        if (sig.reduce((a, v) => a + v, 0) < 6) continue;
        total++;
        if (recognizeOld(sig) !== truth) oldWrong++;
        if (recognizeNew(sig) !== truth) newWrong++;
      }
    }
    console.log(`真值=${truth}: 样本=${total} | 旧算法误识=${oldWrong} (${(oldWrong / total * 100).toFixed(1)}%) | 新算法误识=${newWrong} (${(newWrong / total * 100).toFixed(1)}%)`);
  }
}

// ---- 标准谜面（photos.jpg 真实内容，用于旧/新算法对照）----
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

function runImage(px, W, H) {
  const bg = bgColor(px, W, H);
  const bbox = findBoardBBox(px, W, H, bg);
  const cw = (bbox.right - bbox.left) / 9, ch = (bbox.bottom - bbox.top) / 9;
  const newGrid = new Array(81).fill(0), oldGrid = new Array(81).fill(0);
  const sixNine = [];
  for (let r = 0; r < 9; r++) for (let c = 0; c < 9; c++) {
    const sig = cellSig(px, W, bbox.left + c * cw, bbox.top + r * ch, cw, ch, bbox.isDark, bg);
    if (sig) {
      const nd = recognizeNew(sig), od = recognizeOld(sig);
      newGrid[r * 9 + c] = nd; oldGrid[r * 9 + c] = od;
      if (nd === 6 || nd === 9) {
        const s = scoresOf(sig);
        const qHole = holeCenterRow(sig);
        sixNine.push({ r, c, box: Math.floor(r / 3) * 3 + Math.floor(c / 3) + 1, nd, od, qHole: qHole.toFixed(2) });
      }
    }
  }
  return { newGrid, oldGrid, bbox, bg, sixNine };
}

function printGrid(g) {
  for (let r = 0; r < 9; r++) console.log(g.slice(r * 9, r * 9 + 9).map(v => v === 0 ? '.' : v).join(' '));
}

(async () => {
  console.log('模板空洞纵向位置 TPL_HOLE =', TPL_HOLE.map((v, i) => TEMPLATES[i].digit + ':' + (v < 0 ? '无/多' : v.toFixed(1))).join('  '));
  console.log('');
  jitterStressTest();
  console.log('');

  const imgPath = path.isAbsolute(TARGET) ? TARGET : path.join(TEST_DIR, TARGET);
  if (!fs.existsSync(imgPath)) { console.log('NOT FOUND', imgPath); return; }
  const { px, W, H } = await loadPixels(imgPath);
  const res = runImage(px, W, H);
  console.log(`=== 实测 ${TARGET} ===  bbox=${JSON.stringify(res.bbox)} bg=${res.bg.toFixed(0)} isDark=${res.bbox.isDark}`);
  console.log('--- 新算法(含空洞特征) ---');
  printGrid(res.newGrid);
  console.log('--- 旧算法(纯轮廓, 对照) ---');
  printGrid(res.oldGrid);
  console.log('--- 6/9 格子对照（nd=新 od=旧）---');
  if (res.sixNine.length === 0) console.log('(无可识别的 6/9)');
  for (const x of res.sixNine) console.log(`r${x.r}c${x.c} box${x.box} => 新=${x.nd} 旧=${x.od} | 空洞行=${x.qHole}`);
  console.log('--- 与标准谜面对比 ---');
  let newErr = 0, oldErr = 0;
  for (let i = 0; i < 81; i++) {
    if (EXPECTED[i] === 0) continue;
    if (res.newGrid[i] !== EXPECTED[i]) newErr++;
    if (res.oldGrid[i] !== EXPECTED[i]) oldErr++;
  }
  console.log(`新算法与标准谜面差异格数: ${newErr} / 旧算法: ${oldErr}`);
})();
