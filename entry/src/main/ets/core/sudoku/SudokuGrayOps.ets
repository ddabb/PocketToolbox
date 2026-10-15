import { INK_THRESH, SAUVOLA_K, SAUVOLA_R, BG_SAMPLE_COUNT, SAUVOLA_MIN_DIM } from './SudokuPixelKernel';

import { yieldThread } from './SudokuOCRUtils';

// Cache for per-channel background colors, computed by bgColor() and consumed by toGrayArray().
interface ChannelBg {
  bgR: number;
  bgG: number;
  bgB: number;
}
let g_cachedChannelBg: ChannelBg | null = null;

export function resetChannelBgCache(): void {
  g_cachedChannelBg = null;
}

export function countInk(sig: number[]): number {
  let cnt: number = 0;
  for (let i: number = 0; i < sig.length; i++) {
    if (sig[i] === 1) { cnt++; }
  }
  return cnt;
}

export function isInkPixel(g: number, bg: number, isDark: boolean): boolean {
  if (isDark) { return g > bg + INK_THRESH; }
  return g < bg - INK_THRESH;
}

export async function sauvolaThreshold(
  gray: Float32Array, width: number, height: number,
  cx0: number, cy0: number, cw: number, ch: number,
  isDark: boolean
): Promise<Float32Array | null> {
  const k: number = SAUVOLA_K;
  const R: number = SAUVOLA_R;
  const halfWin: number = Math.max(2, Math.floor(Math.min(cw, ch) / 4));
  const x0: number = Math.floor(cx0);
  const y0: number = Math.floor(cy0);
  const x1: number = Math.floor(cx0 + cw);
  const y1: number = Math.floor(cy0 + ch);
  const w: number = x1 - x0;
  const h: number = y1 - y0;
  if (w < SAUVOLA_MIN_DIM || h < SAUVOLA_MIN_DIM) { return null; }

  const intSum: Float32Array = new Float32Array((w + 1) * (h + 1));
  const intSq: Float32Array = new Float32Array((w + 1) * (h + 1));
  const stride: number = w + 1;
  for (let ly: number = 0; ly < h; ly++) {
    const sy: number = y0 + ly;
    let rSum: number = 0;
    let rSq: number = 0;
    for (let lx: number = 0; lx < w; lx++) {
      const sx: number = x0 + lx;
      let v: number = 0;
      if (sy >= 0 && sy < height && sx >= 0 && sx < width) {
        v = gray[sy * width + sx];
      }
      rSum += v;
      rSq += v * v;
      intSum[(ly + 1) * stride + lx + 1] = rSum + intSum[ly * stride + lx + 1];
      intSq[(ly + 1) * stride + lx + 1] = rSq + intSq[ly * stride + lx + 1];
    }
    if (ly % 16 === 15) { await yieldThread(); }
  }

  const out: Float32Array = new Float32Array(w * h);
  for (let ly: number = 0; ly < h; ly++) {
    for (let lx: number = 0; lx < w; lx++) {
      const top: number = Math.max(0, ly - halfWin);
      const bot: number = Math.min(h - 1, ly + halfWin);
      const left: number = Math.max(0, lx - halfWin);
      const right: number = Math.min(w - 1, lx + halfWin);
      const cnt: number = (bot - top + 1) * (right - left + 1);
      const tR: number = top;
      const tC: number = left;
      const bR: number = bot + 1;
      const bC: number = right + 1;
      const s: number = intSum[bR * stride + bC] - intSum[tR * stride + bC]
        - intSum[bR * stride + tC] + intSum[tR * stride + tC];
      const sq: number = intSq[bR * stride + bC] - intSq[tR * stride + bC]
        - intSq[bR * stride + tC] + intSq[tR * stride + tC];
      const mean: number = s / cnt;
      const variance: number = sq / cnt - mean * mean;
      const std: number = Math.sqrt(Math.max(0, variance));
      const t: number = mean * (1 + k * (std / R - 1));
      const pixelVal: number = gray[(y0 + ly) * width + (x0 + lx)];
      out[ly * w + lx] = isDark ? (pixelVal > t ? 1 : 0) : (pixelVal < t ? 1 : 0);
    }
    if (ly % 16 === 15) { await yieldThread(); }
  }
  return out;
}

