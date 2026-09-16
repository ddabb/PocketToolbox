/**
 * 纯 ArkTS GIF89a 解析器（无 UI / 无 @ohos 依赖，可在本地单元测试环境运行）
 * 能力：文件头/逻辑屏幕/全局调色板、GCE 帧延迟与透明索引、Netscape 循环次数、
 * 局部调色板、隔行帧反交织、LZW 解码、按 disposal 方法逐帧合成（合成到白底画布）。
 * 附加：RGBA 双线性缩放与 BGRA/RGBA 通道交换（供 GIF/视频帧导入使用）。
 */

export class GifParsedFrame {
  /** 合成后的画布像素 RGBA（白底不透明），尺寸为画布宽高 */
  pixels: Uint8Array = new Uint8Array(0);
  /** 帧延迟，单位 1/100 秒 */
  delayCs: number = 0;
}

export class GifParseResult {
  width: number = 0;
  height: number = 0;
  /** 0=无限循环；N(>0)=播放 N 次；无 Netscape 块时为 1（播放一次） */
  loopCount: number = 1;
  frames: GifParsedFrame[] = [];
}

class SubBlockData {
  bytes: Uint8Array = new Uint8Array(0);
  endPos: number = 0;
}

function readSubBlocks(data: Uint8Array, pos: number): SubBlockData {
  let result: SubBlockData = new SubBlockData();
  let chunks: Uint8Array[] = [];
  let total: number = 0;
  let p: number = pos;
  while (p < data.length) {
    let len: number = data[p];
    p++;
    if (len === 0) {
      result.bytes = new Uint8Array(total);
      let o: number = 0;
      for (let i = 0; i < chunks.length; i++) {
        result.bytes.set(chunks[i], o);
        o += chunks[i].length;
      }
      result.endPos = p;
      return result;
    }
    if (p + len > data.length) {
      throw new Error('GIF: 数据截断');
    }
    chunks.push(data.slice(p, p + len));
    total += len;
    p += len;
  }
  throw new Error('GIF: 数据截断');
}

function skipSubBlocks(data: Uint8Array, pos: number): number {
  let p: number = pos;
  while (p < data.length) {
    let len: number = data[p];
    p++;
    if (len === 0) {
      return p;
    }
    p += len;
  }
  throw new Error('GIF: 数据截断');
}

/**
 * GIF LZW 解码（与事实标准编码器配套：解码器建表比编码器晚一个条目，
 * 码宽在 nextCode 达到 2^codeSize 时加宽）
 */
function lzwDecode(data: Uint8Array, minCodeSize: number, maxPixels: number): Uint8Array {
  let clearCode: number = 1 << minCodeSize;
  let eoiCode: number = clearCode + 1;
  let codeSize: number = minCodeSize + 1;
  let nextCode: number = eoiCode + 1;
  let prefix: Int32Array = new Int32Array(4096);
  let suffix: Int32Array = new Int32Array(4096);
  let stack: Int32Array = new Int32Array(4096);
  let output: Uint8Array = new Uint8Array(maxPixels);
  let outLen: number = 0;
  let bitBuf: number = 0;
  let bitCnt: number = 0;
  let pos: number = 0;
  let prev: number = -1;

  while (outLen < maxPixels) {
    while (bitCnt < codeSize) {
      if (pos >= data.length) {
        return output.subarray(0, outLen);
      }
      bitBuf |= data[pos] << bitCnt;
      pos++;
      bitCnt += 8;
    }
    let code: number = bitBuf & ((1 << codeSize) - 1);
    bitBuf >>>= codeSize;
    bitCnt -= codeSize;
    if (code === eoiCode) {
      break;
    }
    if (code === clearCode) {
      codeSize = minCodeSize + 1;
      nextCode = eoiCode + 1;
      prev = -1;
      continue;
    }
    if (prev < 0) {
      if (code >= clearCode) {
        throw new Error('GIF: 非法首码');
      }
      output[outLen] = code;
      outLen++;
      prev = code;
      continue;
    }
    let first: number = -1;
    if (code < nextCode) {
      // 常规码：展开并记录首字节
      let depth: number = 0;
      let c: number = code;
      while (c >= clearCode + 2) {
        stack[depth] = suffix[c];
        depth++;
        c = prefix[c];
      }
      first = c;
      stack[depth] = c;
      depth++;
      if (outLen + depth > maxPixels) {
        throw new Error('GIF: 图像数据超出声明尺寸');
      }
      for (let i = depth - 1; i >= 0; i--) {
        output[outLen] = stack[i];
        outLen++;
      }
    } else if (code === nextCode) {
      // KwKwK 情形：展开 prev 并补上其首字节（首字节追加在末尾）
      let depth: number = 0;
      let c: number = prev;
      while (c >= clearCode + 2) {
        stack[depth] = suffix[c];
        depth++;
        c = prefix[c];
      }
      first = c;
      stack[depth] = c;
      depth++;
      stack[depth] = c;
      depth++;
      if (outLen + depth > maxPixels) {
        throw new Error('GIF: 图像数据超出声明尺寸');
      }
      for (let i = depth - 1; i >= 0; i--) {
        output[outLen] = stack[i];
        outLen++;
      }
    } else {
      throw new Error('GIF: 非法编码');
    }
    prefix[nextCode] = prev;
    suffix[nextCode] = first;
    nextCode++;
    prev = code;
    if (nextCode === (1 << codeSize) && codeSize < 12) {
      codeSize++;
    }
  }
  return output.subarray(0, outLen);
}

