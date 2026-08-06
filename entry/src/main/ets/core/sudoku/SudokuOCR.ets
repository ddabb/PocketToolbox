import { image } from '@kit.ImageKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { fileIo } from '@kit.CoreFileKit';
import { parseOCRToGrid } from './SudokuEngine';
import { BoardBBox, bgColor, cellSig, cellSigFromGray, countInk, findBoardBBox, recognizeDigit, toGrayArray } from './SudokuPixel';

export interface OCRResult {
  success: boolean;
  grid: number[] | null;
  rawText: string;
  error: string;
}

interface RawDigit {
  cx: number;
  cy: number;
  digit: number;
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
    console.info(`[SudokuOCR] === 开始识别 === path=${imagePath}`);
    const visionResult: OCRResult = await tryVisionKitRecognition(imagePath);
    console.info(`[SudokuOCR] VisionKit: success=${visionResult.success} error=${visionResult.error}`);
    if (visionResult.success && visionResult.grid) {
      console.info(`[SudokuOCR] 采用 VisionKit 结果`);
      return visionResult;
    }
    console.info(`[SudokuOCR] VisionKit 失败，转像素分析`);
    return await tryPixelGridRecognition(imagePath);
  } catch (_err) {
    console.error(`[SudokuOCR] 异常: ${_err}`);
    return { success: false, grid: null, rawText: '', error: '图片处理异常，请尝试手动输入' };
  }
}

async function tryVisionKitRecognition(imagePath: string): Promise<OCRResult> {
  let pixelMap: image.PixelMap | null = null;
  try {
    const initOk: boolean = await textRecognition.init();
    if (!initOk) {
      return { success: false, grid: null, rawText: '', error: 'VisionKit init failed' };
    }

    const imageSource: image.ImageSource = openImageSource(imagePath);
    pixelMap = await imageSource.createPixelMap({
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    });
    imageSource.release();

    const imageInfo: image.ImageInfo = await pixelMap.getImageInfo();
    const imgW: number = imageInfo.size.width;
    const imgH: number = imageInfo.size.height;

    const visionInfo: textRecognition.VisionInfo = { pixelMap: pixelMap };
    const recogResult: textRecognition.TextRecognitionResult =
      await textRecognition.recognizeText(visionInfo, {
        isDirectionDetectionSupported: false
      });

    await textRecognition.release();

    const rawText: string = recogResult.value || '';
    console.info(`[SudokuOCR] VisionKit rawText: "${rawText}"`);

    const gridByPos: number[] | null = buildGridByPosition(recogResult, imgW, imgH);
    if (gridByPos && gridByPos.some((d: number) => d > 0)) {
      const givenCount: number = gridByPos.filter((d: number) => d > 0).length;
      let gridStr: string = '';
      for (let r: number = 0; r < 9; r++) {
        let line: string = '';
        for (let c: number = 0; c < 9; c++) {
          line += (gridByPos[r * 9 + c] === 0 ? '.' : gridByPos[r * 9 + c].toString()) + ' ';
        }
        gridStr += line + '\n';
      }
      console.info(`[SudokuOCR] VisionKit positional OK, ${givenCount} digits:\n${gridStr}`);
      return { success: true, grid: gridByPos, rawText: 'positional', error: '' };
    }

    const gridByText: number[] | null = parseOCRToGrid(rawText);
    if (gridByText && gridByText.some((d: number) => d > 0)) {
      console.info(`[SudokuOCR] text fallback OK, raw="${rawText}"`);
      return { success: true, grid: gridByText, rawText, error: '' };
    }

    const structuredText: string = extractStructuredText(recogResult);
    if (structuredText.length > rawText.length) {
      const grid2: number[] | null = parseOCRToGrid(structuredText);
      if (grid2 && grid2.some((d: number) => d > 0)) {
        console.info(`[SudokuOCR] structured text fallback OK:\n${structuredText}`);
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

function buildGridByPosition(
  result: textRecognition.TextRecognitionResult,
  imgW: number, imgH: number
): number[] | null {
  const grid: number[] = new Array<number>(81).fill(0);
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

  for (let i = 0; i < rawDigits.length; i++) {
    const d: RawDigit = rawDigits[i];
    const normX: number = (d.cx - boardL) / boardW;
    const normY: number = (d.cy - boardT) / boardH;
    const gridCol: number = Math.min(Math.max(Math.floor(normX * 9), 0), 8);
    const gridRow: number = Math.min(Math.max(Math.floor(normY * 9), 0), 8);
    grid[gridRow * 9 + gridCol] = d.digit;
  }
  return grid;
}

async function tryPixelGridRecognition(imagePath: string): Promise<OCRResult> {
  let pixelMap: image.PixelMap | null = null;
  try {
    const imageSource: image.ImageSource = openImageSource(imagePath);

    const srcInfo: image.ImageInfo = await imageSource.getImageInfo();
    const origW: number = srcInfo.size.width;
    const origH: number = srcInfo.size.height;

    const maxDim: number = 1280;
    let targetW: number = origW;
    let targetH: number = origH;
    if (origW > maxDim || origH > maxDim) {
      const scale: number = maxDim / Math.max(origW, origH);
      targetW = Math.round(origW * scale);
      targetH = Math.round(origH * scale);
    }
    console.info(`[SudokuOCR] 像素分析: 原图 ${origW}x${origH} -> ${targetW}x${targetH}`);

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
    console.info(`[SudokuOCR] 像素分析完成: 识别到 ${givenCount} 个数字`);
    if (givenCount > 0) {
      return { success: true, grid, rawText: 'pixel analysis', error: '' };
    }
    return {
      success: false, grid: null, rawText: '',
      error: '未能识别数独，请确保图片清晰或手动输入'
    };
  } catch (_err) {
    console.error(`[SudokuOCR] 像素分析异常: ${_err}`);
    if (pixelMap !== null) { pixelMap.release(); }
    return { success: false, grid: null, rawText: '', error: '图片分析失败' };
  }
}

export function analyzePixelGridFromBuffer(pixels: Uint8Array, width: number, height: number): number[] {
  const grid: number[] = new Array<number>(81).fill(0);

  const bg: number = bgColor(pixels, width, height);
  const gray: Float32Array = toGrayArray(pixels, width, height);

  const bbox: BoardBBox = findBoardBBox(pixels, width, height, bg);
  const cellW: number = (bbox.right - bbox.left) / 9;
  const cellH: number = (bbox.bottom - bbox.top) / 9;
  console.info(`[SudokuOCR] 图像 ${width}x${height} bg=${bg.toFixed(1)} isDark=${bbox.isDark} 棋盘=[${bbox.left},${bbox.top},${bbox.right},${bbox.bottom}] 尺寸=${(bbox.right-bbox.left)}x${(bbox.bottom-bbox.top)} 每格=${cellW.toFixed(1)}x${cellH.toFixed(1)}`);

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

  let gridStr: string = '[SudokuOCR] 像素分析结果:\n';
  for (let r: number = 0; r < 9; r++) {
    let line: string = '  ';
    for (let c: number = 0; c < 9; c++) {
      line += (grid[r * 9 + c] === 0 ? '.' : grid[r * 9 + c].toString()) + ' ';
    }
    gridStr += line + '\n';
  }
  console.info(gridStr);

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