export function otsuThreshold(hist: number[], total: number): number {
  let sumAll: number = 0;
  for (let i: number = 0; i < 256; i++) { sumAll += i * hist[i]; }
  let sumBg: number = 0;
  let wBg: number = 0;
  let maxVar: number = -1;
  let threshold: number = 128;
  for (let t: number = 0; t < 256; t++) {
    wBg += hist[t];
    if (wBg === 0) { continue; }
    const wFg: number = total - wBg;
    if (wFg === 0) { break; }
    sumBg += t * hist[t];
    const mBg: number = sumBg / wBg;
    const mFg: number = (sumAll - sumBg) / wFg;
    const diff: number = mBg - mFg;
    const varBetween: number = wBg * wFg * diff * diff;
    if (varBetween > maxVar) { maxVar = varBetween; threshold = t; }
  }
  return threshold;
}

function clamp255(v: number): number { if (v < 0) { return 0; } if (v > 255) { return 255; } return v; }

// 使用缓存的通道背景色计算单像素的颜色对比度灰度值
export function computeContrastPixel(pixels: Uint8Array, off: number): number {
  let bgR: number = 128; let bgG: number = 128; let bgB: number = 128;
  if (g_cachedChannelBg !== null) {
    bgR = g_cachedChannelBg.bgR;
    bgG = g_cachedChannelBg.bgG;
    bgB = g_cachedChannelBg.bgB;
  }
  const dr: number = pixels[off] - bgR;
  const dg: number = pixels[off + 1] - bgG;
  const db: number = pixels[off + 2] - bgB;
  const contrast: number = Math.max(Math.abs(dr), Math.abs(dg), Math.abs(db));
  return clamp255(255 - contrast);
}

export function bgColor(pixels: Uint8Array, width: number, height: number): number {
  // 使用分通道颜色对比度：对每个通道分别统计直方图，取众数作为该通道的背景色。
  // 相比单一亮度值（0.299R+0.587G+0.114B），分通道背景色能正确处理彩色主题
  // （如红色数字浅色背景、蓝色数字深色背景等），避免亮度公式丢失颜色对比度信息。
  const histR: number[] = new Array<number>(256).fill(0);
  const histG: number[] = new Array<number>(256).fill(0);
  const histB: number[] = new Array<number>(256).fill(0);
  const total: number = width * height;
  const step: number = Math.max(1, Math.floor(total / BG_SAMPLE_COUNT));
  for (let i: number = 0; i < total; i += step) {
    const off: number = i * 4;
    let ri: number = pixels[off];
    let gi: number = pixels[off + 1];
    let bi: number = pixels[off + 2];
    if (ri < 0) { ri = 0; } if (ri > 255) { ri = 255; }
    if (gi < 0) { gi = 0; } if (gi > 255) { gi = 255; }
    if (bi < 0) { bi = 0; } if (bi > 255) { bi = 255; }
    histR[ri]++; histG[gi]++; histB[bi]++;
  }
  // 跳过 bin 0 找众数（透明区域/黑边累积在 bin 0）
  let modeR: number = 0; let maxR: number = 0;
  let modeG: number = 0; let maxG: number = 0;
  let modeB: number = 0; let maxB: number = 0;
  for (let i: number = 1; i < 256; i++) {
    if (histR[i] > maxR) { maxR = histR[i]; modeR = i; }
    if (histG[i] > maxG) { maxG = histG[i]; modeG = i; }
    if (histB[i] > maxB) { maxB = histB[i]; modeB = i; }
  }
  // 缓存供 toGrayArray 复用
  g_cachedChannelBg = { bgR: modeR, bgG: modeG, bgB: modeB };
  // 返回反转对比度的 bg：在颜色对比度方案中，所有背景像素映射到接近255的位置
  return 255;
}

