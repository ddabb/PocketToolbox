import { image } from '@kit.ImageKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { fileIo } from '@kit.CoreFileKit';
import { parseOCRToGrid } from './SudokuEngine';
import { BoardBBox, BoardCorners, bgColor, cellSigFromGray, countInk, detectBoardCorners, findBoardBBox, holeCenterRow, inkCentroidRow, topBottomInkRatio, recognizeDigit, SIG_COLS, SIG_ROWS, toGrayArray, warpPerspectiveGray } from './SudokuPixel';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xA03D00;
const TAG: string = 'SudokuOCR';

export interface OCRResult {
  success: boolean;
  grid: number[] | null;
  rawText: string;
  error: string;
}

interface VisionKitGridResult {
  grid: number[];
  boardL: number;
  boardT: number;
  boardW: number;
  boardH: number;
  imgW: number;
  imgH: number;
}

interface RawDigit {
  cx: number;
  cy: number;
  digit: number;
}

interface AdaptiveResizeParams {
  targetW: number;
  targetH: number;
  targetCellPx: number;
}

function computeAdaptiveResize(origW: number, origH: number): AdaptiveResizeParams {
  const maxDim: number = Math.max(origW, origH);
  let targetW: number = origW;
  let targetH: number = origH;
  let targetCellPx: number = 56;

  if (maxDim > 2000) {
    targetCellPx = 80;
  } else {
    targetCellPx = 56;
  }

  if (maxDim > 2000) {
    const scale: number = 1600 / maxDim;
    targetW = Math.round(origW * scale);
    targetH = Math.round(origH * scale);
  } else if (maxDim >= 800) {
    if (maxDim > 1280) {
      const scale: number = 1280 / maxDim;
      targetW = Math.round(origW * scale);
      targetH = Math.round(origH * scale);
    }
  } else {
    const scale: number = 800 / maxDim;
    targetW = Math.round(origW * scale);
    targetH = Math.round(origH * scale);
  }

  const params: AdaptiveResizeParams = { targetW: targetW, targetH: targetH, targetCellPx: targetCellPx };
  return params;
}

function openImageSource(uri: string): image.ImageSource {
  if (uri.startsWith('file://media/') || uri.startsWith('content://')) {
    const file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    return image.createImageSource(file.fd);
  }
  return image.createImageSource(uri);
}

export async function recognizeSudokuFromImage(imagePath: string): Promise<OCRResult> {
  try {
    hilog.info(DOMAIN, TAG, '=== 开始识别 === path=%{public}s', imagePath);
    const visionResult: OCRResult = await tryVisionKitRecognition(imagePath);
    hilog.info(DOMAIN, TAG, 'VisionKit: success=%{public}d error=%{public}s', visionResult.success ? 1 : 0, visionResult.error);
    if (visionResult.success && visionResult.grid) {
      const corrected: OCRResult = await validateAndFixConflicts(visionResult, imagePath);
    const filled: OCRResult = await fillMissingCells(corrected, imagePath);
    return filled;
    }
    hilog.info(DOMAIN, TAG, 'VisionKit 失败，转像素分析');
    return await tryPixelGridRecognition(imagePath);
  } catch (_err) {
    hilog.error(DOMAIN, TAG, '异常: %{public}s', `${_err}`);
    return { success: false, grid: null, rawText: '', error: '图片处理异常，请尝试手动输入' };
  }
}

function findConflictCells(grid: number[]): number[] {
  const conflicts: Set<number> = new Set<number>();

  for (let r: number = 0; r < 9; r++) {
    for (let c: number = 0; c < 9; c++) {
      const val: number = grid[r * 9 + c];
      if (val === 0) { continue; }
      for (let j: number = 0; j < 9; j++) {
        if (j !== c && grid[r * 9 + j] === val) {
          conflicts.add(r * 9 + c);
          conflicts.add(r * 9 + j);
        }
        if (j !== r && grid[j * 9 + c] === val) {
          conflicts.add(r * 9 + c);
          conflicts.add(j * 9 + c);
        }
      }
      const boxR: number = Math.floor(r / 3) * 3;
      const boxC: number = Math.floor(c / 3) * 3;
      for (let br: number = boxR; br < boxR + 3; br++) {
        for (let bc: number = boxC; bc < boxC + 3; bc++) {
          if (!(br === r && bc === c) && grid[br * 9 + bc] === val) {
            conflicts.add(r * 9 + c);
            conflicts.add(br * 9 + bc);
          }
        }
      }
    }
  }

  const result: number[] = [];
  conflicts.forEach((idx: number) => { result.push(idx); });
  return result.sort((a: number, b: number) => a - b);
}

