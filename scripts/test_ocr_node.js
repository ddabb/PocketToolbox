'use strict';
const fs = require('fs');
const path = require('path');
const { createCanvas, loadImage } = require('canvas');

const SIG_ROWS = 28;
const SIG_COLS = 20;
const SIG_LEN = SIG_ROWS * SIG_COLS;
const INK_THRESH = 50;
const GRID_LINE_GRAY_DIFF = INK_THRESH * 0.6;
const MIN_INK_RATIO = 0.25;
const MAX_INK_RATIO = 0.75;
const MIN_INK_COUNT = Math.floor(SIG_LEN * MIN_INK_RATIO);
const MAX_INK_COUNT = Math.floor(SIG_LEN * MAX_INK_RATIO);
const MIN_INK_COUNT_DIGIT1 = Math.floor(SIG_LEN * 0.12);
const THIN1_MIN_INK_COUNT = Math.floor(SIG_LEN * 0.06);
const MIN_DIGIT_SCORE = Math.floor(SIG_LEN * 0.65);
const LOW_INK_FALLBACK_MIN_SCORE = Math.floor(SIG_LEN * 0.60);
const LOW_INK_FALLBACK_MIN_RECALL = 0.35;
const LOW_INK_THRESH_RETRY = Math.floor(INK_THRESH / 2);
const SAUVOLA_K = 0.2;
const SAUVOLA_R = 128;
const SAUVOLA_MIN_DIM = 4;
const CELL_MARGIN_RATIO = 0.08;
const MIN_CELL_INK_RATIO = 0.025;
const OTSU_BG_MIN_DIFF = 12;
const OTSU_MIN_PIXELS = 30;
const BG_SAMPLE_COUNT = 20000;
const BG_DARK_THRESHOLD = 128;
const MIN_BOARD_DIM = 10;
const MIN_BOARD_ASPECT = 0.3;
const MAX_BOARD_ASPECT = 3.0;
const MAX_BOARD_AREA_RATIO = 0.88;
const MIN_BOARD_AREA_RATIO = 0.02;
const MIN_BOARD_SIZE_FRAC = 0.1;
const ADAPTIVE_CONTRASTS = [8, 12, 5];
const ADAPTIVE_THRESHOLDS = [0.3, 0.25, 0.20, 0.15];
const ADAPTIVE_PEAK_THRESH = 0.10;
const CONSERVATIVE_DELTAS = [90, 80, 70, 60, 50, 40];
const CONSERVATIVE_PEAK_THRESH = 0.05;
const CONSERVATIVE_MIN_PEAKS = 7;
const CONSERVATIVE_MIN_ASPECT = 0.45;
const CONSERVATIVE_MAX_ASPECT = 2.2;
const CONSERVATIVE_MIN_DIM = 20;
const MINRUN_ABS_MIN = 20;
const MINRUN_FRAC = 0.10;
const LONGRUN_TIGHTER_OFFSETS = [40, 25, 12];
const LONGRUN_MIN_PIXELS = 50;
const LONGRUN_MAX_RUN_COUNT_FRAC = 0.50;
const LONGRUN_MIN_ASPECT = 0.6;
const LONGRUN_MAX_ASPECT = 2.0;
const HOUGH_EDGE_THRESH = 30;
const HOUGH_THETA_STEPS = 180;
const HOUGH_MAX_SAMPLES = 50000;
const HOUGH_MIN_VOTES_DIVISOR = 50;
const HOUGH_NMS_RHO_DIVISOR = 40;
const HOUGH_NMS_THETA_RADIUS = 3;
const HOUGH_MAX_LINES = 60;
const HOUGH_ANGLE_TOLERANCE = Math.PI / 18;
const CORNER_MIN_LINES = 8;
const CORNER_MAX_SIDE_LINES = 5;
const CORNER_MIN_SIZE_FRAC = 0.08;
const CORNER_MIN_DIAG_RATIO = 0.5;
const CORNER_MAX_DIAG_RATIO = 2.0;
const CORNER_CONFIDENCE_DIV = 10;
const CORNER_OUT_OF_BOUNDS_FRAC = 0.1;
const CENTERING_MARGIN = 0.15;
const CENTERING_MIN_INK = 5;
const CENTERING_MAX_OFFSET = 0.25;
const HOUGH_BOARD_MIN_HORIZ = 4;
const HOUGH_BOARD_MIN_VERT = 4;
const PERIODIC_MIN_PEAKS = 5;
const GRID_LINE_SMOOTH_DIV = 60;
const GRID_LINE_MIN_MAX_FRAC = 0.05;
const GRID_LINE_INK_EXIST_THRESH = 0.15;
const GRID_LINE_PEAK_THRESH_FRAC = 0.3;
const GRID_LINE_SPACING_TOLERANCE = 0.3;
const DISAMBIG_HOLE_WEIGHT = 2;
const DISAMBIG_CENTROID_WEIGHT = 1;
const DISAMBIG_TOP_RATIO_WEIGHT = 2;
const DISAMBIG_HOG_WEIGHT = 1;
const DISAMBIG_SW_WEIGHT = 1;
const DISAMBIG_SCORE_WEIGHT = 4;
const FIX_MAX_ROUNDS = 5;

const DISAMBIG_SCORE_GAP_SKIP = 80;
const TEMPLATE_MISMATCH_PENALTY = 0.5;
const TEMPLATE_F1_WEIGHT = 200;
const BBOX_PRIMARY_THRESH = 0.3;
const BBOX_PRIMARY_MIN_FRAC = 0.3;
const BBOX_RELAXED_THRESHOLDS = [0.20, 0.15];
const BBOX_RELAXED_MIN_FRAC = 0.15;
const BBOX_REGION_THRESHOLDS = [0.30, 0.20, 0.15];
const BBOX_REGION_MIN_FRAC = 0.10;
const BBOX_REGIONS = [[0,0,0.6,0.6],[0.4,0,1.0,0.6],[0,0.4,0.6,1.0],[0.4,0.4,1.0,1.0],[0.15,0.15,0.85,0.85]];
const BBOX_PORTRAIT_REGIONS = [[0,0,1.0,0.5],[0,0.1,1.0,0.6],[0.1,0,0.9,0.45]];
const BBOX_LANDSCAPE_REGIONS = [[0,0,0.5,1.0],[0.1,0,0.6,1.0],[0,0.1,0.45,0.9]];
const PORTRAIT_ASPECT_THRESHOLD = 1.3;
const GRID_LINE_RATIO = 0.80;
const HOLE_SECOND_RATIO = 0.6;
const PIXEL_MAX_DIM = 1600;
const EMPTY_FILL_PIXEL_CONF = 0.55;
const EMPTY_FILL_PIXEL_CONF_NO_RAW_DIGITS = 0.72;
const CONFUSABLE_DIGITS = [5, 6, 7, 9];
const CONFUSABLE_PIXEL_OVERRIDE_CONF = 0.6;
const EXISTING_PIXEL_ONLY_OVERRIDE_CONF = 0.72;
const STABLE_PIXEL_ONLY_OVERRIDE_CONF = 0.66;

let g_cachedChannelBg = null;
let g_templates = [];
let g_holeRows = [];
let g_loaded = false;
let g_gridLineCropTop = new Array(81).fill(0);
let g_gridLineCropBot = new Array(81).fill(0);
let g_gridLineCropLeft = new Array(81).fill(0);
let g_gridLineCropRight = new Array(81).fill(0);
let g_gridLineDetected = false;
let g_preciseGridDetected = false;
let g_gridLineX = new Array(10).fill(0);
let g_gridLineY = new Array(10).fill(0);
let g_lastConfidence = 0;
let g_lastBboxDiag = '';
let g_lastPixelDiag = '';
let g_lastRawInkRatio = 0;
let g_lastSigArray = null;

function resetLastPixelDiag() { g_lastPixelDiag = ''; g_lastRawInkRatio = 0; }
function resetGridLineCrop() { g_gridLineCropTop = new Array(81).fill(0); g_gridLineCropBot = new Array(81).fill(0); g_gridLineCropLeft = new Array(81).fill(0); g_gridLineCropRight = new Array(81).fill(0); g_gridLineDetected = false; }
function getLastConfidence() { return g_lastConfidence; }
function getLastRawInkRatio() { return g_lastRawInkRatio; }
function clamp255(v) { return v < 0 ? 0 : (v > 255 ? 255 : v); }

function bgColor(pixels, width, height) {
  const histR = new Array(256).fill(0), histG = new Array(256).fill(0), histB = new Array(256).fill(0);
  const total = width * height, step = Math.max(1, Math.floor(total / BG_SAMPLE_COUNT));
  for (let i = 0; i < total; i += step) { const off = i * 4; histR[Math.max(0, Math.min(255, pixels[off]))]++; histG[Math.max(0, Math.min(255, pixels[off+1]))]++; histB[Math.max(0, Math.min(255, pixels[off+2]))]++; }
  let modeR = 0, maxR = 0, modeG = 0, maxG = 0, modeB = 0, maxB = 0;
  for (let i = 0; i < 256; i++) { if (histR[i] > maxR) { maxR = histR[i]; modeR = i; } if (histG[i] > maxG) { maxG = histG[i]; modeG = i; } if (histB[i] > maxB) { maxB = histB[i]; modeB = i; } }
  g_cachedChannelBg = { bgR: modeR, bgG: modeG, bgB: modeB };
  return 255;
}

function toGrayArray(pixels, width, height) {
  let bgR = 128, bgG = 128, bgB = 128;
  if (g_cachedChannelBg !== null) { bgR = g_cachedChannelBg.bgR; bgG = g_cachedChannelBg.bgG; bgB = g_cachedChannelBg.bgB; }
  const gray = new Float32Array(width * height);
  for (let i = 0; i < width * height; i++) { const off = i * 4; const dr = pixels[off] - bgR, dg = pixels[off+1] - bgG, db = pixels[off+2] - bgB; gray[i] = clamp255(255 - Math.max(Math.abs(dr), Math.abs(dg), Math.abs(db))); }
  return gray;
}

function isInkPixel(g, bg, isDark) { return isDark ? g > bg + INK_THRESH : g < bg - INK_THRESH; }
function grayInkPixel(g, bg, isDark, thresh) { return isDark ? g > bg + thresh : g < bg - thresh; }
function countInk(sig) { let c = 0; for (let i = 0; i < sig.length; i++) if (sig[i] === 1) c++; return c; }

function otsuThreshold(hist, total) {
  let sumAll = 0; for (let i = 0; i < 256; i++) sumAll += i * hist[i];
  let sumBg = 0, wBg = 0, maxVar = -1, threshold = 128;
  for (let t = 0; t < 256; t++) { wBg += hist[t]; if (wBg === 0) continue; const wFg = total - wBg; if (wFg === 0) break; sumBg += t * hist[t]; const mBg = sumBg / wBg, mFg = (sumAll - sumBg) / wFg; const diff = mBg - mFg; const v = wBg * wFg * diff * diff; if (v > maxVar) { maxVar = v; threshold = t; } }
  return threshold;
}

function sauvolaThreshold(gray, width, height, cx0, cy0, cw, ch, isDark) {
  const halfWin = Math.max(2, Math.floor(Math.min(cw, ch) / 4));
  const x0 = Math.floor(cx0), y0 = Math.floor(cy0), x1 = Math.floor(cx0 + cw), y1 = Math.floor(cy0 + ch);
  const w = x1 - x0, h = y1 - y0;
  if (w < SAUVOLA_MIN_DIM || h < SAUVOLA_MIN_DIM) return null;
  const sumBuf = new Float32Array(w * h), sqBuf = new Float32Array(w * h);
  for (let ly = 0; ly < h; ly++) { const sy = y0 + ly; if (sy < 0 || sy >= height) continue; let rowSum = 0, rowSq = 0; for (let lx = 0; lx < w; lx++) { const sx = x0 + lx; if (sx < 0 || sx >= width) continue; const v = gray[sy * width + sx]; rowSum += v; rowSq += v * v; sumBuf[ly * w + lx] = rowSum; sqBuf[ly * w + lx] = rowSq; } }
  const out = new Float32Array(w * h);
  for (let ly = 0; ly < h; ly++) for (let lx = 0; lx < w; lx++) {
    const top = Math.max(0, ly - halfWin), bot = Math.min(h - 1, ly + halfWin), left = Math.max(0, lx - halfWin), right = Math.min(w - 1, lx + halfWin);
    const cnt = (bot - top + 1) * (right - left + 1); let s = 0, sq = 0;
    for (let ry = top; ry <= bot; ry++) { s += sumBuf[ry * w + right] - (left > 0 ? sumBuf[ry * w + left - 1] : 0); sq += sqBuf[ry * w + right] - (left > 0 ? sqBuf[ry * w + left - 1] : 0); }
    const mean = s / cnt, variance = sq / cnt - mean * mean, std = Math.sqrt(Math.max(0, variance));
    const t = mean * (1 + SAUVOLA_K * (std / SAUVOLA_R - 1));
    out[ly * w + lx] = isDark ? (gray[(y0 + ly) * width + (x0 + lx)] > t ? 1 : 0) : (gray[(y0 + ly) * width + (x0 + lx)] < t ? 1 : 0);
  }
  return out;
}

