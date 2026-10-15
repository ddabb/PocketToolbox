import { hilog } from '@kit.PerformanceAnalysisKit';
import { yieldThread } from './SudokuOCRUtils';

import {
  DOMAIN, TAG, DigitTemplate, SP,
  SIG_ROWS, SIG_COLS, SIG_LEN, MIN_INK_COUNT,
  MIN_INK_COUNT_DIGIT1, THIN1_MIN_INK_COUNT, MIN_DIGIT_SCORE, LOW_INK_FALLBACK_MIN_SCORE,
  LOW_INK_FALLBACK_MIN_RECALL, DISAMBIG_HOLE_WEIGHT, DISAMBIG_CENTROID_WEIGHT, DISAMBIG_TOP_RATIO_WEIGHT,
  DISAMBIG_HOG_WEIGHT, DISAMBIG_SW_WEIGHT, DISAMBIG_SCORE_WEIGHT, DISAMBIG_SCORE_GAP_SKIP,
  TEMPLATE_MISMATCH_PENALTY, TEMPLATE_F1_WEIGHT
} from './SudokuPixelKernel';
import {
  holeCenterRow, countHoles, computeSigQualityMetrics, inkCentroidRow,
  topBottomInkRatio, inkCentroidCol, templateMatchesInkFilter, sigComputeLeftRightRatio,
  hogVerticalGradient, strokeWidthRatio
} from './SudokuSigAnalysis';
import {
  detectThinOne, detectLooseOne, tryStripLeftEdgeAs1, sigToCompactStr,
  isLikelyNot4
} from './SudokuSigShapes';

export * from './SudokuPixelKernel';
export * from './SudokuGrayOps';
export * from './SudokuSigAnalysis';
export * from './SudokuDigitTemplateStore';
export * from './SudokuSigShapes';
export * from './SudokuLatticeFit';
export * from './SudokuBoardBBox';
export * from './SudokuHoughBoard';
export * from './SudokuCellSig';
export * from './SudokuCellSigGray';
export * from './SudokuPreciseGrid';

