/**
 * GIF 编解码单元测试（1.4.7 Phase 1 测试安全网）
 * 覆盖：帧序/延迟纯函数 / BGRA-RGBA 交换 / 双线性缩放 / encode→parse round-trip / 非法输入
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  GifFrameData, GifEncodeOptions, buildFrameOrder, computeDelayCs,
  resolveFrameDelayCs, encodeGif
} from '../../../main/ets/core/gif/GifEncoder';
import { parseGif, resizeRgba, swapBgraRgba, GifParseResult } from '../../../main/ets/core/gif/GifParser';

function solidFrame(w: number, h: number, r: number, g: number, b: number, delayCs: number): GifFrameData {
  let f: GifFrameData = new GifFrameData();
  f.width = w;
  f.height = h;
  f.delayCs = delayCs;
  f.pixels = new Uint8Array(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    f.pixels[i * 4] = r;
    f.pixels[i * 4 + 1] = g;
    f.pixels[i * 4 + 2] = b;
    f.pixels[i * 4 + 3] = 255;
  }
  return f;
}

function arrEq(a: number[], b: number[]): boolean {
  if (a.length !== b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) {
      return false;
    }
  }
  return true;
}

export default function gifCodecTest() {
  describe('gifCodecTest', () => {
    /** tc1: 帧播放顺序 —— 正放 / 倒放 / 来回（首尾帧不重复） */
    it('tc1_buildFrameOrder', 0, () => {
      expect(buildFrameOrder(0, 'normal').length).assertEqual(0);
      expect(arrEq(buildFrameOrder(3, 'normal'), [0, 1, 2])).assertTrue();
      expect(arrEq(buildFrameOrder(3, 'reverse'), [2, 1, 0])).assertTrue();
      expect(arrEq(buildFrameOrder(4, 'pingpong'), [0, 1, 2, 3, 2, 1])).assertTrue();
      expect(arrEq(buildFrameOrder(2, 'pingpong'), [0, 1])).assertTrue();
      expect(arrEq(buildFrameOrder(1, 'pingpong'), [0])).assertTrue();
      expect(arrEq(buildFrameOrder(0, 'pingpong'), [])).assertTrue();
    });

    /** tc2: 帧延迟 —— 时长/倍速换算，最小 1（1/100s），非法倍速按 1 处理 */
    it('tc2_delay', 0, () => {
      expect(computeDelayCs(100, 1)).assertEqual(10);
      expect(computeDelayCs(100, 2)).assertEqual(5);
      expect(computeDelayCs(95, 1)).assertEqual(10);
      expect(computeDelayCs(0, 1)).assertEqual(1);
      expect(computeDelayCs(100, 0)).assertEqual(10);
      expect(resolveFrameDelayCs(50, 100, 1)).assertEqual(5);
      expect(resolveFrameDelayCs(0, 100, 2)).assertEqual(5);
      expect(resolveFrameDelayCs(0, 0, 1)).assertEqual(1);
    });

    /** tc3: BGRA ↔ RGBA 通道交换 */
    it('tc3_swapBgraRgba', 0, () => {
      let out: Uint8Array = swapBgraRgba(new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]));
      expect(arrEq(Array.from(out), [3, 2, 1, 4, 7, 6, 5, 8])).assertTrue();
    });

    /** tc4: RGBA 双线性缩放 —— 同色放大不引入色偏；原尺寸返回拷贝 */
    it('tc4_resizeRgba', 0, () => {
      let src: Uint8Array = new Uint8Array(16);
      for (let i = 0; i < 4; i++) {
        src[i * 4] = 255;
        src[i * 4 + 1] = 0;
        src[i * 4 + 2] = 0;
        src[i * 4 + 3] = 255;
      }
      let out: Uint8Array = resizeRgba(src, 2, 2, 4, 4);
      expect(out.length).assertEqual(64);
      for (let i = 0; i < 16; i++) {
        expect(out[i * 4]).assertEqual(255);
        expect(out[i * 4 + 1]).assertEqual(0);
        expect(out[i * 4 + 2]).assertEqual(0);
        expect(out[i * 4 + 3]).assertEqual(255);
      }
      let same: Uint8Array = resizeRgba(src, 2, 2, 2, 2);
      expect(same.length).assertEqual(16);
      expect(same[0]).assertEqual(255);
    });

    /** tc5: encode → parse round-trip —— 头部/尺寸/循环次数/帧数/延迟/像素色 */
    it('tc5_roundTrip', 0, () => {
      let frames: GifFrameData[] = [
        solidFrame(4, 4, 255, 0, 0, 10),
        solidFrame(4, 4, 0, 0, 255, 10)
      ];
      let opts: GifEncodeOptions = new GifEncodeOptions();
      opts.loopCount = 0;
      opts.dither = false;
      let bytes: Uint8Array = encodeGif(frames, opts);
      expect(bytes.length).assertLargerOrEqual(13);
      expect(bytes[0]).assertEqual(0x47);
      expect(bytes[1]).assertEqual(0x49);
      expect(bytes[2]).assertEqual(0x46);
      expect(bytes[3]).assertEqual(0x38);
      expect(bytes[4]).assertEqual(0x39);
      expect(bytes[5]).assertEqual(0x61);

      let parsed: GifParseResult = parseGif(bytes);
      expect(parsed.width).assertEqual(4);
      expect(parsed.height).assertEqual(4);
      expect(parsed.loopCount).assertEqual(0);
      expect(parsed.frames.length).assertEqual(2);
      expect(parsed.frames[0].delayCs).assertEqual(10);
      expect(parsed.frames[1].delayCs).assertEqual(10);
      expect(parsed.frames[0].pixels[0]).assertEqual(255);
      expect(parsed.frames[0].pixels[1]).assertEqual(0);
      expect(parsed.frames[0].pixels[2]).assertEqual(0);
      expect(parsed.frames[0].pixels[3]).assertEqual(255);
      expect(parsed.frames[1].pixels[0]).assertEqual(0);
      expect(parsed.frames[1].pixels[2]).assertEqual(255);
      expect(parsed.frames[1].pixels[3]).assertEqual(255);
    });

    /** tc6: loopCount=1 不写 Netscape 块 → 解析侧回退默认播放一次 */
    it('tc6_playOnce', 0, () => {
      let frames: GifFrameData[] = [solidFrame(2, 2, 0, 255, 0, 5)];
      let opts: GifEncodeOptions = new GifEncodeOptions();
      opts.loopCount = 1;
      let parsed: GifParseResult = parseGif(encodeGif(frames, opts));
      expect(parsed.loopCount).assertEqual(1);
      expect(parsed.frames.length).assertEqual(1);
      expect(parsed.frames[0].delayCs).assertEqual(5);
    });

    /** tc7: 非法输入 —— 过短/伪头抛错；空帧/尺寸不匹配编码抛错 */
    it('tc7_invalidInput', 0, () => {
      let threw: boolean = false;
      try {
        parseGif(new Uint8Array(5));
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();

      threw = false;
      let junk: Uint8Array = new Uint8Array(20);
      junk[0] = 0x41;
      junk[1] = 0x42;
      try {
        parseGif(junk);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();

      threw = false;
      let opts: GifEncodeOptions = new GifEncodeOptions();
      try {
        encodeGif([], opts);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();

      threw = false;
      let mismatched: GifFrameData[] = [solidFrame(2, 2, 255, 0, 0, 5), solidFrame(3, 3, 0, 0, 255, 5)];
      try {
        encodeGif(mismatched, opts);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });
  });
}
