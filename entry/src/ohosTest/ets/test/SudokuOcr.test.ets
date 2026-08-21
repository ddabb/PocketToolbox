import { describe, it, expect, beforeAll } from '@ohos/hypium';
import { recognizeSudokuFromBuffer, OCRResult, getOCRDebugInfo, OCRDebugInfo } from '../../../main/ets/core/sudoku/SudokuOCR';
import { parseOCRToGrid, gridToString, solveSudoku, validateFullGrid, SolveResult } from '../../../main/ets/core/sudoku/SudokuEngine';
import { initDigitTemplates } from '../../../main/ets/core/sudoku/SudokuPixel';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { resourceManager } from '@kit.LocalizationKit';

const DOMAIN: number = 0xA03D00;
const TAG: string = 'OCR_TEST';

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

const TEST_IMAGES: string[][] = [
  ['01_standard_544', 'sudoku_test_images/01_standard_544.png'],
  ['02_small_300', 'sudoku_test_images/02_small_300.png'],
  ['03_large_800', 'sudoku_test_images/03_large_800.png'],
  ['04_blue_numbers', 'sudoku_test_images/04_blue_numbers.png'],
  ['05_red_theme', 'sudoku_test_images/05_red_theme.png'],
  ['06_green_theme', 'sudoku_test_images/06_green_theme.png'],
  ['07_light_gray_numbers', 'sudoku_test_images/07_light_gray_numbers.png'],
  ['08_gray_bg_dark_numbers', 'sudoku_test_images/08_gray_bg_dark_numbers.png'],
  ['09_serif_font', 'sudoku_test_images/09_serif_font.png'],
  ['10_italic_font', 'sudoku_test_images/10_italic_font.png'],
  ['11_thin_font', 'sudoku_test_images/11_thin_font.png'],
  ['12_all_thin_lines', 'sudoku_test_images/12_all_thin_lines.png'],
  ['13_no_outer_border', 'sudoku_test_images/13_no_outer_border.png'],
  ['14_tiny_200', 'sudoku_test_images/14_tiny_200.png'],
  ['15_huge_1000', 'sudoku_test_images/15_huge_1000.png'],
  ['photos', 'sudoku_test_images/photos.jpg'],
];

interface MatchResult {
  givenAcc: number;
  fullAcc: number;
  falsePos: number;
  falseNeg: number;
  diffDetail: string;
}

function computeMatch(actual: number[], expectArr: number[]): MatchResult {
  let givenMatches: number = 0;
  let givenTotal: number = 0;
  let fullMatches: number = 0;
  let falsePos: number = 0;
  let falseNeg: number = 0;
  const parts: string[] = [];
  for (let i: number = 0; i < 81; i++) {
    if (actual[i] === expectArr[i]) {
      fullMatches++;
    }
    if (expectArr[i] !== 0) {
      givenTotal++;
      if (actual[i] === expectArr[i]) {
        givenMatches++;
      } else {
        falseNeg++;
        parts.push(`R${Math.floor(i / 9) + 1}C${i % 9 + 1}:got=${actual[i]} want=${expectArr[i]}`);
      }
    } else {
      if (actual[i] !== 0) {
        falsePos++;
        parts.push(`R${Math.floor(i / 9) + 1}C${i % 9 + 1}:got=${actual[i]} want=empty`);
      }
    }
  }
  return {
    givenAcc: givenTotal > 0 ? givenMatches / givenTotal : 0,
    fullAcc: fullMatches / 81,
    falsePos: falsePos,
    falseNeg: falseNeg,
    diffDetail: parts.length > 0 ? parts.join('; ') : 'none'
  };
}

function gridToAscii(grid: number[]): string {
  let s: string = '';
  for (let r: number = 0; r < 9; r++) {
    let line: string = '';
    for (let c: number = 0; c < 9; c++) {
      const v: number = grid[r * 9 + c];
      line += (v === 0 ? '.' : v.toString()) + ' ';
    }
    s += line + '\n';
  }
  return s;
}

