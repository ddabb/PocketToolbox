import {
  BoardBBox, SP, MAX_BOARD_AREA_RATIO, MIN_BOARD_AREA_RATIO,
  ADAPTIVE_MAX_DIM, CONSERVATIVE_MIN_DIM, MINRUN_ABS_MIN, MINRUN_FRAC,
  LONGRUN_TIGHTER_OFFSETS, LONGRUN_MIN_PIXELS, LONGRUN_MAX_RUN_COUNT_FRAC, LONGRUN_MIN_ASPECT,
  LONGRUN_MAX_ASPECT, LATTICE_MIN_LINES, LATTICE_CELLS, LATTICE_CLUSTER_GAP,
  LATTICE_MAX_MISSES, LATTICE_TOL_FRAC, LATTICE_STEP_TOL_FRAC, LATTICE_S_MIN_DIV,
  LATTICE_S_MAX_DIV, LONGRAW_CONFIDENT_ASPECT_MIN, LONGRAW_CONFIDENT_ASPECT_MAX
} from './SudokuPixelKernel';

// Set by findBoxLongRunWithThresh: true when the returned bbox came from the
// lattice fit (rather than raw run extents); read by findBoxLongRun's cascade.
let g_lastThreshWasLattice: boolean = false;

// 长行程棋盘定位：数独棋盘的 10 条横线与 10 条竖线都是贯穿整张棋盘的长直线，
// 而木纹/阴影等背景噪声多为短促笔画或渐变，不构成贯穿直线。
// 对"严格阈值二值图"做长行程(run-length)过滤并排除贴图像边缘的行程，
// 仅保留属于长水平/垂直笔画的像素，其包围盒即为棋盘。
// 该方法对 photos.jpg（浅木纹桌面 + 顶部阴影）这类复杂背景鲁棒。
interface GridLine {
  min: number;
  max: number;
  pos: number;
}

interface LatticeCand {
  score: number;
  qSum: number;
  idxs: number[];
  thicknesses: number[];
}

interface LatticeFit {
  phase: number;
  s: number;
  count: number;
  first: number;
  last: number;
  medThick: number;
}

// Cluster run positions (non-decreasing scan order) into lines: positions
// within LATTICE_CLUSTER_GAP of the previous cluster merge into one line
// (thick / antialiased strokes produce runs on several adjacent rows).
function clusterRunsToLines(posList: number[]): GridLine[] {
  const lines: GridLine[] = [];
  let prev: number = -100;
  for (let i = 0; i < posList.length; i++) {
    const p: number = posList[i];
    if (p - prev <= LATTICE_CLUSTER_GAP && lines.length > 0) {
      const L: GridLine = lines[lines.length - 1];
      if (p > L.max) {
        L.max = p;
        L.pos = (L.min + L.max) / 2;
      }
    } else {
      const L: GridLine = { min: p, max: p, pos: p };
      lines.push(L);
    }
    prev = p;
  }
  return lines;
}

function medianOf(sortedVals: number[]): number {
  const n: number = sortedVals.length;
  if (n === 0) { return 0; }
  if (n % 2 === 1) { return sortedVals[(n - 1) / 2]; }
  return (sortedVals[n / 2 - 1] + sortedVals[n / 2]) / 2;
}

// Greedy lattice walk from an anchor in one direction. Accepts the nearest
// line within one cell (or two, when bridging missing lines) of the expected
// position; after LATTICE_MAX_MISSES consecutive misses the walk stops.
// Returns indices into lines (anchor first). inChain marks used lines.
function latticeWalk(lines: GridLine[], inChain: boolean[], anchorIdx: number, s: number, tol: number, dir: number): number[] {
  const idx: number[] = [anchorIdx];
  inChain[anchorIdx] = true;
  let pos: number = lines[anchorIdx].pos;
  let misses: number = 0;
  while (misses <= LATTICE_MAX_MISSES) {
    const target: number = pos + dir * s;
    let found: number = -1;
    let bestD: number = Infinity;
    for (let li = 0; li < lines.length; li++) {
      if (inChain[li]) { continue; }
      const lp: number = lines[li].pos;
      const lo: number = dir > 0 ? pos + s - tol : pos - 2 * s - tol;
      const hi: number = dir > 0 ? pos + 2 * s + tol : pos - s + tol;
      if (lp >= lo && lp <= hi && Math.abs(lp - target) < bestD) {
        bestD = Math.abs(lp - target);
        found = li;
      }
    }
    if (found >= 0) {
      idx.push(found);
      inChain[found] = true;
      pos = lines[found].pos;
      misses = 0;
    } else {
      pos += dir * s;
      misses++;
    }
  }
  return idx;
}