/** 隔行 GIF 的行流顺序：4 趟扫描（0/8、4/8、2/4、1/2），返回流位置 k 对应的图像行号 */
function interlaceRowOrder(height: number): number[] {
  let order: number[] = [];
  let passes: number[][] = [[0, 8], [4, 8], [2, 4], [1, 2]];
  for (let i = 0; i < passes.length; i++) {
    let start: number = passes[i][0];
    let step: number = passes[i][1];
    for (let y = start; y < height; y += step) {
      order.push(y);
    }
  }
  return order;
}

/**
 * 解析 GIF89a 字节流并逐帧合成。合成画布为白底不透明；disposal 2 清回白底，
 * disposal 3 还原上一画布。透明索引像素不落笔（保留画布底色）。
 * 解析失败抛出 Error（调用方负责提示，不崩溃）。
 */
export function parseGif(data: Uint8Array): GifParseResult {
  if (data.length < 13) {
    throw new Error('GIF: 文件过小');
  }
  if (data[0] !== 0x47 || data[1] !== 0x49 || data[2] !== 0x46 || data[3] !== 0x38) {
    throw new Error('GIF: 不是有效的 GIF 文件');
  }
  let width: number = data[6] | (data[7] << 8);
  let height: number = data[8] | (data[9] << 8);
  if (width <= 0 || height <= 0) {
    throw new Error('GIF: 画布尺寸非法');
  }
  let maxPixels: number = width * height;
  if (maxPixels > 64 * 1024 * 1024) {
    throw new Error('GIF: 画布过大');
  }
  let result: GifParseResult = new GifParseResult();
  result.width = width;
  result.height = height;
  let packed: number = data[10];
  let pos: number = 13;
  let gct: Uint8Array | null = null;
  if ((packed & 0x80) !== 0) {
    let n: number = 2 << (packed & 0x07);
    if (pos + n * 3 > data.length) {
      throw new Error('GIF: 数据截断');
    }
    gct = data.slice(pos, pos + n * 3);
    pos += n * 3;
  }
  let canvas: Uint8Array = new Uint8Array(maxPixels * 4);
  for (let i = 0; i < maxPixels; i++) {
    let d: number = i * 4;
    canvas[d] = 255;
    canvas[d + 1] = 255;
    canvas[d + 2] = 255;
    canvas[d + 3] = 255;
  }
  let delayCs: number = 0;
  let transparentIdx: number = -1;
  let disposal: number = 0;
  while (pos < data.length) {
    let blockType: number = data[pos];
    pos++;
    if (blockType === 0x3B) {
      break;
    }
    if (blockType === 0x21) {
      // 扩展块
      if (pos >= data.length) {
        throw new Error('GIF: 数据截断');
      }
      let label: number = data[pos];
      pos++;
      if (label === 0xF9) {
        // 图形控制扩展
        if (pos >= data.length) {
          throw new Error('GIF: 数据截断');
        }
        let blockSize: number = data[pos];
        pos++;
        if (blockSize < 4 || pos + blockSize > data.length) {
          throw new Error('GIF: 图形控制扩展损坏');
        }
        let gcePacked: number = data[pos];
        disposal = (gcePacked >> 2) & 0x07;
        delayCs = data[pos + 1] | (data[pos + 2] << 8);
        transparentIdx = (gcePacked & 0x01) !== 0 ? data[pos + 3] : -1;
        pos += blockSize;
        pos = skipSubBlocks(data, pos);
      } else if (label === 0xFF) {
        // 应用扩展（识别 NETSCAPE2.0 循环块）
        if (pos >= data.length) {
          throw new Error('GIF: 数据截断');
        }
        let idSize: number = data[pos];
        pos++;
        if (pos + idSize > data.length) {
          throw new Error('GIF: 数据截断');
        }
        let appId: string = '';
        for (let i = 0; i < idSize; i++) {
          appId += String.fromCharCode(data[pos + i]);
        }
        pos += idSize;
        if (appId === 'NETSCAPE2.0') {
          while (pos < data.length && data[pos] !== 0) {
            let len: number = data[pos];
            pos++;
            if (pos + len > data.length) {
              throw new Error('GIF: 数据截断');
            }
            if (len >= 3 && data[pos] === 0x01) {
              let v: number = data[pos + 1] | (data[pos + 2] << 8);
              result.loopCount = v === 0 ? 0 : v + 1;
            }
            pos += len;
          }
          if (pos >= data.length) {
            throw new Error('GIF: 数据截断');
          }
          pos++;
        } else {
          pos = skipSubBlocks(data, pos);
        }
      } else {
        // 注释 / 纯文本等：跳过
        pos = skipSubBlocks(data, pos);
      }
      continue;
    }
    if (blockType === 0x2C) {
      // 图像描述符
      if (pos + 9 > data.length) {
        throw new Error('GIF: 数据截断');
      }
      let left: number = data[pos] | (data[pos + 1] << 8);
      let top: number = data[pos + 2] | (data[pos + 3] << 8);
      let fw: number = data[pos + 4] | (data[pos + 5] << 8);
      let fh: number = data[pos + 6] | (data[pos + 7] << 8);
      let descPacked: number = data[pos + 8];
      pos += 9;
      if (fw <= 0 || fh <= 0) {
        throw new Error('GIF: 帧尺寸非法');
      }
      let lct: Uint8Array | null = null;
      if ((descPacked & 0x80) !== 0) {
        let n: number = 2 << (descPacked & 0x07);
        if (pos + n * 3 > data.length) {
          throw new Error('GIF: 数据截断');
        }
        lct = data.slice(pos, pos + n * 3);
        pos += n * 3;
      }
      let interlaced: boolean = (descPacked & 0x40) !== 0;
      if (pos >= data.length) {
        throw new Error('GIF: 数据截断');
      }
      let minCodeSize: number = data[pos];
      pos++;
      if (minCodeSize < 2 || minCodeSize > 8) {
        throw new Error('GIF: 非法最小码宽');
      }
      let sub: SubBlockData = readSubBlocks(data, pos);
      pos = sub.endPos;
      let indices: Uint8Array = lzwDecode(sub.bytes, minCodeSize, fw * fh);
      if (indices.length < fw * fh) {
        throw new Error('GIF: 图像数据不完整');
      }
      let palette: Uint8Array | null = lct !== null ? lct : gct;
      if (palette === null) {
        throw new Error('GIF: 缺少调色板');
      }
      let paletteCount: number = palette.length / 3;
      let rowOrder: number[] = interlaced ? interlaceRowOrder(fh) : [];
      let savedBefore: Uint8Array | null = disposal === 3 ? canvas.slice() : null;
      for (let streamRow = 0; streamRow < fh; streamRow++) {
        let y: number = interlaced ? rowOrder[streamRow] : streamRow;
        let dstY: number = top + y;
        if (dstY >= height) {
          continue;
        }
        let srcBase: number = streamRow * fw;
        for (let x = 0; x < fw; x++) {
          let dstX: number = left + x;
          if (dstX >= width) {
            continue;
          }
          let idx: number = indices[srcBase + x];
          if (idx === transparentIdx || idx >= paletteCount) {
            continue;
          }
          let d: number = (dstY * width + dstX) * 4;
          canvas[d] = palette[idx * 3];
          canvas[d + 1] = palette[idx * 3 + 1];
          canvas[d + 2] = palette[idx * 3 + 2];
          canvas[d + 3] = 255;
        }
      }
      let frame: GifParsedFrame = new GifParsedFrame();
      frame.pixels = canvas.slice();
      frame.delayCs = delayCs;
      result.frames.push(frame);
      // 处理当前帧的 disposal（影响下一帧的画布）
      if (disposal === 2) {
        let clearBottom: number = Math.min(top + fh, height);
        let clearRight: number = Math.min(left + fw, width);
        for (let y = top; y < clearBottom; y++) {
          for (let x = left; x < clearRight; x++) {
            let d: number = (y * width + x) * 4;
            canvas[d] = 255;
            canvas[d + 1] = 255;
            canvas[d + 2] = 255;
            canvas[d + 3] = 255;
          }
        }
      } else if (disposal === 3 && savedBefore !== null) {
        canvas.set(savedBefore);
      }
      delayCs = 0;
      transparentIdx = -1;
      disposal = 0;
      continue;
    }
    throw new Error('GIF: 无法识别的数据块 0x' + blockType.toString(16));
  }
  if (result.frames.length === 0) {
    throw new Error('GIF: 未找到帧数据');
  }
  return result;
}