function boxBlur(gray, W, H, radius) {
  const out = new Float32Array(W * H), tmp = new Float32Array(W * H), k = 2 * radius + 1;
  for (let y = 0; y < H; y++) { let sum = 0; for (let x = 0; x < k; x++) sum += gray[y * W + Math.min(x, W - 1)]; for (let x = 0; x < W; x++) { tmp[y * W + x] = sum / k; sum -= gray[y * W + Math.max(0, Math.min(W - 1, x - radius))]; sum += gray[y * W + Math.max(0, Math.min(W - 1, x + radius + 1))]; } }
  for (let x = 0; x < W; x++) { let sum = 0; for (let y = 0; y < k; y++) sum += tmp[Math.min(y, H - 1) * W + x]; for (let y = 0; y < H; y++) { out[y * W + x] = sum / k; sum -= tmp[Math.max(0, Math.min(H - 1, y - radius)) * W + x]; sum += tmp[Math.max(0, Math.min(H - 1, y + radius + 1)) * W + x]; } }
  return out;
}
function dilate3x3(b, W, H) { const o = new Uint8Array(W*H); for (let y=0;y<H;y++) for (let x=0;x<W;x++) { let m=0; for (let ny=Math.max(0,y-1);ny<=Math.min(H-1,y+1);ny++) for (let nx=Math.max(0,x-1);nx<=Math.min(W-1,x+1);nx++) if (b[ny*W+nx]>m) m=b[ny*W+nx]; o[y*W+x]=m; } return o; }
function erode3x3(b, W, H) { const o = new Uint8Array(W*H); for (let y=0;y<H;y++) for (let x=0;x<W;x++) { let m=1; for (let ny=Math.max(0,y-1);ny<=Math.min(H-1,y+1);ny++) for (let nx=Math.max(0,x-1);nx<=Math.min(W-1,x+1);nx++) if (b[ny*W+nx]<m) m=b[ny*W+nx]; o[y*W+x]=m; } return o; }
function morphOpen3x3(b, W, H) { return dilate3x3(erode3x3(b, W, H), W, H); }

function computeProjectionsGray(gray, W, H, bg, isDark, thresh, rx0, ry0, rx1, ry1, step) {
  const rw = rx1 - rx0, rh = ry1 - ry0, colInk = new Array(rw).fill(0), rowInk = new Array(rh).fill(0);
  for (let x = 0; x < rw; x++) { let c = 0; for (let y = 0; y < rh; y += step) if (grayInkPixel(gray[(y+ry0)*W+(x+rx0)], bg, isDark, thresh)) c++; colInk[x] = c; }
  for (let y = 0; y < rh; y++) { let c = 0; for (let x = 0; x < rw; x += step) if (grayInkPixel(gray[(y+ry0)*W+(x+rx0)], bg, isDark, thresh)) c++; rowInk[y] = c; }
  return { colInk, rowInk, rw, rh };
}

function findBBoxFromProjections(colInk, rowInk, rw, rh, rx0, ry0, threshold, minFrac, sampleStep, isDark) {
  let minX = rw, maxX = 0, minY = rh, maxY = 0, found = false;
  for (let x = 0; x < rw; x++) if (colInk[x] / (rh / sampleStep) > threshold) { if (x < minX) minX = x; if (x > maxX) maxX = x; found = true; }
  for (let y = 0; y < rh; y++) if (rowInk[y] / (rw / sampleStep) > threshold) { if (y < minY) minY = y; if (y > maxY) maxY = y; found = true; }
  if (!found || maxX - minX < rw * minFrac || maxY - minY < rh * minFrac) return null;
  const bw = maxX - minX + 1, bh = maxY - minY + 1;
  if (bw < MIN_BOARD_DIM || bh < MIN_BOARD_DIM) return null;
  return { left: minX + rx0, top: minY + ry0, right: maxX + rx0, bottom: maxY + ry0, isDark };
}

function findBBoxInRectGray(gray, W, H, bg, isDark, rx0, ry0, rx1, ry1, threshold, minFrac) {
  const rw = rx1 - rx0, rh = ry1 - ry0;
  if (rw < MIN_BOARD_DIM || rh < MIN_BOARD_DIM) return null;
  const proj = computeProjectionsGray(gray, W, H, bg, isDark, INK_THRESH, rx0, ry0, rx1, ry1, 2);
  return findBBoxFromProjections(proj.colInk, proj.rowInk, proj.rw, proj.rh, rx0, ry0, threshold, minFrac, 2, isDark);
}

function isValidBoardAspect(bbox, W, H) {
  const bw = bbox.right - bbox.left, bh = bbox.bottom - bbox.top;
  if (bw < MIN_BOARD_DIM || bh < MIN_BOARD_DIM) return false;
  const a = bw / bh; if (a < MIN_BOARD_ASPECT || a > MAX_BOARD_ASPECT) return false;
  return bw >= W * MIN_BOARD_SIZE_FRAC && bh >= H * MIN_BOARD_SIZE_FRAC;
}

function findPeriodicPeaks(frac, threshold) {
  const peaks = [];
  for (let i = 0; i < frac.length; i++) { if (frac[i] > threshold) { let end = i; while (end + 1 < frac.length && frac[end+1] > threshold) end++; peaks.push(Math.floor((i+end)/2)); i = end; } }
  if (peaks.length < PERIODIC_MIN_PEAKS) return peaks;
  let bestSpacing = 0, bestConf = 0;
  const minSp = Math.max(3, Math.floor(frac.length / 15)), maxSp = Math.floor(frac.length / 5);
  for (let sp = minSp; sp <= maxSp; sp++) { let count = 0, sumDiff = 0, lastPeak = -sp * 2; for (const p of peaks) { const diff = p - lastPeak; if (diff >= sp*0.7 && diff <= sp*1.3) { count++; sumDiff += Math.abs(diff-sp); lastPeak = p; } else if (diff > sp*1.3) lastPeak = p; } if (count >= PERIODIC_MIN_PEAKS) { const avgDev = count > 0 ? sumDiff/count/sp : 1; const conf = count - avgDev * 2; if (conf > bestConf) { bestConf = conf; bestSpacing = sp; } } }
  if (bestSpacing > 0) { const selected = []; let lastPeak = -bestSpacing * 2; for (const p of peaks) { const diff = p - lastPeak; if (diff >= bestSpacing*0.7 && diff <= bestSpacing*1.3) { selected.push(p); lastPeak = p; } else if (diff > bestSpacing*1.3) { selected.length = 0; selected.push(p); lastPeak = p; } } if (selected.length >= PERIODIC_MIN_PEAKS) return selected; }
  let bestStart = 0, bestCount = 0;
  for (let i = 0; i < peaks.length - 1; i++) { const sp = peaks[i+1] - peaks[i]; if (sp < 3) continue; let count = 2, lastPos = peaks[i+1]; for (let j = i+2; j < peaks.length; j++) if (peaks[j]-lastPos <= sp*1.3 && peaks[j]-lastPos >= sp*0.7) { count++; lastPos = peaks[j]; } if (count > bestCount) { bestCount = count; bestStart = i; } }
  if (bestCount >= PERIODIC_MIN_PEAKS) return peaks.slice(bestStart, bestStart + bestCount);
  return peaks;
}

function findBBoxAdaptive(gray, W, H, isDark) {
  const winR = Math.max(5, Math.floor(Math.min(W, H) / 25)), blurred = boxBlur(gray, W, H, winR);
  for (const C of ADAPTIVE_CONTRASTS) {
    let binary = new Uint8Array(W * H); for (let i = 0; i < W*H; i++) binary[i] = isDark ? (gray[i] > blurred[i]+C ? 1 : 0) : (gray[i] < blurred[i]-C ? 1 : 0);
    binary = morphOpen3x3(binary, W, H); binary = dilate3x3(dilate3x3(binary, W, H), W, H);
    const colInk = new Array(W).fill(0), rowInk = new Array(H).fill(0);
    for (let x = 0; x < W; x++) { let c = 0; for (let y = 0; y < H; y += 2) if (binary[y*W+x]===1) c++; colInk[x] = c; }
    for (let y = 0; y < H; y++) { let c = 0; for (let x = 0; x < W; x += 2) if (binary[y*W+x]===1) c++; rowInk[y] = c; }
    const colFrac = colInk.map(c => c/(H/2)), rowFrac = rowInk.map(c => c/(W/2));
    for (const thresh of ADAPTIVE_THRESHOLDS) { let minX=W, maxX=0, minY=H, maxY=0, found=false; for (let x=0;x<W;x++) if (colFrac[x]>thresh) { if (x<minX) minX=x; if (x>maxX) maxX=x; found=true; } for (let y=0;y<H;y++) if (rowFrac[y]>thresh) { if (y<minY) minY=y; if (y>maxY) maxY=y; found=true; } if (found) { const bbox = {left:minX,top:minY,right:maxX,bottom:maxY,isDark}; if (isValidBoardAspect(bbox,W,H) && maxX-minX>=W*MIN_BOARD_SIZE_FRAC && maxY-minY>=H*MIN_BOARD_SIZE_FRAC) return bbox; } }
    const colPeaks = findPeriodicPeaks(colFrac, ADAPTIVE_PEAK_THRESH), rowPeaks = findPeriodicPeaks(rowFrac, ADAPTIVE_PEAK_THRESH);
    if (colPeaks.length >= PERIODIC_MIN_PEAKS && rowPeaks.length >= PERIODIC_MIN_PEAKS) { const bbox = {left:colPeaks[0],top:rowPeaks[0],right:colPeaks[colPeaks.length-1],bottom:rowPeaks[rowPeaks.length-1],isDark}; if (isValidBoardAspect(bbox,W,H)) return bbox; }
  }
  return null;
}

function findBBoxConservative(gray, W, H, isDark, bg) {
  for (const delta of CONSERVATIVE_DELTAS) {
    const thr = isDark ? bg + delta : bg - delta; const binary = new Uint8Array(W*H); for (let i=0;i<W*H;i++) binary[i] = isDark ? (gray[i]>thr?1:0) : (gray[i]<thr?1:0);
    const colInk = new Array(W).fill(0), rowInk = new Array(H).fill(0);
    for (let x=0;x<W;x++) { let c=0; for (let y=0;y<H;y+=2) if (binary[y*W+x]===1) c++; colInk[x]=c; }
    for (let y=0;y<H;y++) { let c=0; for (let x=0;x<W;x+=2) if (binary[y*W+x]===1) c++; rowInk[y]=c; }
    const colFrac = colInk.map(c=>c/(H/2)), rowFrac = rowInk.map(c=>c/(W/2));
    const colPeaks = findPeriodicPeaks(colFrac, CONSERVATIVE_PEAK_THRESH), rowPeaks = findPeriodicPeaks(rowFrac, CONSERVATIVE_PEAK_THRESH);
    if (colPeaks.length >= CONSERVATIVE_MIN_PEAKS && rowPeaks.length >= CONSERVATIVE_MIN_PEAKS) {
      const bbox = {left:colPeaks[0],top:rowPeaks[0],right:colPeaks[colPeaks.length-1],bottom:rowPeaks[rowPeaks.length-1],isDark};
      const bw = bbox.right-bbox.left+1, bh = bbox.bottom-bbox.top+1;
      if (bw<CONSERVATIVE_MIN_DIM||bh<CONSERVATIVE_MIN_DIM) continue; const a=bw/bh; if (a<CONSERVATIVE_MIN_ASPECT||a>CONSERVATIVE_MAX_ASPECT) continue;
      if ((bw*bh)/(W*H) > MAX_BOARD_AREA_RATIO) continue; return bbox;
    }
  }
  return null;
}

function findBoxLongRunWithThresh(gray, W, H, isDark, absThresh) {
  const ink = new Uint8Array(W*H); for (let i=0;i<W*H;i++) ink[i] = isDark ? (gray[i]>absThresh?1:0) : (gray[i]<absThresh?1:0);
  const keep = new Uint8Array(W*H); const MINRUN = Math.max(MINRUN_ABS_MIN, Math.floor(Math.min(W,H)*MINRUN_FRAC));
  for (let y=0;y<H;y++) { let run=0,start=0; for (let x=0;x<=W;x++) { if (x<W&&ink[y*W+x]===1) { if (run===0) start=x; run++; } else { if (run>=MINRUN&&start>0&&x<W) for (let xx=start;xx<x;xx++) keep[y*W+xx]=1; run=0; } } }
  for (let x=0;x<W;x++) { let run=0,start=0; for (let y=0;y<=H;y++) { if (y<H&&ink[y*W+x]===1) { if (run===0) start=y; run++; } else { if (run>=MINRUN&&start>0&&y<H) for (let yy=start;yy<y;yy++) keep[yy*W+x]=1; run=0; } } }
  let minX=W,maxX=0,minY=H,maxY=0,n=0;
  for (let y=0;y<H;y++) for (let x=0;x<W;x++) if (keep[y*W+x]===1) { n++; if (x<minX) minX=x; if (x>maxX) maxX=x; if (y<minY) minY=y; if (y>maxY) maxY=y; }
  if (n<LONGRUN_MIN_PIXELS) return null;
  let hRC=0; for (let y=0;y<H;y++) { let r=0; for (let x=0;x<=W;x++) { if (x<W&&ink[y*W+x]===1) r++; else { if (r>=MINRUN) hRC++; r=0; } } }
  let vRC=0; for (let x=0;x<W;x++) { let r=0; for (let y=0;y<=H;y++) { if (y<H&&ink[y*W+x]===1) r++; else { if (r>=MINRUN) vRC++; r=0; } } }
  if (hRC>H*LONGRUN_MAX_RUN_COUNT_FRAC||vRC>W*LONGRUN_MAX_RUN_COUNT_FRAC) return null;
  const bw=maxX-minX+1, bh=maxY-minY+1, aspect=bh>0?bw/bh:0, areaRatio=(bw*bh)/(W*H);
  if (bw<CONSERVATIVE_MIN_DIM||bh<CONSERVATIVE_MIN_DIM) return null;
  if (aspect<LONGRUN_MIN_ASPECT||aspect>LONGRUN_MAX_ASPECT) return null;
  if (areaRatio<MIN_BOARD_AREA_RATIO||areaRatio>MAX_BOARD_AREA_RATIO-0.03) return null;
  return {left:minX,top:minY,right:maxX,bottom:maxY,isDark};
}