async function validateAndFixConflicts(visionResult: OCRResult, imagePath: string): Promise<OCRResult> {
  if (!visionResult.grid) { return visionResult; }
  const grid: number[] = [...visionResult.grid];

  const conflictIndices: number[] = findConflictCells(grid);
  if (conflictIndices.length === 0) {
    hilog.info(DOMAIN, TAG, '验证: 无冲突，直接采用VisionKit结果');
    return visionResult;
  }

  const conflictStr: string = conflictIndices.map((idx: number) =>
    `[${Math.floor(idx / 9)},${idx % 9}]=${grid[idx]}`
  ).join(' ');
  hilog.info(DOMAIN, TAG, '验证: 发现 %{public}d 个冲突格子: %{public}s', conflictIndices.length, conflictStr);

  let fullPixelMap: image.PixelMap | null = null;
  let fullGray: Float32Array | null = null;
  let fullBbox: BoardBBox | null = null;
  let fullBg: number = 0;
  let fullImgW: number = 0;
  let fullImgH: number = 0;

  const imageSource: image.ImageSource = openImageSource(imagePath);
  const srcInfo: image.ImageInfo = await imageSource.getImageInfo();
  const origW: number = srcInfo.size.width;
  const origH: number = srcInfo.size.height;

  const resize: AdaptiveResizeParams = computeAdaptiveResize(origW, origH);

  fullPixelMap = await imageSource.createPixelMap({
    desiredSize: { width: resize.targetW, height: resize.targetH },
    desiredPixelFormat: image.PixelMapFormat.RGBA_8888
  });
  imageSource.release();

  const info: image.ImageInfo = await fullPixelMap.getImageInfo();
  fullImgW = info.size.width;
  fullImgH = info.size.height;

  const buffer: ArrayBuffer = new ArrayBuffer(fullImgW * fullImgH * 4);
  fullPixelMap.readPixelsToBuffer(buffer);
  const pixels: Uint8Array = new Uint8Array(buffer);

  fullBg = bgColor(pixels, fullImgW, fullImgH);
  fullGray = toGrayArray(pixels, fullImgW, fullImgH);
  fullBbox = findBoardBBox(pixels, fullImgW, fullImgH, fullBg);

  let fixCount: number = 0;

  for (const idx of conflictIndices) {
    const row: number = Math.floor(idx / 9);
    const col: number = idx % 9;
    const origDigit: number = grid[idx];
    hilog.info(DOMAIN, TAG, '修正 [%{public}d,%{public}d] VisionKit=%{public}d', row, col, origDigit);

    const cellDigit: number | null = await reRecognizeCell(
      fullPixelMap, fullImgW, fullImgH, row, col,
      fullBbox, fullGray, fullBg
    );

    if (cellDigit !== null && cellDigit !== origDigit) {
      hilog.info(DOMAIN, TAG, '修正 [%{public}d,%{public}d] %{public}d -> %{public}d', row, col, origDigit, cellDigit);
      grid[idx] = cellDigit;
      fixCount++;

      const newConflicts: number[] = findConflictCells(grid);
      const stillConflict: boolean = newConflicts.some((ci: number) => ci === idx);
      if (stillConflict && (cellDigit === 6 || cellDigit === 9)) {
        const swapped: number = cellDigit === 6 ? 9 : 6;
        grid[idx] = swapped;
        const afterSwap: number[] = findConflictCells(grid);
        const swapConflict: boolean = afterSwap.some((ci: number) => ci === idx);
        if (swapConflict) {
          grid[idx] = cellDigit;
          hilog.info(DOMAIN, TAG, '6/9翻转后仍冲突，保留 %{public}d', cellDigit);
        } else {
          hilog.info(DOMAIN, TAG, '6/9翻转 %{public}d -> %{public}d 冲突消除', cellDigit, swapped);
          fixCount++;
        }
      }
    } else {
      hilog.info(DOMAIN, TAG, '修正 [%{public}d,%{public}d] 结果不变=%{public}d', row, col, origDigit);
    }
  }

  fullPixelMap.release();

  if (fixCount > 0) {
    hilog.info(DOMAIN, TAG, '验证: 修正了 %{public}d 个冲突格子', fixCount);
    return { success: true, grid: grid, rawText: visionResult.rawText + '+conflictFix', error: '' };
  }
  hilog.info(DOMAIN, TAG, '验证: 无法修正，采用VisionKit结果');
  return visionResult;
}

