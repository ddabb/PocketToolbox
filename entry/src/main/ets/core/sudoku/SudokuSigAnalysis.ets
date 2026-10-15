import { DigitTemplate, SP, SIG_ROWS, SIG_COLS, SIG_LEN, HOLE_SECOND_RATIO } from './SudokuPixelKernel';

export function holeCenterRow(sig: number[]): number {
  const ROWS: number = SIG_ROWS;
  const COLS: number = SIG_COLS;
  const outside: boolean[] = new Array<boolean>(ROWS * COLS).fill(false);
  const stack: number[] = [];
  const pushIfBg: (i: number) => void = (i: number) => {
    if (!outside[i] && sig[i] === 0) { outside[i] = true; stack.push(i); }
  };
  for (let c: number = 0; c < COLS; c++) {
    pushIfBg(c);
    pushIfBg((ROWS - 1) * COLS + c);
  }
  for (let r: number = 0; r < ROWS; r++) {
    pushIfBg(r * COLS);
    pushIfBg(r * COLS + (COLS - 1));
  }
  while (stack.length > 0) {
    const i: number = stack.pop() as number;
    const r: number = Math.floor(i / COLS);
    const c: number = i % COLS;
    if (r > 0) { pushIfBg(i - COLS); }
    if (r < ROWS - 1) { pushIfBg(i + COLS); }
    if (c > 0) { pushIfBg(i - 1); }
    if (c < COLS - 1) { pushIfBg(i + 1); }
  }
  const visited: boolean[] = new Array<boolean>(ROWS * COLS).fill(false);
  const components: number[][] = [];
  for (let i: number = 0; i < ROWS * COLS; i++) {
    if (sig[i] === 0 && !outside[i] && !visited[i]) {
      const comp: number[] = [];
      const cs: number[] = [i];
      visited[i] = true;
      while (cs.length > 0) {
        const j: number = cs.pop() as number;
        comp.push(j);
        const r: number = Math.floor(j / COLS);
        const c: number = j % COLS;
        const push2: (n: number) => void = (n: number) => {
          if (!visited[n] && sig[n] === 0 && !outside[n]) { visited[n] = true; cs.push(n); }
        };
        if (r > 0) { push2(j - COLS); }
        if (r < ROWS - 1) { push2(j + COLS); }
        if (c > 0) { push2(j - 1); }
        if (c < COLS - 1) { push2(j + 1); }
      }
      components.push(comp);
    }
  }
  if (components.length === 0) { return -1; }
  components.sort((a: number[], b: number[]) => b.length - a.length);
  if (components.length >= 2 && components[1].length > components[0].length * HOLE_SECOND_RATIO) {
    return -1;
  }
  let sumRow: number = 0;
  for (const j of components[0]) { sumRow += Math.floor(j / COLS); }
  return sumRow / components[0].length;
}

export function countHoles(sig: number[]): number {
  const ROWS: number = SIG_ROWS;
  const COLS: number = SIG_COLS;
  const outside: boolean[] = new Array<boolean>(ROWS * COLS).fill(false);
  const stack: number[] = [];
  const pushIfBgH: (i: number) => void = (i: number) => {
    if (!outside[i] && sig[i] === 0) { outside[i] = true; stack.push(i); }
  };
  for (let c: number = 0; c < COLS; c++) {
    pushIfBgH(c);
    pushIfBgH((ROWS - 1) * COLS + c);
  }
  for (let r: number = 0; r < ROWS; r++) {
    pushIfBgH(r * COLS);
    pushIfBgH(r * COLS + (COLS - 1));
  }
  while (stack.length > 0) {
    const i: number = stack.pop() as number;
    const r: number = Math.floor(i / COLS);
    const c: number = i % COLS;
    if (r > 0) { pushIfBgH(i - COLS); }
    if (r < ROWS - 1) { pushIfBgH(i + COLS); }
    if (c > 0) { pushIfBgH(i - 1); }
    if (c < COLS - 1) { pushIfBgH(i + 1); }
  }
  let count: number = 0;
  const visited: boolean[] = new Array<boolean>(ROWS * COLS).fill(false);
  for (let i: number = 0; i < ROWS * COLS; i++) {
    if (sig[i] === 0 && !outside[i] && !visited[i]) {
      count++;
      const cs: number[] = [i];
      visited[i] = true;
      while (cs.length > 0) {
        const j: number = cs.pop() as number;
        const r2: number = Math.floor(j / COLS);
        const c2: number = j % COLS;
        const pushH: (n: number) => void = (n: number) => {
          if (!visited[n] && sig[n] === 0 && !outside[n]) { visited[n] = true; cs.push(n); }
        };
        if (r2 > 0) { pushH(j - COLS); }
        if (r2 < ROWS - 1) { pushH(j + COLS); }
        if (c2 > 0) { pushH(j - 1); }
        if (c2 < COLS - 1) { pushH(j + 1); }
      }
    }
  }
  return count;
}

