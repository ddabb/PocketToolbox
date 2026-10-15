import { image } from '@kit.ImageKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  OCRResult, PixelConflictCandidate, PerCellVkDiag, AdaptiveResizeParams,
  g_cachedPixels, g_cachedImgW, g_cachedImgH,
  g_probeBbox, g_probeResizeW, g_probeResizeH,
  g_fittedBoardL, g_fittedBoardT, g_fittedBoardR, g_fittedBoardB,
  g_vkFailed,
  g_lastDebugRawDigits, g_perCellVkDiag, g_lastRecognizeDiag,
  g_lastRawInkPerCell,
  setLastDebugFixDetails, setLastDebugConflicts,
  setLastDebugLowConf, setLastDebugEmpty, setLastDebugFixCount, setPerPixelVkDiag
} from './SudokuOCRTypes';
import {
  DOMAIN, TAG, yieldThread, withTimeout, computeAdaptiveResize,
  openImageSource, openImageSourceFromBuffer, cropCellFromBuffer,
  CELL_CROP_PAD_FACTOR, CELL_UPSCALE_FACTOR,
  CELL_CROP_PAD_FACTOR_RETRY, CELL_UPSCALE_FACTOR_RETRY,
  WIDE_CELL_PAD_X_FACTOR, WIDE_CELL_PAD_Y_FACTOR, WIDE_CELL_UPSCALE_FACTOR,
  MIN_CELL_CROP_DIM, PER_CELL_VK_TIMEOUT_MS, MAX_FIX_CELLS,
  VK_SLOW_CALL_THRESHOLD_MS, VK_MAX_CONSECUTIVE_NULL,
  EXISTING_PIXEL_ONLY_OVERRIDE_CONF,
  STABLE_PIXEL_ONLY_OVERRIDE_CONF, EMPTY_FILL_PIXEL_CONF,
  EMPTY_FILL_PIXEL_CONF_NO_RAW_DIGITS, PIXEL_MAX_DIM
} from './SudokuOCRUtils';
import { recognizeDigitVisionKit, recognizeDigitInWideRegion } from './SudokuVKOCR';
import {
  BoardBBox, bgColor, toGrayArray, findBoardBBox,
  getLastConfidence, getLastRawInkRatio, getLastPixelDiag,
  getLastLocalBgInfo, getLastSigMetrics, getLastSigQualityFail,
  getLastSigCompCount, getLastSigLrgRatio, getLastSigHoles, getLastSigInk,
  resetGridLineCrop, detectGridLineWidths,
  MIN_CELL_INK_RATIO
} from './SudokuPixel';
import {
  findConflictCells, isConfusablePair, conflictCountAfterSet, applyBestPixelConflictPair,
  GridFixTargets, computeGridFixTargets
} from './SudokuGridConflict';
import { recognizeDigitPixel } from './SudokuGridPixel';
import {
  applyComboSolverFix, applyConflictGuessSwaps, applySolverUniqueSwaps
} from './SudokuGridSolverFix';
import {
  applyPixelAdjudicationPass, clearFinalNoInkConflicts,
  clearLowConfConflicts, clearHighInkSolidBlocks
} from './SudokuGridClearPasses';

export * from './SudokuGridConflict';
export * from './SudokuGridPixel';
export * from './SudokuGridSolverFix';
export * from './SudokuGridClearPasses';

