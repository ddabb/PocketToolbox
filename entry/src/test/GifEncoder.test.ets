import { describe, it, expect } from '@ohos/hypium';
import {
  GifFrameData,
  GifEncodeOptions,
  encodeGif,
  lzwEncode,
  quantizeToPalette,
  mapFrameToIndices,
  buildFrameOrder,
  computeDelayCs,
  resolveFrameDelayCs,
  composeFramePixels
} from '../main/ets/core/gif/GifEncoder';

/** 2×2 标记帧，R 通道标记位置：TL=1 TR=2 BL=3 BR=4 */
function markerFrame(): Uint8Array {
  let src: Uint8Array = new Uint8Array(16);
  let marks: number[] = [1, 2, 3, 4];
  for (let i = 0; i < 4; i++) {
    src[i * 4] = marks[i];
    src[i * 4 + 3] = 255;
  }
  return src;
}

function markerAt(px: Uint8Array, canvasW: number, x: number, y: number): number {
  let p: number = (y * canvasW + x) * 4;
  return (px[p] << 16) | (px[p + 1] << 8) | px[p + 2];
}

/**
 * 测试内置的独立 GIF LZW 解码器（按规范独立实现，用于回环校验编码器）
 */
function lzwDecodeForTest(data: Uint8Array, minCodeSize: number, maxPixels: number): Uint8Array {
  let clearCode: number = 1 << minCodeSize;
  let eoiCode: number = clearCode + 1;
  let codeSize: number = minCodeSize + 1;
  let nextCode: number = eoiCode + 1;
  let prefix: number[] = [];
  let suffix: number[] = [];
  let output: number[] = [];
  let bitBuf: number = 0;
  let bitCnt: number = 0;
  let pos: number = 0;
  let prev: number = -1;

  const readCode = (): number => {
    while (bitCnt < codeSize) {
      if (pos >= data.length) {
        return eoiCode;
      }
      bitBuf |= data[pos] << bitCnt;
      pos++;
      bitCnt += 8;
    }
    let code: number = bitBuf & ((1 << codeSize) - 1);
    bitBuf >>= codeSize;
    bitCnt -= codeSize;
    return code;
  };

  const emitEntry = (code: number): number => {
    // 回溯收集后正向输出
    let stack: number[] = [];
    let c: number = code;
    let first: number = -1;
    while (c >= clearCode + 2) {
      stack.push(suffix[c]);
      c = prefix[c];
    }
    first = c;
    stack.push(c);
    for (let i = stack.length - 1; i >= 0; i--) {
      output.push(stack[i]);
    }
    return first;
  };

  while (output.length < maxPixels) {
    let code: number = readCode();
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
      // 第一个码必为根色
      output.push(code);
      prev = code;
      continue;
    }
    if (code < nextCode) {
      let first: number = emitEntry(code);
      prefix[nextCode] = prev;
      suffix[nextCode] = first;
      nextCode++;
    } else {
      // KwKwK 情形
      let firstPrev: number = emitEntry(prev);
      output.push(firstPrev);
      prefix[nextCode] = prev;
      suffix[nextCode] = firstPrev;
      nextCode++;
    }
    prev = code;
    if (nextCode === (1 << codeSize) && codeSize < 12) {
      codeSize++;
    }
  }
  return Uint8Array.from(output);
}

function makeFrame(width: number, height: number, delayCs: number, colors: number[][]): GifFrameData {
  let frame: GifFrameData = new GifFrameData();
  frame.width = width;
  frame.height = height;
  frame.delayCs = delayCs;
  let pixels: Uint8Array = new Uint8Array(width * height * 4);
  let k: number = 0;
  for (let i = 0; i < width * height; i++) {
    let c: number[] = colors[i % colors.length];
    pixels[k++] = c[0];
    pixels[k++] = c[1];
    pixels[k++] = c[2];
    pixels[k++] = 255;
  }
  frame.pixels = pixels;
  return frame;
}

function indexOfBytes(haystack: Uint8Array, needle: number[]): number {
  outer: for (let i = 0; i <= haystack.length - needle.length; i++) {
    for (let j = 0; j < needle.length; j++) {
      if (haystack[i + j] !== needle[j]) {
        continue outer;
      }
    }
    return i;
  }
  return -1;
}

function asciiBytes(s: string): number[] {
  let arr: number[] = [];
  for (let i = 0; i < s.length; i++) {
    arr.push(s.charCodeAt(i));
  }
  return arr;
}

