import {
  BoardBBox, BoardCorners, MIN_BOARD_ASPECT, MAX_BOARD_ASPECT,
  MAX_BOARD_AREA_RATIO, MIN_BOARD_AREA_RATIO, HOUGH_EDGE_THRESH, HOUGH_THETA_STEPS,
  HOUGH_MAX_SAMPLES, HOUGH_MIN_VOTES_DIVISOR, HOUGH_NMS_RHO_DIVISOR, HOUGH_NMS_THETA_RADIUS,
  HOUGH_MAX_LINES, HOUGH_ANGLE_TOLERANCE, CORNER_MIN_LINES, CORNER_MAX_SIDE_LINES,
  CORNER_MIN_SIZE_FRAC, CORNER_MIN_DIAG_RATIO, CORNER_MAX_DIAG_RATIO, CORNER_CONFIDENCE_DIV,
  CORNER_OUT_OF_BOUNDS_FRAC, HOUGH_BOARD_MIN_HORIZ, HOUGH_BOARD_MIN_VERT
} from './SudokuPixelKernel';

export interface HoughLine {
  rho: number;
  theta: number;
  votes: number;
}


function houghLines(gray: Float32Array, W: number, H: number, isDark: boolean, bg: number): HoughLine[] {
  const edgeThresh: number = HOUGH_EDGE_THRESH;
  const dx: Float32Array = new Float32Array(W * H);
  const dy: Float32Array = new Float32Array(W * H);
  const mag: Float32Array = new Float32Array(W * H);
  for (let y: number = 1; y < H - 1; y++) {
    for (let x: number = 1; x < W - 1; x++) {
      const idx: number = y * W + x;
      const l: number = gray[idx - 1];
      const r: number = gray[idx + 1];
      const t: number = gray[idx - W];
      const b: number = gray[idx + W];
      dx[idx] = r - l;
      dy[idx] = b - t;
      mag[idx] = Math.abs(dx[idx]) + Math.abs(dy[idx]);
    }
  }
  const diagonal: number = Math.floor(Math.sqrt(W * W + H * H));
  const thetaSteps: number = HOUGH_THETA_STEPS;
  const accSize: number = (diagonal * 2 + 1) * thetaSteps;
  const acc: number[] = new Array<number>(accSize).fill(0);
  const cosLut: number[] = new Array<number>(thetaSteps);
  const sinLut: number[] = new Array<number>(thetaSteps);
  for (let t: number = 0; t < thetaSteps; t++) {
    const rad: number = t * Math.PI / thetaSteps;
    cosLut[t] = Math.cos(rad);
    sinLut[t] = Math.sin(rad);
  }
  const step: number = Math.max(1, Math.floor(W * H / HOUGH_MAX_SAMPLES));
  for (let y: number = 2; y < H - 2; y += step) {
    for (let x: number = 2; x < W - 2; x += step) {
      const idx: number = y * W + x;
      if (mag[idx] < edgeThresh) { continue; }
      for (let t: number = 0; t < thetaSteps; t++) {
        const rho: number = Math.round(x * cosLut[t] + y * sinLut[t]) + diagonal;
        if (rho >= 0 && rho <= diagonal * 2) {
          acc[rho * thetaSteps + t]++;
        }
      }
    }
  }
  const threshold: number = Math.max(8, Math.floor(Math.min(W, H) / HOUGH_MIN_VOTES_DIVISOR));
  const lines: HoughLine[] = [];
  const nmsRho: number = Math.max(5, Math.floor(diagonal / HOUGH_NMS_RHO_DIVISOR));
  for (let rho: number = 1; rho < diagonal * 2; rho++) {
    for (let t: number = 0; t < thetaSteps; t++) {
      const val: number = acc[rho * thetaSteps + t];
      if (val < threshold) { continue; }
      let isMax: boolean = true;
      for (let dr: number = -nmsRho; dr <= nmsRho && isMax; dr++) {
        for (let dt: number = -HOUGH_NMS_THETA_RADIUS; dt <= HOUGH_NMS_THETA_RADIUS && isMax; dt++) {
          if (dr === 0 && dt === 0) { continue; }
          const nr: number = rho + dr;
          const nt: number = (t + dt + thetaSteps) % thetaSteps;
          if (nr >= 0 && nr <= diagonal * 2) {
            if (acc[nr * thetaSteps + nt] > val) { isMax = false; }
          }
        }
      }
      if (isMax) {
        lines.push({ rho: rho - diagonal, theta: t * Math.PI / thetaSteps, votes: val });
      }
    }
  }
  lines.sort((a: HoughLine, b: HoughLine) => b.votes - a.votes);
  return lines.slice(0, Math.min(lines.length, HOUGH_MAX_LINES));
}

