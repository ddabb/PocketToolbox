/**
 * 数独引擎单元测试（1.4.7 Phase 1 测试安全网）
 * 覆盖：DLX 求解（唯一解/长度校验/冲突/无解）/ 候选数 / 提示 / OCR 文本解析 / 网格校验
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  solveSudoku, getCandidates, getHint, parseOCRToGrid, gridToString,
  validateFullGrid, isGridFull, SolveResult, HintCell
} from '../../../main/ets/core/sudoku/SudokuEngine';

const PUZZLE: number[] = [
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

const SOLUTION: number[] = [
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

/** 无直接冲突但 (0,3) 无候选 → 无解（解数 0） */
const UNSOLVABLE: number[] = [
  2, 3, 4, 0, 5, 6, 7, 8, 9,
  5, 6, 7, 0, 0, 0, 0, 0, 0,
  8, 9, 1, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 1, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0,
];

function arrEq(a: number[], b: number[]): boolean {
  if (a.length !== b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) {
      return false;
    }
  }
  return true;
}

export default function sudokuEngineTest() {
  describe('sudokuEngineTest', () => {
    /** tc1: 经典题唯一解 —— DLX 求解与已知解一致，题面数字保留 */
    it('tc1_solveClassic', 0, () => {
      let r: SolveResult = solveSudoku(PUZZLE);
      expect(r.success).assertTrue();
      expect(r.solutionCount).assertEqual(1);
      expect(arrEq(r.solution, SOLUTION)).assertTrue();
      expect(validateFullGrid(r.solution)).assertTrue();
      for (let i = 0; i < 81; i++) {
        if (PUZZLE[i] !== 0) {
          expect(r.solution[i]).assertEqual(PUZZLE[i]);
        }
      }
    });

    /** tc2: 输入校验 —— 长度非 81 直接失败 */
    it('tc2_wrongLength', 0, () => {
      let r: SolveResult = solveSudoku(new Array<number>(80).fill(0));
      expect(r.success).assertFalse();
      expect(r.solutionCount).assertEqual(0);
    });

    /** tc3: 题面直接冲突（同行重复）→ solutionCount = -1 */
    it('tc3_directConflict', 0, () => {
      let bad: number[] = PUZZLE.slice();
      bad[1] = 5;
      let r: SolveResult = solveSudoku(bad);
      expect(r.success).assertFalse();
      expect(r.solutionCount).assertEqual(-1);
    });

    /** tc4: 无直接冲突但无解 → solutionCount = 0 */
    it('tc4_unsolvable', 0, () => {
      let r: SolveResult = solveSudoku(UNSOLVABLE);
      expect(r.success).assertFalse();
      expect(r.solutionCount).assertEqual(0);
    });

    /** tc5: 候选数 —— 空格 (0,2) 候选 {1,2,4}；已填格返回空 */
    it('tc5_candidates', 0, () => {
      let cands: number[] = getCandidates(PUZZLE, 0, 2);
      expect(arrEq(cands, [1, 2, 4])).assertTrue();
      expect(getCandidates(PUZZLE, 0, 0).length).assertEqual(0);
    });

    /** tc6: 提示 —— 提示值与解一致 */
    it('tc6_hint', 0, () => {
      let hint: HintCell | null = getHint(PUZZLE);
      expect(hint !== null).assertTrue();
      if (hint !== null) {
        expect(hint.value).assertEqual(SOLUTION[hint.row * 9 + hint.col]);
      }
    });

    /** tc7: OCR 文本解析 —— 81 位连续 / 点号问号占位 / 换行分组 / 不足 17 位拒绝 */
    it('tc7_parseOcr', 0, () => {
      let digits: string = '';
      for (let i = 0; i < 81; i++) {
        digits += PUZZLE[i].toString();
      }
      let g1: number[] | null = parseOCRToGrid(digits);
      expect(g1 !== null).assertTrue();
      expect(arrEq(g1 as number[], PUZZLE)).assertTrue();

      let dotted: string = digits.replace(/0/g, '.');
      let g2: number[] | null = parseOCRToGrid(dotted);
      expect(arrEq(g2 as number[], PUZZLE)).assertTrue();

      let asked: string = digits.replace(/0/g, '?');
      let g3: number[] | null = parseOCRToGrid(asked);
      expect(arrEq(g3 as number[], PUZZLE)).assertTrue();

      expect(parseOCRToGrid('123')).assertEqual(null);
      expect(parseOCRToGrid('')).assertEqual(null);

      // 行分组 + 空白容忍
      let lines: string[] = [];
      for (let r = 0; r < 9; r++) {
        lines.push(digits.substring(r * 9, r * 9 + 9));
      }
      let g4: number[] | null = parseOCRToGrid(lines.join('\n'));
      expect(arrEq(g4 as number[], PUZZLE)).assertTrue();

      // 17..80 位：按行分组补零成 81
      let g5: number[] | null = parseOCRToGrid('12345678901234567890');
      expect(g5 !== null).assertTrue();
      expect((g5 as number[]).length).assertEqual(81);
      expect((g5 as number[])[0]).assertEqual(1);
    });

    /** tc8: gridToString —— 空格用 '.'、行间换行 */
    it('tc8_gridToString', 0, () => {
      let s: string = gridToString(PUZZLE);
      expect(s.indexOf('.')).assertLargerOrEqual(0);
      expect(s.indexOf('\n')).assertLargerOrEqual(0);
      let full: string = gridToString(SOLUTION);
      expect(full.indexOf('.')).assertEqual(-1);
    });

    /** tc9: 完整解校验 / 填满判定 */
    it('tc9_validateAndFull', 0, () => {
      expect(validateFullGrid(SOLUTION)).assertTrue();
      expect(isGridFull(SOLUTION)).assertTrue();
      expect(isGridFull(PUZZLE)).assertFalse();
      let swapped: number[] = SOLUTION.slice();
      let t: number = swapped[0];
      swapped[0] = swapped[1];
      swapped[1] = t;
      expect(validateFullGrid(swapped)).assertFalse();
      expect(validateFullGrid(new Array<number>(80).fill(0))).assertFalse();
    });
  });
}