function findBoxLongRun(gray, W, H, isDark, bg) {
  const baseOffset = 60, baseAbs = isDark ? bg + baseOffset : bg - baseOffset;
  const result = findBoxLongRunWithThresh(gray, W, H, isDark, baseAbs);
  if (result !== null) return result;
  for (const offset of LONGRUN_TIGHTER_OFFSETS) { if (offset >= baseOffset) continue; const r2 = findBoxLongRunWithThresh(gray, W, H, isDark, isDark ? bg + offset : bg - offset); if (r2 !== null) return r2; }
  return null;
}

function findGridLinePeaks(gray, W, H, bg, isDark, axis) {
  const len = axis === 'col' ? W : H;
  const otherLen = axis === 'col' ? H : W;
  const peaks = [];
  for (let i = 0; i < len; i++) {
    let ink = 0;
    for (let j = 0; j < otherLen; j += 2) {
      const idx = axis === 'col' ? j * W + i : i * W + j;
      if (isDark ? gray[idx] > bg + INK_THRESH : gray[idx] < bg - INK_THRESH) ink++;
    }
    if (ink / (otherLen / 2) > 0.7) { let end = i; while (end + 1 < len) { let ink2 = 0; for (let j = 0; j < otherLen; j += 2) { const idx2 = axis === 'col' ? j * W + (end+1) : (end+1) * W + j; if (isDark ? gray[idx2] > bg + INK_THRESH : gray[idx2] < bg - INK_THRESH) ink2++; } if (ink2 / (otherLen / 2) < 0.7) break; end++; } peaks.push(Math.floor((i + end) / 2)); i = end; }
  }
  return peaks;
}

function findBoardBBox(pixels, width, height, bg) {
  g_lastBboxDiag = ''; const isDark = bg < BG_DARK_THRESHOLD;
  const gray = toGrayArray(pixels, width, height), imgArea = width * height;
  const isDegenerate = (b) => ((b.right-b.left)*(b.bottom-b.top)) > imgArea * MAX_BOARD_AREA_RATIO;
  const longRun = findBoxLongRun(gray, width, height, isDark, bg); if (longRun !== null) return longRun;
  const primary = findBBoxInRectGray(gray, width, height, bg, isDark, 0, 0, width, height, BBOX_PRIMARY_THRESH, BBOX_PRIMARY_MIN_FRAC);
  if (primary !== null && isValidBoardAspect(primary, width, height) && !isDegenerate(primary)) return primary;
  for (const thresh of BBOX_RELAXED_THRESHOLDS) { const res = findBBoxInRectGray(gray, width, height, bg, isDark, 0, 0, width, height, thresh, BBOX_RELAXED_MIN_FRAC); g_lastBboxDiag += ' relaxed:' + thresh + '=' + (res ? (res.left+'-'+res.right) : 'null') + ' deg=' + (res ? isDegenerate(res) : 'n/a'); if (res !== null && isValidBoardAspect(res, width, height) && !isDegenerate(res)) return res; }
  const colPeaks = findGridLinePeaks(gray, width, height, bg, isDark, 'col');
  const rowPeaks = findGridLinePeaks(gray, width, height, bg, isDark, 'row');
  g_lastBboxDiag = 'gridPeaks col=' + colPeaks.length + '[' + colPeaks.join(',') + '] row=' + rowPeaks.length + '[' + rowPeaks.join(',') + '] bg=' + bg.toFixed(1) + ' isDark=' + isDark;
  if (colPeaks.length >= 9 && rowPeaks.length >= 9) {
    const colSpacing = (colPeaks[colPeaks.length-1] - colPeaks[0]) / (colPeaks.length - 1);
    const rowSpacing = (rowPeaks[rowPeaks.length-1] - rowPeaks[0]) / (rowPeaks.length - 1);
    if (colSpacing > 0 && rowSpacing > 0) {
      const colSpreads = [];
      for (let i = 1; i < colPeaks.length; i++) colSpreads.push(colPeaks[i] - colPeaks[i-1]);
      const rowSpreads = [];
      for (let i = 1; i < rowPeaks.length; i++) rowSpreads.push(rowPeaks[i] - rowPeaks[i-1]);
      const colCV = colSpreads.reduce((s,v) => s + Math.abs(v - colSpacing), 0) / colSpreads.length / colSpacing;
      const rowCV = rowSpreads.reduce((s,v) => s + Math.abs(v - rowSpacing), 0) / rowSpreads.length / rowSpacing;
      if (colCV < 0.35 && rowCV < 0.35) {
        const bbox = { left: Math.max(0, colPeaks[0] - Math.floor(colSpacing * 0.5)), top: Math.max(0, rowPeaks[0] - Math.floor(rowSpacing * 0.5)), right: Math.min(width - 1, colPeaks[colPeaks.length-1] + Math.floor(colSpacing * 0.5)), bottom: Math.min(height - 1, rowPeaks[rowPeaks.length-1] + Math.floor(rowSpacing * 0.5)), isDark };
        if (isValidBoardAspect(bbox, width, height)) return bbox;
      }
    }
  }
  const regions = [];
  for (const br of BBOX_REGIONS) regions.push([Math.floor(width*br[0]),Math.floor(height*br[1]),Math.floor(width*br[2]),Math.floor(height*br[3])]);
  if (height > width * PORTRAIT_ASPECT_THRESHOLD) for (const br of BBOX_PORTRAIT_REGIONS) regions.push([Math.floor(width*br[0]),Math.floor(height*br[1]),Math.floor(width*br[2]),Math.floor(height*br[3])]);
  if (width > height * PORTRAIT_ASPECT_THRESHOLD) for (const br of BBOX_LANDSCAPE_REGIONS) regions.push([Math.floor(width*br[0]),Math.floor(height*br[1]),Math.floor(width*br[2]),Math.floor(height*br[3])]);
  let bestArea = 0, bestBox = null;
  for (const r of regions) for (const thresh of BBOX_REGION_THRESHOLDS) { const res = findBBoxInRectGray(gray, width, height, bg, isDark, r[0], r[1], r[2], r[3], thresh, BBOX_REGION_MIN_FRAC); if (res !== null && isValidBoardAspect(res, width, height)) { const area = (res.right-res.left)*(res.bottom-res.top); if (area < imgArea * MAX_BOARD_AREA_RATIO && area > bestArea) { bestArea = area; bestBox = res; } break; } }
  const adaptive = findBBoxAdaptive(gray, width, height, isDark);
  if (adaptive !== null) {
    const aArea = (adaptive.right-adaptive.left)*(adaptive.bottom-adaptive.top);
    if (aArea < imgArea * MAX_BOARD_AREA_RATIO) return adaptive;
    if (aArea >= imgArea * 0.85 && isValidBoardAspect(adaptive, width, height)) {
      if (bestBox === null || aArea > bestArea * 1.5) return adaptive;
    }
  }
  const conservative = findBBoxConservative(gray, width, height, isDark, bg); if (conservative !== null) return conservative;
  if (bestBox !== null) return bestBox;
  return { left: 0, top: 0, right: width, bottom: height, isDark };
}

function stripEdgeGridLines(sig) {
  const minCount = Math.floor(Math.min(SIG_ROWS, SIG_COLS) * GRID_LINE_RATIO);
  for (let row=0;row<=1&&row<SIG_ROWS;row++) { let ic=0; for (let c=0;c<SIG_COLS;c++) if (sig[row*SIG_COLS+c]===1) ic++; if (ic>=minCount) for (let c=0;c<SIG_COLS;c++) sig[row*SIG_COLS+c]=0; }
  for (let row=SIG_ROWS-1;row>=SIG_ROWS-2&&row>=0;row--) { let ic=0; for (let c=0;c<SIG_COLS;c++) if (sig[row*SIG_COLS+c]===1) ic++; if (ic>=minCount) for (let c=0;c<SIG_COLS;c++) sig[row*SIG_COLS+c]=0; }
  for (let col=0;col<=1&&col<SIG_COLS;col++) { let ic=0; for (let r=0;r<SIG_ROWS;r++) if (sig[r*SIG_COLS+col]===1) ic++; if (ic>=minCount) for (let r=0;r<SIG_ROWS;r++) sig[r*SIG_COLS+col]=0; }
  for (let col=SIG_COLS-1;col>=SIG_COLS-2&&col>=0;col--) { let ic=0; for (let r=0;r<SIG_ROWS;r++) if (sig[r*SIG_COLS+col]===1) ic++; if (ic>=minCount) for (let r=0;r<SIG_ROWS;r++) sig[r*SIG_COLS+col]=0; }
}

function stripFullHeightVerticalStrokes(sig) {
  const FULL_HEIGHT_THRESH = SIG_ROWS * 0.70;
  const colInk = new Array(SIG_COLS).fill(0);
  for (let c = 0; c < SIG_COLS; c++) for (let r = 0; r < SIG_ROWS; r++) if (sig[r * SIG_COLS + c] === 1) colInk[c]++;
  let rightMostHigh = -1;
  for (let c = SIG_COLS - 1; c >= 0; c--) if (colInk[c] >= FULL_HEIGHT_THRESH) rightMostHigh = c;
  for (let c = 0; c < SIG_COLS; c++) {
    if (colInk[c] >= FULL_HEIGHT_THRESH) {
      let clusterEnd = c;
      while (clusterEnd + 1 < SIG_COLS && colInk[clusterEnd + 1] >= FULL_HEIGHT_THRESH * 0.5) clusterEnd++;
      const clusterW = clusterEnd - c + 1;
      if (clusterW <= 4 && c < rightMostHigh - 2) {
        for (let cc = c; cc <= clusterEnd; cc++) for (let r = 0; r < SIG_ROWS; r++) sig[r * SIG_COLS + cc] = 0;
      }
      c = clusterEnd;
    }
  }
}

function detectGridLineWidths(gray, imgW, boardL, boardT, boardR, boardB, isDark, bg) {
  g_gridLineCropTop=new Array(81).fill(0); g_gridLineCropBot=new Array(81).fill(0); g_gridLineCropLeft=new Array(81).fill(0); g_gridLineCropRight=new Array(81).fill(0);
  const cellW=(boardR-boardL)/9, cellH=(boardB-boardT)/9, imgH=Math.floor(gray.length/imgW);
  const hLineInkDown=new Array(10).fill(0), hLineInkUp=new Array(10).fill(0), vLineInkRight=new Array(10).fill(0), vLineInkLeft=new Array(10).fill(0);
  for (let i=0;i<10;i++) {
    const lineY=Math.round(boardT+i*cellH); if (lineY<0||lineY>=imgH) continue;
    const bandHalf=Math.max(3,Math.floor(cellH*CENTERING_MARGIN)), yStart=Math.max(0,lineY-bandHalf), yEnd=Math.min(imgH-1,lineY+bandHalf);
    const innerX0=Math.floor(boardL+cellW*CENTERING_MARGIN), innerX1=Math.floor(boardR-cellW*CENTERING_MARGIN), spanLen=innerX1-innerX0+1;
    if (spanLen<5) continue; let maxInkPct=0, bestY=lineY;
    for (let y=yStart;y<=yEnd;y++) { let ic=0; for (let x=innerX0;x<=innerX1;x++) if (grayInkPixel(gray[y*imgW+x],bg,isDark,INK_THRESH)) ic++; const pct=ic/spanLen; if (pct>maxInkPct) { maxInkPct=pct; bestY=y; } }
    if (maxInkPct<GRID_LINE_INK_EXIST_THRESH) continue; const threshPct=maxInkPct*0.5; let topInkY=bestY, botInkY=bestY;
    for (let y=bestY-1;y>=yStart;y--) { let ic=0; for (let x=innerX0;x<=innerX1;x++) if (grayInkPixel(gray[y*imgW+x],bg,isDark,INK_THRESH)) ic++; if (ic/spanLen<threshPct) break; topInkY=y; }
    for (let y=bestY+1;y<=yEnd;y++) { let ic=0; for (let x=innerX0;x<=innerX1;x++) if (grayInkPixel(gray[y*imgW+x],bg,isDark,INK_THRESH)) ic++; if (ic/spanLen<threshPct) break; botInkY=y; }
    hLineInkUp[i]=Math.max(0,lineY-topInkY); hLineInkDown[i]=Math.max(0,botInkY-lineY);
  }
  for (let j=0;j<10;j++) {
    const lineX=Math.round(boardL+j*cellW); if (lineX<0||lineX>=imgW) continue;
    const bandHalf=Math.max(3,Math.floor(cellW*CENTERING_MARGIN)), xStart=Math.max(0,lineX-bandHalf), xEnd=Math.min(imgW-1,lineX+bandHalf);
    const innerY0=Math.floor(boardT+cellH*CENTERING_MARGIN), innerY1=Math.floor(boardB-cellH*CENTERING_MARGIN), spanLen=innerY1-innerY0+1;
    if (spanLen<5) continue; let maxInkPct=0, bestX=lineX;
    for (let x=xStart;x<=xEnd;x++) { let ic=0; for (let y=innerY0;y<=innerY1;y++) if (grayInkPixel(gray[y*imgW+x],bg,isDark,INK_THRESH)) ic++; const pct=ic/spanLen; if (pct>maxInkPct) { maxInkPct=pct; bestX=x; } }
    if (maxInkPct<GRID_LINE_INK_EXIST_THRESH) continue; const threshPct=maxInkPct*0.5; let leftInkX=bestX, rightInkX=bestX;
    for (let x=bestX-1;x>=xStart;x--) { let ic=0; for (let y=innerY0;y<=innerY1;y++) if (grayInkPixel(gray[y*imgW+x],bg,isDark,INK_THRESH)) ic++; if (ic/spanLen<threshPct) break; leftInkX=x; }
    for (let x=bestX+1;x<=xEnd;x++) { let ic=0; for (let y=innerY0;y<=innerY1;y++) if (grayInkPixel(gray[y*imgW+x],bg,isDark,INK_THRESH)) ic++; if (ic/spanLen<threshPct) break; rightInkX=x; }
    vLineInkLeft[j]=Math.max(0,lineX-leftInkX); vLineInkRight[j]=Math.max(0,rightInkX-lineX);
  }
  const minMargin=Math.max(1,Math.floor(Math.min(cellW,cellH)*GRID_LINE_MIN_MAX_FRAC));
  for (let row=0;row<9;row++) for (let col=0;col<9;col++) { const idx=row*9+col, maxM=Math.floor(Math.min(cellW,cellH)*0.45); g_gridLineCropTop[idx]=Math.max(minMargin,Math.min(hLineInkDown[row]+1,maxM)); g_gridLineCropBot[idx]=Math.max(minMargin,Math.min(hLineInkUp[row+1]+1,maxM)); g_gridLineCropLeft[idx]=Math.max(minMargin,Math.min(vLineInkRight[col]+1,maxM)); g_gridLineCropRight[idx]=Math.max(minMargin,Math.min(vLineInkLeft[col+1]+1,maxM)); }
  g_gridLineDetected = true;
}

