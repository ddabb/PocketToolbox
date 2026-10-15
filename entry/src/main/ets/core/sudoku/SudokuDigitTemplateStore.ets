import { DOMAIN, TAG, DigitTemplate, SP, SIG_ROWS, SIG_COLS } from './SudokuPixelKernel';
import { holeCenterRow } from './SudokuSigAnalysis';

import { Context } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RawFileUtil } from '../../common/utils/RawFileUtil';

interface DigitTemplateEntry {
  digit: number;
  font: string;
  key: number[];
}

interface DigitTemplateFile {
  rows: number;
  cols: number;
  templates: DigitTemplateEntry[];
}

export function initDigitTemplates(context: Context): boolean {
  if (SP.loaded) { return true; }
  try {
    let file: DigitTemplateFile = RawFileUtil.readJson<DigitTemplateFile>(context, 'digit_templates_extended.json');
    if (!file || !file.templates || file.templates.length === 0) {
      file = RawFileUtil.readJson<DigitTemplateFile>(context, 'digit_templates.json');
    }
    if (!file || !file.templates || file.templates.length === 0) {
      return false;
    }
    SP.templates = [];
    SP.templatesByDigit = new Array<DigitTemplate[]>(10);
    for (let d: number = 0; d < 10; d++) {
      SP.templatesByDigit[d] = [];
    }
    for (let i: number = 0; i < file.templates.length; i++) {
      const e: DigitTemplateEntry = file.templates[i];
      const kb: Int8Array = new Int8Array(e.key.length);
      let inkC: number = 0;
      for (let j: number = 0; j < e.key.length; j++) {
        kb[j] = e.key[j];
        if (e.key[j] === 1) { inkC++; }
      }
      const tpl: DigitTemplate = {
        digit: e.digit, key: e.key, keyBytes: kb, inkCount: inkC,
        centroidRow: 0, centroidCol: 0, topBottomRatio: 0, leftRightRatio: 0, hasHole: false
      };
      let sumR: number = 0;
      let sumC: number = 0;
      for (let j2: number = 0; j2 < e.key.length; j2++) {
        if (e.key[j2] === 1) {
          sumR += Math.floor(j2 / SIG_COLS);
          sumC += j2 % SIG_COLS;
        }
      }
      tpl.centroidRow = inkC > 0 ? sumR / inkC : -1;
      tpl.centroidCol = inkC > 0 ? sumC / inkC : -1;
      const halfRowT: number = Math.floor(SIG_ROWS / 2);
      const halfColT: number = Math.floor(SIG_COLS / 2);
      let topInkT: number = 0;
      let botInkT: number = 0;
      let leftInkT: number = 0;
      let rightInkT: number = 0;
      for (let j3: number = 0; j3 < e.key.length; j3++) {
        if (e.key[j3] === 1) {
          const rT: number = Math.floor(j3 / SIG_COLS);
          const cT: number = j3 % SIG_COLS;
          if (rT < halfRowT) { topInkT++; } else { botInkT++; }
          if (cT < halfColT) { leftInkT++; } else { rightInkT++; }
        }
      }
      tpl.topBottomRatio = botInkT > 0 ? topInkT / botInkT : 0;
      tpl.leftRightRatio = rightInkT > 0 ? leftInkT / rightInkT : 0;
      tpl.hasHole = holeCenterRow(e.key) >= 0;
      SP.templates.push(tpl);
      if (e.digit >= 0 && e.digit <= 9) {
        SP.templatesByDigit[e.digit].push(tpl);
      }
    }
    SP.holeRows = SP.templates.map((t: DigitTemplate) => holeCenterRow(t.key));
    SP.loaded = true;
    hilog.info(DOMAIN, TAG, '已加载 %{public}d 个数字模板 (%{public}dx%{public}d)', SP.templates.length, SIG_ROWS, SIG_COLS);
    return true;
  } catch (err) {
    hilog.error(DOMAIN, TAG, '加载模板失败: %{public}s', `${(err as Error).message}`);
    return false;
  }
}
