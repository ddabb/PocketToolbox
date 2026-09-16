/**
 * 纯 ArkTS GIF89a 编码器（无 UI / 无 @ohos 依赖，可在本地单元测试环境运行）
 * 结构：中位切分颜色量化 + Floyd-Steinberg 抖动(可选) + LZW 压缩
 */

export class GifFrameData {
  width: number = 0;
  height: number = 0;
  /** 帧延迟，单位 1/100 秒 */
  delayCs: number = 0;
  /** RGBA 像素，长度 = width * height * 4 */
  pixels: Uint8Array = new Uint8Array(0);
}

export class GifEncodeOptions {
  /** 0 = 无限循环；N(>0) = 播放 N 次 */
  loopCount: number = 0;
  /** 高清档：启用 Floyd-Steinberg 抖动 */
  dither: boolean = false;
}

class ByteWriter {
  private buf: Uint8Array;
  private len: number = 0;

  constructor(capacity: number) {
    if (capacity < 64) {
      capacity = 64;
    }
    this.buf = new Uint8Array(capacity);
  }

  private ensure(extra: number): void {
    if (this.len + extra <= this.buf.length) {
      return;
    }
    let newCap: number = this.buf.length * 2;
    while (newCap < this.len + extra) {
      newCap *= 2;
    }
    let next: Uint8Array = new Uint8Array(newCap);
    next.set(this.buf.subarray(0, this.len));
    this.buf = next;
  }

  writeByte(value: number): void {
    this.ensure(1);
    this.buf[this.len] = value & 0xFF;
    this.len++;
  }

  writeBytes(bytes: Uint8Array): void {
    this.ensure(bytes.length);
    this.buf.set(bytes, this.len);
    this.len += bytes.length;
  }

  writeAscii(text: string): void {
    this.ensure(text.length);
    for (let i = 0; i < text.length; i++) {
      this.buf[this.len] = text.charCodeAt(i) & 0xFF;
      this.len++;
    }
  }

  writeU16LE(value: number): void {
    this.writeByte(value & 0xFF);
    this.writeByte((value >> 8) & 0xFF);
  }

  getLength(): number {
    return this.len;
  }

  toUint8Array(): Uint8Array {
    return this.buf.slice(0, this.len);
  }
}

class ColorCount {
  color: number = 0; // 0xRRGGBB
  count: number = 0;
}

/** 帧播放顺序：正放 / 倒放 / 来回(首尾帧不重复出现) */
export function buildFrameOrder(count: number, mode: string): number[] {
  let order: number[] = [];
  if (count <= 0) {
    return order;
  }
  if (mode === 'reverse') {
    for (let i = count - 1; i >= 0; i--) {
      order.push(i);
    }
  } else if (mode === 'pingpong') {
    if (count <= 2) {
      for (let i = 0; i < count; i++) {
        order.push(i);
      }
    } else {
      for (let i = 0; i < count; i++) {
        order.push(i);
      }
      for (let i = count - 2; i >= 1; i--) {
        order.push(i);
      }
    }
  } else {
    for (let i = 0; i < count; i++) {
      order.push(i);
    }
  }
  return order;
}

/** 实际帧延迟(1/100s) = 时长(ms) / 倍速，最小 1 */
export function computeDelayCs(durationMs: number, speed: number): number {
  if (!(speed > 0)) {
    speed = 1;
  }
  let cs: number = Math.round(durationMs / speed / 10);
  if (cs < 1) {
    cs = 1;
  }
  return cs;
}

/** 单帧时长覆盖：frameMs > 0 时优先使用单帧值，否则回退全局时长；倍速统一作用于两者 */
export function resolveFrameDelayCs(frameMs: number, globalMs: number, speed: number): number {
  return computeDelayCs(frameMs > 0 ? frameMs : globalMs, speed);
}

function channelValue(packed: number, channel: number): number {
  if (channel === 0) {
    return (packed >> 16) & 0xFF;
  }
  if (channel === 1) {
    return (packed >> 8) & 0xFF;
  }
  return packed & 0xFF;
}

/**
 * 中位切分颜色量化：跨帧采样建立直方图（15-bit 分桶，桶内保存精确色均值），
 * 输出不超过 maxColors 色的调色板(RGB 三元组)。
 */