// Digit-likeness metrics for shadow/noise rejection: counts 8-connectivity
// ink components, the largest component's share of total ink, and enclosed
// holes. A real digit has few components with one dominant stroke; shadow
// fragments scatter into many small blobs.
const LOCAL_BG_CLEAN_PEAK: number = 252;

export function computeSigQualityMetrics(sig: number[]): void {
  let totalInk: number = 0;
  for (let i: number = 0; i < SIG_LEN; i++) {
    if (sig[i] === 1) { totalInk++; }
  }
  if (totalInk === 0) {
    SP.lastSigMetrics = 'comp=0 lrg=0.00 holes=0 ink=0';
    SP.lastSigQualityFail = true;
    SP.lastSigCompCount = 0;
    SP.lastSigLrgRatio = 0;
    SP.lastSigHoles = 0;
    SP.lastSigInk = 0;
    return;
  }
  const visited: boolean[] = new Array<boolean>(SIG_LEN).fill(false);
  const stack: number[] = [];
  let compCount: number = 0;
  let largestComp: number = 0;
  for (let i: number = 0; i < SIG_LEN; i++) {
    if (sig[i] !== 1 || visited[i]) { continue; }
    compCount++;
    let compSize: number = 0;
    stack.push(i);
    visited[i] = true;
    while (stack.length > 0) {
      const p: number = stack[stack.length - 1];
      stack.length = stack.length - 1;
      compSize++;
      const pr: number = Math.floor(p / SIG_COLS);
      const pc: number = p % SIG_COLS;
      for (let dr: number = -1; dr <= 1; dr++) {
        for (let dc: number = -1; dc <= 1; dc++) {
          if (dr === 0 && dc === 0) { continue; }
          const nr: number = pr + dr;
          const nc: number = pc + dc;
          if (nr < 0 || nr >= SIG_ROWS || nc < 0 || nc >= SIG_COLS) { continue; }
          const np: number = nr * SIG_COLS + nc;
          if (sig[np] === 1 && !visited[np]) {
            visited[np] = true;
            stack.push(np);
          }
        }
      }
    }
    if (compSize > largestComp) { largestComp = compSize; }
  }
  const holes: number = countHoles(sig);
  const lrgRatio: number = largestComp / totalInk;
  SP.lastSigMetrics = `comp=${compCount} lrg=${lrgRatio.toFixed(2)} holes=${holes} ink=${totalInk}`;
  SP.lastSigCompCount = compCount;
  SP.lastSigLrgRatio = lrgRatio;
  SP.lastSigHoles = holes;
  SP.lastSigInk = totalInk;
  SP.lastSigQualityFail = (compCount >= 5 || holes >= 6 || lrgRatio < 0.75 || (holes >= 2 && compCount >= 3)) && SP.lastLocalBgPeak < LOCAL_BG_CLEAN_PEAK;
}

export function inkCentroidRow(sig: number[]): number {
  let sumR: number = 0;
  let cnt: number = 0;
  for (let r: number = 0; r < SIG_ROWS; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) { sumR += r; cnt++; }
    }
  }
  return cnt > 0 ? sumR / cnt / (SIG_ROWS - 1) : 0.5;
}

export function topBottomInkRatio(sig: number[]): number {
  const halfRow: number = Math.floor(SIG_ROWS / 2);
  let topInk: number = 0;
  let bottomInk: number = 0;
  for (let r: number = 0; r < SIG_ROWS; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) {
        if (r < halfRow) { topInk++; } else { bottomInk++; }
      }
    }
  }
  return bottomInk > 0 ? topInk / bottomInk : 999;
}