// Fit an equal-spacing lattice (LATTICE_CELLS cells) to clustered lines.
// Scans candidate spacings, walks greedy chains from every anchor, enumerates
// end-trims (a chain polluted by off-grid lines must still yield its 9-cell
// core), and scores candidates by step regularity. Returns the best fit with
// refined phase (median of per-line offsets) and spacing.
function fitLattice(lines: GridLine[], minDim: number): LatticeFit | null {
  if (lines.length < LATTICE_MIN_LINES) { return null; }
  const sMin: number = Math.max(6, Math.floor(minDim / LATTICE_S_MIN_DIV));
  const sMax: number = Math.max(sMin + 1, Math.floor(minDim / LATTICE_S_MAX_DIV));
  const inChain: boolean[] = new Array<boolean>(lines.length).fill(false);
  const cands: LatticeCand[] = [];
  const seen: Set<string> = new Set<string>();
  for (let s = sMin; s <= sMax; s += 0.5) {
    const tol: number = Math.max(2, s * LATTICE_TOL_FRAC);
    for (let ai = 0; ai < lines.length; ai++) {
      const fwd: number[] = latticeWalk(lines, inChain, ai, s, tol, 1);
      const back: number[] = latticeWalk(lines, inChain, ai, s, tol, -1);
      for (let i = 0; i < fwd.length; i++) { inChain[fwd[i]] = false; }
      for (let i = 0; i < back.length; i++) { inChain[back[i]] = false; }
      const full: number[] = [];
      for (let i = back.length - 1; i >= 1; i--) { full.push(back[i]); }
      for (let i = 0; i < fwd.length; i++) { full.push(fwd[i]); }
      if (full.length < LATTICE_MIN_LINES) { continue; }
      full.sort((a: number, b: number) => lines[a].pos - lines[b].pos);
      for (let tl = 0; tl <= full.length - LATTICE_MIN_LINES; tl++) {
        for (let tr = 0; tr <= full.length - LATTICE_MIN_LINES - tl; tr++) {
          const firstI: number = full[tl];
          const lastI: number = full[full.length - 1 - tr];
          const span: number = lines[lastI].pos - lines[firstI].pos;
          if (span < 8.5 * s) { break; }
          const cells: number = Math.round(span / s);
          if (cells !== LATTICE_CELLS) { continue; }
          const cnt: number = full.length - tl - tr;
          let qSum: number = 0;
          for (let i = tl + 1; i <= full.length - 1 - tr; i++) {
            const gap: number = lines[full[i]].pos - lines[full[i - 1]].pos;
            const k: number = Math.max(1, Math.round(gap / s));
            const dev: number = Math.abs(gap - k * s);
            qSum += Math.max(0, 1 - dev / (k * s * LATTICE_STEP_TOL_FRAC));
          }
          const score: number = qSum * 100 + cnt;
          const sig: string = `${lines[firstI].pos.toFixed(1)}|${lines[lastI].pos.toFixed(1)}|${s}`;
          if (seen.has(sig)) { continue; }
          seen.add(sig);
          const thicks: number[] = [];
          const idxs: number[] = [];
          for (let i = tl; i <= full.length - 1 - tr; i++) {
            idxs.push(full[i]);
            thicks.push(lines[full[i]].max - lines[full[i]].min + 1);
          }
          thicks.sort((a: number, b: number) => a - b);
          cands.push({ score: score, qSum: qSum, idxs: idxs, thicknesses: thicks });
          break;
        }
      }
    }
  }
  if (cands.length === 0) { return null; }
  cands.sort((a: LatticeCand, b: LatticeCand) => b.score - a.score);
  const best: LatticeCand = cands[0];
  const span: number = lines[best.idxs[best.idxs.length - 1]].pos - lines[best.idxs[0]].pos;
  const sRef: number = span / LATTICE_CELLS;
  const firstPos: number = lines[best.idxs[0]].pos;
  const offsets: number[] = [];
  for (let i = 0; i < best.idxs.length; i++) {
    const p: number = lines[best.idxs[i]].pos;
    offsets.push(p - firstPos - Math.round((p - firstPos) / sRef) * sRef);
  }
  offsets.sort((a: number, b: number) => a - b);
  const phase: number = firstPos + medianOf(offsets);
  const medThick: number = medianOf(best.thicknesses);
  return {
    phase: phase, s: sRef, count: best.idxs.length,
    first: phase, last: phase + LATTICE_CELLS * sRef, medThick: medThick
  };
}

