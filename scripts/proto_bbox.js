// Offline prototype: replicate CURRENT ArkTS findBoardBBox longRun path exactly.
// Usage:
//   node proto_bbox.js baseline            -> bbox for all 29 images (current algorithm)
//   node proto_bbox.js dump photos.jpg     -> hRun/vRun detail dump for one image
//   node proto_bbox.js fix <idea>          -> candidate fix applied to all images
'use strict';
const fs = require('fs');
const path = require('path');
const { createCanvas, loadImage } = require('canvas');

// ===== constants from SudokuOCRUtils.ets / SudokuPixel.ets (current) =====
const TARGET_CELL_PX = 100;
const RESIZE_LARGE_THRESHOLD = 2000;
const RESIZE_LARGE_TARGET = 1600;
const RESIZE_MEDIUM_THRESHOLD = 1280;
const RESIZE_SMALL_THRESHOLD = 800;
const RESIZE_SMALL_TARGET = 800;
const PIXEL_MAX_DIM = 1200;
const BG_DARK_THRESHOLD = 128;
const BG_SAMPLE_COUNT = 20000;
const MAX_BOARD_AREA_RATIO = 0.88;
const MIN_BOARD_AREA_RATIO = 0.02;
const CONSERVATIVE_MIN_DIM = 20;
const MINRUN_ABS_MIN = 20;
const MINRUN_FRAC = 0.10;
const LONGRUN_TIGHTER_OFFSETS = [40, 25, 12];
const LONGRUN_MIN_PIXELS = 50;
const LONGRUN_MAX_RUN_COUNT_FRAC = 0.50;
const LONGRUN_MIN_ASPECT = 0.6;
const LONGRUN_MAX_ASPECT = 2.0;
const ADAPTIVE_MAX_DIM = 400;

// ===== probe size: computeAdaptiveResize + PIXEL_MAX_DIM cap (tryPixelGridRecognition) =====
function computeProbeSize(origW, origH) {
  let targetW = origW, targetH = origH;
  const maxDim = Math.max(origW, origH);
  const MAX_UPSCALE = 2.0;
  if (maxDim > RESIZE_LARGE_THRESHOLD) {
    const scale = RESIZE_LARGE_TARGET / maxDim;
    targetW = Math.round(origW * scale); targetH = Math.round(origH * scale);
  } else if (maxDim >= RESIZE_SMALL_THRESHOLD) {
    if (maxDim > RESIZE_MEDIUM_THRESHOLD) {
      const scale = RESIZE_MEDIUM_THRESHOLD / maxDim;
      targetW = Math.round(origW * scale); targetH = Math.round(origH * scale);
    }
  } else {
    const scale = Math.min(MAX_UPSCALE, RESIZE_SMALL_TARGET / maxDim);
    targetW = Math.round(origW * scale); targetH = Math.round(origH * scale);
  }
  const md = Math.max(targetW, targetH);
  if (md > PIXEL_MAX_DIM) {
    const s = PIXEL_MAX_DIM / md;
    targetW = Math.round(targetW * s); targetH = Math.round(targetH * s);
  }
  return { targetW, targetH };
}

// ===== image -> RGBA pixels at probe size =====
async function loadProbePixels(filePath) {
  const img = await loadImage(filePath);
  const { targetW, targetH } = computeProbeSize(img.width, img.height);
  const canvas = createCanvas(targetW, targetH);
  const ctx = canvas.getContext('2d');
  ctx.imageSmoothingEnabled = true;
  ctx.drawImage(img, 0, 0, targetW, targetH);
  const data = ctx.getImageData(0, 0, targetW, targetH).data;
  return { pixels: data, W: targetW, H: targetH, origW: img.width, origH: img.height };
}

