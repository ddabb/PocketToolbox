/**
 * PDF 工具纯函数单元测试（1.4.7 Phase 1 测试安全网）
 * 覆盖：px→pt 换算 / 边距档位 / A4 常量 / 枚举值稳定性（历史记录与 JSON 序列化兼容）
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  PdfComposer, PdfPageMode, PdfMarginMode, PdfOrientation, ComposeImage,
  A4_SHORT_PT, A4_LONG_PT
} from '../../../main/ets/core/pdf/PdfComposer';
import { SplitFormat, PdfThumb, SplitOpenResult, SplitExportResult } from '../../../main/ets/core/pdf/PdfSplitter';

export default function pdfUtilTest() {
  describe('pdfUtilTest', () => {
    /** tc1: px → pt（96dpi 像素 → 72dpi PDF 点） */
    it('tc1_pxToPt', 0, () => {
      expect(PdfComposer.pxToPt(96)).assertEqual(72);
      expect(PdfComposer.pxToPt(0)).assertEqual(0);
      expect(PdfComposer.pxToPt(192)).assertEqual(144);
      expect(PdfComposer.pxToPt(100)).assertEqual(75);
    });

    /** tc2: A4 常量与边距档位（pt） */
    it('tc2_a4AndMargins', 0, () => {
      expect(A4_SHORT_PT).assertEqual(595);
      expect(A4_LONG_PT).assertEqual(842);
      expect(PdfComposer.marginPt(PdfMarginMode.NONE)).assertEqual(0);
      expect(PdfComposer.marginPt(PdfMarginMode.NARROW)).assertEqual(12);
      expect(PdfComposer.marginPt(PdfMarginMode.NORMAL)).assertEqual(24);
    });

    /** tc3: 枚举值冻结 —— 历史记录存储/导出 JSON 依赖数值，重排会破坏兼容 */
    it('tc3_enumStability', 0, () => {
      expect(PdfPageMode.FIT).assertEqual(0);
      expect(PdfPageMode.A4).assertEqual(1);
      expect(PdfMarginMode.NONE).assertEqual(0);
      expect(PdfMarginMode.NARROW).assertEqual(1);
      expect(PdfMarginMode.NORMAL).assertEqual(2);
      expect(PdfOrientation.AUTO).assertEqual(0);
      expect(PdfOrientation.PORTRAIT).assertEqual(1);
      expect(SplitFormat.JPEG).assertEqual(0);
      expect(SplitFormat.PNG).assertEqual(1);
    });

    /** tc4: 数据类字段默认值（失败结果不携带误导信息） */
    it('tc4_resultDefaults', 0, () => {
      let img: ComposeImage = new ComposeImage('file://a.png', 100, 200);
      expect(img.uri).assertEqual('file://a.png');
      expect(img.widthPx).assertEqual(100);
      expect(img.heightPx).assertEqual(200);

      let open: SplitOpenResult = new SplitOpenResult();
      expect(open.ok).assertFalse();
      expect(open.parseErr).assertEqual(-1);
      expect(open.needPassword).assertFalse();
      expect(open.pageCount).assertEqual(0);

      let exp: SplitExportResult = new SplitExportResult();
      expect(exp.ok).assertFalse();
      expect(exp.paths.length).assertEqual(0);
      expect(exp.errMsg).assertEqual('');

      let thumb: PdfThumb = new PdfThumb(3, '/tmp/t3.jpg');
      expect(thumb.index).assertEqual(3);
      expect(thumb.path).assertEqual('/tmp/t3.jpg');
    });
  });
}