/**
 * RGBA 双线性缩放（用于 GIF/视频帧导入时限制长边尺寸、导出时降档）
 */
export function resizeRgba(src: Uint8Array, sw: number, sh: number, tw: number, th: number): Uint8Array {
  if (tw <= 0 || th <= 0 || sw <= 0 || sh <= 0) {
    throw new Error('resizeRgba: 非法尺寸');
  }
  if (tw === sw && th === sh) {
    return src.slice();
  }
  let out: Uint8Array = new Uint8Array(tw * th * 4);
  let xRatio: number = sw / tw;
  let yRatio: number = sh / th;
  for (let y = 0; y < th; y++) {
    let sy: number = (y + 0.5) * yRatio - 0.5;
    let fy0: number = Math.floor(sy);
    let fy: number = sy - fy0;
    if (fy0 < 0) {
      fy0 = 0;
      fy = 0;
    }
    if (fy0 > sh - 1) {
      fy0 = sh - 1;
      fy = 0;
    }
    let y0: number = fy0;
    let y1: number = fy0 + 1 < sh ? fy0 + 1 : fy0;
    for (let x = 0; x < tw; x++) {
      let sx: number = (x + 0.5) * xRatio - 0.5;
      let fx0: number = Math.floor(sx);
      let fx: number = sx - fx0;
      if (fx0 < 0) {
        fx0 = 0;
        fx = 0;
      }
      if (fx0 > sw - 1) {
        fx0 = sw - 1;
        fx = 0;
      }
      let x0: number = fx0;
      let x1: number = fx0 + 1 < sw ? fx0 + 1 : fx0;
      let d: number = (y * tw + x) * 4;
      for (let c = 0; c < 4; c++) {
        let p00: number = src[(y0 * sw + x0) * 4 + c];
        let p01: number = src[(y0 * sw + x1) * 4 + c];
        let p10: number = src[(y1 * sw + x0) * 4 + c];
        let p11: number = src[(y1 * sw + x1) * 4 + c];
        let topv: number = p00 + (p01 - p00) * fx;
        let botv: number = p10 + (p11 - p10) * fx;
        let v: number = topv + (botv - topv) * fy;
        out[d + c] = Math.round(v);
      }
    }
  }
  return out;
}

/** BGRA ↔ RGBA 通道交换（视频抽帧返回 BGRA 时转换） */
export function swapBgraRgba(px: Uint8Array): Uint8Array {
  let out: Uint8Array = px.slice();
  for (let i = 0; i < out.length; i += 4) {
    let b: number = out[i];
    out[i] = out[i + 2];
    out[i + 2] = b;
  }
  return out;
}
