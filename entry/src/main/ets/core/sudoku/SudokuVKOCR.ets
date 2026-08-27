import { image } from '@kit.ImageKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  OCRResult, VisionKitGridResult, RawDigit, AdaptiveResizeParams,
  CellCoordInfo, PerCellVkDiag,
  g_vkInited, g_vkFailed, g_cachedPixels, g_cachedImgW, g_cachedImgH,
  g_probeBbox, g_probeResizeW, g_probeResizeH,
  g_lastDebugVkRawText, g_lastDebugVkBlockCount, g_lastDebugVkOcrSize,
  g_lastDebugVkOcrError, g_lastDebugProbeInfo, g_lastDebugBbox,
  g_lastDebugResize, g_lastDebugVkBlockDetail, g_lastDebugRawDigits,
  g_fittedBoardL, g_fittedBoardT, g_fittedBoardR, g_fittedBoardB,
  g_lastDebugRawDigitPositions, g_perCellVkDiag,
  setVkInited, setVkFailed, setCachedPixels, setCachedImgW, setCachedImgH,
  setProbeBbox, setProbeResizeW, setProbeResizeH,
  setLastDebugVkRawText, setLastDebugVkBlockCount, setLastDebugVkOcrSize,
  setLastDebugVkOcrError, setLastDebugProbeInfo, setLastDebugBbox,
  setLastDebugResize, setLastDebugVkBlockDetail, setLastDebugRawDigits,
  setFittedBoardL, setFittedBoardT, setFittedBoardR, setFittedBoardB,
  setLastDebugRawDigitPositions
} from './SudokuOCRTypes';
import {
  DOMAIN, TAG, withTimeout, computeAdaptiveResize,
  openImageSource, openImageSourceFromBuffer,
  BOARD_CROP_PAD_RATIO, TARGET_CELL_PX, OCR_MAX_DIM, OCR_MIN_DIM,
  POSITIONAL_CONFIDENCE, TEXT_FALLBACK_CONFIDENCE, BG_DARK_THRESHOLD
} from './SudokuOCRUtils';
import { parseOCRToGrid } from './SudokuEngine';
import { BoardBBox, bgColor, findBoardBBox } from './SudokuPixel';

interface CellCandidate {
  digit: number;
  dist: number;
}

interface BoardBoundsOCR {
  boardL: number;
  boardT: number;
  boardR: number;
  boardB: number;
}

function extractStructuredText(result: textRecognition.TextRecognitionResult): string {
  const parts: string[] = [];
  const blocks: Array<textRecognition.TextBlock> = result.blocks || [];
  for (let bi: number = 0; bi < blocks.length; bi++) {
    const lines: Array<textRecognition.TextLine> = blocks[bi].lines || [];
    for (let li: number = 0; li < lines.length; li++) {
      parts.push(lines[li].value);
    }
  }
  return parts.join('\n');
}

function estimateBoardBoundsFromDigits(
  rawDigits: RawDigit[], imgW: number, imgH: number
): BoardBoundsOCR | null {
  if (rawDigits.length === 0) { return null; }

  let minX: number = imgW;
  let maxX: number = 0;
  let minY: number = imgH;
  let maxY: number = 0;
  for (let i: number = 0; i < rawDigits.length; i++) {
    const d: RawDigit = rawDigits[i];
    if (d.cx < minX) { minX = d.cx; }
    if (d.cx > maxX) { maxX = d.cx; }
    if (d.cy < minY) { minY = d.cy; }
    if (d.cy > maxY) { maxY = d.cy; }
  }

  const colBuckets: number[] = new Array<number>(9).fill(0);
  const rowBuckets: number[] = new Array<number>(9).fill(0);
  const digitSpanX: number = maxX - minX;
  const digitSpanY: number = maxY - minY;
  if (digitSpanX <= 0 || digitSpanY <= 0) { return null; }

  for (let i: number = 0; i < rawDigits.length; i++) {
    const d: RawDigit = rawDigits[i];
    const colIdx: number = Math.min(Math.max(Math.floor((d.cx - minX) / digitSpanX * 8.999), 0), 8);
    const rowIdx: number = Math.min(Math.max(Math.floor((d.cy - minY) / digitSpanY * 8.999), 0), 8);
    colBuckets[colIdx]++;
    rowBuckets[rowIdx]++;
  }

  let firstCol: number = 0;
  let lastCol: number = 8;
  for (let c: number = 0; c < 9; c++) {
    if (colBuckets[c] > 0) { firstCol = c; break; }
  }
  for (let c: number = 8; c >= 0; c--) {
    if (colBuckets[c] > 0) { lastCol = c; break; }
  }
  let firstRow: number = 0;
  let lastRow: number = 8;
  for (let r: number = 0; r < 9; r++) {
    if (rowBuckets[r] > 0) { firstRow = r; break; }
  }
  for (let r: number = 8; r >= 0; r--) {
    if (rowBuckets[r] > 0) { lastRow = r; break; }
  }

  const cellWEst: number = digitSpanX / Math.max(lastCol - firstCol, 1);
  const cellHEst: number = digitSpanY / Math.max(lastRow - firstRow, 1);
  const boardL: number = Math.max(minX - firstCol * cellWEst - cellWEst * 0.5, 0);
  const boardR: number = Math.min(maxX + (8 - lastCol) * cellWEst + cellWEst * 0.5, imgW);
  const boardT: number = Math.max(minY - firstRow * cellHEst - cellHEst * 0.5, 0);
  const boardB: number = Math.min(maxY + (8 - lastRow) * cellHEst + cellHEst * 0.5, imgH);

  const out: BoardBoundsOCR = { boardL: boardL, boardT: boardT, boardR: boardR, boardB: boardB };
  return out;
}