function lineIntersection(r1: number, t1: number, r2: number, t2: number): [number, number] | null {
  const c1: number = Math.cos(t1);
  const s1: number = Math.sin(t1);
  const c2: number = Math.cos(t2);
  const s2: number = Math.sin(t2);
  const det: number = c1 * s2 - c2 * s1;
  if (Math.abs(det) < 1e-8) { return null; }
  const x: number = (r1 * s2 - r2 * s1) / det;
  const y: number = (r2 * c1 - r1 * c2) / det;
  return [x, y];
}

function clusterLinesByAngle(lines: HoughLine[], targetAngle: number, tolerance: number): HoughLine[] {
  const result: HoughLine[] = [];
  for (const line of lines) {
    let angle: number = line.theta;
    let diff: number = Math.abs(angle - targetAngle);
    if (diff > Math.PI / 2) { diff = Math.PI - diff; }
    if (diff < tolerance) { result.push(line); }
  }
  return result;
}

export function detectBoardCorners(gray: Float32Array, W: number, H: number, isDark: boolean, bg: number): BoardCorners | null {
  const lines: HoughLine[] = houghLines(gray, W, H, isDark, bg);
  if (lines.length < CORNER_MIN_LINES) { return null; }
  const horizLines: HoughLine[] = clusterLinesByAngle(lines, Math.PI / 2, HOUGH_ANGLE_TOLERANCE);
  const vertLines: HoughLine[] = clusterLinesByAngle(lines, 0, HOUGH_ANGLE_TOLERANCE);
  if (horizLines.length < 2 || vertLines.length < 2) { return null; }
  const topLines: HoughLine[] = horizLines.slice(0, Math.min(horizLines.length, CORNER_MAX_SIDE_LINES));
  const bottomLines: HoughLine[] = horizLines.slice(Math.max(0, horizLines.length - CORNER_MAX_SIDE_LINES));
  const leftLines: HoughLine[] = vertLines.slice(0, Math.min(vertLines.length, CORNER_MAX_SIDE_LINES));
  const rightLines: HoughLine[] = vertLines.slice(Math.max(0, vertLines.length - CORNER_MAX_SIDE_LINES));
  const candidates: Array<[number, number]> = [];
  for (const h of topLines) {
    for (const v of leftLines) {
      const pt: [number, number] | null = lineIntersection(h.rho, h.theta, v.rho, v.theta);
      if (pt !== null && pt[0] >= -W * CORNER_OUT_OF_BOUNDS_FRAC && pt[0] < W * (1 + CORNER_OUT_OF_BOUNDS_FRAC) && pt[1] >= -H * CORNER_OUT_OF_BOUNDS_FRAC && pt[1] < H * (1 + CORNER_OUT_OF_BOUNDS_FRAC)) {
        candidates.push(pt);
      }
    }
  }
  if (candidates.length === 0) { return null; }
  let tlX: number = W; let tlY: number = H;
  for (const pt of candidates) {
    const d: number = pt[0] * pt[0] + pt[1] * pt[1];
    const cd: number = tlX * tlX + tlY * tlY;
    if (d < cd) { tlX = pt[0]; tlY = pt[1]; }
  }
  const trCandidates: Array<[number, number]> = [];
  for (const h of topLines) {
    for (const v of rightLines) {
      const pt: [number, number] | null = lineIntersection(h.rho, h.theta, v.rho, v.theta);
      if (pt !== null && pt[0] >= -W * CORNER_OUT_OF_BOUNDS_FRAC && pt[0] < W * (1 + CORNER_OUT_OF_BOUNDS_FRAC) && pt[1] >= -H * CORNER_OUT_OF_BOUNDS_FRAC && pt[1] < H * (1 + CORNER_OUT_OF_BOUNDS_FRAC)) {
        trCandidates.push(pt);
      }
    }
  }
  if (trCandidates.length === 0) { return null; }
  let trX: number = 0; let trY: number = H;
  for (const pt of trCandidates) {
    const d: number = (W - pt[0]) * (W - pt[0]) + pt[1] * pt[1];
    const cd: number = (W - trX) * (W - trX) + trY * trY;
    if (d < cd) { trX = pt[0]; trY = pt[1]; }
  }
  const brCandidates: Array<[number, number]> = [];
  for (const h of bottomLines) {
    for (const v of rightLines) {
      const pt: [number, number] | null = lineIntersection(h.rho, h.theta, v.rho, v.theta);
      if (pt !== null && pt[0] >= -W * CORNER_OUT_OF_BOUNDS_FRAC && pt[0] < W * (1 + CORNER_OUT_OF_BOUNDS_FRAC) && pt[1] >= -H * CORNER_OUT_OF_BOUNDS_FRAC && pt[1] < H * (1 + CORNER_OUT_OF_BOUNDS_FRAC)) {
        brCandidates.push(pt);
      }
    }
  }
  if (brCandidates.length === 0) { return null; }
  let brX: number = 0; let brY: number = 0;
  for (const pt of brCandidates) {
    const d: number = (W - pt[0]) * (W - pt[0]) + (H - pt[1]) * (H - pt[1]);
    const cd: number = (W - brX) * (W - brX) + (H - brY) * (H - brY);
    if (d < cd) { brX = pt[0]; brY = pt[1]; }
  }
  const blCandidates: Array<[number, number]> = [];
  for (const h of bottomLines) {
    for (const v of leftLines) {
      const pt: [number, number] | null = lineIntersection(h.rho, h.theta, v.rho, v.theta);
      if (pt !== null && pt[0] >= -W * CORNER_OUT_OF_BOUNDS_FRAC && pt[0] < W * (1 + CORNER_OUT_OF_BOUNDS_FRAC) && pt[1] >= -H * CORNER_OUT_OF_BOUNDS_FRAC && pt[1] < H * (1 + CORNER_OUT_OF_BOUNDS_FRAC)) {
        blCandidates.push(pt);
      }
    }
  }
  if (blCandidates.length === 0) { return null; }
  let blX: number = W; let blY: number = 0;
  for (const pt of blCandidates) {
    const d: number = pt[0] * pt[0] + (H - pt[1]) * (H - pt[1]);
    const cd: number = blX * blX + (H - blY) * (H - blY);
    if (d < cd) { blX = pt[0]; blY = pt[1]; }
  }
  const boardW: number = (trX - tlX + brX - blX) / 2;
  const boardH: number = (blY - tlY + brY - trY) / 2;
  if (boardW < W * CORNER_MIN_SIZE_FRAC || boardH < H * CORNER_MIN_SIZE_FRAC) { return null; }
  const aspect: number = boardW / boardH;
  if (aspect < MIN_BOARD_ASPECT || aspect > MAX_BOARD_ASPECT) { return null; }
  const area: number = boardW * boardH;
  if (area > W * H * MAX_BOARD_AREA_RATIO || area < W * H * MIN_BOARD_AREA_RATIO) { return null; }
  const diag1Sq: number = (trX - blX) * (trX - blX) + (trY - blY) * (trY - blY);
  const diag2Sq: number = (tlX - brX) * (tlX - brX) + (tlY - brY) * (tlY - brY);
  const diagRatio: number = Math.sqrt(diag1Sq) / (Math.sqrt(diag2Sq) + 0.01);
  if (diagRatio < CORNER_MIN_DIAG_RATIO || diagRatio > CORNER_MAX_DIAG_RATIO) { return null; }
  const confidence: number = Math.min(horizLines.length, vertLines.length) / CORNER_CONFIDENCE_DIV;
  return {
    topLeftX: tlX, topLeftY: tlY,
    topRightX: trX, topRightY: trY,
    bottomRightX: brX, bottomRightY: brY,
    bottomLeftX: blX, bottomLeftY: blY,
    isDark: isDark,
    confidence: confidence
  };
}