// Try to build a board bbox (probe space) from lattice fits of both axes:
// the lattice extent (expanded by median half line thickness) is scaled back
// to probe space with floor/ceil applied after scaling (same rounding as the
// validated prototype), then clamped to image bounds. Returns null when
// either axis has no confident lattice fit.
function tryLatticeBBoxWork(
  hPosList: number[], vPosList: number[], workW: number, workH: number,
  invScale: number, W: number, H: number
): [number, number, number, number] | null {
  const hLines: GridLine[] = clusterRunsToLines(hPosList);
  const vLines: GridLine[] = clusterRunsToLines(vPosList);
  const minDim: number = Math.min(workW, workH);
  const hFit: LatticeFit | null = fitLattice(hLines, minDim);
  if (hFit === null) { return null; }
  const vFit: LatticeFit | null = fitLattice(vLines, minDim);
  if (vFit === null) { return null; }
  const hT: number = hFit.medThick / 2;
  const vT: number = vFit.medThick / 2;
  SP.lastBboxDiag += `\n  lattice h(count=${hFit.count} s=${hFit.s.toFixed(2)} phase=${hFit.phase.toFixed(1)}) v(count=${vFit.count} s=${vFit.s.toFixed(2)} phase=${vFit.phase.toFixed(1)}) thick=${hFit.medThick.toFixed(1)}/${vFit.medThick.toFixed(1)}`;
  const l: number = Math.max(0, Math.min(W - 1, Math.floor((vFit.first - vT) * invScale)));
  const t: number = Math.max(0, Math.min(H - 1, Math.floor((hFit.first - hT) * invScale)));
  const r: number = Math.max(0, Math.min(W - 1, Math.ceil((vFit.last + vT) * invScale)));
  const b: number = Math.max(0, Math.min(H - 1, Math.ceil((hFit.last + hT) * invScale)));
  return [l, t, r, b];
}