export function leftRightInkRatio(sig: number[]): number {
  const halfCol: number = Math.floor(SIG_COLS / 2);
  let leftInk: number = 0;
  let rightInk: number = 0;
  for (let r: number = 0; r < SIG_ROWS; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) {
        if (c < halfCol) { leftInk++; } else { rightInk++; }
      }
    }
  }
  return rightInk > 0 ? leftInk / rightInk : 0;
}

export function inkCentroidCol(sig: number[]): number {
  let sumC: number = 0;
  let cnt: number = 0;
  for (let r: number = 0; r < SIG_ROWS; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) { sumC += c; cnt++; }
    }
  }
  return cnt > 0 ? sumC / cnt : -1;
}

function templateMatchesFilter(
  tpl: DigitTemplate, sigInkCount: number,
  sigCentroidRow: number, sigCentroidCol: number,
  sigTopBottom: number, sigLeftRight: number,
  sigHasHole: boolean
): boolean {
  const inkRatio: number = sigInkCount / tpl.inkCount;
  if (inkRatio < 0.45 || inkRatio > 2.2) { return false; }
  if (Math.abs(sigCentroidRow - tpl.centroidRow) > 10) { return false; }
  if (Math.abs(sigCentroidCol - tpl.centroidCol) > 8) { return false; }
  const tbDiff: number = Math.abs(sigTopBottom - tpl.topBottomRatio);
  if (tbDiff > 3.5) { return false; }
  const lrDiff: number = Math.abs(sigLeftRight - tpl.leftRightRatio);
  if (lrDiff > 3.5) { return false; }
  if (sigHasHole && !tpl.hasHole) {
    const noHoleDigits: Set<number> = new Set<number>([1, 2, 3, 5, 7]);
    if (noHoleDigits.has(tpl.digit)) { return false; }
  }
  return true;
}

export function templateMatchesInkFilter(tpl: DigitTemplate, sigInkCount: number): boolean {
  const inkRatio: number = sigInkCount / tpl.inkCount;
  if (inkRatio < 0.45 || inkRatio > 2.2) { return false; }
  return true;
}

export function sigComputeLeftRightRatio(sig: number[]): number {
  const halfCol2: number = Math.floor(SIG_COLS / 2);
  let lInk: number = 0;
  let rInk: number = 0;
  for (let i: number = 0; i < SIG_LEN; i++) {
    if (sig[i] === 1) {
      if (i % SIG_COLS < halfCol2) { lInk++; } else { rInk++; }
    }
  }
  return rInk > 0 ? lInk / rInk : 0;
}

function sigToAscii(sig: number[]): string {
  let s: string = '';
  for (let r: number = 0; r < SIG_ROWS; r++) {
    let line: string = '';
    for (let c: number = 0; c < SIG_COLS; c++) {
      line += sig[r * SIG_COLS + c] ? '#' : '.';
    }
    s += line + '\n';
  }
  return s;
}


export function hogVerticalGradient(sig: number[]): number {
  let posGrad: number = 0;
  let negGrad: number = 0;
  for (let r: number = 1; r < SIG_ROWS; r++) {
    for (let c: number = 0; c < SIG_COLS; c++) {
      const d: number = sig[r * SIG_COLS + c] - sig[(r - 1) * SIG_COLS + c];
      if (d > 0) { posGrad += d; } else { negGrad += d; }
    }
  }
  return posGrad + negGrad > 0 ? posGrad / (posGrad - negGrad) : 0.5;
}

export function strokeWidthRatio(sig: number[]): number {
  let maxH: number = 0;
  for (let r: number = 0; r < SIG_ROWS; r++) {
    let run: number = 0;
    for (let c: number = 0; c < SIG_COLS; c++) {
      if (sig[r * SIG_COLS + c] === 1) { run++; }
      else {
        if (run > maxH) { maxH = run; }
        run = 0;
      }
    }
    if (run > maxH) { maxH = run; }
  }
  let maxV: number = 0;
  for (let c: number = 0; c < SIG_COLS; c++) {
    let run: number = 0;
    for (let r: number = 0; r < SIG_ROWS; r++) {
      if (sig[r * SIG_COLS + c] === 1) { run++; }
      else {
        if (run > maxV) { maxV = run; }
        run = 0;
      }
    }
    if (run > maxV) { maxV = run; }
  }
  return maxV > 0 ? maxH / maxV : 0;
}