function buildGridByPosition(
  result: textRecognition.TextRecognitionResult,
  imgW: number, imgH: number,
  pixelBbox: BoardBBox | null,
  cropOffsetX: number, cropOffsetY: number,
  cropToOcrScaleX: number, cropToOcrScaleY: number
): VisionKitGridResult | null {
  const blocks: Array<textRecognition.TextBlock> = result.blocks || [];
  if (blocks.length === 0) { return null; }

  const rawDigits: RawDigit[] = [];

  for (let bi: number = 0; bi < blocks.length; bi++) {
    const lines: Array<textRecognition.TextLine> = blocks[bi].lines || [];
    for (let li: number = 0; li < lines.length; li++) {
      const line: textRecognition.TextLine = lines[li];
      const words: Array<textRecognition.TextWord> = line.words || [];
      for (let wi: number = 0; wi < words.length; wi++) {
        const word: textRecognition.TextWord = words[wi];
        const text: string = word.value.trim();
        if (text.length === 0) { continue; }
        const cp: Array<textRecognition.PixelPoint> = word.cornerPoints;
        if (cp.length < 4) { continue; }

        const topLeftX: number = cp[0].x;
        const topLeftY: number = cp[0].y;
        const topRightX: number = cp[1].x;
        const bottomRightX: number = cp[2].x;
        const bottomRightY: number = cp[2].y;
        const cy: number = (topLeftY + bottomRightY) / 2;

        const charSpanX: number = (topRightX - topLeftX + bottomRightX - cp[3].x) / 2;
        const charWidth: number = charSpanX / text.length;

        for (let ci: number = 0; ci < text.length; ci++) {
          const ch: string = text[ci];
          if (!new RegExp('^[0-9]$').test(ch)) { continue; }
          const charCx: number = topLeftX + charWidth * (ci + 0.5);
          const rd: RawDigit = { cx: charCx, cy: cy, digit: parseInt(ch, 10) };
          rawDigits.push(rd);
        }
      }
    }
  }

  if (rawDigits.length === 0) { return null; }

  let posStr: string = '';
  for (let di2: number = 0; di2 < rawDigits.length; di2++) {
    if (posStr.length > 0) { posStr += ' '; }
    posStr += `${rawDigits[di2].digit}@(${rawDigits[di2].cx.toFixed(0)},${rawDigits[di2].cy.toFixed(0)})`;
  }
  setLastDebugRawDigitPositions(posStr);

  let boardL: number = 0;
  let boardT: number = 0;
  let boardR: number = imgW;
  let boardB: number = imgH;

  if (pixelBbox !== null) {
    boardL = (pixelBbox.left - cropOffsetX) * cropToOcrScaleX;
    boardT = (pixelBbox.top - cropOffsetY) * cropToOcrScaleY;
    boardR = (pixelBbox.right - cropOffsetX) * cropToOcrScaleX;
    boardB = (pixelBbox.bottom - cropOffsetY) * cropToOcrScaleY;
    boardL = Math.max(boardL, 0);
    boardT = Math.max(boardT, 0);
    boardR = Math.min(boardR, imgW);
    boardB = Math.min(boardB, imgH);
    hilog.info(DOMAIN, TAG, '【VisionKit Block详情】buildGrid pixelBoard ocr=[%{public}.1f,%{public}.1f,%{public}.1f,%{public}.1f]',
      boardL, boardT, boardR, boardB);
    if (rawDigits.length >= 8) {
      const sortedY: number[] = [];
      for (let di: number = 0; di < rawDigits.length; di++) {
        sortedY.push(rawDigits[di].cy);
      }
      sortedY.sort((a: number, b: number) => a - b);
      const rowCenters: number[] = [];
      let rowStart: number = 0;
      for (let si: number = 1; si <= sortedY.length; si++) {
        const isGap: boolean = si < sortedY.length && (sortedY[si] - sortedY[si - 1]) > (sortedY[sortedY.length - 1] - sortedY[0]) / 12;
        if (isGap || si === sortedY.length) {
          let sum: number = 0;
          let cnt: number = 0;
          for (let j: number = rowStart; j < si; j++) { sum += sortedY[j]; cnt++; }
          rowCenters.push(sum / cnt);
          rowStart = si;
        }
      }
      if (rowCenters.length >= 2) {
        const yGaps: number[] = [];
        for (let ri: number = 1; ri < rowCenters.length; ri++) {
          yGaps.push(rowCenters[ri] - rowCenters[ri - 1]);
        }
        yGaps.sort((a: number, b: number) => a - b);
        const medianCellH: number = yGaps[Math.floor(yGaps.length / 2)];
        const firstGridRow: number = Math.round((rowCenters[0] - boardT) / medianCellH - 0.5);
        const clampedFirstRow: number = Math.max(0, Math.min(firstGridRow, 8 - rowCenters.length + 1));
        const refinedBoardT: number = rowCenters[0] - (clampedFirstRow + 0.5) * medianCellH;
        const refinedBoardB: number = refinedBoardT + 9 * medianCellH;
        if (refinedBoardT >= 0 && refinedBoardB <= imgH) {
          hilog.info(DOMAIN, TAG, '【VisionKit Block详情】buildGrid rowFit medianCellH=%{public}.1f firstGridRow=%{public}d refinedT=%.1f refinedB=%.1f',
            medianCellH, clampedFirstRow, refinedBoardT, refinedBoardB);
          boardT = refinedBoardT;
          boardB = refinedBoardB;
        }
      }
      const sortedX: number[] = [];
      for (let di: number = 0; di < rawDigits.length; di++) {
        sortedX.push(rawDigits[di].cx);
      }
      sortedX.sort((a: number, b: number) => a - b);
      const colCenters: number[] = [];
      let colStart: number = 0;
      for (let si: number = 1; si <= sortedX.length; si++) {
        const isGap: boolean = si < sortedX.length && (sortedX[si] - sortedX[si - 1]) > (sortedX[sortedX.length - 1] - sortedX[0]) / 12;
        if (isGap || si === sortedX.length) {
          let sum: number = 0;
          let cnt: number = 0;
          for (let j: number = colStart; j < si; j++) { sum += sortedX[j]; cnt++; }
          colCenters.push(sum / cnt);
          colStart = si;
        }
      }
      if (colCenters.length >= 2) {
        const xGaps: number[] = [];
        for (let ci: number = 1; ci < colCenters.length; ci++) {
          xGaps.push(colCenters[ci] - colCenters[ci - 1]);
        }
        xGaps.sort((a: number, b: number) => a - b);
        const medianCellW: number = xGaps[Math.floor(xGaps.length / 2)];
        const firstGridCol: number = Math.round((colCenters[0] - boardL) / medianCellW - 0.5);
        const clampedFirstCol: number = Math.max(0, Math.min(firstGridCol, 8 - colCenters.length + 1));
        const refinedBoardL: number = colCenters[0] - (clampedFirstCol + 0.5) * medianCellW;
        const refinedBoardR: number = refinedBoardL + 9 * medianCellW;
        if (refinedBoardL >= 0 && refinedBoardR <= imgW) {
          hilog.info(DOMAIN, TAG, '【VisionKit Block详情】buildGrid colFit medianCellW=%{public}.1f firstGridCol=%{public}d refinedL=%.1f refinedR=%.1f',
            medianCellW, clampedFirstCol, refinedBoardL, refinedBoardR);
          boardL = refinedBoardL;
          boardR = refinedBoardR;
        }
      }
    }
  } else {
    const estimated: BoardBoundsOCR | null =
      estimateBoardBoundsFromDigits(rawDigits, imgW, imgH);
    if (estimated !== null) {
      boardL = estimated.boardL;
      boardT = estimated.boardT;
      boardR = estimated.boardR;
      boardB = estimated.boardB;
    }
    hilog.info(DOMAIN, TAG, '【VisionKit Block详情】buildGrid digitEst ocr=[%{public}.1f,%{public}.1f,%{public}.1f,%{public}.1f]',
      boardL, boardT, boardR, boardB);
  }

  const bW: number = boardR - boardL;
  const bH: number = boardB - boardT;

  if (bW <= 0 || bH <= 0) { return null; }

  const cellW: number = bW / 9;
  const cellH: number = bH / 9;

  const candidates: CellCandidate[] = new Array<CellCandidate>(81);
  for (let i: number = 0; i < 81; i++) {
    const cc: CellCandidate = { digit: 0, dist: Number.MAX_VALUE };
    candidates[i] = cc;
  }

  for (let i: number = 0; i < rawDigits.length; i++) {
    const d: RawDigit = rawDigits[i];
    const normX: number = (d.cx - boardL) / bW;
    const normY: number = (d.cy - boardT) / bH;
    const gridCol: number = Math.min(Math.max(Math.floor(normX * 9), 0), 8);
    const gridRow: number = Math.min(Math.max(Math.floor(normY * 9), 0), 8);
    const idx: number = gridRow * 9 + gridCol;

    const cellCx: number = boardL + (gridCol + 0.5) * cellW;
    const cellCy: number = boardT + (gridRow + 0.5) * cellH;
    const dist: number = Math.sqrt((d.cx - cellCx) * (d.cx - cellCx) + (d.cy - cellCy) * (d.cy - cellCy));

    if (dist < candidates[idx].dist) {
      const cc2: CellCandidate = { digit: d.digit, dist: dist };
      candidates[idx] = cc2;
    }
  }

  const grid: number[] = new Array<number>(81).fill(0);
  for (let i: number = 0; i < 81; i++) {
    grid[i] = candidates[i].digit;
  }
  const gridResult: VisionKitGridResult = {
    grid: grid, boardL: boardL, boardT: boardT,
    boardW: bW, boardH: bH, imgW: imgW, imgH: imgH
  };
  return gridResult;
}