export function toGrayArray(pixels: Uint8Array, width: number, height: number): Float32Array {
  let bgR: number = 128; let bgG: number = 128; let bgB: number = 128;
  if (g_cachedChannelBg !== null) {
    bgR = g_cachedChannelBg.bgR;
    bgG = g_cachedChannelBg.bgG;
    bgB = g_cachedChannelBg.bgB;
  }
  const len: number = width * height;
  const gray: Float32Array = new Float32Array(len);
  for (let i: number = 0; i < len; i++) {
    const off: number = i * 4;
    let dr: number = pixels[off] - bgR;
    let dg: number = pixels[off + 1] - bgG;
    let db: number = pixels[off + 2] - bgB;
    if (dr < 0) { dr = -dr; }
    if (dg < 0) { dg = -dg; }
    if (db < 0) { db = -db; }
    let contrast: number = dr;
    if (dg > contrast) { contrast = dg; }
    if (db > contrast) { contrast = db; }
    let v: number = 255 - contrast;
    if (v < 0) { v = 0; } else if (v > 255) { v = 255; }
    gray[i] = v;
  }
  return gray;
}

export function boxBlur(gray: Float32Array, W: number, H: number, radius: number): Float32Array {
  const out: Float32Array = new Float32Array(W * H);
  const tmp: Float32Array = new Float32Array(W * H);
  const k: number = 2 * radius + 1;
  for (let y: number = 0; y < H; y++) {
    let sum: number = 0;
    for (let x: number = 0; x < k; x++) {
      sum += gray[y * W + Math.min(x, W - 1)];
    }
    for (let x: number = 0; x < W; x++) {
      tmp[y * W + x] = sum / k;
      sum -= gray[y * W + Math.max(0, Math.min(W - 1, x - radius))];
      sum += gray[y * W + Math.max(0, Math.min(W - 1, x + radius + 1))];
    }
  }
  for (let x: number = 0; x < W; x++) {
    let sum: number = 0;
    for (let y: number = 0; y < k; y++) {
      sum += tmp[Math.min(y, H - 1) * W + x];
    }
    for (let y: number = 0; y < H; y++) {
      out[y * W + x] = sum / k;
      sum -= tmp[Math.max(0, Math.min(H - 1, y - radius)) * W + x];
      sum += tmp[Math.max(0, Math.min(H - 1, y + radius + 1)) * W + x];
    }
  }
  return out;
}

export function dilate3x3(binary: Uint8Array, W: number, H: number): Uint8Array {
  const out: Uint8Array = new Uint8Array(W * H);
  for (let y: number = 0; y < H; y++) {
    for (let x: number = 0; x < W; x++) {
      let m: number = 0;
      const y0: number = Math.max(0, y - 1);
      const y1: number = Math.min(H - 1, y + 1);
      const x0: number = Math.max(0, x - 1);
      const x1: number = Math.min(W - 1, x + 1);
      for (let ny: number = y0; ny <= y1; ny++) {
        for (let nx: number = x0; nx <= x1; nx++) {
          if (binary[ny * W + nx] > m) { m = binary[ny * W + nx]; }
        }
      }
      out[y * W + x] = m;
    }
  }
  return out;
}

function erode3x3(binary: Uint8Array, W: number, H: number): Uint8Array {
  const out: Uint8Array = new Uint8Array(W * H);
  for (let y: number = 0; y < H; y++) {
    for (let x: number = 0; x < W; x++) {
      let m: number = 1;
      const y0: number = Math.max(0, y - 1);
      const y1: number = Math.min(H - 1, y + 1);
      const x0: number = Math.max(0, x - 1);
      const x1: number = Math.min(W - 1, x + 1);
      for (let ny: number = y0; ny <= y1; ny++) {
        for (let nx: number = x0; nx <= x1; nx++) {
          if (binary[ny * W + nx] < m) { m = binary[ny * W + nx]; }
        }
      }
      out[y * W + x] = m;
    }
  }
  return out;
}

export function morphOpen3x3(binary: Uint8Array, W: number, H: number): Uint8Array {
  return dilate3x3(erode3x3(binary, W, H), W, H);
}

export function grayInkPixel(g: number, bg: number, isDark: boolean, thresh: number): boolean {
  if (isDark) { return g > bg + thresh; }
  return g < bg - thresh;
}
