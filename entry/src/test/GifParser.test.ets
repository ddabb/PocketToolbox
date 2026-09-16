import { describe, it, expect } from '@ohos/hypium';
import {
  GifFrameData,
  GifEncodeOptions,
  encodeGif,
  lzwEncode
} from '../main/ets/core/gif/GifEncoder';
import {
  GifParseResult,
  parseGif,
  resizeRgba,
  swapBgraRgba
} from '../main/ets/core/gif/GifParser';

function u8(arr: number[]): Uint8Array {
  return Uint8Array.from(arr);
}

function ascii(s: string): number[] {
  let arr: number[] = [];
  for (let i = 0; i < s.length; i++) {
    arr.push(s.charCodeAt(i));
  }
  return arr;
}

/** 读取画布 (x,y) 处的打包 RGB 值 */
function rgbAt(px: Uint8Array, canvasW: number, x: number, y: number): number {
  let p: number = (y * canvasW + x) * 4;
  return (px[p] << 16) | (px[p + 1] << 8) | px[p + 2];
}

/** 构建纯色帧（供 encodeGif 回环用） */
function solidFrame(width: number, height: number, delayCs: number, color: number[]): GifFrameData {
  let frame: GifFrameData = new GifFrameData();
  frame.width = width;
  frame.height = height;
  frame.delayCs = delayCs;
  let pixels: Uint8Array = new Uint8Array(width * height * 4);
  for (let i = 0; i < width * height; i++) {
    pixels[i * 4] = color[0];
    pixels[i * 4 + 1] = color[1];
    pixels[i * 4 + 2] = color[2];
    pixels[i * 4 + 3] = 255;
  }
  frame.pixels = pixels;
  return frame;
}

/** 手工拼一个 2×1 双色 GIF（无 GCE、无 NETSCAPE）：像素 0=红、1=蓝 */
function craftMinimalGif(): Uint8Array {
  let bytes: number[] = ascii('GIF89a')
    .concat([2, 0, 1, 0, 0x80, 0, 0])
    .concat([255, 0, 0, 0, 0, 255])
    .concat([0x2C, 0, 0, 0, 0, 2, 0, 1, 0, 0x00])
    .concat([2, 2, 0x44, 0x0A, 0])
    .concat([0x3B]);
  return u8(bytes);
}

/**
 * 手工拼透明 + disposal2 两帧 GIF：
 * 帧1：2×2 全红（GCE disposal=2，delay 10cs）
 * 帧2：2×1 索引 [1(透明), 2(绿)]（GCE 透明索引 1，delay 5cs）
 */
function craftTransparentDisposalGif(): Uint8Array {
  let f1Indices: Uint8Array = new Uint8Array(4);
  f1Indices.fill(0);
  let f1Data: Uint8Array = lzwEncode(f1Indices, 2);
  let f2Indices: Uint8Array = u8([1, 2]);
  let f2Data: Uint8Array = lzwEncode(f2Indices, 2);
  let f1Block: number[] = [f1Data.length];
  for (let i = 0; i < f1Data.length; i++) {
    f1Block.push(f1Data[i]);
  }
  f1Block.push(0);
  let f2Block: number[] = [f2Data.length];
  for (let i = 0; i < f2Data.length; i++) {
    f2Block.push(f2Data[i]);
  }
  f2Block.push(0);
  let bytes: number[] = ascii('GIF89a')
    .concat([2, 0, 2, 0, 0x81, 0, 0])
    .concat([255, 0, 0, 0, 0, 255, 0, 255, 0, 255, 255, 255])
    // 帧1 GCE：disposal 2 (packed 0x08)，delay 10cs，无透明
    .concat([0x21, 0xF9, 0x04, 0x08, 10, 0, 0, 0x00])
    .concat([0x2C, 0, 0, 0, 0, 2, 0, 2, 0, 0x00])
    .concat([2])
    .concat(f1Block)
    // 帧2 GCE：disposal 0 + 透明标志，透明索引 1，delay 5cs
    .concat([0x21, 0xF9, 0x04, 0x01, 5, 0, 1, 0x00])
    .concat([0x2C, 0, 0, 0, 0, 2, 0, 1, 0, 0x00])
    .concat([2])
    .concat(f2Block)
    .concat([0x3B]);
  return u8(bytes);
}

/** 手工拼 4×4 隔行 GIF：行流顺序 [0,2,1,3]，16 级灰度调色板，像素 (x,y) 索引 = y*4+x */
function craftInterlacedGif(): Uint8Array {
  let order: number[] = [0, 2, 1, 3];
  let stream: Uint8Array = new Uint8Array(16);
  for (let k = 0; k < 4; k++) {
    for (let x = 0; x < 4; x++) {
      stream[k * 4 + x] = order[k] * 4 + x;
    }
  }
  let data: Uint8Array = lzwEncode(stream, 4);
  let block: number[] = [data.length];
  for (let i = 0; i < data.length; i++) {
    block.push(data[i]);
  }
  block.push(0);
  let gct: number[] = [];
  for (let i = 0; i < 16; i++) {
    gct.push(i * 17, i * 17, i * 17);
  }
  let bytes: number[] = ascii('GIF89a')
    .concat([4, 0, 4, 0, 0x83, 0, 0])
    .concat(gct)
    .concat([0x2C, 0, 0, 0, 0, 4, 0, 4, 0, 0x40])
    .concat([4])
    .concat(block)
    .concat([0x3B]);
  return u8(bytes);
}