async function fillMissingCells(ocrResult: OCRResult, imagePath: string): Promise<OCRResult> {
  if (!ocrResult.success || !ocrResult.grid) { return ocrResult; }
  const grid: number[] = [...ocrResult.grid];
  const emptyIndices: number[] = [];
  for (let i: number = 0; i < 81; i++) {
    if (grid[i] === 0) { emptyIndices.push(i); }
  }
  if (emptyIndices.length === 0) { return ocrResult; }

  hilog.info(DOMAIN, TAG, '补缺: 发现 %{public}d 个空格子', emptyIndices.length);

  const imageSource: image.ImageSource = openImageSource(imagePath);
  const srcInfo: image.ImageInfo = await imageSource.getImageInfo();
  const origW: number = srcInfo.size.width;
  const origH: number = srcInfo.size.height;

  const resize: AdaptiveResizeParams = computeAdaptiveResize(origW, origH);

  const pixelMap: image.PixelMap = await imageSource.createPixelMap({
    desiredSize: { width: resize.targetW, height: resize.targetH },
    desiredPixelFormat: image.PixelMapFormat.RGBA_8888
  });
  imageSource.release();

  const info: image.ImageInfo = await pixelMap.getImageInfo();
  const imgW: number = info.size.width;
  const imgH: number = info.size.height;

  const buffer: ArrayBuffer = new ArrayBuffer(imgW * imgH * 4);
  pixelMap.readPixelsToBuffer(buffer);
  const pixels: Uint8Array = new Uint8Array(buffer);

  const bg: number = bgColor(pixels, imgW, imgH);
  const gray: Float32Array = toGrayArray(pixels, imgW, imgH);
  const bbox: BoardBBox = findBoardBBox(pixels, imgW, imgH, bg);

  let fillCount: number = 0;

  for (const idx of emptyIndices) {
    const row: number = Math.floor(idx / 9);
    const col: number = idx % 9;
    const cellW: number = (bbox.right - bbox.left) / 9;
    const cellH: number = (bbox.bottom - bbox.top) / 9;
    const cellLeft: number = bbox.left + col * cellW;
    const cellTop: number = bbox.top + row * cellH;

    const sig: number[] | null = cellSigFromGray(gray, imgW, cellLeft, cellTop, cellW, cellH, bbox.isDark, bg);
    if (sig === null) { continue; }

    const inkCount: number = countInk(sig);
    if (inkCount < SIG_ROWS * SIG_COLS * 0.05) { continue; }

    const cellDigit: number | null = await reRecognizeCell(
      pixelMap, imgW, imgH, row, col, bbox, gray, bg
    );
    if (cellDigit !== null && cellDigit > 0) {
      hilog.info(DOMAIN, TAG, '补缺 [%{public}d,%{public}d] =%{public}d (VisionKit+像素)', row, col, cellDigit);
      grid[idx] = cellDigit;
      fillCount++;
    } else {
      const digit: number = recognizeDigit(sig, inkCount);
      if (digit > 0) {
        hilog.info(DOMAIN, TAG, '补缺 [%{public}d,%{public}d] 像素=%{public}d ink=%{public}d', row, col, digit, inkCount);
        grid[idx] = digit;
        fillCount++;
      }
    }
  }

  pixelMap.release();

  if (fillCount > 0) {
    hilog.info(DOMAIN, TAG, '补缺: 填充了 %{public}d 个空格子', fillCount);
    return { success: true, grid: grid, rawText: ocrResult.rawText + '+fillMissing', error: '' };
  }
  return ocrResult;
}

