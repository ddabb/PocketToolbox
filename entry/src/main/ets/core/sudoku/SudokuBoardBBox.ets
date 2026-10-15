import {
  BoardBBox, SP, INK_THRESH, MIN_BOARD_DIM,
  MIN_BOARD_ASPECT, MAX_BOARD_ASPECT, MAX_BOARD_AREA_RATIO, MIN_BOARD_SIZE_FRAC,
  ADAPTIVE_CONTRASTS, ADAPTIVE_THRESHOLDS, ADAPTIVE_PEAK_THRESH, ADAPTIVE_MAX_DIM,
  CONSERVATIVE_DELTAS, CONSERVATIVE_PEAK_THRESH, CONSERVATIVE_MIN_PEAKS, CONSERVATIVE_MIN_ASPECT,
  CONSERVATIVE_MAX_ASPECT, CONSERVATIVE_MIN_DIM, PERIODIC_MIN_PEAKS, BBOX_PRIMARY_THRESH,
  BBOX_PRIMARY_MIN_FRAC, BBOX_RELAXED_THRESHOLDS, BBOX_RELAXED_MIN_FRAC, BBOX_REGION_THRESHOLDS,
  BBOX_REGION_MIN_FRAC, BBOX_REGIONS, BBOX_PORTRAIT_REGIONS, BBOX_LANDSCAPE_REGIONS,
  PORTRAIT_ASPECT_THRESHOLD, BG_DARK_THRESHOLD
} from './SudokuPixelKernel';
import {
  isInkPixel, computeContrastPixel, bgColor, toGrayArray,
  boxBlur, dilate3x3, morphOpen3x3
} from './SudokuGrayOps';
import { findBoxLongRun } from './SudokuLatticeFit';

interface ProjectionResult {
  colInk: number[];
  rowInk: number[];
  rw: number;
  rh: number;
}

function computeProjectionsGray(
  gray: Float32Array, W: number, H: number,
  bg: number, isDark: boolean, thresh: number,
  rx0: number, ry0: number, rx1: number, ry1: number,
  step: number
): ProjectionResult {
  const rw: number = rx1 - rx0;
  const rh: number = ry1 - ry0;
  const colInk: number[] = new Array<number>(rw).fill(0);
  const rowInk: number[] = new Array<number>(rh).fill(0);
  const inkBg: number = isDark ? bg + thresh : bg - thresh;
  for (let x: number = 0; x < rw; x++) {
    let c: number = 0;
    for (let y: number = 0; y < rh; y += step) {
      const g: number = gray[(y + ry0) * W + (x + rx0)];
      if (isDark ? g > inkBg : g < inkBg) { c++; }
    }
    colInk[x] = c;
  }
  for (let y: number = 0; y < rh; y++) {
    let c: number = 0;
    for (let x: number = 0; x < rw; x += step) {
      const g: number = gray[(y + ry0) * W + (x + rx0)];
      if (isDark ? g > inkBg : g < inkBg) { c++; }
    }
    rowInk[y] = c;
  }
  const result: ProjectionResult = { colInk: colInk, rowInk: rowInk, rw: rw, rh: rh };
  return result;
}

function findBBoxFromProjections(
  colInk: number[], rowInk: number[],
  rw: number, rh: number,
  rx0: number, ry0: number,
  threshold: number, minFrac: number,
  sampleStep: number,
  isDark: boolean
): BoardBBox | null {
  let minX: number = rw;
  let maxX: number = 0;
  let minY: number = rh;
  let maxY: number = 0;
  let found: boolean = false;
  for (let x: number = 0; x < rw; x++) {
    if (colInk[x] / (rh / sampleStep) > threshold) {
      if (x < minX) { minX = x; }
      if (x > maxX) { maxX = x; }
      found = true;
    }
  }
  for (let y: number = 0; y < rh; y++) {
    if (rowInk[y] / (rw / sampleStep) > threshold) {
      if (y < minY) { minY = y; }
      if (y > maxY) { maxY = y; }
      found = true;
    }
  }
  if (!found || maxX - minX < rw * minFrac || maxY - minY < rh * minFrac) {
    return null;
  }
  const bw: number = maxX - minX + 1;
  const bh: number = maxY - minY + 1;
  if (bw < MIN_BOARD_DIM || bh < MIN_BOARD_DIM) { return null; }
  return { left: minX + rx0, top: minY + ry0, right: maxX + rx0, bottom: maxY + ry0, isDark };
}