export function warpPerspectiveGray(
  gray: Float32Array, W: number, H: number,
  corners: BoardCorners, outSize: number, bgVal: number
): Float32Array {
  const out: Float32Array = new Float32Array(outSize * outSize);
  const srcX: number[] = [corners.topLeftX, corners.topRightX, corners.bottomRightX, corners.bottomLeftX];
  const srcY: number[] = [corners.topLeftY, corners.topRightY, corners.bottomRightY, corners.bottomLeftY];
  const dstX: number[] = [0, outSize - 1, outSize - 1, 0];
  const dstY: number[] = [0, 0, outSize - 1, outSize - 1];
  const A: number[][] = [];
  const bVec: number[] = [];
  for (let i: number = 0; i < 4; i++) {
    A.push([dstX[i], dstY[i], 1, 0, 0, 0, -srcX[i] * dstX[i], -srcX[i] * dstY[i]]);
    bVec.push(srcX[i]);
    A.push([0, 0, 0, dstX[i], dstY[i], 1, -srcY[i] * dstX[i], -srcY[i] * dstY[i]]);
    bVec.push(srcY[i]);
  }
  const n: number = 8;
  for (let col: number = 0; col < n; col++) {
    let maxRow: number = col;
    let maxVal: number = Math.abs(A[col][col]);
    for (let row: number = col + 1; row < n; row++) {
      if (Math.abs(A[row][col]) > maxVal) { maxVal = Math.abs(A[row][col]); maxRow = row; }
    }
    const tmpA: number[] = A[col]; A[col] = A[maxRow]; A[maxRow] = tmpA;
    const tmpB: number = bVec[col]; bVec[col] = bVec[maxRow]; bVec[maxRow] = tmpB;
    const pivot: number = A[col][col];
    if (Math.abs(pivot) < 1e-12) { break; }
    for (let j: number = col; j < n; j++) { A[col][j] /= pivot; }
    bVec[col] /= pivot;
    for (let row: number = 0; row < n; row++) {
      if (row === col) { continue; }
      const factor: number = A[row][col];
      for (let j: number = col; j < n; j++) { A[row][j] -= factor * A[col][j]; }
      bVec[row] -= factor * bVec[col];
    }
  }
  const h: number[] = bVec;
  for (let oy: number = 0; oy < outSize; oy++) {
    for (let ox: number = 0; ox < outSize; ox++) {
      const denom: number = h[6] * ox + h[7] * oy + 1;
      if (Math.abs(denom) < 1e-8) { out[oy * outSize + ox] = 128; continue; }
      const sx: number = (h[0] * ox + h[1] * oy + h[2]) / denom;
      const sy: number = (h[3] * ox + h[4] * oy + h[5]) / denom;
      const ix: number = Math.floor(sx);
      const iy: number = Math.floor(sy);
      const fx: number = sx - ix;
      const fy: number = sy - iy;
      if (ix >= 0 && ix + 1 < W && iy >= 0 && iy + 1 < H) {
        const v00: number = gray[iy * W + ix];
        const v10: number = gray[iy * W + ix + 1];
        const v01: number = gray[(iy + 1) * W + ix];
        const v11: number = gray[(iy + 1) * W + ix + 1];
        out[oy * outSize + ox] = v00 * (1 - fx) * (1 - fy) + v10 * fx * (1 - fy) + v01 * (1 - fx) * fy + v11 * fx * fy;
      } else {
        const cx: number = Math.round(sx);
        const cy: number = Math.round(sy);
        if (cx >= 0 && cx < W && cy >= 0 && cy < H) {
          out[oy * outSize + ox] = gray[cy * W + cx];
        } else {
          out[oy * outSize + ox] = bgVal;
        }
      }
    }
  }
  return out;
}