export async function fixAndFillGrid(ocrResult: OCRResult, imagePath: string, imageBuf: ArrayBuffer | null = null): Promise<OCRResult> {
  if (!ocrResult.success || !ocrResult.grid) { return ocrResult; }
  const grid: number[] = [...ocrResult.grid];

  const targets: GridFixTargets = computeGridFixTargets(ocrResult, grid);
  const conflictIndices: number[] = targets.conflictIndices;
  const lowConfIndices: number[] = targets.lowConfIndices;
  const emptyIndices: number[] = targets.emptyIndices;
  const allFixIndices: number[] = targets.allFixIndices;

  if (allFixIndices.length === 0) {
    hilog.info(DOMAIN, TAG, '【实际修正】无冲突且无空格，直接采用结果');
    setLastDebugFixDetails('');
    setLastDebugConflicts(conflictIndices);
    setLastDebugLowConf(lowConfIndices);
    setLastDebugEmpty(emptyIndices);
    setLastDebugFixCount(0);
    return ocrResult;
  }

  let pixels: Uint8Array;
  let imgW: number = 0;
  let imgH: number = 0;
  let pixelMap: image.PixelMap | null = null;

  if (g_cachedPixels.length > 0 && g_cachedImgW > 0 && g_cachedImgH > 0 &&
      g_probeBbox !== null) {
    pixels = g_cachedPixels;
    imgW = g_cachedImgW;
    imgH = g_cachedImgH;
    hilog.info(DOMAIN, TAG, '【步骤详情】校正复用缓存像素 %{public}dx%{public}d', imgW, imgH);
  } else {
    const imageSource = imageBuf !== null
      ? openImageSourceFromBuffer(imageBuf)
      : openImageSource(imagePath);
    const srcInfo: image.ImageInfo = await withTimeout<image.ImageInfo>(imageSource.getImageInfo(), 5000,
      { size: { width: 0, height: 0 } } as image.ImageInfo);
    if (srcInfo.size.width === 0 || srcInfo.size.height === 0) {
      hilog.error(DOMAIN, TAG, '【步骤详情】getImageInfo超时或失败');
      imageSource.release();
      return ocrResult;
    }
    const origW: number = srcInfo.size.width;
    const origH: number = srcInfo.size.height;

    const resize: AdaptiveResizeParams = computeAdaptiveResize(origW, origH);
    let targetW: number = resize.targetW;
    let targetH: number = resize.targetH;
    const maxDim: number = Math.max(targetW, targetH);
    if (maxDim > PIXEL_MAX_DIM) {
      const scaleDown: number = PIXEL_MAX_DIM / maxDim;
      targetW = Math.round(targetW * scaleDown);
      targetH = Math.round(targetH * scaleDown);
    }

    pixelMap = await withTimeout<image.PixelMap | null>(
      imageSource.createPixelMap({
        desiredSize: { width: targetW, height: targetH },
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
          desiredDynamicRange: image.DecodingDynamicRange.SDR
      }), 5000, null);
    imageSource.release();

    if (pixelMap === null) {
      hilog.error(DOMAIN, TAG, '【步骤详情】createPixelMap超时');
      return ocrResult;
    }

    const info: image.ImageInfo = await withTimeout<image.ImageInfo>(pixelMap.getImageInfo(), 5000,
      { size: { width: 0, height: 0 } } as image.ImageInfo);
    if (info.size.width === 0 || info.size.height === 0) {
      hilog.error(DOMAIN, TAG, '【步骤详情】fixAndFillGrid getImageInfo超时或失败');
      pixelMap.release();
      return ocrResult;
    }
    imgW = info.size.width;
    imgH = info.size.height;

    const buffer: ArrayBuffer = new ArrayBuffer(imgW * imgH * 4);
    try {
      pixelMap.readPixelsToBufferSync(buffer);
    } catch (e) {
      hilog.error(DOMAIN, TAG, '【步骤详情】readPixelsToBufferSync失败');
      pixelMap.release();
      return ocrResult;
    }
    pixels = new Uint8Array(buffer);
  }

  hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 像素加载完成 %{public}dx%{public}d', imgW, imgH);
  const bg: number = bgColor(pixels, imgW, imgH);
  const gray: Float32Array = toGrayArray(pixels, imgW, imgH);

  let bbox: BoardBBox;
  if (g_probeBbox !== null && g_probeResizeW === imgW && g_probeResizeH === imgH) {
    bbox = g_probeBbox;
    hilog.info(DOMAIN, TAG, '【图片与棋盘】校正复用探测bbox [%{public}d,%{public}d,%{public}d,%{public}d] isDark=%{public}d',
      bbox.left, bbox.top, bbox.right, bbox.bottom, bbox.isDark ? 1 : 0);
  } else {
    bbox = findBoardBBox(pixels, imgW, imgH, bg);
    hilog.info(DOMAIN, TAG, '【图片与棋盘】校正重新探测bbox [%{public}d,%{public}d,%{public}d,%{public}d] isDark=%{public}d',
      bbox.left, bbox.top, bbox.right, bbox.bottom, bbox.isDark ? 1 : 0);
  }

  let boardL: number = bbox.left;
  let boardT: number = bbox.top;
  let boardR: number = bbox.right;
  let boardB: number = bbox.bottom;
  if (g_fittedBoardL >= 0 && g_probeResizeW === imgW && g_probeResizeH === imgH) {
    boardL = g_fittedBoardL;
    boardT = g_fittedBoardT;
    boardR = g_fittedBoardR;
    boardB = g_fittedBoardB;
    hilog.info(DOMAIN, TAG, '【图片与棋盘】校正复用拟合bbox [%.1f,%.1f,%.1f,%.1f]',
      boardL, boardT, boardR, boardB);
  }

  const cellW: number = (boardR - boardL) / 9;
  const cellH: number = (boardB - boardT) / 9;
  const padFactor: number = CELL_CROP_PAD_FACTOR;
  const upscale: number = CELL_UPSCALE_FACTOR;

  resetGridLineCrop();
  if (gray.length > 0) {
    detectGridLineWidths(gray, imgW, boardL, boardT, boardR, boardB, bbox.isDark, bg);
    hilog.info(DOMAIN, TAG, '【GridLineCrop】%{public}s', getLastPixelDiag());
  }

  hilog.info(DOMAIN, TAG, '【步骤详情】校正图=%{public}dx%{public}d cell=%.1fx%.1f upscale=%{public}d',
    imgW, imgH, cellW, cellH, upscale);

  let vkInitOk: boolean = false;
  let fixCount: number = 0;
  let vkCellCount: number = 0;
  let vkConsecutiveNull: number = 0;
  let vkSlowMs: number = 0;
  const vkMaxCalls: number = Math.min(allFixIndices.length * 3, MAX_FIX_CELLS);
  let vkCallCount: number = 0;

  if (vkMaxCalls > 0 && pixels.length > 0 && !g_vkFailed) {
    hilog.info(DOMAIN, TAG, 'fixAndFillGrid: VK init attempt, vkMaxCalls=%{public}d pixelsLen=%{public}d vkFailed=%{public}d',
      vkMaxCalls, pixels.length, g_vkFailed ? 1 : 0);
    try {
      const vkInit: boolean = await withTimeout<boolean>(textRecognition.init(), 3000, false);
      vkInitOk = vkInit;
      hilog.info(DOMAIN, TAG, 'fixAndFillGrid: VK init=%{public}d', vkInitOk ? 1 : 0);
      hilog.info(DOMAIN, TAG, 'fixAndFillGrid: VK init=%{public}d', vkInitOk ? 1 : 0);
    } catch (_e) {
      hilog.warn(DOMAIN, TAG, 'fixAndFillGrid: VK init异常 %{public}s', `${_e}`);
      hilog.warn(DOMAIN, TAG, 'fixAndFillGrid: VK init exception: %{public}s', `${_e}`);
    }
  } else {
    hilog.info(DOMAIN, TAG, 'fixAndFillGrid: VK skipped, vkMaxCalls=%{public}d pixelsLen=%{public}d vkFailed=%{public}d',
      vkMaxCalls, pixels.length, g_vkFailed ? 1 : 0);
  }

  setPerPixelVkDiag({ cropFail: 0, noBlock: 0, noCenter: 0, found: 0, samples: [] });
  const fixDetailLines: string[] = [];
  const pixelConflictCandidates: PixelConflictCandidate[] = [];
  const cellConfidence: number[] = new Array<number>(81).fill(1.0);

  for (const idx of allFixIndices) {
    const origDigit: number = grid[idx];
    const row: number = Math.floor(idx / 9);
    const col: number = idx % 9;
    const cellLeft: number = boardL + col * cellW;
    const cellTop: number = boardT + row * cellH;
    const cellLabel: string = `(${row},${col})`;

    let pixelDigit: number | null = null;
    if (gray.length > 0) {
      pixelDigit = await recognizeDigitPixel(gray, imgW, cellLeft, cellTop, cellW, cellH, bbox.isDark, bg, row, col);
    }
    const pixelDiag: string = g_lastRecognizeDiag;
    const pixelQ: string = pixelDigit !== null && pixelDigit > 0 ? ` q=[${getLastSigMetrics()}]` : '';

    let vkDigit: number | null = null;
    let vkCropInfo: string = 'skip';
    const cellRawInk: number = getLastRawInkRatio();
    const cellHasInk: boolean = origDigit !== 0 || pixelDigit !== null || cellRawInk > 0;
    const vkAllowRetry: boolean = cellHasInk;

    if (vkInitOk && vkCallCount < vkMaxCalls && vkConsecutiveNull < VK_MAX_CONSECUTIVE_NULL && vkSlowMs < VK_SLOW_CALL_THRESHOLD_MS * 3) {
      const padW: number = Math.round(cellW * padFactor);
      const padH: number = Math.round(cellH * padFactor);
      const cropX: number = Math.max(Math.floor(cellLeft - padW), 0);
      const cropY: number = Math.max(Math.floor(cellTop - padH), 0);
      const cropX2: number = Math.min(Math.floor(cellLeft + cellW + padW), imgW);
      const cropY2: number = Math.min(Math.floor(cellTop + cellH + padH), imgH);
      const cW: number = cropX2 - cropX;
      const cH: number = cropY2 - cropY;

      if (cW >= MIN_CELL_CROP_DIM && cH >= MIN_CELL_CROP_DIM) {
        const cellPm: image.PixelMap | null = cropCellFromBuffer(pixels, imgW, imgH, cropX, cropY, cW, cH, upscale);
        if (cellPm !== null) {
          const t0: number = Date.now();
          const vkResult: number | null = await withTimeout<number | null>(
            recognizeDigitVisionKit(cellPm), PER_CELL_VK_TIMEOUT_MS, null
          );
          const elapsed: number = Date.now() - t0;
          vkSlowMs = elapsed > VK_SLOW_CALL_THRESHOLD_MS ? elapsed : 0;
          cellPm.release();
          vkCallCount++;
          if (vkResult !== null) {
            vkDigit = vkResult;
            vkConsecutiveNull = 0;
            vkCropInfo = `VK=${vkResult}(${elapsed}ms)`;
          } else {
            if (cellRawInk > 0) {
              vkConsecutiveNull++;
            }
            vkCropInfo = `VK=null(${elapsed}ms)`;
          }
        } else {
          g_perCellVkDiag.cropFail++;
          vkCropInfo = 'cropFail';
        }
      } else {
        vkCropInfo = `tooSmall=${cW}x${cH}`;
      }
    }

    const pStr: string = pixelDigit !== null && pixelDigit > 0 ? `${pixelDigit}` : '-';
    const vStr: string = vkDigit !== null && vkDigit > 0 ? `${vkDigit}` : '-';
    const pixelConf: number = pixelDigit !== null && pixelDigit > 0 ? getLastConfidence() : 0;
    const rawInkRatio: number = getLastRawInkRatio();
    cellConfidence[idx] = pixelConf;

    const pixelQualityFail: boolean = pixelDigit !== null && pixelDigit > 0 && getLastSigQualityFail();
    if (pixelQualityFail && (vkDigit === null || vkDigit === 0)) {
      if (origDigit > 0) {
        const exComp: number = getLastSigCompCount();
        const exLrg: number = getLastSigLrgRatio();
        const exHoles: number = getLastSigHoles();
        const exInk: number = getLastSigInk();
        const exFirstInk: number = g_lastRawInkPerCell.length > idx ? g_lastRawInkPerCell[idx] : 0;
        if (exComp < 5 && exLrg >= 0.75 && exHoles >= 6 && exInk < 265 && exFirstInk < 0.55) {
          cellConfidence[idx] = Math.min(pixelConf, 0.85);
          hilog.info(DOMAIN, TAG, '【逐格修正详情】质量豁免 %{public}s=%{public}d comp=%{public}d lrg=%{public}.2f holes=%{public}d ink=%{public}d firstInk=%{public}.4f',
            cellLabel, origDigit, exComp, exLrg, exHoles, exInk, exFirstInk);
          fixDetailLines.push(`质量豁免${cellLabel}=${origDigit} P=${pStr}${pixelQ} firstInk=${exFirstInk.toFixed(4)} pxDiag=[${pixelDiag}] ${getLastLocalBgInfo()}`);
          continue;
        }
        grid[idx] = 0;
        fixCount++;
        hilog.info(DOMAIN, TAG, '【逐格修正详情】质量清除 %{public}s %{public}d→0', cellLabel, origDigit);
        fixDetailLines.push(`质量清除${cellLabel} ${origDigit}→0 P=${pStr}${pixelQ} pxDiag=[${pixelDiag}] ${getLastLocalBgInfo()}`);
        continue;
      } else {
        fixDetailLines.push(`质量拦P${cellLabel} P=${pStr}→null rawInk=${rawInkRatio.toFixed(4)}${pixelQ} pxDiag=[${pixelDiag}] ${getLastLocalBgInfo()}`);
        pixelDigit = null;
      }
    }

    if (origDigit === 0) {
      let fillDigit: number | null = null;
      let fillSource: string = '';
      const pixelHasInk: boolean = pixelDigit !== null || rawInkRatio > 0;
      if (vkDigit !== null && vkDigit > 0 && pixelHasInk) {
        fillDigit = vkDigit;
        fillSource = 'V';
      } else if (pixelHasInk && vkInitOk && vkCallCount < vkMaxCalls && vkConsecutiveNull < VK_MAX_CONSECUTIVE_NULL &&
        vkSlowMs < VK_SLOW_CALL_THRESHOLD_MS * 3) {
        const retryPadW: number = Math.round(cellW * CELL_CROP_PAD_FACTOR_RETRY);
        const retryPadH: number = Math.round(cellH * CELL_CROP_PAD_FACTOR_RETRY);
        const rcX: number = Math.max(Math.floor(cellLeft - retryPadW), 0);
        const rcY: number = Math.max(Math.floor(cellTop - retryPadH), 0);
        const rcX2: number = Math.min(Math.floor(cellLeft + cellW + retryPadW), imgW);
        const rcY2: number = Math.min(Math.floor(cellTop + cellH + retryPadH), imgH);
        const rcW: number = rcX2 - rcX;
        const rcH: number = rcY2 - rcY;
        if (rcW >= MIN_CELL_CROP_DIM && rcH >= MIN_CELL_CROP_DIM) {
          const retryPm: image.PixelMap | null = cropCellFromBuffer(pixels, imgW, imgH, rcX, rcY, rcW, rcH, CELL_UPSCALE_FACTOR_RETRY);
          if (retryPm !== null) {
            const rt0: number = Date.now();
            const retryResult: number | null = await withTimeout<number | null>(
              recognizeDigitVisionKit(retryPm), PER_CELL_VK_TIMEOUT_MS, null
            );
            const rtElapsed: number = Date.now() - rt0;
            vkSlowMs = rtElapsed > VK_SLOW_CALL_THRESHOLD_MS ? rtElapsed : 0;
            retryPm.release();
            vkCallCount++;
            if (retryResult !== null) {
              vkDigit = retryResult;
              vkConsecutiveNull = 0;
              if (pixelHasInk) {
                fillDigit = retryResult;
                fillSource = `Vretry(${rtElapsed}ms)`;
              }
              vkCropInfo += ` Vretry=${retryResult}(${rtElapsed}ms)`;
            } else {
              vkConsecutiveNull++;
              vkCropInfo += ` Vretry=null(${rtElapsed}ms)`;
            }
          }
        }
      }
      if (fillDigit === null && pixelHasInk && vkInitOk && vkCallCount < vkMaxCalls &&
        vkConsecutiveNull < VK_MAX_CONSECUTIVE_NULL && vkSlowMs < VK_SLOW_CALL_THRESHOLD_MS * 3) {
        const widePadW: number = Math.round(cellW * WIDE_CELL_PAD_X_FACTOR);
        const widePadH: number = Math.round(cellH * WIDE_CELL_PAD_Y_FACTOR);
        const wideX: number = Math.max(Math.floor(cellLeft - widePadW), 0);
        const wideY: number = Math.max(Math.floor(cellTop - widePadH), 0);
        const wideX2: number = Math.min(Math.floor(cellLeft + cellW + widePadW), imgW);
        const wideY2: number = Math.min(Math.floor(cellTop + cellH + widePadH), imgH);
        const wideW: number = wideX2 - wideX;
        const wideH: number = wideY2 - wideY;
        if (wideW >= MIN_CELL_CROP_DIM && wideH >= MIN_CELL_CROP_DIM) {
          const widePm: image.PixelMap | null = cropCellFromBuffer(pixels, imgW, imgH, wideX, wideY, wideW, wideH, WIDE_CELL_UPSCALE_FACTOR);
          if (widePm !== null) {
            const wt0: number = Date.now();
            const wideResult: number | null = await withTimeout<number | null>(
              recognizeDigitInWideRegion(
                widePm, WIDE_CELL_UPSCALE_FACTOR,
                cellLeft - wideX, cellTop - wideY, cellW, cellH
              ), PER_CELL_VK_TIMEOUT_MS, null
            );
            const wtElapsed: number = Date.now() - wt0;
            vkSlowMs = wtElapsed > VK_SLOW_CALL_THRESHOLD_MS ? wtElapsed : 0;
            widePm.release();
            vkCallCount++;
            if (wideResult !== null) {
              vkDigit = wideResult;
              vkConsecutiveNull = 0;
              if (pixelHasInk) {
                fillDigit = wideResult;
                fillSource = `Vwide(${wtElapsed}ms)`;
              }
              vkCropInfo += ` Vwide=${wideResult}(${wtElapsed}ms)`;
            } else {
              vkConsecutiveNull++;
              vkCropInfo += ` Vwide=null(${wtElapsed}ms)`;
            }
          }
        }
      }
      if (fillDigit === null && pixelDigit !== null && pixelDigit > 0) {
        const emptyFillPixelConf: number = g_lastDebugRawDigits === 0 ? EMPTY_FILL_PIXEL_CONF_NO_RAW_DIGITS : EMPTY_FILL_PIXEL_CONF;
        if (rawInkRatio > 0.75) {
          fillDigit = null;
        } else if (pixelConf >= emptyFillPixelConf) {
          fillDigit = pixelDigit;
          fillSource = `P(conf=${pixelConf.toFixed(2)})`;
        } else if (pixelDigit === 1 && pixelConf >= 0.10) {
          if (rawInkRatio > 0.015 && rawInkRatio < 0.50) {
            fillDigit = 1;
            fillSource = `P_1_ink(ratio=${rawInkRatio.toFixed(4)})`;
          }
        }
      }
      if (fillDigit !== null) {
        grid[idx] = fillDigit;
        const newConflicts: number[] = findConflictCells(grid);
        const selfConflict: boolean = newConflicts.some((ci: number) => ci === idx);
        if (selfConflict) {
          grid[idx] = 0;
          let fallbackDigit: number | null = null;
          let fallbackSource: string = '';
          if (fillSource.startsWith('V') && pixelDigit !== null && pixelDigit > 0 && pixelDigit !== fillDigit) {
            grid[idx] = pixelDigit;
            const fbConflicts: number[] = findConflictCells(grid);
            const fbSelf: boolean = fbConflicts.some((ci: number) => ci === idx);
            if (!fbSelf) {
              fallbackDigit = pixelDigit;
              fallbackSource = `P_fb(V=${fillDigit}冲突)`;
            } else {
              grid[idx] = 0;
            }
          }
          if (fallbackDigit === null && fillDigit > 0) {
            const confusableSwaps: number[][] = [[6, 9], [9, 6], [5, 9], [9, 5], [5, 6], [6, 5], [5, 8], [8, 5], [1, 8], [8, 1], [1, 4], [4, 1], [7, 1], [1, 7], [2, 4], [4, 2], [3, 7], [7, 3], [1, 6], [6, 1]];
            let bestSwapFallback: number | null = null;
            let bestSwapConflicts: number = 999;
            for (const pair of confusableSwaps) {
              if (fillDigit === pair[0]) {
                grid[idx] = pair[1];
                const swConflicts: number[] = findConflictCells(grid);
                if (!swConflicts.some((ci: number) => ci === idx) && swConflicts.length < bestSwapConflicts) {
                  bestSwapFallback = pair[1];
                  bestSwapConflicts = swConflicts.length;
                }
                grid[idx] = 0;
              }
            }
            if (bestSwapFallback !== null) {
              fallbackDigit = bestSwapFallback;
              fallbackSource = `swap(${fillDigit}→${bestSwapFallback})`;
            }
          }
          if (fallbackDigit !== null) {
            fixCount++;
            hilog.info(DOMAIN, TAG, '【逐格修正详情】VK冲突回退Pixel %{public}s V=%{public}d冲突→P=%{public}d',
              cellLabel, fillDigit, fallbackDigit);
            fixDetailLines.push(`VK冲突回P${cellLabel} V=${fillDigit}冲突→P=${fallbackDigit} P=${pStr} crop=${vkCropInfo}`);
          } else {
            hilog.info(DOMAIN, TAG, '【逐格修正详情】填充冲突回退 %{public}s %{public}s=%{public}d',
              cellLabel, fillSource, fillDigit);
            fixDetailLines.push(`冲突回填${cellLabel} ${fillSource}=${fillDigit}冲突→留空 P=${pStr} crop=${vkCropInfo}`);
          }
        } else {
          hilog.info(DOMAIN, TAG, '【逐格修正详情】填充 %{public}s 空→%{public}d %{public}s',
            cellLabel, fillDigit, fillSource);
          fixCount++;
          fixDetailLines.push(`填充${cellLabel} 空→${fillDigit} ${fillSource} P=${pStr} V=${vStr} crop=${vkCropInfo}`);
        }
      } else {
        if (pixelHasInk) {
          hilog.info(DOMAIN, TAG, '【留空有墨】%{public}s P=%{public}s V=%{public}s rawInk=%{public}s crop=%{public}s',
            cellLabel, pStr, vStr, rawInkRatio.toFixed(4), vkCropInfo);
        } else if (vkDigit !== null && vkDigit > 0) {
          hilog.info(DOMAIN, TAG, '【VK无墨填充】%{public}s V=%{public}d P=%{public}s rawInk=%{public}s',
            cellLabel, vkDigit, pStr, rawInkRatio.toFixed(4));
        }
        if (rawInkRatio > 0.05 && vkDigit === null && (pixelDigit === null || pixelDigit === 0)) {
          const probeLeft: number | undefined = g_probeBbox?.left;
          const probeTop: number | undefined = g_probeBbox?.top;
          fixDetailLines.push(`高墨VK全null${cellLabel} cell=(${cellLeft.toFixed(0)},${cellTop.toFixed(0)},${cellW.toFixed(0)}x${cellH.toFixed(0)}) board=(${boardL.toFixed(0)},${boardT.toFixed(0)}) probeBbox=(${probeLeft},${probeTop}) fitted=(${g_fittedBoardL.toFixed(0)},${g_fittedBoardT.toFixed(0)}) cellSize=(${cellW.toFixed(1)}x${cellH.toFixed(1)})`);
        }
        fixDetailLines.push(`留空${cellLabel} V=${vStr} P=${pStr} ink=${pixelHasInk ? 1 : 0} rawInk=${rawInkRatio.toFixed(4)} pxDiag=[${pixelDiag}]${pixelQ} ${getLastLocalBgInfo()} ${getLastLocalBgInfo()} crop=${vkCropInfo}`);
      }
      continue;
    }

    let finalDigit: number | null = null;
    let decision: string = '';
    const beforeConflicts: number = findConflictCells(grid).length;
    const origIsConflict: boolean = conflictIndices.some((ci: number) => ci === idx);
    if (pixelDigit !== null && pixelDigit > 0 && vkDigit !== null && vkDigit > 0) {
      if (pixelDigit === vkDigit) {
        finalDigit = pixelDigit;
        decision = 'P=V';
      } else {
        const pConflicts: number = conflictCountAfterSet(grid, idx, pixelDigit);
        const vConflicts: number = conflictCountAfterSet(grid, idx, vkDigit);
        if (vConflicts < pConflicts) {
          finalDigit = vkDigit;
          decision = `P≠V→V(pC=${pConflicts} vC=${vConflicts})`;
        } else if (pConflicts < vConflicts || pixelConf >= EXISTING_PIXEL_ONLY_OVERRIDE_CONF) {
          finalDigit = pixelDigit;
          decision = `P≠V→P(pC=${pConflicts} vC=${vConflicts} conf=${pixelConf.toFixed(2)})`;
        } else if (isConfusablePair(pixelDigit, vkDigit) && pixelConf < EXISTING_PIXEL_ONLY_OVERRIDE_CONF) {
          finalDigit = vkDigit;
          decision = `P≠V→V_confusable(pC=${pConflicts} vC=${vConflicts} conf=${pixelConf.toFixed(2)})`;
        } else {
          finalDigit = origDigit;
          decision = `P≠V→keep(pC=${pConflicts} vC=${vConflicts} conf=${pixelConf.toFixed(2)})`;
        }
      }
    } else if (pixelDigit !== null && pixelDigit > 0) {
      const pConflicts: number = conflictCountAfterSet(grid, idx, pixelDigit);
      const reducesConflict: boolean = pConflicts < beforeConflicts;
      const highConfidence: boolean = pixelConf >= EXISTING_PIXEL_ONLY_OVERRIDE_CONF;
      const likelyCorrection: boolean = isConfusablePair(origDigit, pixelDigit) || ocrResult.confidence === null || origIsConflict;
      const stableConfusableCorrection: boolean = beforeConflicts === 0 && g_lastDebugRawDigits > 0 &&
        ocrResult.confidence !== null && isConfusablePair(origDigit, pixelDigit) &&
        pixelConf >= STABLE_PIXEL_ONLY_OVERRIDE_CONF;
      const hasInk: boolean = rawInkRatio >= MIN_CELL_INK_RATIO;
      const allowLowInk: boolean = isConfusablePair(origDigit, pixelDigit);
      if ((hasInk || (allowLowInk && pixelConf >= 0.40)) && (reducesConflict || highConfidence || stableConfusableCorrection) && likelyCorrection) {
        finalDigit = pixelDigit;
        decision = `P_only(conf=${pixelConf.toFixed(2)} c=${beforeConflicts}→${pConflicts})`;
      } else if ((hasInk || (allowLowInk && pixelConf >= 0.40)) && likelyCorrection && beforeConflicts > 0 && pConflicts <= beforeConflicts + 1) {
        const candidate: PixelConflictCandidate = { idx: idx, digit: pixelDigit, confidence: pixelConf };
        pixelConflictCandidates.push(candidate);
        finalDigit = origDigit;
        decision = `P_only_pair(conf=${pixelConf.toFixed(2)} c=${beforeConflicts}→${pConflicts})`;
      } else {
        finalDigit = origDigit;
        decision = `P_only_keep(conf=${pixelConf.toFixed(2)} c=${beforeConflicts}→${pConflicts})`;
      }
    } else if (vkDigit !== null && vkDigit > 0) {
      if (origDigit > 0 && vkDigit !== origDigit && isConfusablePair(origDigit, vkDigit)) {
        const vConflicts: number = conflictCountAfterSet(grid, idx, vkDigit);
        const oConflicts: number = conflictCountAfterSet(grid, idx, origDigit);
        if (vConflicts < oConflicts) {
          finalDigit = vkDigit;
          decision = `V_only_confusable(c=${oConflicts}→${vConflicts})`;
        } else {
          finalDigit = origDigit;
          decision = `V_only_skip(V=${vkDigit} c=${oConflicts}→${vConflicts})`;
        }
      } else {
        finalDigit = vkDigit;
        decision = 'V_only';
      }
    }

    if (finalDigit !== null && finalDigit > 0 && finalDigit !== origDigit) {
      hilog.info(DOMAIN, TAG, '【逐格修正详情】修正 %{public}s %{public}d -> %{public}d', cellLabel, origDigit, finalDigit);
      grid[idx] = finalDigit;
      fixCount++;

      const newConflicts: number[] = findConflictCells(grid);
      const stillConflict: boolean = newConflicts.some((ci: number) => ci === idx);
      let swapNote: string = '';
      if (stillConflict && (finalDigit === 6 || finalDigit === 9)) {
        const swapped: number = finalDigit === 6 ? 9 : 6;
        grid[idx] = swapped;
        const afterSwap: number[] = findConflictCells(grid);
        const swapConflict: boolean = afterSwap.some((ci: number) => ci === idx);
        if (swapConflict) {
          grid[idx] = finalDigit;
          swapNote = ' 6/9交换仍冲突';
          hilog.info(DOMAIN, TAG, '【逐格修正详情】6/9翻转后仍冲突 保留%{public}d', finalDigit);
        } else {
          hilog.info(DOMAIN, TAG, '【逐格修正详情】6/9翻转 %{public}d -> %{public}d 冲突消除', finalDigit, swapped);
          swapNote = ` 6/9→${swapped}消除`;
        }
      }
      if (stillConflict && (finalDigit === 5 || finalDigit === 9)) {
        const swapped: number = finalDigit === 5 ? 9 : 5;
        grid[idx] = swapped;
        const afterSwap: number[] = findConflictCells(grid);
        const swapConflict: boolean = afterSwap.some((ci: number) => ci === idx);
        if (swapConflict) {
          grid[idx] = finalDigit;
          swapNote += ' 5/9交换仍冲突';
        } else {
          swapNote += ` 5/9→${swapped}消除`;
        }
      }
      if (stillConflict && (finalDigit === 5 || finalDigit === 6)) {
        const swapped: number = finalDigit === 5 ? 6 : 5;
        grid[idx] = swapped;
        const afterSwap: number[] = findConflictCells(grid);
        const swapConflict: boolean = afterSwap.some((ci: number) => ci === idx);
        if (swapConflict) {
          grid[idx] = finalDigit;
          swapNote += ' 5/6交换仍冲突';
        } else {
          swapNote += ` 5/6→${swapped}消除`;
        }
      }

      if (stillConflict && (finalDigit === 7 || finalDigit === 9)) {
        const swapped: number = finalDigit === 7 ? 9 : 7;
        grid[idx] = swapped;
        const afterSwap: number[] = findConflictCells(grid);
        const swapConflict: boolean = afterSwap.some((ci: number) => ci === idx);
        if (swapConflict) {
          grid[idx] = finalDigit;
          swapNote += ' 7/9交换仍冲突';
        } else {
          swapNote += ` 7/9→${swapped}消除`;
        }
      }

      fixDetailLines.push(`修正${cellLabel} ${origDigit}→${finalDigit} P=${pStr} V=${vStr} ${decision}${swapNote} pxDiag=[${pixelDiag}]${pixelQ} ${getLastLocalBgInfo()}`);
    } else if (finalDigit === null && (origDigit === 6 || origDigit === 9)) {
      const isConflict: boolean = conflictIndices.some((ci: number) => ci === idx);
      if (isConflict && rawInkRatio < MIN_CELL_INK_RATIO && pixelDigit === null) {
        grid[idx] = 0;
        fixCount++;
        hilog.info(DOMAIN, TAG, '【逐格修正详情】冲突无墨清除 %{public}s %{public}d→0', cellLabel, origDigit);
        fixDetailLines.push(`清除${cellLabel} ${origDigit}→0 P=${pStr} V=${vStr} 冲突无墨 pxDiag=[${pixelDiag}]${pixelQ} ${getLastLocalBgInfo()}`);
      } else if (isConflict && rawInkRatio >= MIN_CELL_INK_RATIO) {
        const swapped: number = origDigit === 6 ? 9 : 6;
        grid[idx] = swapped;
        const afterSwap: number[] = findConflictCells(grid);
        const swapConflict: boolean = afterSwap.some((ci: number) => ci === idx);
        if (swapConflict) {
          grid[idx] = origDigit;
          fixDetailLines.push(`不变${cellLabel}=${origDigit} P=${pStr} V=${vStr} ${decision} 6/9冲突交换失败 pxDiag=[${pixelDiag}]${pixelQ} ${getLastLocalBgInfo()}`);
        } else {
          fixCount++;
          hilog.info(DOMAIN, TAG, '【逐格修正详情】6/9冲突交换 %{public}s %{public}d -> %{public}d', cellLabel, origDigit, swapped);
          fixDetailLines.push(`修正${cellLabel} ${origDigit}→${swapped} P=${pStr} V=${vStr} 冲突6/9交换 pxDiag=[${pixelDiag}]${pixelQ} ${getLastLocalBgInfo()}`);
        }
      } else {
        fixDetailLines.push(`不变${cellLabel}=${origDigit} P=${pStr} V=${vStr} ${decision} pxDiag=[${pixelDiag}]${pixelQ} ${getLastLocalBgInfo()}`);
      }
    } else if (finalDigit === null && origDigit > 0) {
      const isConflict: boolean = conflictIndices.some((ci: number) => ci === idx);
      if (isConflict && rawInkRatio < MIN_CELL_INK_RATIO && pixelDigit === null) {
        grid[idx] = 0;
        fixCount++;
        hilog.info(DOMAIN, TAG, '【逐格修正详情】冲突无墨清除 %{public}s %{public}d→0', cellLabel, origDigit);
        fixDetailLines.push(`清除${cellLabel} ${origDigit}→0 P=${pStr} V=${vStr} 冲突无墨 pxDiag=[${pixelDiag}]${pixelQ} ${getLastLocalBgInfo()}`);
      } else if (isConflict && rawInkRatio >= MIN_CELL_INK_RATIO) {
        let swappedOk: boolean = false;
        let swapDigit: number = origDigit;
        const confusableSwaps: number[][] = [[5, 9], [9, 5], [5, 6], [6, 5], [7, 9], [9, 7]];
        for (const pair of confusableSwaps) {
          if (origDigit === pair[0]) {
            grid[idx] = pair[1];
            const afterSwap: number[] = findConflictCells(grid);
            if (!afterSwap.some((ci: number) => ci === idx)) {
              swapDigit = pair[1];
              swappedOk = true;
              break;
            }
            grid[idx] = origDigit;
          }
        }
        if (swappedOk) {
          fixCount++;
          hilog.info(DOMAIN, TAG, '【逐格修正详情】冲突交换 %{public}s %{public}d -> %{public}d', cellLabel, origDigit, swapDigit);
          fixDetailLines.push(`修正${cellLabel} ${origDigit}→${swapDigit} P=${pStr} V=${vStr} 冲突交换 pxDiag=[${pixelDiag}]${pixelQ} ${getLastLocalBgInfo()}`);
        } else {
          fixDetailLines.push(`不变${cellLabel}=${origDigit} P=${pStr} V=${vStr} ${decision} 冲突交换失败 pxDiag=[${pixelDiag}]${pixelQ} ${getLastLocalBgInfo()}`);
        }
      } else {
        fixDetailLines.push(`不变${cellLabel}=${origDigit} P=${pStr} V=${vStr} ${decision} pxDiag=[${pixelDiag}]${pixelQ} ${getLastLocalBgInfo()}`);
      }
    } else {
      fixDetailLines.push(`不变${cellLabel}=${origDigit} P=${pStr} V=${vStr} ${decision} pxDiag=[${pixelDiag}]${pixelQ} ${getLastLocalBgInfo()}`);
    }
    if (col === 8) { await yieldThread(); }
  }

  const pairFixDetail: string = applyBestPixelConflictPair(grid, pixelConflictCandidates);
  if (pairFixDetail.length > 0) {
    fixCount += 2;
    fixDetailLines.push(pairFixDetail);
  }

  const remainingCandidates: PixelConflictCandidate[] = [];
  for (const cand of pixelConflictCandidates) {
    if (grid[cand.idx] === cand.digit) { continue; }
    if (!isConfusablePair(grid[cand.idx], cand.digit)) { continue; }
    const gv: number = grid[cand.idx];
    const only69: boolean = (gv === 6 && cand.digit === 9) || (gv === 9 && cand.digit === 6);
    if (!only69 && cand.confidence < EXISTING_PIXEL_ONLY_OVERRIDE_CONF) { continue; }
    remainingCandidates.push(cand);
  }
  if (remainingCandidates.length > 0) {
    remainingCandidates.sort((a: PixelConflictCandidate, b: PixelConflictCandidate): number => {
      return b.confidence - a.confidence;
    });
    for (const rc of remainingCandidates) {
      const origVal: number = grid[rc.idx];
      grid[rc.idx] = rc.digit;
      const afterConflicts: number[] = findConflictCells(grid);
      const selfConflict: boolean = afterConflicts.some((ci: number) => ci === rc.idx);
      if (!selfConflict) {
        fixCount++;
        const rcRow: number = Math.floor(rc.idx / 9);
        const rcCol: number = rc.idx % 9;
        hilog.info(DOMAIN, TAG, '【逐格修正详情】剩余6/9修正 (%{public}d,%{public}d) %{public}d→%{public}d conf=%{public}.2f',
          rcRow, rcCol, origVal, rc.digit, rc.confidence);
        fixDetailLines.push(`剩余6/9修正(${rcRow},${rcCol}) ${origVal}→${rc.digit} conf=${rc.confidence.toFixed(2)}`);
      } else {
        grid[rc.idx] = origVal;
      }
    }
  }

  const diag: PerCellVkDiag = g_perCellVkDiag;
  const diagTotal: number = diag.cropFail + diag.noBlock + diag.noCenter + diag.found;
  hilog.info(DOMAIN, TAG, '【逐格VK诊断】尝试%{public}d次 成功%{public}d 裁剪失败%{public}d 无block%{public}d 无中心%{public}d',
    diagTotal, diag.found, diag.cropFail, diag.noBlock, diag.noCenter);
  if (diagTotal > 0) {
    const diagLines: string[] = [];
    diagLines.push(`【逐格VK诊断】尝试${diagTotal}次 成功${diag.found} 裁剪失败${diag.cropFail} 无block${diag.noBlock} 无中心${diag.noCenter}`);
    if (diag.samples.length > 0) {
      diagLines.push(`  样本: ${diag.samples.join(' | ')}`);
    }
    fixDetailLines.unshift(diagLines.join('\n'), '');
  }
  setLastDebugFixDetails(fixDetailLines.join('\n'));
  for (let fi: number = 0; fi < fixDetailLines.length; fi += 10) {
    const chunkEnd: number = Math.min(fi + 10, fixDetailLines.length);
    hilog.info(DOMAIN, TAG, '【逐格修正详情】%{public}d-%{public}d/%{public}d %{public}s',
      fi, chunkEnd - 1, fixDetailLines.length,
      fixDetailLines.slice(fi, chunkEnd).join(' | '));
  }

  hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 循环结束 fixCount=%{public}d', fixCount);

  if (gray.length > 0) {
    fixCount += await applyPixelAdjudicationPass(grid, cellConfidence, gray, imgW, boardL, boardT, cellW, cellH, bbox, bg);
  }

  fixCount += applyComboSolverFix(grid, cellConfidence);

  fixCount += await applyConflictGuessSwaps(grid, cellConfidence);

  fixCount += await clearFinalNoInkConflicts(grid, gray, imgW, boardL, boardT, cellW, cellH, bbox, bg);
  let remainingConflicts: number[] = findConflictCells(grid);

  if (remainingConflicts.length > 0 && gray.length > 0) {
    fixCount += await clearLowConfConflicts(grid, remainingConflicts, gray, imgW, boardL, boardT, cellW, cellH, bbox, bg);
  }
  remainingConflicts = findConflictCells(grid);

  if (gray.length > 0) {
    fixCount += await clearHighInkSolidBlocks(grid, remainingConflicts, gray, imgW, boardL, boardT, cellW, cellH, bbox, bg);
  }
  remainingConflicts = findConflictCells(grid);

  if (remainingConflicts.length > 0) {
    hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 最终冲突%{public}d个(无法交换)', remainingConflicts.length);
  }

  fixCount += applySolverUniqueSwaps(grid, cellConfidence, fixCount > 0);

  if (pixelMap !== null) {
    pixelMap.release();
  }

  setLastDebugConflicts(conflictIndices);
  setLastDebugLowConf(lowConfIndices);
  setLastDebugEmpty(emptyIndices);
  setLastDebugFixCount(fixCount);

  if (fixCount > 0) {
    hilog.info(DOMAIN, TAG, '【实际修正】修正了%{public}d个格子', fixCount);
    return { success: true, grid: grid, rawText: ocrResult.rawText + '+conflictFix', error: '', confidence: ocrResult.confidence, debugInfo: null };
  }
  return ocrResult;
}
