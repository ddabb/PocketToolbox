/**
 * SudokuPixel 像素引擎 - 单元测试（P2-0 拆分前回归网）
 * 覆盖：签名度量（countInk/holes/centroid/ratios）、形状特征（strokeWidth/hog）、
 * Otsu 阈值、通道背景灰度映射、透视恒等变换、合成棋盘 BBox 检测、
 * 精确网格线拟合、单元格居中校验、模板加载与识别守卫
 * 期望值全部由实现语义手工推导（合成 460×460 棋盘：线宽 3px、格距 50px）
 */
import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import {
  BoardBBox, BoardCorners, GridLines, SIG_ROWS, SIG_COLS,
  countInk, countHoles, holeCenterRow, inkCentroidRow, inkCentroidCol,
  topBottomInkRatio, leftRightInkRatio, computeSigQualityMetrics,
  getLastSigMetrics, getLastSigCompCount, getLastSigLrgRatio, getLastSigHoles,
  getLastSigInk, strokeWidthRatio, hogVerticalGradient,
  otsuThreshold, bgColor, toGrayArray, resetChannelBgCache, isInkPixel,
  warpPerspectiveGray, findBoardBBox, findPreciseGridLines, validateCellCentering,
  initDigitTemplates, recognizeDigit, getLastBboxDiag
} from '../../../main/ets/core/sudoku/SudokuPixel';

/** 模块加载期 delegator 尚未就绪，必须在用例执行期懒获取 */
function appCtx(): common.Context {
  const delegator: abilityDelegatorRegistry.AbilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();
  return delegator.getAppContext();
}

/** 空签名：28×20 全 0 */
function emptySig(): number[] {
  return new Array<number>(SIG_ROWS * SIG_COLS).fill(0);
}

/** 环形签名（类 0/8）：行 8..20、列 6..14 的边框，内孔 11×7 */
function ringSig(): number[] {
  const sig: number[] = emptySig();
  for (let r: number = 8; r <= 20; r++) {
    for (let c: number = 6; c <= 14; c++) {
      if (r === 8 || r === 20 || c === 6 || c === 14) {
        sig[r * SIG_COLS + c] = 1;
      }
    }
  }
  return sig;
}

/** 实心矩形签名：行 8..20、列 6..14（无孔） */
function solidSig(): number[] {
  const sig: number[] = emptySig();
  for (let r: number = 8; r <= 20; r++) {
    for (let c: number = 6; c <= 14; c++) {
      sig[r * SIG_COLS + c] = 1;
    }
  }
  return sig;
}

/** 全白 RGBA 图 */
function mkImage(w: number, h: number): Uint8Array {
  const p: Uint8Array = new Uint8Array(w * h * 4);
  for (let i: number = 0; i < w * h; i++) {
    p[i * 4] = 255;
    p[i * 4 + 1] = 255;
    p[i * 4 + 2] = 255;
    p[i * 4 + 3] = 255;
  }
  return p;
}

/** 黑色矩形（x0..x1 / y0..y1 闭区间） */
function fillRect(px: Uint8Array, w: number, x0: number, y0: number, x1: number, y1: number): void {
  for (let y: number = y0; y <= y1; y++) {
    for (let x: number = x0; x <= x1; x++) {
      const o: number = (y * w + x) * 4;
      px[o] = 0;
      px[o + 1] = 0;
      px[o + 2] = 0;
      px[o + 3] = 255;
    }
  }
}

/** 合成棋盘：460×460 白底；10 竖线 + 10 横线（x/y=50c±1，c=0..9，宽 3px）；
 *  居中数字条 (122..127, 160..189) 于格 (2,3)；离心数字条 (257..262, 270..289) 于格 (5,5) */
function boardPixels(): Uint8Array {
  const size: number = 460;
  const px: Uint8Array = mkImage(size, size);
  for (let c: number = 0; c <= 9; c++) {
    const x0: number = Math.max(0, 50 * c - 1);
    const x1: number = Math.min(size - 1, 50 * c + 1);
    fillRect(px, size, x0, 0, x1, size - 1);
    const y0: number = Math.max(0, 50 * c - 1);
    const y1: number = Math.min(size - 1, 50 * c + 1);
    fillRect(px, size, 0, y0, size - 1, y1);
  }
  fillRect(px, size, 122, 160, 127, 189);
  fillRect(px, size, 257, 270, 262, 289);
  return px;
}

