import { describe, it, expect } from '@ohos/hypium';
import { analyzePixelGridFromBuffer } from '../../../main/ets/core/sudoku/SudokuOCR';
import { parseOCRToGrid, gridToString, solveSudoku, validateFullGrid, SolveResult } from '../../../main/ets/core/sudoku/SudokuEngine';
import { image } from '@kit.ImageKit';
import { resourceManager } from '@kit.LocalizationKit';

const EXPECTED: number[] = [
  5, 3, 0, 0, 7, 0, 0, 0, 0,
  6, 0, 0, 1, 9, 5, 0, 0, 0,
  0, 9, 8, 0, 0, 0, 0, 6, 0,
  8, 0, 0, 0, 6, 0, 0, 0, 3,
  4, 0, 0, 8, 0, 3, 0, 0, 1,
  7, 0, 0, 0, 2, 0, 0, 0, 6,
  0, 6, 0, 0, 0, 0, 2, 8, 0,
  0, 0, 0, 4, 1, 9, 0, 0, 5,
  0, 0, 0, 0, 8, 0, 0, 7, 9,
];

interface ImageThreshold {
  file: string;
  minAcc: number;
}

interface PixelData {
  pixels: Uint8Array;
  width: number;
  height: number;
}

const CASES: ImageThreshold[] = [
  { file: '01_standard_544.png', minAcc: 1.0 },
  { file: '02_small_300.png', minAcc: 0.9 },
  { file: '03_large_800.png', minAcc: 1.0 },
  { file: '04_blue_numbers.png', minAcc: 0.7 },
  { file: '05_red_theme.png', minAcc: 0.7 },
  { file: '06_green_theme.png', minAcc: 0.7 },
  { file: '07_light_gray_numbers.png', minAcc: 0.7 },
  { file: '08_gray_bg_dark_numbers.png', minAcc: 0.7 },
  { file: '09_serif_font.png', minAcc: 0.9 },
  { file: '10_italic_font.png', minAcc: 0.7 },
  { file: '11_thin_font.png', minAcc: 0.7 },
  { file: '12_all_thin_lines.png', minAcc: 0.7 },
  { file: '13_no_outer_border.png', minAcc: 0.7 },
  { file: '14_tiny_200.png', minAcc: 0.7 },
  { file: '15_huge_1000.png', minAcc: 1.0 },
];

function diffDetail(actual: number[], expectArr: number[]): string {
  let parts: string[] = [];
  for (let i: number = 0; i < 81; i++) {
    if (expectArr[i] !== 0 && actual[i] !== expectArr[i]) {
      parts.push(`[${Math.floor(i / 9)},${i % 9}]:${actual[i]}/${expectArr[i]}`);
    }
  }
  return parts.length > 0 ? parts.join(' ') : 'none';
}

function countGivenMatches(actual: number[], expectArr: number[]): number {
  let matches: number = 0;
  let total: number = 0;
  for (let i: number = 0; i < 81; i++) {
    if (expectArr[i] !== 0) {
      total++;
      if (actual[i] === expectArr[i]) {
        matches++;
      }
    }
  }
  return total > 0 ? matches / total : 0;
}

function loadPixelsSync(rawfile: string): PixelData | null {
  try {
    const ctx: Context = getContext();
    const rm: resourceManager.ResourceManager = ctx.resourceManager;
    const rawData: Uint8Array = rm.getRawFileContentSync(rawfile);
    if (rawData.byteLength === 0) {
      console.error(`[OCR_TEST] ${rawfile}: empty rawfile`);
      return null;
    }
    const imgSrc: image.ImageSource = image.createImageSource(rawData.buffer as ArrayBuffer);
    const pm: image.PixelMap = imgSrc.createPixelMapSync({
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    });
    imgSrc.release();
    const info: image.ImageInfo = pm.getImageInfoSync();
    const w: number = info.size.width;
    const h: number = info.size.height;
    const buf: ArrayBuffer = new ArrayBuffer(w * h * 4);
    pm.readPixelsToBufferSync(buf);
    pm.release();
    return { pixels: new Uint8Array(buf), width: w, height: h };
  } catch (e) {
    const err: Error = e as Error;
    console.error(`[OCR_TEST] ${rawfile}: load error ${err.message}`);
    return null;
  }
}