function cellSigFromGray(gray, width, cellLeft, cellTop, cellW, cellH, isDark, bg, gridRow, gridCol) {
  let mxLeft=cellW*CELL_MARGIN_RATIO, mxRight=cellW*CELL_MARGIN_RATIO, myTop=cellH*CELL_MARGIN_RATIO, myBot=cellH*CELL_MARGIN_RATIO;
  if (g_gridLineDetected && gridRow>=0 && gridRow<9 && gridCol>=0 && gridCol<9) { const idx=gridRow*9+gridCol, maxMW=Math.floor(cellW*0.45), maxMH=Math.floor(cellH*0.45); mxLeft=Math.max(mxLeft,Math.min(g_gridLineCropLeft[idx],maxMW)); mxRight=Math.max(mxRight,Math.min(g_gridLineCropRight[idx],maxMW)); myTop=Math.max(myTop,Math.min(g_gridLineCropTop[idx],maxMH)); myBot=Math.max(myBot,Math.min(g_gridLineCropBot[idx],maxMH)); }
  const x0=Math.floor(cellLeft+mxLeft), y0=Math.floor(cellTop+myTop), x1=Math.floor(cellLeft+cellW-mxRight), y1=Math.floor(cellTop+cellH-myBot);
  const H=Math.floor(gray.length/width), cellWInner=x1-x0, cellHInner=y1-y0;
  const savedPixels=[], savedPositions=[];
  { const rowAvg=new Float32Array(cellHInner); for (let dy=0;dy<cellHInner;dy++) { let sum=0; const y=y0+dy; for (let dx=0;dx<cellWInner;dx++) sum+=gray[y*width+x0+dx]; rowAvg[dy]=sum/cellWInner; }
    const colAvg=new Float32Array(cellWInner); for (let dx=0;dx<cellWInner;dx++) { let sum=0; const x=x0+dx; for (let dy=0;dy<cellHInner;dy++) sum+=gray[(y0+dy)*width+x]; colAvg[dx]=sum/cellHInner; }
    const isGridRow=new Array(cellHInner).fill(false); let gridRowCount=0;
    for (let dy=0;dy<cellHInner;dy++) { const diff=isDark?(rowAvg[dy]-bg):(bg-rowAvg[dy]); if (diff>GRID_LINE_GRAY_DIFF) { let v=0; const y=y0+dy; for (let dx=0;dx<cellWInner;dx++) { const g=gray[y*width+x0+dx]; v+=(g-rowAvg[dy])**2; } v=Math.sqrt(v/cellWInner); if (v<GRID_LINE_GRAY_DIFF*2) { isGridRow[dy]=true; gridRowCount++; } } }
    if (gridRowCount>Math.floor(cellHInner*0.3)) for (let dy=0;dy<cellHInner;dy++) isGridRow[dy]=false;
    const isGridCol=new Array(cellWInner).fill(false); let gridColCount=0;
    for (let dx=0;dx<cellWInner;dx++) { const diff=isDark?(colAvg[dx]-bg):(bg-colAvg[dx]); if (diff>GRID_LINE_GRAY_DIFF) { let v=0; const x=x0+dx; for (let dy=0;dy<cellHInner;dy++) { const g=gray[(y0+dy)*width+x]; v+=(g-colAvg[dx])**2; } v=Math.sqrt(v/cellHInner); if (v<GRID_LINE_GRAY_DIFF*2) { isGridCol[dx]=true; gridColCount++; } } }
    if (gridColCount>Math.floor(cellWInner*0.3)) for (let dx=0;dx<cellWInner;dx++) isGridCol[dx]=false;
    for (let dy=0;dy<cellHInner;dy++) { if (!isGridRow[dy]) continue; const y=y0+dy; for (let dx=0;dx<cellWInner;dx++) { const pos=y*width+x0+dx; savedPixels.push(gray[pos]); savedPositions.push(pos); gray[pos]=bg; } }
    for (let dx=0;dx<cellWInner;dx++) { if (!isGridCol[dx]) continue; const x=x0+dx; for (let dy=0;dy<cellHInner;dy++) { const pos=(y0+dy)*width+x; savedPixels.push(gray[pos]); savedPositions.push(pos); gray[pos]=bg; } }
  }
  let ink=0, area=0, bminX=1e6, bmaxX=-1, bminY=1e6, bmaxY=-1;
  for (let y=y0;y<y1;y++) for (let x=x0;x<x1;x++) { area++; const g=gray[y*width+x]; if (grayInkPixel(g,bg,isDark,INK_THRESH)) { ink++; if (x<bminX) bminX=x; if (x>bmaxX) bmaxX=x; if (y<bminY) bminY=y; if (y>bmaxY) bmaxY=y; } }
  g_lastRawInkRatio = area > 0 ? ink / area : 0;
  let result = null;
  if (ink >= area * MIN_CELL_INK_RATIO && bmaxX >= 0) {
    const bw=bmaxX-bminX+1, bh=bmaxY-bminY+1;
    if (bw >= SAUVOLA_MIN_DIM * 3 && bh >= SAUVOLA_MIN_DIM * 3) {
      const sauvBinary = sauvolaThreshold(gray, width, H, bminX, bminY, bw, bh, isDark);
      if (sauvBinary !== null) {
        const scale = Math.max(1, Math.ceil(SIG_COLS / bw), Math.ceil(SIG_ROWS / bh));
        const sbw = bw * scale, sbh = bh * scale;
        const scaledBinary = new Float32Array(sbw * sbh);
        for (let r=0;r<sbh;r++) for (let c=0;c<sbw;c++) scaledBinary[r*sbw+c] = sauvBinary[Math.floor(r/scale)*bw+Math.floor(c/scale)];
        const sauvSig=new Array(SIG_LEN).fill(0);
        for (let r=0;r<SIG_ROWS;r++) for (let c=0;c<SIG_COLS;c++) { const sx0=Math.floor(sbw*c/SIG_COLS),sx1=Math.floor(sbw*(c+1)/SIG_COLS),sy0=Math.floor(sbh*r/SIG_ROWS),sy1=Math.floor(sbh*(r+1)/SIG_ROWS); let s=0,n=0; for (let ly=sy0;ly<sy1;ly++) for (let lx=sx0;lx<sx1;lx++) { s+=scaledBinary[ly*sbw+lx]; n++; } sauvSig[r*SIG_COLS+c]=(n>0&&s/n>0.5)?1:0; }
        stripEdgeGridLines(sauvSig); stripFullHeightVerticalStrokes(sauvSig); const si=countInk(sauvSig); if (si>=THIN1_MIN_INK_COUNT&&si<=MAX_INK_COUNT) result=sauvSig;
      }
    }
    if (result === null) {
      const sig=new Array(SIG_LEN).fill(0);
      const scale = Math.max(1, Math.ceil(SIG_COLS / bw), Math.ceil(SIG_ROWS / bh));
      const sbw = bw * scale, sbh = bh * scale;
      const scaledGray = new Float32Array(sbw * sbh);
      for (let r=0;r<sbh;r++) for (let c=0;c<sbw;c++) {
        const sy = bminY + Math.floor(r / scale), sx = bminX + Math.floor(c / scale);
        scaledGray[r * sbw + c] = (sy >= 0 && sy < H && sx >= 0 && sx < width) ? gray[sy * width + sx] : bg;
      }
      for (let r=0;r<SIG_ROWS;r++) for (let c=0;c<SIG_COLS;c++) {
        const sx0=Math.floor(sbw*c/SIG_COLS),sx1=Math.floor(sbw*(c+1)/SIG_COLS),sy0=Math.floor(sbh*r/SIG_ROWS),sy1=Math.floor(sbh*(r+1)/SIG_ROWS);
        let s=0,n=0;
        for (let ly=sy0;ly<sy1;ly++) for (let lx=sx0;lx<sx1;lx++) { s+=scaledGray[ly*sbw+lx]; n++; }
        const avg=n>0?s/n:bg;
        sig[r*SIG_COLS+c]=grayInkPixel(avg,bg,isDark,INK_THRESH)?1:0;
      }
      stripEdgeGridLines(sig); stripFullHeightVerticalStrokes(sig); const ic=countInk(sig); if (ic>=THIN1_MIN_INK_COUNT&&ic<=MAX_INK_COUNT) result=sig;
    }
  }
  for (let i=0;i<savedPositions.length;i++) gray[savedPositions[i]]=savedPixels[i];
  return result;
}

function cellSigFromGrayLowThresh(gray, width, cellLeft, cellTop, cellW, cellH, isDark, bg, gridRow, gridCol) {
  const LOW_GRID_DIFF = LOW_INK_THRESH_RETRY * 0.6;
  let mxLeft=cellW*CELL_MARGIN_RATIO, mxRight=cellW*CELL_MARGIN_RATIO, myTop=cellH*CELL_MARGIN_RATIO, myBot=cellH*CELL_MARGIN_RATIO;
  if (g_gridLineDetected && gridRow>=0 && gridRow<9 && gridCol>=0 && gridCol<9) { const idx=gridRow*9+gridCol, maxMW=Math.floor(cellW*0.45), maxMH=Math.floor(cellH*0.45); mxLeft=Math.max(mxLeft,Math.min(g_gridLineCropLeft[idx],maxMW)); mxRight=Math.max(mxRight,Math.min(g_gridLineCropRight[idx],maxMW)); myTop=Math.max(myTop,Math.min(g_gridLineCropTop[idx],maxMH)); myBot=Math.max(myBot,Math.min(g_gridLineCropBot[idx],maxMH)); }
  const x0=Math.floor(cellLeft+mxLeft), y0=Math.floor(cellTop+myTop), x1=Math.floor(cellLeft+cellW-mxRight), y1=Math.floor(cellTop+cellH-myBot);
  const H=Math.floor(gray.length/width), cellWInner=x1-x0, cellHInner=y1-y0;
  const rowAvg=new Array(cellHInner).fill(0); for (let dy=0;dy<cellHInner;dy++) { let s=0; for (let dx=0;dx<cellWInner;dx++) s+=gray[(y0+dy)*width+x0+dx]; rowAvg[dy]=s/cellWInner; }
  const isGridRow=new Array(cellHInner).fill(false);
  for (let dy=0;dy<cellHInner;dy++) { const diff=isDark?(rowAvg[dy]-bg):(bg-rowAvg[dy]); if (diff>LOW_GRID_DIFF) { let v=0; const y=y0+dy; for (let dx=0;dx<cellWInner;dx++) { const g=gray[y*width+x0+dx]; v+=(g-rowAvg[dy])**2; } v=Math.sqrt(v/cellWInner); if (v<LOW_GRID_DIFF*2) isGridRow[dy]=true; } }
  const colAvg=new Array(cellWInner).fill(0); for (let dx=0;dx<cellWInner;dx++) { let s=0; for (let dy=0;dy<cellHInner;dy++) s+=gray[(y0+dy)*width+x0+dx]; colAvg[dx]=s/cellWInner; }
  const isGridCol=new Array(cellWInner).fill(false);
  for (let dx=0;dx<cellWInner;dx++) { const diff=isDark?(colAvg[dx]-bg):(bg-colAvg[dx]); if (diff>LOW_GRID_DIFF) { let v=0; const x=x0+dx; for (let dy=0;dy<cellHInner;dy++) { const g=gray[(y0+dy)*width+x]; v+=(g-colAvg[dx])**2; } v=Math.sqrt(v/cellHInner); if (v<LOW_GRID_DIFF*2) isGridCol[dx]=true; } }
  const savedPixels=[], savedPositions=[];
  for (let dy=0;dy<cellHInner;dy++) { if (!isGridRow[dy]) continue; const y=y0+dy; for (let dx=0;dx<cellWInner;dx++) { const pos=y*width+x0+dx; savedPixels.push(gray[pos]); savedPositions.push(pos); gray[pos]=bg; } }
  for (let dx=0;dx<cellWInner;dx++) { if (!isGridCol[dx]) continue; const x=x0+dx; for (let dy=0;dy<cellHInner;dy++) { const pos=(y0+dy)*width+x; savedPixels.push(gray[pos]); savedPositions.push(pos); gray[pos]=bg; } }
  let bminX=1e6,bmaxX=-1,bminY=1e6,bmaxY=-1,inkCount=0;
  for (let y=y0;y<y1;y++) for (let x=x0;x<x1;x++) { const g=gray[y*width+x]; if (grayInkPixel(g,bg,isDark,LOW_INK_THRESH_RETRY)) { inkCount++; if (x<bminX) bminX=x; if (x>bmaxX) bmaxX=x; if (y<bminY) bminY=y; if (y>bmaxY) bmaxY=y; } }
  let result = null;
  if (bmaxX>=0) { const bw=bmaxX-bminX+1, bh=bmaxY-bminY+1; const scale=Math.max(1,Math.ceil(SIG_COLS/bw),Math.ceil(SIG_ROWS/bh)); const sbw=bw*scale,sbh=bh*scale; const scaledGray=new Float32Array(sbw*sbh); for(let r=0;r<sbh;r++) for(let c=0;c<sbw;c++){const sy=bminY+Math.floor(r/scale),sx=bminX+Math.floor(c/scale);scaledGray[r*sbw+c]=(sy>=0&&sy<H&&sx>=0&&sx<width)?gray[sy*width+sx]:bg;} const sig=new Array(SIG_LEN).fill(0); for (let r=0;r<SIG_ROWS;r++) for (let c=0;c<SIG_COLS;c++) { const sx0=Math.floor(sbw*c/SIG_COLS),sx1=Math.floor(sbw*(c+1)/SIG_COLS),sy0=Math.floor(sbh*r/SIG_ROWS),sy1=Math.floor(sbh*(r+1)/SIG_ROWS); let s=0,n=0; for (let ly=sy0;ly<sy1;ly++) for (let lx=sx0;lx<sx1;lx++) { s+=scaledGray[ly*sbw+lx]; n++; } const avg=n>0?s/n:bg; sig[r*SIG_COLS+c]=grayInkPixel(avg,bg,isDark,LOW_INK_THRESH_RETRY)?1:0; } stripEdgeGridLines(sig); stripFullHeightVerticalStrokes(sig); const si=countInk(sig); if (si>=THIN1_MIN_INK_COUNT&&si<=MAX_INK_COUNT) result=sig; }
  for (let i=0;i<savedPositions.length;i++) gray[savedPositions[i]]=savedPixels[i];
  return result;
}

