import { describe, it, expect } from '@ohos/hypium';
import { parseOCRToGrid, gridToString, validateFullGrid, solveSudoku } from '../main/ets/core/sudoku/SudokuEngine';
import {
  recognizeDigit,
  findBoardBBox,
  countInk,
  TEMPLATES,
} from '../main/ets/core/sudoku/SudokuPixel';
import { analyzePixelGridFromBuffer } from '../main/ets/core/sudoku/SudokuOCR';

export default function sudokuCoreTest() {
  describe('SudokuEngine', () => {
    const puzzle: number[] = [
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
    const solution: number[] = [
      5, 3, 4, 6, 7, 8, 9, 1, 2,
      6, 7, 2, 1, 9, 5, 3, 4, 8,
      1, 9, 8, 3, 4, 2, 5, 6, 7,
      8, 5, 9, 7, 6, 1, 4, 2, 3,
      4, 2, 6, 8, 5, 3, 7, 9, 1,
      7, 1, 3, 9, 2, 4, 8, 5, 6,
      9, 6, 1, 5, 3, 7, 2, 8, 4,
      2, 8, 7, 4, 1, 9, 6, 3, 5,
      3, 4, 5, 2, 8, 6, 1, 7, 9,
    ];

    it('solveSudoku_returns_correct_solution', 0, () => {
      const res = solveSudoku(puzzle.slice());
      expect(res.success).assertTrue();
      expect(res.solution.join(',')).assertEqual(solution.join(','));
    });

    it('solveSudoku_unsolvable_returns_false', 0, () => {
      const bad: number[] = puzzle.slice();
      bad[0] = 5; bad[1] = 5;
      const res = solveSudoku(bad);
      expect(res.success).assertFalse();
    });

    it('validateFullGrid_valid_solution', 0, () => {
      expect(validateFullGrid(solution)).assertTrue();
    });

    it('validateFullGrid_invalid_duplicate', 0, () => {
      const bad: number[] = solution.slice();
      bad[0] = 1;
      expect(validateFullGrid(bad)).assertFalse();
    });

    it('gridToString_roundtrip', 0, () => {
      const s: string = gridToString(puzzle);
      expect(parseOCRToGrid(s)!.join(',')).assertEqual(puzzle.join(','));
    });
  });

  describe('parseOCRToGrid', () => {
    it('parses_81char_string', 0, () => {
      const s: string = '53..7....6..195....98....6.8...6...34..8.3..17...2...6.6....28....419..5....8..79';
      const grid: number[] = parseOCRToGrid(s)!;
      expect(grid.length).assertEqual(81);
      expect(grid[0]).assertEqual(5);
      expect(grid[2]).assertEqual(0);
    });

    it('parses_line_feeded_grid_with_dots', 0, () => {
      const s: string = [
        '5 3 . | . 7 . | . . .',
        '6 . . | 1 9 5 | . . .',
        '. 9 8 | . . . | . 6 .',
        '------+-------+------',
        '8 . . | . 6 . | . . 3',
        '4 . . | 8 . 3 | . . 1',
        '7 . . | . 2 . | . . 6',
        '------+-------+------',
        '. 6 . | . . . | 2 8 .',
        '. . . | 4 1 9 | . . 5',
        '. . . | . 8 . | . 7 9',
      ].join('\n');
      const grid: number[] = parseOCRToGrid(s)!;
      expect(grid.length).assertEqual(81);
      expect(grid[0]).assertEqual(5);
      expect(grid[80]).assertEqual(9);
    });

    it('handles_garbage_chars_as_empty', 0, () => {
      const s: string = '1a2b3c4d5e6f7g8h9i'.padEnd(81, '0');
      const grid: number[] = parseOCRToGrid(s)!;
      expect(grid.length).assertEqual(81);
      expect(grid.some((v: number) => v < 0 || v > 9)).assertFalse();
    });
  });

  describe('SudokuPixel_recognizeDigit', () => {
    it('recognizes_all_9_templates', 0, () => {
      for (let d: number = 1; d <= 9; d++) {
        const sig: number[] = TEMPLATES[d - 1].key.slice();
        const ink: number = countInk(sig);
        const got: number = recognizeDigit(sig, ink);
        expect(got).assertEqual(d);
      }
    });

    it('returns_0_for_empty_signature', 0, () => {
      const empty: number[] = new Array<number>(70).fill(0);
      const got: number = recognizeDigit(empty, 0);
      expect(got).assertEqual(0);
    });

    it('noisy_template_still_recognized', 0, () => {
      const sig: number[] = TEMPLATES[4].key.slice();
      sig[3] = sig[3] === 1 ? 0 : 1;
      sig[40] = sig[40] === 1 ? 0 : 1;
      sig[66] = sig[66] === 1 ? 0 : 1;
      const got: number = recognizeDigit(sig, countInk(sig));
      expect(got).assertEqual(5);
    });

    it('9_with_top_loop_broken_still_9', 0, () => {
      const sig: number[] = TEMPLATES[8].key.slice();
      for (let i: number = 0; i < 7; i++) { sig[i] = 0; }
      sig[7] = 0; sig[8] = 0;
      const got: number = recognizeDigit(sig, countInk(sig));
      expect(got).assertEqual(9);
    });

    it('9_with_heavy_noise_still_9', 0, () => {
      const sig: number[] = TEMPLATES[8].key.slice();
      for (let i: number = 0; i < 14; i++) { sig[i] = 0; }
      sig[63] = 1; sig[64] = 1; sig[65] = 1;
      const got: number = recognizeDigit(sig, countInk(sig));
      expect(got).assertEqual(9);
    });

    it('6_with_top_noise_still_6', 0, () => {
      const sig: number[] = TEMPLATES[5].key.slice();
      sig[3] = 1; sig[4] = 1; sig[5] = 1;
      const got: number = recognizeDigit(sig, countInk(sig));
      expect(got).assertEqual(6);
    });

    it('6_with_bottom_erased_still_6', 0, () => {
      const sig: number[] = TEMPLATES[5].key.slice();
      for (let i: number = 63; i < 70; i++) { sig[i] = 0; }
      const got: number = recognizeDigit(sig, countInk(sig));
      expect(got).assertEqual(6);
    });

    it('6_vs_9_with_3bit_noise_correct', 0, () => {
      const sig6: number[] = TEMPLATES[5].key.slice();
      sig6[5] = 1; sig6[47] = 0; sig6[62] = 0;
      const got6: number = recognizeDigit(sig6, countInk(sig6));
      expect(got6).assertEqual(6);

      const sig9: number[] = TEMPLATES[8].key.slice();
      sig9[3] = 0; sig9[41] = 0; sig9[48] = 1;
      const got9: number = recognizeDigit(sig9, countInk(sig9));
      expect(got9).assertEqual(9);
    });
  });

  describe('SudokuPixel_findBoardBBox', () => {
    it('detects_full_image_when_no_grid_lines', 0, () => {
      const W: number = 100;
      const H: number = 100;
      const px: Uint8Array = new Uint8Array(W * H * 4).fill(255);
      const box = findBoardBBox(px, W, H, 255);
      expect(box.left).assertEqual(0);
      expect(box.right).assertEqual(W);
      expect(box.isDark).assertFalse();
    });

    it('detects_bounding_box_with_grid_lines', 0, () => {
      const W: number = 200;
      const H: number = 200;
      const px: Uint8Array = new Uint8Array(W * H * 4).fill(255);
      const lines: number[] = [20, 100, 180];
      for (let li: number = 0; li < lines.length; li++) {
        const lx: number = lines[li];
        for (let y: number = 0; y < H; y++) {
          const idx: number = (y * W + lx) * 4;
          px[idx] = 0; px[idx + 1] = 0; px[idx + 2] = 0; px[idx + 3] = 255;
        }
      }
      for (let li: number = 0; li < lines.length; li++) {
        const ly: number = lines[li];
        for (let x: number = 0; x < W; x++) {
          const idx: number = (ly * W + x) * 4;
          px[idx] = 0; px[idx + 1] = 0; px[idx + 2] = 0; px[idx + 3] = 255;
        }
      }
      const box = findBoardBBox(px, W, H, 255);
      expect(box.left).assertLess(30);
      expect(box.right).assertLarger(170);
      expect(box.top).assertLess(30);
      expect(box.bottom).assertLarger(170);
    });
  });

  describe('analyzePixelGridFromBuffer', () => {
    it('returns_81_zeros_for_blank_white_image', 0, () => {
      const W: number = 100;
      const H: number = 100;
      const px: Uint8Array = new Uint8Array(W * H * 4).fill(255);
      const grid: number[] = analyzePixelGridFromBuffer(px, W, H);
      expect(grid.length).assertEqual(81);
      expect(grid.every((v: number) => v === 0)).assertTrue();
    });

    it('detects_grid_lines_in_synthetic_image', 0, () => {
      const W: number = 450;
      const H: number = 450;
      const px: Uint8Array = new Uint8Array(W * H * 4).fill(255);
      const cellSize: number = 50;
      for (let i: number = 0; i <= 9; i++) {
        const pos: number = i * cellSize;
        for (let y: number = 0; y < H; y++) {
          const idx: number = (y * W + pos) * 4;
          if (idx + 3 < px.length) {
            px[idx] = 0; px[idx + 1] = 0; px[idx + 2] = 0; px[idx + 3] = 255;
          }
        }
        for (let x: number = 0; x < W; x++) {
          const idx: number = (pos * W + x) * 4;
          if (idx + 3 < px.length) {
            px[idx] = 0; px[idx + 1] = 0; px[idx + 2] = 0; px[idx + 3] = 255;
          }
        }
      }
      const grid: number[] = analyzePixelGridFromBuffer(px, W, H);
      expect(grid.length).assertEqual(81);
    });
  });
}
