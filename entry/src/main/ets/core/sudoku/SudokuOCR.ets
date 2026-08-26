import { OCRResult, OCRDebugInfo, OCRDebugStep, g_debugInfo, g_fittedBoardL, g_fittedBoardT, g_fittedBoardR, g_fittedBoardB, g_cachedPixels, g_cachedImgW, g_cachedImgH, g_vkFailed, g_lastDebugBbox, g_lastDebugResize, g_lastDebugRawDigits, g_lastDebugConflicts, g_lastDebugLowConf, g_lastDebugEmpty, g_lastDebugFixCount, setDebugInfo, setFittedBoardL, setFittedBoardT, setFittedBoardR, setFittedBoardB, setCachedPixels, setCachedImgW, setCachedImgH, setVkFailed, setLastDebugBbox, setLastDebugResize, setLastDebugRawDigits, setLastDebugConflicts, setLastDebugLowConf, setLastDebugEmpty, setLastDebugFixCount } from './SudokuOCRTypes';
import { DOMAIN, TAG, OCR_PIPELINE_TOTAL_TIMEOUT_MS, withTimeout } from './SudokuOCRUtils';
import { buildDebugInfo } from './SudokuOCRDebug';
import { tryVisionKitRecognition } from './SudokuVKOCR';
import { tryPixelGridRecognition } from './SudokuPixelOCR';
import { fixAndFillGrid } from './SudokuGridFix';
import { resetChannelBgCache } from './SudokuPixel';
import { hilog } from '@kit.PerformanceAnalysisKit';

export { OCRResult, OCRDebugInfo, OCRDebugStep, getOCRDebugInfo, getLastPixelConfidence } from './SudokuOCRTypes';
export { analyzePixelGridFromBuffer, analyzePixelGridFromBufferAsync } from './SudokuPixelOCR';

export async function recognizeSudokuFromBuffer(buf: ArrayBuffer, pixelOnly: boolean = false): Promise<OCRResult> {
  setDebugInfo(null);
  setFittedBoardL(-1);
  setFittedBoardT(-1);
  setFittedBoardR(-1);
  setFittedBoardB(-1);
  setCachedPixels(new Uint8Array(0));
  setCachedImgW(0);
  setCachedImgH(0);
  resetChannelBgCache();
  setVkFailed(pixelOnly);
  const steps: OCRDebugStep[] = [];
  const pipelineStart: number = Date.now();
  try {
    hilog.info(DOMAIN, TAG, '=== recognizeSudokuFromBuffer START ===');
    hilog.info(DOMAIN, TAG, '=== 识别调试信息(buffer) ===');

    steps.push({ step: '1. 像素分析', detail: '开始(buffer)' });
    hilog.info(DOMAIN, TAG, '>>> tryPixelGridRecognition');
    hilog.info(DOMAIN, TAG, '>>> tryPixelGridRecognition 开始');
    const pixelResult: OCRResult = await tryPixelGridRecognition('', buf);
    const pixelDigits: number = pixelResult.grid !== null ? pixelResult.grid.filter((d: number) => d > 0).length : 0;
    hilog.info(DOMAIN, TAG, '<<< tryPixelGridRecognition success=%{public}d digits=%{public}d elapsed=%{public}dms',
      pixelResult.success ? 1 : 0, pixelDigits, Date.now() - pipelineStart);
    hilog.info(DOMAIN, TAG, '<<< tryPixelGridRecognition 返回 success=%{public}d digits=%{public}d', pixelResult.success ? 1 : 0, pixelDigits);

    if (pixelResult.success && pixelResult.grid && pixelDigits > 0) {
      steps.push({ step: '2. 像素分析结果', detail: `成功, ${pixelDigits}个数字` });
      const pixelGrid: number[] = [...pixelResult.grid];

      if (pixelDigits < 20 && !pixelOnly) {
        hilog.info(DOMAIN, TAG, 'pixelDigits=%{public}d < 20, trying VK full-page OCR', pixelDigits);
        hilog.info(DOMAIN, TAG, '【步骤详情】像素识别数不足%{public}d个，转VK全页识别', pixelDigits);
        const visionResult: OCRResult = await tryVisionKitRecognition('', buf);
        const vkDigits: number = visionResult.grid !== null ? visionResult.grid.filter((d: number) => d > 0).length : 0;
        hilog.info(DOMAIN, TAG, 'VK full-page: success=%{public}d digits=%{public}d', visionResult.success ? 1 : 0, vkDigits);
        hilog.info(DOMAIN, TAG, 'VK全页识别 success=%{public}d digits=%{public}d', visionResult.success ? 1 : 0, vkDigits);

        if (visionResult.success && visionResult.grid && vkDigits > pixelDigits) {
          hilog.info(DOMAIN, TAG, 'VK (%{public}d digits) better than pixel (%{public}d), using VK', vkDigits, pixelDigits);
          hilog.info(DOMAIN, TAG, 'VK结果更优，采用VK');
          const vkGrid: number[] = [...visionResult.grid];
          const corrected: OCRResult = await fixAndFillGrid(visionResult, '', buf);
          setDebugInfo(buildDebugInfo(
            'VK全页+修正',
            steps,
            g_lastDebugBbox,
            g_lastDebugResize,
            g_lastDebugRawDigits,
            vkGrid,
            null,
            corrected.grid,
            g_lastDebugConflicts,
            g_lastDebugLowConf,
            g_lastDebugEmpty,
            g_lastDebugFixCount,
            corrected.confidence
          ));
          return corrected;
        }
      }

      const corrected: OCRResult = await fixAndFillGrid(pixelResult, '', buf);
      hilog.info(DOMAIN, TAG, '<<< fixAndFillGrid success=%{public}d elapsed=%{public}dms',
        corrected.success ? 1 : 0, Date.now() - pipelineStart);
      setDebugInfo(buildDebugInfo(
        '像素分析+修正',
        steps,
        g_lastDebugBbox,
        g_lastDebugResize,
        0,
        pixelGrid,
        null,
        corrected.grid,
        g_lastDebugConflicts,
        g_lastDebugLowConf,
        g_lastDebugEmpty,
        g_lastDebugFixCount,
        corrected.confidence
      ));
      return corrected;
    }

    steps.push({ step: '2. 像素分析失败', detail: pixelResult.error });
      hilog.info(DOMAIN, TAG, '像素分析失败, 转VisionKit');
    hilog.info(DOMAIN, TAG, '【步骤详情】像素分析失败，转VisionKit识别');
    if (!pixelOnly) {
      hilog.info(DOMAIN, TAG, '>>> tryVisionKitRecognition 开始');
      const visionResult: OCRResult = await tryVisionKitRecognition('', buf);
      hilog.info(DOMAIN, TAG, '<<< tryVisionKitRecognition 返回 success=%{public}d', visionResult.success ? 1 : 0);
      if (visionResult.success && visionResult.grid) {
        const vkGrid: number[] = [...visionResult.grid];
        steps.push({ step: '3. VisionKit结果', detail: `成功, ${visionResult.grid.filter((d: number) => d > 0).length}个数字` });
        const corrected: OCRResult = await fixAndFillGrid(visionResult, '', buf);
        setDebugInfo(buildDebugInfo(
          'VisionKit+修正',
          steps,
          g_lastDebugBbox,
          g_lastDebugResize,
          g_lastDebugRawDigits,
          vkGrid,
          null,
          corrected.grid,
          g_lastDebugConflicts,
          g_lastDebugLowConf,
          g_lastDebugEmpty,
          g_lastDebugFixCount,
          corrected.confidence
        ));
        return corrected;
      }
    }

    return pixelResult;
  } catch (_err) {
    hilog.error(DOMAIN, TAG, '异常: %{public}s', `${_err}`);
    hilog.error(DOMAIN, TAG, '异常: %{public}s', `${_err}`);
    return { success: false, grid: null, rawText: '', error: '图片处理异常，请尝试手动输入', confidence: null, debugInfo: null };
  }
}