export default function sudokuPixelTest() {
  describe('sudokuPixelTest', () => {
    /** tc1: 签名度量 —— 环形 countInk=40/单孔/质心对称；实心无孔；空签名边界 */
    it('tc1_sigMetrics', 0, () => {
      const ring: number[] = ringSig();
      expect(countInk(ring)).assertEqual(40);
      expect(countHoles(ring)).assertEqual(1);
      expect(holeCenterRow(ring)).assertEqual(14);
      expect(Math.abs(inkCentroidRow(ring) - 14 / 27) < 1e-9).assertTrue();
      expect(inkCentroidCol(ring)).assertEqual(10);
      expect(Math.abs(topBottomInkRatio(ring) - 19 / 21) < 1e-9).assertTrue();
      expect(Math.abs(leftRightInkRatio(ring) - 19 / 21) < 1e-9).assertTrue();

      const solid: number[] = solidSig();
      expect(countHoles(solid)).assertEqual(0);
      expect(holeCenterRow(solid)).assertEqual(-1);
      expect(countInk(solid)).assertEqual(117);

      const empty: number[] = emptySig();
      expect(countInk(empty)).assertEqual(0);
      expect(countHoles(empty)).assertEqual(0);
      expect(holeCenterRow(empty)).assertEqual(-1);
      expect(inkCentroidRow(empty)).assertEqual(0.5);
      expect(inkCentroidCol(empty)).assertEqual(-1);
      expect(topBottomInkRatio(empty)).assertEqual(999);
      expect(leftRightInkRatio(empty)).assertEqual(0);
    });

    /** tc2: 形状特征 —— 环形水平笔画 9 / 垂直笔画 13；空签名 hog=0.5、stroke=0 */
    it('tc2_shapeFeatures', 0, () => {
      const ring: number[] = ringSig();
      expect(Math.abs(strokeWidthRatio(ring) - 9 / 13) < 1e-9).assertTrue();
      const hog: number = hogVerticalGradient(ring);
      expect(hog >= 0 && hog <= 1).assertTrue();
      const empty: number[] = emptySig();
      expect(hogVerticalGradient(empty)).assertEqual(0.5);
      expect(strokeWidthRatio(empty)).assertEqual(0);
    });

    /** tc3: Otsu 双峰直方图阈值 + 签名质量度量诊断字段 */
    it('tc3_otsuAndQuality', 0, () => {
      const hist: number[] = new Array<number>(256).fill(0);
      hist[50] = 100;
      hist[200] = 100;
      expect(otsuThreshold(hist, 200)).assertEqual(50);

      const ring: number[] = ringSig();
      computeSigQualityMetrics(ring);
      expect(getLastSigCompCount()).assertEqual(1);
      expect(Math.abs(getLastSigLrgRatio() - 1) < 1e-9).assertTrue();
      expect(getLastSigHoles()).assertEqual(1);
      expect(getLastSigInk()).assertEqual(40);
      expect(getLastSigMetrics().indexOf('holes=1') >= 0).assertTrue();

      const empty: number[] = emptySig();
      computeSigQualityMetrics(empty);
      expect(getLastSigInk()).assertEqual(0);
      expect(getLastSigMetrics()).assertEqual('comp=0 lrg=0.00 holes=0 ink=0');
    });

    /** tc4: 通道背景灰度映射 —— bg 恒返 255 缓存众数通道；对比度灰度 255-|Δ|max；墨迹判定 */
    it('tc4_bgGrayMapping', 0, () => {
      resetChannelBgCache();
      const px: Uint8Array = mkImage(4, 4);
      expect(bgColor(px, 4, 4)).assertEqual(255);
      const gray: Float32Array = toGrayArray(px, 4, 4);
      expect(gray.length).assertEqual(16);
      expect(gray[0]).assertEqual(255);
      expect(gray[15]).assertEqual(255);

      px[0] = 40;
      px[1] = 40;
      px[2] = 40;
      const gray2: Float32Array = toGrayArray(px, 4, 4);
      expect(Math.abs(gray2[0] - 55) < 1e-6).assertTrue();
      expect(gray2[1]).assertEqual(255);

      expect(isInkPixel(100, 200, true)).assertFalse();
      expect(isInkPixel(100, 200, false)).assertTrue();
      expect(isInkPixel(260, 200, true)).assertTrue();
      expect(isInkPixel(140, 200, false)).assertFalse();
    });

    /** tc5: 透视恒等变换 —— 四角即整幅边界时输出≈输入（双线性在整点采样） */
    it('tc5_warpIdentity', 0, () => {
      const w: number = 20;
      const gray: Float32Array = new Float32Array(w * w);
      for (let y: number = 0; y < w; y++) {
        for (let x: number = 0; x < w; x++) {
          gray[y * w + x] = (x * 7 + y * 13) % 256;
        }
      }
      const corners: BoardCorners = {
        topLeftX: 0, topLeftY: 0,
        topRightX: w - 1, topRightY: 0,
        bottomRightX: w - 1, bottomRightY: w - 1,
        bottomLeftX: 0, bottomLeftY: w - 1,
        isDark: false, confidence: 1
      };
      const out: Float32Array = warpPerspectiveGray(gray, w, w, corners, w, 128);
      expect(out.length).assertEqual(w * w);
      let maxDiff: number = 0;
      for (let i: number = 0; i < w * w; i++) {
        const d: number = Math.abs(out[i] - gray[i]);
        if (d > maxDiff) { maxDiff = d; }
      }
      expect(maxDiff <= 0.5).assertTrue();
    });

    /** tc6: 合成棋盘 BBox —— 覆盖网格外沿、不退化为全图、诊断非空 */
    it('tc6_findBoardBBox', 0, () => {
      const px: Uint8Array = boardPixels();
      const bbox: BoardBBox = findBoardBBox(px, 460, 460, 255);
      expect(bbox.left <= 6).assertTrue();
      expect(bbox.top <= 6).assertTrue();
      expect(bbox.right >= 445).assertTrue();
      expect(bbox.bottom >= 445).assertTrue();
      expect(bbox.right < 460).assertTrue();
      expect(bbox.bottom < 460).assertTrue();
      expect(bbox.isDark).assertFalse();
      expect(getLastBboxDiag().length > 0).assertTrue();
    });

    /** tc7: 精确网格线拟合 —— 10 竖/横线落在 50c ± 2 */
    it('tc7_findPreciseGridLines', 0, () => {
      const px: Uint8Array = boardPixels();
      bgColor(px, 460, 460);
      const gray: Float32Array = toGrayArray(px, 460, 460);
      const bbox: BoardBBox = { left: 0, top: 0, right: 451, bottom: 451, isDark: false };
      const gl: GridLines | null = findPreciseGridLines(gray, 460, 460, bbox, 255);
      expect(gl !== null).assertTrue();
      if (gl !== null) {
        expect(gl.vLines.length).assertEqual(10);
        expect(gl.hLines.length).assertEqual(10);
        for (let i: number = 0; i < 10; i++) {
          expect(Math.abs(gl.vLines[i] - 50 * i) <= 2).assertTrue();
          expect(Math.abs(gl.hLines[i] - 50 * i) <= 2).assertTrue();
        }
      }
    });

    /** tc8: 单元格居中校验 —— 居中条 true / 离心条（质心偏移 0.3 格宽）false / 空格 true */
    it('tc8_validateCellCentering', 0, () => {
      const px: Uint8Array = boardPixels();
      bgColor(px, 460, 460);
      const gray: Float32Array = toGrayArray(px, 460, 460);
      expect(validateCellCentering(gray, 460, 460, 99, 149, 50, 50, false, 255)).assertTrue();
      expect(validateCellCentering(gray, 460, 460, 250, 250, 50, 50, false, 255)).assertFalse();
      expect(validateCellCentering(gray, 460, 460, 350, 350, 50, 50, false, 255)).assertTrue();
    });

    /** tc9: 模板加载与识别守卫 —— rawfile 模板可载入；墨量 < THIN1 下限时直接返回 0 */
    it('tc9_templatesAndGuard', 0, async () => {
      expect(initDigitTemplates(appCtx())).assertTrue();
      const empty: number[] = emptySig();
      const digit: number = await recognizeDigit(empty, 0);
      expect(digit).assertEqual(0);
    });
  });
}