export default function gifEncoderTest() {
  describe('GifLogic', () => {
    it('buildFrameOrder_forward', 0, () => {
      let order: number[] = buildFrameOrder(4, 'forward');
      expect(order.join(',')).assertEqual('0,1,2,3');
    });

    it('buildFrameOrder_reverse', 0, () => {
      let order: number[] = buildFrameOrder(4, 'reverse');
      expect(order.join(',')).assertEqual('3,2,1,0');
    });

    it('buildFrameOrder_pingpong_no_adjacent_duplicate', 0, () => {
      let order: number[] = buildFrameOrder(4, 'pingpong');
      expect(order.join(',')).assertEqual('0,1,2,3,2,1');
      let order2: number[] = buildFrameOrder(2, 'pingpong');
      expect(order2.join(',')).assertEqual('0,1');
      let order3: number[] = buildFrameOrder(1, 'pingpong');
      expect(order3.join(',')).assertEqual('0');
    });

    it('computeDelayCs_basic_and_speed', 0, () => {
      expect(computeDelayCs(500, 1)).assertEqual(50);
      expect(computeDelayCs(500, 2)).assertEqual(25);
      expect(computeDelayCs(500, 4)).assertEqual(13);
      expect(computeDelayCs(500, 0.25)).assertEqual(200);
    });

    it('computeDelayCs_minimum_one_centisecond', 0, () => {
      expect(computeDelayCs(50, 4)).assertEqual(1);
    });

    it('resolveFrameDelayCs_fallback_and_override', 0, () => {
      // 单帧时长为 0 时回退到全局值
      expect(resolveFrameDelayCs(0, 500, 1)).assertEqual(50);
      // 单帧时长覆盖全局值
      expect(resolveFrameDelayCs(300, 500, 1)).assertEqual(30);
      // 覆盖值同样受倍速影响
      expect(resolveFrameDelayCs(400, 500, 4)).assertEqual(10);
      expect(resolveFrameDelayCs(0, 500, 0.25)).assertEqual(200);
      // 最小 1cs
      expect(resolveFrameDelayCs(50, 500, 4)).assertEqual(1);
    });
  });

  describe('GifLzw', () => {
    it('lzw_single_color_roundtrip', 0, () => {
      let indices: Uint8Array = new Uint8Array(100);
      indices.fill(3);
      let encoded: Uint8Array = lzwEncode(indices, 8);
      let decoded: Uint8Array = lzwDecodeForTest(encoded, 8, 100);
      expect(decoded.length).assertEqual(100);
      let same: boolean = true;
      for (let i = 0; i < 100; i++) {
        if (decoded[i] !== 3) {
          same = false;
        }
      }
      expect(same).assertTrue();
    });

    it('lzw_sequential_256_roundtrip', 0, () => {
      let indices: Uint8Array = new Uint8Array(256);
      for (let i = 0; i < 256; i++) {
        indices[i] = i;
      }
      let encoded: Uint8Array = lzwEncode(indices, 8);
      let decoded: Uint8Array = lzwDecodeForTest(encoded, 8, 256);
      expect(decoded.length).assertEqual(256);
      let same: boolean = true;
      for (let i = 0; i < 256; i++) {
        if (decoded[i] !== indices[i]) {
          same = false;
        }
      }
      expect(same).assertTrue();
    });

    it('lzw_long_repeating_pattern_triggers_dict_reset', 0, () => {
      // 大量重复序列驱动字典到达 4096 触发 Clear 重置
      let n: number = 20000;
      let indices: Uint8Array = new Uint8Array(n);
      let pattern: number[] = [7, 8, 9, 10, 11, 12, 13, 14, 15, 16];
      for (let i = 0; i < n; i++) {
        indices[i] = pattern[i % pattern.length];
      }
      let encoded: Uint8Array = lzwEncode(indices, 8);
      let decoded: Uint8Array = lzwDecodeForTest(encoded, 8, n);
      expect(decoded.length).assertEqual(n);
      let same: boolean = true;
      for (let i = 0; i < n; i++) {
        if (decoded[i] !== indices[i]) {
          same = false;
        }
      }
      expect(same).assertTrue();
      // 压缩应显著小于原数据
      expect(encoded.length < n).assertTrue();
    });

    it('lzw_empty_input_produces_terminating_codes', 0, () => {
      let encoded: Uint8Array = lzwEncode(new Uint8Array(0), 2);
      expect(encoded.length > 0).assertTrue();
    });
  });

  describe('GifQuantize', () => {
    it('quantize_two_colors_exact_palette', 0, () => {
      let red: number[] = [255, 0, 0];
      let blue: number[] = [0, 0, 255];
      let frame: GifFrameData = makeFrame(4, 4, 5, [red, blue]);
      let frames: GifFrameData[] = [frame];
      let palette: Uint8Array = quantizeToPalette(frames, 256);
      expect(palette.length).assertEqual(6);
      let hasRed: boolean = false;
      let hasBlue: boolean = false;
      for (let i = 0; i < palette.length; i += 3) {
        if (palette[i] === 255 && palette[i + 1] === 0 && palette[i + 2] === 0) {
          hasRed = true;
        }
        if (palette[i] === 0 && palette[i + 1] === 0 && palette[i + 2] === 255) {
          hasBlue = true;
        }
      }
      expect(hasRed).assertTrue();
      expect(hasBlue).assertTrue();
      // 无抖动时索引映射应无损还原
      let indices: Uint8Array = mapFrameToIndices(frame, palette, false);
      let lossless: boolean = true;
      for (let i = 0; i < indices.length; i++) {
        let p: number = indices[i] * 3;
        let src: number = i * 4;
        let origRed: number = frame.pixels[src];
        let origGreen: number = frame.pixels[src + 1];
        let origBlue: number = frame.pixels[src + 2];
        let isRed: boolean = origRed === 255 && origBlue === 0;
        let expectRedIdx: number = -1;
        for (let j = 0; j < palette.length; j += 3) {
          if (palette[j] === 255 && palette[j + 1] === 0 && palette[j + 2] === 0) {
            expectRedIdx = j / 3;
          }
        }
        if (isRed && indices[i] !== expectRedIdx) {
          lossless = false;
        }
        if (!isRed && indices[i] === expectRedIdx) {
          lossless = false;
        }
      }
      expect(lossless).assertTrue();
    });

    it('quantize_many_colors_capped_at_256', 0, () => {
      let colors: number[][] = [];
      for (let i = 0; i < 600; i++) {
        colors.push([i % 256, (i * 37) % 256, (i * 73) % 256]);
      }
      let frame: GifFrameData = makeFrame(30, 20, 5, colors);
      let palette: Uint8Array = quantizeToPalette([frame], 256);
      expect(palette.length <= 256 * 3).assertTrue();
      expect(palette.length >= 3).assertTrue();
    });
  });

  describe('GifEncodeStructure', () => {
    it('encode_header_and_trailer', 0, () => {
      let frame: GifFrameData = makeFrame(2, 2, 5, [[255, 0, 0]]);
      let options: GifEncodeOptions = new GifEncodeOptions();
      options.loopCount = 0;
      let gif: Uint8Array = encodeGif([frame], options);
      expect(gif.length > 13).assertTrue();
      expect(String.fromCharCode(gif[0], gif[1], gif[2], gif[3], gif[4], gif[5])).assertEqual('GIF89a');
      expect(gif[6]).assertEqual(2); // 宽度低字节
      expect(gif[8]).assertEqual(2); // 高度低字节
      expect(gif[gif.length - 1]).assertEqual(0x3B); // Trailer
    });

    it('encode_netscape_loop_infinite', 0, () => {
      let frame: GifFrameData = makeFrame(2, 2, 5, [[0, 255, 0]]);
      let options: GifEncodeOptions = new GifEncodeOptions();
      options.loopCount = 0;
      let gif: Uint8Array = encodeGif([frame], options);
      let pattern: number[] = [0x21, 0xFF, 0x0B].concat(asciiBytes('NETSCAPE2.0')).concat([0x03, 0x01, 0x00, 0x00, 0x00]);
      expect(indexOfBytes(gif, pattern)).assertLargerOrEqual(0);
    });

    it('encode_play_once_omits_netscape', 0, () => {
      let frame: GifFrameData = makeFrame(2, 2, 5, [[0, 255, 0]]);
      let options: GifEncodeOptions = new GifEncodeOptions();
      options.loopCount = 1;
      let gif: Uint8Array = encodeGif([frame], options);
      let pattern: number[] = [0x21, 0xFF, 0x0B].concat(asciiBytes('NETSCAPE2.0'));
      expect(indexOfBytes(gif, pattern)).assertEqual(-1);
    });

    it('encode_finite_loop_value_is_count_minus_one', 0, () => {
      let frame: GifFrameData = makeFrame(2, 2, 5, [[0, 255, 0]]);
      let options: GifEncodeOptions = new GifEncodeOptions();
      options.loopCount = 3;
      let gif: Uint8Array = encodeGif([frame], options);
      let pattern: number[] = [0x21, 0xFF, 0x0B].concat(asciiBytes('NETSCAPE2.0')).concat([0x03, 0x01, 0x02, 0x00, 0x00]);
      expect(indexOfBytes(gif, pattern)).assertLargerOrEqual(0);
    });

    it('encode_multi_frame_gce_and_descriptor_count', 0, () => {
      let f1: GifFrameData = makeFrame(2, 2, 5, [[255, 0, 0]]);
      let f2: GifFrameData = makeFrame(2, 2, 8, [[0, 0, 255]]);
      let f3: GifFrameData = makeFrame(2, 2, 12, [[0, 255, 0]]);
      let options: GifEncodeOptions = new GifEncodeOptions();
      let gif: Uint8Array = encodeGif([f1, f2, f3], options);
      let gceCount: number = 0;
      let descCount: number = 0;
      for (let i = 0; i < gif.length - 1; i++) {
        if (gif[i] === 0x21 && gif[i + 1] === 0xF9) {
          gceCount++;
        }
        if (gif[i] === 0x2C && i > 13) {
          descCount++;
        }
      }
      expect(gceCount).assertEqual(3);
      expect(descCount).assertEqual(3);
    });

    it('encode_frame_delay_in_gce_is_little_endian', 0, () => {
      let frame: GifFrameData = makeFrame(2, 2, 50, [[255, 255, 0]]);
      let options: GifEncodeOptions = new GifEncodeOptions();
      let gif: Uint8Array = encodeGif([frame], options);
      // GCE: 21 F9 04 00 <delayLE16> 00 00
      let pattern: number[] = [0x21, 0xF9, 0x04, 0x00, 50, 0x00, 0x00, 0x00];
      expect(indexOfBytes(gif, pattern)).assertLargerOrEqual(0);
    });

    it('encode_full_roundtrip_pixels_lossless_within_palette', 0, () => {
      let colors: number[][] = [[255, 0, 0], [0, 200, 30], [10, 10, 250], [250, 250, 250]];
      let f1: GifFrameData = makeFrame(8, 6, 5, colors);
      let f2: GifFrameData = makeFrame(8, 6, 9, [[0, 0, 0]].concat(colors));
      let options: GifEncodeOptions = new GifEncodeOptions();
      options.loopCount = 0;
      let frames: GifFrameData[] = [f1, f2];
      let gif: Uint8Array = encodeGif(frames, options);

      // 提取全局调色板
      let packed: number = gif[10];
      let gctSize: number = 2 << (packed & 0x07);
      let gctStart: number = 13;
      let palette: Uint8Array = gif.slice(gctStart, gctStart + gctSize * 3);

      // 遍历帧，逐帧解码图像数据子块并对比像素
      let p: number = gctStart + gctSize * 3;
      let frameIdx: number = 0;
      while (p < gif.length - 1) {
        if (gif[p] === 0x21 && gif[p + 1] === 0xF9) {
          p += 8; // 跳过 GCE 块（含终止符）
        } else if (gif[p] === 0x21 && gif[p + 1] === 0xFF) {
          p += 14 + 5; // NETSCAPE 块
        } else if (gif[p] === 0x2C) {
          let w: number = gif[p + 5] | (gif[p + 6] << 8);
          let h: number = gif[p + 7] | (gif[p + 8] << 8);
          let q: number = p + 10; // 跳过描述符
          let mcs: number = gif[q];
          q++;
          let raw: number[] = [];
          while (gif[q] !== 0) {
            let blockSize: number = gif[q];
            for (let b = 0; b < blockSize; b++) {
              raw.push(gif[q + 1 + b]);
            }
            q += 1 + blockSize;
          }
          let decoded: Uint8Array = lzwDecodeForTest(Uint8Array.from(raw), mcs, w * h);
          expect(decoded.length).assertEqual(w * h);
          let src: GifFrameData = frames[frameIdx];
          let lossless: boolean = true;
          for (let i = 0; i < w * h; i++) {
            let pi: number = decoded[i] * 3;
            let si: number = i * 4;
            // 量化调色板包含全部原色（颜色数<=256），应能无损还原
            let distR: number = palette[pi] - src.pixels[si];
            let distG: number = palette[pi + 1] - src.pixels[si + 1];
            let distB: number = palette[pi + 2] - src.pixels[si + 2];
            if (distR !== 0 || distG !== 0 || distB !== 0) {
              lossless = false;
            }
          }
          expect(lossless).assertTrue();
          frameIdx++;
          p = q + 1;
        } else {
          p++;
        }
      }
      expect(frameIdx).assertEqual(2);
    });

    it('encode_dither_produces_valid_structure', 0, () => {
      let colors: number[][] = [];
      for (let i = 0; i < 400; i++) {
        colors.push([i % 256, (i * 91) % 256, (i * 17) % 256]);
      }
      let frame: GifFrameData = makeFrame(20, 20, 5, colors);
      let options: GifEncodeOptions = new GifEncodeOptions();
      options.dither = true;
      let gif: Uint8Array = encodeGif([frame], options);
      expect(gif.length > 13).assertTrue();
      expect(gif[gif.length - 1]).assertEqual(0x3B);
      expect(String.fromCharCode(gif[0], gif[1], gif[2], gif[3], gif[4], gif[5])).assertEqual('GIF89a');
    });
  });
}