function findBoxLongRunWithThresh(
  gray: Float32Array, W: number, H: number, isDark: boolean, absThresh: number
): BoardBBox | null {
  g_lastThreshWasLattice = false;
  let workGray: Float32Array = gray;
  let workW: number = W;
  let workH: number = H;
  let scale: number = 1;
  const maxDim: number = Math.max(W, H);
  if (maxDim > ADAPTIVE_MAX_DIM) {
    scale = ADAPTIVE_MAX_DIM / maxDim;
    workW = Math.max(1, Math.round(W * scale));
    workH = Math.max(1, Math.round(H * scale));
    workGray = new Float32Array(workW * workH);
    for (let y: number = 0; y < workH; y++) {
      const srcY: number = Math.min(Math.floor(y / scale), H - 1);
      for (let x: number = 0; x < workW; x++) {
        const srcX: number = Math.min(Math.floor(x / scale), W - 1);
        workGray[y * workW + x] = gray[srcY * W + srcX];
      }
    }
  }
  const invScale: number = 1 / scale;
  const ink: Uint8Array = new Uint8Array(workW * workH);
  for (let i: number = 0; i < workW * workH; i++) {
    ink[i] = isDark ? (workGray[i] > absThresh ? 1 : 0) : (workGray[i] < absThresh ? 1 : 0);
  }
  const keep: Uint8Array = new Uint8Array(workW * workH);
  const MINRUN: number = Math.max(MINRUN_ABS_MIN, Math.floor(Math.min(workW, workH) * MINRUN_FRAC));
  let hRunCount: number = 0;
  let hKeepCount: number = 0;
  const hPosList: number[] = [];
  for (let y: number = 0; y < workH; y++) {
    let run: number = 0;
    let start: number = 0;
    for (let x: number = 0; x <= workW; x++) {
      if (x < workW && ink[y * workW + x] === 1) {
        if (run === 0) { start = x; }
        run++;
      } else {
        if (run >= MINRUN && start > 0 && x < workW) {
          for (let xx: number = start; xx < x; xx++) { keep[y * workW + xx] = 1; }
          hRunCount++;
          hKeepCount += run;
          hPosList.push(y);
        }
        run = 0;
      }
    }
  }
  let vRunCount: number = 0;
  let vKeepCount: number = 0;
  const vPosList: number[] = [];
  for (let x: number = 0; x < workW; x++) {
    let run: number = 0;
    let start: number = 0;
    for (let y: number = 0; y < workH; y++) {
      if (ink[y * workW + x] === 1) {
        if (run === 0) { start = y; }
        run++;
      } else {
        if (run >= MINRUN && start > 0 && y < workH) {
          for (let yy: number = start; yy < y; yy++) { keep[yy * workW + x] = 1; }
          vRunCount++;
          vKeepCount += run;
          vPosList.push(x);
        }
        run = 0;
      }
    }
  }
  let minX: number = workW, maxX: number = 0, minY: number = workH, maxY: number = 0, n: number = 0;
  for (let y: number = 0; y < workH; y++) {
    for (let x: number = 0; x < workW; x++) {
      if (keep[y * workW + x] === 1) {
        n++;
        if (x < minX) { minX = x; }
        if (x > maxX) { maxX = x; }
        if (y < minY) { minY = y; }
        if (y > maxY) { maxY = y; }
      }
    }
  }
  minX = Math.round(minX * invScale);
  maxX = Math.round(maxX * invScale);
  minY = Math.round(minY * invScale);
  maxY = Math.round(maxY * invScale);
  const bw: number = maxX - minX + 1;
  const bh: number = maxY - minY + 1;
  const aspect: number = bh > 0 ? bw / bh : 0;
  const areaRatio: number = (bw * bh) / (W * H);
  const diag: string = `longRun(abs=${absThresh}): MINRUN=${MINRUN} hRuns=${hRunCount} hPx=${hKeepCount} vRuns=${vRunCount} vPx=${vKeepCount} n=${n} bbox=[${minX},${minY},${maxX},${maxY}] ${bw}x${bh} aspect=${aspect.toFixed(2)} areaRatio=${areaRatio.toFixed(3)}`;
  SP.lastBboxDiag += (SP.lastBboxDiag.length > 0 ? '\n' : '') + diag;
  if (n < LONGRUN_MIN_PIXELS) {
    SP.lastBboxDiag += `\n  → n<MIN(${LONGRUN_MIN_PIXELS}) null`;
    return null;
  }
  if (hRunCount > workH * LONGRUN_MAX_RUN_COUNT_FRAC || vRunCount > workW * LONGRUN_MAX_RUN_COUNT_FRAC) {
    SP.lastBboxDiag += `\n  → runs>${LONGRUN_MAX_RUN_COUNT_FRAC.toFixed(2)}dim null`;
    return null;
  }
  // Lattice fitting: raw run extents can include table shadows / paper edges
  // beyond the grid; an equal-spacing lattice fit on both axes rejects them.
  const latBox: [number, number, number, number] | null =
    tryLatticeBBoxWork(hPosList, vPosList, workW, workH, invScale, W, H);
  if (latBox !== null) {
    const lL: number = latBox[0];
    const lT: number = latBox[1];
    const lR: number = latBox[2];
    const lB: number = latBox[3];
    const lBw: number = lR - lL + 1;
    const lBh: number = lB - lT + 1;
    const lAsp: number = lBh > 0 ? lBw / lBh : 0;
    const lAr: number = (lBw * lBh) / (W * H);
    SP.lastBboxDiag += `\n  lattice bbox=[${lL},${lT},${lR},${lB}] ${lBw}x${lBh} aspect=${lAsp.toFixed(2)} areaRatio=${lAr.toFixed(3)}`;
    if (lBw >= CONSERVATIVE_MIN_DIM && lBh >= CONSERVATIVE_MIN_DIM &&
      lAsp >= LONGRUN_MIN_ASPECT && lAsp <= LONGRUN_MAX_ASPECT &&
      lAr >= MIN_BOARD_AREA_RATIO && lAr <= MAX_BOARD_AREA_RATIO) {
      SP.lastBboxDiag += `\n  → ✓lattice`;
      g_lastThreshWasLattice = true;
      return { left: lL, top: lT, right: lR, bottom: lB, isDark };
    }
    SP.lastBboxDiag += `\n  → lattice rejected, fallback raw extents`;
  }
  if (bw < CONSERVATIVE_MIN_DIM || bh < CONSERVATIVE_MIN_DIM) {
    SP.lastBboxDiag += `\n  → dim<MIN(${CONSERVATIVE_MIN_DIM}) null`;
    return null;
  }
  if (aspect < LONGRUN_MIN_ASPECT || aspect > LONGRUN_MAX_ASPECT) {
    SP.lastBboxDiag += `\n  → aspect∉[${LONGRUN_MIN_ASPECT},${LONGRUN_MAX_ASPECT}] null`;
    return null;
  }
  if (areaRatio < MIN_BOARD_AREA_RATIO || areaRatio > MAX_BOARD_AREA_RATIO) {
    SP.lastBboxDiag += `\n  → areaRatio∉[${MIN_BOARD_AREA_RATIO},${MAX_BOARD_AREA_RATIO.toFixed(2)}] null`;
    return null;
  }
  SP.lastBboxDiag += `\n  → ✓`;
  return { left: minX, top: minY, right: maxX, bottom: maxY, isDark };
}