async function reRecognizeCell(
  fullPixelMap: image.PixelMap,
  imgW: number, imgH: number,
  row: number, col: number,
  bbox: BoardBBox,
  gray: Float32Array | null,
  bg: number
): Promise<number | null> {
  const cellW: number = (bbox.right - bbox.left) / 9;
  const cellH: number = (bbox.bottom - bbox.top) / 9;
  const cellLeft: number = bbox.left + col * cellW;
  const cellTop: number = bbox.top + row * cellH;

  const padFactor: number = 0.15;
  const cropX: number = Math.max(Math.floor(cellLeft - cellW * padFactor), 0);
  const cropY: number = Math.max(Math.floor(cellTop - cellH * padFactor), 0);
  const cropR: number = Math.min(Math.floor(cellLeft + cellW + cellW * padFactor), imgW);
  const cropB: number = Math.min(Math.floor(cellTop + cellH + cellH * padFactor), imgH);
  const cropW: number = cropR - cropX;
  const cropH: number = cropB - cropY;

  if (cropW < 10 || cropH < 10) {
    hilog.info(DOMAIN, TAG, '重识[%{public}d,%{public}d] 裁剪区域太小', row, col);
    return null;
  }

  const vkDigit: number | null = await reRecognizeCellVisionKit(
    fullPixelMap, imgW, imgH, cropX, cropY, cropW, cropH
  );
  hilog.info(DOMAIN, TAG, '重识[%{public}d,%{public}d] VisionKit重识=%{public}d', row, col, vkDigit !== null ? vkDigit : -1);

  if (vkDigit !== null) {
    hilog.info(DOMAIN, TAG, '重识[%{public}d,%{public}d] VisionKit重识=%{public}d，启动像素分析', row, col, vkDigit);
  }

  if (gray !== null) {
    const pixelDigit: number | null = reRecognizeCellPixel(
      gray, imgW, cellLeft, cellTop, cellW, cellH, bbox.isDark, bg, row, col
    );
    hilog.info(DOMAIN, TAG, '重识[%{public}d,%{public}d] 像素分析=%{public}d', row, col, pixelDigit !== null ? pixelDigit : -1);

    if (pixelDigit !== null) {
      if (vkDigit === null) {
        return pixelDigit;
      }
      if (vkDigit === pixelDigit) {
        return vkDigit;
      }
      hilog.info(DOMAIN, TAG, '重识[%{public}d,%{public}d] VisionKit=%{public}d vs Pixel=%{public}d 不一致，采用像素分析', row, col, vkDigit, pixelDigit);
      return pixelDigit;
    }
  }

  return vkDigit;
}

async function reRecognizeCellVisionKit(
  fullPixelMap: image.PixelMap,
  imgW: number, imgH: number,
  cropX: number, cropY: number, cropW: number, cropH: number
): Promise<number | null> {
  try {
    const upscale: number = 3;
    const targetW: number = cropW * upscale;
    const targetH: number = cropH * upscale;

    const cellPm: image.PixelMap = fullPixelMap.cloneSync();
    cellPm.cropSync({
      size: { width: cropW, height: cropH },
      x: cropX, y: cropY
    });
    cellPm.scaleSync(upscale, upscale);

    const initOk: boolean = await textRecognition.init();
    if (!initOk) {
      cellPm.release();
      return null;
    }

    const visionInfo: textRecognition.VisionInfo = { pixelMap: cellPm };
    const recogResult: textRecognition.TextRecognitionResult =
      await textRecognition.recognizeText(visionInfo, {
        isDirectionDetectionSupported: false
      });
    await textRecognition.release();
    cellPm.release();

    const rawText: string = recogResult.value || '';
    const digits: string[] = rawText.replace(/[^0-9]/g, '').split('');
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

    hilog.info(DOMAIN, TAG, 'VisionKit重识: rawText="%{public}s" bestDigit=%{public}d', rawText, bestDigit);
    return bestDigit;
  } catch (_e) {
    hilog.error(DOMAIN, TAG, 'VisionKit重识异常: %{public}s', `${_e}`);
    return null;
  }
}

function reRecognizeCellPixel(
  gray: Float32Array,
  imgW: number,
  cellLeft: number, cellTop: number,
  cellW: number, cellH: number,
  isDark: boolean, bg: number,
  row: number, col: number
): number | null {
  const sig: number[] | null = cellSigFromGray(
    gray, imgW,
    cellLeft, cellTop, cellW, cellH, isDark, bg
  );
  if (sig === null) {
    return null;
  }

  const inkCount: number = countInk(sig);
  const templateDigit: number = recognizeDigit(sig, inkCount);

  if (templateDigit === 6 || templateDigit === 9) {
    const pixelDigit: number = disambiguate69(sig, templateDigit, row, col);
    return pixelDigit;
  }

  return templateDigit;
}