export function quantizeToPalette(frames: GifFrameData[], maxColors: number): Uint8Array {
  let counts: Uint32Array = new Uint32Array(32768);
  let sumR: Uint32Array = new Uint32Array(32768);
  let sumG: Uint32Array = new Uint32Array(32768);
  let sumB: Uint32Array = new Uint32Array(32768);
  for (let f = 0; f < frames.length; f++) {
    let frame: GifFrameData = frames[f];
    let pixelCount: number = frame.pixels.length >> 2;
    // 采样上限约 26 万像素，防止超大图拖慢量化
    let step: number = Math.max(1, Math.floor(pixelCount / 262144));
    for (let i = 0; i < pixelCount; i += step) {
      let p: number = i * 4;
      if (frame.pixels[p + 3] < 128) {
        continue; // 透明像素不参与调色板
      }
      let r: number = frame.pixels[p];
      let g: number = frame.pixels[p + 1];
      let b: number = frame.pixels[p + 2];
      let key: number = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
      counts[key]++;
      sumR[key] += r;
      sumG[key] += g;
      sumB[key] += b;
    }
  }
  let colors: ColorCount[] = [];
  for (let key = 0; key < 32768; key++) {
    let c: number = counts[key];
    if (c === 0) {
      continue;
    }
    let cc: ColorCount = new ColorCount();
    cc.color =
      (Math.round(sumR[key] / c) << 16) | (Math.round(sumG[key] / c) << 8) | Math.round(sumB[key] / c);
    cc.count = c;
    colors.push(cc);
  }
  if (colors.length === 0) {
    let fallback: Uint8Array = new Uint8Array(3);
    return fallback;
  }
  let boxes: ColorCount[][] = [colors];
  while (boxes.length < maxColors) {
    // 选通道跨度最大的盒子分裂
    let bestBox: number = -1;
    let bestRange: number = 0;
    let bestChannel: number = 0;
    for (let b = 0; b < boxes.length; b++) {
      let box: ColorCount[] = boxes[b];
      if (box.length < 2) {
        continue;
      }
      for (let ch = 0; ch < 3; ch++) {
        let minV: number = 255;
        let maxV: number = 0;
        for (let i = 0; i < box.length; i++) {
          let v: number = channelValue(box[i].color, ch);
          if (v < minV) {
            minV = v;
          }
          if (v > maxV) {
            maxV = v;
          }
        }
        if (maxV - minV > bestRange) {
          bestRange = maxV - minV;
          bestBox = b;
          bestChannel = ch;
        }
      }
    }
    if (bestBox < 0 || bestRange <= 0) {
      break;
    }
    let box: ColorCount[] = boxes[bestBox];
    boxes.splice(bestBox, 1);
    let channel: number = bestChannel;
    box.sort((a: ColorCount, b: ColorCount): number => {
      return channelValue(a.color, channel) - channelValue(b.color, channel);
    });
    let totalCount: number = 0;
    for (let i = 0; i < box.length; i++) {
      totalCount += box[i].count;
    }
    let acc: number = 0;
    let splitAt: number = 1;
    for (let i = 0; i < box.length - 1; i++) {
      acc += box[i].count;
      if (acc * 2 >= totalCount) {
        splitAt = i + 1;
        break;
      }
    }
    let left: ColorCount[] = box.slice(0, splitAt);
    let right: ColorCount[] = box.slice(splitAt);
    boxes.push(left);
    boxes.push(right);
  }
  // 每盒输出计数加权平均色
  let palette: Uint8Array = new Uint8Array(boxes.length * 3);
  for (let b = 0; b < boxes.length; b++) {
    let box: ColorCount[] = boxes[b];
    let sumR: number = 0;
    let sumG: number = 0;
    let sumB: number = 0;
    let sumW: number = 0;
    for (let i = 0; i < box.length; i++) {
      let w: number = box[i].count;
      let c: number = box[i].color;
      sumR += ((c >> 16) & 0xFF) * w;
      sumG += ((c >> 8) & 0xFF) * w;
      sumB += (c & 0xFF) * w;
      sumW += w;
    }
    palette[b * 3] = Math.round(sumR / sumW);
    palette[b * 3 + 1] = Math.round(sumG / sumW);
    palette[b * 3 + 2] = Math.round(sumB / sumW);
  }
  return palette;
}