function findBBoxInRectGray(
  gray: Float32Array, W: number, H: number,
  bg: number, isDark: boolean,
  rx0: number, ry0: number, rx1: number, ry1: number,
  threshold: number, minFrac: number
): BoardBBox | null {
  const rw: number = rx1 - rx0;
  const rh: number = ry1 - ry0;
  if (rw < MIN_BOARD_DIM || rh < MIN_BOARD_DIM) { return null; }
  const proj = computeProjectionsGray(gray, W, H, bg, isDark, INK_THRESH, rx0, ry0, rx1, ry1, 2);
  return findBBoxFromProjections(proj.colInk, proj.rowInk, proj.rw, proj.rh, rx0, ry0, threshold, minFrac, 2, isDark);
}

function findBBoxInRect(
  pixels: Uint8Array, width: number, height: number,
  bg: number, isDark: boolean,
  rx0: number, ry0: number, rx1: number, ry1: number,
  threshold: number, minFrac: number
): BoardBBox | null {
  const rw: number = rx1 - rx0;
  const rh: number = ry1 - ry0;
  if (rw < MIN_BOARD_DIM || rh < MIN_BOARD_DIM) { return null; }
  const colInk: number[] = new Array<number>(rw).fill(0);
  const rowInk: number[] = new Array<number>(rh).fill(0);
  for (let x: number = 0; x < rw; x++) {
    let c: number = 0;
    for (let y: number = 0; y < rh; y += 2) {
      const off: number = ((y + ry0) * width + (x + rx0)) * 4;
      const g: number = computeContrastPixel(pixels, off);
      if (isInkPixel(g, bg, isDark)) { c++; }
    }
    colInk[x] = c;
  }
  for (let y: number = 0; y < rh; y++) {
    let c: number = 0;
    for (let x: number = 0; x < rw; x += 2) {
      const off: number = ((y + ry0) * width + (x + rx0)) * 4;
      const g: number = computeContrastPixel(pixels, off);
      if (isInkPixel(g, bg, isDark)) { c++; }
    }
    rowInk[y] = c;
  }
  return findBBoxFromProjections(colInk, rowInk, rw, rh, rx0, ry0, threshold, minFrac, 2, isDark);
}

function isValidBoardAspect(bbox: BoardBBox, W: number, H: number): boolean {
  const bw: number = bbox.right - bbox.left;
  const bh: number = bbox.bottom - bbox.top;
  if (bw < MIN_BOARD_DIM || bh < MIN_BOARD_DIM) { return false; }
  const aspect: number = bw / bh;
  if (aspect < MIN_BOARD_ASPECT || aspect > MAX_BOARD_ASPECT) { return false; }
  if (bw < W * MIN_BOARD_SIZE_FRAC || bh < H * MIN_BOARD_SIZE_FRAC) { return false; }
  return true;
}

