import { image } from '@kit.ImageKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { parseOCRToGrid } from './SudokuEngine';
import { BoardBBox, cellSig, countInk, findBoardBBox, recognizeDigit } from './SudokuPixel';

export interface OCRResult {
  success: boolean;
  grid: number[] | null;
  rawText: string;
  error: string;
}

interface DigitPosition {
  row: number;
  col: number;
  digit: number;
}

export async function recognizeSudokuFromImage(imagePath: string): Promise<OCRResult> {
  try {
    const visionResult: OCRResult = await tryVisionKitRecognition(imagePath);
    if (visionResult.success && visionResult.grid) {
      return visionResult;
    }
    return await tryPixelGridRecognition(imagePath);
  } catch (_err) {
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

    const imageSource: image.ImageSource = image.createImageSource(imagePath);
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
    const gridByText: number[] | null = parseOCRToGrid(rawText);
    if (gridByText && gridByText.some((d: number) => d > 0)) {
      return { success: true, grid: gridByText, rawText, error: '' };
    }

    const structuredText: string = extractStructuredText(recogResult);
    if (structuredText.length > rawText.length) {
      const grid2: number[] | null = parseOCRToGrid(structuredText);
      if (grid2 && grid2.some((d: number) => d > 0)) {
        return { success: true, grid: grid2, rawText: structuredText, error: '' };
      }
    }

    const gridByPos: number[] | null = buildGridByPosition(recogResult, imgW, imgH);
    if (gridByPos && gridByPos.some((d: number) => d > 0)) {
      return { success: true, grid: gridByPos, rawText: 'positional', error: '' };
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

  const digits: DigitPosition[] = [];

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
          const gridCol: number = Math.min(Math.max(Math.floor(charCx / imgW * 9), 0), 8);
          const gridRow: number = Math.min(Math.max(Math.floor(cy / imgH * 9), 0), 8);
          digits.push({ row: gridRow, col: gridCol, digit: parseInt(ch, 10) });
        }
      }
    }
  }

  for (let di = 0; di < digits.length; di++) {
    const d: DigitPosition = digits[di];
    grid[d.row * 9 + d.col] = d.digit;
  }
  return grid;
}

async function tryPixelGridRecognition(imagePath: string): Promise<OCRResult> {
  let pixelMap: image.PixelMap | null = null;
  try {
    const imageSource: image.ImageSource = image.createImageSource(imagePath);
    pixelMap = await imageSource.createPixelMap({
      desiredSize: { width: 450, height: 450 },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    });
    imageSource.release();

    const imageInfo: image.ImageInfo = await pixelMap.getImageInfo();
    const width: number = imageInfo.size.width;
    const height: number = imageInfo.size.height;

    const grid: number[] = analyzePixelGrid(pixelMap, width, height);
    pixelMap.release();
    pixelMap = null;

    if (grid.some((d: number) => d > 0)) {
      return { success: true, grid, rawText: 'pixel analysis', error: '' };
    }
    return {
      success: false, grid: null, rawText: '',
      error: '未能识别数独，请确保图片清晰或手动输入'
    };
  } catch (_err) {
    if (pixelMap !== null) { pixelMap.release(); }
    return { success: false, grid: null, rawText: '', error: '图片分析失败' };
  }
}

export function analyzePixelGridFromBuffer(pixels: Uint8Array, width: number, height: number): number[] {
  const grid: number[] = new Array<number>(81).fill(0);

  const margin: number = Math.max(2, Math.floor(Math.min(width, height) * 0.05));
  let bgSum: number = 0;
  let bgCnt: number = 0;
  for (let y: number = 0; y < margin; y += 2) {
    for (let x: number = 0; x < margin; x += 2) {
      bgSum += 0.299 * pixels[(y * width + x) * 4] +
        0.587 * pixels[(y * width + x) * 4 + 1] +
        0.114 * pixels[(y * width + x) * 4 + 2];
      bgCnt++;
    }
    for (let x: number = width - margin; x < width; x += 2) {
      bgSum += 0.299 * pixels[(y * width + x) * 4] +
        0.587 * pixels[(y * width + x) * 4 + 1] +
        0.114 * pixels[(y * width + x) * 4 + 2];
      bgCnt++;
    }
  }
  const bg: number = bgCnt > 0 ? bgSum / bgCnt : 200;

  const bbox: BoardBBox = findBoardBBox(pixels, width, height, bg);
  const cellW: number = (bbox.right - bbox.left) / 9;
  const cellH: number = (bbox.bottom - bbox.top) / 9;

  for (let r: number = 0; r < 9; r++) {
    for (let c: number = 0; c < 9; c++) {
      const sig: number[] | null = cellSig(
        pixels, width,
        bbox.left + c * cellW, bbox.top + r * cellH,
        cellW, cellH, bbox.isDark, bg
      );
      if (sig !== null) {
        grid[r * 9 + c] = recognizeDigit(sig, countInk(sig));
      }
    }
  }

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


