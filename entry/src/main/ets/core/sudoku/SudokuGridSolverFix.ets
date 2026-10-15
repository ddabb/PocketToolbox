import { hilog } from '@kit.PerformanceAnalysisKit';
import { setLastComboSolverDiag, g_lastSecondBestDigit } from './SudokuOCRTypes';
import { DOMAIN, TAG, yieldThread } from './SudokuOCRUtils';
import { solveSudoku, SolveResult } from './SudokuEngine';
import { findConflictCells } from './SudokuGridConflict';

interface SwapOption { idx: number; newVal: number; isOrig: boolean; }

export function applyComboSolverFix(grid: number[], cellConfidence: number[]): number {
  let comboFixed: number = 0;

  // Brute-force search for confusable groups BEFORE combo-swap
  {
    const confusablePairsAll: number[][] = [[3, 8], [8, 3], [5, 8], [8, 5],
      [7, 1], [1, 7], [8, 9], [9, 8], [1, 4], [4, 1], [9, 4], [4, 9],
      [6, 9], [9, 6], [5, 6], [6, 5], [1, 2], [2, 1], [2, 8], [8, 2],
      [1, 8], [8, 1], [3, 5], [5, 3], [3, 7], [7, 3]];
    const ambiguousCells: number[] = [];
    const ambiguousAlt: number[] = [];
    const ambiguousSet: Set<number> = new Set<number>();
    for (let si2: number = 0; si2 < 81; si2++) {
      if (grid[si2] <= 0) { continue; }
      if (cellConfidence[si2] < 0.90) {
        for (const cp of confusablePairsAll) {
          if (grid[si2] === cp[0]) {
            if (!ambiguousSet.has(si2)) {
              ambiguousCells.push(si2);
              ambiguousAlt.push(cp[1]);
              ambiguousSet.add(si2);
            }
            break;
          }
        }
      }
    }
    let comboDiag: string = `ambiguous=${ambiguousCells.length}:`;
    for (let ai0: number = 0; ai0 < ambiguousCells.length; ai0++) {
      comboDiag += ` (${Math.floor(ambiguousCells[ai0] / 9)},${ambiguousCells[ai0] % 9})${grid[ambiguousCells[ai0]]}→${ambiguousAlt[ai0]}`;
    }
    if (ambiguousCells.length < 2 || ambiguousCells.length > 20) {
      setLastComboSolverDiag(comboDiag + ` skip(count)`);
    }
    if (ambiguousCells.length >= 2 && ambiguousCells.length <= 20) {
      const comboCount: number = 1 << ambiguousCells.length;
      const validCombos: number[] = [];
      for (let combo: number = 0; combo < comboCount; combo++) {
        const savedGrid: number[] = grid.slice(0);
        for (let ai: number = 0; ai < ambiguousCells.length; ai++) {
          if ((combo & (1 << ai)) !== 0) {
            grid[ambiguousCells[ai]] = ambiguousAlt[ai];
          }
        }
        const trial: SolveResult = solveSudoku(grid);
        if (trial.solutionCount >= 1) {
          validCombos.push(combo);
        }
        for (let ai2: number = 0; ai2 < ambiguousCells.length; ai2++) {
          grid[ambiguousCells[ai2]] = savedGrid[ambiguousCells[ai2]];
        }
      }
      if (validCombos.length === 1) {
        const applyCombo: number = validCombos[0];
        for (let ai3: number = 0; ai3 < ambiguousCells.length; ai3++) {
          if ((applyCombo & (1 << ai3)) !== 0) {
            const oldV: number = grid[ambiguousCells[ai3]];
            grid[ambiguousCells[ai3]] = ambiguousAlt[ai3];
            comboFixed++;
            hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 组合求解交换(%{public}d,%{public}d) %{public}d→%{public}d',
              Math.floor(ambiguousCells[ai3] / 9), ambiguousCells[ai3] % 9, oldV, ambiguousAlt[ai3]);
          }
        }
      } else if (validCombos.length > 1) {
        comboDiag += ` multiValid=${validCombos.length}`;
      } else {
        comboDiag += ` noValid`;
      }
      setLastComboSolverDiag(comboDiag);
    }
  }

  return comboFixed;
}