function nearestPaletteIndex(r: number, g: number, b: number, palette: Uint8Array): number {
  let best: number = 0;
  let bestDist: number = Number.MAX_VALUE;
  let count: number = palette.length / 3;
  for (let i = 0; i < count; i++) {
    let dr: number = palette[i * 3] - r;
    let dg: number = palette[i * 3 + 1] - g;
    let db: number = palette[i * 3 + 2] - b;
    let dist: number = dr * dr + dg * dg + db * db;
    if (dist < bestDist) {
      bestDist = dist;
      best = i;
      if (dist === 0) {
        break;
      }
    }
  }
  return best;
}

function clampChannel(v: number): number {
  if (v < 0) {
    return 0;
  }
  if (v > 255) {
    return 255;
  }
  return Math.round(v);
}

/**
 * 将源帧像素贴到白底画布：支持 0/90/180/270 度旋转，顶左对齐，超出画布部分丢弃。
 * 旋转 90/270 时源帧有效尺寸宽高互换（画布尺寸需由调用方按旋转后尺寸预留）。
 */
export function composeFramePixels(
  srcPx: Uint8Array,
  fw: number,
  fh: number,
  rotation: number,
  canvasW: number,
  canvasH: number
): Uint8Array {
  let px: Uint8Array = new Uint8Array(canvasW * canvasH * 4);
  for (let i: number = 0; i < canvasW * canvasH; i++) {
    let d: number = i * 4;
    px[d] = 255;
    px[d + 1] = 255;
    px[d + 2] = 255;
    px[d + 3] = 255;
  }
  let r: number = ((rotation % 360) + 360) % 360;
  if (r === 90 || r === 270) {
    for (let y: number = 0; y < fh; y++) {
      let srcRow: number = y * fw * 4;
      for (let x: number = 0; x < fw; x++) {
        let s: number = srcRow + x * 4;
        let dx: number = 0;
        let dy: number = 0;
        if (r === 90) {
          dx = fh - 1 - y;
          dy = x;
        } else {
          dx = y;
          dy = fw - 1 - x;
        }
        if (dx >= canvasW || dy >= canvasH) {
          continue;
        }
        let d: number = (dy * canvasW + dx) * 4;
        px[d] = srcPx[s];
        px[d + 1] = srcPx[s + 1];
        px[d + 2] = srcPx[s + 2];
        px[d + 3] = srcPx[s + 3];
      }
    }
    return px;
  }
  let copyH: number = fh < canvasH ? fh : canvasH;
  let copyW: number = fw < canvasW ? fw : canvasW;
  for (let y: number = 0; y < copyH; y++) {
    let srcRow: number = y * fw * 4;
    for (let x: number = 0; x < copyW; x++) {
      let s: number = srcRow + x * 4;
      let d: number = y * canvasW * 4 + x * 4;
      if (r === 180) {
        let ex: number = copyW - 1 - x;
        let ey: number = copyH - 1 - y;
        d = (ey * canvasW + ex) * 4;
      }
      px[d] = srcPx[s];
      px[d + 1] = srcPx[s + 1];
      px[d + 2] = srcPx[s + 2];
      px[d + 3] = srcPx[s + 3];
    }
  }
  return px;
}

/**
 * 将 RGBA 帧映射为调色板索引。近邻搜索使用 15-bit 量化缓存（建议由调用方跨帧共享），
 * 相同 5-bit 色彩空间的颜色只做一次全表搜索。
 */
