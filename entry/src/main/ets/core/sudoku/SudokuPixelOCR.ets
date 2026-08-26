import { OCRResult, CellCoordInfo, AdaptiveResizeParams,
  g_lastPixelConfidence, g_lastCellCoords, g_cachedPixels, g_cachedImgW, g_cachedImgH,
  g_probeBbox, g_probeResizeW, g_probeResizeH,
  g_lastDebugPixelBgInfo, g_lastDebugPixelBboxLocator, g_lastDebugPixelWarpInfo,
  g_lastDebugPixelCellStats, g_lastDebugPixelCellCoords,
  setLastPixelConfidence, setLastCellCoords, setCachedPixels, setCachedImgW, setCachedImgH,
  setProbeBbox, setProbeResizeW, setProbeResizeH,
  setLastDebugPixelBgInfo, setLastDebugPixelBboxLocator, setLastDebugPixelWarpInfo,
  setLastDebugPixelCellStats, setLastDebugPixelCellCoords } from './SudokuOCRTypes';
import { DOMAIN, TAG, yieldThread, withTimeout, computeAdaptiveResize,
  openImageSource, openImageSourceFromBuffer, PIXEL_MAX_DIM, BG_DARK_THRESHOLD,
  WARP_SIZE_MULTIPLIER, WARP_BG_SAMPLE_DIV } from './SudokuOCRUtils';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BoardBBox, BoardCorners, GridLines, bgColor, cellSigFromGray, cellSigFromGrayLowThresh,
  cellSigFromGrayThin, countInk, detectBoardCorners, detectGridLineWidths, findBoardBBox,
  findBoxLongRun, getLastBboxDiag, getLastConfidence, getLastRawInkRatio, MIN_CELL_INK_RATIO,
  resetChannelBgCache, resetGridLineCrop, isGridLineCropDetected, findPreciseGridLines,
  toGrayArray, validateCellCentering, warpPerspectiveGray, INK_THRESH, recognizeDigit } from './SudokuPixel';
import { taskpool } from '@kit.ArkTS';