export async function applyConflictGuessSwaps(grid: number[], cellConfidence: number[]): Promise<number> {
  const remainingConflicts: number[] = findConflictCells(grid);
  const conflictGuessSwaps: number[][] = [
    [6, 9], [9, 6], [5, 9], [9, 5], [5, 6], [6, 5],
    [5, 8], [8, 5], [1, 8], [8, 1], [1, 4], [4, 1],
    [7, 1], [1, 7], [2, 4], [4, 2], [3, 7], [7, 3],
    [1, 6], [6, 1], [2, 8], [8, 2], [3, 8], [8, 3],
    [7, 9], [9, 7], [8, 9], [9, 8], [4, 9], [9, 4], [3, 5], [5, 3],
  ];
  if (remainingConflicts.length > 0 && remainingConflicts.length <= 10) {
    const cellOptions: SwapOption[][] = [];
    const cellOriginals: number[] = [];
    for (const ci of remainingConflicts) {
      const origVal: number = grid[ci];
      if (origVal === 0) { continue; }
      const options: SwapOption[] = [{ idx: ci, newVal: origVal, isOrig: true }];
      for (const pair of conflictGuessSwaps) {
        if (origVal === pair[0]) {
          options.push({ idx: ci, newVal: pair[1], isOrig: false });
        }
      }
      cellOptions.push(options);
      cellOriginals.push(origVal);
    }
    if (cellOptions.length > 0 && cellOptions.length <= 10) {
      const combos: number = cellOptions.reduce((acc: number, opts: SwapOption[]): number => acc * opts.length, 1);
      if (combos <= 5000) {
        const saved: number[] = [];
        for (const ci of remainingConflicts) { saved.push(grid[ci]); }
        let bestCombo: number[] = saved.slice();
        let bestConf: number = remainingConflicts.length;
        let bestHighConfSwaps: number = 999;
        let bestSecondBestMatch: number = -1;
        const indices: number[] = new Array<number>(cellOptions.length).fill(0);
        let searching: boolean = true;
        while (searching) {
          for (let k: number = 0; k < cellOptions.length; k++) {
            const ci: number = cellOptions[k][indices[k]].idx;
            grid[ci] = cellOptions[k][indices[k]].newVal;
          }
          const trialConf: number = findConflictCells(grid).length;
          let highConfSwaps: number = 0;
          let veryHighConfSwaps: number = 0;
          let secondBestMatch: number = 0;
          for (let k: number = 0; k < cellOptions.length; k++) {
            if (!cellOptions[k][indices[k]].isOrig && cellConfidence[cellOptions[k][indices[k]].idx] >= 0.70) {
              highConfSwaps++;
            }
            if (!cellOptions[k][indices[k]].isOrig && cellConfidence[cellOptions[k][indices[k]].idx] >= 0.90) {
              veryHighConfSwaps++;
            }
            if (!cellOptions[k][indices[k]].isOrig && cellOptions[k][indices[k]].newVal === g_lastSecondBestDigit[cellOptions[k][indices[k]].idx] && cellConfidence[cellOptions[k][indices[k]].idx] >= 0.60) {
              secondBestMatch++;
            }
          }
          if (veryHighConfSwaps > 0) {
            for (let k: number = cellOptions.length - 1; k >= 0; k--) {
              indices[k]++;
              if (indices[k] < cellOptions[k].length) { break; }
              indices[k] = 0;
              if (k === 0) { searching = false; }
            }
            continue;
          }
          if (trialConf < bestConf || (trialConf === bestConf && highConfSwaps < bestHighConfSwaps) ||
            (trialConf === bestConf && highConfSwaps === bestHighConfSwaps && secondBestMatch > bestSecondBestMatch)) {
            bestConf = trialConf;
            bestHighConfSwaps = highConfSwaps;
            bestSecondBestMatch = secondBestMatch;
            for (let k: number = 0; k < cellOptions.length; k++) {
              bestCombo[k] = cellOptions[k][indices[k]].newVal;
            }
          }
          for (let k: number = cellOptions.length - 1; k >= 0; k--) {
            indices[k]++;
            if (indices[k] < cellOptions[k].length) { break; }
            indices[k] = 0;
            if (k === 0) { searching = false; }
          }
        }
        for (let k: number = 0; k < remainingConflicts.length; k++) { grid[remainingConflicts[k]] = saved[k]; }
        let comboFixCount: number = 0;
        for (let k: number = 0; k < remainingConflicts.length; k++) {
          const ci: number = remainingConflicts[k];
          if (saved[k] !== bestCombo[k]) {
            hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 组合交换(%{public}d,%{public}d) %{public}d→%{public}d conf=%{public}.2f',
              Math.floor(ci / 9), ci % 9, saved[k], bestCombo[k], cellConfidence[ci]);
            grid[ci] = bestCombo[k];
            comboFixCount++;
          }
        }
        if (comboFixCount > 0) {
          hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 组合交换修正%{public}d个 冲突%{public}d→%{public}d',
            comboFixCount, remainingConflicts.length, bestConf);
        }
        return comboFixCount;
      } else {
        let guessFixCount: number = 0;
        for (const ci of remainingConflicts) {
          await yieldThread();
          const origVal: number = grid[ci];
          if (origVal === 0) { continue; }
          const beforeConf: number = findConflictCells(grid).length;
          let bestSwapVal: number = origVal;
          let bestSwapConf: number = beforeConf;
          if (cellConfidence[ci] >= 0.90) { continue; }
          for (const pair of conflictGuessSwaps) {
            if (origVal === pair[0]) {
              grid[ci] = pair[1];
              const afterSwap: number[] = findConflictCells(grid);
              if (afterSwap.length < bestSwapConf && !afterSwap.some((ac: number) => ac === ci)) {
                bestSwapVal = pair[1];
                bestSwapConf = afterSwap.length;
              }
              grid[ci] = origVal;
            }
          }
          if (bestSwapVal !== origVal) {
            grid[ci] = bestSwapVal;
            guessFixCount++;
            hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 冲突猜测交换(%{public}d,%{public}d) %{public}d→%{public}d 冲突%{public}d→%{public}d',
              Math.floor(ci / 9), ci % 9, origVal, bestSwapVal, beforeConf, bestSwapConf);
          }
        }
        if (guessFixCount > 0) {
          hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 冲突猜测交换修正%{public}d个', guessFixCount);
        }
        return guessFixCount;
      }
    }
  }
  return 0;
}