function cellSigFromGrayThin(gray, width, cellLeft, cellTop, cellW, cellH, isDark, bg, gridRow, gridCol) {
  const LOW_GRID_DIFF = LOW_INK_THRESH_RETRY * 0.4;
  const THIN_MARGIN = 0.02;
  let mxLeft=cellW*THIN_MARGIN, mxRight=cellW*THIN_MARGIN, myTop=cellH*THIN_MARGIN, myBot=cellH*THIN_MARGIN;
  if (g_gridLineDetected && gridRow>=0 && gridRow<9 && gridCol>=0 && gridCol<9) { const idx=gridRow*9+gridCol, maxMW=Math.floor(cellW*0.45), maxMH=Math.floor(cellH*0.45); mxLeft=Math.max(mxLeft,Math.min(g_gridLineCropLeft[idx],maxMW)); mxRight=Math.max(mxRight,Math.min(g_gridLineCropRight[idx],maxMW)); myTop=Math.max(myTop,Math.min(g_gridLineCropTop[idx],maxMH)); myBot=Math.max(myBot,Math.min(g_gridLineCropBot[idx],maxMH)); }
  const x0=Math.floor(cellLeft+mxLeft), y0=Math.floor(cellTop+myTop), x1=Math.floor(cellLeft+cellW-mxRight), y1=Math.floor(cellTop+cellH-myBot);
  const H=Math.floor(gray.length/width), cellWInner=x1-x0, cellHInner=y1-y0;
  const rowAvg=new Array(cellHInner).fill(0); for (let dy=0;dy<cellHInner;dy++) { let s=0; for (let dx=0;dx<cellWInner;dx++) s+=gray[(y0+dy)*width+x0+dx]; rowAvg[dy]=s/cellWInner; }
  const isGridRow=new Array(cellHInner).fill(false); let gridRowCount=0;
  for (let dy=0;dy<cellHInner;dy++) { const diff=isDark?(rowAvg[dy]-bg):(bg-rowAvg[dy]); if (diff>LOW_GRID_DIFF) { let v=0; const y=y0+dy; for (let dx=0;dx<cellWInner;dx++) { const g=gray[y*width+x0+dx]; v+=(g-rowAvg[dy])**2; } v=Math.sqrt(v/cellWInner); if (v<LOW_GRID_DIFF*3) { isGridRow[dy]=true; gridRowCount++; } } }
  if (gridRowCount>Math.floor(cellHInner*0.3)) for (let dy=0;dy<cellHInner;dy++) isGridRow[dy]=false;
  const colAvg=new Array(cellWInner).fill(0); for (let dx=0;dx<cellWInner;dx++) { let s=0; for (let dy=0;dy<cellHInner;dy++) s+=gray[(y0+dy)*width+x0+dx]; colAvg[dx]=s/cellHInner; }
  const isGridCol=new Array(cellWInner).fill(false); let gridColCount=0;
  for (let dx=0;dx<cellWInner;dx++) { const diff=isDark?(colAvg[dx]-bg):(bg-colAvg[dx]); if (diff>LOW_GRID_DIFF) { let v=0; const x=x0+dx; for (let dy=0;dy<cellHInner;dy++) { const g=gray[(y0+dy)*width+x]; v+=(g-colAvg[dx])**2; } v=Math.sqrt(v/cellHInner); if (v<LOW_GRID_DIFF*3) { isGridCol[dx]=true; gridColCount++; } } }
  if (gridColCount>Math.floor(cellWInner*0.3)) for (let dx=0;dx<cellWInner;dx++) isGridCol[dx]=false;
  const savedPixels=[], savedPositions=[];
  for (let dy=0;dy<cellHInner;dy++) { if (!isGridRow[dy]) continue; const y=y0+dy; for (let dx=0;dx<cellWInner;dx++) { const pos=y*width+x0+dx; savedPixels.push(gray[pos]); savedPositions.push(pos); gray[pos]=bg; } }
  for (let dx=0;dx<cellWInner;dx++) { if (!isGridCol[dx]) continue; const x=x0+dx; for (let dy=0;dy<cellHInner;dy++) { const pos=(y0+dy)*width+x; savedPixels.push(gray[pos]); savedPositions.push(pos); gray[pos]=bg; } }
  let bminX=1e6,bmaxX=-1,bminY=1e6,bmaxY=-1,inkCount=0;
  for (let y=y0;y<y1;y++) for (let x=x0;x<x1;x++) { const g=gray[y*width+x]; if (grayInkPixel(g,bg,isDark,LOW_INK_THRESH_RETRY)) { inkCount++; if (x<bminX) bminX=x; if (x>bmaxX) bmaxX=x; if (y<bminY) bminY=y; if (y>bmaxY) bmaxY=y; } }
  let result = null;
  if (bmaxX>=0) { const bw=bmaxX-bminX+1, bh=bmaxY-bminY+1; if (bw>=3&&bh>=3) { const scale=Math.max(1,Math.ceil(SIG_COLS/bw),Math.ceil(SIG_ROWS/bh)); const sbw=bw*scale,sbh=bh*scale; const scaledGray=new Float32Array(sbw*sbh); for(let r=0;r<sbh;r++) for(let c=0;c<sbw;c++){const sy=bminY+Math.floor(r/scale),sx=bminX+Math.floor(c/scale);scaledGray[r*sbw+c]=(sy>=0&&sy<H&&sx>=0&&sx<width)?gray[sy*width+sx]:bg;} const sig=new Array(SIG_LEN).fill(0); for (let r=0;r<SIG_ROWS;r++) for (let c=0;c<SIG_COLS;c++) { const sx0=Math.floor(sbw*c/SIG_COLS),sx1=Math.floor(sbw*(c+1)/SIG_COLS),sy0=Math.floor(sbh*r/SIG_ROWS),sy1=Math.floor(sbh*(r+1)/SIG_ROWS); let s=0,n=0; for (let ly=sy0;ly<sy1;ly++) for (let lx=sx0;lx<sx1;lx++) { s+=scaledGray[ly*sbw+lx]; n++; } const avg=n>0?s/n:bg; sig[r*SIG_COLS+c]=grayInkPixel(avg,bg,isDark,LOW_INK_THRESH_RETRY)?1:0; } stripEdgeGridLines(sig); stripFullHeightVerticalStrokes(sig); const si=countInk(sig); if (si>=THIN1_MIN_INK_COUNT&&si<=MAX_INK_COUNT) result=sig; } }
  for (let i=0;i<savedPositions.length;i++) gray[savedPositions[i]]=savedPixels[i];
  return result;
}

function holeCenterRow(sig) {
  let r1=-1,r2=-1; for (let r=0;r<SIG_ROWS;r++) { let ic=0; for (let c=0;c<SIG_COLS;c++) if (sig[r*SIG_COLS+c]===1) ic++; if (ic>0&&ic<SIG_COLS*0.4) { if (r1<0) r1=r; r2=r; } }
  if (r1<0) return 0.5;
  let midFill=0; for (let r=r1;r<=r2;r++) { let ic=0; for (let c=0;c<SIG_COLS;c++) if (sig[r*SIG_COLS+c]===1) ic++; if (ic>=SIG_COLS*0.5) midFill++; }
  if (midFill>0.5*(r2-r1+1)) return 0.5;
  return (r1+r2)/2/(SIG_ROWS-1);
}

function inkCentroidRow(sig) {
  let sumR=0, count=0; for (let r=0;r<SIG_ROWS;r++) for (let c=0;c<SIG_COLS;c++) if (sig[r*SIG_COLS+c]===1) { sumR+=r; count++; }
  return count>0 ? sumR/count/(SIG_ROWS-1) : 0.5;
}

function topBottomInkRatio(sig) {
  let top=0, bot=0; const mid=Math.floor(SIG_ROWS/2);
  for (let r=0;r<mid;r++) for (let c=0;c<SIG_COLS;c++) if (sig[r*SIG_COLS+c]===1) top++;
  for (let r=mid;r<SIG_ROWS;r++) for (let c=0;c<SIG_COLS;c++) if (sig[r*SIG_COLS+c]===1) bot++;
  return bot>0 ? top/bot : 999;
}

function hogVerticalGradient(sig) {
  const h=SIG_ROWS, w=SIG_COLS; let posGrad=0, negGrad=0;
  for (let r=1;r<h;r++) for (let c=0;c<w;c++) { const d=sig[r*SIG_COLS+c]-sig[(r-1)*SIG_COLS+c]; if (d>0) posGrad+=d; else negGrad+=d; }
  return posGrad+negGrad>0 ? posGrad/(posGrad-negGrad) : 0.5;
}

function strokeWidthRatio(sig) {
  let maxH=0; for (let r=0;r<SIG_ROWS;r++) { let run=0; for (let c=0;c<SIG_COLS;c++) { if (sig[r*SIG_COLS+c]===1) run++; else { if (run>maxH) maxH=run; run=0; } } if (run>maxH) maxH=run; }
  let maxV=0; for (let c=0;c<SIG_COLS;c++) { let run=0; for (let r=0;r<SIG_ROWS;r++) { if (sig[r*SIG_COLS+c]===1) run++; else { if (run>maxV) maxV=run; run=0; } } if (run>maxV) maxV=run; }
  return maxV>0 ? maxH/maxV : 0;
}

function detectThinOne(sig, inkCount) {
  if (inkCount < THIN1_MIN_INK_COUNT) return false;
  let minCol=SIG_COLS, maxCol=-1, minRow=SIG_ROWS, maxRow=-1;
  const colInk=new Array(SIG_COLS).fill(0), rowInk=new Array(SIG_ROWS).fill(0);
  for (let r=0;r<SIG_ROWS;r++) for (let c=0;c<SIG_COLS;c++) { if (sig[r*SIG_COLS+c]===1) { if (c<minCol)minCol=c; if (c>maxCol)maxCol=c; if (r<minRow)minRow=r; if (r>maxRow)maxRow=r; colInk[c]++; rowInk[r]++; } }
  if (maxCol<0) return false;
  const inkWidth=maxCol-minCol+1, inkHeight=maxRow-minRow+1;
  if (inkWidth>SIG_COLS*0.50) return false;
  if (inkHeight<SIG_ROWS*0.50) return false;
  if (inkWidth===0||inkHeight/inkWidth<1.8) return false;
  const bboxArea=inkWidth*inkHeight; if (bboxArea===0) return false;
  const density=inkCount/bboxArea; if (density<0.30) return false;
  const startRow=Math.floor(SIG_ROWS*0.2), endRow=Math.floor(SIG_ROWS*0.8);
  let rowsWithInk=0; const totalMidRows=endRow-startRow;
  for (let r=startRow;r<endRow;r++) if (rowInk[r]>0) rowsWithInk++;
  if (rowsWithInk<totalMidRows*0.65) return false;
  let colSum=0; for (let c=0;c<SIG_COLS;c++) colSum+=c*colInk[c];
  const colCenter=inkCount>0?colSum/inkCount:SIG_COLS/2;
  if (colCenter<SIG_COLS*0.20||colCenter>SIG_COLS*0.80) return false;
  return true;
}

function maxHorizontalSpan(sig, rowStart, rowEnd) {
  let maxSpan=0;
  for (let r=rowStart;r<rowEnd;r++) { let start=-1,span=0; for (let c=0;c<SIG_COLS;c++) { if (sig[r*SIG_COLS+c]===1) { if (start<0) start=c; span=c-start+1; } else if (start>=0) break; } if (span>maxSpan) maxSpan=span; }
  return maxSpan;
}

function isLikelyNot4(sig) {
  const midTop=Math.floor(SIG_ROWS*0.25), midBot=Math.floor(SIG_ROWS*0.60);
  const hSpan=maxHorizontalSpan(sig,midTop,midBot);
  if (hSpan<SIG_COLS*0.30) return true;
  const topRow=Math.floor(SIG_ROWS*0.15), midRow=Math.floor(SIG_ROWS*0.45);
  let topLeftInk=0, topRightInk=0;
  for (let r=topRow;r<midRow;r++) for (let c=0;c<SIG_COLS;c++) if (sig[r*SIG_COLS+c]===1) { if (c<SIG_COLS/2) topLeftInk++; else topRightInk++; }
  if (topLeftInk===0&&topRightInk>0) return true;
  return false;
}