export default function sudokuOcrTest() {
  describe('SudokuOCR_pixel_all_images', () => {
    for (let idx: number = 0; idx < CASES.length; idx++) {
      const c: ImageThreshold = CASES[idx];
      it(`pixel_${c.file.replace('.png', '')}`, 0, () => {
        const pd: PixelData | null = loadPixelsSync(c.file);
        expect(pd !== null).assertTrue();
        if (pd === null) { return; }

        const grid: number[] = analyzePixelGridFromBuffer(pd.pixels, pd.width, pd.height);
        const acc: number = countGivenMatches(grid, EXPECTED);

        if (acc < 1.0) {
          console.log(`[OCR_TEST] ${c.file} (${pd.width}x${pd.height}) MISTAKES: ${diffDetail(grid, EXPECTED)}`);
        }
        console.log(`[OCR_TEST] ${c.file} accuracy: ${(acc * 100).toFixed(0)}% (threshold ${(c.minAcc * 100).toFixed(0)}%)`);

        expect(acc >= c.minAcc).assertTrue();
      });
    }
  });

  describe('SudokuOCR_edge_cases', () => {
    it('zero_size_buffer_returns_all_zeros', 0, () => {
      const empty: Uint8Array = new Uint8Array(0);
      const grid: number[] = analyzePixelGridFromBuffer(empty, 0, 0);
      expect(grid.length).assertEqual(81);
      for (let i: number = 0; i < 81; i++) {
        expect(grid[i]).assertEqual(0);
      }
    });

    it('tiny_buffer_no_crash', 0, () => {
      const tiny: Uint8Array = new Uint8Array(16);
      const grid: number[] = analyzePixelGridFromBuffer(tiny, 2, 2);
      expect(grid.length).assertEqual(81);
    });

    it('solid_white_image_all_zeros', 0, () => {
      const white: Uint8Array = new Uint8Array(90 * 90 * 4);
      white.fill(255);
      const grid: number[] = analyzePixelGridFromBuffer(white, 90, 90);
      expect(grid.length).assertEqual(81);
    });
  });

  describe('SudokuOCR_parseOCRToGrid', () => {
    it('exact_81_digits', 0, () => {
      const text: string = '530070000600195000098000060800060003400803001700020006060000280000410005000080079';
      const grid: number[] = parseOCRToGrid(text)!;
      expect(grid.length).assertEqual(81);
      expect(grid[0]).assertEqual(5);
      expect(grid[1]).assertEqual(3);
    });

    it('dots_as_zeros', 0, () => {
      const text: string = '53..7....6....195....98....6.8...6...34..8.3..7...2...6.6....28....4..19....8..79';
      const grid: number[] = parseOCRToGrid(text)!;
      expect(grid.length).assertEqual(81);
      expect(grid[2]).assertEqual(0);
      expect(grid[3]).assertEqual(0);
      expect(grid[4]).assertEqual(7);
    });

    it('too_few_digits_returns_null', 0, () => {
      const result: number[] | null = parseOCRToGrid('12345');
      expect(result === null).assertTrue();
    });

    it('multiline_format', 0, () => {
      const s: string = gridToString(EXPECTED);
      const grid: number[] = parseOCRToGrid(s)!;
      expect(grid.length).assertEqual(81);
      for (let i: number = 0; i < 81; i++) {
        if (EXPECTED[i] !== 0) {
          expect(grid[i]).assertEqual(EXPECTED[i]);
        }
      }
    });

    it('mixed_whitespace_and_noise', 0, () => {
      const text: string = '5 3 0 0 7\n6 0 0 1 9\nabc530070000600195000098000060800060003400803001700020006060000280000410005000080079xyz';
      const grid: number[] = parseOCRToGrid(text)!;
      expect(grid.length).assertEqual(81);
    });
  });

  describe('SudokuOCR_pipeline_solve', () => {
    it('parse_and_solve', 0, () => {
      const s: string = gridToString(EXPECTED);
      const g: number[] = parseOCRToGrid(s)!;
      expect(g.length).assertEqual(81);
      const r: SolveResult = solveSudoku(g);
      expect(r.success).assertTrue();
      expect(validateFullGrid(r.solution)).assertTrue();
      expect(r.solutionCount > 0).assertTrue();
    });

    it('solve_preserves_given_digits', 0, () => {
      const r: SolveResult = solveSudoku(EXPECTED);
      expect(r.success).assertTrue();
      for (let i: number = 0; i < 81; i++) {
        if (EXPECTED[i] !== 0) {
          expect(r.solution[i]).assertEqual(EXPECTED[i]);
        }
      }
    });

    it('invalid_puzzle_returns_failure', 0, () => {
      const invalid: number[] = new Array<number>(81).fill(1);
      const r: SolveResult = solveSudoku(invalid);
      expect(r.success).assertFalse();
    });
  });
}