function disambiguate69(sig: number[], visionDigit: number, row: number, col: number): number {
  const qHole: number = holeCenterRow(sig);
  const iCentroid: number = inkCentroidRow(sig);
  const ratio: number = topBottomInkRatio(sig);

  let vote6: number = 0;
  let vote9: number = 0;

  if (qHole >= 0) {
    if (qHole > SIG_ROWS / 2) { vote6 += 2; } else { vote9 += 2; }
  }
  if (iCentroid >= 0) {
    if (iCentroid > SIG_ROWS / 2) { vote6++; } else { vote9++; }
  }
  if (ratio > 0.5) { vote9++; } else { vote6++; }

  const pixelAnswer: number = vote6 >= vote9 ? 6 : 9;

  hilog.info(DOMAIN, TAG, '6/9消歧 [%{public}d,%{public}d] digit=%{public}d qHole=%{public}.2f centroid=%{public}.2f ratio=%{public}.2f vote6=%{public}d vote9=%{public}d => %{public}d',
    row, col, visionDigit, qHole, iCentroid, ratio, vote6, vote9, pixelAnswer);

  return pixelAnswer;
}

async function tryVisionKitRecognition(imagePath: string): Promise<OCRResult> {
  let pixelMap: image.PixelMap | null = null;
  try {
    const initOk: boolean = await textRecognition.init();
    if (!initOk) {
      return { success: false, grid: null, rawText: '', error: 'VisionKit init failed' };
    }

    const imageSource: image.ImageSource = openImageSource(imagePath);
    const srcInfo: image.ImageInfo = await imageSource.getImageInfo();
    const origW: number = srcInfo.size.width;
    const origH: number = srcInfo.size.height;

    const resize: AdaptiveResizeParams = computeAdaptiveResize(origW, origH);
    const probeW: number = resize.targetW;
    const probeH: number = resize.targetH;

    const probePm: image.PixelMap = await imageSource.createPixelMap({
      desiredSize: { width: probeW, height: probeH },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    });
    const probeInfo: image.ImageInfo = await probePm.getImageInfo();
    const probeImgW: number = probeInfo.size.width;
    const probeImgH: number = probeInfo.size.height;

    const probeBuf: ArrayBuffer = new ArrayBuffer(probeImgW * probeImgH * 4);
    probePm.readPixelsToBuffer(probeBuf);
    const probePixels: Uint8Array = new Uint8Array(probeBuf);
    probePm.release();

    const bg: number = bgColor(probePixels, probeImgW, probeImgH);
    const bbox: BoardBBox = findBoardBBox(probePixels, probeImgW, probeImgH, bg);
    const boardW: number = bbox.right - bbox.left;
    const boardH: number = bbox.bottom - bbox.top;
    const cellW: number = boardW / 9;
    const cellH: number = boardH / 9;

    const TARGET_CELL_PX: number = resize.targetCellPx;
    const boardScale: number = TARGET_CELL_PX / Math.min(cellW, cellH);
    const cropL: number = Math.max(Math.floor(bbox.left - boardW * 0.05), 0);
    const cropT: number = Math.max(Math.floor(bbox.top - boardH * 0.05), 0);
    const cropR: number = Math.min(Math.floor(bbox.right + boardW * 0.05), probeImgW);
    const cropB: number = Math.min(Math.floor(bbox.bottom + boardH * 0.05), probeImgH);
    const cropW: number = cropR - cropL;
    const cropH: number = cropB - cropT;

    const targetW: number = Math.round(cropW * boardScale);
    const targetH: number = Math.round(cropH * boardScale);
    const maxDim: number = 4096;
    let finalW: number = targetW;
    let finalH: number = targetH;
    if (finalW > maxDim || finalH > maxDim) {
      const ms: number = maxDim / Math.max(finalW, finalH);
      finalW = Math.round(finalW * ms);
      finalH = Math.round(finalH * ms);
    }
    const minDim: number = 360;
    if (Math.min(finalW, finalH) < minDim) {
      const ms2: number = minDim / Math.min(finalW, finalH);
      finalW = Math.round(finalW * ms2);
      finalH = Math.round(finalH * ms2);
    }

    hilog.info(DOMAIN, TAG, 'VisionKit: 探测图%{public}dx%{public}d 棋盘[%{public}d,%{public}d,%{public}d,%{public}d] 每格=%{public}.1fx%{public}.1f 放大=%{public}.2f 裁剪=%{public}d,%{public}d,%{public}d,%{public}d 目标=%{public}dx%{public}d',
      probeImgW, probeImgH, bbox.left, bbox.top, bbox.right, bbox.bottom,
      cellW, cellH, boardScale, cropL, cropT, cropW, cropH, finalW, finalH);

    pixelMap = await imageSource.createPixelMap({
      desiredRegion: { size: { width: cropW, height: cropH }, x: cropL, y: cropT },
      desiredSize: { width: finalW, height: finalH },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST
    });
    imageSource.release();

    const imageInfo: image.ImageInfo = await pixelMap.getImageInfo();
    const imgW: number = imageInfo.size.width;
    const imgH: number = imageInfo.size.height;
    hilog.info(DOMAIN, TAG, 'VisionKit: 实际PixelMap=%{public}dx%{public}d', imgW, imgH);

    const visionInfo: textRecognition.VisionInfo = { pixelMap: pixelMap };
    const recogResult: textRecognition.TextRecognitionResult =
      await textRecognition.recognizeText(visionInfo, {
        isDirectionDetectionSupported: true
      });

    await textRecognition.release();

    const rawText: string = recogResult.value || '';
    hilog.info(DOMAIN, TAG, 'VisionKit rawText: "%{public}s"', rawText);

    const posResult: VisionKitGridResult | null = buildGridByPosition(recogResult, imgW, imgH);
    if (posResult && posResult.grid.some((d: number) => d > 0)) {
      const givenCount: number = posResult.grid.filter((d: number) => d > 0).length;
      let gridStr: string = '';
      for (let r: number = 0; r < 9; r++) {
        let line: string = '';
        for (let c: number = 0; c < 9; c++) {
          line += (posResult.grid[r * 9 + c] === 0 ? '.' : posResult.grid[r * 9 + c].toString()) + ' ';
        }
        gridStr += line + '\n';
      }
      hilog.info(DOMAIN, TAG, 'VisionKit positional OK, %{public}d digits:\n%{public}s', givenCount, gridStr);
      return { success: true, grid: posResult.grid, rawText: 'positional', error: '' };
    }

    const gridByText: number[] | null = parseOCRToGrid(rawText);
    if (gridByText && gridByText.some((d: number) => d > 0)) {
      hilog.info(DOMAIN, TAG, 'text fallback OK, raw="%{public}s"', rawText);
      return { success: true, grid: gridByText, rawText, error: '' };
    }

    const structuredText: string = extractStructuredText(recogResult);
    if (structuredText.length > rawText.length) {
      const grid2: number[] | null = parseOCRToGrid(structuredText);
      if (grid2 && grid2.some((d: number) => d > 0)) {
        hilog.info(DOMAIN, TAG, 'structured text fallback OK:\n%{public}s', structuredText);
        return { success: true, grid: grid2, rawText: structuredText, error: '' };
      }
    }

    return {
      success: false, grid: null, rawText,
      error: '识别文本中未检测到数独数字，请确保图片清晰、棋盘端正'
    };
  } catch (_e) {
    try { await textRecognition.release(); } catch (_ee) { /* ignore */ }
    return { success: false, grid: null, rawText: '', error: 'VisionKit unavailable' };
  } finally {
    if (pixelMap !== null) { pixelMap.release(); }
  }
}