function findPeriodicPeaks(frac: number[], threshold: number): number[] {
  const peaks: number[] = [];
  for (let i: number = 0; i < frac.length; i++) {
    if (frac[i] > threshold) {
      let end: number = i;
      while (end + 1 < frac.length && frac[end + 1] > threshold) { end++; }
      peaks.push(Math.floor((i + end) / 2));
      i = end;
    }
  }
  if (peaks.length < PERIODIC_MIN_PEAKS) { return peaks; }
  let bestSpacing: number = 0;
  let bestConf: number = 0;
  const minSpacing: number = Math.max(3, Math.floor(frac.length / 15));
  const maxSpacing: number = Math.floor(frac.length / 5);
  for (let sp: number = minSpacing; sp <= maxSpacing; sp++) {
    let count: number = 0;
    let sumDiff: number = 0;
    let lastPeak: number = -sp * 2;
    for (const p of peaks) {
      const diff: number = p - lastPeak;
      if (diff >= sp * 0.7 && diff <= sp * 1.3) {
        count++;
        sumDiff += Math.abs(diff - sp);
        lastPeak = p;
      } else if (diff > sp * 1.3) {
        lastPeak = p;
      }
    }
    if (count >= PERIODIC_MIN_PEAKS) {
      const avgDev: number = count > 0 ? sumDiff / count / sp : 1;
      const conf: number = count - avgDev * 2;
      if (conf > bestConf) { bestConf = conf; bestSpacing = sp; }
    }
  }
  if (bestSpacing > 0) {
    const selected: number[] = [];
    let lastPeak: number = -bestSpacing * 2;
    for (const p of peaks) {
      const diff: number = p - lastPeak;
      if (diff >= bestSpacing * 0.7 && diff <= bestSpacing * 1.3) {
        selected.push(p);
        lastPeak = p;
      } else if (diff > bestSpacing * 1.3) {
        selected.length = 0;
        selected.push(p);
        lastPeak = p;
      }
    }
    if (selected.length >= PERIODIC_MIN_PEAKS) { return selected; }
  }
  let bestStart: number = 0;
  let bestCount: number = 0;
  for (let i: number = 0; i < peaks.length - 1; i++) {
    const spacing: number = peaks[i + 1] - peaks[i];
    if (spacing < 3) { continue; }
    let count: number = 2;
    let lastPos: number = peaks[i + 1];
    for (let j: number = i + 2; j < peaks.length; j++) {
      if (peaks[j] - lastPos <= spacing * 1.3 && peaks[j] - lastPos >= spacing * 0.7) {
        count++;
        lastPos = peaks[j];
      }
    }
    if (count > bestCount) { bestCount = count; bestStart = i; }
  }
  if (bestCount >= PERIODIC_MIN_PEAKS) { return peaks.slice(bestStart, bestStart + bestCount); }
  return peaks;
}



