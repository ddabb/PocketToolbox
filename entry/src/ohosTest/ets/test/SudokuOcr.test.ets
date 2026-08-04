import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { recognizeSudokuFromImage, OCRResult } from '../../../main/ets/core/sudoku/SudokuOCR';
import { parseOCRToGrid, gridToString, solveSudoku, validateFullGrid, SolveResult } from '../../../main/ets/core/sudoku/SudokuEngine';

interface TestImage {
  filename: string;
  label: string;
}

const TEST_IMAGES: TestImage[] = [
  { filename: '01_standard_544.png', label: 'standard 544' },
  { filename: '02_small_300.png', label: 'small 300' },
  { filename: '03_large_800.png', label: 'large 800' },
  { filename: '04_blue_numbers.png', label: 'blue numbers' },
  { filename: '05_red_theme.png', label: 'red theme' },
  { filename: '06_green_theme.png', label: 'green theme' },
  { filename: '07_light_gray_numbers.png', label: 'light gray numbers' },
  { filename: '08_gray_bg_dark_numbers.png', label: 'gray bg dark numbers' },
  { filename: '09_serif_font.png', label: 'serif font' },
  { filename: '10_italic_font.png', label: 'italic font' },
  { filename: '11_thin_font.png', label: 'thin font' },
  { filename: '12_all_thin_lines.png', label: 'all thin lines' },
  { filename: '13_no_outer_border.png', label: 'no outer border' },
  { filename: '14_tiny_200.png', label: 'tiny 200' },
  { filename: '15_huge_1000.png', label: 'huge 1000' },
];

const EXPECTED_GIVENS: number[] = [
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

async function copyRawfileToCache(context: common.Context, filename: string): Promise<string> {
  const bytes: Uint8Array = await context.resourceManager.getRawFileContent(filename);
  const filePath: string = context.cacheDir + '/' + filename;
  const file = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  fileIo.writeSync(file.fd, bytes.buffer as ArrayBuffer);
  fileIo.closeSync(file);
  return filePath;
}

function countGivenMatches(grid: number[], expected: number[]): number {
  let matches: number = 0;
  let total: number = 0;
  for (let i: number = 0; i < 81; i++) {
    if (expected[i] !== 0) {
      total++;
      if (grid[i] === expected[i]) {
        matches++;
      }
    }
  }
  return matches;
}

export default function sudokuOcrTest() {
  describe('SudokuOCR_recognize_all_images', () => {
    for (let idx: number = 0; idx < TEST_IMAGES.length; idx++) {
      const img: TestImage = TEST_IMAGES[idx];
      it(`recognize_${img.label}`, 0, async () => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator();
        const context = delegator.getAppContext() as common.Context;

        const filePath: string = await copyRawfileToCache(context, img.filename);
        const result: OCRResult = await recognizeSudokuFromImage(filePath);

        expect(result.success).assertTrue();
        expect(result.grid).assertInstanceOf('Array');
        const grid: number[] = result.grid as number[];
        expect(grid.length).assertEqual(81);

        const matches: number = countGivenMatches(grid, EXPECTED_GIVENS);
        const givenCount: number = EXPECTED_GIVENS.filter((v: number) => v !== 0).length;
        const accuracy: number = matches / givenCount;
        expect(accuracy >= 0.7).assertTrue();
      });
    }
  });

  describe('SudokuOCR_pipeline_solve', () => {
    it('parse_and_solve_from_expected_givens', 0, () => {
      const s: string = gridToString(EXPECTED_GIVENS);
      const grid: number[] = parseOCRToGrid(s)!;
      expect(grid.length).assertEqual(81);
      const solved: SolveResult = solveSudoku(grid);
      expect(solved.success).assertTrue();
      expect(validateFullGrid(solved.solution)).assertTrue();
    });
  });
}