function recognizeDigit(sig, templates) {
  g_lastConfidence = 0;
  if (sig === null) return 0;
  const inkCount = countInk(sig);
  if (inkCount < THIN1_MIN_INK_COUNT || inkCount > MAX_INK_COUNT) return 0;
  if (templates.length === 0) return 0;
  const lowInk = inkCount < MIN_INK_COUNT;
  if (lowInk) {
    let best1Score = -100000, best1Key = null;
    for (const t of templates) {
      if (t.digit !== 1) continue;
      let match = 0; for (let i = 0; i < SIG_LEN; i++) if (sig[i] === t.key[i]) match++;
      const score = match - (SIG_LEN - match) * TEMPLATE_MISMATCH_PENALTY;
      if (score > best1Score) { best1Score = score; best1Key = t.key; }
    }
    const lowInkMinScore = Math.floor(SIG_LEN * 0.57);
    const geoMinScore = Math.floor(SIG_LEN * 0.55);
    const veryThinInk = inkCount < MIN_INK_COUNT_DIGIT1;
    if (veryThinInk) {
      if (best1Key !== null) {
        let tplInk = 0, tp = 0;
        for (let i = 0; i < SIG_LEN; i++) { if (best1Key[i] === 1) { tplInk++; if (sig[i] === 1) tp++; } }
        const recall = tplInk > 0 ? tp / tplInk : 0;
        const thinOk = detectThinOne(sig, inkCount);
        if (best1Score >= lowInkMinScore && recall >= 0.25 && thinOk) { g_lastConfidence = 0.50; return 1; }
      }
      g_lastConfidence = 0; return 0;
    }
    if (best1Score >= lowInkMinScore && best1Key !== null) {
      const inkCentroid = inkCentroidRow(sig);
      const tplCentroid = inkCentroidRow(best1Key);
      if (Math.abs(inkCentroid - tplCentroid) <= SIG_ROWS * 0.4) {
        const topRow = Math.floor(SIG_ROWS * 0.10), topEnd = Math.floor(SIG_ROWS * 0.30);
        let topMinC = SIG_COLS, topMaxC = 0;
        for (let r = topRow; r < topEnd; r++) for (let c = 0; c < SIG_COLS; c++) if (sig[r * SIG_COLS + c] === 1) { if (c < topMinC) topMinC = c; if (c > topMaxC) topMaxC = c; }
        const topSpan = topMaxC >= topMinC ? topMaxC - topMinC + 1 : 0;
        if (topSpan >= SIG_COLS * 0.6) {
          let solidTopRows = 0;
          for (let r = topRow; r < topEnd; r++) { let inkInRow = 0; for (let c = 0; c < SIG_COLS; c++) if (sig[r * SIG_COLS + c] === 1) inkInRow++; if (inkInRow >= SIG_COLS * 0.5) solidTopRows++; }
          if (solidTopRows >= 2) {
            let best7Score = -100000;
            for (const t7 of templates) { if (t7.digit !== 7) continue; let m7 = 0; for (let i = 0; i < SIG_LEN; i++) if (sig[i] === t7.key[i]) m7++; const s7 = m7 - (SIG_LEN - m7) * TEMPLATE_MISMATCH_PENALTY; if (s7 > best7Score) best7Score = s7; }
            if (best7Score >= lowInkMinScore - 50) {
              if (best1Score > best7Score + 30) { g_lastConfidence = Math.min(1, best1Score / (SIG_LEN + 200)); return 1; }
              g_lastConfidence = Math.min(1, best7Score / (SIG_LEN + 200)); return 7;
            }
          }
        }
        let best7F1 = -100000, best7F1Recall = 0;
        for (const t7 of templates) { if (t7.digit !== 7) continue; let tplInk = 0, tp = 0; for (let i = 0; i < SIG_LEN; i++) { if (t7.key[i] === 1) { tplInk++; if (sig[i] === 1) tp++; } } const recall = tplInk > 0 ? tp / tplInk : 0; const prec = inkCount > 0 ? tp / inkCount : 0; const f1 = (recall + prec) > 0 ? (2 * recall * prec) / (recall + prec) : 0; const match = tp + (SIG_LEN - inkCount - (tplInk - tp)); const score = f1 * 500 + match - (SIG_LEN - match) * TEMPLATE_MISMATCH_PENALTY; if (score > best7F1) { best7F1 = score; best7F1Recall = recall; } }
        if (best7F1 >= LOW_INK_FALLBACK_MIN_SCORE && best7F1Recall >= LOW_INK_FALLBACK_MIN_RECALL) {
          g_lastConfidence = Math.min(1, best7F1 / (SIG_LEN + 200)); return 7;
        }
        g_lastConfidence = Math.min(1, best1Score / (SIG_LEN + 200)); return 1;
      }
    }
    if (best1Score >= geoMinScore && detectThinOne(sig, inkCount)) { g_lastConfidence = 0.55; return 1; }
    const digitBestScore = new Array(10).fill(-100000), digitBestRecall = new Array(10).fill(0);
    for (const t of templates) {
      if (t.digit === 1) continue;
      let tplInk = 0, tp = 0;
      for (let i = 0; i < SIG_LEN; i++) { if (t.key[i] === 1) { tplInk++; if (sig[i] === 1) tp++; } }
      const recall = tplInk > 0 ? tp / tplInk : 0;
      const prec = inkCount > 0 ? tp / inkCount : 0;
      const f1 = (recall + prec) > 0 ? (2 * recall * prec) / (recall + prec) : 0;
      const match = tp + (SIG_LEN - inkCount - (tplInk - tp));
      const score = f1 * 500 + match - (SIG_LEN - match) * TEMPLATE_MISMATCH_PENALTY;
      if (score > digitBestScore[t.digit]) { digitBestScore[t.digit] = score; digitBestRecall[t.digit] = recall; }
    }
    let lowBestDigit = 0, lowBestScore = -100000, lowBestRecall = 0;
    for (let d = 2; d <= 9; d++) if (digitBestScore[d] > lowBestScore) { lowBestDigit = d; lowBestScore = digitBestScore[d]; lowBestRecall = digitBestRecall[d]; }
    const lowMinScore = LOW_INK_FALLBACK_MIN_SCORE;
    if (lowBestDigit > 0 && lowBestScore >= lowMinScore && lowBestRecall >= LOW_INK_FALLBACK_MIN_RECALL) {
      if (lowBestDigit === 4 && isLikelyNot4(sig)) {
        let best1s2 = -100000;
        for (const t of templates) { if (t.digit !== 1) continue; let m = 0; for (let i = 0; i < SIG_LEN; i++) if (sig[i] === t.key[i]) m++; const s = m - (SIG_LEN - m) * TEMPLATE_MISMATCH_PENALTY; if (s > best1s2) best1s2 = s; }
        if (best1s2 >= Math.floor(SIG_LEN * 0.55)) { g_lastConfidence = 0.55; return 1; }
      }
      if (lowBestDigit === 7) {
        if (best1Score > digitBestScore[7] + 30) { g_lastConfidence = Math.min(1, best1Score / (SIG_LEN + 200)); return 1; }
        const topRow7 = Math.floor(SIG_ROWS * 0.05), topEnd7 = Math.floor(SIG_ROWS * 0.35);
        let topSolid7 = 0, topTotal7 = 0;
        for (let r = topRow7; r < topEnd7; r++) { let inkInRow = 0; for (let c = 0; c < SIG_COLS; c++) if (sig[r * SIG_COLS + c] === 1) inkInRow++; topTotal7++; if (inkInRow >= SIG_COLS * 0.4) topSolid7++; }
        if (topSolid7 === 0) { g_lastConfidence = Math.min(1, best1Score / (SIG_LEN + 200)); return 1; }
      }
      g_lastConfidence = Math.min(1, lowBestScore / (SIG_LEN + 200));
      return lowBestDigit;
    }
    if (lowBestDigit === 4 && isLikelyNot4(sig)) {
      let best1s4 = -100000;
      for (const t of templates) { if (t.digit !== 1) continue; let m = 0; for (let i = 0; i < SIG_LEN; i++) if (sig[i] === t.key[i]) m++; const s = m - (SIG_LEN - m) * TEMPLATE_MISMATCH_PENALTY; if (s > best1s4) best1s4 = s; }
      if (best1s4 >= Math.floor(SIG_LEN * 0.50)) { g_lastConfidence = 0.50; return 1; }
    }
    g_lastConfidence = 0; return 0;
  }
  const digitBestScore = new Array(10).fill(-100000), digitBestIdx = new Array(10).fill(-1);
  for (const t of templates) {
    let tplInk = 0, tp = 0;
    for (let i = 0; i < SIG_LEN; i++) { if (t.key[i] === 1) { tplInk++; if (sig[i] === 1) tp++; } }
    const recall = tplInk > 0 ? tp / tplInk : 0;
    const prec = inkCount > 0 ? tp / inkCount : 0;
    const f1 = (recall + prec) > 0 ? (2 * recall * prec) / (recall + prec) : 0;
    const match = tp + (SIG_LEN - inkCount - (tplInk - tp));
    const score = f1 * 500 + match - (SIG_LEN - match) * TEMPLATE_MISMATCH_PENALTY;
    if (score > digitBestScore[t.digit]) { digitBestScore[t.digit] = score; digitBestIdx[t.digit] = templates.indexOf(t); }
  }
  let bestDigit = 0, bestScore = -100000, secondDigit = 0, secondScore = -100000;
  for (let d = 1; d <= 9; d++) {
    if (digitBestScore[d] > bestScore) { secondDigit = bestDigit; secondScore = bestScore; bestDigit = d; bestScore = digitBestScore[d]; }
    else if (digitBestScore[d] > secondScore) { secondDigit = d; secondScore = digitBestScore[d]; }
  }
  if (bestDigit === 1) {
    const leftCol = Math.floor(SIG_COLS * 0.4);
    const midRow = Math.floor(SIG_ROWS * 0.35);
    let leftLowerInk = 0;
    for (let r2 = midRow; r2 < SIG_ROWS; r2++) {
      for (let c2 = 0; c2 < leftCol; c2++) {
        if (sig[r2 * SIG_COLS + c2] === 1) leftLowerInk++;
      }
    }
    if (leftLowerInk > inkCount * 0.18) {
      let bestNon1 = 0, bestNon1Score = -100000;
      for (let d = 2; d <= 9; d++) {
        if (digitBestScore[d] > bestNon1Score) { bestNon1Score = digitBestScore[d]; bestNon1 = d; }
      }
      if (bestNon1 > 0) { bestDigit = bestNon1; bestScore = bestNon1Score; }
    }
    if (bestDigit === 1 && secondDigit === 7) {
      const topRow1 = Math.floor(SIG_ROWS * 0.05), topEnd1 = Math.floor(SIG_ROWS * 0.30);
      let topMinC1 = SIG_COLS, topMaxC1 = 0, solidTopRows1 = 0;
      for (let r = topRow1; r < topEnd1; r++) {
        let inkInRow = 0;
        for (let c = 0; c < SIG_COLS; c++) {
          if (sig[r * SIG_COLS + c] === 1) { inkInRow++; if (c < topMinC1) topMinC1 = c; if (c > topMaxC1) topMaxC1 = c; }
        }
        if (inkInRow >= SIG_COLS * 0.4) solidTopRows1++;
      }
      const topSpan1 = topMaxC1 >= topMinC1 ? topMaxC1 - topMinC1 + 1 : 0;
      if (topSpan1 >= SIG_COLS * 0.55 && solidTopRows1 >= 1) {
        bestDigit = 7; bestScore = digitBestScore[7];
      }
    }
  }
  const rawConf = bestScore / (SIG_LEN + 200);
  g_lastConfidence = rawConf > 1 ? 1 : (rawConf < 0 ? 0 : rawConf);
  if (bestDigit === 6 || bestDigit === 9) {
    const score6 = digitBestScore[6], score9 = digitBestScore[9];
    const scoreGap = Math.abs(score6 - score9);
    if (scoreGap >= DISAMBIG_SCORE_GAP_SKIP) return score6 > score9 ? 6 : 9;
    const qHole = holeCenterRow(sig), iCentroid = inkCentroidRow(sig), ratio = topBottomInkRatio(sig), hogGrad = hogVerticalGradient(sig), swRatio = strokeWidthRatio(sig);
    let vote6 = 0, vote9 = 0;
    if (qHole >= 0) { if (qHole > SIG_ROWS / 2) vote6 += DISAMBIG_HOLE_WEIGHT; else vote9 += DISAMBIG_HOLE_WEIGHT; }
    if (iCentroid >= 0) { if (iCentroid > SIG_ROWS / 2) vote6 += DISAMBIG_CENTROID_WEIGHT; else vote9 += DISAMBIG_CENTROID_WEIGHT; }
    if (ratio > 0.5) vote9 += DISAMBIG_TOP_RATIO_WEIGHT; else vote6 += DISAMBIG_TOP_RATIO_WEIGHT;
    if (hogGrad > 0.5) vote9 += DISAMBIG_HOG_WEIGHT; else vote6 += DISAMBIG_HOG_WEIGHT;
    if (swRatio > 1.1) vote9 += DISAMBIG_SW_WEIGHT; else if (swRatio < 0.9) vote6 += DISAMBIG_SW_WEIGHT;
    if (score6 > score9 + 50) vote6 += DISAMBIG_SCORE_WEIGHT; else if (score9 > score6 + 50) vote9 += DISAMBIG_SCORE_WEIGHT; else if (score6 > score9) vote6 += 1; else vote9 += 1;
    return vote6 > vote9 ? 6 : (vote9 > vote6 ? 9 : (score6 >= score9 ? 6 : 9));
  }
  if (bestDigit === 5 || bestDigit === 6) {
    const score5 = digitBestScore[5], score6d = digitBestScore[6], gap56 = Math.abs(score5 - score6d);
    if (gap56 >= 80) return score5 > score6d ? 5 : 6;
    const hole56 = holeCenterRow(sig);
    if (hole56 >= 0 && hole56 > SIG_ROWS * 0.45) return 6;
    let topInkCols56 = 0, botInkCols56 = 0;
    for (let c = 0; c < SIG_COLS; c++) { let topHas = false, botHas = false; for (let r = 0; r < SIG_ROWS / 2; r++) if (sig[r * SIG_COLS + c] === 1) topHas = true; for (let r2 = Math.floor(SIG_ROWS / 2); r2 < SIG_ROWS; r2++) if (sig[r2 * SIG_COLS + c] === 1) botHas = true; if (topHas) topInkCols56++; if (botHas) botInkCols56++; }
    if (botInkCols56 > topInkCols56 + 2 && score6d >= score5 - 30) return 6;
    return score5 >= score6d ? 5 : 6;
  }
  if (bestDigit === 5 || bestDigit === 9) {
    const score5b = digitBestScore[5], score9b = digitBestScore[9], gap59 = Math.abs(score5b - score9b);
    if (gap59 >= 80) return score5b > score9b ? 5 : 9;
    const hole59 = holeCenterRow(sig);
    if (hole59 >= 0 && hole59 < SIG_ROWS * 0.45) return 9;
    const botRow59 = Math.floor(SIG_ROWS * 0.7), endRow59 = Math.floor(SIG_ROWS * 0.9);
    let botLeftInk59 = 0, botRightInk59 = 0;
    for (let r = botRow59; r < endRow59; r++) { for (let c = 0; c < SIG_COLS / 2; c++) if (sig[r * SIG_COLS + c] === 1) botLeftInk59++; for (let c2 = Math.floor(SIG_COLS / 2); c2 < SIG_COLS; c2++) if (sig[r * SIG_COLS + c2] === 1) botRightInk59++; }
    if (botLeftInk59 > botRightInk59 * 1.5 && score5b >= score9b - 20) return 5;
    const topInkRatio59 = topBottomInkRatio(sig);
    if (topInkRatio59 > 0.55 && score9b >= score5b - 30) return 9;
    return score5b >= score9b ? 5 : 9;
  }
  if (bestDigit === 3 || bestDigit === 8) {
    const score3 = digitBestScore[3], score8 = digitBestScore[8], gap38 = Math.abs(score3 - score8);
    if (gap38 >= 80) return score3 > score8 ? 3 : 8;
    const midTop38 = Math.floor(SIG_ROWS * 0.3), midBot38 = Math.floor(SIG_ROWS * 0.7);
    let leftInk38 = 0, rightInk38 = 0;
    for (let r = midTop38; r < midBot38; r++) { for (let c = 0; c < SIG_COLS / 2; c++) if (sig[r * SIG_COLS + c] === 1) leftInk38++; for (let c2 = Math.floor(SIG_COLS / 2); c2 < SIG_COLS; c2++) if (sig[r * SIG_COLS + c2] === 1) rightInk38++; }
    const leftRatio38 = (leftInk38 + rightInk38) > 0 ? leftInk38 / (leftInk38 + rightInk38) : 0.5;
    if (leftRatio38 > 0.30) return 8;
    return score3 >= score8 ? 3 : 8;
  }
  if (bestDigit === 7) {
    const score7 = digitBestScore[7], score1 = digitBestScore[1], gap71 = score7 - score1;
    if (gap71 < 100 && score1 > 0) {
      const midTop71 = Math.floor(SIG_ROWS * 0.30), midBot71 = Math.floor(SIG_ROWS * 0.70);
      let totalRowWidth71 = 0, rowCount71 = 0;
      for (let r = midTop71; r < midBot71; r++) { let minC = SIG_COLS, maxC = -1; for (let c = 0; c < SIG_COLS; c++) if (sig[r * SIG_COLS + c] === 1) { if (c < minC) minC = c; if (c > maxC) maxC = c; } if (maxC >= minC) { totalRowWidth71 += maxC - minC + 1; rowCount71++; } }
      const avgRowWidth71 = rowCount71 > 0 ? totalRowWidth71 / rowCount71 : 0;
      if (avgRowWidth71 > 8 && inkCount > 200) { bestDigit = 1; bestScore = score1; }
    }
    if (bestDigit === 7) {
      const topRow71 = Math.floor(SIG_ROWS * 0.10), topEnd71 = Math.floor(SIG_ROWS * 0.30);
      let topMinC71 = SIG_COLS, topMaxC71 = 0;
      for (let r = topRow71; r < topEnd71; r++) for (let c = 0; c < SIG_COLS; c++) if (sig[r * SIG_COLS + c] === 1) { if (c < topMinC71) topMinC71 = c; if (c > topMaxC71) topMaxC71 = c; }
      const topSpan71 = topMaxC71 >= topMinC71 ? topMaxC71 - topMinC71 + 1 : 0;
      if (topSpan71 >= SIG_COLS * 0.6) {
        let solidTopRows71 = 0;
        for (let r = topRow71; r < topEnd71; r++) { let inkInRow = 0; for (let c = 0; c < SIG_COLS; c++) if (sig[r * SIG_COLS + c] === 1) inkInRow++; if (inkInRow >= SIG_COLS * 0.5) solidTopRows71++; }
        if (solidTopRows71 >= 2 && score7 >= score1) return 7;
        if (solidTopRows71 >= 2 && score1 > score7) return 1;
      }
      const botRow71 = Math.floor(SIG_ROWS * 0.60), botEnd71 = Math.floor(SIG_ROWS * 0.85);
      let botMinC71 = SIG_COLS, botMaxC71 = 0;
      for (let r = botRow71; r < botEnd71; r++) for (let c = 0; c < SIG_COLS; c++) if (sig[r * SIG_COLS + c] === 1) { if (c < botMinC71) botMinC71 = c; if (c > botMaxC71) botMaxC71 = c; }
      const botSpan71 = botMaxC71 >= botMinC71 ? botMaxC71 - botMinC71 + 1 : 0;
      if (botSpan71 <= 6 && topSpan71 < SIG_COLS * 0.6) return 1;
    }
  }
  if (bestScore >= MIN_DIGIT_SCORE) {
    if (bestDigit === 4 && isLikelyNot4(sig)) {
      let best1s3 = -100000;
      for (const t of templates) { if (t.digit !== 1) continue; let m = 0; for (let i = 0; i < SIG_LEN; i++) if (sig[i] === t.key[i]) m++; const s = m - (SIG_LEN - m) * TEMPLATE_MISMATCH_PENALTY; if (s > best1s3) best1s3 = s; }
      if (best1s3 >= Math.floor(SIG_LEN * 0.55)) { g_lastConfidence = 0.55; return 1; }
    }
    return bestDigit;
  }
  return 0;
}