function extractStructuredText(result: textRecognition.TextRecognitionResult): string {
  const parts: string[] = [];
  const blocks: Array<textRecognition.TextBlock> = result.blocks || [];
  for (let bi = 0; bi < blocks.length; bi++) {
    const lines: Array<textRecognition.TextLine> = blocks[bi].lines || [];
    for (let li = 0; li < lines.length; li++) {
      parts.push(lines[li].value);
    }
  }
  return parts.join('\n');
}

interface CellCandidate {
  digit: number;
  dist: number;
}

function buildGridByPosition(
  result: textRecognition.TextRecognitionResult,
  imgW: number, imgH: number
): VisionKitGridResult | null {
  const blocks: Array<textRecognition.TextBlock> = result.blocks || [];
  if (blocks.length === 0) { return null; }

  const rawDigits: RawDigit[] = [];

  for (let bi = 0; bi < blocks.length; bi++) {
    const lines: Array<textRecognition.TextLine> = blocks[bi].lines || [];
    for (let li = 0; li < lines.length; li++) {
      const line: textRecognition.TextLine = lines[li];
      const words: Array<textRecognition.TextWord> = line.words || [];
      for (let wi = 0; wi < words.length; wi++) {
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

        for (let ci = 0; ci < text.length; ci++) {
          const ch: string = text[ci];
          if (!new RegExp('^[0-9]$').test(ch)) { continue; }
          const charCx: number = topLeftX + charWidth * (ci + 0.5);
          rawDigits.push({ cx: charCx, cy: cy, digit: parseInt(ch, 10) });
        }
      }
    }
  }

  if (rawDigits.length === 0) { return null; }

  let minX: number = imgW;
  let maxX: number = 0;
  let minY: number = imgH;
  let maxY: number = 0;
  for (let i = 0; i < rawDigits.length; i++) {
    const d: RawDigit = rawDigits[i];
    if (d.cx < minX) { minX = d.cx; }
    if (d.cx > maxX) { maxX = d.cx; }
    if (d.cy < minY) { minY = d.cy; }
    if (d.cy > maxY) { maxY = d.cy; }
  }

  const padX: number = (maxX - minX) / 9 * 0.45;
  const padY: number = (maxY - minY) / 9 * 0.45;
  const boardL: number = Math.max(minX - padX, 0);
  const boardR: number = Math.min(maxX + padX, imgW);
  const boardT: number = Math.max(minY - padY, 0);
  const boardB: number = Math.min(maxY + padY, imgH);
  const boardW: number = boardR - boardL;
  const boardH: number = boardB - boardT;

  if (boardW <= 0 || boardH <= 0) { return null; }

  const cellW: number = boardW / 9;
  const cellH: number = boardH / 9;

  const candidates: CellCandidate[] = new Array<CellCandidate>(81);
  for (let i = 0; i < 81; i++) {
    candidates[i] = { digit: 0, dist: Number.MAX_VALUE };
  }

  for (let i = 0; i < rawDigits.length; i++) {
    const d: RawDigit = rawDigits[i];
    const normX: number = (d.cx - boardL) / boardW;
    const normY: number = (d.cy - boardT) / boardH;
    const gridCol: number = Math.min(Math.max(Math.floor(normX * 9), 0), 8);
    const gridRow: number = Math.min(Math.max(Math.floor(normY * 9), 0), 8);
    const idx: number = gridRow * 9 + gridCol;

    const cellCx: number = boardL + (gridCol + 0.5) * cellW;
    const cellCy: number = boardT + (gridRow + 0.5) * cellH;
    const dist: number = Math.sqrt((d.cx - cellCx) * (d.cx - cellCx) + (d.cy - cellCy) * (d.cy - cellCy));

    if (dist < candidates[idx].dist) {
      candidates[idx] = { digit: d.digit, dist: dist };
    }
  }

  const grid: number[] = new Array<number>(81).fill(0);
  for (let i = 0; i < 81; i++) {
    grid[i] = candidates[i].digit;
  }
  return { grid, boardL, boardT, boardW, boardH, imgW, imgH };
}