export function mapFrameToIndices(
  frame: GifFrameData,
  palette: Uint8Array,
  dither: boolean,
  ditherCache?: Int16Array
): Uint8Array {
  let w: number = frame.width;
  let h: number = frame.height;
  let n: number = w * h;
  let indices: Uint8Array = new Uint8Array(n);
  let pixels: Uint8Array = frame.pixels;
  let cache: Int16Array;
  if (ditherCache !== undefined) {
    cache = ditherCache;
  } else {
    cache = new Int16Array(32768);
    cache.fill(-1);
  }
  if (!dither) {
    for (let i = 0; i < n; i++) {
      let p: number = i * 4;
      if (pixels[p + 3] < 128) {
        indices[i] = 0; // 透明统一映射到 0 号色（无透明通道支持时用调色板首色兜底）
        continue;
      }
      let r: number = pixels[p];
      let g: number = pixels[p + 1];
      let b: number = pixels[p + 2];
      let cacheKey: number = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
      let idx: number = cache[cacheKey];
      if (idx < 0) {
        idx = nearestPaletteIndex(r, g, b, palette);
        cache[cacheKey] = idx;
      }
      indices[i] = idx;
    }
    return indices;
  }
  // Floyd-Steinberg 抖动
  let errR: Float32Array = new Float32Array(n);
  let errG: Float32Array = new Float32Array(n);
  let errB: Float32Array = new Float32Array(n);
  for (let y: number = 0; y < h; y++) {
    for (let x: number = 0; x < w; x++) {
      let i: number = y * w + x;
      let p: number = i * 4;
      let r: number = clampChannel(pixels[p] + errR[i]);
      let g: number = clampChannel(pixels[p + 1] + errG[i]);
      let b: number = clampChannel(pixels[p + 2] + errB[i]);
      let cacheKey: number = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
      let idx: number = cache[cacheKey];
      if (idx < 0) {
        idx = nearestPaletteIndex(r, g, b, palette);
        cache[cacheKey] = idx;
      }
      indices[i] = idx;
      let er: number = r - palette[idx * 3];
      let eg: number = g - palette[idx * 3 + 1];
      let eb: number = b - palette[idx * 3 + 2];
      if (x + 1 < w) {
        errR[i + 1] += er * 7 / 16;
        errG[i + 1] += eg * 7 / 16;
        errB[i + 1] += eb * 7 / 16;
      }
      if (y + 1 < h) {
        let below: number = i + w;
        if (x > 0) {
          errR[below - 1] += er * 3 / 16;
          errG[below - 1] += eg * 3 / 16;
          errB[below - 1] += eb * 3 / 16;
        }
        errR[below] += er * 5 / 16;
        errG[below] += eg * 5 / 16;
        errB[below] += eb * 5 / 16;
        if (x + 1 < w) {
          errR[below + 1] += er * 1 / 16;
          errG[below + 1] += eg * 1 / 16;
          errB[below + 1] += eb * 1 / 16;
        }
      }
    }
  }
  return indices;
}

/**
 * GIF LZW 压缩：输出裸比特流（不含子块切分）
 */
export function lzwEncode(indices: Uint8Array, minCodeSize: number): Uint8Array {
  let clearCode: number = 1 << minCodeSize;
  let eoiCode: number = clearCode + 1;
  let writer: ByteWriter = new ByteWriter(1024);
  let codeSize: number = minCodeSize + 1;
  let dict: Map<number, number> = new Map<number, number>();
  let bitBuf: number = 0;
  let bitCnt: number = 0;
  let nextCode: number = eoiCode + 1;

  const emit = (code: number): void => {
    bitBuf |= code << bitCnt;
    bitCnt += codeSize;
    while (bitCnt >= 8) {
      writer.writeByte(bitBuf & 0xFF);
      bitBuf >>= 8;
      bitCnt -= 8;
    }
  };

  emit(clearCode);
  if (indices.length === 0) {
    emit(eoiCode);
    if (bitCnt > 0) {
      writer.writeByte(bitBuf & 0xFF);
    }
    return writer.toUint8Array();
  }
  let prefix: number = indices[0];
  for (let i = 1; i < indices.length; i++) {
    let k: number = indices[i];
    let key: number = (prefix << 8) | k;
    let found: number = dict.get(key) ?? -1;
    if (found >= 0) {
      prefix = found;
      continue;
    }
    emit(prefix);
    dict.set(key, nextCode);
    if (nextCode === 4095) {
      // 表满前最后一步：发出 Clear 并重置字典
      nextCode++;
      emit(clearCode);
      dict.clear();
      codeSize = minCodeSize + 1;
      nextCode = eoiCode + 1;
    } else {
      nextCode++;
      // GIF 事实标准：解码器建表比编码器晚一个条目，因此编码器在
      // nextCode 达到 (1<<codeSize)+1 时才加宽码宽（giflib 约定）
      if (nextCode === (1 << codeSize) + 1 && codeSize < 12) {
        codeSize++;
      }
    }
    prefix = k;
  }
  emit(prefix);
  emit(eoiCode);
  if (bitCnt > 0) {
    writer.writeByte(bitBuf & 0xFF);
  }
  return writer.toUint8Array();
}