function findPreciseGridLines(gray, width, bbox, isDark, bg) {
  const boardL = bbox.left, boardT = bbox.top, boardR = bbox.right, boardB = bbox.bottom;
  const boardW = boardR - boardL, boardH = boardB - boardT;
  const cellW = boardW / 9, cellH = boardH / 9;
  const H = Math.floor(gray.length / width);
  g_gridLineX = new Array(10).fill(0); g_gridLineY = new Array(10).fill(0);
  const PRECISE_GRID_MIN_INK_FRAC = 0.15;
  for (let i = 0; i < 10; i++) {
    const approxX = Math.round(boardL + i * cellW);
    const bandHalf = Math.max(3, Math.floor(cellW * 0.3));
    const x0 = Math.max(0, approxX - bandHalf), x1 = Math.min(width - 1, approxX + bandHalf);
    const innerY0 = Math.floor(boardT + cellH * 0.2), innerY1 = Math.floor(boardB - cellH * 0.2);
    const spanLen = innerY1 - innerY0 + 1;
    let bestX = approxX, bestInk = 0;
    for (let x = x0; x <= x1; x++) { let ic = 0; for (let y = innerY0; y <= innerY1; y++) if (grayInkPixel(gray[y * width + x], bg, isDark, INK_THRESH)) ic++; if (ic > bestInk) { bestInk = ic; bestX = x; } }
    g_gridLineX[i] = (bestInk >= spanLen * PRECISE_GRID_MIN_INK_FRAC) ? bestX : approxX;
  }
  for (let i = 0; i < 10; i++) {
    const approxY = Math.round(boardT + i * cellH);
    const bandHalf = Math.max(3, Math.floor(cellH * 0.3));
    const y0 = Math.max(0, approxY - bandHalf), y1 = Math.min(H - 1, approxY + bandHalf);
    const innerX0 = Math.floor(boardL + cellW * 0.2), innerX1 = Math.floor(boardR - cellW * 0.2);
    const spanLen = innerX1 - innerX0 + 1;
    let bestY = approxY, bestInk = 0;
    for (let y = y0; y <= y1; y++) { let ic = 0; for (let x = innerX0; x <= innerX1; x++) if (grayInkPixel(gray[y * width + x], bg, isDark, INK_THRESH)) ic++; if (ic > bestInk) { bestInk = ic; bestY = y; } }
    g_gridLineY[i] = (bestInk >= spanLen * PRECISE_GRID_MIN_INK_FRAC) ? bestY : approxY;
  }
  g_preciseGridDetected = true;
}

function findConflictCells(grid) {
  const conflicts = new Set();
  for (let r = 0; r < 9; r++) {
    const seen = new Map();
    for (let c = 0; c < 9; c++) { const v = grid[r * 9 + c]; if (v === 0) continue; if (seen.has(v)) { conflicts.add(r * 9 + c); conflicts.add(seen.get(v)); } else seen.set(v, r * 9 + c); }
  }
  for (let c = 0; c < 9; c++) {
    const seen = new Map();
    for (let r = 0; r < 9; r++) { const v = grid[r * 9 + c]; if (v === 0) continue; if (seen.has(v)) { conflicts.add(r * 9 + c); conflicts.add(seen.get(v)); } else seen.set(v, r * 9 + c); }
  }
  for (let br = 0; br < 3; br++) for (let bc = 0; bc < 3; bc++) {
    const seen = new Map();
    for (let dr = 0; dr < 3; dr++) for (let dc = 0; dc < 3; dc++) { const r = br*3+dr, c = bc*3+dc, v = grid[r*9+c]; if (v===0) continue; if (seen.has(v)) { conflicts.add(r*9+c); conflicts.add(seen.get(v)); } else seen.set(v, r*9+c); }
  }
  return conflicts;
}

function isConfusablePair(a, b) {
  const pairs = [[5,6],[5,9],[6,9],[3,8],[7,1],[1,7],[4,1],[1,4]];
  return pairs.some(p => (p[0]===a&&p[1]===b)||(p[0]===b&&p[1]===a));
}

function conflictCountAfterSet(grid, idx, val) {
  const r = Math.floor(idx / 9), c = idx % 9;
  let count = 0;
  for (let cc = 0; cc < 9; cc++) if (cc !== c && grid[r * 9 + cc] === val) count++;
  for (let rr = 0; rr < 9; rr++) if (rr !== r && grid[rr * 9 + c] === val) count++;
  const br = Math.floor(r / 3) * 3, bc = Math.floor(c / 3) * 3;
  for (let dr = 0; dr < 3; dr++) for (let dc = 0; dc < 3; dc++) { const rr = br+dr, cc = bc+dc; if (rr!==r||cc!==c) if (grid[rr*9+cc]===val) count++; }
  return count;
}

function solveSudoku(grid) {
  const g = grid.slice();
  let iterations = 0;
  const MAX_ITER = 100000;
  function isValid(r, c, val) {
    for (let i = 0; i < 9; i++) { if (g[r*9+i]===val||g[i*9+c]===val) return false; }
    const br=Math.floor(r/3)*3, bc=Math.floor(c/3)*3;
    for (let dr=0;dr<3;dr++) for (let dc=0;dc<3;dc++) if (g[(br+dr)*9+bc+dc]===val) return false;
    return true;
  }
  function solve() {
    if (++iterations > MAX_ITER) return false;
    let minCandidates = 10, bestIdx = -1;
    for (let i=0;i<81;i++) { if (g[i]===0) { const r=Math.floor(i/9), c=i%9; let n=0; for (let v=1;v<=9;v++) if (isValid(r,c,v)) n++; if (n===0) return false; if (n<minCandidates) { minCandidates=n; bestIdx=i; if (n===1) break; } } }
    if (bestIdx===-1) return true;
    const r=Math.floor(bestIdx/9), c=bestIdx%9;
    for (let v=1;v<=9;v++) { if (isValid(r,c,v)) { g[bestIdx]=v; if (solve()) return true; g[bestIdx]=0; } }
    return false;
  }
  if (!solve()) return null;
  return g;
}

function validateFullGrid(grid) {
  for (let r=0;r<9;r++) { const s=new Set(); for (let c=0;c<9;c++) { const v=grid[r*9+c]; if (v<1||v>9||s.has(v)) return false; s.add(v); } }
  for (let c=0;c<9;c++) { const s=new Set(); for (let r=0;r<9;r++) { const v=grid[r*9+c]; if (s.has(v)) return false; s.add(v); } }
  for (let br=0;br<3;br++) for (let bc=0;bc<3;bc++) { const s=new Set(); for (let dr=0;dr<3;dr++) for (let dc=0;dc<3;dc++) { const v=grid[(br*3+dr)*9+bc*3+dc]; if (s.has(v)) return false; s.add(v); } }
  return true;
}

