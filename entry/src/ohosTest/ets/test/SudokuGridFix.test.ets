/**
 * SudokuGridFix 冲突修复引擎 - 单元测试（P2-5 拆分回归网）
 * 覆盖：冲突检测（行/列/宫）、易混对判定、置数冲突计数、像素成对修正、
 * 修正目标计算、组合求解交换、冲突猜测交换、求解器唯一解交换守卫
 * 期望值全部由实现语义手工推导（标准数独唯一解网格）
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  findConflictCells, isConfusablePair, conflictCountAfterSet, applyBestPixelConflictPair,
  GridFixTargets, computeGridFixTargets,
  applyComboSolverFix, applyConflictGuessSwaps, applySolverUniqueSwaps
} from '../../../main/ets/core/sudoku/SudokuGridFix';
import { solveSudoku } from '../../../main/ets/core/sudoku/SudokuEngine';
import { OCRResult, PixelConflictCandidate, g_lastRawInkPerCell } from '../../../main/ets/core/sudoku/SudokuOCRTypes';

/** 标准数独唯一解（Wikipedia 经典题解） */
function solvedGrid(): number[] {
  return [
    5, 3, 4, 6, 7, 8, 9, 1, 2,
    6, 7, 2, 1, 9, 5, 3, 4, 8,
    1, 9, 8, 3, 4, 2, 5, 6, 7,
    8, 5, 9, 7, 6, 1, 4, 2, 3,
    4, 2, 6, 8, 5, 3, 7, 9, 1,
    7, 1, 3, 9, 2, 4, 8, 5, 6,
    9, 6, 1, 5, 3, 7, 2, 8, 4,
    2, 8, 7, 4, 1, 9, 6, 3, 5,
    3, 4, 5, 2, 8, 6, 1, 7, 9
  ];
}

function zeros81(): number[] {
  return new Array<number>(81).fill(0);
}

function conf81(v: number): number[] {
  return new Array<number>(81).fill(v);
}

