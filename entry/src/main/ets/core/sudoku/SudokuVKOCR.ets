import { image } from '@kit.ImageKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { g_perCellVkDiag, PerCellVkDiag } from './SudokuOCRTypes';
import { DOMAIN, TAG } from './SudokuOCRUtils';

export async function recognizeDigitVisionKit(cellPm: image.PixelMap): Promise<number | null> {
  try {
    const visionInfo: textRecognition.VisionInfo = { pixelMap: cellPm };
    const recogResult: textRecognition.TextRecognitionResult =
      await textRecognition.recognizeText(visionInfo, {
        isDirectionDetectionSupported: false
      });

    const rawText: string = recogResult.value || '';
    const nonDigitRe: RegExp = new RegExp('[^0-9]', 'g');
    const digits: string[] = rawText.replace(nonDigitRe, '').split('');
    if (digits.length === 0) { return null; }

    const digitCounts: Map<number, number> = new Map<number, number>();
    for (const ch of digits) {
      const d: number = parseInt(ch, 10);
      const prev: number | undefined = digitCounts.get(d);
      digitCounts.set(d, prev !== undefined ? prev + 1 : 1);
    }

    let bestDigit: number = parseInt(digits[0], 10);
    let bestCount: number = 0;
    digitCounts.forEach((count: number, digit: number) => {
      if (count > bestCount) {
        bestCount = count;
        bestDigit = digit;
      }
    });

    hilog.info(DOMAIN, TAG, '【逐格修正详情】单格识别 rawText="%{public}s" bestDigit=%{public}d', rawText, bestDigit);
    return bestDigit;
  } catch (_e) {
    hilog.error(DOMAIN, TAG, 'VisionKit重识异常: %{public}s', `${_e}`);
    return null;
  }
}

export async function recognizeDigitInWideRegion(
  cellPm: image.PixelMap,
  upscale: number,
  centerCellX: number, centerCellY: number,
  centerCellW: number, centerCellH: number
): Promise<number | null> {
  const diag: PerCellVkDiag = g_perCellVkDiag;
  try {
    const visionInfo: textRecognition.VisionInfo = { pixelMap: cellPm };
    const recogResult: textRecognition.TextRecognitionResult =
      await textRecognition.recognizeText(visionInfo, {
        isDirectionDetectionSupported: false
      });

    const rawText: string = recogResult.value || '';
    if (diag.samples.length < 3) {
      const blockArr: Array<textRecognition.TextBlock> = recogResult.blocks || [];
      diag.samples.push(`raw="${rawText.slice(0, 30)}" blocks=${blockArr.length}`);
    }
    hilog.info(DOMAIN, TAG, '【逐格修正详情】宽域识 raw="%{public}s" blocks=%{public}d',
      rawText, (recogResult.blocks || []).length);

    const blocks: Array<textRecognition.TextBlock> = recogResult.blocks || [];
    if (blocks.length === 0) {
      diag.noBlock++;
      if (rawText.length === 0) { return null; }
      hilog.info(DOMAIN, TAG, '【逐格修正详情】宽域识无block 留空 raw="%{public}s"', rawText);
      return null;
    }

    const cxMin: number = centerCellX * upscale;
    const cxMax: number = (centerCellX + centerCellW) * upscale;
    const cyMin: number = centerCellY * upscale;
    const cyMax: number = (centerCellY + centerCellH) * upscale;

    const centerCandidates: number[] = [];
    let wordCount: number = 0;
    let cpCount: number = 0;

    for (const block of blocks) {
      const lines: Array<textRecognition.TextLine> = block.lines || [];
      for (const line of lines) {
        const words: Array<textRecognition.TextWord> = line.words || [];
        for (const word of words) {
          wordCount++;
          const text: string = word.value.trim();
          const cp: Array<textRecognition.PixelPoint> = word.cornerPoints;
          if (cp.length < 4) { continue; }
          cpCount++;

          const wcx: number = (cp[0].x + cp[2].x) / 2;
          const wcy: number = (cp[0].y + cp[2].y) / 2;

          const inCenter: boolean = (wcx >= cxMin && wcx < cxMax && wcy >= cyMin && wcy < cyMax);

          const nonDigitRe: RegExp = new RegExp('[^0-9]', 'g');
          const ds: string[] = text.replace(nonDigitRe, '').split('');
          for (const ch of ds) {
            const d: number = parseInt(ch, 10);
            if (d >= 1 && d <= 9) {
              if (inCenter) {
                centerCandidates.push(d);
              }
            }
          }
        }
      }
    }

    if (centerCandidates.length > 0) {
      const cntMap: Map<number, number> = new Map();
      for (const d of centerCandidates) {
        cntMap.set(d, (cntMap.get(d) || 0) + 1);
      }
      let best: number = 0;
      let bestCnt: number = 0;
      cntMap.forEach((c: number, d: number) => { if (c > bestCnt) { bestCnt = c; best = d; } });
      hilog.info(DOMAIN, TAG, '【逐格修正详情】宽域识定位成功 centerCandidates=%{public}s best=%{public}d',
        centerCandidates.join(','), best);
      diag.found++;
      return best;
    }

    diag.noCenter++;
    hilog.info(DOMAIN, TAG, '【逐格修正详情】宽域识定位失败 留空 words=%{public}d cpWords=%{public}d center=[%.0f-%.0f, %.0f-%.0f] upscale=%{public}d',
      wordCount, cpCount, cxMin, cxMax, cyMin, cyMax, upscale);
    return null;
  } catch (_e) {
    hilog.error(DOMAIN, TAG, 'VisionKit宽域识异常: %{public}s', `${_e}`);
    diag.noBlock++;
    return null;
  }
}