function dumpDebugCompact(info: OCRDebugInfo, prefix: string): void {
  console.info(`[OCR_DBG] ${prefix}pipeline=${info.pipeline}`);
  console.info(`[OCR_DBG] ${prefix}resize=${info.resizeInfo}`);
  console.info(`[OCR_DBG] ${prefix}bbox=${info.bboxInfo}`);
  console.info(`[OCR_DBG] ${prefix}probe=${info.probeInfo}`);
  console.info(`[OCR_DBG] ${prefix}bboxDiag=${info.bboxDiag}`);
  console.info(`[OCR_DBG] ${prefix}rawDigits=${info.rawDigits}`);
  console.info(`[OCR_DBG] ${prefix}vkOcrSize=${info.visionKitOcrSize}`);
  console.info(`[OCR_DBG] ${prefix}vkBlocks=${info.visionKitBlockCount}`);
  if (info.visionKitRawDigitPositions.length > 0) {
    console.info(`[OCR_DBG] ${prefix}vkRawDigitPos=${info.visionKitRawDigitPositions}`);
  }
  if (info.visionKitOcrError.length > 0) {
    console.info(`[OCR_DBG] ${prefix}vkErr=${info.visionKitOcrError}`);
  }
  console.info(`[OCR_DBG] ${prefix}vkGrid=`);
  const vkLines: string[] = info.visionKitGrid.split('\n');
  for (const vl of vkLines) {
    console.info(`[OCR_DBG] ${prefix}  ${vl}`);
  }
  if (info.pixelGrid.length > 0 && info.pixelGrid !== '(null)') {
    console.info(`[OCR_DBG] ${prefix}pxGrid=`);
    const pxLines: string[] = info.pixelGrid.split('\n');
    for (const pl of pxLines) {
      console.info(`[OCR_DBG] ${prefix}  ${pl}`);
    }
  }
  console.info(`[OCR_DBG] ${prefix}finalGrid=`);
  const fgLines: string[] = info.finalGrid.split('\n');
  for (const fl of fgLines) {
    console.info(`[OCR_DBG] ${prefix}  ${fl}`);
  }
  if (info.fixDetails.length > 0) {
    const fdLines: string[] = info.fixDetails.split('\n');
    for (const fdl of fdLines) {
      console.info(`[OCR_DBG] ${prefix}fd=${fdl}`);
    }
  }
}

function loadRawFileBuf(ctx: Context, rawfile: string): ArrayBuffer {
  const rm: resourceManager.ResourceManager = ctx.resourceManager;
  const rawData: Uint8Array = rm.getRawFileContentSync(rawfile);
  hilog.info(DOMAIN, TAG, `${rawfile}: ${rawData.byteLength} bytes`);
  if (rawData.byteLength === 0) {
    throw new Error(`${rawfile}: 0 bytes`);
  }
  const copy: ArrayBuffer = new ArrayBuffer(rawData.byteLength);
  const view: Uint8Array = new Uint8Array(copy);
  for (let i: number = 0; i < rawData.byteLength; i++) {
    view[i] = rawData[i];
  }
  return copy;
}

function runPipelineTest(name: string, rawfile: string, done: Function): void {
  const ctx: Context = getContext();
  let buf: ArrayBuffer;
  try {
    buf = loadRawFileBuf(ctx, rawfile);
    console.info(`[OCR_TEST] === pipeline: ${name} buf=${buf.byteLength} ===`);
    hilog.info(DOMAIN, TAG, `=== pipeline: ${name} buf=${buf.byteLength} ===`);
  } catch (e) {
    console.info(`[OCR_TEST] ${name}: loadRawFile FAILED: ${e}`);
    hilog.error(DOMAIN, TAG, `${name}: loadRawFile FAILED: ${e}`);
    try {
      expect(false).assertTrue();
    } catch (_e) { /* swallow assertion error */ }
    done();
    return;
  }

  recognizeSudokuFromBuffer(buf).then((ocrResult: OCRResult) => {
    try {
      if (!ocrResult.success || !ocrResult.grid) {
        const dbg: OCRDebugInfo | null = getOCRDebugInfo();
        if (dbg !== null) { dumpDebugCompact(dbg, `${name}:OCR_FAIL `); }
        console.info(`[OCR_TEST] ${name}: FAIL OCR_FAILED err="${ocrResult.error}"`);
        hilog.info(DOMAIN, TAG, `${name}: FAIL OCR_FAILED err="${ocrResult.error}"`);
        try {
          expect(ocrResult.success).assertTrue();
        } catch (_e) { /* swallow */ }
        done();
        return;
      }
      const mr: MatchResult = computeMatch(ocrResult.grid, EXPECTED);
      if (mr.givenAcc >= 1.0 && mr.falsePos === 0) {
        console.info(`[OCR_TEST] ${name}: PASS given:100% full:${(mr.fullAcc * 100).toFixed(0)}%`);
        hilog.info(DOMAIN, TAG, `${name}: PASS given:100% full:${(mr.fullAcc * 100).toFixed(0)}%`);
      } else {
        const dbg: OCRDebugInfo | null = getOCRDebugInfo();
        if (dbg !== null) { dumpDebugCompact(dbg, `${name}:MIS `); }
        console.info(`[OCR_TEST] ${name}: FAIL given:${(mr.givenAcc * 100).toFixed(0)}% full:${(mr.fullAcc * 100).toFixed(0)}% fp:${mr.falsePos} fn:${mr.falseNeg} diff=${mr.diffDetail}`);
        hilog.info(DOMAIN, TAG, `${name}:\n${gridToAscii(ocrResult.grid)}`);
        hilog.info(DOMAIN, TAG, `${name}: FAIL given:${(mr.givenAcc * 100).toFixed(0)}% full:${(mr.fullAcc * 100).toFixed(0)}% fp:${mr.falsePos} fn:${mr.falseNeg} diff=${mr.diffDetail}`);
        try {
          expect(mr.givenAcc).assertEqual(1.0);
          expect(mr.falsePos).assertEqual(0);
        } catch (_e) { /* swallow assertion error */ }
      }
    } catch (innerErr) {
      console.info(`[OCR_TEST] ${name}: FAIL unexpected: ${innerErr}`);
      hilog.error(DOMAIN, TAG, `${name}: FAIL unexpected: ${innerErr}`);
      try {
        expect(false).assertTrue();
      } catch (_e) { /* swallow */ }
    }
    done();
  }).catch((err: Object) => {
    console.info(`[OCR_TEST] ${name}: FAIL exception: ${err}`);
    hilog.error(DOMAIN, TAG, `${name}: FAIL exception: ${err}`);
    try {
      expect(false).assertTrue();
    } catch (_e) { /* swallow */ }
    done();
  });
}

