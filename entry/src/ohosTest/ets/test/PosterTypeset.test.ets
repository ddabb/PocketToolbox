/**
 * 排版内核单元测试（1.4.7 Phase 1 测试安全网）
 * 覆盖：字宽估算 / 有效字数 / 横排 layout（连续性、宽度下限、MIN_FONT_PX 截断、大字下限）
 *      / 竖排 layoutVertical（列数预算、列首列尾避让、宽度上限、截断容量）
 * 判据来源：docs/1.4.6开发计划_欠账收口与排版内核.md §2.1.2 spike 边界用例 + 实现不变量
 */
import { describe, it, expect } from '@ohos/hypium';
import { PosterTypeset, PosterLayout, PosterVerticalLayout } from '../../../main/ets/core/cover/PosterTypeset';

function repeatChar(ch: string, n: number): string {
  let s: string = '';
  for (let i = 0; i < n; i++) {
    s += ch;
  }
  return s;
}

/** 数组逐元素相等 */
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

export default function posterTypesetTest() {
  describe('posterTypesetTest', () => {
    /** tc1: measureEm —— 汉字/全角标点 1.0em，拉丁 0.55em，emoji 1.2em */
    it('tc1_measureEm', 0, () => {
      expect(PosterTypeset.measureEm('')).assertEqual(0);
      expect(PosterTypeset.measureEm('中')).assertEqual(1);
      expect(PosterTypeset.measureEm('，')).assertEqual(1);
      expect(PosterTypeset.measureEm('「')).assertEqual(1);
      expect(PosterTypeset.measureEm('5')).assertEqual(0.55);
      let latin: number = PosterTypeset.measureEm('ab');
      expect(latin > 1.09 && latin < 1.11).assertTrue();
      expect(PosterTypeset.measureEm('😀')).assertEqual(1.2);
    });

    /** tc2: countChars 去空白口径 */
    it('tc2_countChars', 0, () => {
      expect(PosterTypeset.countChars('')).assertEqual(0);
      expect(PosterTypeset.countChars('你 好')).assertEqual(2);
      expect(PosterTypeset.countChars(' \n\t')).assertEqual(0);
      expect(PosterTypeset.countChars('四字文案')).assertEqual(4);
    });

    /** tc3: layout 空文案 / 短文案基线 */
    it('tc3_layoutBasics', 0, () => {
      let empty: PosterLayout = PosterTypeset.layout('', 540, 8, 72, false);
      expect(empty.fontPx).assertEqual(72);
      expect(empty.lines).assertEqual(0);
      expect(empty.truncated).assertFalse();
      expect(empty.capacity).assertEqual(0);

      let one: PosterLayout = PosterTypeset.layout('中', 540, 8, 72, false);
      expect(one.fontPx).assertEqual(72);
      expect(one.lines).assertEqual(1);
      expect(one.truncated).assertFalse();

      let four: PosterLayout = PosterTypeset.layout('四字文案', 540, 8, 72, false);
      expect(four.fontPx).assertEqual(72);
      expect(four.lines).assertEqual(1);
    });

    /** tc4: 字号连续性 —— 1..60 字无骤降（相邻跌落 ≤10px）、单调不增、不截断 */
    it('tc4_fontContinuity', 0, () => {
      let prevFont: number = 72; // basePx 即字号上限，drop 判据自 n=2 生效
      for (let n = 1; n <= 60; n++) {
        let r: PosterLayout = PosterTypeset.layout(repeatChar('字', n), 540, 8, 72, false);
        expect(r.fontPx).assertLargerOrEqual(20);
        expect(r.fontPx <= prevFont).assertTrue();
        expect(prevFont - r.fontPx <= 10).assertTrue();
        expect(r.truncated).assertFalse();
        prevFont = r.fontPx;
      }
    });

    /** tc5: 宽度下限 —— 字号不超过 availWidth/2 与 basePx 的较小值；极限窄容器落到 MIN_FONT_PX */
    it('tc5_widthFloor', 0, () => {
      let r: PosterLayout = PosterTypeset.layout('文案文案', 100, 8, 72, false);
      expect(r.fontPx).assertEqual(50);
      expect(r.lines).assertEqual(2);
      expect(r.capacity).assertEqual(16);

      let tiny: PosterLayout = PosterTypeset.layout('文案', 1, 8, 72, false);
      expect(tiny.fontPx).assertEqual(20);
    });

    /** tc6: MIN_FONT_PX 截断 —— 120 字 / 200px / 3 行预算：字号 20、容量 30、截 90 字 */
    it('tc6_minFontTruncation', 0, () => {
      let r: PosterLayout = PosterTypeset.layout(repeatChar('字', 120), 200, 3, 72, false);
      expect(r.fontPx).assertEqual(20);
      expect(r.lines).assertEqual(3);
      expect(r.truncated).assertTrue();
      expect(r.truncatedChars).assertEqual(90);
      expect(r.capacity).assertEqual(30);
    });

    /** tc7: 大字下限保护 —— 200 字收缩后仍不低于 basePx×0.5=36，超出部分记截断 */
    it('tc7_bigFloor', 0, () => {
      let r: PosterLayout = PosterTypeset.layout(repeatChar('字', 200), 400, 12, 72, true);
      expect(r.fontPx).assertEqual(36);
      expect(r.truncated).assertTrue();
      expect(r.truncatedChars).assertEqual(68);
    });

    /** tc8: lineHeight / blockHeight / estimateCapacity 纯函数 */
    it('tc8_heightAndCapacity', 0, () => {
      expect(PosterTypeset.lineHeight(50)).assertEqual(70);
      expect(PosterTypeset.blockHeight(50, 3)).assertEqual(210);
      expect(PosterTypeset.blockHeight(50, 0)).assertEqual(70);
      expect(PosterTypeset.estimateCapacity(50, 540, 8)).assertEqual(80);
      expect(PosterTypeset.estimateCapacity(50, 0, 8)).assertEqual(0);
    });

    /** tc9: layoutVertical 空文案 */
    it('tc9_verticalEmpty', 0, () => {
      let r: PosterVerticalLayout = PosterTypeset.layoutVertical('', 800, 5, 48, false, 1.3, 400, 1.6);
      expect(r.fontPx).assertEqual(48);
      expect(r.cols).assertEqual(0);
      expect(r.columns.length).assertEqual(0);
    });

    /** tc10: 竖排 9 字恰满 3 列（字号不收缩） */
    it('tc10_verticalExactFit', 0, () => {
      let r: PosterVerticalLayout =
        PosterTypeset.layoutVertical('甲乙丙丁戊己庚辛壬', 100, 3, 30, false, 1.0, 0, 1.0);
      expect(r.fontPx).assertEqual(30);
      expect(r.cols).assertEqual(3);
      expect(r.perCol).assertEqual(3);
      expect(r.truncated).assertFalse();
      expect(r.capacity).assertEqual(9);
      expect(r.columns[0].length).assertEqual(3);
    });

    /** tc11: 竖排 10 字超列预算 → 连续收缩至 25px（perCol 4），列长 [4,4,2] */
    it('tc11_verticalShrink', 0, () => {
      let r: PosterVerticalLayout =
        PosterTypeset.layoutVertical('甲乙丙丁戊己庚辛壬癸', 100, 3, 30, false, 1.0, 0, 1.0);
      expect(r.fontPx).assertEqual(25);
      expect(r.perCol).assertEqual(4);
      expect(r.cols).assertEqual(3);
      expect(r.truncated).assertFalse();
      expect(r.columns[0].length).assertEqual(4);
      expect(r.columns[2].length).assertEqual(2);
      expect(r.capacity).assertEqual(12);
    });

    /** tc12: 竖排 100 字超容量 → MIN_FONT_PX 截断，保前 15 字（3 列 × 5 字） */
    it('tc12_verticalTruncation', 0, () => {
      let r: PosterVerticalLayout =
        PosterTypeset.layoutVertical(repeatChar('字', 100), 100, 3, 30, false, 1.0, 0, 1.0);
      expect(r.fontPx).assertEqual(20);
      expect(r.truncated).assertTrue();
      expect(r.truncatedChars).assertEqual(85);
      expect(r.capacity).assertEqual(15);
      expect(r.cols).assertEqual(3);
      expect(r.perCol).assertEqual(5);
    });

    /** tc13: 竖排列首避让 —— 闭合标点「。」不落列首（提前 1 字收列） */
    it('tc13_verticalNoColStart', 0, () => {
      let r: PosterVerticalLayout =
        PosterTypeset.layoutVertical('一二三四。五', 100, 3, 25, false, 1.0, 0, 1.0);
      expect(r.fontPx).assertEqual(25);
      expect(r.truncated).assertFalse();
      expect(r.columns.length).assertEqual(2);
      let sum: number = 0;
      for (let i = 0; i < r.columns.length; i++) {
        expect(r.columns[i][0] === '。').assertFalse();
        sum += r.columns[i].length;
      }
      expect(sum).assertEqual(6);
    });

    /** tc14: 竖排列尾避让 —— 开放标点「「」不落列尾（带到下一列，「」不断词） */
    it('tc14_verticalNoColEnd', 0, () => {
      let r: PosterVerticalLayout =
        PosterTypeset.layoutVertical('一二「三四五六七八', 75, 4, 25, false, 1.0, 0, 1.0);
      expect(r.fontPx).assertEqual(25);
      expect(r.cols).assertEqual(4);
      expect(r.truncated).assertFalse();
      expect(r.columns[0][r.columns[0].length - 1] === '「').assertFalse();
      expect(r.columns[1][0]).assertEqual('「');
      let sum: number = 0;
      for (let i = 0; i < r.columns.length; i++) {
        sum += r.columns[i].length;
      }
      expect(sum).assertEqual(9);
    });

    /** tc15: 竖排宽度上限 —— availWidth/pitch 限制列数，宽不足时收缩字号 */
    it('tc15_verticalWidthCap', 0, () => {
      let r: PosterVerticalLayout =
        PosterTypeset.layoutVertical('甲乙丙丁戊己庚辛壬', 100, 5, 30, false, 1.0, 60, 1.0);
      expect(r.fontPx).assertEqual(20);
      expect(r.cols).assertEqual(2);
      expect(r.perCol).assertEqual(5);
      expect(r.truncated).assertFalse();
    });

    /** tc16: 竖排不变量扫描（T20 量级参数）—— 1..80 字：不截断时列内总字数守恒、
     *  列数不超预算、相邻字号跌落 ≤12px（spike 判据）；200 字触发 MIN_FONT_PX 截断 */
    it('tc16_verticalInvariants', 0, () => {
      let prevFont: number = 48; // basePx 即字号上限，drop 判据自 n=2 生效
      for (let n = 1; n <= 80; n++) {
        let r: PosterVerticalLayout =
          PosterTypeset.layoutVertical(repeatChar('字', n), 650, 5, 48, false, 1.32, 760, 1.8);
        expect(r.fontPx >= 20).assertTrue();
        expect(r.fontPx <= prevFont).assertTrue();
        expect(prevFont - r.fontPx <= 12).assertTrue();
        expect(r.truncated).assertFalse();
        expect(r.cols <= 5).assertTrue();
        let sum: number = 0;
        for (let i = 0; i < r.columns.length; i++) {
          expect(r.columns[i].length <= r.perCol).assertTrue();
          sum += r.columns[i].length;
        }
        expect(sum).assertEqual(n);
        prevFont = r.fontPx;
      }
      let over: PosterVerticalLayout =
        PosterTypeset.layoutVertical(repeatChar('字', 200), 650, 5, 48, false, 1.32, 760, 1.8);
      expect(over.truncated).assertTrue();
      expect(over.fontPx).assertEqual(20);
      expect(over.truncatedChars).assertEqual(80);
      expect(over.capacity).assertEqual(120);
    });
  });
}