function paletteBitsFor(colorCount: number): number {
  let bits: number = 1;
  while ((1 << bits) < colorCount) {
    bits++;
  }
  if (bits < 2) {
    bits = 2;
  }
  if (bits > 8) {
    bits = 8;
  }
  return bits;
}

/**
 * 编码多帧 GIF89a。所有帧必须同尺寸（由调用方归一化）。
 */
export function encodeGif(frames: GifFrameData[], options: GifEncodeOptions): Uint8Array {
  if (frames.length === 0) {
    throw new Error('GifEncoder: frames is empty');
  }
  let width: number = frames[0].width;
  let height: number = frames[0].height;
  for (let i = 0; i < frames.length; i++) {
    if (frames[i].width !== width || frames[i].height !== height) {
      throw new Error('GifEncoder: frame size mismatch');
    }
    if (frames[i].pixels.length !== width * height * 4) {
      throw new Error('GifEncoder: pixel buffer size mismatch');
    }
  }
  let palette: Uint8Array = quantizeToPalette(frames, 256);
  let colorCount: number = palette.length / 3;
  let bits: number = paletteBitsFor(colorCount);
  let tableSize: number = 1 << bits;
  let minCodeSize: number = bits;

  let writer: ByteWriter = new ByteWriter(4096);
  writer.writeAscii('GIF89a');
  writer.writeU16LE(width);
  writer.writeU16LE(height);
  writer.writeByte(0x80 | ((bits - 1) << 4) | (bits - 1));
  writer.writeByte(0); // 背景色索引
  writer.writeByte(0); // 像素宽高比
  // 全局调色板（不足 2^bits 补零）
  writer.writeBytes(palette);
  for (let i = colorCount; i < tableSize; i++) {
    writer.writeByte(0);
    writer.writeByte(0);
    writer.writeByte(0);
  }
  // Netscape 循环块：loopCount=1(播放一次)时不写；0=无限；N=播放 N 次(值 N-1)
  if (options.loopCount !== 1) {
    let loopValue: number = options.loopCount <= 0 ? 0 : options.loopCount - 1;
    writer.writeByte(0x21);
    writer.writeByte(0xFF);
    writer.writeByte(0x0B);
    writer.writeAscii('NETSCAPE2.0');
    writer.writeByte(0x03);
    writer.writeByte(0x01);
    writer.writeU16LE(loopValue);
    writer.writeByte(0);
  }
  let ditherCache: Int16Array = new Int16Array(32768);
  ditherCache.fill(-1);
  for (let f = 0; f < frames.length; f++) {
    let frame: GifFrameData = frames[f];
    let indices: Uint8Array = mapFrameToIndices(frame, palette, options.dither, ditherCache);
    // 图形控制扩展
    writer.writeByte(0x21);
    writer.writeByte(0xF9);
    writer.writeByte(0x04);
    writer.writeByte(0x00);
    writer.writeU16LE(frame.delayCs);
    writer.writeByte(0x00);
    writer.writeByte(0x00);
    // 图像描述符
    writer.writeByte(0x2C);
    writer.writeU16LE(0);
    writer.writeU16LE(0);
    writer.writeU16LE(width);
    writer.writeU16LE(height);
    writer.writeByte(0x00);
    // LZW 图像数据（子块切分，每块最大 255 字节）
    writer.writeByte(minCodeSize);
    let raw: Uint8Array = lzwEncode(indices, minCodeSize);
    let pos: number = 0;
    while (pos < raw.length) {
      let chunk: number = Math.min(255, raw.length - pos);
      writer.writeByte(chunk);
      writer.writeBytes(raw.subarray(pos, pos + chunk));
      pos += chunk;
    }
    writer.writeByte(0);
  }
  writer.writeByte(0x3B);
  return writer.toUint8Array();
}