function findBoardByHoughLines(gray: Float32Array, W: number, H: number, isDark: boolean, bg: number): BoardBBox | null {
  const lines: HoughLine[] = houghLines(gray, W, H, isDark, bg);
  if (lines.length < HOUGH_BOARD_MIN_HORIZ) { return null; }

  const horizLines: HoughLine[] = clusterLinesByAngle(lines, Math.PI / 2, HOUGH_ANGLE_TOLERANCE);
  const vertLines: HoughLine[] = clusterLinesByAngle(lines, 0, HOUGH_ANGLE_TOLERANCE);
  if (horizLines.length < HOUGH_BOARD_MIN_HORIZ || vertLines.length < HOUGH_BOARD_MIN_VERT) { return null; }

  horizLines.sort((a: HoughLine, b: HoughLine) => a.rho - b.rho);
  vertLines.sort((a: HoughLine, b: HoughLine) => a.rho - b.rho);

  const clusterEquidistant = (sorted: HoughLine[], targetCount: number): HoughLine[] | null => {
    if (sorted.length < targetCount) { return null; }
    let bestSet: HoughLine[] = [];
    let bestScore: number = 0;
    const minGap: number = Math.max(3, Math.floor(Math.min(W, H) / 25));
    for (let startIdx: number = 0; startIdx < sorted.length; startIdx++) {
      const selected: HoughLine[] = [sorted[startIdx]];
      let lastRho: number = sorted[startIdx].rho;
      for (let i: number = startIdx + 1; i < sorted.length; i++) {
        const gap: number = sorted[i].rho - lastRho;
        if (selected.length === 1) {
          if (gap < minGap) { continue; }
          selected.push(sorted[i]);
          lastRho = sorted[i].rho;
        } else {
          const avgGap: number = (selected[selected.length - 1].rho - selected[0].rho) / (selected.length - 1);
          if (gap >= avgGap * 0.6 && gap <= avgGap * 1.5) {
            selected.push(sorted[i]);
            lastRho = sorted[i].rho;
          }
        }
        if (selected.length >= targetCount) { break; }
      }
      if (selected.length >= targetCount) {
        const span: number = selected[selected.length - 1].rho - selected[0].rho;
        const avgGap2: number = span / (selected.length - 1);
        let devSum: number = 0;
        for (let j: number = 1; j < selected.length; j++) {
          devSum += Math.abs((selected[j].rho - selected[j - 1].rho) - avgGap2);
        }
        const score: number = selected.length * 100 - devSum / avgGap2;
        if (score > bestScore) {
          bestScore = score;
          bestSet = selected;
        }
      }
    }
    return bestSet.length >= targetCount ? bestSet : null;
  };

  const hSet: HoughLine[] | null = clusterEquidistant(horizLines, 10);
  const vSet: HoughLine[] | null = clusterEquidistant(vertLines, 10);

  let topRho: number = 0;
  let bottomRho: number = 0;
  let leftRho: number = 0;
  let rightRho: number = 0;

  if (hSet !== null && hSet.length >= 10) {
    topRho = hSet[0].rho;
    bottomRho = hSet[hSet.length - 1].rho;
  } else if (horizLines.length >= 2) {
    topRho = horizLines[0].rho;
    bottomRho = horizLines[horizLines.length - 1].rho;
  } else {
    return null;
  }

  if (vSet !== null && vSet.length >= 10) {
    leftRho = vSet[0].rho;
    rightRho = vSet[vSet.length - 1].rho;
  } else if (vertLines.length >= 2) {
    leftRho = vertLines[0].rho;
    rightRho = vertLines[vertLines.length - 1].rho;
  } else {
    return null;
  }

  let minX: number = W;
  let maxX: number = 0;
  let minY: number = H;
  let maxY: number = 0;

  const corners: Array<[number, number]> = [];
  const hBounds: HoughLine[] = [hSet !== null && hSet.length >= 2 ? hSet[0] : horizLines[0],
    hSet !== null && hSet.length >= 2 ? hSet[hSet.length - 1] : horizLines[horizLines.length - 1]];
  const vBounds: HoughLine[] = [vSet !== null && vSet.length >= 2 ? vSet[0] : vertLines[0],
    vSet !== null && vSet.length >= 2 ? vSet[vSet.length - 1] : vertLines[vertLines.length - 1]];

  for (const h of hBounds) {
    for (const v of vBounds) {
      const pt: [number, number] | null = lineIntersection(h.rho, h.theta, v.rho, v.theta);
      if (pt !== null && pt[0] >= 0 && pt[0] < W && pt[1] >= 0 && pt[1] < H) {
        corners.push(pt);
        if (pt[0] < minX) { minX = pt[0]; }
        if (pt[0] > maxX) { maxX = pt[0]; }
        if (pt[1] < minY) { minY = pt[1]; }
        if (pt[1] > maxY) { maxY = pt[1]; }
      }
    }
  }

  if (corners.length < 3) { return null; }
  const bw: number = maxX - minX;
  const bh: number = maxY - minY;
  if (bw < 20 || bh < 20) { return null; }
  const aspect: number = bw / bh;
  if (aspect < 0.3 || aspect > 3.0) { return null; }
  const areaRatio: number = (bw * bh) / (W * H);
  if (areaRatio > 0.88 || areaRatio < 0.02) { return null; }

  return { left: Math.floor(minX), top: Math.floor(minY), right: Math.floor(maxX), bottom: Math.floor(maxY), isDark };
}