export async function tryVisionKitRecognition(imagePath: string, imageBuf: ArrayBuffer | null = null): Promise<OCRResult> {
  let pixelMap: image.PixelMap | null = null;
  setLastDebugVkRawText('');
  setLastDebugVkBlockCount(0);
  setLastDebugVkOcrSize('');
  setLastDebugVkOcrError('');
  setLastDebugProbeInfo('');
  if (g_vkFailed) {
    hilog.warn(DOMAIN, TAG, 'VK: skip (g_vkFailed=true)');
    setLastDebugVkOcrError('VK previously failed, skipped');
    const failRet: OCRResult = {
      success: false, grid: null, rawText: '',
      error: 'VisionKit skipped (previous failure)',
      confidence: null, debugInfo: null
    };
    return failRet;
  }
  try {
    hilog.info(DOMAIN, TAG, 'VK: await textRecognition.init()');
    const initOk: boolean = await withTimeout<boolean>(textRecognition.init(), 5000, false);
    hilog.info(DOMAIN, TAG, 'VK: init() returned %{public}d', initOk ? 1 : 0);
    setVkInited(initOk);
    if (!initOk) {
      setLastDebugVkOcrError('VisionKit init() returned false');
      const initFailRet: OCRResult = {
        success: false, grid: null, rawText: '',
        error: 'VisionKit init failed',
        confidence: null, debugInfo: null
      };
      return initFailRet;
    }

    const imageSource: image.ImageSource = imageBuf !== null ? openImageSourceFromBuffer(imageBuf) : openImageSource(imagePath);
    hilog.info(DOMAIN, TAG, 'VK: await imageSource.getImageInfo()');
    const srcInfo: image.ImageInfo = await withTimeout<image.ImageInfo>(imageSource.getImageInfo(), 5000,
      { size: { width: 0, height: 0 } } as image.ImageInfo);
    const origW: number = srcInfo.size.width;
    const origH: number = srcInfo.size.height;

    const resize: AdaptiveResizeParams = computeAdaptiveResize(origW, origH);
    const probeW: number = resize.targetW;
    const probeH: number = resize.targetH;

    const probePm: image.PixelMap | null = await withTimeout<image.PixelMap | null>(imageSource.createPixelMap({
      desiredSize: { width: probeW, height: probeH },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    }), 5000, null);
    hilog.info(DOMAIN, TAG, 'VK: createPixelMap(probe) %{public}s', probePm !== null ? 'OK' : 'null');
    if (probePm === null) {
      imageSource.release();
      setLastDebugVkOcrError('createPixelMap(probe)超时');
      const probeFailRet: OCRResult = {
        success: false, grid: null, rawText: '',
        error: 'createPixelMap超时',
        confidence: null, debugInfo: null
      };
      return probeFailRet;
    }
    const probeImgInfo: image.ImageInfo = await probePm.getImageInfo();
    const probeImgW: number = probeImgInfo.size.width;
    const probeImgH: number = probeImgInfo.size.height;

    const probeBuf: ArrayBuffer = new ArrayBuffer(probeImgW * probeImgH * 4);
    probePm.readPixelsToBuffer(probeBuf);
    const probePixels: Uint8Array = new Uint8Array(probeBuf);
    probePm.release();

    setCachedPixels(probePixels);
    setCachedImgW(probeImgW);
    setCachedImgH(probeImgH);

    const bg: number = bgColor(probePixels, probeImgW, probeImgH);
    const isDark: boolean = bg < BG_DARK_THRESHOLD;
    const bbox: BoardBBox = findBoardBBox(probePixels, probeImgW, probeImgH, bg);
    const boardW: number = bbox.right - bbox.left;
    const boardH: number = bbox.bottom - bbox.top;
    const cellW: number = boardW / 9;
    const cellH: number = boardH / 9;
    const isFullImage: boolean = bbox.left === 0 && bbox.top === 0 &&
      bbox.right === probeImgW && bbox.bottom === probeImgH;

    const probeBboxVal: BoardBBox = {
      left: bbox.left, top: bbox.top,
      right: bbox.right, bottom: bbox.bottom,
      isDark: bbox.isDark
    };
    setProbeBbox(probeBboxVal);
    setProbeResizeW(probeImgW);
    setProbeResizeH(probeImgH);

    const bgHist: number[] = new Array<number>(256).fill(0);
    const bgSampleStep: number = Math.max(1, Math.floor(probeImgW * probeImgH / 20000));
    let bgMin: number = 255;
    let bgMax: number = 0;
    for (let i: number = 0; i < probeImgW * probeImgH; i += bgSampleStep) {
      const g: number = Math.floor(0.299 * probePixels[i * 4] + 0.587 * probePixels[i * 4 + 1] + 0.114 * probePixels[i * 4 + 2]);
      if (g >= 0 && g <= 255) { bgHist[g]++; }
      if (g < bgMin) { bgMin = g; }
      if (g > bgMax) { bgMax = g; }
    }
    let bgHistTop3: string = '';
    for (let pass: number = 0; pass < 3; pass++) {
      let topI: number = 0;
      let topV: number = 0;
      for (let i: number = 0; i < 256; i++) {
        if (bgHist[i] > topV && bgHist[i] > 0) {
          topV = bgHist[i];
          topI = i;
        }
      }
      if (topV > 0) {
        bgHistTop3 += (bgHistTop3.length > 0 ? ', ' : '') + `${topI}(${topV})`;
        bgHist[topI] = 0;
      }
    }
    const boardAreaRatio: number = (boardW * boardH) / (probeImgW * probeImgH);
    const boardAspect: number = boardH > 0 ? boardW / boardH : 0;

    setLastDebugProbeInfo(`实际探测图=${probeImgW}x${probeImgH} bg=${bg.toFixed(1)} isDark=${isDark ? 1 : 0} bgRange=[${bgMin},${bgMax}] bgHistTop3=[${bgHistTop3}]`);
    setLastDebugBbox(`原图${origW}x${origH}→探测${probeImgW}x${probeImgH} bbox=[${bbox.left},${bbox.top},${bbox.right},${bbox.bottom}] board=${boardW}x${boardH} cell=${cellW.toFixed(1)}x${cellH.toFixed(1)} isDark=${bbox.isDark ? 1 : 0} isFullImageFallback=${isFullImage ? 1 : 0} areaRatio=${boardAreaRatio.toFixed(3)} aspect=${boardAspect.toFixed(2)}`);
    setLastDebugResize(`resize: ${origW}x${origH} → ${resize.targetW}x${resize.targetH} targetCellPx=${resize.targetCellPx}`);

    hilog.info(DOMAIN, TAG, '【探测图详情】%{public}s', g_lastDebugProbeInfo);
    hilog.info(DOMAIN, TAG, '【图片与棋盘】%{public}s', g_lastDebugBbox);

    if (isFullImage) {
      hilog.warn(DOMAIN, TAG, 'VisionKit: 警告 - findBoardBBox返回全图退化bbox，棋盘定位可能失败');
    }

    const TARGET_CELL_PX_LOCAL: number = resize.targetCellPx;
    const boardScale: number = TARGET_CELL_PX_LOCAL / Math.min(cellW, cellH);
    const cropL: number = Math.max(Math.floor(bbox.left - boardW * BOARD_CROP_PAD_RATIO), 0);
    const cropT: number = Math.max(Math.floor(bbox.top - boardH * BOARD_CROP_PAD_RATIO), 0);
    const cropR: number = Math.min(Math.floor(bbox.right + boardW * BOARD_CROP_PAD_RATIO), probeImgW);
    const cropB: number = Math.min(Math.floor(bbox.bottom + boardH * BOARD_CROP_PAD_RATIO), probeImgH);
    const cropW: number = cropR - cropL;
    const cropH: number = cropB - cropT;

    const targetW: number = Math.round(cropW * boardScale);
    const targetH: number = Math.round(cropH * boardScale);
    const maxDim: number = OCR_MAX_DIM;
    let finalW: number = targetW;
    let finalH: number = targetH;
    if (finalW > maxDim || finalH > maxDim) {
      const ms: number = maxDim / Math.max(finalW, finalH);
      finalW = Math.round(finalW * ms);
      finalH = Math.round(finalH * ms);
    }
    const minDim: number = OCR_MIN_DIM;
    if (Math.min(finalW, finalH) < minDim) {
      const ms2: number = minDim / Math.min(finalW, finalH);
      finalW = Math.round(finalW * ms2);
      finalH = Math.round(finalH * ms2);
    }

    hilog.info(DOMAIN, TAG, '【缩放参数】探测图%{public}dx%{public}d 棋盘[%{public}d,%{public}d,%{public}d,%{public}d] 每格=%{public}.1f 放大=%{public}.2f clip->target %{public}dx%{public}d',
      probeImgW, probeImgH, bbox.left, bbox.top, bbox.right, bbox.bottom,
      Math.min(cellW, cellH), boardScale, finalW, finalH);

    const probeToOrigScaleX: number = origW / probeImgW;
    const probeToOrigScaleY: number = origH / probeImgH;
    const origCropL: number = Math.round(cropL * probeToOrigScaleX);
    const origCropT: number = Math.round(cropT * probeToOrigScaleY);
    const origCropW: number = Math.round(cropW * probeToOrigScaleX);
    const origCropH: number = Math.round(cropH * probeToOrigScaleY);

    hilog.info(DOMAIN, TAG, '【缩放参数】probe→orig scaleX=%{public}.2f scaleY=%{public}.2f crop(...)->orig(%{public}d,%{public}d,%{public}d,%{public}d)',
      probeToOrigScaleX, probeToOrigScaleY, origCropL, origCropT, origCropW, origCropH);

    pixelMap = await withTimeout<image.PixelMap | null>(imageSource.createPixelMap({
      desiredRegion: { size: { width: origCropW, height: origCropH }, x: origCropL, y: origCropT },
      desiredSize: { width: finalW, height: finalH },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST
    }), 5000, null);
    imageSource.release();

    if (pixelMap === null) {
      setLastDebugVkOcrError('createPixelMap(OCR)超时');
      const pmFailRet: OCRResult = {
        success: false, grid: null, rawText: '',
        error: 'createPixelMap超时',
        confidence: null, debugInfo: null
      };
      return pmFailRet;
    }

    const imageInfo: image.ImageInfo = await pixelMap.getImageInfo();
    const imgW: number = imageInfo.size.width;
    const imgH: number = imageInfo.size.height;
    setLastDebugVkOcrSize(`${imgW}x${imgH}`);
    hilog.info(DOMAIN, TAG, '【VisionKit OCR图尺寸】%{public}dx%{public}d', imgW, imgH);

    const ocrBuf: ArrayBuffer = new ArrayBuffer(imgW * imgH * 4);
    pixelMap.readPixelsToBuffer(ocrBuf);
    const ocrPx: Uint8Array = new Uint8Array(ocrBuf);
    let ocrBgSum: number = 0;
    const ocrBgStep: number = Math.max(1, Math.floor(imgW * imgH / 10000));
    let ocrBgCnt: number = 0;
    for (let i: number = 0; i < imgW * imgH; i += ocrBgStep) {
      ocrBgSum += Math.floor(0.299 * ocrPx[i * 4] + 0.587 * ocrPx[i * 4 + 1] + 0.114 * ocrPx[i * 4 + 2]);
      ocrBgCnt++;
    }
    const ocrBg: number = ocrBgCnt > 0 ? ocrBgSum / ocrBgCnt : 128;
    for (let i: number = 0; i < imgW * imgH; i++) {
      const rv: number = ocrPx[i * 4];
      const gv: number = ocrPx[i * 4 + 1];
      const bv: number = ocrPx[i * 4 + 2];
      const gray: number = 0.299 * rv + 0.587 * gv + 0.114 * bv;
      const ink: number = ocrBg >= 128
        ? Math.max(0, (ocrBg - gray) / ocrBg)
        : Math.max(0, (gray - ocrBg) / (255 - ocrBg));
      const contrastInk: number = Math.min(1, Math.max(0, (ink - 0.1) / 0.2));
      const outVal: number = Math.round(255 * (1 - contrastInk));
      ocrPx[i * 4] = outVal;
      ocrPx[i * 4 + 1] = outVal;
      ocrPx[i * 4 + 2] = outVal;
    }
    const destArea: image.PositionArea = {
      pixels: ocrBuf,
      offset: 0,
      stride: imgW * 4,
      region: { size: { width: imgW, height: imgH }, x: 0, y: 0 }
    };
    pixelMap.writePixelsSync(destArea);
    hilog.info(DOMAIN, TAG, '【VisionKit预处理】软对比度拉伸 ocrBg=%{public}.1f', ocrBg);

    const visionInfo: textRecognition.VisionInfo = { pixelMap: pixelMap };
    hilog.info(DOMAIN, TAG, 'VK: await recognizeText() main OCR');
    const recogResult: textRecognition.TextRecognitionResult =
      await withTimeout<textRecognition.TextRecognitionResult>(
        textRecognition.recognizeText(visionInfo, {
          isDirectionDetectionSupported: true
        }), 10000,
        { value: '', blocks: [] } as textRecognition.TextRecognitionResult
      );
    hilog.info(DOMAIN, TAG, 'VK: recognizeText() blocks=%{public}d', (recogResult.blocks || []).length);

    const rawText: string = recogResult.value || '';
    const vkBlocks: Array<textRecognition.TextBlock> = recogResult.blocks || [];
    setLastDebugVkRawText(rawText.substring(0, 500));
    setLastDebugVkBlockCount(vkBlocks.length);
    hilog.info(DOMAIN, TAG, '【VisionKit原始文本】(%{public}d chars) "%{public}s"', rawText.length, rawText.substring(0, 200));
    hilog.info(DOMAIN, TAG, '【VisionKit Block数】%{public}d', vkBlocks.length);

    let vkLineCount: number = 0;
    let vkWordCount: number = 0;
    let vkDigitWordCount: number = 0;
    let vkBlockDetails: string = '';
    for (let bi: number = 0; bi < vkBlocks.length; bi++) {
      const block: textRecognition.TextBlock = vkBlocks[bi];
      const lines: Array<textRecognition.TextLine> = block.lines || [];
      vkLineCount += lines.length;
      for (let li: number = 0; li < lines.length; li++) {
        const line: textRecognition.TextLine = lines[li];
        const words: Array<textRecognition.TextWord> = line.words || [];
        vkWordCount += words.length;
        for (let wi: number = 0; wi < words.length; wi++) {
          const word: textRecognition.TextWord = words[wi];
          const hasDigit: boolean = new RegExp('[0-9]').test(word.value);
          if (hasDigit) { vkDigitWordCount++; }
          if (vkBlockDetails.length < 2000) {
            const cp: Array<textRecognition.PixelPoint> = word.cornerPoints;
            let posStr2: string = '';
            if (cp.length >= 4) {
              const cx2: number = Math.round((cp[0].x + cp[1].x + cp[2].x + cp[3].x) / 4);
              const cy2: number = Math.round((cp[0].y + cp[1].y + cp[2].y + cp[3].y) / 4);
              posStr2 = ` xy=(${cx2},${cy2})`;
            }
            vkBlockDetails += `B${bi}L${li}W${wi}="${word.value}" cp=${cp.length}${posStr2}`;
            if (wi < words.length - 1) { vkBlockDetails += ' | '; }
          }
        }
      }
      if (bi < vkBlocks.length - 1 && vkBlockDetails.length < 2000) { vkBlockDetails += '\n'; }
    }
    hilog.info(DOMAIN, TAG, '【VisionKit Block详情】blocks=%{public}d lines=%{public}d words=%{public}d digitWords=%{public}d\n%{public}s',
      vkBlocks.length, vkLineCount, vkWordCount, vkDigitWordCount, vkBlockDetails);
    setLastDebugVkBlockDetail(vkBlockDetails);
    const ocrErrMsg: string = vkBlocks.length === 0 ? 'blocks为空，VisionKit未检测到任何文字' : (vkDigitWordCount === 0 ? `有${vkBlocks.length}个block但无数字word` : '');
    setLastDebugVkOcrError(ocrErrMsg);

    const cropToOcrScaleX: number = imgW / cropW;
    const cropToOcrScaleY: number = imgH / cropH;
    const mapL: number = (bbox.left - cropL) * cropToOcrScaleX;
    const mapT: number = (bbox.top - cropT) * cropToOcrScaleY;
    const mapR: number = (bbox.right - cropL) * cropToOcrScaleX;
    const mapB: number = (bbox.bottom - cropT) * cropToOcrScaleY;
    const mapCellW: number = (mapR - mapL) / 9;
    const mapCellH: number = (mapB - mapT) / 9;
    const sizeExtra: string = ` boardOcr=[${mapL.toFixed(0)},${mapT.toFixed(0)},${mapR.toFixed(0)},${mapB.toFixed(0)}] cellOcr=${mapCellW.toFixed(1)}x${mapCellH.toFixed(1)}`;
    setLastDebugVkOcrSize(g_lastDebugVkOcrSize + sizeExtra);

    const posResult: VisionKitGridResult | null = buildGridByPosition(
      recogResult, imgW, imgH, bbox, cropL, cropT, cropToOcrScaleX, cropToOcrScaleY
    );
    if (posResult !== null) {
      const fittedL: number = posResult.boardL / cropToOcrScaleX + cropL;
      const fittedT: number = posResult.boardT / cropToOcrScaleY + cropT;
      const fittedR: number = (posResult.boardL + posResult.boardW) / cropToOcrScaleX + cropL;
      const fittedB: number = (posResult.boardT + posResult.boardH) / cropToOcrScaleY + cropT;
      setFittedBoardL(fittedL);
      setFittedBoardT(fittedT);
      setFittedBoardR(fittedR);
      setFittedBoardB(fittedB);
      hilog.info(DOMAIN, TAG, '【VisionKit Block详情】fittedBoard detect=[%{public}.1f,%{public}.1f,%{public}.1f,%{public}.1f]',
        fittedL, fittedT, fittedR, fittedB);
    }
    setLastDebugRawDigits(posResult !== null ? posResult.grid.filter((d: number) => d > 0).length : 0);
    if (posResult !== null && posResult.grid.some((d: number) => d > 0)) {
      const givenCount: number = posResult.grid.filter((d: number) => d > 0).length;
      let gridStr: string = '';
      for (let r: number = 0; r < 9; r++) {
        let line: string = '';
        for (let c: number = 0; c < 9; c++) {
          line += (posResult.grid[r * 9 + c] === 0 ? '.' : posResult.grid[r * 9 + c].toString()) + ' ';
        }
        gridStr += line + '\n';
      }
      hilog.info(DOMAIN, TAG, '【VisionKit网格】%{public}d digits\n%{public}s', givenCount, gridStr);
      const posRet: OCRResult = {
        success: true, grid: posResult.grid, rawText: 'positional',
        error: '', confidence: new Array<number>(81).fill(POSITIONAL_CONFIDENCE),
        debugInfo: null
      };
      return posRet;
    }

    const gridByText: number[] | null = parseOCRToGrid(rawText);
    if (gridByText !== null && gridByText.some((d: number) => d > 0)) {
      hilog.info(DOMAIN, TAG, '【步骤详情】text fallback OK raw="%{public}s"', rawText);
      const textRet: OCRResult = {
        success: true, grid: gridByText, rawText: rawText,
        error: '', confidence: new Array<number>(81).fill(TEXT_FALLBACK_CONFIDENCE),
        debugInfo: null
      };
      return textRet;
    }

    const structuredText: string = extractStructuredText(recogResult);
    if (structuredText.length > rawText.length) {
      const grid2: number[] | null = parseOCRToGrid(structuredText);
      if (grid2 !== null && grid2.some((d: number) => d > 0)) {
        hilog.info(DOMAIN, TAG, '【步骤详情】structured text fallback OK\n%{public}s', structuredText);
        const structRet: OCRResult = {
          success: true, grid: grid2, rawText: structuredText,
          error: '', confidence: new Array<number>(81).fill(TEXT_FALLBACK_CONFIDENCE),
          debugInfo: null
        };
        return structRet;
      }
    }

    const errDetail: string = `rawText="${rawText.substring(0, 100)}" blocks=${vkBlocks.length} lines=${vkLineCount} words=${vkWordCount} digitWords=${vkDigitWordCount} positionalDigits=${g_lastDebugRawDigits}`;
    setLastDebugVkOcrError(errDetail);
    const noResult: OCRResult = {
      success: false, grid: null, rawText: rawText,
      error: '识别文本中未检测到数独数字，请确保图片清晰、棋盘端正',
      confidence: null, debugInfo: null
    };
    return noResult;
  } catch (_e) {
    const errStr: string = `异常: ${_e}`;
    setLastDebugVkOcrError(errStr);
    setVkInited(false);
    setVkFailed(true);
    hilog.error(DOMAIN, TAG, 'VK exception: %{public}s, setting g_vkFailed=true', `${_e}`);
    textRecognition.release().catch((_ee: Object) => { /* ignore */ });
    const excRet: OCRResult = {
      success: false, grid: null, rawText: '',
      error: 'VisionKit unavailable',
      confidence: null, debugInfo: null
    };
    return excRet;
  } finally {
    if (pixelMap !== null) { pixelMap.release(); }
  }
}

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