function fixAndFillGridPixelOnly(grid, sigArray, templates, gray, width, bbox, isDark, bg) {
  let g = grid.slice();
  const boardL=bbox.left, boardT=bbox.top, boardR=bbox.right, boardB=bbox.bottom;
  const boardW=boardR-boardL, boardH=boardB-boardT;
  for (let round=0;round<FIX_MAX_ROUNDS;round++) {
    const conflicts = findConflictCells(g);
    if (conflicts.size === 0) break;
    let changed = false;
    for (const idx of conflicts) {
      const r=Math.floor(idx/9), c=idx%9, cur=g[idx];
      const curConflicts = conflictCountAfterSet(g, idx, cur);
      const alternatives = [];
      for (let d=1;d<=9;d++) { if (d===cur) continue; if (isConfusablePair(d, cur)) { const sig=sigArray[idx]; if (sig!==null) { const rec=recognizeDigit(sig,templates); if (rec===d) { const cc=conflictCountAfterSet(g,idx,d); alternatives.push({digit:d,conflicts:cc,isConfusable:true}); } } } }
      alternatives.sort((a,b)=>a.conflicts-b.conflicts);
      if (alternatives.length>0 && alternatives[0].conflicts<curConflicts) { g[idx]=alternatives[0].digit; changed=true; }
    }
    if (!changed) {
      for (const idx of conflicts) {
        const r=Math.floor(idx/9), c=idx%9, cur=g[idx];
        const curConflicts = conflictCountAfterSet(g, idx, cur);
        let bestAlt=null, bestScore=-1;
        for (let d=1;d<=9;d++) { if (d===cur) continue; if (!isConfusablePair(d, cur)) continue; const cc=conflictCountAfterSet(g,idx,d); if (cc<curConflicts) { const sig=sigArray[idx]; if (sig!==null) { const prevConf=g_lastConfidence; recognizeDigit(sig,templates); const sc=g_lastConfidence; if (sc>bestScore) { bestScore=sc; bestAlt=d; } } } }
        if (bestAlt!==null) { g[idx]=bestAlt; changed=true; break; }
      }
    }
    if (!changed) break;
  }
  const zeroCount = g.filter(v => v === 0).length;
  if (zeroCount > 30) return g;
  const solved = solveSudoku(g);
  if (solved !== null && validateFullGrid(solved)) return solved;
  return g;
}

function processImage(pixels, width, height, templates) {
  const _t0 = Date.now();
  g_gridLineDetected = false;
  g_preciseGridDetected = false;
  g_gridLineX = new Array(10).fill(0);
  g_gridLineY = new Array(10).fill(0);
  g_gridLineCropTop = new Array(81).fill(0);
  g_gridLineCropBot = new Array(81).fill(0);
  g_gridLineCropLeft = new Array(81).fill(0);
  g_gridLineCropRight = new Array(81).fill(0);

  const bg = bgColor(pixels, width, height);
  const _t1 = Date.now();
  const bbox = findBoardBBox(pixels, width, height, bg);
  const _t2 = Date.now();
  const isDark = bbox.isDark;
  const gray = toGrayArray(pixels, width, height);
  const _t3 = Date.now();
  const boardL = bbox.left, boardT = bbox.top, boardR = bbox.right, boardB = bbox.bottom;
  const boardW = boardR - boardL, boardH = boardB - boardT;

  detectGridLineWidths(gray, width, boardL, boardT, boardR, boardB, isDark, bg);
  const _t4 = Date.now();
  findPreciseGridLines(gray, width, bbox, isDark, bg);
  const _t5 = Date.now();

  const grid = new Array(81).fill(0);
  const sigArray = new Array(81).fill(null);

  for (let r = 0; r < 9; r++) {
    for (let c = 0; c < 9; c++) {
      let cellL, cellT, cellW, cellH;
      if (g_preciseGridDetected) {
        cellL = g_gridLineX[c]; cellT = g_gridLineY[r];
        cellW = g_gridLineX[c + 1] - g_gridLineX[c];
        cellH = g_gridLineY[r + 1] - g_gridLineY[r];
      } else {
        cellW = boardW / 9; cellH = boardH / 9;
        cellL = boardL + c * cellW; cellT = boardT + r * cellH;
      }
      const sig = cellSigFromGray(gray, width, cellL, cellT, cellW, cellH, isDark, bg, r, c);
      let digit = recognizeDigit(sig, templates);
      if (digit === 0 && g_lastRawInkRatio > 0 && g_lastRawInkRatio < MIN_CELL_INK_RATIO) {
        const lowSig = cellSigFromGrayLowThresh(gray, width, cellL, cellT, cellW, cellH, isDark, bg, r, c);
        if (lowSig !== null) {
          const lowDigit = recognizeDigit(lowSig, templates);
          if (lowDigit !== 0) digit = lowDigit;
        }
      }
      if (digit === 0 && g_lastRawInkRatio >= 0 && g_lastRawInkRatio < MIN_CELL_INK_RATIO * 0.5) {
        const thinSig = cellSigFromGrayThin(gray, width, cellL, cellT, cellW, cellH, isDark, bg, r, c);
        if (thinSig !== null) {
          const thinDigit = recognizeDigit(thinSig, templates);
          if (thinDigit !== 0 && g_lastConfidence >= 0.6) digit = thinDigit;
        }
      }
      grid[r * 9 + c] = digit;
      sigArray[r * 9 + c] = sig;
    }
  }
  g_lastSigArray = sigArray;
  const _t6 = Date.now();
  const finalGrid = fixAndFillGridPixelOnly(grid, sigArray, templates, gray, width, bbox, isDark, bg);
  const _t7 = Date.now();
  if (process.env.OCR_TIMING) console.error(`  timing: bg=${_t1-_t0} bbox=${_t2-_t1} gray=${_t3-_t2} gridLine=${_t4-_t3} precise=${_t5-_t4} cells=${_t6-_t5} fix=${_t7-_t6} total=${_t7-_t0}`);
  return finalGrid;
}

function getSigArray() { return g_lastSigArray; }
function getConstants() { return { SIG_ROWS, SIG_COLS, SIG_LEN }; }
module.exports = { processImage, bgColor, toGrayArray, findBoardBBox, cellSigFromGray, cellSigFromGrayLowThresh, cellSigFromGrayThin, recognizeDigit, countInk, getSigArray, getConstants, grayInkPixel };

const EXPECTED_GRID = [
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

async function runTests() {
  const templatePath = path.join(__dirname, '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'digit_templates_extended.json');
  console.log('Loading templates from:', templatePath);
  const tmplData = JSON.parse(fs.readFileSync(templatePath, 'utf8'));
  const templates = tmplData.templates.map(t => ({ digit: t.digit, key: t.key }));
  console.log('Loaded', templates.length, 'templates');

  const imgDir = path.join(__dirname, '..', 'sudoku_test_images');
  const files = fs.readdirSync(imgDir).filter(f => f.endsWith('.png')).sort();
  console.log('Found', files.length, 'test images\n');

  const results = [];
  for (const file of files) {
    const filePath = path.join(imgDir, file);
    try {
      const img = await loadImage(filePath);
      const canvas = createCanvas(img.width, img.height);
      const ctx = canvas.getContext('2d');
      ctx.drawImage(img, 0, 0);
      const imgData = ctx.getImageData(0, 0, img.width, img.height);
      const pixels = imgData.data;

      const grid = processImage(pixels, img.width, img.height, templates);

      let correct = 0, total = 0, digitCorrect = 0, digitTotal = 0;
      const diffs = [];
      for (let i = 0; i < 81; i++) {
        if (EXPECTED_GRID[i] !== 0) { digitTotal++; if (grid[i] === EXPECTED_GRID[i]) digitCorrect++; else diffs.push('R'+Math.floor(i/9+1)+'C'+(i%9+1)+':'+grid[i]+'→'+EXPECTED_GRID[i]); }
        total++; if (grid[i] === EXPECTED_GRID[i]) correct++;
      }
      const pct = (correct / total * 100).toFixed(1);
      const digitPct = (digitTotal > 0 ? digitCorrect / digitTotal * 100 : 0).toFixed(1);
      results.push({ file, correct, total, pct, digitCorrect, digitTotal, digitPct });
      console.log(file.padEnd(35), correct + '/81 (' + pct + '%)  digits: ' + digitCorrect + '/' + digitTotal + ' (' + digitPct + '%)');
      if (diffs.length > 0 && digitPct < 100) console.log('    diff: ' + diffs.join(' '));
    } catch (e) {
      console.error(file, 'ERROR:', e.message);
      results.push({ file, correct: 0, total: 81, pct: '0.0', digitCorrect: 0, digitTotal: 0, digitPct: '0.0', error: e.message });
    }
  }

  console.log('\n' + '='.repeat(80));
  console.log('SUMMARY');
  console.log('='.repeat(80));
  let totalCorrect = 0, grandTotal = 0, totalDigitCorrect = 0, totalDigitTotal = 0;
  for (const r of results) {
    totalCorrect += r.correct; grandTotal += r.total;
    totalDigitCorrect += r.digitCorrect; totalDigitTotal += r.digitTotal;
  }
  console.log('Overall: ' + totalCorrect + '/' + grandTotal + ' (' + (totalCorrect/grandTotal*100).toFixed(1) + '%)');
  console.log('Digits only: ' + totalDigitCorrect + '/' + totalDigitTotal + ' (' + (totalDigitTotal>0?totalDigitCorrect/totalDigitTotal*100:0).toFixed(1) + '%)');
  console.log('Images tested: ' + results.length);
}

if (process.argv.includes('--debug-bbox')) {
  const idx = process.argv.indexOf('--debug-bbox');
  const imagePath = process.argv[idx + 1];
  (async () => {
    const { createCanvas, loadImage } = require('canvas');
    const img = await loadImage(imagePath);
    const canvas = createCanvas(img.width, img.height);
    const ctx = canvas.getContext('2d');
    ctx.drawImage(img, 0, 0);
    const imgData = ctx.getImageData(0, 0, img.width, img.height);
    const pixels = imgData.data;
    const bg = bgColor(pixels, img.width, img.height);
    const gray = toGrayArray(pixels, img.width, img.height);
    const isDark = bg < BG_DARK_THRESHOLD;
    console.log('size:', img.width, 'x', img.height, 'isDark:', isDark, 'bg:', bg.toFixed(1));
    console.log('findBoxLongRun:', JSON.stringify(findBoxLongRun(gray, img.width, img.height, isDark, bg)));
    const bb = findBoardBBox(pixels, img.width, img.height, bg);
    console.log('findBoardBBox:', JSON.stringify(bb));
    console.log('diag:', g_lastBboxDiag);
    console.log('findBBoxAdaptive:', JSON.stringify(findBBoxAdaptive(gray, img.width, img.height, isDark)));
    console.log('findBBoxConservative:', JSON.stringify(findBBoxConservative(gray, img.width, img.height, isDark, bg)));
    console.log('findBoxLongRun:', JSON.stringify(findBoxLongRun(gray, img.width, img.height, isDark, bg)));
  })().catch(e => console.error(e));
} else if (process.argv.includes('--debug-cell')) {
  const idx = process.argv.indexOf('--debug-cell');
  const imagePath = process.argv[idx + 1];
  const row = parseInt(process.argv[idx + 2]);
  const col = parseInt(process.argv[idx + 3]);
  (async () => {
    const { createCanvas, loadImage } = require('canvas');
    const fs = require('fs'), path = require('path');
    const img = await loadImage(imagePath);
    const canvas = createCanvas(img.width, img.height);
    const ctx = canvas.getContext('2d');
    ctx.drawImage(img, 0, 0);
    const imgData = ctx.getImageData(0, 0, img.width, img.height);
    const tmplPath = path.join(__dirname, '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'digit_templates.json');
    const tmplPathExt = path.join(__dirname, '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'digit_templates_extended.json');
    const tmplData = JSON.parse(fs.readFileSync(fs.existsSync(tmplPathExt) ? tmplPathExt : tmplPath, 'utf8'));
    const templates = tmplData.templates.map(t => ({ digit: t.digit, key: t.key }));
    const grid = processImage(imgData.data, img.width, img.height, templates);
    const i = row * 9 + col;
    const sig = g_lastSigArray ? g_lastSigArray[i] : null;
    console.log('R' + (row+1) + 'C' + (col+1) + ' digit=' + grid[i]);
    if (sig) {
      let s = '';
      for (let r2 = 0; r2 < SIG_ROWS; r2++) { for (let c2 = 0; c2 < SIG_COLS; c2++) s += sig[r2*SIG_COLS+c2] ? '#' : '.'; s += '\n'; }
      console.log(s);
      const inkC = countInk(sig);
      console.log('ink=' + inkC);
      for (let d = 1; d <= 9; d++) {
        let best = -100000, bestR = 0, bestP = 0, bestF = 0;
        for (const t of templates) {
          if (t.digit !== d) continue;
          let tplInk = 0, tp = 0;
          for (let j = 0; j < SIG_LEN; j++) { if (t.key[j] === 1) { tplInk++; if (sig[j] === 1) tp++; } }
          const recall = tplInk > 0 ? tp / tplInk : 0;
          const prec = inkC > 0 ? tp / inkC : 0;
          const f1 = (recall + prec) > 0 ? (2 * recall * prec) / (recall + prec) : 0;
          const match = tp + (SIG_LEN - inkC - (tplInk - tp));
    const score = f1 * 1500 + match - (SIG_LEN - match) * TEMPLATE_MISMATCH_PENALTY;
          if (score > best) { best = score; bestR = recall; bestP = prec; bestF = f1; }
        }
        console.log('d=' + d + ' score=' + best.toFixed(1) + ' F1=' + bestF.toFixed(3) + ' R=' + bestR.toFixed(3) + ' P=' + bestP.toFixed(3));
      }
    }
  })().catch(e => console.error(e));
} else if (require.main === module) {
  runTests().catch(e => { console.error('Fatal:', e); process.exit(1); });
}