function findBBoxAdaptive(gray: Float32Array, W: number, H: number, isDark: boolean): BoardBBox | null {
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
  const winR: number = Math.max(5, Math.floor(Math.min(workW, workH) / 25));
  const blurred: Float32Array = boxBlur(workGray, workW, workH, winR);

  for (const C of ADAPTIVE_CONTRASTS) {
    let binary: Uint8Array = new Uint8Array(workW * workH);
    for (let i: number = 0; i < workW * workH; i++) {
      if (isDark) {
        binary[i] = (workGray[i] > blurred[i] + C) ? 1 : 0;
      } else {
        binary[i] = (workGray[i] < blurred[i] - C) ? 1 : 0;
      }
    }
    binary = morphOpen3x3(binary, workW, workH);
    binary = dilate3x3(dilate3x3(binary, workW, workH), workW, workH);

    const colInk: number[] = new Array<number>(workW).fill(0);
    const rowInk: number[] = new Array<number>(workH).fill(0);
    for (let x: number = 0; x < workW; x++) {
      let c: number = 0;
      for (let y: number = 0; y < workH; y += 2) {
        if (binary[y * workW + x] === 1) { c++; }
      }
      colInk[x] = c;
    }
    for (let y: number = 0; y < workH; y++) {
      let c: number = 0;
      for (let x: number = 0; x < workW; x += 2) {
        if (binary[y * workW + x] === 1) { c++; }
      }
      rowInk[y] = c;
    }
    const colFrac: number[] = colInk.map((c: number) => c / (workH / 2));
    const rowFrac: number[] = rowInk.map((c: number) => c / (workW / 2));

    for (const thresh of ADAPTIVE_THRESHOLDS) {
      let minX: number = workW;
      let maxX: number = 0;
      let minY: number = workH;
      let maxY: number = 0;
      let found: boolean = false;
      for (let x: number = 0; x < workW; x++) {
        if (colFrac[x] > thresh) { if (x < minX) { minX = x; } if (x > maxX) { maxX = x; } found = true; }
      }
      for (let y: number = 0; y < workH; y++) {
        if (rowFrac[y] > thresh) { if (y < minY) { minY = y; } if (y > maxY) { maxY = y; } found = true; }
      }
      if (found) {
        const bbox: BoardBBox = {
          left: Math.round(minX * invScale),
          top: Math.round(minY * invScale),
          right: Math.round(maxX * invScale),
          bottom: Math.round(maxY * invScale),
          isDark
        };
        if (isValidBoardAspect(bbox, W, H) && bbox.right - bbox.left >= W * MIN_BOARD_SIZE_FRAC && bbox.bottom - bbox.top >= H * MIN_BOARD_SIZE_FRAC) {
          return bbox;
        }
      }
    }

    const colPeaks: number[] = findPeriodicPeaks(colFrac, ADAPTIVE_PEAK_THRESH);
    const rowPeaks: number[] = findPeriodicPeaks(rowFrac, ADAPTIVE_PEAK_THRESH);
    if (colPeaks.length >= PERIODIC_MIN_PEAKS && rowPeaks.length >= PERIODIC_MIN_PEAKS) {
      const bbox: BoardBBox = {
        left: Math.round(colPeaks[0] * invScale),
        top: Math.round(rowPeaks[0] * invScale),
        right: Math.round(colPeaks[colPeaks.length - 1] * invScale),
        bottom: Math.round(rowPeaks[rowPeaks.length - 1] * invScale),
        isDark
      };
      if (isValidBoardAspect(bbox, W, H)) {
        return bbox;
      }
    }
  }
  return null;
}

function findBBoxConservative(
  gray: Float32Array, W: number, H: number, isDark: boolean, bg: number
): BoardBBox | null {
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
  for (const delta of CONSERVATIVE_DELTAS) {
    const thr: number = isDark ? bg + delta : bg - delta;
    const binary: Uint8Array = new Uint8Array(workW * workH);
    for (let i: number = 0; i < workW * workH; i++) {
      binary[i] = isDark ? (workGray[i] > thr ? 1 : 0)
        : (workGray[i] < thr ? 1 : 0);
    }

    const colInk: number[] = new Array(workW).fill(0);
    const rowInk: number[] = new Array(workH).fill(0);
    for (let x: number = 0; x < workW; x++) {
      let c: number = 0;
      for (let y: number = 0; y < workH; y += 2) {
        if (binary[y * workW + x] === 1) { c++; }
      }
      colInk[x] = c;
    }
    for (let y: number = 0; y < workH; y++) {
      let c: number = 0;
      for (let x: number = 0; x < workW; x += 2) {
        if (binary[y * workW + x] === 1) { c++; }
      }
      rowInk[y] = c;
    }
    const colFrac: number[] = colInk.map((c: number) => c / (workH / 2));
    const rowFrac: number[] = rowInk.map((c: number) => c / (workW / 2));

    const colPeaks: number[] = findPeriodicPeaks(colFrac, CONSERVATIVE_PEAK_THRESH);
    const rowPeaks: number[] = findPeriodicPeaks(rowFrac, CONSERVATIVE_PEAK_THRESH);

    if (colPeaks.length >= CONSERVATIVE_MIN_PEAKS && rowPeaks.length >= CONSERVATIVE_MIN_PEAKS) {
      const bbox: BoardBBox = {
        left: Math.round(colPeaks[0] * invScale),
        top: Math.round(rowPeaks[0] * invScale),
        right: Math.round(colPeaks[colPeaks.length - 1] * invScale),
        bottom: Math.round(rowPeaks[rowPeaks.length - 1] * invScale),
        isDark
      };
      const bw: number = bbox.right - bbox.left + 1;
      const bh: number = bbox.bottom - bbox.top + 1;
      if (bw < CONSERVATIVE_MIN_DIM || bh < CONSERVATIVE_MIN_DIM) { continue; }
      const aspect: number = bw / bh;
      if (aspect < CONSERVATIVE_MIN_ASPECT || aspect > CONSERVATIVE_MAX_ASPECT) { continue; }
      const areaRatio: number = (bw * bh) / (W * H);
      if (areaRatio > MAX_BOARD_AREA_RATIO) { continue; }
      return bbox;
    }
  }

  return null;
}