export async function recognizeDigit(sig: number[], inkCount: number): Promise<number> {
  computeSigQualityMetrics(sig);
  if (inkCount < THIN1_MIN_INK_COUNT) { return 0; }
  if (SP.templates.length === 0) { return 0; }
  const sigInkPos: number[] = [];
  for (let i: number = 0; i < SIG_LEN; i++) {
    if (sig[i] === 1) { sigInkPos.push(i); }
  }
  const sigInkLen: number = sigInkPos.length;
  const lowInk: boolean = inkCount < MIN_INK_COUNT;
  if (lowInk) {
    let best1Score: number = -100000;
    let best1Key: Int8Array | null = null;
    const tpls1: DigitTemplate[] = SP.templatesByDigit[1];
    const veryThinInk: boolean = inkCount < MIN_INK_COUNT_DIGIT1;
    for (let ti: number = 0; ti < tpls1.length; ti++) {
      if (ti % 30 === 0) { await yieldThread(); }
      const t: DigitTemplate = tpls1[ti];
      if (!veryThinInk && !templateMatchesInkFilter(t, inkCount)) { continue; }
      const kb: Int8Array = t.keyBytes;
      let tp: number = 0;
      for (let j: number = 0; j < sigInkLen; j++) {
        if (kb[sigInkPos[j]] === 1) { tp++; }
      }
      const match: number = SIG_LEN - sigInkLen - t.inkCount + 2 * tp;
      const score: number = match - (SIG_LEN - match) * TEMPLATE_MISMATCH_PENALTY;
      if (score > best1Score) { best1Score = score; best1Key = kb; }
    }
    const lowInkMinScore: number = Math.floor(SIG_LEN * 0.57);
    const geoMinScore: number = Math.floor(SIG_LEN * 0.55);
    if (veryThinInk) {
      if (best1Key !== null) {
        let tp: number = 0;
        let tplInkC: number = 0;
        for (let i: number = 0; i < SIG_LEN; i++) {
          if (best1Key[i] === 1) {
            tplInkC++;
            if (sig[i] === 1) { tp++; }
          }
        }
        const recall: number = tplInkC > 0 ? tp / tplInkC : 0;
        const thinOk: boolean = detectThinOne(sig, inkCount);
      SP.lastPixelDiag = `ink=${inkCount} score=${best1Score} recall=${recall.toFixed(2)} thinOk=${thinOk ? 1 : 0} tp=${tp}/${tplInkC}`;
        const recallGate: number = inkCount < THIN1_MIN_INK_COUNT * 2 ? 0.10 : 0.25;
        if (best1Score >= lowInkMinScore && recall >= recallGate && thinOk) {
          SP.lastConfidence = 0.50;
          return 1;
        }
      }
    }
    if (best1Score >= lowInkMinScore && best1Key !== null) {
      const inkCentroid: number = inkCentroidRow(sig);
      let tSumR: number = 0;
      let tCnt: number = 0;
      for (let r: number = 0; r < SIG_ROWS; r++) {
        for (let c: number = 0; c < SIG_COLS; c++) {
          if (best1Key[r * SIG_COLS + c] === 1) { tSumR += r; tCnt++; }
        }
      }
      const tplCentroid: number = tCnt > 0 ? tSumR / tCnt : -1;
      if (Math.abs(inkCentroid - tplCentroid) <= SIG_ROWS * 0.4) {
        // Check if this might be 7 not 1: 7 has wide top bar with solid rows
        const topRow: number = Math.floor(SIG_ROWS * 0.10);
        const topEnd: number = Math.floor(SIG_ROWS * 0.30);
        let topMinC: number = SIG_COLS;
        let topMaxC: number = 0;
        for (let r: number = topRow; r < topEnd; r++) {
          for (let c: number = 0; c < SIG_COLS; c++) {
            if (sig[r * SIG_COLS + c] === 1) {
              if (c < topMinC) { topMinC = c; }
              if (c > topMaxC) { topMaxC = c; }
            }
          }
        }
        const topSpan: number = topMaxC >= topMinC ? topMaxC - topMinC + 1 : 0;
        if (topSpan >= SIG_COLS * 0.6) {
          let solidTopRows: number = 0;
          for (let r: number = topRow; r < topEnd; r++) {
            let inkInRow: number = 0;
            for (let c: number = 0; c < SIG_COLS; c++) {
              if (sig[r * SIG_COLS + c] === 1) { inkInRow++; }
            }
            if (inkInRow >= SIG_COLS * 0.5) { solidTopRows++; }
          }
          if (solidTopRows >= 2) {
            let best7Score: number = -100000;
            const tpls7: DigitTemplate[] = SP.templatesByDigit[7];
            for (let ti2: number = 0; ti2 < tpls7.length; ti2++) {
              if (ti2 % 30 === 0) { await yieldThread(); }
              const t7: DigitTemplate = tpls7[ti2];
              if (!templateMatchesInkFilter(t7, inkCount)) { continue; }
              const kb7: Int8Array = t7.keyBytes;
              let tp7: number = 0;
              for (let j: number = 0; j < sigInkLen; j++) {
                if (kb7[sigInkPos[j]] === 1) { tp7++; }
              }
              const m7: number = SIG_LEN - sigInkLen - t7.inkCount + 2 * tp7;
              const s7: number = m7 - (SIG_LEN - m7) * TEMPLATE_MISMATCH_PENALTY;
              if (s7 > best7Score) { best7Score = s7; }
            }
            if (best7Score >= lowInkMinScore - 50) {
              if (best1Score > best7Score + 30) {
                SP.lastPixelDiag = `lowInk7→1: s1=${best1Score}>s7=${best7Score}+30 topSpan=${topSpan} solidTop=${solidTopRows}`;
                const rawConf1: number = best1Score / (SIG_LEN + 200);
                SP.lastConfidence = rawConf1 > 1 ? 1 : (rawConf1 < 0 ? 0 : rawConf1);
                return 1;
              }
              SP.lastPixelDiag = `lowInk7-over-1: topSpan=${topSpan} solidTop=${solidTopRows} s7=${best7Score} s1=${best1Score}`;
              const rawConf7: number = best7Score / (SIG_LEN + 200);
              SP.lastConfidence = rawConf7 > 1 ? 1 : (rawConf7 < 0 ? 0 : rawConf7);
              return 7;
            }
          }
        }
        const rawConf: number = best1Score / (SIG_LEN + 200);
        SP.lastConfidence = rawConf > 1 ? 1 : (rawConf < 0 ? 0 : rawConf);
        let bestNon1ScoreLow: number = -100000;
        let bestNon1DigitLow: number = 0;
        for (let d: number = 2; d <= 9; d++) {
          const tplsN1: DigitTemplate[] = SP.templatesByDigit[d];
          for (let tiN1: number = 0; tiN1 < tplsN1.length; tiN1++) {
            if (tiN1 % 30 === 0) { await yieldThread(); }
            const tN1: DigitTemplate = tplsN1[tiN1];
            if (!templateMatchesInkFilter(tN1, inkCount)) { continue; }
            const kbN1: Int8Array = tN1.keyBytes;
            let tpN1: number = 0;
            for (let jN1: number = 0; jN1 < sigInkLen; jN1++) {
              if (kbN1[sigInkPos[jN1]] === 1) { tpN1++; }
            }
            const mN1: number = SIG_LEN - sigInkLen - tN1.inkCount + 2 * tpN1;
            const rN1: number = tN1.inkCount > 0 ? tpN1 / tN1.inkCount : 0;
            const pN1: number = inkCount > 0 ? tpN1 / inkCount : 0;
            const fN1: number = (rN1 + pN1) > 0 ? (2 * rN1 * pN1) / (rN1 + pN1) : 0;
            const sN1: number = mN1 - (SIG_LEN - mN1) * TEMPLATE_MISMATCH_PENALTY + fN1 * TEMPLATE_F1_WEIGHT;
            if (sN1 > bestNon1ScoreLow) { bestNon1ScoreLow = sN1; bestNon1DigitLow = d; }
          }
        }
        if (bestNon1ScoreLow > best1Score + 50) {
          SP.lastPixelDiag = `lowInk1→${bestNon1DigitLow}: s${bestNon1DigitLow}=${bestNon1ScoreLow.toFixed(0)} s1=${best1Score}`;
          const rawConfN1: number = bestNon1ScoreLow / (SIG_LEN + 200);
          SP.lastConfidence = rawConfN1 > 1 ? 1 : (rawConfN1 < 0 ? 0 : rawConfN1);
          if (bestNon1DigitLow === 9 || bestNon1DigitLow === 8) {
            const holes98low: number = countHoles(sig);
            if (holes98low >= 2 && bestNon1DigitLow === 8) {
              SP.lastPixelDiag = `lowInk 9/8→8(holes=${holes98low}): s8=${bestNon1ScoreLow.toFixed(0)} ink=${inkCount}`;
              const rawConf98h: number = bestNon1ScoreLow / (SIG_LEN + 200);
              SP.lastConfidence = rawConf98h > 1 ? 1 : (rawConf98h < 0 ? 0 : rawConf98h);
              return 8;
            }
            let score9low: number = -100000;
            let score8low: number = -100000;
            for (let d98low: number = 8; d98low <= 9; d98low++) {
              const tpls98: DigitTemplate[] = SP.templatesByDigit[d98low];
              for (let ti98: number = 0; ti98 < tpls98.length; ti98++) {
                const t98: DigitTemplate = tpls98[ti98];
                if (!templateMatchesInkFilter(t98, inkCount)) { continue; }
                const kb98: Int8Array = t98.keyBytes;
                let tp98: number = 0;
                for (let j98: number = 0; j98 < sigInkLen; j98++) {
                  if (kb98[sigInkPos[j98]] === 1) { tp98++; }
                }
                const r98: number = sigInkLen > 0 ? tp98 / sigInkLen : 0;
                const m98: number = sigInkLen > 0 ? tp98 / (tp98 + (sigInkLen - tp98)) : 0;
                const p98: number = sigInkLen > 0 ? tp98 / (t98.inkCount > 0 ? t98.inkCount : 1) : 0;
                const f98: number = (r98 + p98) > 0 ? (2 * r98 * p98) / (r98 + p98) : 0;
                const s98: number = m98 - (SIG_LEN - m98) * TEMPLATE_MISMATCH_PENALTY + f98 * TEMPLATE_F1_WEIGHT;
                if (d98low === 9 && s98 > score9low) { score9low = s98; }
                if (d98low === 8 && s98 > score8low) { score8low = s98; }
              }
            }
            if (holes98low >= 2 && Math.abs(score9low - score8low) < 200) {
              SP.lastPixelDiag = `lowInk 9/8→8(holes=${holes98low}): s9=${score9low.toFixed(0)} s8=${score8low.toFixed(0)} ink=${inkCount}`;
              const rawConf98h2: number = score8low / (SIG_LEN + 200);
              SP.lastConfidence = rawConf98h2 > 1 ? 1 : (rawConf98h2 < 0 ? 0 : rawConf98h2);
              return 8;
            }
            const midRow98l: number = Math.floor(SIG_ROWS / 2);
            let botInk98l: number = 0;
            let topInk98l: number = 0;
            for (let r98l: number = midRow98l; r98l < SIG_ROWS; r98l++) {
              for (let c98l: number = 0; c98l < SIG_COLS; c98l++) {
                if (sig[r98l * SIG_COLS + c98l] === 1) { botInk98l++; }
              }
            }
            for (let r98lt: number = 0; r98lt < midRow98l; r98lt++) {
              for (let c98lt: number = 0; c98lt < SIG_COLS; c98lt++) {
                if (sig[r98lt * SIG_COLS + c98lt] === 1) { topInk98l++; }
              }
            }
            const botRatio98l: number = (topInk98l + botInk98l) > 0 ? botInk98l / (topInk98l + botInk98l) : 0.5;
            const midColL98l: number = Math.floor(SIG_COLS * 0.25);
            const midColR98l: number = Math.floor(SIG_COLS * 0.75);
            let midNarrow98l: number = 0;
            for (let r98m: number = Math.floor(SIG_ROWS * 0.4); r98m < Math.floor(SIG_ROWS * 0.6); r98m++) {
              let rowInk98l: number = 0;
              for (let c98m: number = midColL98l; c98m < midColR98l; c98m++) {
                if (sig[r98m * SIG_COLS + c98m] === 1) { rowInk98l++; }
              }
              midNarrow98l += rowInk98l;
            }
            const midNarrowR98l: number = midNarrow98l / ((Math.floor(SIG_ROWS * 0.6) - Math.floor(SIG_ROWS * 0.4)) * (midColR98l - midColL98l));
            if (botRatio98l > 0.42 && midNarrowR98l < 0.40) {
              SP.lastPixelDiag = `lowInk 9/8→8: botR=${botRatio98l.toFixed(2)} midNarrow=${midNarrowR98l.toFixed(2)} s9=${score9low.toFixed(0)} s8=${score8low.toFixed(0)} ink=${inkCount}`;
              const rawConf98l: number = score8low / (SIG_LEN + 200);
              SP.lastConfidence = rawConf98l > 1 ? 1 : (rawConf98l < 0 ? 0 : rawConf98l);
              return 8;
            }
          }
          return bestNon1DigitLow;
        }
        return 1;
      }
    }
    if (best1Score >= geoMinScore && detectThinOne(sig, inkCount)) {
      SP.lastConfidence = 0.55;
      return 1;
    }
    const digitBestScore: number[] = new Array<number>(10).fill(-100000);
    const digitBestIdx: number[] = new Array<number>(10).fill(-1);
    const digitBestRecall: number[] = new Array<number>(10).fill(0);
    for (let d: number = 2; d <= 9; d++) {
      const tplsD: DigitTemplate[] = SP.templatesByDigit[d];
      for (let ti: number = 0; ti < tplsD.length; ti++) {
        if (ti % 30 === 0) { await yieldThread(); }
        const t: DigitTemplate = tplsD[ti];
        if (!templateMatchesInkFilter(t, inkCount)) { continue; }
        const kb: Int8Array = t.keyBytes;
        let tp: number = 0;
        for (let j: number = 0; j < sigInkLen; j++) {
          if (kb[sigInkPos[j]] === 1) { tp++; }
        }
        const match: number = SIG_LEN - sigInkLen - t.inkCount + 2 * tp;
        const recall: number = t.inkCount > 0 ? tp / t.inkCount : 0;
        const prec: number = inkCount > 0 ? tp / inkCount : 0;
        const f1: number = (recall + prec) > 0 ? (2 * recall * prec) / (recall + prec) : 0;
        const score: number = match - (SIG_LEN - match) * TEMPLATE_MISMATCH_PENALTY + f1 * TEMPLATE_F1_WEIGHT;
        if (score > digitBestScore[t.digit]) {
          digitBestScore[t.digit] = score;
          digitBestIdx[t.digit] = ti;
          digitBestRecall[t.digit] = recall;
        }
      }
    }
    let lowBestDigit: number = 0;
    let lowBestScore: number = -100000;
    let lowBestRecall: number = 0;
    for (let d: number = 2; d <= 9; d++) {
      if (digitBestScore[d] > lowBestScore) {
        lowBestDigit = d;
        lowBestScore = digitBestScore[d];
        lowBestRecall = digitBestRecall[d];
      }
    }
    const lowMinScore: number = LOW_INK_FALLBACK_MIN_SCORE;
    if (lowBestDigit > 0 && lowBestScore >= lowMinScore && lowBestRecall >= LOW_INK_FALLBACK_MIN_RECALL) {
      if (lowBestDigit === 4) {
        const midTop14low: number = Math.floor(SIG_ROWS * 0.25);
        const midBot14low: number = Math.floor(SIG_ROWS * 0.75);
        let totalRowWidth14low: number = 0;
        let rowCount14low: number = 0;
        for (let r: number = midTop14low; r < midBot14low; r++) {
          let minC14: number = SIG_COLS;
          let maxC14: number = -1;
          for (let c: number = 0; c < SIG_COLS; c++) {
            if (sig[r * SIG_COLS + c] === 1) {
              if (c < minC14) { minC14 = c; }
              if (c > maxC14) { maxC14 = c; }
            }
          }
          if (maxC14 >= minC14) { totalRowWidth14low += maxC14 - minC14 + 1; rowCount14low++; }
        }
        const avgRowWidth14low: number = rowCount14low > 0 ? totalRowWidth14low / rowCount14low : 0;
        if (avgRowWidth14low <= 6) {
          let rightVertRows14w: number = 0;
          const rvTop14w: number = Math.floor(SIG_ROWS * 0.15);
          const rvBot14w: number = Math.floor(SIG_ROWS * 0.85);
          const rvLeft14w: number = Math.floor(SIG_COLS * 0.60);
          for (let r14wv: number = rvTop14w; r14wv < rvBot14w; r14wv++) {
            let hasRightInk14w: boolean = false;
            for (let c14wv: number = rvLeft14w; c14wv < SIG_COLS; c14wv++) {
              if (sig[r14wv * SIG_COLS + c14wv] === 1) { hasRightInk14w = true; break; }
            }
            if (hasRightInk14w) { rightVertRows14w++; }
          }
          const rightVertRatio14w: number = (rvBot14w - rvTop14w) > 0 ? rightVertRows14w / (rvBot14w - rvTop14w) : 0;
          if (rightVertRatio14w >= 0.50) {
            SP.lastPixelDiag = `lowInk4→1:blocked(rvR=${rightVertRatio14w.toFixed(2)}) avgRowW=${avgRowWidth14low.toFixed(1)} ink=${inkCount}`;
          } else {
            SP.lastPixelDiag = `lowInk4→1: avgRowW=${avgRowWidth14low.toFixed(1)} ink=${inkCount}`;
            SP.lastConfidence = 0.50;
            return 1;
          }
        }
        const crossTop14low: number = Math.floor(SIG_ROWS * 0.40);
        const crossBot14low: number = Math.floor(SIG_ROWS * 0.65);
        let hasMidCross14low: boolean = false;
        for (let r2: number = crossTop14low; r2 < crossBot14low; r2++) {
          let span14l: number = 0;
          let maxSpan14l: number = 0;
          for (let c2: number = 0; c2 < SIG_COLS; c2++) {
            if (sig[r2 * SIG_COLS + c2] === 1) {
              span14l++;
              if (span14l > maxSpan14l) { maxSpan14l = span14l; }
            } else {
              span14l = 0;
            }
          }
          if (maxSpan14l >= SIG_COLS * 0.40) { hasMidCross14low = true; break; }
        }
        if (!hasMidCross14low) {
          let rightVertRows14: number = 0;
          const rvTop14: number = Math.floor(SIG_ROWS * 0.15);
          const rvBot14: number = Math.floor(SIG_ROWS * 0.85);
          const rvLeft14: number = Math.floor(SIG_COLS * 0.60);
          for (let r14rv: number = rvTop14; r14rv < rvBot14; r14rv++) {
            let hasRightInk14: boolean = false;
            for (let c14rv: number = rvLeft14; c14rv < SIG_COLS; c14rv++) {
              if (sig[r14rv * SIG_COLS + c14rv] === 1) { hasRightInk14 = true; break; }
            }
            if (hasRightInk14) { rightVertRows14++; }
          }
          const rightVertRatio14: number = (rvBot14 - rvTop14) > 0 ? rightVertRows14 / (rvBot14 - rvTop14) : 0;
          if (rightVertRatio14 >= 0.50) {
            SP.lastPixelDiag = `lowInk4→1:blocked(rvR=${rightVertRatio14.toFixed(2)}) avgRowW=${avgRowWidth14low.toFixed(1)} ink=${inkCount}`;
          } else {
            SP.lastPixelDiag = `lowInk4→1: noMidCross rvR=${rightVertRatio14.toFixed(2)} avgRowW=${avgRowWidth14low.toFixed(1)} ink=${inkCount}`;
            SP.lastConfidence = 0.50;
            return 1;
          }
        }
        if (isLikelyNot4(sig)) {
          let best1Score2: number = -100000;
          const tpls1b: DigitTemplate[] = SP.templatesByDigit[1];
          for (let ti: number = 0; ti < tpls1b.length; ti++) {
            if (ti % 30 === 0) { await yieldThread(); }
            const t: DigitTemplate = tpls1b[ti];
            if (!templateMatchesInkFilter(t, inkCount)) { continue; }
            const kb: Int8Array = t.keyBytes;
            let tp2: number = 0;
            for (let j: number = 0; j < sigInkLen; j++) {
              if (kb[sigInkPos[j]] === 1) { tp2++; }
            }
            const match2: number = SIG_LEN - sigInkLen - t.inkCount + 2 * tp2;
            const score: number = match2 - (SIG_LEN - match2) * TEMPLATE_MISMATCH_PENALTY;
            if (score > best1Score2) { best1Score2 = score; }
          }
          const geoGate1: number = Math.floor(SIG_LEN * 0.55);
          if (best1Score2 >= geoGate1) {
            SP.lastPixelDiag = `not4→1: score1=${best1Score2} ink=${inkCount} sig=${sigToCompactStr(sig)}`;
            SP.lastConfidence = 0.55;
            return 1;
          }
        }
      }
      if (lowBestDigit === 4 || lowBestDigit === 7) {
        const stripResult: number = tryStripLeftEdgeAs1(sig, inkCount, lowBestDigit, lowBestScore);
        const stripDiag: string = SP.lastPixelDiag;
        if (stripResult === 1) { return 1; }
        if (lowBestDigit === 7) {
          if (best1Score > digitBestScore[7] + 30) {
            SP.lastPixelDiag = `lowInkFallback7→1: s1=${best1Score}>s7=${digitBestScore[7]}+30 ink=${inkCount}`;
            const rawConf1: number = best1Score / (SIG_LEN + 200);
            SP.lastConfidence = rawConf1 > 1 ? 1 : (rawConf1 < 0 ? 0 : rawConf1);
            return 1;
          }
          const topRow7: number = Math.floor(SIG_ROWS * 0.05);
          const topEnd7: number = Math.floor(SIG_ROWS * 0.35);
          let topSolid7: number = 0;
          let topTotal7: number = 0;
          let topWideRows7: number = 0;
          for (let r: number = topRow7; r < topEnd7; r++) {
            let inkInRow7: number = 0;
            let minC7: number = SIG_COLS;
            let maxC7: number = -1;
            for (let c: number = 0; c < SIG_COLS; c++) {
              if (sig[r * SIG_COLS + c] === 1) {
                inkInRow7++;
                if (c < minC7) { minC7 = c; }
                if (c > maxC7) { maxC7 = c; }
              }
            }
            topTotal7++;
            const rowSpan7: number = maxC7 >= minC7 ? maxC7 - minC7 + 1 : 0;
            if (inkInRow7 >= SIG_COLS * 0.4 && rowSpan7 >= SIG_COLS * 0.5) { topSolid7++; }
            if (rowSpan7 >= SIG_COLS * 0.6) { topWideRows7++; }
          }
          SP.lastPixelDiag = `lowInk7check: s1=${best1Score} s7=${digitBestScore[7]} topSolid=${topSolid7}/${topTotal7} topWide=${topWideRows7} ink=${inkCount}`;
          if (topSolid7 === 0 || topWideRows7 === 0) {
            if (digitBestScore[3] > digitBestScore[7] - 20) {
              SP.lastPixelDiag = `lowInk7→3(close s3): s7=${digitBestScore[7].toFixed(0)} s3=${digitBestScore[3].toFixed(0)} s1=${best1Score.toFixed(0)} ink=${inkCount}`;
              SP.lastConfidence = 0.75;
              return 3;
            }
            if (digitBestScore[7] > best1Score + 100) {
              SP.lastPixelDiag = `lowInk7keep: noSolidTop s7>>s1 s7=${digitBestScore[7].toFixed(0)} s1=${best1Score.toFixed(0)} s3=${digitBestScore[3].toFixed(0)} s9=${digitBestScore[9].toFixed(0)} ink=${inkCount} sig=${sigToCompactStr(sig)}`;
              const rawConf7lk: number = digitBestScore[7] / (SIG_LEN + 200);
              SP.lastConfidence = rawConf7lk > 1 ? 1 : (rawConf7lk < 0 ? 0 : rawConf7lk);
              return 7;
            }
            SP.lastPixelDiag = `lowInkFallback7→1: noSolidTop ink=${inkCount} topSolid=${topSolid7}/${topTotal7} topWide=${topWideRows7} s7=${digitBestScore[7].toFixed(0)} s1=${best1Score.toFixed(0)}`;
            const rawConf1: number = best1Score / (SIG_LEN + 200);
            SP.lastConfidence = rawConf1 > 1 ? 1 : (rawConf1 < 0 ? 0 : rawConf1);
            return 1;
          }
          const inkCols7: number[] = new Array<number>(SIG_COLS).fill(0);
          for (let i7: number = 0; i7 < sig.length; i7++) {
            if (sig[i7] === 1) { inkCols7[i7 % SIG_COLS]++; }
          }
          let nonZeroCols7: number = 0;
          let maxColInk7: number = 0;
          for (let ci7: number = 0; ci7 < SIG_COLS; ci7++) {
            if (inkCols7[ci7] > 0) { nonZeroCols7++; }
            if (inkCols7[ci7] > maxColInk7) { maxColInk7 = inkCols7[ci7]; }
          }
          if (nonZeroCols7 <= 6 && maxColInk7 >= inkCount * 0.20) {
            SP.lastPixelDiag = `lowInkFallback7→1: narrowCols=${nonZeroCols7} maxColInk=${maxColInk7} ink=${inkCount}`;
            const rawConf1: number = best1Score / (SIG_LEN + 200);
            SP.lastConfidence = rawConf1 > 1 ? 1 : (rawConf1 < 0 ? 0 : rawConf1);
            return 1;
          }
          const topRow7ms: number = Math.floor(SIG_ROWS * 0.10);
          const topEnd7ms: number = Math.floor(SIG_ROWS * 0.40);
          let firstC7ms: number = -1;
          let lastC7ms: number = -1;
          let allInc7ms: boolean = true;
          let allDec7ms: boolean = true;
          let prevC7ms: number = -1;
          for (let r7ms: number = topRow7ms; r7ms < topEnd7ms; r7ms++) {
            let sumC7ms: number = 0;
            let cntC7ms: number = 0;
            for (let c7ms: number = 0; c7ms < SIG_COLS; c7ms++) {
              if (sig[r7ms * SIG_COLS + c7ms] === 1) { sumC7ms += c7ms; cntC7ms++; }
            }
            if (cntC7ms > 0) {
              const center7ms: number = sumC7ms / cntC7ms;
              if (firstC7ms < 0) { firstC7ms = center7ms; }
              lastC7ms = center7ms;
              if (prevC7ms >= 0) {
                if (center7ms < prevC7ms - 0.5) { allInc7ms = false; }
                if (center7ms > prevC7ms + 0.5) { allDec7ms = false; }
              }
              prevC7ms = center7ms;
            }
          }
          if (firstC7ms >= 0 && lastC7ms >= 0) {
            const totalShift7ms: number = Math.abs(lastC7ms - firstC7ms);
            if ((allInc7ms || allDec7ms) && totalShift7ms >= SIG_COLS * 0.2 && digitBestScore[7] - best1Score < 100) {
              SP.lastPixelDiag = `lowInk7→1: monoShift=${totalShift7ms.toFixed(1)} inc=${allInc7ms} dec=${allDec7ms} ink=${inkCount} s7=${digitBestScore[7]} s1=${best1Score}`;
              const rawConf1ms: number = best1Score / (SIG_LEN + 200);
              SP.lastConfidence = rawConf1ms > 1 ? 1 : (rawConf1ms < 0 ? 0 : rawConf1ms);
              return 1;
            }
          }
        }
        const sigDump: string = sigToCompactStr(sig);
        SP.lastPixelDiag = `lowInk fallback: best=${lowBestDigit} score=${lowBestScore.toFixed(0)} recall=${lowBestRecall.toFixed(2)} gate=${lowMinScore} ink=${inkCount} [${stripDiag}] sig=${sigDump}`;
      } else {
        const topDigits81: number[] = [1, 2, 3, 4, 5, 6, 7, 8, 9];
        topDigits81.sort((a: number, b: number): number => digitBestScore[b] - digitBestScore[a]);
        let topStr81: string = '';
        for (let ti81: number = 0; ti81 < 3 && ti81 < topDigits81.length; ti81++) {
          topStr81 += `${topDigits81[ti81]}:${digitBestScore[topDigits81[ti81]].toFixed(0)} `;
        }
        SP.lastPixelDiag = `lowInk fallback: best=${lowBestDigit} score=${lowBestScore.toFixed(0)} recall=${lowBestRecall.toFixed(2)} gate=${lowMinScore} ink=${inkCount} top=[${topStr81}] sig=${sigToCompactStr(sig)}`;
      }
      const rawConf: number = lowBestScore / (SIG_LEN + 200);
      if (lowBestDigit === 3 && digitBestScore[8] > digitBestScore[3] - 60) {
        let luInk81: number = 0;
        for (let r81: number = Math.floor(SIG_ROWS * 0.15); r81 < Math.floor(SIG_ROWS * 0.45); r81++) {
          for (let c81: number = Math.floor(SIG_COLS * 0.05); c81 < Math.floor(SIG_COLS * 0.25); c81++) {
            if (sig[r81 * SIG_COLS + c81] === 1) { luInk81++; }
          }
        }
        let ldInk81: number = 0;
        for (let r82: number = Math.floor(SIG_ROWS * 0.60); r82 < Math.floor(SIG_ROWS * 0.90); r82++) {
          for (let c82: number = 0; c82 < Math.floor(SIG_COLS * 0.25); c82++) {
            if (sig[r82 * SIG_COLS + c82] === 1) { ldInk81++; }
          }
        }
        if (luInk81 >= 3 && ldInk81 >= 3) {
          SP.lastPixelDiag = `lowInk3→8(leftArcFrag lu=${luInk81} ld=${ldInk81}): s3=${digitBestScore[3].toFixed(0)} s8=${digitBestScore[8].toFixed(0)} ink=${inkCount}`;
          SP.lastConfidence = 0.60;
          return 8;
        }
      }
      SP.lastConfidence = rawConf > 1 ? 1 : (rawConf < 0 ? 0 : rawConf);
      return lowBestDigit;
    }
    SP.lastPixelDiag = `lowInk no1: best=${lowBestDigit} score=${lowBestScore.toFixed(0)} recall=${lowBestRecall.toFixed(2)} gate=${lowMinScore} ink=${inkCount} s1=${best1Score} thinOk=${detectThinOne(sig, inkCount) ? 1 : 0} looseOk=${detectLooseOne(sig, inkCount) ? 1 : 0}`;
    if (inkCount >= THIN1_MIN_INK_COUNT && inkCount < MIN_INK_COUNT_DIGIT1 * 2 &&
      best1Score >= Math.floor(SIG_LEN * 0.40) && detectLooseOne(sig, inkCount)) {
      const topRowNo1: number = Math.floor(SIG_ROWS * 0.10);
      const topEndNo1: number = Math.floor(SIG_ROWS * 0.30);
      let topMaxSpanNo1: number = 0;
      for (let rNo1: number = topRowNo1; rNo1 < topEndNo1; rNo1++) {
        let spanNo1: number = 0;
        let maxSpanNo1: number = 0;
        for (let cNo1: number = 0; cNo1 < SIG_COLS; cNo1++) {
          if (sig[rNo1 * SIG_COLS + cNo1] === 1) {
            spanNo1++;
            if (spanNo1 > maxSpanNo1) { maxSpanNo1 = spanNo1; }
          } else {
            spanNo1 = 0;
          }
        }
        if (maxSpanNo1 > topMaxSpanNo1) { topMaxSpanNo1 = maxSpanNo1; }
      }
      if (topMaxSpanNo1 < SIG_COLS * 0.6) {
        SP.lastPixelDiag = `lowInk no1→1(thin geo): topSpan=${topMaxSpanNo1} s1=${best1Score} ink=${inkCount}`;
        SP.lastConfidence = 0.50;
        return 1;
      }
    }
    if (lowBestDigit === 4 && isLikelyNot4(sig)) {
      let best1Score4: number = -100000;
      const tpls1c: DigitTemplate[] = SP.templatesByDigit[1];
      for (let ti: number = 0; ti < tpls1c.length; ti++) {
        if (ti % 30 === 0) { await yieldThread(); }
        const t: DigitTemplate = tpls1c[ti];
        if (!templateMatchesInkFilter(t, inkCount)) { continue; }
        const kb: Int8Array = t.keyBytes;
        let tp4: number = 0;
        for (let j: number = 0; j < sigInkLen; j++) {
          if (kb[sigInkPos[j]] === 1) { tp4++; }
        }
        const match4: number = SIG_LEN - sigInkLen - t.inkCount + 2 * tp4;
        const score: number = match4 - (SIG_LEN - match4) * TEMPLATE_MISMATCH_PENALTY;
        if (score > best1Score4) { best1Score4 = score; }
      }
      const geoGate3: number = Math.floor(SIG_LEN * 0.50);
      if (best1Score4 >= geoGate3) {
        SP.lastPixelDiag = `not4→1(no1path): score1=${best1Score4} ink=${inkCount}`;
        SP.lastConfidence = 0.50;
        return 1;
      }
    }
    SP.lastConfidence = 0;
    return 0;
  }
  const qHole: number = holeCenterRow(sig);

  const sigCentroidRow: number = inkCentroidRow(sig);
  const sigCentroidCol2: number = inkCentroidCol(sig);
  const sigTopBottom: number = topBottomInkRatio(sig);
  const sigHasHole: boolean = qHole >= 0;
  const sigLeftRight: number = sigComputeLeftRightRatio(sig);

  const digitBestScore: number[] = new Array<number>(10).fill(-100000);
  const digitBestIdx: number[] = new Array<number>(10).fill(-1);
  for (let d: number = 1; d <= 9; d++) {
    const tplsD: DigitTemplate[] = SP.templatesByDigit[d];
    for (let ti: number = 0; ti < tplsD.length; ti++) {
      if (ti % 30 === 0) { await yieldThread(); }
      const t: DigitTemplate = tplsD[ti];
      const kb: Int8Array = t.keyBytes;
      let tp: number = 0;
      for (let j: number = 0; j < sigInkLen; j++) {
        if (kb[sigInkPos[j]] === 1) { tp++; }
      }
      const match: number = SIG_LEN - sigInkLen - t.inkCount + 2 * tp;
      const recall: number = t.inkCount > 0 ? tp / t.inkCount : 0;
      const prec: number = inkCount > 0 ? tp / inkCount : 0;
      const f1: number = (recall + prec) > 0 ? (2 * recall * prec) / (recall + prec) : 0;
      const score: number = match - (SIG_LEN - match) * TEMPLATE_MISMATCH_PENALTY + f1 * TEMPLATE_F1_WEIGHT;
      if (score > digitBestScore[t.digit]) {
        digitBestScore[t.digit] = score;
        digitBestIdx[t.digit] = ti;
      }
    }
  }

  let bestDigit: number = 0;
  let bestScore: number = -100000;
  let secondDigit: number = 0;
  let secondScore: number = -100000;
  for (let d: number = 1; d <= 9; d++) {
    if (digitBestScore[d] > bestScore) {
      secondDigit = bestDigit; secondScore = bestScore;
      bestDigit = d; bestScore = digitBestScore[d];
    } else if (digitBestScore[d] > secondScore) {
      secondDigit = d; secondScore = digitBestScore[d];
    }
  }
  g_lastSecondDigit = secondDigit;
  g_lastSecondScore = secondScore;

  if (bestDigit === 1 && inkCount > 0) {
    const leftCol: number = Math.floor(SIG_COLS * 0.4);
    const midRow: number = Math.floor(SIG_ROWS * 0.35);
    let leftLowerInk: number = 0;
    for (let r2: number = midRow; r2 < SIG_ROWS; r2++) {
      for (let c2: number = 0; c2 < leftCol; c2++) {
        if (sig[r2 * SIG_COLS + c2] === 1) { leftLowerInk++; }
      }
    }
    if (leftLowerInk > inkCount * 0.18) {
      let bestNon1: number = 0;
      let bestNon1Score: number = -100000;
      for (let d: number = 2; d <= 9; d++) {
        if (digitBestScore[d] > bestNon1Score) { bestNon1Score = digitBestScore[d]; bestNon1 = d; }
      }
      if (bestNon1 > 0) {
        hilog.info(DOMAIN, TAG, 'digit1 left-lower-ink reject: lowerLeftInk=%{public}d/%{public}d(%.0f%%) => %{public}d',
          leftLowerInk, inkCount, leftLowerInk / inkCount * 100, bestNon1);
        bestDigit = bestNon1;
        bestScore = bestNon1Score;
        if (bestNon1 !== 7) { secondDigit = 7; secondScore = digitBestScore[7]; }
      }
    }
  }

  if (bestDigit === 1 && secondDigit === 7) {
    const topRow17: number = Math.floor(SIG_ROWS * 0.05);
    const topEnd17: number = Math.floor(SIG_ROWS * 0.30);
    let topMinC17: number = SIG_COLS;
    let topMaxC17: number = 0;
    let solidTopRows17: number = 0;
    for (let r: number = topRow17; r < topEnd17; r++) {
      let inkInRow17: number = 0;
      for (let c: number = 0; c < SIG_COLS; c++) {
        if (sig[r * SIG_COLS + c] === 1) {
          inkInRow17++;
          if (c < topMinC17) { topMinC17 = c; }
          if (c > topMaxC17) { topMaxC17 = c; }
        }
      }
      if (inkInRow17 >= SIG_COLS * 0.4) { solidTopRows17++; }
    }
    const topSpan17: number = topMaxC17 >= topMinC17 ? topMaxC17 - topMinC17 + 1 : 0;
    if (topSpan17 >= SIG_COLS * 0.55 && solidTopRows17 >= 1) {
      bestDigit = 7;
      bestScore = digitBestScore[7];
    }
  }

  const rawConf: number = bestScore / (SIG_LEN + 200);
  SP.lastConfidence = rawConf > 1 ? 1 : (rawConf < 0 ? 0 : rawConf);

  if (bestDigit === 6 || bestDigit === 9) {
    const score6: number = digitBestScore[6];
    const score9: number = digitBestScore[9];
    const score5: number = digitBestScore[5];
    const scoreGap: number = Math.abs(score6 - score9);

    if (scoreGap >= DISAMBIG_SCORE_GAP_SKIP && !(bestDigit === 6 && score5 >= score6 - DISAMBIG_SCORE_GAP_SKIP)) {
      const r69skip: number = score6 > score9 ? 6 : 9;
      SP.lastPixelDiag = `69skip: s6=${score6.toFixed(0)} s9=${score9.toFixed(0)} gap=${scoreGap.toFixed(0)}>=${DISAMBIG_SCORE_GAP_SKIP} =>${r69skip}`;
      return r69skip;
    }
    if (bestDigit === 6 && score5 >= score6 - DISAMBIG_SCORE_GAP_SKIP && score9 < score5) {
      hilog.info(DOMAIN, TAG, '69skip: s6=%{public}.1f s5=%{public}.1f s9=%{public}.1f, 5/6 ambiguous, fall to 5/6 block', score6, score5, score9);
    } else if (scoreGap >= DISAMBIG_SCORE_GAP_SKIP) {
      const r69skip2: number = score6 > score9 ? 6 : 9;
      SP.lastPixelDiag = `69skip: s6=${score6.toFixed(0)} s9=${score9.toFixed(0)} s5=${score5.toFixed(0)} gap=${scoreGap.toFixed(0)}>=${DISAMBIG_SCORE_GAP_SKIP} =>${r69skip2}`;
      return r69skip2;
    }

    const iCentroid: number = sigCentroidRow;
    const ratio: number = sigTopBottom;
    const hogGrad: number = hogVerticalGradient(sig);
    const swRatio: number = strokeWidthRatio(sig);

    hilog.info(DOMAIN, TAG, '6/9消歧: score6=%{public}.1f score9=%{public}.1f gap=%{public}.1f qHole=%{public}.2f centroid=%{public}.2f topRatio=%{public}.2f hogGrad=%{public}.2f swRatio=%{public}.2f',
      score6, score9, scoreGap, qHole, iCentroid, ratio, hogGrad, swRatio);

    let vote6: number = 0;
    let vote9: number = 0;

    if (qHole >= 0) {
      if (qHole > SIG_ROWS / 2) { vote6 += DISAMBIG_HOLE_WEIGHT; } else { vote9 += DISAMBIG_HOLE_WEIGHT; }
    }
    if (iCentroid >= 0) {
      if (iCentroid > SIG_ROWS / 2) { vote6 += DISAMBIG_CENTROID_WEIGHT; } else { vote9 += DISAMBIG_CENTROID_WEIGHT; }
    }
    if (ratio > 0.5) { vote9 += DISAMBIG_TOP_RATIO_WEIGHT; } else { vote6 += DISAMBIG_TOP_RATIO_WEIGHT; }
    if (hogGrad > 0.5) { vote9 += DISAMBIG_HOG_WEIGHT; } else { vote6 += DISAMBIG_HOG_WEIGHT; }
    if (swRatio > 1.1) { vote9 += DISAMBIG_SW_WEIGHT; } else if (swRatio < 0.9) { vote6 += DISAMBIG_SW_WEIGHT; }
    if (score6 > score9 + 50) { vote6 += DISAMBIG_SCORE_WEIGHT; }
    else if (score9 > score6 + 50) { vote9 += DISAMBIG_SCORE_WEIGHT; }
    else if (score6 > score9) { vote6 += 1; }
    else { vote9 += 1; }

    const result69: number = vote6 === vote9 ? (score6 >= score9 ? 6 : 9) : (vote6 > vote9 ? 6 : 9);
    SP.lastPixelDiag = `69disambig: s6=${score6.toFixed(0)} s9=${score9.toFixed(0)} gap=${scoreGap.toFixed(0)} hole=${qHole.toFixed(1)} cent=${iCentroid.toFixed(1)} ratio=${ratio.toFixed(2)} hog=${hogGrad.toFixed(2)} sw=${swRatio.toFixed(2)} v6=${vote6} v9=${vote9} =>${result69} sig=${sigToCompactStr(sig)}`;
    hilog.info(DOMAIN, TAG, 'vote6=%{public}d vote9=%{public}d => %{public}d', vote6, vote9, result69);
    if (result69 === 9) { return 9; }
    if (result69 === 6 && score5 >= score6 - DISAMBIG_SCORE_GAP_SKIP) {
      hilog.info(DOMAIN, TAG, '6/9→6 but score5=%{public}.1f close to score6=%{public}.1f, fall to 5/6', score5, score6);
    } else {
      return result69;
    }
  }

  // 9/8 disambiguation
  if (bestDigit === 9 || bestDigit === 8) {
    const score9d: number = digitBestScore[9];
    const score8d: number = digitBestScore[8];
    const scoreGap98: number = score9d - score8d;
    const holes98: number = countHoles(sig);
    if (holes98 >= 2 && Math.abs(scoreGap98) < 200) {
      SP.lastPixelDiag = `9/8→8(holes=${holes98}): s9=${score9d.toFixed(0)} s8=${score8d.toFixed(0)} ink=${inkCount}`;
      const rawConf98h: number = score8d / (SIG_LEN + 200);
      SP.lastConfidence = rawConf98h > 1 ? 1 : (rawConf98h < 0 ? 0 : rawConf98h);
      return 8;
    }
    if (Math.abs(scoreGap98) < 150) {
      const midRow98: number = Math.floor(SIG_ROWS / 2);
      let botInk98: number = 0;
      let topInk98: number = 0;
      for (let r98: number = midRow98; r98 < SIG_ROWS; r98++) {
        for (let c98: number = 0; c98 < SIG_COLS; c98++) {
          if (sig[r98 * SIG_COLS + c98] === 1) { botInk98++; }
        }
      }
      for (let r98t: number = 0; r98t < midRow98; r98t++) {
        for (let c98t: number = 0; c98t < SIG_COLS; c98t++) {
          if (sig[r98t * SIG_COLS + c98t] === 1) { topInk98++; }
        }
      }
      const botRatio98: number = (topInk98 + botInk98) > 0 ? botInk98 / (topInk98 + botInk98) : 0.5;
      const midColL98: number = Math.floor(SIG_COLS * 0.25);
      const midColR98: number = Math.floor(SIG_COLS * 0.75);
      let midNarrow98: number = 0;
      for (let r98m: number = Math.floor(SIG_ROWS * 0.4); r98m < Math.floor(SIG_ROWS * 0.6); r98m++) {
        let rowInk98: number = 0;
        for (let c98m: number = midColL98; c98m < midColR98; c98m++) {
          if (sig[r98m * SIG_COLS + c98m] === 1) { rowInk98++; }
        }
        midNarrow98 += rowInk98;
      }
      const midNarrowR98: number = midNarrow98 / ((Math.floor(SIG_ROWS * 0.6) - Math.floor(SIG_ROWS * 0.4)) * (midColR98 - midColL98));
      if (botRatio98 > 0.42 && midNarrowR98 < 0.40) {
        SP.lastPixelDiag = `9/8→8: botR=${botRatio98.toFixed(2)} midNarrow=${midNarrowR98.toFixed(2)} s9=${score9d.toFixed(0)} s8=${score8d.toFixed(0)} ink=${inkCount}`;
        const rawConf98: number = score8d / (SIG_LEN + 200);
        SP.lastConfidence = rawConf98 > 1 ? 1 : (rawConf98 < 0 ? 0 : rawConf98);
        return 8;
      }
      if (botRatio98 < 0.35) {
        SP.lastPixelDiag = `9/8→9: botR=${botRatio98.toFixed(2)} s9=${score9d.toFixed(0)} s8=${score8d.toFixed(0)} ink=${inkCount}`;
        const rawConf98b: number = score9d / (SIG_LEN + 200);
        SP.lastConfidence = rawConf98b > 1 ? 1 : (rawConf98b < 0 ? 0 : rawConf98b);
        return 9;
      }
    }
  }

  // 2/8 disambiguation: a true 8 has two enclosed holes; a 2 has at most one
  // and carries a long flat baseline near the bottom.
  if (bestDigit === 8) {
    const score2d: number = digitBestScore[2];
    const score8d: number = digitBestScore[8];
    const holes28: number = countHoles(sig);
    const botTop28: number = Math.floor(SIG_ROWS * 0.72);
    const botEnd28: number = Math.floor(SIG_ROWS * 0.92);
    let maxSpan28: number = 0;
    for (let r28: number = botTop28; r28 < botEnd28; r28++) {
      let span28: number = 0;
      let rowMax28: number = 0;
      for (let c28: number = 0; c28 < SIG_COLS; c28++) {
        if (sig[r28 * SIG_COLS + c28] === 1) {
          span28++;
          if (span28 > rowMax28) { rowMax28 = span28; }
        } else {
          span28 = 0;
        }
      }
      if (rowMax28 > maxSpan28) { maxSpan28 = rowMax28; }
    }
    SP.lastPixelDiag = `2/8probe: s2=${score2d.toFixed(0)} s8=${score8d.toFixed(0)} holes=${holes28} base=${maxSpan28} ink=${inkCount}`;
    if (score8d - score2d < 250 && holes28 < 2 && maxSpan28 >= SIG_COLS * 0.55) {
      SP.lastPixelDiag = `2/8→2(holes=${holes28}): s2=${score2d.toFixed(0)} s8=${score8d.toFixed(0)} base=${maxSpan28} ink=${inkCount}`;
      const rawConf28: number = score2d / (SIG_LEN + 200);
      SP.lastConfidence = rawConf28 > 1 ? 1 : (rawConf28 < 0 ? 0 : rawConf28);
      return 2;
    }
  }

  // 5/6 disambiguation
  if (bestDigit === 5 || bestDigit === 6) {
    const score5: number = digitBestScore[5];
    const score6d: number = digitBestScore[6];
    const hole56: number = holeCenterRow(sig);
    let topInkCols56: number = 0;
    let botInkCols56: number = 0;
    for (let c: number = 0; c < SIG_COLS; c++) {
      let topHas: boolean = false;
      let botHas: boolean = false;
      for (let r: number = 0; r < SIG_ROWS / 2; r++) {
        if (sig[r * SIG_COLS + c] === 1) { topHas = true; }
      }
      for (let r2: number = Math.floor(SIG_ROWS / 2); r2 < SIG_ROWS; r2++) {
        if (sig[r2 * SIG_COLS + c] === 1) { botHas = true; }
      }
      if (topHas) { topInkCols56++; }
      if (botHas) { botInkCols56++; }
    }
    const rightColStart56: number = Math.floor(SIG_COLS * 0.65);
    let topRightInkRows56: number = 0;
    let botRightInkRows56: number = 0;
    const midRow56: number = Math.floor(SIG_ROWS * 0.45);
    for (let r56: number = 0; r56 < SIG_ROWS; r56++) {
      let hasRightInk: boolean = false;
      for (let c56: number = rightColStart56; c56 < SIG_COLS; c56++) {
        if (sig[r56 * SIG_COLS + c56] === 1) { hasRightInk = true; break; }
      }
      if (hasRightInk) {
        if (r56 < midRow56) { topRightInkRows56++; } else { botRightInkRows56++; }
      }
    }
    const topRightRatio56: number = topRightInkRows56 / midRow56;
    let hBarCols56: number = 0;
    const hBarRow56: number = Math.floor(SIG_ROWS * 0.15);
    for (let c56b: number = 0; c56b < SIG_COLS; c56b++) {
      if (sig[hBarRow56 * SIG_COLS + c56b] === 1) { hBarCols56++; }
    }
    if (topRightRatio56 >= 0.5 && hBarCols56 >= SIG_COLS * 0.3) {
      SP.lastPixelDiag = `5/6→5: topRightR=${topRightRatio56.toFixed(2)} hBar=${hBarCols56} hole=${hole56.toFixed(1)} topC=${topInkCols56} botC=${botInkCols56} s5=${score5.toFixed(0)} s6=${score6d.toFixed(0)}`;
      return 5;
    }
    if (hole56 >= 0 && hole56 < SIG_ROWS * 0.45 && topRightRatio56 < 0.35) {
      SP.lastPixelDiag = `5/6→6: hole=${hole56.toFixed(1)} topRightR=${topRightRatio56.toFixed(2)} hBar=${hBarCols56} s5=${score5.toFixed(0)} s6=${score6d.toFixed(0)}`;
      return 6;
    }
    if (botInkCols56 > topInkCols56 + 2 && topRightRatio56 < 0.35) {
      SP.lastPixelDiag = `5/6→6: botC=${botInkCols56}>topC=${topInkCols56}+2 topRightR=${topRightRatio56.toFixed(2)} s5=${score5.toFixed(0)} s6=${score6d.toFixed(0)}`;
      return 6;
    }
    const result56: number = score5 >= score6d ? 5 : 6;
    SP.lastPixelDiag = `5/6→${result56}: s5=${score5.toFixed(0)} s6=${score6d.toFixed(0)} hole=${hole56.toFixed(1)} topC=${topInkCols56} botC=${botInkCols56} topRightR=${topRightRatio56.toFixed(2)} hBar=${hBarCols56}`;
    return result56;
  }

  // 5/9 disambiguation
  if (bestDigit === 5 || bestDigit === 9) {
    const score5b: number = digitBestScore[5];
    const score9b: number = digitBestScore[9];
    const hole59: number = holeCenterRow(sig);
    if (hole59 >= 0 && hole59 < SIG_ROWS * 0.45) {
      return 9;
    }
    const botRow59: number = Math.floor(SIG_ROWS * 0.7);
    const endRow59: number = Math.floor(SIG_ROWS * 0.9);
    let botLeftInk59: number = 0;
    let botRightInk59: number = 0;
    for (let r: number = botRow59; r < endRow59; r++) {
      for (let c: number = 0; c < SIG_COLS / 2; c++) {
        if (sig[r * SIG_COLS + c] === 1) { botLeftInk59++; }
      }
      for (let c2: number = Math.floor(SIG_COLS / 2); c2 < SIG_COLS; c2++) {
        if (sig[r * SIG_COLS + c2] === 1) { botRightInk59++; }
      }
    }
    if (botLeftInk59 > botRightInk59 * 1.5) {
      return 5;
    }
    const topInkRatio59: number = topBottomInkRatio(sig);
    if (topInkRatio59 > 0.55) {
      return 9;
    }
    return score5b >= score9b ? 5 : 9;
  }

  // 5/8 disambiguation (log117): 5 and 8 are topologically similar in small
  // images. Key discriminators: 8 has a hole (enclosed region) while 5 does
  // not; 8 has roughly equal left/right ink in the middle band, while 5's
  // middle band ink is left-skewed; 8 has roughly equal top/bottom ink, while
  // 5 has more bottom ink. Affects tests 18 (7→8, 3→8), 32 (8↔5 ×3).
  if (bestDigit === 5 || bestDigit === 8) {
    const score5c: number = digitBestScore[5];
    const score8c: number = digitBestScore[8];
    const hole58: number = holeCenterRow(sig);
    if (hole58 >= 0) {
      SP.lastPixelDiag = `5/8→8(hole): s5=${score5c.toFixed(0)} s8=${score8c.toFixed(0)} holeRow=${hole58} ink=${inkCount}`;
      return 8;
    }
    const midTop58: number = Math.floor(SIG_ROWS * 0.3);
    const midBot58: number = Math.floor(SIG_ROWS * 0.7);
    let midLeftInk58: number = 0;
    let midRightInk58: number = 0;
    for (let r: number = midTop58; r < midBot58; r++) {
      for (let c: number = 0; c < SIG_COLS / 2; c++) {
        if (sig[r * SIG_COLS + c] === 1) { midLeftInk58++; }
      }
      for (let c2: number = Math.floor(SIG_COLS / 2); c2 < SIG_COLS; c2++) {
        if (sig[r * SIG_COLS + c2] === 1) { midRightInk58++; }
      }
    }
    const totalMid58: number = midLeftInk58 + midRightInk58;
    const leftMidRatio58: number = totalMid58 > 0 ? midLeftInk58 / totalMid58 : 0.5;
    if (leftMidRatio58 > 0.55) {
      return 5;
    }
    if (leftMidRatio58 < 0.48) {
      SP.lastPixelDiag = `5/8→8(lRatio=${leftMidRatio58.toFixed(2)}): s5=${score5c.toFixed(0)} s8=${score8c.toFixed(0)} ink=${inkCount}`;
      return 8;
    }
    SP.lastPixelDiag = `5/8→${score5c >= score8c ? 5 : 8}: lRatio=${leftMidRatio58.toFixed(2)} s5=${score5c.toFixed(0)} s8=${score8c.toFixed(0)} ink=${inkCount}`;
    return score5c >= score8c ? 5 : 8;
  }

  // 3/8 disambiguation
  if (bestDigit === 3 || bestDigit === 8) {
    const score3: number = digitBestScore[3];
    const score8: number = digitBestScore[8];
    if (Math.abs(score3 - score8) < 200) {
      g_lastSecondDigit = (bestDigit === 3) ? 8 : 3;
      g_lastSecondScore = (bestDigit === 3) ? score8 : score3;
    }
    const holes38: number = countHoles(sig);
    if (holes38 >= 2 && score8 > score3 - 150) {
      SP.lastPixelDiag = `3/8→8(holes=${holes38}): s3=${score3.toFixed(0)} s8=${score8.toFixed(0)} ink=${inkCount}`;
      return 8;
    }
    const midTop38: number = Math.floor(SIG_ROWS * 0.3);
    const midBot38: number = Math.floor(SIG_ROWS * 0.7);
    let leftInk38: number = 0;
    let rightInk38: number = 0;
    for (let r: number = midTop38; r < midBot38; r++) {
      for (let c: number = 0; c < SIG_COLS / 2; c++) {
        if (sig[r * SIG_COLS + c] === 1) { leftInk38++; }
      }
      for (let c2: number = Math.floor(SIG_COLS / 2); c2 < SIG_COLS; c2++) {
        if (sig[r * SIG_COLS + c2] === 1) { rightInk38++; }
      }
    }
    const leftRatio38: number = (leftInk38 + rightInk38) > 0 ? leftInk38 / (leftInk38 + rightInk38) : 0.5;
    const midTop38v: number = Math.floor(SIG_ROWS * 0.25);
    const midBot38v: number = Math.floor(SIG_ROWS * 0.75);
    const colLeft38: number = Math.floor(SIG_COLS * 0.10);
    const colRight38: number = Math.floor(SIG_COLS * 0.40);
    let leftVertRows38: number = 0;
    for (let r38v: number = midTop38v; r38v < midBot38v; r38v++) {
      let hasLeftInk38: boolean = false;
      for (let c38v: number = colLeft38; c38v < colRight38; c38v++) {
        if (sig[r38v * SIG_COLS + c38v] === 1) { hasLeftInk38 = true; break; }
      }
      if (hasLeftInk38) { leftVertRows38++; }
    }
    const leftVertR38: number = (midBot38v - midTop38v) > 0 ? leftVertRows38 / (midBot38v - midTop38v) : 0;
    const scoreGap38: number = score3 - score8;
    if (scoreGap38 > 80) {
      SP.lastPixelDiag = `3/8→3: leftR=${leftRatio38.toFixed(2)} lvR=${leftVertR38.toFixed(2)} s3=${score3.toFixed(0)} s8=${score8.toFixed(0)} ink=${inkCount}`;
      return 3;
    }
    if (-scoreGap38 > 80) {
      SP.lastPixelDiag = `3/8→8: leftR=${leftRatio38.toFixed(2)} lvR=${leftVertR38.toFixed(2)} s3=${score3.toFixed(0)} s8=${score8.toFixed(0)} ink=${inkCount}`;
      return 8;
    }
    if (leftRatio38 > 0.25 && leftVertR38 >= 0.50) {
      SP.lastPixelDiag = `3/8→8(left+vert): leftR=${leftRatio38.toFixed(2)} lvR=${leftVertR38.toFixed(2)} s3=${score3.toFixed(0)} s8=${score8.toFixed(0)} ink=${inkCount}`;
      return 8;
    }
    if (leftVertR38 >= 0.55) {
      SP.lastPixelDiag = `3/8→8(vert): leftR=${leftRatio38.toFixed(2)} lvR=${leftVertR38.toFixed(2)} s3=${score3.toFixed(0)} s8=${score8.toFixed(0)} ink=${inkCount}`;
      return 8;
    }
    const waistRowStart38: number = Math.floor(SIG_ROWS * 0.40);
    const waistRowEnd38: number = Math.floor(SIG_ROWS * 0.60);
    const waistColL38: number = Math.floor(SIG_COLS * 0.20);
    const waistColR38: number = Math.floor(SIG_COLS * 0.80);
    let waistInk38: number = 0;
    let waistTotal38: number = (waistRowEnd38 - waistRowStart38) * (waistColR38 - waistColL38);
    for (let rw38: number = waistRowStart38; rw38 < waistRowEnd38; rw38++) {
      for (let cw38: number = waistColL38; cw38 < waistColR38; cw38++) {
        if (sig[rw38 * SIG_COLS + cw38] === 1) { waistInk38++; }
      }
    }
    const waistR38: number = waistTotal38 > 0 ? waistInk38 / waistTotal38 : 0.5;
    const rightMidL38: number = Math.floor(SIG_COLS * 0.50);
    const rightMidR38: number = Math.floor(SIG_COLS * 0.85);
    let rightMidInk38: number = 0;
    let rightMidTotal38: number = (midBot38 - midTop38) * (rightMidR38 - rightMidL38);
    for (let rrm38: number = midTop38; rrm38 < midBot38; rrm38++) {
      for (let crm38: number = rightMidL38; crm38 < rightMidR38; crm38++) {
        if (sig[rrm38 * SIG_COLS + crm38] === 1) { rightMidInk38++; }
      }
    }
    const rightMidRatio38: number = rightMidTotal38 > 0 ? rightMidInk38 / rightMidTotal38 : 0;
    if (waistR38 < 0.28 && rightMidRatio38 > 0.25 && Math.abs(scoreGap38) < 50) {
      SP.lastPixelDiag = `3/8→8(waist=${waistR38.toFixed(2)} rmid=${rightMidRatio38.toFixed(2)}): s3=${score3.toFixed(0)} s8=${score8.toFixed(0)} ink=${inkCount}`;
      return 8;
    }
    SP.lastPixelDiag = `3/8→${score3 >= score8 ? 3 : 8}: leftR=${leftRatio38.toFixed(2)} lvR=${leftVertR38.toFixed(2)} waist=${waistR38.toFixed(2)} s3=${score3.toFixed(0)} s8=${score8.toFixed(0)} ink=${inkCount}`;
    if (Math.abs(scoreGap38) < 80) {
      SP.lastConfidence = 0.75;
    }
    return score3 >= score8 ? 3 : 8;
  }

  if (bestDigit === 2 || bestDigit === 8) {
    const score2: number = digitBestScore[2];
    const score8b: number = digitBestScore[8];
    const holes28o: number = countHoles(sig);
    const botTop28o: number = Math.floor(SIG_ROWS * 0.72);
    const botEnd28o: number = Math.floor(SIG_ROWS * 0.92);
    let maxSpan28o: number = 0;
    for (let r28o: number = botTop28o; r28o < botEnd28o; r28o++) {
      let span28o: number = 0;
      let rowMax28o: number = 0;
      for (let c28o: number = 0; c28o < SIG_COLS; c28o++) {
        if (sig[r28o * SIG_COLS + c28o] === 1) {
          span28o++;
          if (span28o > rowMax28o) { rowMax28o = span28o; }
        } else {
          span28o = 0;
        }
      }
      if (rowMax28o > maxSpan28o) { maxSpan28o = rowMax28o; }
    }
    const midTop28: number = Math.floor(SIG_ROWS * 0.3);
    const midBot28: number = Math.floor(SIG_ROWS * 0.7);
    let leftInk28: number = 0;
    let rightInk28: number = 0;
    for (let r: number = midTop28; r < midBot28; r++) {
      for (let c: number = 0; c < SIG_COLS / 2; c++) {
        if (sig[r * SIG_COLS + c] === 1) { leftInk28++; }
      }
      for (let c2: number = Math.floor(SIG_COLS / 2); c2 < SIG_COLS; c2++) {
        if (sig[r * SIG_COLS + c2] === 1) { rightInk28++; }
      }
    }
    const leftRatio28: number = (leftInk28 + rightInk28) > 0 ? leftInk28 / (leftInk28 + rightInk28) : 0.5;
    SP.lastPixelDiag = `2/8old: s2=${score2.toFixed(0)} s8=${score8b.toFixed(0)} holes=${holes28o} base=${maxSpan28o} lRatio=${leftRatio28.toFixed(2)} ink=${inkCount}`;
    if (holes28o >= 2 && leftRatio28 > 0.40) {
      SP.lastConfidence = 0.75;
      return 8;
    }
    if (bestDigit === 2) {
      SP.lastConfidence = 0.70;
      return 2;
    }
    SP.lastConfidence = 0.70;
    return score2 >= score8b ? 2 : 8;
  }

  if (bestDigit === 4 || bestDigit === 5) {
    hilog.info(DOMAIN, TAG, 'DBG_45BLOCK: bestDigit=%{public}d s4=%{public}.0f s5=%{public}.0f', bestDigit, digitBestScore[4], digitBestScore[5]);
    const score4: number = digitBestScore[4];
    const score5: number = digitBestScore[5];
    if (score4 > score5) {
      const botTop41: number = Math.floor(SIG_ROWS * 0.50);
      let colSum41: number = 0;
      let inkCnt41: number = 0;
      for (let r: number = botTop41; r < SIG_ROWS; r++) {
        for (let c: number = 0; c < SIG_COLS; c++) {
          if (sig[r * SIG_COLS + c] === 1) { colSum41 += c; inkCnt41++; }
        }
      }
      const colCentroid41: number = inkCnt41 > 0 ? colSum41 / inkCnt41 : SIG_COLS / 2;
      if (colCentroid41 > SIG_COLS * 0.55) {
        const urTop41: number = Math.floor(SIG_ROWS * 0.05);
        const urBot41: number = Math.floor(SIG_ROWS * 0.40);
        const urLeft41: number = Math.floor(SIG_COLS * 0.50);
        let urInk41: number = 0;
        let urTotal41: number = 0;
        for (let r: number = urTop41; r < urBot41; r++) {
          for (let c: number = urLeft41; c < SIG_COLS; c++) {
            urTotal41++;
            if (sig[r * SIG_COLS + c] === 1) { urInk41++; }
          }
        }
        const urRatio41: number = urTotal41 > 0 ? urInk41 / urTotal41 : 0;
        if (urRatio41 > 0.25) {
          SP.lastPixelDiag = `4/5→4(urInk): colCent=${colCentroid41.toFixed(1)} urR=${urRatio41.toFixed(2)} s4=${score4.toFixed(0)} s5=${score5.toFixed(0)}`;
          return 4;
        }
        const score1check: number = digitBestScore[1];
        SP.lastPixelDiag = `4/5→1: colCent=${colCentroid41.toFixed(1)} urR=${urRatio41.toFixed(2)} s4=${score4.toFixed(0)} s5=${score5.toFixed(0)} s1=${score1check.toFixed(0)}`;
        SP.lastConfidence = score1check > 0 ? Math.min(score1check / (SIG_LEN + 200), 1) : 0.55;
        return 1;
      }
      SP.lastPixelDiag = `4/5→4: s4=${score4.toFixed(0)}>s5=${score5.toFixed(0)} colCent=${colCentroid41.toFixed(1)}`;
      return 4;
    }
    const topRow45: number = Math.floor(SIG_ROWS * 0.05);
    const topEnd45: number = Math.floor(SIG_ROWS * 0.30);
    let topSolidRows45: number = 0;
    for (let r: number = topRow45; r < topEnd45; r++) {
      let inkCols45: number = 0;
      for (let c: number = 0; c < SIG_COLS; c++) {
        if (sig[r * SIG_COLS + c] === 1) { inkCols45++; }
      }
      if (inkCols45 >= SIG_COLS * 0.6) { topSolidRows45++; }
    }
    if (topSolidRows45 >= 2) {
      SP.lastPixelDiag = `4/5→5: topSolid=${topSolidRows45} s4=${score4.toFixed(0)} s5=${score5.toFixed(0)}`;
      return 5;
    }
    const botTop41b: number = Math.floor(SIG_ROWS * 0.50);
    let colSum41b: number = 0;
    let inkCnt41b: number = 0;
    for (let r2: number = botTop41b; r2 < SIG_ROWS; r2++) {
      for (let c2: number = 0; c2 < SIG_COLS; c2++) {
        if (sig[r2 * SIG_COLS + c2] === 1) { colSum41b += c2; inkCnt41b++; }
      }
    }
    const colCentroid41b: number = inkCnt41b > 0 ? colSum41b / inkCnt41b : SIG_COLS / 2;
    if (colCentroid41b > SIG_COLS * 0.55) {
      const score1check2: number = digitBestScore[1];
      SP.lastPixelDiag = `4/5→1b: colCent=${colCentroid41b.toFixed(1)} s4=${score4.toFixed(0)} s5=${score5.toFixed(0)} s1=${score1check2.toFixed(0)}`;
      SP.lastConfidence = score1check2 > 0 ? Math.min(score1check2 / (SIG_LEN + 200), 1) : 0.55;
      return 1;
    }
    SP.lastPixelDiag = `4/5→4: topSolid=${topSolidRows45} s4=${score4.toFixed(0)} s5=${score5.toFixed(0)} colCent=${colCentroid41b.toFixed(1)}`;
    return 4;
  }

  // 1/4 disambiguation: Digit 1 with a serif or slanted top can be
  // misrecognized as 4. Two structural checks:
  // (a) avg row width: 1 has narrow vertical stroke (≤6px), 4 has wider structure
  // (b) cross-stroke detection: 4 has a continuous horizontal stroke in the
  //     middle band (40-65% down); 1 does not. A serif-1 may have wide ink
  //     in the upper portion but never a continuous mid-band cross-stroke.
  let flipped4to1ByStructure: boolean = false;
  if (bestDigit === 4) {
    const score4b: number = digitBestScore[4];
    const score1b: number = digitBestScore[1];
    {
      const midTop14: number = Math.floor(SIG_ROWS * 0.25);
      const midBot14: number = Math.floor(SIG_ROWS * 0.75);
      let totalRowWidth14: number = 0;
      let rowCount14: number = 0;
      for (let r: number = midTop14; r < midBot14; r++) {
        let minC: number = SIG_COLS;
        let maxC: number = -1;
        for (let c: number = 0; c < SIG_COLS; c++) {
          if (sig[r * SIG_COLS + c] === 1) {
            if (c < minC) { minC = c; }
            if (c > maxC) { maxC = c; }
          }
        }
        if (maxC >= minC) { totalRowWidth14 += maxC - minC + 1; rowCount14++; }
      }
      const avgRowWidth14: number = rowCount14 > 0 ? totalRowWidth14 / rowCount14 : 0;
      if (avgRowWidth14 <= 6) {
        SP.lastPixelDiag = `4→1: avgRowW=${avgRowWidth14.toFixed(1)} s4=${score4b} s1=${score1b}`;
        bestDigit = 1;
        bestScore = score1b > 0 ? score1b : score4b;
        flipped4to1ByStructure = true;
      } else {
        const crossTop14: number = Math.floor(SIG_ROWS * 0.40);
        const crossBot14: number = Math.floor(SIG_ROWS * 0.65);
        let hasMidCross14: boolean = false;
        let maxMidSpan14: number = 0;
        for (let r: number = crossTop14; r < crossBot14; r++) {
          let span14: number = 0;
          let maxSpan14: number = 0;
          for (let c: number = 0; c < SIG_COLS; c++) {
            if (sig[r * SIG_COLS + c] === 1) {
              span14++;
              if (span14 > maxSpan14) { maxSpan14 = span14; }
            } else {
              span14 = 0;
            }
          }
          if (maxSpan14 > maxMidSpan14) { maxMidSpan14 = maxSpan14; }
          if (maxSpan14 >= SIG_COLS * 0.40) { hasMidCross14 = true; break; }
        }
        if (!hasMidCross14) {
          SP.lastPixelDiag = `4→1: avgRowW=${avgRowWidth14.toFixed(1)} noMidCross(maxSpan=${maxMidSpan14}) s4=${score4b} s1=${score1b}`;
          bestDigit = 1;
          bestScore = score1b > 0 ? score1b : score4b;
          flipped4to1ByStructure = true;
        } else {
          let widestRow14: number = -1;
          let widestWidth14: number = 0;
          for (let r2: number = 0; r2 < SIG_ROWS; r2++) {
            let minCw: number = SIG_COLS;
            let maxCw: number = -1;
            for (let cw: number = 0; cw < SIG_COLS; cw++) {
              if (sig[r2 * SIG_COLS + cw] === 1) {
                if (cw < minCw) { minCw = cw; }
                if (cw > maxCw) { maxCw = cw; }
              }
            }
            const rowW14: number = maxCw >= minCw ? maxCw - minCw + 1 : 0;
            if (rowW14 > widestWidth14) { widestWidth14 = rowW14; widestRow14 = r2; }
          }
          const widestRowRatio14: number = widestRow14 >= 0 ? widestRow14 / SIG_ROWS : 0.5;
          if (widestRowRatio14 < 0.35) {
            SP.lastPixelDiag = `4→1: topWidest row=${widestRow14}(${widestRowRatio14.toFixed(2)}) w=${widestWidth14} s4=${score4b} s1=${score1b}`;
            bestDigit = 1;
            bestScore = score1b > 0 ? score1b : score4b;
            flipped4to1ByStructure = true;
          }
        }
      }
    }
  }

  // 1→4 disambiguation: Serif "4" with a narrow vertical stem can be
  // misrecognized as "1". Key discriminator: "4" has a diagonal arm from
  // top-right to mid-left, creating top-right ink that "1" lacks.
  // Also "4" has a horizontal cross-stroke in the lower half.
  // Skip if we already flipped 4→1 via structural checks (no mid-band cross-stroke).
  if (bestDigit === 1 && !flipped4to1ByStructure) {
    const score1c: number = digitBestScore[1];
    const score4d: number = digitBestScore[4];
    if (score4d > 0 && score4d >= score1c * 0.75) {
      const midTop14b: number = Math.floor(SIG_ROWS * 0.15);
      const midBot14b: number = Math.floor(SIG_ROWS * 0.45);
      let topRightInk14: number = 0;
      let topLeftInk14: number = 0;
      for (let r: number = midTop14b; r < midBot14b; r++) {
        for (let c: number = 0; c < SIG_COLS; c++) {
          if (sig[r * SIG_COLS + c] === 1) {
            if (c >= SIG_COLS / 2) { topRightInk14++; } else { topLeftInk14++; }
          }
        }
      }
      const crossTop14: number = Math.floor(SIG_ROWS * 0.55);
      const crossBot14: number = Math.floor(SIG_ROWS * 0.75);
      let crossInk14: number = 0;
      let crossCols14: number = 0;
      for (let r2: number = crossTop14; r2 < crossBot14; r2++) {
        let minC2: number = SIG_COLS;
        let maxC2: number = -1;
        for (let c2: number = 0; c2 < SIG_COLS; c2++) {
          if (sig[r2 * SIG_COLS + c2] === 1) {
            if (c2 < minC2) { minC2 = c2; }
            if (c2 > maxC2) { maxC2 = c2; }
          }
        }
        if (maxC2 >= minC2) { crossCols14 += maxC2 - minC2 + 1; }
        for (let c3: number = 0; c3 < SIG_COLS; c3++) {
          if (sig[r2 * SIG_COLS + c3] === 1) { crossInk14++; }
        }
      }
      if (topRightInk14 >= SIG_COLS * 0.3 && crossCols14 >= SIG_COLS * 0.5) {
        SP.lastPixelDiag = `1→4: topR=${topRightInk14} cross=${crossCols14} s1=${score1c} s4=${score4d}`;
        bestDigit = 4;
        bestScore = score4d;
      }
    }
  }

  // 4/6 disambiguation (log117): Digit 4 with thick strokes can be
  // misrecognized as 6. Key discriminator: 4 has no enclosed hole, 6 has one.
  // Also 6 has more ink in the bottom half, 4 has more in the top half.
  // Affects tests 23,29 (R8C4: got=6 want=4).
  if (bestDigit === 6) {
    const score6b: number = digitBestScore[6];
    const score4c: number = digitBestScore[4];
    if (score4c > 0) {
      const hole46: number = holeCenterRow(sig);
      if (hole46 < 0) {
        const topRatio46: number = topBottomInkRatio(sig);
        if (topRatio46 > 0.5) {
          SP.lastPixelDiag = `6→4: noHole topRatio=${topRatio46.toFixed(2)} s6=${score6b} s4=${score4c}`;
          bestDigit = 4;
          bestScore = score4c;
        }
      }
    }
  }

  // 1/8 and 1/7 disambiguation (log117): A very faint digit can collapse
  // into a narrow vertical stroke after thresholding, causing misrecognition
  // as "1". Key discriminators:
  //   - 8 has ink on both left and right sides in the middle band; 1 is narrow
  //   - 7 has a wide top bar; 1 does not
  // Affects test 25 (R3C3: got=1 want=8; R9C8: got=1 want=7).
  if (bestDigit === 1) {
    const score1c: number = digitBestScore[1];
    const score8d: number = digitBestScore[8];
    const score7d: number = digitBestScore[7];
    const score6d: number = digitBestScore[6];
    if (score6d > 0 && score6d > score1c + 50) {
      const botRow16: number = Math.floor(SIG_ROWS * 0.6);
      const botEnd16: number = Math.floor(SIG_ROWS * 0.95);
      let botRowWidth16: number = 0;
      let botRowCount16: number = 0;
      for (let r: number = botRow16; r < botEnd16; r++) {
        let minC16: number = SIG_COLS;
        let maxC16: number = -1;
        for (let c: number = 0; c < SIG_COLS; c++) {
          if (sig[r * SIG_COLS + c] === 1) {
            if (c < minC16) { minC16 = c; }
            if (c > maxC16) { maxC16 = c; }
          }
        }
        if (maxC16 >= minC16) { botRowWidth16 += maxC16 - minC16 + 1; botRowCount16++; }
      }
      const avgBotWidth16: number = botRowCount16 > 0 ? botRowWidth16 / botRowCount16 : 0;
      if (avgBotWidth16 > SIG_COLS * 0.35) {
        SP.lastPixelDiag = `1→6: avgBotW=${avgBotWidth16.toFixed(1)} s1=${score1c} s6=${score6d}`;
        bestDigit = 6;
        bestScore = score6d;
      }
    }
    const midTop1: number = Math.floor(SIG_ROWS * 0.3);
    const midBot1: number = Math.floor(SIG_ROWS * 0.7);
    let midLeft1: number = 0;
    let midRight1: number = 0;
    for (let r: number = midTop1; r < midBot1; r++) {
      for (let c: number = 0; c < SIG_COLS / 2; c++) {
        if (sig[r * SIG_COLS + c] === 1) { midLeft1++; }
      }
      for (let c2: number = Math.floor(SIG_COLS / 2); c2 < SIG_COLS; c2++) {
        if (sig[r * SIG_COLS + c2] === 1) { midRight1++; }
      }
    }
    const totalMid1: number = midLeft1 + midRight1;
    // Check 1→8: if middle band has balanced ink on both sides.
    // No score-gap gate: faint digits collapse to thin strokes that
    // score very high as "1" but structurally resemble 8 when ink is
    // distributed on both sides.
    if (score8d > 0 && totalMid1 > 0) {
      const leftRatio1: number = midLeft1 / totalMid1;
      if (leftRatio1 > 0.3 && leftRatio1 < 0.7 && midLeft1 > 3 && midRight1 > 3) {
        SP.lastPixelDiag = `1→8: midL=${midLeft1} midR=${midRight1} lr=${leftRatio1.toFixed(2)} s1=${score1c} s8=${score8d}`;
        bestDigit = 8;
        bestScore = score8d;
      }
    }
    // Check 1→7: if top area has a wide horizontal bar.
    // No score-gap gate for the same reason as 1→8.
    if (bestDigit === 1 && score7d > 0) {
      const topRow1: number = Math.floor(SIG_ROWS * 0.05);
      const topEnd1: number = Math.floor(SIG_ROWS * 0.25);
      let topMinC1: number = SIG_COLS;
      let topMaxC1: number = 0;
      let solidTopRows1: number = 0;
      for (let r: number = topRow1; r < topEnd1; r++) {
        let inkInRow1: number = 0;
        let rMinC: number = SIG_COLS;
        let rMaxC: number = 0;
        for (let c: number = 0; c < SIG_COLS; c++) {
          if (sig[r * SIG_COLS + c] === 1) {
            inkInRow1++;
            if (c < rMinC) { rMinC = c; }
            if (c > rMaxC) { rMaxC = c; }
          }
        }
        const rowSpan1: number = rMaxC >= rMinC ? rMaxC - rMinC + 1 : 0;
        if (inkInRow1 >= SIG_COLS * 0.4 && rowSpan1 >= SIG_COLS * 0.5) { solidTopRows1++; }
        if (rMaxC >= rMinC) {
          if (rMinC < topMinC1) { topMinC1 = rMinC; }
          if (rMaxC > topMaxC1) { topMaxC1 = rMaxC; }
        }
      }
      const topSpan1: number = topMaxC1 >= topMinC1 ? topMaxC1 - topMinC1 + 1 : 0;
      if (topSpan1 >= SIG_COLS * 0.6 && solidTopRows1 >= 2) {
        SP.lastPixelDiag = `1→7: topSpan=${topSpan1} solidTop=${solidTopRows1} s1=${score1c} s7=${score7d}`;
        bestDigit = 7;
        bestScore = score7d;
      }
    }
  }

  // 7/1 disambiguation: only check if 7 might actually be 1 (never flip 1→7)
  if (bestDigit === 7) {
    const score7: number = digitBestScore[7];
    const score1: number = digitBestScore[1];
    if (score1 > 0) {
      const midTop71: number = Math.floor(SIG_ROWS * 0.30);
      const midBot71: number = Math.floor(SIG_ROWS * 0.70);
      let totalRowWidth71: number = 0;
      let rowCount71: number = 0;
      for (let r: number = midTop71; r < midBot71; r++) {
        let minC: number = SIG_COLS;
        let maxC: number = -1;
        for (let c: number = 0; c < SIG_COLS; c++) {
          if (sig[r * SIG_COLS + c] === 1) {
            if (c < minC) { minC = c; }
            if (c > maxC) { maxC = c; }
          }
        }
        if (maxC >= minC) { totalRowWidth71 += maxC - minC + 1; rowCount71++; }
      }
      const avgRowWidth71: number = rowCount71 > 0 ? totalRowWidth71 / rowCount71 : 0;
      if (avgRowWidth71 > 8 && inkCount > 200) {
        SP.lastPixelDiag = `7→1: avgRowW=${avgRowWidth71.toFixed(1)} ink=${inkCount} s7=${score7} s1=${score1}`;
        bestDigit = 1;
        bestScore = score1;
      }
    }
    if (bestDigit === 7) {
      const topRow71: number = Math.floor(SIG_ROWS * 0.10);
      const topEnd71: number = Math.floor(SIG_ROWS * 0.30);
      let topMinC71: number = SIG_COLS;
      let topMaxC71: number = 0;
      for (let r: number = topRow71; r < topEnd71; r++) {
        for (let c: number = 0; c < SIG_COLS; c++) {
          if (sig[r * SIG_COLS + c] === 1) {
            if (c < topMinC71) { topMinC71 = c; }
            if (c > topMaxC71) { topMaxC71 = c; }
          }
        }
      }
      const topSpan71: number = topMaxC71 >= topMinC71 ? topMaxC71 - topMinC71 + 1 : 0;
      if (topSpan71 >= SIG_COLS * 0.6) {
        let solidTopRows71: number = 0;
        for (let r: number = topRow71; r < topEnd71; r++) {
          let inkInRow71: number = 0;
          let rMinC71: number = SIG_COLS;
          let rMaxC71: number = -1;
          for (let c: number = 0; c < SIG_COLS; c++) {
            if (sig[r * SIG_COLS + c] === 1) {
              inkInRow71++;
              if (c < rMinC71) { rMinC71 = c; }
              if (c > rMaxC71) { rMaxC71 = c; }
            }
          }
          const rowSpan71: number = rMaxC71 >= rMinC71 ? rMaxC71 - rMinC71 + 1 : 0;
          if (inkInRow71 >= SIG_COLS * 0.5 && rowSpan71 >= SIG_COLS * 0.5) { solidTopRows71++; }
        }
        if (solidTopRows71 >= 2 && score7 >= score1) {
          let firstCenter71m: number = -1;
          let lastCenter71m: number = -1;
          let allIncreasing71m: boolean = true;
          let allDecreasing71m: boolean = true;
          let prevCenter71m: number = -1;
          for (let r: number = topRow71; r < topEnd71; r++) {
            let sumC71m: number = 0;
            let cntC71m: number = 0;
            for (let c: number = 0; c < SIG_COLS; c++) {
              if (sig[r * SIG_COLS + c] === 1) { sumC71m += c; cntC71m++; }
            }
            if (cntC71m > 0) {
              const center71m: number = sumC71m / cntC71m;
              if (firstCenter71m < 0) { firstCenter71m = center71m; }
              lastCenter71m = center71m;
              if (prevCenter71m >= 0) {
                if (center71m < prevCenter71m - 0.5) { allIncreasing71m = false; }
                if (center71m > prevCenter71m + 0.5) { allDecreasing71m = false; }
              }
              prevCenter71m = center71m;
            }
          }
          if (firstCenter71m >= 0 && lastCenter71m >= 0) {
            const totalShift71m: number = Math.abs(lastCenter71m - firstCenter71m);
            const shiftNeed71m: number = score7 - score1 >= 50 ? SIG_COLS * 0.35 : SIG_COLS * 0.25;
            if ((allIncreasing71m || allDecreasing71m) && totalShift71m >= shiftNeed71m && inkCount < 250 && score7 - score1 < 100) {
              SP.lastPixelDiag = `7→1: monoShift=${totalShift71m.toFixed(1)} inc=${allIncreasing71m} dec=${allDecreasing71m} ink=${inkCount} s7=${score7} s1=${score1}`;
              return 1;
            }
          }
          const footTop71: number = Math.floor(SIG_ROWS * 0.70);
          const footBot71: number = Math.floor(SIG_ROWS * 0.95);
          let footWideRows71: number = 0;
          let footTotalRows71: number = 0;
          for (let r: number = footTop71; r < footBot71; r++) {
            let fMinC71: number = SIG_COLS;
            let fMaxC71: number = -1;
            for (let c: number = 0; c < SIG_COLS; c++) {
              if (sig[r * SIG_COLS + c] === 1) {
                if (c < fMinC71) { fMinC71 = c; }
                if (c > fMaxC71) { fMaxC71 = c; }
              }
            }
            if (fMaxC71 >= fMinC71) {
              const fSpan71: number = fMaxC71 - fMinC71 + 1;
              footTotalRows71++;
              if (fSpan71 >= 5) { footWideRows71++; }
            }
          }
          if (footWideRows71 >= 4 && footTotalRows71 >= 4 && inkCount < 250) {
            const gap71m: number = score7 - score1;
            const shift71m: number = firstCenter71m >= 0 && lastCenter71m >= 0 ? Math.abs(lastCenter71m - firstCenter71m) : 99;
            const mono7ish71m: boolean = (allIncreasing71m || allDecreasing71m) && shift71m >= SIG_COLS * 0.25;
            if (gap71m < 50 || (gap71m < 100 && !mono7ish71m)) {
              SP.lastPixelDiag = `7→1: footSerif wide=${footWideRows71}/${footTotalRows71} ink=${inkCount} s7=${score7} s1=${score1}`;
              return 1;
            }
          }
          SP.lastPixelDiag = `71m no-flip: shift=${firstCenter71m >= 0 && lastCenter71m >= 0 ? Math.abs(lastCenter71m - firstCenter71m).toFixed(1) : 'x'} inc=${allIncreasing71m} dec=${allDecreasing71m} footWide=${footWideRows71}/${footTotalRows71} ink=${inkCount} s7=${score7} s1=${score1}`;
          return 7;
        }
        if (solidTopRows71 >= 2 && score1 > score7) {
          SP.lastPixelDiag = `7→1: solidTop=${solidTopRows71} but s1=${score1}>s7=${score7} topSpan=${topSpan71}`;
          return 1;
        }
      }
      const topRow71s: number = Math.floor(SIG_ROWS * 0.10);
      const topEnd71s: number = Math.floor(SIG_ROWS * 0.40);
      let prevCenter71: number = -1;
      let monotonicShift71: number = 0;
      let shiftRows71: number = 0;
      for (let r: number = topRow71s; r < topEnd71s; r++) {
        let sumC71: number = 0;
        let cntC71: number = 0;
        for (let c: number = 0; c < SIG_COLS; c++) {
          if (sig[r * SIG_COLS + c] === 1) { sumC71 += c; cntC71++; }
        }
        if (cntC71 > 0) {
          const center71: number = sumC71 / cntC71;
          if (prevCenter71 >= 0) {
            const diff71: number = center71 - prevCenter71;
            if (Math.abs(diff71) >= 1) {
              monotonicShift71 += diff71;
              shiftRows71++;
            }
          }
          prevCenter71 = center71;
        }
      }
      const avgShift71: number = shiftRows71 > 0 ? Math.abs(monotonicShift71) / shiftRows71 : 0;
      if (shiftRows71 >= 3 && avgShift71 >= 1.5 && inkCount < 250 && score7 - score1 < 100) {
        SP.lastPixelDiag = `7→1: slanted topShift=${monotonicShift71.toFixed(1)} avg=${avgShift71.toFixed(1)} rows=${shiftRows71} ink=${inkCount} s7=${score7} s1=${score1}`;
        return 1;
      }
      // No solid top bar + score very close → might be 1 not 7
      const botRow71: number = Math.floor(SIG_ROWS * 0.60);
      const botEnd71: number = Math.floor(SIG_ROWS * 0.85);
      let botMinC71: number = SIG_COLS;
      let botMaxC71: number = 0;
      for (let r: number = botRow71; r < botEnd71; r++) {
        for (let c: number = 0; c < SIG_COLS; c++) {
          if (sig[r * SIG_COLS + c] === 1) {
            if (c < botMinC71) { botMinC71 = c; }
            if (c > botMaxC71) { botMaxC71 = c; }
          }
        }
      }
      const botSpan71: number = botMaxC71 >= botMinC71 ? botMaxC71 - botMinC71 + 1 : 0;
      if (botSpan71 <= 6 && topSpan71 < SIG_COLS * 0.6) {
        SP.lastPixelDiag = `7→1: botSpan=${botSpan71} topSpan=${topSpan71} s7=${score7} s1=${score1}`;
        return 1;
      }
      if (inkCount < 200 && score1 > 0) {
        const inkCols71: number[] = new Array<number>(SIG_COLS).fill(0);
        for (let i71: number = 0; i71 < sig.length; i71++) {
          if (sig[i71] === 1) { inkCols71[i71 % SIG_COLS]++; }
        }
        let nonZeroCols71: number = 0;
        let maxColInk71: number = 0;
        for (let ci71: number = 0; ci71 < SIG_COLS; ci71++) {
          if (inkCols71[ci71] > 0) { nonZeroCols71++; }
          if (inkCols71[ci71] > maxColInk71) { maxColInk71 = inkCols71[ci71]; }
        }
        if (nonZeroCols71 <= 5 && maxColInk71 >= inkCount * 0.25) {
          SP.lastPixelDiag = `7→1: narrowCols=${nonZeroCols71} maxColInk=${maxColInk71} ink=${inkCount} s7=${score7} s1=${score1}`;
          return 1;
        }
      }
    }
    }


  if (qHole >= 0 && bestScore >= MIN_DIGIT_SCORE && secondDigit > 0) {
    const halfRow: number = SIG_ROWS / 2;
    const halfOf: (h: number) => number = (h: number) => (h < 0 ? 0 : (h <= halfRow ? 1 : 2));
    const bh: number = halfOf(SP.holeRows[digitBestIdx[bestDigit]]);
    const sh: number = halfOf(SP.holeRows[digitBestIdx[secondDigit]]);
    if (bh !== 0 && sh !== 0 && bh !== sh) {
      const qh: number = halfOf(qHole);
      if (qh !== 0 && qh === sh) { bestDigit = secondDigit; }
    }
  }

  if (bestScore >= MIN_DIGIT_SCORE) {
    if (bestDigit === 4 && isLikelyNot4(sig)) {
      const scoreGap41: number = digitBestScore[4] - digitBestScore[1];
      if (scoreGap41 < 100) {
        let best1Score3: number = -100000;
        const tpls1d: DigitTemplate[] = SP.templatesByDigit[1];
        for (let ti: number = 0; ti < tpls1d.length; ti++) {
          if (ti % 30 === 0) { await yieldThread(); }
          const t: DigitTemplate = tpls1d[ti];
          if (!templateMatchesInkFilter(t, inkCount)) { continue; }
          const kb: Int8Array = t.keyBytes;
          let tp3: number = 0;
          for (let j: number = 0; j < sigInkLen; j++) {
            if (kb[sigInkPos[j]] === 1) { tp3++; }
          }
          const match3: number = SIG_LEN - sigInkLen - t.inkCount + 2 * tp3;
          const score: number = match3 - (SIG_LEN - match3) * TEMPLATE_MISMATCH_PENALTY;
          if (score > best1Score3) { best1Score3 = score; }
        }
        const geoGate2: number = Math.floor(SIG_LEN * 0.55);
        if (best1Score3 >= geoGate2) {
          SP.lastPixelDiag = `not4→1: score1=${best1Score3} ink=${inkCount} sig=${sigToCompactStr(sig)}`;
          SP.lastConfidence = 0.55;
          return 1;
        }
      }
    }
    if (bestDigit === 4 || bestDigit === 7) {
      hilog.info(DOMAIN, TAG, 'DBG_STRIP: bestDigit=%{public}d score=%{public}.0f ink=%{public}d', bestDigit, bestScore, inkCount);
      const stripResult: number = tryStripLeftEdgeAs1(sig, inkCount, bestDigit, bestScore);
      const stripDiag: string = SP.lastPixelDiag;
      if (stripResult === 1) { return 1; }
      if (bestDigit === 4) {
        const botTop4f: number = Math.floor(SIG_ROWS * 0.50);
        let colSum4f: number = 0;
        let inkCnt4f: number = 0;
        for (let r4f: number = botTop4f; r4f < SIG_ROWS; r4f++) {
          for (let c4f: number = 0; c4f < SIG_COLS; c4f++) {
            if (sig[r4f * SIG_COLS + c4f] === 1) { colSum4f += c4f; inkCnt4f++; }
          }
        }
        const colCent4f: number = inkCnt4f > 0 ? colSum4f / inkCnt4f : SIG_COLS / 2;
        if (colCent4f > SIG_COLS * 0.55) {
          const s1f: number = digitBestScore[1];
          SP.lastPixelDiag = `4→1(stripPath): colCent=${colCent4f.toFixed(1)} s4=${digitBestScore[4].toFixed(0)} s1=${s1f.toFixed(0)} [${stripDiag}]`;
          SP.lastConfidence = s1f > 0 ? Math.min(s1f / (SIG_LEN + 200), 1) : 0.55;
          return 1;
        }
        SP.lastPixelDiag = `best=4 score=${bestScore.toFixed(0)} ink=${inkCount} colCent=${colCent4f.toFixed(1)} [${stripDiag}] sig=${sigToCompactStr(sig)}`;
      } else {
        SP.lastPixelDiag = `best=${bestDigit} score=${bestScore.toFixed(0)} ink=${inkCount} [${stripDiag}] sig=${sigToCompactStr(sig)}`;
      }
    } else {
      SP.lastPixelDiag = `best=${bestDigit} score=${bestScore.toFixed(0)} ink=${inkCount}`;
    }
    if (bestDigit === 4) {
      const botTopCc: number = Math.floor(SIG_ROWS * 0.50);
      let colSumCc: number = 0;
      let inkCntCc: number = 0;
      for (let rCc: number = botTopCc; rCc < SIG_ROWS; rCc++) {
        for (let cCc: number = 0; cCc < SIG_COLS; cCc++) {
          if (sig[rCc * SIG_COLS + cCc] === 1) { colSumCc += cCc; inkCntCc++; }
        }
      }
      const colCentCc: number = inkCntCc > 0 ? colSumCc / inkCntCc : SIG_COLS / 2;
      if (colCentCc > SIG_COLS * 0.55) {
        SP.lastPixelDiag = `4→1(colCentCatchAll): colCent=${colCentCc.toFixed(1)} s4=${digitBestScore[4].toFixed(0)} s1=${digitBestScore[1].toFixed(0)}`;
        SP.lastConfidence = 0.55;
        return 1;
      }
    }
    return bestDigit;
  }
  SP.lastPixelDiag = `bestDigit=${bestDigit} bestScore=${bestScore.toFixed(0)} second=${secondDigit}(${secondScore.toFixed(0)}) minGate=${MIN_DIGIT_SCORE} ink=${inkCount}`;
  return 0;
}

let g_lastSecondDigit: number = 0;
let g_lastSecondScore: number = -100000;

export function getLastSecondDigit(): number {
  return g_lastSecondDigit;
}

export function getLastConfidence(): number {
  return SP.lastConfidence;
}

export interface DigitResult {
  digit: number;
  confidence: number;
}

export async function recognizeDigitWithConfidence(sig: number[], inkCount: number): Promise<DigitResult> {
  const digit: number = await recognizeDigit(sig, inkCount);
  const result: DigitResult = { digit, confidence: SP.lastConfidence };
  return result;
}