export function findBoxLongRun(
  gray: Float32Array, W: number, H: number, isDark: boolean, bg: number
): BoardBBox | null {
  const baseOffset: number = 60;
  const offsets: number[] = [baseOffset];
  for (let i: number = 0; i < LONGRUN_TIGHTER_OFFSETS.length; i++) {
    if (LONGRUN_TIGHTER_OFFSETS[i] < baseOffset) {
      offsets.push(LONGRUN_TIGHTER_OFFSETS[i]);
    }
  }
  let fallback: BoardBBox | null = null;
  let latticeBest: BoardBBox | null = null;
  for (let i: number = 0; i < offsets.length; i++) {
    const abs: number = isDark ? bg + offsets[i] : bg - offsets[i];
    const r: BoardBBox | null = findBoxLongRunWithThresh(gray, W, H, isDark, abs);
    if (r === null) { continue; }
    if (g_lastThreshWasLattice) {
      SP.lastBboxDiag += `\n  → lattice held, scanning tighter thresholds`;
      latticeBest = r;
      continue;
    }
    const bw: number = r.right - r.left + 1;
    const bh: number = r.bottom - r.top + 1;
    const asp: number = bh > 0 ? bw / bh : 0;
    if (asp >= LONGRAW_CONFIDENT_ASPECT_MIN && asp <= LONGRAW_CONFIDENT_ASPECT_MAX) {
      if (latticeBest === null) {
        return r;
      }
      SP.lastBboxDiag += `\n  → raw confident but lattice candidate exists, keep scanning`;
    } else if (fallback === null) {
      fallback = r;
      SP.lastBboxDiag += `\n  → raw bbox aspect outside confident range, kept as fallback; scanning remaining thresholds for lattice`;
    }
  }
  if (latticeBest !== null) {
    SP.lastBboxDiag += `\n  → final lattice (tightest)`;
    return latticeBest;
  }
  return fallback;
}