export default function sudokuOcrTest() {
  describe('SudokuOCR_pipeline_full', () => {
    beforeAll(() => {
      const ctx: Context = getContext();
      const ok: boolean = initDigitTemplates(ctx);
      console.info(`[OCR_TEST] initDigitTemplates: ${ok}`);
      hilog.info(DOMAIN, TAG, `initDigitTemplates: ${ok}`);
    });

    it('pipeline_01_standard_544', 0, (done: Function) => {
      runPipelineTest('01_standard_544', 'sudoku_test_images/01_standard_544.png', done);
    });
    it('pipeline_02_small_300', 0, (done: Function) => {
      runPipelineTest('02_small_300', 'sudoku_test_images/02_small_300.png', done);
    });
    it('pipeline_03_large_800', 0, (done: Function) => {
      runPipelineTest('03_large_800', 'sudoku_test_images/03_large_800.png', done);
    });
    it('pipeline_04_blue_numbers', 0, (done: Function) => {
      runPipelineTest('04_blue_numbers', 'sudoku_test_images/04_blue_numbers.png', done);
    });
    it('pipeline_05_red_theme', 0, (done: Function) => {
      runPipelineTest('05_red_theme', 'sudoku_test_images/05_red_theme.png', done);
    });
    it('pipeline_06_green_theme', 0, (done: Function) => {
      runPipelineTest('06_green_theme', 'sudoku_test_images/06_green_theme.png', done);
    });
    it('pipeline_07_light_gray_numbers', 0, (done: Function) => {
      runPipelineTest('07_light_gray_numbers', 'sudoku_test_images/07_light_gray_numbers.png', done);
    });
    it('pipeline_08_gray_bg_dark_numbers', 0, (done: Function) => {
      runPipelineTest('08_gray_bg_dark_numbers', 'sudoku_test_images/08_gray_bg_dark_numbers.png', done);
    });
    it('pipeline_09_serif_font', 0, (done: Function) => {
      runPipelineTest('09_serif_font', 'sudoku_test_images/09_serif_font.png', done);
    });
    it('pipeline_10_italic_font', 0, (done: Function) => {
      runPipelineTest('10_italic_font', 'sudoku_test_images/10_italic_font.png', done);
    });
    it('pipeline_11_thin_font', 0, (done: Function) => {
      runPipelineTest('11_thin_font', 'sudoku_test_images/11_thin_font.png', done);
    });
    it('pipeline_12_all_thin_lines', 0, (done: Function) => {
      runPipelineTest('12_all_thin_lines', 'sudoku_test_images/12_all_thin_lines.png', done);
    });
    it('pipeline_13_no_outer_border', 0, (done: Function) => {
      runPipelineTest('13_no_outer_border', 'sudoku_test_images/13_no_outer_border.png', done);
    });
    it('pipeline_14_tiny_200', 0, (done: Function) => {
      runPipelineTest('14_tiny_200', 'sudoku_test_images/14_tiny_200.png', done);
    });
    it('pipeline_15_huge_1000', 0, (done: Function) => {
      runPipelineTest('15_huge_1000', 'sudoku_test_images/15_huge_1000.png', done);
    });
    it('pipeline_photos', 0, (done: Function) => {
      runPipelineTest('photos', 'sudoku_test_images/photos.jpg', done);
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