export function findBoardBBox(pixels: Uint8Array, width: number, height: number, bg: number): BoardBBox {
  SP.lastBboxDiag = '';
  // 确保灰度映射使用当前图像的通道背景缓存: toGrayArray 依赖 g_cachedChannelBg,
  // 该缓存仅由 bgColor() 刷新。若调用方未先调 bgColor（或缓存来自上一张图）,
  // 灰度会按默认 128 基准映射, 导致全图被误判为墨迹。此处重算对生产零影响
  // （生产调用方传入的 bg 本就来自同一张图的 bgColor, 结果一致）。
  bgColor(pixels, width, height);
  const isDark: boolean = bg < BG_DARK_THRESHOLD;
  const gray: Float32Array = toGrayArray(pixels, width, height);
  const imgArea: number = width * height;
  const addDiag = (s: string): void => { SP.lastBboxDiag += (SP.lastBboxDiag.length > 0 ? '\n' : '') + s; };

  const longRun: BoardBBox | null = findBoxLongRun(gray, width, height, isDark, bg);
  if (longRun !== null) {
    addDiag(`路径=longRun ✓ [${longRun.left},${longRun.top},${longRun.right},${longRun.bottom}]`);
    return longRun;
  }
  addDiag('longRun → null, trying primary');

  const isDegenerate = (b: BoardBBox): boolean => {
    return ((b.right - b.left) * (b.bottom - b.top)) > imgArea * MAX_BOARD_AREA_RATIO;
  };

  const primary: BoardBBox | null = findBBoxInRectGray(
    gray, width, height, bg, isDark, 0, 0, width, height, BBOX_PRIMARY_THRESH, BBOX_PRIMARY_MIN_FRAC
  );
  if (primary !== null && isValidBoardAspect(primary, width, height) && !isDegenerate(primary)) {
    addDiag(`路径=primary ✓ [${primary.left},${primary.top},${primary.right},${primary.bottom}]`);
    return primary;
  }
  if (primary !== null) {
    addDiag(`primary found but invalid aspect=${((primary.right - primary.left) / (primary.bottom - primary.top)).toFixed(2)} or degenerate`);
  } else {
    addDiag('primary → null');
  }

  for (const thresh of BBOX_RELAXED_THRESHOLDS) {
    const res: BoardBBox | null = findBBoxInRectGray(
      gray, width, height, bg, isDark, 0, 0, width, height, thresh, BBOX_RELAXED_MIN_FRAC
    );
    if (res !== null && isValidBoardAspect(res, width, height) && !isDegenerate(res)) {
      addDiag(`路径=relaxed(thresh=${thresh}) ✓ [${res.left},${res.top},${res.right},${res.bottom}]`);
      return res;
    }
  }
  addDiag('relaxed → no valid result, trying regions');

  const regions: number[][] = [];
  for (let i: number = 0; i < BBOX_REGIONS.length; i++) {
    const br: number[] = BBOX_REGIONS[i];
    regions.push([
      Math.floor(width * br[0]), Math.floor(height * br[1]),
      Math.floor(width * br[2]), Math.floor(height * br[3])
    ]);
  }
  if (height > width * PORTRAIT_ASPECT_THRESHOLD) {
    for (let i: number = 0; i < BBOX_PORTRAIT_REGIONS.length; i++) {
      const br: number[] = BBOX_PORTRAIT_REGIONS[i];
      regions.push([
        Math.floor(width * br[0]), Math.floor(height * br[1]),
        Math.floor(width * br[2]), Math.floor(height * br[3])
      ]);
    }
  }
  if (width > height * PORTRAIT_ASPECT_THRESHOLD) {
    for (let i: number = 0; i < BBOX_LANDSCAPE_REGIONS.length; i++) {
      const br: number[] = BBOX_LANDSCAPE_REGIONS[i];
      regions.push([
        Math.floor(width * br[0]), Math.floor(height * br[1]),
        Math.floor(width * br[2]), Math.floor(height * br[3])
      ]);
    }
  }
  let bestArea: number = 0;
  let bestBox: BoardBBox | null = null;
  let bestRegionIdx: number = -1;
  for (let ri: number = 0; ri < regions.length; ri++) {
    const r: number[] = regions[ri];
    for (const thresh of BBOX_REGION_THRESHOLDS) {
      const res: BoardBBox | null = findBBoxInRectGray(
        gray, width, height, bg, isDark,
        r[0], r[1], r[2], r[3], thresh, BBOX_REGION_MIN_FRAC
      );
      if (res !== null && isValidBoardAspect(res, width, height)) {
        const area: number = (res.right - res.left) * (res.bottom - res.top);
        if (area < width * height * MAX_BOARD_AREA_RATIO) {
          if (area > bestArea) { bestArea = area; bestBox = res; bestRegionIdx = ri; }
        }
        break;
      }
    }
  }
  if (bestBox !== null) {
    addDiag(`region[${bestRegionIdx}] bestBox [${bestBox.left},${bestBox.top},${bestBox.right},${bestBox.bottom}] area=${bestArea}`);
  }

  // Adaptive check BEFORE conservative/bestBox: when the image has no padding
  // around the board, adaptive often finds a bbox covering >=85% of the image.
  // If that bbox is >1.5x the bestBox area, it's likely a better result for
  // no-padding images where region search only finds a sub-region.
  const adaptive: BoardBBox | null = findBBoxAdaptive(gray, width, height, isDark);
  if (adaptive !== null) {
    const aArea: number = (adaptive.right - adaptive.left) * (adaptive.bottom - adaptive.top);
    if (aArea < imgArea * MAX_BOARD_AREA_RATIO) {
      addDiag(`路径=adaptive ✓ [${adaptive.left},${adaptive.top},${adaptive.right},${adaptive.bottom}]`);
      return adaptive;
    }
    if (aArea >= imgArea * 0.85 && isValidBoardAspect(adaptive, width, height)) {
      if (bestBox === null || aArea > bestArea * 1.5) {
        addDiag(`路径=adaptive(large-no-pad) ✓ [${adaptive.left},${adaptive.top},${adaptive.right},${adaptive.bottom}] aArea=${aArea} bestArea=${bestArea}`);
        return adaptive;
      }
    }
  }
  addDiag('adaptive → null or no fallback');

  const conservative: BoardBBox | null = findBBoxConservative(gray, width, height, isDark, bg);
  if (conservative !== null) {
    addDiag(`路径=conservative ✓ [${conservative.left},${conservative.top},${conservative.right},${conservative.bottom}]`);
    return conservative;
  }
  addDiag('conservative → null');

  if (bestBox !== null) {
    addDiag(`路径=region(bestBox) [${bestBox.left},${bestBox.top},${bestBox.right},${bestBox.bottom}]`);
    return bestBox;
  }

  addDiag('全部失败 → 全图退化bbox');
  return { left: 0, top: 0, right: width, bottom: height, isDark };
}