async function tryPixelGridRecognition(imagePath: string): Promise<OCRResult> {
  let pixelMap: image.PixelMap | null = null;
  try {
    const imageSource: image.ImageSource = openImageSource(imagePath);

    const srcInfo: image.ImageInfo = await imageSource.getImageInfo();
    const origW: number = srcInfo.size.width;
    const origH: number = srcInfo.size.height;

    const resize: AdaptiveResizeParams = computeAdaptiveResize(origW, origH);
    const targetW: number = resize.targetW;
    const targetH: number = resize.targetH;
    hilog.info(DOMAIN, TAG, '像素分析: 原图 %{public}dx%{public}d -> %{public}dx%{public}d', origW, origH, targetW, targetH);

    pixelMap = await imageSource.createPixelMap({
      desiredSize: { width: targetW, height: targetH },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    });
    imageSource.release();

    const imageInfo: image.ImageInfo = await pixelMap.getImageInfo();
    const width: number = imageInfo.size.width;
    const height: number = imageInfo.size.height;

    const grid: number[] = analyzePixelGrid(pixelMap, width, height);
    pixelMap.release();
    pixelMap = null;

    const givenCount: number = grid.filter((d: number) => d > 0).length;
    hilog.info(DOMAIN, TAG, '像素分析完成: 识别到 %{public}d 个数字', givenCount);
    if (givenCount > 0) {
      return { success: true, grid, rawText: 'pixel analysis', error: '' };
    }
    return {
      success: false, grid: null, rawText: '',
      error: '未能识别数独，请确保图片清晰或手动输入'
    };
  } catch (_err) {
    hilog.error(DOMAIN, TAG, '像素分析异常: %{public}s', `${_err}`);
    if (pixelMap !== null) { pixelMap.release(); }
    return { success: false, grid: null, rawText: '', error: '图片分析失败' };
  }
}