describe('GifCompose', () => {
  it('compose_rotation0_top_left_with_white_padding', 0, () => {
    let src: Uint8Array = new Uint8Array(4);
    src[0] = 255;
    src[1] = 0;
    src[2] = 0;
    src[3] = 255;
    let px: Uint8Array = composeFramePixels(src, 1, 1, 0, 2, 2);
    expect(markerAt(px, 2, 0, 0)).assertEqual(0xFF0000);
    expect(markerAt(px, 2, 1, 0)).assertEqual(0xFFFFFF);
    expect(markerAt(px, 2, 0, 1)).assertEqual(0xFFFFFF);
    expect(markerAt(px, 2, 1, 1)).assertEqual(0xFFFFFF);
  });

  it('compose_rotation90_swaps_axes_clockwise', 0, () => {
    let px: Uint8Array = composeFramePixels(markerFrame(), 2, 2, 90, 2, 2);
    // 顺时针 90°：底行变顶行
    expect(markerAt(px, 2, 0, 0)).assertEqual(3 << 16);
    expect(markerAt(px, 2, 1, 0)).assertEqual(1 << 16);
    expect(markerAt(px, 2, 0, 1)).assertEqual(4 << 16);
    expect(markerAt(px, 2, 1, 1)).assertEqual(2 << 16);
  });

  it('compose_rotation180_reverses_both_axes', 0, () => {
    let px: Uint8Array = composeFramePixels(markerFrame(), 2, 2, 180, 2, 2);
    expect(markerAt(px, 2, 0, 0)).assertEqual(4 << 16);
    expect(markerAt(px, 2, 1, 0)).assertEqual(3 << 16);
    expect(markerAt(px, 2, 0, 1)).assertEqual(2 << 16);
    expect(markerAt(px, 2, 1, 1)).assertEqual(1 << 16);
  });

  it('compose_rotation270_swaps_axes_counterclockwise', 0, () => {
    let px: Uint8Array = composeFramePixels(markerFrame(), 2, 2, 270, 2, 2);
    // 逆时针 90°：顶行变底行
    expect(markerAt(px, 2, 0, 0)).assertEqual(2 << 16);
    expect(markerAt(px, 2, 1, 0)).assertEqual(4 << 16);
    expect(markerAt(px, 2, 0, 1)).assertEqual(1 << 16);
    expect(markerAt(px, 2, 1, 1)).assertEqual(3 << 16);
  });

  it('compose_rotation90_landscape_to_portrait_canvas', 0, () => {
    // 2×1 横条 [A B] 顺时针 90° → 1×2 竖条 [A; B]
    let src: Uint8Array = new Uint8Array(8);
    src[0] = 255;
    src[3] = 255; // A 红
    src[5] = 255;
    src[7] = 255; // B 绿
    let px: Uint8Array = composeFramePixels(src, 2, 1, 90, 1, 2);
    expect(markerAt(px, 1, 0, 0)).assertEqual(0xFF0000);
    expect(markerAt(px, 1, 0, 1)).assertEqual(0x00FF00);
  });
});