// ===== bgColor (current ArkTS: skip bin 0) =====
function bgColor(pixels, width, height) {
  const histR = new Array(256).fill(0), histG = new Array(256).fill(0), histB = new Array(256).fill(0);
  const total = width * height;
  const step = Math.max(1, Math.floor(total / BG_SAMPLE_COUNT));
  for (let i = 0; i < total; i += step) {
    const off = i * 4;
    histR[pixels[off]]++; histG[pixels[off + 1]]++; histB[pixels[off + 2]]++;
  }
  let modeR = 0, maxR = 0, modeG = 0, maxG = 0, modeB = 0, maxB = 0;
  for (let i = 1; i < 256; i++) { // skip bin 0
    if (histR[i] > maxR) { maxR = histR[i]; modeR = i; }
    if (histG[i] > maxG) { maxG = histG[i]; modeG = i; }
    if (histB[i] > maxB) { maxB = histB[i]; modeB = i; }
  }
  return { bg: 255, bgR: modeR, bgG: modeG, bgB: modeB };
}

function toGrayArray(pixels, width, height, chBg) {
  const gray = new Float32Array(width * height);
  for (let i = 0; i < width * height; i++) {
    const off = i * 4;
    const dr = Math.abs(pixels[off] - chBg.bgR);
    const dg = Math.abs(pixels[off + 1] - chBg.bgG);
    const db = Math.abs(pixels[off + 2] - chBg.bgB);
    let contrast = dr;
    if (dg > contrast) contrast = dg;
    if (db > contrast) contrast = db;
    let v = 255 - contrast;
    if (v < 0) v = 0; else if (v > 255) v = 255;
    gray[i] = v;
  }
  return gray;
}