export async function recognizeSudokuFromImage(imagePath: string): Promise<OCRResult> {
  setDebugInfo(null);
  setFittedBoardL(-1);
  setFittedBoardT(-1);
  setFittedBoardR(-1);
  setFittedBoardB(-1);
  resetChannelBgCache();
  const steps: OCRDebugStep[] = [];
  try {
    hilog.info(DOMAIN, TAG, '=== 识别调试信息 ===');
    hilog.info(DOMAIN, TAG, '【流水线】VisionKit+修正 (首次尝试)');
    steps.push({ step: '1. VisionKit识别', detail: '开始' });
    const visionResult: OCRResult = await tryVisionKitRecognition(imagePath);
    hilog.info(DOMAIN, TAG, '【步骤详情】VisionKit识别 success=%{public}d error=%{public}s', visionResult.success ? 1 : 0, visionResult.error);
    if (visionResult.success && visionResult.grid) {
      const vkGrid: number[] = [...visionResult.grid];
      steps.push({ step: '2. VisionKit结果', detail: `成功, ${visionResult.grid.filter((d: number) => d > 0).length}个数字` });
      const corrected: OCRResult = await fixAndFillGrid(visionResult, imagePath);
      setDebugInfo(buildDebugInfo(
        'VisionKit+修正',
        steps,
        g_lastDebugBbox,
        g_lastDebugResize,
        g_lastDebugRawDigits,
        vkGrid,
        null,
        corrected.grid,
        g_lastDebugConflicts,
        g_lastDebugLowConf,
        g_lastDebugEmpty,
        g_lastDebugFixCount,
        corrected.confidence
      ));
    return corrected;
    }
    steps.push({ step: '2. VisionKit失败', detail: visionResult.error });
    hilog.info(DOMAIN, TAG, '【步骤详情】VisionKit失败，转像素分析');
    const pixelResult: OCRResult = await tryPixelGridRecognition(imagePath);
    setDebugInfo(buildDebugInfo(
      '像素分析',
      steps,
      g_lastDebugBbox,
      g_lastDebugResize,
      0,
      null,
      pixelResult.grid,
      pixelResult.grid,
      [],
      [],
      [],
      0,
      pixelResult.confidence
    ));
    return pixelResult;
  } catch (_err) {
    hilog.error(DOMAIN, TAG, '异常: %{public}s', `${_err}`);
    return { success: false, grid: null, rawText: '', error: '图片处理异常，请尝试手动输入', confidence: null, debugInfo: null };
  }
}