export function applySolverUniqueSwaps(grid: number[], cellConfidence: number[], hasFixedAny: boolean): number {
  const solverSwaps: number[][] = [
    [8, 9], [9, 8], [7, 9], [9, 7], [6, 9], [9, 6],
    [5, 9], [9, 5], [5, 6], [6, 5], [5, 8], [8, 5],
    [3, 8], [8, 3], [1, 8], [8, 1], [2, 8], [8, 2],
    [3, 5], [5, 3], [1, 7], [7, 1], [1, 4], [4, 1],
    [1, 6], [6, 1], [2, 4], [4, 2], [3, 7], [7, 3],
    [4, 9], [9, 4], [1, 2], [2, 1],
  ];
  const solverResult = solveSudoku(grid);
  if (solverResult.solutionCount !== 1 && hasFixedAny) {
    const changedCells: number[] = [];
    for (let si: number = 0; si < 81; si++) {
      if (grid[si] > 0 && cellConfidence[si] < 0.90) {
        changedCells.push(si);
      }
    }
    if (changedCells.length > 0 && changedCells.length <= 15) {
      let solverFixed: number = 0;
      for (const ci of changedCells) {
        const origVal: number = grid[ci];
        if (origVal === 0) { continue; }
        for (const pair of solverSwaps) {
          if (origVal !== pair[0]) { continue; }
          grid[ci] = pair[1];
          const trialResult = solveSudoku(grid);
          if (trialResult.solutionCount === 1) {
            solverFixed++;
            hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 求解器唯一解交换(%{public}d,%{public}d) %{public}d→%{public}d',
              Math.floor(ci / 9), ci % 9, origVal, pair[1]);
            break;
          }
          grid[ci] = origVal;
        }
      }
      if (solverFixed > 0) {
        hilog.info(DOMAIN, TAG, 'fixAndFillGrid: 求解器修正%{public}d个', solverFixed);
      }
      return solverFixed;
    }
  }
  return 0;
}