export default function sudokuGridFixTest() {
  describe('SudokuGridFixTest', () => {
    /** tc1: 冲突检测 —— 解毕网格无冲突；行/列/宫重复各自暴露两个下标 */
    it('tc1_findConflictCells', 0, () => {
      expect(findConflictCells(solvedGrid()).length).assertEqual(0);
      const rowDup: number[] = zeros81();
      rowDup[0] = 6; rowDup[1] = 6;
      expect(findConflictCells(rowDup).length).assertEqual(2);
      expect(findConflictCells(rowDup)[0]).assertEqual(0);
      expect(findConflictCells(rowDup)[1]).assertEqual(1);
      const colDup: number[] = zeros81();
      colDup[0] = 5; colDup[27] = 5;
      expect(findConflictCells(colDup).length).assertEqual(2);
      expect(findConflictCells(colDup)[0]).assertEqual(0);
      expect(findConflictCells(colDup)[1]).assertEqual(27);
      const boxDup: number[] = zeros81();
      boxDup[0] = 5; boxDup[10] = 5;
      expect(findConflictCells(boxDup).length).assertEqual(2);
      expect(findConflictCells(boxDup)[0]).assertEqual(0);
      expect(findConflictCells(boxDup)[1]).assertEqual(10);
    });

    /** tc2: 易混对 —— 5/6/9 互通、指定易混对 true；相同/非易混/非法入参 false */
    it('tc2_isConfusablePair', 0, () => {
      expect(isConfusablePair(5, 9)).assertTrue();
      expect(isConfusablePair(6, 9)).assertTrue();
      expect(isConfusablePair(3, 8)).assertTrue();
      expect(isConfusablePair(2, 4)).assertTrue();
      expect(isConfusablePair(1, 3)).assertTrue();
      expect(isConfusablePair(7, 7)).assertFalse();
      expect(isConfusablePair(1, 2)).assertFalse();
      expect(isConfusablePair(0, 5)).assertFalse();
      expect(isConfusablePair(5, 0)).assertFalse();
    });

    /** tc3: 置数冲突计数 —— 原值/清零无冲突；置 5 与行首 5、列内 5 共 3 处冲突格 */
    it('tc3_conflictCountAfterSet', 0, () => {
      const solved: number[] = solvedGrid();
      expect(conflictCountAfterSet(solved, 1, 3)).assertEqual(0);
      expect(conflictCountAfterSet(solved, 1, 0)).assertEqual(0);
      expect(conflictCountAfterSet(solved, 1, 5)).assertEqual(3);
    });

    /** tc4: 像素成对修正 —— 候选不足或无冲突返 ''；双候选消冲突后应用并返回详情 */
    it('tc4_applyBestPixelConflictPair', 0, () => {
      const g: number[] = zeros81();
      g[0] = 6; g[1] = 6;
      const cands: PixelConflictCandidate[] = [];
      expect(applyBestPixelConflictPair(g, cands)).assertEqual('');
      const c0: PixelConflictCandidate = { idx: 0, digit: 9, confidence: 0.9 };
      cands.push(c0);
      expect(applyBestPixelConflictPair(g, cands)).assertEqual('');
      const c1: PixelConflictCandidate = { idx: 1, digit: 5, confidence: 0.8 };
      cands.push(c1);
      const detail: string = applyBestPixelConflictPair(g, cands);
      expect(detail.length > 0).assertTrue();
      expect(detail.indexOf('像素成对解冲突') >= 0).assertTrue();
      expect(g[0]).assertEqual(9);
      expect(g[1]).assertEqual(5);
      expect(findConflictCells(g).length).assertEqual(0);
      expect(applyBestPixelConflictPair(g, cands)).assertEqual('');
    });

    /** tc5: 修正目标计算 —— 冲突/空格索引正确；高置信不进易混/低置信；无置信时全部非零格易混 */
    it('tc5_computeGridFixTargets', 0, () => {
      g_lastRawInkPerCell.fill(0);
      const g: number[] = zeros81();
      g[0] = 6; g[1] = 6;
      const conf: number[] = conf81(1.0);
      const ocr: OCRResult = { success: true, grid: g, rawText: '', error: '', confidence: conf, debugInfo: null };
      const t: GridFixTargets = computeGridFixTargets(ocr, g);
      expect(t.conflictIndices.length).assertEqual(2);
      expect(t.conflictIndices[0]).assertEqual(0);
      expect(t.conflictIndices[1]).assertEqual(1);
      expect(t.lowConfIndices.length).assertEqual(0);
      expect(t.confusableIndices.length).assertEqual(0);
      expect(t.emptyIndices.length).assertEqual(79);
      expect(t.lowInkConfusableIndices.length).assertEqual(0);
      expect(t.highInkSuspiciousIndices.length).assertEqual(0);
      expect(t.allFixIndices.length).assertEqual(81);
      expect(t.allFixIndices[0]).assertEqual(0);
      expect(t.allFixIndices[1]).assertEqual(1);
      expect(t.allFixIndices[2]).assertEqual(2);
      expect(t.allFixIndices[80]).assertEqual(80);
      const ocrNoConf: OCRResult = { success: true, grid: g, rawText: '', error: '', confidence: null, debugInfo: null };
      const t2: GridFixTargets = computeGridFixTargets(ocrNoConf, g);
      expect(t2.confusableIndices.length).assertEqual(2);
      expect(t2.confusableIndices[0]).assertEqual(0);
      expect(t2.confusableIndices[1]).assertEqual(1);
      expect(t2.allFixIndices.length).assertEqual(81);
    });

    /** tc6: 组合求解交换 —— 3→8 误识 + 0/1 格低置信；唯一合法组合回退 idx1=3 */
    it('tc6_applyComboSolverFix', 0, () => {
      const solved: number[] = solvedGrid();
      expect(solveSudoku(solved).solutionCount).assertEqual(1);
      const g: number[] = solved.slice(0);
      g[1] = 8;
      const conf: number[] = conf81(1.0);
      conf[0] = 0.5;
      conf[1] = 0.5;
      const fixed: number = applyComboSolverFix(g, conf);
      expect(fixed).assertEqual(1);
      expect(g[1]).assertEqual(3);
      expect(g[0]).assertEqual(5);
      expect(findConflictCells(g).length).assertEqual(0);
    });

    /** tc7: 冲突猜测交换 —— 行首双 6、idx1 低置信；枚举分支选中 (6,9) 消除冲突 */
    it('tc7_applyConflictGuessSwaps', 0, async () => {
      const g: number[] = zeros81();
      g[0] = 6; g[1] = 6;
      const conf: number[] = conf81(1.0);
      conf[1] = 0.5;
      const fixed: number = await applyConflictGuessSwaps(g, conf);
      expect(fixed).assertEqual(1);
      expect(g[0]).assertEqual(6);
      expect(g[1]).assertEqual(9);
      expect(findConflictCells(g).length).assertEqual(0);
    });

    /** tc8: 求解器唯一解交换守卫 —— 唯一解不换；hasFixedAny=false 不换；多解候选不换 */
    it('tc8_applySolverUniqueSwaps', 0, () => {
      expect(applySolverUniqueSwaps(solvedGrid(), conf81(1.0), true)).assertEqual(0);
      const g: number[] = zeros81();
      g[0] = 6; g[1] = 6;
      expect(applySolverUniqueSwaps(g, conf81(1.0), false)).assertEqual(0);
      const conf: number[] = conf81(1.0);
      conf[1] = 0.5;
      expect(applySolverUniqueSwaps(g, conf, true)).assertEqual(0);
      expect(g[1]).assertEqual(6);
    });
  });
}