// ===== exact replica of findBoxLongRunWithThresh (current ArkTS, incl. diag) =====
// collectRuns=true -> also return run lists in work space
function findBoxLongRunWithThresh(gray, W, H, isDark, absThresh, collectRuns, useLattice) {
  let workGray = gray, workW = W, workH = H, scale = 1;
  const maxDim = Math.max(W, H);
  if (maxDim > ADAPTIVE_MAX_DIM) {
    scale = ADAPTIVE_MAX_DIM / maxDim;
    workW = Math.max(1, Math.round(W * scale));
    workH = Math.max(1, Math.round(H * scale));
    workGray = new Float32Array(workW * workH);
    for (let y = 0; y < workH; y++) {
      const srcY = Math.min(Math.floor(y / scale), H - 1);
      for (let x = 0; x < workW; x++) {
        const srcX = Math.min(Math.floor(x / scale), W - 1);
        workGray[y * workW + x] = gray[srcY * W + srcX];
      }
    }
  }
  const invScale = 1 / scale;
  const ink = new Uint8Array(workW * workH);
  for (let i = 0; i < workW * workH; i++) {
    ink[i] = isDark ? (workGray[i] > absThresh ? 1 : 0) : (workGray[i] < absThresh ? 1 : 0);
  }
  const keep = new Uint8Array(workW * workH);
  const MINRUN = Math.max(MINRUN_ABS_MIN, Math.floor(Math.min(workW, workH) * MINRUN_FRAC));
  const hRuns = []; // {y, x0, x1} inclusive-exclusive as kept
  let hRunCount = 0, hKeepCount = 0;
  for (let y = 0; y < workH; y++) {
    let run = 0, start = 0;
    for (let x = 0; x <= workW; x++) {
      if (x < workW && ink[y * workW + x] === 1) {
        if (run === 0) start = x;
        run++;
      } else {
        if (run >= MINRUN && start > 0 && x < workW) {
          for (let xx = start; xx < x; xx++) keep[y * workW + xx] = 1;
          hRunCount++; hKeepCount += run;
          hRuns.push({ y, x0: start, x1: x - 1 });
        }
        run = 0;
      }
    }
  }
  const vRuns = []; // {x, y0, y1}
  let vRunCount = 0, vKeepCount = 0;
  for (let x = 0; x < workW; x++) {
    let run = 0, start = 0;
    for (let y = 0; y <= workH; y++) {
      if (y < workH && ink[y * workW + x] === 1) {
        if (run === 0) start = y;
        run++;
      } else {
        if (run >= MINRUN && start > 0 && y < workH) {
          for (let yy = start; yy < y; yy++) keep[yy * workW + x] = 1;
          vRunCount++; vKeepCount += run;
          vRuns.push({ x, y0: start, y1: y - 1 });
        }
        run = 0;
      }
    }
  }
  let minX = workW, maxX = 0, minY = workH, maxY = 0, n = 0;
  for (let y = 0; y < workH; y++) {
    for (let x = 0; x < workW; x++) {
      if (keep[y * workW + x] === 1) {
        n++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  minX = Math.round(minX * invScale);
  maxX = Math.round(maxX * invScale);
  minY = Math.round(minY * invScale);
  maxY = Math.round(maxY * invScale);
  const bw = maxX - minX + 1, bh = maxY - minY + 1;
  const aspect = bh > 0 ? bw / bh : 0;
  const areaRatio = (bw * bh) / (W * H);
  const diag = `longRun(abs=${absThresh}): MINRUN=${MINRUN} hRuns=${hRunCount} hPx=${hKeepCount} vRuns=${vRunCount} vPx=${vKeepCount} n=${n} bbox=[${minX},${minY},${maxX},${maxY}] ${bw}x${bh} aspect=${aspect.toFixed(2)} areaRatio=${areaRatio.toFixed(3)}`;
  let verdict = 'OK';
  if (n < LONGRUN_MIN_PIXELS) verdict = `n<MIN(${LONGRUN_MIN_PIXELS})`;
  else if (hRunCount > workH * LONGRUN_MAX_RUN_COUNT_FRAC || vRunCount > workW * LONGRUN_MAX_RUN_COUNT_FRAC) verdict = 'runs>frac';
  let latticeInfo = '';
  if (useLattice && verdict === 'OK') {
    const lat = latticeBBox(hRuns, vRuns, workW, workH, LATTICE_DEBUG);
    if (lat !== null) {
      const box = latticeToBBox(lat, invScale);
      const l = box.l, t = box.t, rr = box.r, bb = box.b;
      const bw2 = rr - l + 1, bh2 = bb - t + 1;
      const asp2 = bh2 > 0 ? bw2 / bh2 : 0;
      const ar2 = (bw2 * bh2) / (W * H);
      latticeInfo = `lattice: h(count=${lat.hFit.count} s=${lat.hFit.s.toFixed(2)} phase=${lat.hFit.phase.toFixed(1)} span=[${lat.hFit.first.toFixed(1)},${lat.hFit.last.toFixed(1)}]) v(count=${lat.vFit.count} s=${lat.vFit.s.toFixed(2)} phase=${lat.vFit.phase.toFixed(1)} span=[${lat.vFit.first.toFixed(1)},${lat.vFit.last.toFixed(1)}]) cand=[${l},${t},${rr},${bb}] ${bw2}x${bh2} aspect=${asp2.toFixed(2)} areaRatio=${ar2.toFixed(3)}`;
      if (bw2 >= CONSERVATIVE_MIN_DIM && bh2 >= CONSERVATIVE_MIN_DIM &&
        asp2 >= LONGRUN_MIN_ASPECT && asp2 <= LONGRUN_MAX_ASPECT &&
        ar2 >= MIN_BOARD_AREA_RATIO && ar2 <= MAX_BOARD_AREA_RATIO) {
        return {
          bbox: { left: l, top: t, right: rr, bottom: bb, isDark },
          diag: diag + '\n  �?' + latticeInfo + ' ✓LATTICE',
          verdict: 'lattice', hRuns, vRuns, workW, workH, MINRUN, keep, ink
        };
      }
      latticeInfo += ' (rejected by checks)';
    }
  }
  if (verdict === 'OK') {
    if (bw < CONSERVATIVE_MIN_DIM || bh < CONSERVATIVE_MIN_DIM) verdict = 'dim<MIN';
    else if (aspect < LONGRUN_MIN_ASPECT || aspect > LONGRUN_MAX_ASPECT) verdict = 'aspect';
    else if (areaRatio < MIN_BOARD_AREA_RATIO || areaRatio > MAX_BOARD_AREA_RATIO) verdict = 'areaRatio';
  }
  const bbox = verdict === 'OK' ? { left: minX, top: minY, right: maxX, bottom: maxY, isDark } : null;
  return { bbox, diag: diag + (latticeInfo ? '\n  ' + latticeInfo : ''), verdict, hRuns, vRuns, workW, workH, MINRUN, keep, ink };
}

function findBoxLongRun(gray, W, H, isDark, bg, collectRuns, useLattice) {
  const baseOffset = 60;
  const baseAbs = isDark ? bg + baseOffset : bg - baseOffset;
  const r = findBoxLongRunWithThresh(gray, W, H, isDark, baseAbs, collectRuns, useLattice);
  if (r.bbox !== null) return r;
  for (const offset of LONGRUN_TIGHTER_OFFSETS) {
    if (offset >= baseOffset) continue;
    const r2 = findBoxLongRunWithThresh(gray, W, H, isDark, isDark ? bg + offset : bg - offset, collectRuns, useLattice);
    if (r2.bbox !== null) return r2;
  }
  return collectRuns ? r : { bbox: null, diag: r.diag, verdict: r.verdict };
}

// NEW cascade: remember the first raw-accepted bbox but keep scanning all
// offsets; a lattice hit at ANY offset takes priority (the grid structure is
// more trustworthy than raw extents polluted by shadows/paper edges).
function findBoxLongRunCascade(gray, W, H, isDark, bg, collectRuns) {
  const offsets = [60, ...LONGRUN_TIGHTER_OFFSETS.filter(o => o < 60)];
  let fallback = null;
  const diags = [];
  for (const off of offsets) {
    const abs = isDark ? bg + off : bg - off;
    const r = findBoxLongRunWithThresh(gray, W, H, isDark, abs, collectRuns, true);
    diags.push(r.diag);
    if (r.verdict === 'lattice' && r.bbox !== null) {
      return { bbox: r.bbox, diag: diags.join('\n'), verdict: `lattice@${off}`, hRuns: r.hRuns, vRuns: r.vRuns, workW: r.workW, workH: r.workH, MINRUN: r.MINRUN };
    }
    if (r.bbox !== null && fallback === null) {
      fallback = { bbox: r.bbox, verdict: `raw@${off}` };
    }
  }
  if (fallback !== null) return { ...fallback, diag: diags.join('\n') };
  return { bbox: null, diag: diags.join('\n'), verdict: 'null' };
}

// Aspect-gated cascade: a raw bbox whose aspect is "confidently square" is
// returned immediately (zero behavior change vs old cascade); only a
// suspicious aspect (shadows stretch one axis) keeps scanning for a lattice.
const CONFIDENT_ASPECT_MIN = 0.72;
const CONFIDENT_ASPECT_MAX = 1.39;
function findBoxLongRunCascade2(gray, W, H, isDark, bg, collectRuns) {
  const offsets = [60, ...LONGRUN_TIGHTER_OFFSETS.filter(o => o < 60)];
  let fallback = null;
  const diags = [];
  for (const off of offsets) {
    const abs = isDark ? bg + off : bg - off;
    const r = findBoxLongRunWithThresh(gray, W, H, isDark, abs, collectRuns, true);
    diags.push(r.diag);
    if (r.verdict === 'lattice' && r.bbox !== null) {
      return { bbox: r.bbox, diag: diags.join('\n'), verdict: `lattice@${off}`, hRuns: r.hRuns, vRuns: r.vRuns, workW: r.workW, workH: r.workH, MINRUN: r.MINRUN };
    }
    if (r.bbox !== null) {
      const asp = (r.bbox.right - r.bbox.left + 1) / (r.bbox.bottom - r.bbox.top + 1);
      if (fallback === null) fallback = { bbox: r.bbox, verdict: `raw@${off}` };
      if (asp >= CONFIDENT_ASPECT_MIN && asp <= CONFIDENT_ASPECT_MAX) {
        return { bbox: r.bbox, diag: diags.join('\n'), verdict: `raw@${off}` };
      }
    }
  }
  if (fallback !== null) return { ...fallback, diag: diags.join('\n') };
  return { bbox: null, diag: diags.join('\n'), verdict: 'null' };
}

// ===== candidate fix: lattice fitting =====
let LATTICE_DEBUG = false;
// Cluster runs into lines, fit an equal-spacing lattice (9 cells, 10 lines)
// independently for h/v. If both axes yield >=7 matched lines spanning ~9
// cells, build the bbox from lattice phase+spacing instead of raw run extents.
function clusterRunsToLines(runs, axis) {
  // axis 'h': group runs by y; 'v': by x
  const byPos = new Map();
  for (const rn of runs) {
    const p = axis === 'h' ? rn.y : rn.x;
    if (!byPos.has(p)) byPos.set(p, []);
    byPos.get(p).push(rn);
  }
  const lines = [];
  let prev = -100;
  for (const p of [...byPos.keys()].sort((a, b) => a - b)) {
    const group = byPos.get(p);
    const lo = axis === 'h' ? Math.min(...group.map(q => q.x0)) : Math.min(...group.map(q => q.y0));
    const hi = axis === 'h' ? Math.max(...group.map(q => q.x1)) : Math.max(...group.map(q => q.y1));
    if (p - prev <= 2 && lines.length > 0) {
      const L = lines[lines.length - 1];
      L.max = Math.max(L.max, p);
      L.pos = (L.min + L.max) / 2;
      L.lo = Math.min(L.lo, lo); L.hi = Math.max(L.hi, hi);
    } else {
      lines.push({ min: p, max: p, pos: p, lo, hi });
    }
    prev = p;
  }
  return lines;
}

function fitLattice(lines, minDim, debug) {
  if (lines.length < 7) return null;
  const sMin = Math.max(6, Math.floor(minDim / 32));
  const sMax = Math.max(sMin + 1, Math.floor(minDim / 8));
  const cands = [];
  const seen = new Set();
  for (let s = sMin; s <= sMax; s += 0.5) {
    const tol = Math.max(2, s * 0.22);
    for (const a of lines) {
      const chainFrom = (anchor) => {
        const chain = [anchor];
        let pos = anchor.pos;
        let misses = 0;
        while (misses <= 2) {
          const target = pos + s;
          let found = null;
          let bestD = Infinity;
          for (const L of lines) {
            if (chain.includes(L)) continue;
            const d = L.pos - target;
            if (L.pos >= pos + s - tol && L.pos <= pos + 2 * s + tol && Math.abs(d) < bestD) {
              bestD = Math.abs(d); found = L;
            }
          }
          if (found) { chain.push(found); pos = found.pos; misses = 0; }
          else { pos = pos + s; misses++; }
        }
        return chain;
      };
      const backChain = (() => {
        const chain = [a];
        let pos = a.pos;
        let misses = 0;
        while (misses <= 2) {
          const target = pos - s;
          let found = null;
          let bestD = Infinity;
          for (const L of lines) {
            if (chain.includes(L)) continue;
            const d = target - L.pos;
            if (L.pos <= pos - s + tol && L.pos >= pos - 2 * s - tol && Math.abs(d) < bestD) {
              bestD = Math.abs(d); found = L;
            }
          }
          if (found) { chain.push(found); pos = found.pos; misses = 0; }
          else { pos = pos - s; misses++; }
        }
        return chain;
      })();
      const full = [...backChain.slice(1).reverse(), ...chainFrom(a)];
      if (full.length < 7) continue;
      const sorted = full.slice().sort((p, q) => p.pos - q.pos);
      // enumerate trims from both ends; accept sub-chains with cells==9
      for (let tl = 0; tl <= sorted.length - 7; tl++) {
        for (let tr = 0; tr <= sorted.length - 7 - tl; tr++) {
          const sub = sorted.slice(tl, sorted.length - tr);
          const span = sub[sub.length - 1].pos - sub[0].pos;
          if (span < 8.5 * s) break; // further right-trims only shrink
          const cells = Math.round(span / s);
          if (cells !== 9) continue;
          let qSum = 0;
          for (let i = 1; i < sub.length; i++) {
            const gap = sub[i].pos - sub[i - 1].pos;
            const k = Math.max(1, Math.round(gap / s));
            const dev = Math.abs(gap - k * s);
            qSum += Math.max(0, 1 - dev / (k * s * 0.15));
          }
          const score = qSum * 100 + sub.length;
          const sig = `${sub[0].pos}|${sub[sub.length - 1].pos}|${s}`;
          if (seen.has(sig)) continue;
          seen.add(sig);
          cands.push({ score, chain: sub, s, span, cells, qSum });
          break; // one valid right-trim per left-trim is enough
        }
      }
    }
  }
  if (cands.length === 0) return null;
  cands.sort((p, q) => q.score - p.score);
  if (debug) {
    console.log(`  fitLattice: ${cands.length} candidates, top 8:`);
    for (const cd of cands.slice(0, 8)) {
      console.log(`    s=${cd.s} count=${cd.chain.length} span=${cd.span.toFixed(1)} qSum=${cd.qSum.toFixed(2)} score=${cd.score.toFixed(0)} lines=[${cd.chain.map(L => L.pos.toFixed(1)).join(',')}]`);
    }
  }
  const best = cands[0];
  // refine spacing & phase
  const sRef = best.span / best.cells;
  const firstPos = best.chain[0].pos;
  const offsets = best.chain.map(L => L.pos - firstPos - Math.round((L.pos - firstPos) / sRef) * sRef);
  offsets.sort((p, q) => p - q);
  const med = offsets.length % 2 === 1
    ? offsets[(offsets.length - 1) / 2]
    : (offsets[offsets.length / 2 - 1] + offsets[offsets.length / 2]) / 2;
  const phase = firstPos + med;
  const thicks = best.chain.map(L => L.max - L.min + 1).sort((p, q) => p - q);
  const medThick = thicks.length % 2 === 1 ? thicks[(thicks.length - 1) / 2] : (thicks[thicks.length / 2 - 1] + thicks[thicks.length / 2]) / 2;
  return { phase, s: sRef, cells: best.cells, count: best.chain.length, first: phase, last: phase + best.cells * sRef, medThick };
}

function latticeBBox(hRuns, vRuns, workW, workH, debug) {
  const hLines = clusterRunsToLines(hRuns, 'h');
  const vLines = clusterRunsToLines(vRuns, 'v');
  if (debug) {
    console.log(`  hLines: ${hLines.map(L => L.pos.toFixed(1)).join(',')}`);
    console.log(`  vLines: ${vLines.map(L => L.pos.toFixed(1)).join(',')}`);
    console.log('  --- h fitLattice ---');
  }
  const hFit = fitLattice(hLines, Math.min(workW, workH), debug);
  if (debug) console.log('  --- v fitLattice ---');
  const vFit = fitLattice(vLines, Math.min(workW, workH), debug);
  if (hFit === null || vFit === null) return null;
  return { hFit, vFit };
}

// build probe-space bbox from lattice fits, expanded by median half line thickness
function latticeToBBox(lat, invScale) {
  const hT = lat.hFit.medThick / 2;
  const vT = lat.vFit.medThick / 2;
  if (LATTICE_DEBUG) console.log(`  latticeToBBox: hFit.first=${lat.hFit.first.toFixed(2)} hFit.last=${lat.hFit.last.toFixed(2)} hT=${hT} vFit.first=${lat.vFit.first.toFixed(2)} vFit.last=${lat.vFit.last.toFixed(2)} vT=${vT}`);
  const l = Math.floor((lat.vFit.first - vT) * invScale);
  const t = Math.floor((lat.hFit.first - hT) * invScale);
  const r = Math.ceil((lat.vFit.last + vT) * invScale);
  const b = Math.ceil((lat.hFit.last + hT) * invScale);
  return { l, t, r, b };
}

async function analyze(filePath, collectRuns, useLattice) {
  const { pixels, W, H, origW, origH } = await loadProbePixels(filePath);
  const chBg = bgColor(pixels, W, H);
  const isDark = chBg.bg < BG_DARK_THRESHOLD;
  const gray = toGrayArray(pixels, W, H, chBg);
  const res = findBoxLongRun(gray, W, H, isDark, chBg.bg, collectRuns, useLattice);
  return { file: path.basename(filePath), origW, origH, probeW: W, probeH: H, chBg, isDark, ...res };
}

async function main() {
  const mode = process.argv[2] || 'baseline';
  const imgDir = path.join(__dirname, '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'sudoku_test_images');
  const files = fs.readdirSync(imgDir).filter(f => /\.(png|jpg)$/i.test(f)).sort();

  if (mode === 'dump') {
    const target = process.argv[3] || 'photos.jpg';
    const r = await analyze(path.join(imgDir, target), true);
    console.log(`${r.file}: orig=${r.origW}x${r.origH} probe=${r.probeW}x${r.probeH} bg=(${r.chBg.bgR},${r.chBg.bgG},${r.chBg.bgB}) isDark=${r.isDark} work=${r.workW}x${r.workH} MINRUN=${r.MINRUN}`);
    console.log(r.diag, '=>', r.verdict);
    // cluster hRuns by y into lines
    const hByY = new Map();
    for (const hr of r.hRuns) {
      if (!hByY.has(hr.y)) hByY.set(hr.y, []);
      hByY.get(hr.y).push(hr);
    }
    const hLines = [];
    let prevY = -10;
    for (const y of [...hByY.keys()].sort((a, b) => a - b)) {
      const runs = hByY.get(y);
      const x0 = Math.min(...runs.map(q => q.x0)), x1 = Math.max(...runs.map(q => q.x1));
      if (y - prevY <= 2) { const L = hLines[hLines.length - 1]; L.ys.push(y); L.x0 = Math.min(L.x0, x0); L.x1 = Math.max(L.x1, x1); }
      else hLines.push({ ys: [y], x0, x1 });
      prevY = y;
    }
    console.log(`hLines (work space, clustered): ${hLines.length}`);
    for (const L of hLines) console.log(`  y=[${L.ys[0]}..${L.ys[L.ys.length - 1]}] nY=${L.ys.length} x=[${L.x0}..${L.x1}]`);
    const vByX = new Map();
    for (const vr of r.vRuns) {
      if (!vByX.has(vr.x)) vByX.set(vr.x, []);
      vByX.get(vr.x).push(vr);
    }
    const vLines = [];
    let prevX = -10;
    for (const x of [...vByX.keys()].sort((a, b) => a - b)) {
      const runs = vByX.get(x);
      const y0 = Math.min(...runs.map(q => q.y0)), y1 = Math.max(...runs.map(q => q.y1));
      if (x - prevX <= 2) { const L = vLines[vLines.length - 1]; L.xs.push(x); L.y0 = Math.min(L.y0, y0); L.y1 = Math.max(L.y1, y1); }
      else vLines.push({ xs: [x], y0, y1 });
      prevX = x;
    }
    console.log(`vLines (work space, clustered): ${vLines.length}`);
    for (const L of vLines) console.log(`  x=[${L.xs[0]}..${L.xs[L.xs.length - 1]}] nX=${L.xs.length} y=[${L.y0}..${L.y1}]`);
    return;
  }

  if (mode === 'latdump') {
    const target = process.argv[3] || 'photos.jpg';
    LATTICE_DEBUG = true;
    const r = await analyze(path.join(imgDir, target), true, true);
    console.log(`${r.file}: probe=${r.probeW}x${r.probeH} verdict=${r.verdict}`);
    console.log(r.diag);
    return;
  }

  if (mode === 'cascade') {
    // compare: old cascade (first accepted wins) vs new cascade (lattice at any offset wins)
    let nChanged = 0;
    for (const f of files) {
      const { pixels, W, H, origW, origH } = await loadProbePixels(path.join(imgDir, f));
      const chBg = bgColor(pixels, W, H);
      const isDark = chBg.bg < BG_DARK_THRESHOLD;
      const gray = toGrayArray(pixels, W, H, chBg);
      const oldR = findBoxLongRun(gray, W, H, isDark, chBg.bg, false, true);
      const newR = findBoxLongRunCascade(gray, W, H, isDark, chBg.bg, false);
      const bb = (r) => r.bbox ? `[${r.bbox.left},${r.bbox.top},${r.bbox.right},${r.bbox.bottom}]` : 'null';
      const same = (oldR.bbox === null) === (newR.bbox === null) && (
        oldR.bbox === null || (
          oldR.bbox.left === newR.bbox.left && oldR.bbox.top === newR.bbox.top &&
          oldR.bbox.right === newR.bbox.right && oldR.bbox.bottom === newR.bbox.bottom));
      if (!same) nChanged++;
      const aspect = newR.bbox ? ((newR.bbox.right - newR.bbox.left + 1) / (newR.bbox.bottom - newR.bbox.top + 1)).toFixed(2) : '-';
      console.log(`${f.padEnd(30)} probe=${String(W).padStart(4)}x${String(H).padStart(4)} old=${bb(oldR).padEnd(22)} new=${bb(newR).padEnd(22)} aspect=${aspect} via=${newR.verdict} ${same ? 'same' : 'CHANGED'}`);
      if (!same) {
        console.log(`    old diag: ${oldR.diag.replace(/\n/g, ' | ')}`);
        console.log(`    new diag: ${newR.diag.replace(/\n/g, ' | ')}`);
      }
    }
    console.log(`\nchanged: ${nChanged}/${files.length}`);
    return;
  }

  if (mode === 'cascade2') {
    // aspect-gated cascade vs old cascade: expect identical on all images
    let nChanged = 0;
    for (const f of files) {
      const { pixels, W, H, origW, origH } = await loadProbePixels(path.join(imgDir, f));
      const chBg = bgColor(pixels, W, H);
      const isDark = chBg.bg < BG_DARK_THRESHOLD;
      const gray = toGrayArray(pixels, W, H, chBg);
      const oldR = findBoxLongRun(gray, W, H, isDark, chBg.bg, false, true);
      const newR = findBoxLongRunCascade2(gray, W, H, isDark, chBg.bg, false);
      const bb = (r) => r.bbox ? `[${r.bbox.left},${r.bbox.top},${r.bbox.right},${r.bbox.bottom}]` : 'null';
      const same = (oldR.bbox === null) === (newR.bbox === null) && (
        oldR.bbox === null || (
          oldR.bbox.left === newR.bbox.left && oldR.bbox.top === newR.bbox.top &&
          oldR.bbox.right === newR.bbox.right && oldR.bbox.bottom === newR.bbox.bottom));
      if (!same) nChanged++;
      console.log(`${f.padEnd(30)} old=${bb(oldR).padEnd(22)} new=${bb(newR).padEnd(22)} via=${newR.verdict} ${same ? 'same' : 'CHANGED'}`);
      if (!same) {
        console.log(`    old diag: ${oldR.diag.replace(/\n/g, ' | ')}`);
        console.log(`    new diag: ${newR.diag.replace(/\n/g, ' | ')}`);
      }
    }
    console.log(`\nchanged: ${nChanged}/${files.length}`);
    return;
  }

  if (mode === 'baseline' || mode === 'fix') {
    const useLattice = mode === 'fix';
    let nChanged = 0;
    for (const f of files) {
      const base = await analyze(path.join(imgDir, f), false, false);
      const fixed = useLattice ? await analyze(path.join(imgDir, f), false, true) : base;
      const bb = (r) => r.bbox ? `[${r.bbox.left},${r.bbox.top},${r.bbox.right},${r.bbox.bottom}]` : 'null';
      const same = (base.bbox === null) === (fixed.bbox === null) && (
        base.bbox === null || (
          base.bbox.left === fixed.bbox.left && base.bbox.top === fixed.bbox.top &&
          base.bbox.right === fixed.bbox.right && base.bbox.bottom === fixed.bbox.bottom));
      const changed = !same;
      if (changed) nChanged++;
      const aspect = fixed.bbox ? ((fixed.bbox.right - fixed.bbox.left + 1) / (fixed.bbox.bottom - fixed.bbox.top + 1)).toFixed(2) : '-';
      console.log(`${fixed.file.padEnd(30)} probe=${String(fixed.probeW).padStart(4)}x${String(fixed.probeH).padStart(4)} bbox=${bb(fixed).padEnd(22)} aspect=${aspect} ${changed ? 'CHANGED (was ' + bb(base) + ')' : 'same'}${fixed.verdict === 'lattice' ? ' [lattice]' : ''}`);
      if (changed || fixed.verdict === 'lattice') {
        console.log(`    base: ${base.diag}`);
        console.log(`    fix : ${fixed.diag}`);
      }
    }
    if (useLattice) console.log(`\nchanged: ${nChanged}/${files.length}`);
    return;
  }
  console.log('unknown mode:', mode);
}
main().catch(e => { console.error(e); process.exit(1); });