export async function tryPixelGridRecognition(imagePath: string, imageBuf: ArrayBuffer | null = null): Promise<OCRResult> {
  let pixelMap: image.PixelMap | null = null;
  try {
    hilog.info(DOMAIN, TAG, 'Pixel: start');
    const imageSource: image.ImageSource = imageBuf !== null ? openImageSourceFromBuffer(imageBuf) : openImageSource(imagePath);

    hilog.info(DOMAIN, TAG, 'Pixel: await imageSource.getImageInfo()');
    const srcInfo: image.ImageInfo = await withTimeout<image.ImageInfo>(imageSource.getImageInfo(), 5000,
      { size: { width: 0, height: 0 } } as image.ImageInfo);
    if (srcInfo.size.width === 0 || srcInfo.size.height === 0) {
      hilog.warn(DOMAIN, TAG, 'Pixel: getImageInfo timeout or failed');
      hilog.error(DOMAIN, TAG, 'Pixel: getImageInfo超时或失败');
      imageSource.release();
      return { success: false, grid: null, rawText: '', error: 'getImageInfo超时', confidence: null, debugInfo: null };
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
    hilog.info(DOMAIN, TAG, '【缩放参数】原图%{public}dx%{public}d -> %{public}dx%{public}d', origW, origH, targetW, targetH);

    hilog.info(DOMAIN, TAG, 'Pixel: await createPixelMap()');
    pixelMap = await withTimeout<image.PixelMap | null>(imageSource.createPixelMap({
      desiredSize: { width: targetW, height: targetH },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    }), 5000, null);
    imageSource.release();

    if (pixelMap === null) {
      hilog.error(DOMAIN, TAG, 'Pixel: createPixelMap超时');
      return { success: false, grid: null, rawText: '', error: 'createPixelMap超时', confidence: null, debugInfo: null };
    }
    hilog.info(DOMAIN, TAG, 'Pixel: createPixelMap OK');

    const imageInfo: image.ImageInfo = await pixelMap.getImageInfo();
    const width: number = imageInfo.size.width;
    const height: number = imageInfo.size.height;

    const pixelBuf: ArrayBuffer = new ArrayBuffer(width * height * 4);
    pixelMap.readPixelsToBuffer(pixelBuf);
    const pixelBytes: Uint8Array = new Uint8Array(pixelBuf);
    setCachedPixels(pixelBytes);
    setCachedImgW(width);
    setCachedImgH(height);

    const pxBg: number = bgColor(pixelBytes, width, height);
    const pxBbox: BoardBBox = findBoardBBox(pixelBytes, width, height, pxBg);
    setProbeBbox({ left: pxBbox.left, top: pxBbox.top, right: pxBbox.right, bottom: pxBbox.bottom, isDark: pxBbox.isDark });
    setProbeResizeW(width);
    setProbeResizeH(height);

    hilog.info(DOMAIN, TAG, 'Pixel: 开始 analyzePixelGrid');
    const grid: number[] = await analyzePixelGridFromBufferAsync(pixelBytes, width, height);
    const givenCount: number = grid.filter((d: number) => d > 0).length;
    hilog.info(DOMAIN, TAG, 'Pixel: analyzePixelGrid done digits=%{public}d', givenCount);
    hilog.info(DOMAIN, TAG, 'Pixel: analyzePixelGrid 完成 digits=%{public}d', givenCount);
    pixelMap.release();
    pixelMap = null;

    hilog.info(DOMAIN, TAG, '【步骤详情】像素分析完成 识别到%{public}d个数字', givenCount);
    if (givenCount > 0) {
      const confCopy: number[] = new Array<number>(g_lastPixelConfidence.length);
      for (let i: number = 0; i < g_lastPixelConfidence.length; i++) {
        confCopy[i] = g_lastPixelConfidence[i];
      }
      return { success: true, grid: grid, rawText: 'pixel analysis', error: '', confidence: confCopy, debugInfo: null };
    }
    hilog.warn(DOMAIN, TAG, 'Pixel: no digits found');
    return {
      success: false, grid: null, rawText: '',
      error: '未能识别数独，请确保图片清晰或手动输入',
      confidence: null,
      debugInfo: null
    };
  } catch (_err) {
    hilog.error(DOMAIN, TAG, '像素分析异常: %{public}s', `${_err}`);
    if (pixelMap !== null) { pixelMap.release(); }
    return { success: false, grid: null, rawText: '', error: '图片分析失败', confidence: null, debugInfo: null };
  }
}

export function analyzePixelGridFromBuffer(pixels: Uint8Array, width: number, height: number): number[] {
  const grid: number[] = new Array<number>(81).fill(0);
  setLastPixelConfidence(new Array<number>(81).fill(0));

  const bg: number = bgColor(pixels, width, height);
  const gray: Float32Array = toGrayArray(pixels, width, height);
  const isDark: boolean = bg < BG_DARK_THRESHOLD;

  const bgHist: number[] = new Array<number>(256).fill(0);
  const bgSampleStep2: number = Math.max(1, Math.floor(width * height / 20000));
  let bgMin2: number = 255;
  let bgMax2: number = 0;
  for (let i: number = 0; i < width * height; i += bgSampleStep2) {
    const g: number = Math.floor(gray[i]);
    if (g >= 0 && g <= 255) { bgHist[g]++; }
    if (g < bgMin2) { bgMin2 = g; }
    if (g > bgMax2) { bgMax2 = g; }
  }
  let bgHistTop3Str: string = '';
  let tmpMax2: number = -1;
  const bgHistCopy: number[] = new Array<number>(256);
  for (let i: number = 0; i < 256; i++) {
    bgHistCopy[i] = bgHist[i];
  }
  for (let pass: number = 0; pass < 3; pass++) {
    let topI: number = 0;
    let topV: number = 0;
    for (let i: number = 0; i < 256; i++) {
      if (bgHistCopy[i] > topV) {
        topV = bgHistCopy[i];
        topI = i;
      }
    }
    if (topV > 0) {
      bgHistTop3Str += (bgHistTop3Str.length > 0 ? ', ' : '') + `${topI}(${topV})`;
      bgHistCopy[topI] = 0;
    }
  }
  setLastDebugPixelBgInfo(`size=${width}x${height} bg=${bg.toFixed(1)} isDark=${isDark ? 1 : 0} bgRange=[${bgMin2},${bgMax2}] bgHistTop3=[${bgHistTop3Str}] threshold=${BG_DARK_THRESHOLD}`);

  const bbox: BoardBBox = findBoardBBox(pixels, width, height, bg);
  const cellW: number = (bbox.right - bbox.left) / 9;
  const cellH: number = (bbox.bottom - bbox.top) / 9;
  const isFullImage: boolean = bbox.left === 0 && bbox.top === 0 &&
    bbox.right === width && bbox.bottom === height;
  const boardAreaRatio2: number = (bbox.right - bbox.left) * (bbox.bottom - bbox.top) / (width * height);

  const longRunResult: BoardBBox | null = findBoxLongRun(gray, width, height, isDark, bg);
  const longRunInfo: string = longRunResult !== null
    ? `OK [${longRunResult.left},${longRunResult.top},${longRunResult.right},${longRunResult.bottom}]`
    : '失败';
  setLastDebugPixelBboxLocator(`longRun=${longRunInfo} final=[${bbox.left},${bbox.top},${bbox.right},${bbox.bottom}] isFullImage=${isFullImage ? 1 : 0} areaRatio=${boardAreaRatio2.toFixed(3)} cell=${cellW.toFixed(1)}x${cellH.toFixed(1)}`);

  hilog.info(DOMAIN, TAG, '【图片与棋盘】%{public}dx%{public}d bg=%{public}.1f isDark=%{public}d 棋盘=[%{public}d,%{public}d,%{public}d,%{public}d] 每格=%{public}.1f',
    width, height, bg, isDark ? 1 : 0, bbox.left, bbox.top, bbox.right, bbox.bottom,
    Math.min(cellW, cellH));
  hilog.info(DOMAIN, TAG, '【像素背景分析】%{public}s', g_lastDebugPixelBgInfo);
  hilog.info(DOMAIN, TAG, '【像素棋盘定位】%{public}s', g_lastDebugPixelBboxLocator);

  if (isFullImage) {
    hilog.warn(DOMAIN, TAG, '像素分析: 警告 - findBoardBBox返回全图退化bbox，棋盘定位可能失败');
  }

  const corners: BoardCorners | null = detectBoardCorners(gray, width, height, isDark, bg);
  if (corners !== null) {
    const boardSize: number = Math.max(bbox.right - bbox.left, bbox.bottom - bbox.top);
    const outSize: number = Math.round(boardSize * WARP_SIZE_MULTIPLIER);
    const warpedGray: Float32Array = warpPerspectiveGray(gray, width, height, corners, outSize, bg);
    const warpCellW: number = outSize / 9;
    const warpCellH: number = outSize / 9;
    let warpBgSum: number = 0;
    const warpSampleStep: number = Math.max(1, Math.floor(outSize * outSize / WARP_BG_SAMPLE_DIV));
    let warpBgCnt: number = 0;
    for (let i: number = 0; i < outSize * outSize; i += warpSampleStep) {
      warpBgSum += warpedGray[i];
      warpBgCnt++;
    }
    const warpBg: number = warpBgCnt > 0 ? warpBgSum / warpBgCnt : BG_DARK_THRESHOLD;
    const warpIsDark: boolean = warpBg < BG_DARK_THRESHOLD;
    resetGridLineCrop();
    detectGridLineWidths(warpedGray, outSize, 0, 0, outSize, outSize, warpIsDark, warpBg);
    setLastDebugPixelWarpInfo(`透视校正 outSize=${outSize} confidence=${corners.confidence.toFixed(2)} warpBg=${warpBg.toFixed(1)} warpIsDark=${warpIsDark ? 1 : 0} corners=[${corners.topLeftX.toFixed(0)},${corners.topLeftY.toFixed(0)}]-[${corners.topRightX.toFixed(0)},${corners.topRightY.toFixed(0)}]-[${corners.bottomRightX.toFixed(0)},${corners.bottomRightY.toFixed(0)}]-[${corners.bottomLeftX.toFixed(0)},${corners.bottomLeftY.toFixed(0)}]`);
    hilog.info(DOMAIN, TAG, '【像素透视/网格】outSize=%{public}d confidence=%{public}.2f', outSize, corners.confidence);

    let sigCount: number = 0;
    let digitCount: number = 0;
    for (let r: number = 0; r < 9; r++) {
      for (let c: number = 0; c < 9; c++) {
        let sig: number[] | null = cellSigFromGray(
          warpedGray, outSize,
          c * warpCellW, r * warpCellH,
          warpCellW, warpCellH, warpIsDark, warpBg, r, c
        );
        let digit: number = 0;
        if (sig !== null) {
          digit = recognizeDigit(sig, countInk(sig));
        }
        if (digit === 0) {
          const lowSig: number[] | null = cellSigFromGrayLowThresh(
            warpedGray, outSize,
            c * warpCellW, r * warpCellH,
            warpCellW, warpCellH, warpIsDark, warpBg, r, c
          );
          if (lowSig !== null) {
            sig = lowSig;
            digit = recognizeDigit(lowSig, countInk(lowSig));
          }
        }
        if (digit === 0 && getLastRawInkRatio() < MIN_CELL_INK_RATIO * 0.5) {
          const thinSig: number[] | null = cellSigFromGrayThin(
            warpedGray, outSize,
            c * warpCellW, r * warpCellH,
            warpCellW, warpCellH, warpIsDark, warpBg, r, c
          );
          if (thinSig !== null) {
            sig = thinSig;
            digit = recognizeDigit(thinSig, countInk(thinSig));
          }
        }
        if (sig !== null) {
          sigCount++;
          grid[r * 9 + c] = digit;
          g_lastPixelConfidence[r * 9 + c] = getLastConfidence();
          if (digit > 0) { digitCount++; }
        }
      }
    }
    g_lastDebugPixelCellStats = `warp路径: sigOK=${sigCount}/81 digits=${digitCount}/81`;
  } else {
    hilog.info(DOMAIN, TAG, '【像素透视/网格】角点检测失败 使用AABB');
    setLastDebugPixelWarpInfo('角点检测失败，使用AABB');

    const gridLines: GridLines | null = findPreciseGridLines(gray, width, height, bbox, bg);
    if (gridLines !== null) {
      hilog.info(DOMAIN, TAG, '【像素透视/网格】精确网格线OK');
      g_lastDebugPixelWarpInfo += ' → 精确网格线OK';
      resetGridLineCrop();
      detectGridLineWidths(gray, width, bbox.left, bbox.top, bbox.right, bbox.bottom, isDark, bg);
      let sigCount2: number = 0;
      let digitCount2: number = 0;
      for (let r: number = 0; r < 9; r++) {
        for (let c: number = 0; c < 9; c++) {
          const cLeft: number = gridLines.vLines[c];
          const cTop: number = gridLines.hLines[r];
          const cW: number = gridLines.vLines[c + 1] - cLeft;
          const cH: number = gridLines.hLines[r + 1] - cTop;
          let sig: number[] | null = cellSigFromGray(
            gray, width, cLeft, cTop, cW, cH, bbox.isDark, bg, r, c
          );
          let digit: number = 0;
          if (sig !== null) {
            digit = recognizeDigit(sig, countInk(sig));
          }
          if (digit === 0) {
            const lowSig: number[] | null = cellSigFromGrayLowThresh(
              gray, width, cLeft, cTop, cW, cH, bbox.isDark, bg, r, c
            );
            if (lowSig !== null) {
              sig = lowSig;
              digit = recognizeDigit(lowSig, countInk(lowSig));
            }
          }
          if (digit === 0 && getLastRawInkRatio() < MIN_CELL_INK_RATIO * 0.5) {
            const thinSig: number[] | null = cellSigFromGrayThin(
              gray, width, cLeft, cTop, cW, cH, bbox.isDark, bg, r, c
            );
            if (thinSig !== null) {
              sig = thinSig;
              digit = recognizeDigit(thinSig, countInk(thinSig));
            }
          }
          if (sig !== null) {
            sigCount2++;
            g_lastPixelConfidence[r * 9 + c] = getLastConfidence();
            if (digit > 0 && !validateCellCentering(gray, width, height, cLeft, cTop, cW, cH, bbox.isDark, bg)) {
              const fallbackW: number = (bbox.right - bbox.left) / 9;
              const fallbackH: number = (bbox.bottom - bbox.top) / 9;
              const fallbackLeft: number = bbox.left + c * fallbackW;
              const fallbackTop: number = bbox.top + r * fallbackH;
              const fallbackSig: number[] | null = cellSigFromGray(
                gray, width, fallbackLeft, fallbackTop, fallbackW, fallbackH, bbox.isDark, bg, r, c
              );
              if (fallbackSig !== null) {
                const fbDigit: number = recognizeDigit(fallbackSig, countInk(fallbackSig));
                g_lastPixelConfidence[r * 9 + c] = getLastConfidence();
                if (fbDigit > 0) {
                  grid[r * 9 + c] = fbDigit;
                  digitCount2++;
                  continue;
                }
              }
            }
            grid[r * 9 + c] = digit;
            if (digit > 0) { digitCount2++; }
          }
        }
      }
      g_lastDebugPixelCellStats = `gridLines路径: sigOK=${sigCount2}/81 digits=${digitCount2}/81 vLines=${gridLines.vLines.length} hLines=${gridLines.hLines.length}`;
    } else {
      g_lastDebugPixelWarpInfo += ' → AABB均匀分格';
      resetGridLineCrop();
      detectGridLineWidths(gray, width, bbox.left, bbox.top, bbox.right, bbox.bottom, isDark, bg);
      let sigCount3: number = 0;
      let digitCount3: number = 0;
      for (let r: number = 0; r < 9; r++) {
        for (let c: number = 0; c < 9; c++) {
          let sig: number[] | null = cellSigFromGray(
            gray, width,
            bbox.left + c * cellW, bbox.top + r * cellH,
            cellW, cellH, bbox.isDark, bg, r, c
          );
          let digit: number = 0;
          if (sig !== null) {
            digit = recognizeDigit(sig, countInk(sig));
          }
          if (digit === 0) {
            const lowSig: number[] | null = cellSigFromGrayLowThresh(
              gray, width,
              bbox.left + c * cellW, bbox.top + r * cellH,
              cellW, cellH, bbox.isDark, bg, r, c
            );
            if (lowSig !== null) {
              sig = lowSig;
              digit = recognizeDigit(lowSig, countInk(lowSig));
            }
          }
          if (digit === 0 && getLastRawInkRatio() < MIN_CELL_INK_RATIO * 0.5) {
            const thinSig: number[] | null = cellSigFromGrayThin(
              gray, width,
              bbox.left + c * cellW, bbox.top + r * cellH,
              cellW, cellH, bbox.isDark, bg, r, c
            );
            if (thinSig !== null) {
              sig = thinSig;
              digit = recognizeDigit(thinSig, countInk(thinSig));
            }
          }
          if (sig !== null) {
            sigCount3++;
            grid[r * 9 + c] = digit;
            g_lastPixelConfidence[r * 9 + c] = getLastConfidence();
            if (digit > 0) { digitCount3++; }
          }
        }
      }
      g_lastDebugPixelCellStats = `AABB路径: sigOK=${sigCount3}/81 digits=${digitCount3}/81`;
    }
  }

  let gridStr: string = '[SudokuOCR] 像素分析结果:\n';
  for (let r: number = 0; r < 9; r++) {
    let line: string = '  ';
    for (let c: number = 0; c < 9; c++) {
      line += (grid[r * 9 + c] === 0 ? '.' : grid[r * 9 + c].toString()) + ' ';
    }
    gridStr += line + '\n';
  }
  hilog.info(DOMAIN, TAG, '【像素分析网格】\n%{public}s', gridStr);

  return grid;
}

export async function analyzePixelGridFromBufferAsync(pixels: Uint8Array, width: number, height: number): Promise<number[]> {
  const grid: number[] = new Array<number>(81).fill(0);
  setLastPixelConfidence(new Array<number>(81).fill(0));
  setLastCellCoords([]);

  const bg: number = bgColor(pixels, width, height);
  const gray: Float32Array = toGrayArray(pixels, width, height);
  const isDark: boolean = bg < BG_DARK_THRESHOLD;
  await yieldThread();

  const bgHist: number[] = new Array<number>(256).fill(0);
  const bgSampleStep2: number = Math.max(1, Math.floor(width * height / 20000));
  let bgMin2: number = 255;
  let bgMax2: number = 0;
  for (let i: number = 0; i < width * height; i += bgSampleStep2) {
    const g: number = Math.floor(gray[i]);
    if (g >= 0 && g <= 255) { bgHist[g]++; }
    if (g < bgMin2) { bgMin2 = g; }
    if (g > bgMax2) { bgMax2 = g; }
  }
  let bgHistTop3Str: string = '';
  const bgHistCopy: number[] = new Array<number>(256);
  for (let i: number = 0; i < 256; i++) {
    bgHistCopy[i] = bgHist[i];
  }
  for (let pass: number = 0; pass < 3; pass++) {
    let topI: number = 0;
    let topV: number = 0;
    for (let i: number = 0; i < 256; i++) {
      if (bgHistCopy[i] > topV) {
        topV = bgHistCopy[i];
        topI = i;
      }
    }
    if (topV > 0) {
      bgHistTop3Str += (bgHistTop3Str.length > 0 ? ', ' : '') + `${topI}(${topV})`;
      bgHistCopy[topI] = 0;
    }
  }
  setLastDebugPixelBgInfo(`size=${width}x${height} bg=${bg.toFixed(1)} isDark=${isDark ? 1 : 0} bgRange=[${bgMin2},${bgMax2}] bgHistTop3=[${bgHistTop3Str}] threshold=${BG_DARK_THRESHOLD}`);

  const bbox: BoardBBox = findBoardBBox(pixels, width, height, bg);
  const cellW: number = (bbox.right - bbox.left) / 9;
  const cellH: number = (bbox.bottom - bbox.top) / 9;
  const isFullImage: boolean = bbox.left === 0 && bbox.top === 0 &&
    bbox.right === width && bbox.bottom === height;
  const boardAreaRatio2: number = (bbox.right - bbox.left) * (bbox.bottom - bbox.top) / (width * height);
  await yieldThread();

  const longRunResult: BoardBBox | null = findBoxLongRun(gray, width, height, isDark, bg);
  const longRunInfo: string = longRunResult !== null
    ? `OK [${longRunResult.left},${longRunResult.top},${longRunResult.right},${longRunResult.bottom}]`
    : '失败';
  setLastDebugPixelBboxLocator(`longRun=${longRunInfo} final=[${bbox.left},${bbox.top},${bbox.right},${bbox.bottom}] isFullImage=${isFullImage ? 1 : 0} areaRatio=${boardAreaRatio2.toFixed(3)} cell=${cellW.toFixed(1)}x${cellH.toFixed(1)}`);

  hilog.info(DOMAIN, TAG, '【图片与棋盘】%{public}dx%{public}d bg=%{public}.1f isDark=%{public}d 棋盘=[%{public}d,%{public}d,%{public}d,%{public}d] 每格=%{public}.1f',
    width, height, bg, isDark ? 1 : 0, bbox.left, bbox.top, bbox.right, bbox.bottom,
    Math.min(cellW, cellH));
  hilog.info(DOMAIN, TAG, '【像素背景分析】%{public}s', g_lastDebugPixelBgInfo);
  hilog.info(DOMAIN, TAG, '【像素棋盘定位】%{public}s', g_lastDebugPixelBboxLocator);

  if (isFullImage) {
    hilog.warn(DOMAIN, TAG, '像素分析: 警告 - findBoardBBox返回全图退化bbox，棋盘定位可能失败');
  }
  await yieldThread();

  const corners: BoardCorners | null = detectBoardCorners(gray, width, height, isDark, bg);
  if (corners !== null) {
    const boardSize: number = Math.max(bbox.right - bbox.left, bbox.bottom - bbox.top);
    const outSize: number = Math.round(boardSize * WARP_SIZE_MULTIPLIER);
    const warpedGray: Float32Array = warpPerspectiveGray(gray, width, height, corners, outSize, bg);
    const warpCellW: number = outSize / 9;
    const warpCellH: number = outSize / 9;
    const warpInkBg: number = isDark ? bg + INK_THRESH : bg - INK_THRESH;
    let warpBgSum: number = 0;
    let warpBgCnt: number = 0;
    const warpSampleStep: number = Math.max(1, Math.floor(outSize * outSize / WARP_BG_SAMPLE_DIV));
    for (let sy: number = 0; sy < outSize; sy += warpSampleStep) {
      for (let sx: number = 0; sx < outSize; sx += warpSampleStep) {
        const g: number = warpedGray[sy * outSize + sx];
        if (isDark ? g < warpInkBg : g > warpInkBg) {
          warpBgSum += g;
          warpBgCnt++;
        }
      }
    }
    const warpBg: number = warpBgCnt > 0 ? warpBgSum / warpBgCnt : bg;
    const warpIsDark: boolean = warpBg < BG_DARK_THRESHOLD;
    resetGridLineCrop();
    const warpBBox: BoardBBox = { left: 0, top: 0, right: outSize, bottom: outSize, isDark: warpIsDark };
    const warpGridLines: GridLines | null = findPreciseGridLines(warpedGray, outSize, outSize, warpBBox, warpBg);
    if (warpGridLines !== null) {
      detectGridLineWidths(warpedGray, outSize, 0, 0, outSize, outSize, warpIsDark, warpBg);
    }
    g_lastDebugPixelWarpInfo = `透视校正 outSize=${outSize} confidence=${corners.confidence.toFixed(2)} warpBg=${warpBg.toFixed(1)} warpIsDark=${warpIsDark ? 1 : 0} warpGridLines=${warpGridLines !== null ? 'OK' : 'null'} corners=[${corners.topLeftX.toFixed(0)},${corners.topLeftY.toFixed(0)}]-[${corners.topRightX.toFixed(0)},${corners.topRightY.toFixed(0)}]-[${corners.bottomRightX.toFixed(0)},${corners.bottomRightY.toFixed(0)}]-[${corners.bottomLeftX.toFixed(0)},${corners.bottomLeftY.toFixed(0)}]`;
    hilog.info(DOMAIN, TAG, '【像素透视/网格】outSize=%{public}d confidence=%{public}.2f warpBg=%{public}.1f gridLines=%{public}s', outSize, corners.confidence, warpBg, warpGridLines !== null ? 'OK' : 'null');
    await yieldThread();

    let sigCount: number = 0;
    let digitCount: number = 0;
    for (let r: number = 0; r < 9; r++) {
      for (let c: number = 0; c < 9; c++) {
        let cellL: number = 0;
        let cellT: number = 0;
        let cellW: number = warpCellW;
        let cellH: number = warpCellH;
        if (warpGridLines !== null) {
          cellL = warpGridLines.vLines[c];
          cellT = warpGridLines.hLines[r];
          cellW = warpGridLines.vLines[c + 1] - cellL;
          cellH = warpGridLines.hLines[r + 1] - cellT;
        } else {
          cellL = c * warpCellW;
          cellT = r * warpCellH;
        }
        let sig: number[] | null = cellSigFromGray(
          warpedGray, outSize,
          cellL, cellT,
          cellW, cellH, warpIsDark, warpBg, r, c
        );
        let digit: number = 0;
        if (sig !== null) {
          digit = recognizeDigit(sig, countInk(sig));
        }
        await yieldThread();
        if (digit === 0) {
          const lowSig: number[] | null = cellSigFromGrayLowThresh(
            warpedGray, outSize,
            cellL, cellT,
            cellW, cellH, warpIsDark, warpBg, r, c
          );
          if (lowSig !== null) {
            sig = lowSig;
            digit = recognizeDigit(lowSig, countInk(lowSig));
          }
          await yieldThread();
        }
        if (digit === 0 && getLastRawInkRatio() < MIN_CELL_INK_RATIO * 0.5) {
          const thinSig: number[] | null = cellSigFromGrayThin(
            warpedGray, outSize,
            cellL, cellT,
            cellW, cellH, warpIsDark, warpBg, r, c
          );
          if (thinSig !== null) {
            sig = thinSig;
            digit = recognizeDigit(thinSig, countInk(thinSig));
          }
          await yieldThread();
        }
        if (sig !== null) {
          sigCount++;
          grid[r * 9 + c] = digit;
          g_lastPixelConfidence[r * 9 + c] = getLastConfidence();
          if (digit > 0) { digitCount++; }
          const coordInfo: CellCoordInfo = {
            row: r, col: c, digit: digit,
            left: Math.round(cellL), top: Math.round(cellT),
            w: Math.round(cellW), h: Math.round(cellH),
            conf: getLastConfidence(), rawInk: getLastRawInkRatio(),
            imgW: outSize, imgH: outSize,
            source: warpGridLines !== null ? 'warp+grid' : 'warp'
          };
          g_lastCellCoords.push(coordInfo);
        }
        await yieldThread();
      }
    }
    g_lastDebugPixelCellStats = `warp路径: sigOK=${sigCount}/81 digits=${digitCount}/81`;
  } else {
    hilog.info(DOMAIN, TAG, '【像素透视/网格】角点检测失败 使用AABB');
    setLastDebugPixelWarpInfo('角点检测失败，使用AABB');
    await yieldThread();

    const gridLines: GridLines | null = findPreciseGridLines(gray, width, height, bbox, bg);
    if (gridLines !== null) {
      hilog.info(DOMAIN, TAG, '【像素透视/网格】精确网格线OK');
      g_lastDebugPixelWarpInfo += ' → 精确网格线OK';
      resetGridLineCrop();
      detectGridLineWidths(gray, width, bbox.left, bbox.top, bbox.right, bbox.bottom, isDark, bg);
      await yieldThread();
      let sigCount2: number = 0;
      let digitCount2: number = 0;
      for (let r: number = 0; r < 9; r++) {
        for (let c: number = 0; c < 9; c++) {
          const cLeft: number = gridLines.vLines[c];
          const cTop: number = gridLines.hLines[r];
          const cW: number = gridLines.vLines[c + 1] - cLeft;
          const cH: number = gridLines.hLines[r + 1] - cTop;
          let sig: number[] | null = cellSigFromGray(
            gray, width, cLeft, cTop, cW, cH, bbox.isDark, bg, r, c
          );
          let digit: number = 0;
          if (sig !== null) {
            digit = recognizeDigit(sig, countInk(sig));
          }
          await yieldThread();
          if (digit === 0) {
            const lowSig: number[] | null = cellSigFromGrayLowThresh(
              gray, width, cLeft, cTop, cW, cH, bbox.isDark, bg, r, c
            );
            if (lowSig !== null) {
              sig = lowSig;
              digit = recognizeDigit(lowSig, countInk(lowSig));
            }
            await yieldThread();
          }
          if (digit === 0 && getLastRawInkRatio() < MIN_CELL_INK_RATIO * 0.5) {
            const thinSig: number[] | null = cellSigFromGrayThin(
              gray, width, cLeft, cTop, cW, cH, bbox.isDark, bg, r, c
            );
            if (thinSig !== null) {
              sig = thinSig;
              digit = recognizeDigit(thinSig, countInk(thinSig));
            }
            await yieldThread();
          }
          if (sig !== null) {
            sigCount2++;
            g_lastPixelConfidence[r * 9 + c] = getLastConfidence();
            if (digit > 0 && !validateCellCentering(gray, width, height, cLeft, cTop, cW, cH, bbox.isDark, bg)) {
              const fallbackW: number = (bbox.right - bbox.left) / 9;
              const fallbackH: number = (bbox.bottom - bbox.top) / 9;
              const fallbackLeft: number = bbox.left + c * fallbackW;
              const fallbackTop: number = bbox.top + r * fallbackH;
              const fallbackSig: number[] | null = cellSigFromGray(
                gray, width, fallbackLeft, fallbackTop, fallbackW, fallbackH, bbox.isDark, bg, r, c
              );
              if (fallbackSig !== null) {
                const fbDigit: number = recognizeDigit(fallbackSig, countInk(fallbackSig));
                g_lastPixelConfidence[r * 9 + c] = getLastConfidence();
                if (fbDigit > 0) {
                  grid[r * 9 + c] = fbDigit;
                  digitCount2++;
                  const coordInfo2: CellCoordInfo = {
                    row: r, col: c, digit: fbDigit,
                    left: Math.round(fallbackLeft), top: Math.round(fallbackTop),
                    w: Math.round(fallbackW), h: Math.round(fallbackH),
                    conf: getLastConfidence(), rawInk: getLastRawInkRatio(),
                    imgW: width, imgH: height,
                    source: 'gridLines_fallback'
                  };
                  g_lastCellCoords.push(coordInfo2);
                  continue;
                }
              }
            }
            grid[r * 9 + c] = digit;
            if (digit > 0) { digitCount2++; }
            const coordInfo3: CellCoordInfo = {
              row: r, col: c, digit: digit,
              left: Math.round(cLeft), top: Math.round(cTop),
              w: Math.round(cW), h: Math.round(cH),
              conf: getLastConfidence(), rawInk: getLastRawInkRatio(),
              imgW: width, imgH: height,
              source: 'gridLines'
            };
            g_lastCellCoords.push(coordInfo3);
          }
          await yieldThread();
        }
      }
      g_lastDebugPixelCellStats = `gridLines路径: sigOK=${sigCount2}/81 digits=${digitCount2}/81 vLines=${gridLines.vLines.length} hLines=${gridLines.hLines.length}`;
    } else {
      g_lastDebugPixelWarpInfo += ' → AABB均匀分格';
      resetGridLineCrop();
      detectGridLineWidths(gray, width, bbox.left, bbox.top, bbox.right, bbox.bottom, isDark, bg);
      await yieldThread();
      let sigCount3: number = 0;
      let digitCount3: number = 0;
      for (let r: number = 0; r < 9; r++) {
        for (let c: number = 0; c < 9; c++) {
          let sig: number[] | null = cellSigFromGray(
            gray, width,
            bbox.left + c * cellW, bbox.top + r * cellH,
            cellW, cellH, bbox.isDark, bg, r, c
          );
          let digit: number = 0;
          if (sig !== null) {
            digit = recognizeDigit(sig, countInk(sig));
          }
          await yieldThread();
          if (digit === 0) {
            const lowSig: number[] | null = cellSigFromGrayLowThresh(
              gray, width,
              bbox.left + c * cellW, bbox.top + r * cellH,
              cellW, cellH, bbox.isDark, bg, r, c
            );
            if (lowSig !== null) {
              sig = lowSig;
              digit = recognizeDigit(lowSig, countInk(lowSig));
            }
            await yieldThread();
          }
          if (digit === 0 && getLastRawInkRatio() < MIN_CELL_INK_RATIO * 0.5) {
            const thinSig: number[] | null = cellSigFromGrayThin(
              gray, width,
              bbox.left + c * cellW, bbox.top + r * cellH,
              cellW, cellH, bbox.isDark, bg, r, c
            );
            if (thinSig !== null) {
              sig = thinSig;
              digit = recognizeDigit(thinSig, countInk(thinSig));
            }
            await yieldThread();
          }
          if (sig !== null) {
            sigCount3++;
            grid[r * 9 + c] = digit;
            g_lastPixelConfidence[r * 9 + c] = getLastConfidence();
            if (digit > 0) { digitCount3++; }
            const aabbLeft: number = bbox.left + c * cellW;
            const aabbTop: number = bbox.top + r * cellH;
            const coordInfo4: CellCoordInfo = {
              row: r, col: c, digit: digit,
              left: Math.round(aabbLeft), top: Math.round(aabbTop),
              w: Math.round(cellW), h: Math.round(cellH),
              conf: getLastConfidence(), rawInk: getLastRawInkRatio(),
              imgW: width, imgH: height,
              source: 'AABB'
            };
            g_lastCellCoords.push(coordInfo4);
          }
          await yieldThread();
        }
      }
      g_lastDebugPixelCellStats = `AABB路径: sigOK=${sigCount3}/81 digits=${digitCount3}/81`;
    }
  }

  let coordLines: string[] = [];
  for (let idx: number = 0; idx < g_lastCellCoords.length; idx++) {
    const ci: CellCoordInfo = g_lastCellCoords[idx];
    coordLines.push(`R${ci.row}C${ci.col}:d=${ci.digit} rect=[${ci.left},${ci.top},${ci.w}x${ci.h}] conf=${ci.conf.toFixed(2)} ink=${ci.rawInk.toFixed(4)} imgSize=${ci.imgW}x${ci.imgH} src=${ci.source}`);
  }
  g_lastDebugPixelCellCoords = coordLines.join('\n');

  let gridStr: string = '[SudokuOCR] 像素分析结果:\n';
  for (let r: number = 0; r < 9; r++) {
    let line: string = '  ';
    for (let c: number = 0; c < 9; c++) {
      line += (grid[r * 9 + c] === 0 ? '.' : grid[r * 9 + c].toString()) + ' ';
    }
    gridStr += line + '\n';
  }
  hilog.info(DOMAIN, TAG, '【像素分析网格】\n%{public}s', gridStr);

  return grid;
}
