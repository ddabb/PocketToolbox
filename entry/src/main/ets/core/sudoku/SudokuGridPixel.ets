import { setLastRecognizeDiag } from './SudokuOCRTypes';
import {
  cellSigFromGray, cellSigFromGrayLowThresh, cellSigFromGrayThin,
  recognizeDigit, countInk, resetLastPixelDiag, getLastPixelDiag,
  getLastRawInkRatio, MIN_CELL_INK_RATIO, ULTRA_LOW_INK_THRESH,
  SIG_ROWS, SIG_COLS
} from './SudokuPixel';

export async function recognizeDigitPixel(
  gray: Float32Array,
  imgW: number,
  cellLeft: number, cellTop: number,
  cellW: number, cellH: number,
  isDark: boolean, bg: number,
  gridRow: number = -1,
  gridCol: number = -1
): Promise<number | null> {
  resetLastPixelDiag();
  let sig: number[] | null = await cellSigFromGray(
    gray, imgW,
    cellLeft, cellTop, cellW, cellH, isDark, bg, gridRow, gridCol
  );
  if (sig === null) {
    const d: string = getLastPixelDiag();
    const ri: number = getLastRawInkRatio();
    const lowSig: number[] | null = await cellSigFromGrayLowThresh(
      gray, imgW, cellLeft, cellTop, cellW, cellH, isDark, bg, gridRow, gridCol
    );
    if (lowSig !== null) {
      sig = lowSig;
      const lowInk: number = countInk(lowSig);
      const lowDigit: number = await recognizeDigit(lowSig, lowInk);
      if (lowDigit > 0) {
        const lowD: string = getLastPixelDiag();
        setLastRecognizeDiag(`retryLowThresh: digit=${lowDigit} ink=${lowInk} diag=[${lowD}] rawInk=${ri.toFixed(4)}`);
        return lowDigit;
      }
    }
    if (ri < MIN_CELL_INK_RATIO) {
      const thinSig: number[] | null = await cellSigFromGrayThin(
        gray, imgW, cellLeft, cellTop, cellW, cellH, isDark, bg, gridRow, gridCol
      );
      if (thinSig !== null) {
        sig = thinSig;
        const thinInk: number = countInk(thinSig);
        const thinDigit: number = await recognizeDigit(thinSig, thinInk);
        if (thinDigit > 0) {
          const thinD: string = getLastPixelDiag();
          setLastRecognizeDiag(`retryThin: digit=${thinDigit} ink=${thinInk} diag=[${thinD}] rawInk=${ri.toFixed(4)}`);
          return thinDigit;
        }
        const thinDf: string = getLastPixelDiag();
        setLastRecognizeDiag(`retryThinFail: digit=0 ink=${thinInk} diag=[${thinDf}] rawInk=${ri.toFixed(4)}`);
      }
    }
    if (ri < MIN_CELL_INK_RATIO * 3) {
      const ultraSig: number[] | null = await cellSigFromGrayLowThresh(
        gray, imgW, cellLeft, cellTop, cellW, cellH, isDark, bg, gridRow, gridCol,
        ULTRA_LOW_INK_THRESH
      );
      if (ultraSig !== null) {
        sig = ultraSig;
        const ultraInk: number = countInk(ultraSig);
        let ublkStats: string = '';
        if (ultraInk >= SIG_ROWS * SIG_COLS * 0.6) {
          const imgH86: number = Math.floor(gray.length / imgW);
          const px0: number = Math.max(Math.floor(cellLeft), 0);
          const py0: number = Math.max(Math.floor(cellTop), 0);
          const px1: number = Math.min(Math.ceil(cellLeft + cellW), imgW);
          const py1: number = Math.min(Math.ceil(cellTop + cellH), imgH86);
          let gMin: number = 255;
          let gMax: number = 0;
          let gSum: number = 0;
          let gCnt: number = 0;
          for (let yy: number = py0; yy < py1; yy++) {
            for (let xx: number = px0; xx < px1; xx++) {
              const gv: number = gray[yy * imgW + xx];
              if (gv < gMin) { gMin = gv; }
              if (gv > gMax) { gMax = gv; }
              gSum += gv;
              gCnt++;
            }
          }
          const gMean: number = gCnt > 0 ? gSum / gCnt : 0;
          let gVar: number = 0;
          for (let yy2: number = py0; yy2 < py1; yy2++) {
            for (let xx2: number = px0; xx2 < px1; xx2++) {
              const dv: number = gray[yy2 * imgW + xx2] - gMean;
              gVar += dv * dv;
            }
          }
          const gStd: number = Math.sqrt(gVar / (gCnt > 0 ? gCnt : 1));
          ublkStats = ` ublk[min=${gMin.toFixed(0)} max=${gMax.toFixed(0)} mean=${gMean.toFixed(1)} std=${gStd.toFixed(1)}]`;
        }
        const ultraDigit: number = await recognizeDigit(ultraSig, ultraInk);
        if (ultraDigit > 0) {
          const ultraD: string = getLastPixelDiag();
          setLastRecognizeDiag(`retryUltraLow: digit=${ultraDigit} ink=${ultraInk}${ublkStats} diag=[${ultraD}] rawInk=${ri.toFixed(4)}`);
          return ultraDigit;
        }
        const ultraDf: string = getLastPixelDiag();
        setLastRecognizeDiag(`retryUltraLowFail: digit=0 ink=${ultraInk}${ublkStats} diag=[${ultraDf}] rawInk=${ri.toFixed(4)}`);
      }
    }
    setLastRecognizeDiag(`sigNull diag=[${d}] rawInk=${ri.toFixed(4)}`);
    return null;
  }

  const inkCount: number = countInk(sig);
  const digit: number = await recognizeDigit(sig, inkCount);
  if (digit > 0) {
    const d: string = getLastPixelDiag();
    setLastRecognizeDiag(`digit=${digit} ink=${inkCount} diag=[${d}]`);
    return digit;
  }

  const ri2: number = getLastRawInkRatio();
  const lowSig: number[] | null = await cellSigFromGrayLowThresh(
    gray, imgW, cellLeft, cellTop, cellW, cellH, isDark, bg, gridRow, gridCol
  );
  if (lowSig !== null) {
    const lowInk: number = countInk(lowSig);
    const lowDigit: number = await recognizeDigit(lowSig, lowInk);
    if (lowDigit > 0) {
      const lowD: string = getLastPixelDiag();
      setLastRecognizeDiag(`retryLowThresh: digit=${lowDigit} ink=${lowInk} diag=[${lowD}] rawInk=${ri2.toFixed(4)}`);
      return lowDigit;
    }
  }
  if (ri2 < MIN_CELL_INK_RATIO) {
    const thinSig: number[] | null = await cellSigFromGrayThin(
      gray, imgW, cellLeft, cellTop, cellW, cellH, isDark, bg, gridRow, gridCol
    );
    if (thinSig !== null) {
      const thinInk: number = countInk(thinSig);
      const thinDigit: number = await recognizeDigit(thinSig, thinInk);
      if (thinDigit > 0) {
        const thinD: string = getLastPixelDiag();
        setLastRecognizeDiag(`retryThin: digit=${thinDigit} ink=${thinInk} diag=[${thinD}] rawInk=${ri2.toFixed(4)}`);
        return thinDigit;
      }
    }
  }
  if (ri2 < MIN_CELL_INK_RATIO * 3) {
    const ultraSig: number[] | null = await cellSigFromGrayLowThresh(
      gray, imgW, cellLeft, cellTop, cellW, cellH, isDark, bg, gridRow, gridCol,
      ULTRA_LOW_INK_THRESH
    );
    if (ultraSig !== null) {
      sig = ultraSig;
      const ultraInk: number = countInk(ultraSig);
      const ultraDigit: number = await recognizeDigit(ultraSig, ultraInk);
      if (ultraDigit > 0) {
        const ultraD: string = getLastPixelDiag();
        setLastRecognizeDiag(`retryUltraLow: digit=${ultraDigit} ink=${ultraInk} diag=[${ultraD}] rawInk=${ri2.toFixed(4)}`);
        return ultraDigit;
      }
    }
  }

  const d: string = getLastPixelDiag();
  setLastRecognizeDiag(`digit=0 ink=${inkCount} diag=[${d}]`);
  return null;
}