export function analyzePixelGridFromBuffer(pixels: Uint8Array, width: number, height: number): number[] {
  const grid: number[] = new Array<number>(81).fill(0);

  const bg: number = bgColor(pixels, width, height);
  const gray: Float32Array = toGrayArray(pixels, width, height);
  const isDark: boolean = bg < 128;

  const bbox: BoardBBox = findBoardBBox(pixels, width, height, bg);
  const cellW: number = (bbox.right - bbox.left) / 9;
  const cellH: number = (bbox.bottom - bbox.top) / 9;
  hilog.info(DOMAIN, TAG, '图像 %{public}dx%{public}d bg=%{public}.1f isDark=%{public}d 棋盘=[%{public}d,%{public}d,%{public}d,%{public}d] 尺寸=%{public}dx%{public}d 每格=%{public}.1fx%{public}.1f',
    width, height, bg, isDark ? 1 : 0, bbox.left, bbox.top, bbox.right, bbox.bottom,
    bbox.right - bbox.left, bbox.bottom - bbox.top, cellW, cellH);

  const corners: BoardCorners | null = detectBoardCorners(gray, width, height, isDark, bg);
  if (corners !== null) {
    const boardSize: number = Math.max(bbox.right - bbox.left, bbox.bottom - bbox.top);
    const outSize: number = Math.round(boardSize * 1.1);
    const warpedGray: Float32Array = warpPerspectiveGray(gray, width, height, corners, outSize, bg);
    const warpCellW: number = outSize / 9;
    const warpCellH: number = outSize / 9;
    let warpBgSum: number = 0;
    const warpSampleStep: number = Math.max(1, Math.floor(outSize * outSize / 20000));
    let warpBgCnt: number = 0;
    for (let i: number = 0; i < outSize * outSize; i += warpSampleStep) {
      warpBgSum += warpedGray[i];
      warpBgCnt++;
    }
    const warpBg: number = warpBgCnt > 0 ? warpBgSum / warpBgCnt : 128;
    const warpIsDark: boolean = warpBg < 128;
    hilog.info(DOMAIN, TAG, '透视校正: outSize=%{public}d confidence=%{public}.2f', outSize, corners.confidence);

    for (let r: number = 0; r < 9; r++) {
      for (let c: number = 0; c < 9; c++) {
        const sig: number[] | null = cellSigFromGray(
          warpedGray, outSize,
          c * warpCellW, r * warpCellH,
          warpCellW, warpCellH, warpIsDark, warpBg
        );
        if (sig !== null) {
          grid[r * 9 + c] = recognizeDigit(sig, countInk(sig));
        }
      }
    }
  } else {
    hilog.info(DOMAIN, TAG, '透视校正: 未能检测棋盘角点，使用原始AABB');

    for (let r: number = 0; r < 9; r++) {
      for (let c: number = 0; c < 9; c++) {
        const sig: number[] | null = cellSigFromGray(
          gray, width,
          bbox.left + c * cellW, bbox.top + r * cellH,
          cellW, cellH, bbox.isDark, bg
        );
        if (sig !== null) {
          grid[r * 9 + c] = recognizeDigit(sig, countInk(sig));
        }
      }
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
  hilog.info(DOMAIN, TAG, '像素分析结果:\n%{public}s', gridStr);

  return grid;
}

function analyzePixelGrid(pixelMap: image.PixelMap, width: number, height: number): number[] {
  try {
    const buffer: ArrayBuffer = new ArrayBuffer(width * height * 4);
    pixelMap.readPixelsToBuffer(buffer);
    const pixels: Uint8Array = new Uint8Array(buffer);
    return analyzePixelGridFromBuffer(pixels, width, height);
  } catch (_e) {
    return new Array<number>(81).fill(0);
  }
}