export default function gifParserTest() {
  describe('GifParseMinimal', () => {
    it('parse_hand_crafted_2x1', 0, () => {
      let result: GifParseResult = parseGif(craftMinimalGif());
      expect(result.width).assertEqual(2);
      expect(result.height).assertEqual(1);
      expect(result.loopCount).assertEqual(1);
      expect(result.frames.length).assertEqual(1);
      expect(result.frames[0].delayCs).assertEqual(0);
      expect(rgbAt(result.frames[0].pixels, 2, 0, 0)).assertEqual(0xFF0000);
      expect(rgbAt(result.frames[0].pixels, 2, 1, 0)).assertEqual(0x0000FF);
      // 合成画布不透明
      expect(result.frames[0].pixels[3]).assertEqual(255);
    });

    it('parse_transparent_and_disposal2', 0, () => {
      let result: GifParseResult = parseGif(craftTransparentDisposalGif());
      expect(result.frames.length).assertEqual(2);
      expect(result.frames[0].delayCs).assertEqual(10);
      expect(result.frames[1].delayCs).assertEqual(5);
      // 帧1：全红
      expect(rgbAt(result.frames[0].pixels, 2, 0, 0)).assertEqual(0xFF0000);
      expect(rgbAt(result.frames[0].pixels, 2, 1, 1)).assertEqual(0xFF0000);
      // 帧2：disposal2 已清回白底，透明像素保持白，绿色像素落笔
      expect(rgbAt(result.frames[1].pixels, 2, 0, 0)).assertEqual(0xFFFFFF);
      expect(rgbAt(result.frames[1].pixels, 2, 1, 0)).assertEqual(0x00FF00);
      expect(rgbAt(result.frames[1].pixels, 2, 0, 1)).assertEqual(0xFFFFFF);
      expect(rgbAt(result.frames[1].pixels, 2, 1, 1)).assertEqual(0xFFFFFF);
    });

    it('parse_interlaced_deinterlace', 0, () => {
      let result: GifParseResult = parseGif(craftInterlacedGif());
      expect(result.frames.length).assertEqual(1);
      let px: Uint8Array = result.frames[0].pixels;
      // (x,y) 应为灰度 (y*4+x)*17
      expect(rgbAt(px, 4, 0, 0)).assertEqual(0x000000);
      expect(rgbAt(px, 4, 3, 0)).assertEqual(0x333333);
      expect(rgbAt(px, 4, 2, 1)).assertEqual(0x666666);
      expect(rgbAt(px, 4, 0, 3)).assertEqual(0xCCCCCC);
      expect(rgbAt(px, 4, 3, 3)).assertEqual(0xFFFFFF);
    });
  });

  describe('GifParseRoundtrip', () => {
    it('parse_encoder_output_pixels_delays_loop0', 0, () => {
      let frames: GifFrameData[] = [
        solidFrame(8, 6, 5, [255, 0, 0]),
        solidFrame(8, 6, 8, [0, 200, 30]),
        solidFrame(8, 6, 12, [10, 10, 250])
      ];
      let opts: GifEncodeOptions = new GifEncodeOptions();
      opts.loopCount = 0;
      let gif: Uint8Array = encodeGif(frames, opts);
      let result: GifParseResult = parseGif(gif);
      expect(result.width).assertEqual(8);
      expect(result.height).assertEqual(6);
      expect(result.loopCount).assertEqual(0);
      expect(result.frames.length).assertEqual(3);
      expect(result.frames[0].delayCs).assertEqual(5);
      expect(result.frames[1].delayCs).assertEqual(8);
      expect(result.frames[2].delayCs).assertEqual(12);
      expect(rgbAt(result.frames[0].pixels, 8, 2, 3)).assertEqual(0xFF0000);
      expect(rgbAt(result.frames[1].pixels, 8, 7, 5)).assertEqual(0x00C81E);
      expect(rgbAt(result.frames[2].pixels, 8, 0, 0)).assertEqual(0x0A0AFA);
    });

    it('parse_encoder_output_loop_counts', 0, () => {
      let frames: GifFrameData[] = [solidFrame(2, 2, 5, [0, 255, 0])];
      let opts3: GifEncodeOptions = new GifEncodeOptions();
      opts3.loopCount = 3;
      expect(parseGif(encodeGif(frames, opts3)).loopCount).assertEqual(3);
      let opts1: GifEncodeOptions = new GifEncodeOptions();
      opts1.loopCount = 1;
      expect(parseGif(encodeGif(frames, opts1)).loopCount).assertEqual(1);
      let opts5: GifEncodeOptions = new GifEncodeOptions();
      opts5.loopCount = 5;
      expect(parseGif(encodeGif(frames, opts5)).loopCount).assertEqual(5);
    });

    it('parse_encoder_output_gradient_lossless', 0, () => {
      // 4×4 渐变 3 帧，像素两两不同且 ≤256 色，量化应无损
      let frames: GifFrameData[] = [];
      for (let f = 0; f < 3; f++) {
        let frame: GifFrameData = new GifFrameData();
        frame.width = 4;
        frame.height = 4;
        frame.delayCs = 4;
        let pixels: Uint8Array = new Uint8Array(64);
        for (let i = 0; i < 16; i++) {
          pixels[i * 4] = (i * 13 + f * 40) % 256;
          pixels[i * 4 + 1] = (i * 29 + f * 20) % 256;
          pixels[i * 4 + 2] = (i * 7 + f * 60) % 256;
          pixels[i * 4 + 3] = 255;
        }
        frame.pixels = pixels;
        frames.push(frame);
      }
      let opts: GifEncodeOptions = new GifEncodeOptions();
      opts.loopCount = 0;
      let result: GifParseResult = parseGif(encodeGif(frames, opts));
      expect(result.frames.length).assertEqual(3);
      let lossless: boolean = true;
      for (let f = 0; f < 3; f++) {
        for (let i = 0; i < 16; i++) {
          let src: number = i * 4;
          let got: number = rgbAt(result.frames[f].pixels, 4, i % 4, Math.floor(i / 4));
          let want: number = (frames[f].pixels[src] << 16) | (frames[f].pixels[src + 1] << 8) | frames[f].pixels[src + 2];
          if (got !== want) {
            lossless = false;
          }
        }
      }
      expect(lossless).assertTrue();
    });
  });

  describe('GifParseInvalid', () => {
    it('parse_rejects_non_gif', 0, () => {
      let threw: boolean = false;
      try {
        parseGif(u8(ascii('NOTAGIF!').concat([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])));
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('parse_rejects_too_small', 0, () => {
      let threw: boolean = false;
      try {
        parseGif(u8(ascii('GIF89a')));
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('parse_rejects_truncated', 0, () => {
      let full: Uint8Array = craftMinimalGif();
      let threw: boolean = false;
      try {
        parseGif(full.subarray(0, full.length - 4));
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('parse_rejects_unknown_block', 0, () => {
      let bytes: Uint8Array = u8(ascii('GIF89a').concat([2, 0, 1, 0, 0x00, 0, 0, 0x55]));
      let threw: boolean = false;
      try {
        parseGif(bytes);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });
  });

  describe('GifResizeAndSwap', () => {
    it('resize_identity', 0, () => {
      let src: Uint8Array = u8([10, 20, 30, 255, 40, 50, 60, 255]);
      let out: Uint8Array = resizeRgba(src, 2, 1, 2, 1);
      expect(out.length).assertEqual(8);
      let same: boolean = true;
      for (let i = 0; i < 8; i++) {
        if (out[i] !== src[i]) {
          same = false;
        }
      }
      expect(same).assertTrue();
    });

    it('resize_2x2_to_1x1_average', 0, () => {
      // TL 黑 TR 白 BL 白 BR 黑 → 平均 127.5 → 128
      let src: Uint8Array = u8([
        0, 0, 0, 255, 255, 255, 255, 255,
        255, 255, 255, 255, 0, 0, 0, 255
      ]);
      let out: Uint8Array = resizeRgba(src, 2, 2, 1, 1);
      expect(out.length).assertEqual(4);
      expect(out[0]).assertEqual(128);
      expect(out[1]).assertEqual(128);
      expect(out[2]).assertEqual(128);
      expect(out[3]).assertEqual(255);
    });

    it('resize_1x1_to_2x2_replicate', 0, () => {
      let src: Uint8Array = u8([10, 20, 30, 255]);
      let out: Uint8Array = resizeRgba(src, 1, 1, 2, 2);
      expect(out.length).assertEqual(16);
      let same: boolean = true;
      for (let i = 0; i < 4; i++) {
        if (out[i * 4] !== 10 || out[i * 4 + 1] !== 20 || out[i * 4 + 2] !== 30 || out[i * 4 + 3] !== 255) {
          same = false;
        }
      }
      expect(same).assertTrue();
    });

    it('resize_invalid_size_throws', 0, () => {
      let threw: boolean = false;
      try {
        resizeRgba(u8([0, 0, 0, 255]), 1, 1, 0, 1);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('swap_bgra_rgba', 0, () => {
      let src: Uint8Array = u8([200, 150, 100, 255, 1, 2, 3, 254]);
      let out: Uint8Array = swapBgraRgba(src);
      expect(out[0]).assertEqual(100);
      expect(out[1]).assertEqual(150);
      expect(out[2]).assertEqual(200);
      expect(out[3]).assertEqual(255);
      expect(out[4]).assertEqual(3);
      expect(out[5]).assertEqual(2);
      expect(out[6]).assertEqual(1);
      expect(out[7]).assertEqual(254);
      // 原数组不被修改
      expect(src[0]).assertEqual(200);
    });
  });
}
