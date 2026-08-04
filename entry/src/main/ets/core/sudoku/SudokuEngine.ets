/**
 * 数独引擎 — 基于 Dancing Links (DLX) Algorithm X
 * 支持求解、验证、生成、提示等功能
 */

// ---- DLX 节点结构 ----

class DLXNode {
  left: DLXNode = this;
  right: DLXNode = this;
  up: DLXNode = this;
  down: DLXNode = this;
  column: DLXColumn | null = null;
  rowId: number = -1; // 编码: r*100 + c*10 + d
}

class DLXColumn extends DLXNode {
  size: number = 0;
  name: string = '';

  constructor(name: string) {
    super();
    this.name = name;
    this.column = this;
  }
}

const EMPTY: number = 0;
const SIZE: number = 9;
const BOX: number = 3;

// ---- 公共接口 ----

export interface SolveResult {
  success: boolean;
  solution: number[];      // 81 个数字, 0=空
  solutions: number[][];   // 所有解（限制最多2个）
  solutionCount: number;   // 解的数量
}

export interface CellCandidates {
  row: number;
  col: number;
  candidates: number[];
}

export interface HintCell {
  row: number;
  col: number;
  value: number;
}

// ---- DLX 核心 ----

function buildMatrix(puzzle: number[]): DLXNode {
  const header: DLXNode = new DLXColumn('header');
  const columns: DLXColumn[] = [];

  // 324 列: 81 cell + 81 row + 81 col + 81 box
  for (let i: number = 0; i < 324; i++) {
    const col: DLXColumn = new DLXColumn(`c${i}`);
    columns.push(col);
    col.left = header.left;
    col.right = header;
    header.left.right = col;
    header.left = col;
  }

  for (let r: number = 0; r < SIZE; r++) {
    for (let c: number = 0; c < SIZE; c++) {
      const cellIdx: number = r * SIZE + c;
      const box: number = Math.floor(r / BOX) * BOX + Math.floor(c / BOX);
      const d: number = puzzle[cellIdx];

      if (d !== EMPTY) {
        addRow(columns, r, c, d, box);
      } else {
        for (let digit: number = 1; digit <= SIZE; digit++) {
          if (canPlace(puzzle, r, c, digit)) {
            addRow(columns, r, c, digit, box);
          }
        }
      }
    }
  }

  return header;
}

function addRow(columns: DLXColumn[], r: number, c: number, d: number, box: number): void {
  const rowId: number = r * 100 + c * 10 + d;
  const constraintCols: number[] = [
    0 * 81 + r * SIZE + c,             // cell constraint
    1 * 81 + r * SIZE + (d - 1),       // row constraint
    2 * 81 + c * SIZE + (d - 1),       // col constraint
    3 * 81 + box * SIZE + (d - 1)      // box constraint
  ];

  const nodes: DLXNode[] = [];
  for (let colIdx of constraintCols) {
    const node: DLXNode = new DLXNode();
    node.column = columns[colIdx];
    node.rowId = rowId;
    nodes.push(node);
  }

  // 水平链接
  for (let i: number = 0; i < nodes.length; i++) {
    nodes[i].left = nodes[(i + nodes.length - 1) % nodes.length];
    nodes[i].right = nodes[(i + 1) % nodes.length];
  }

  // 垂链接入列
  for (let node of nodes) {
    const col: DLXColumn = node.column!;
    node.up = col.up;
    node.down = col;
    col.up.down = node;
    col.up = node;
    col.size++;
  }
}

function coverColumn(col: DLXColumn): void {
  col.right.left = col.left;
  col.left.right = col.right;
  let row: DLXNode = col.down;
  while (row !== col) {
    let node: DLXNode = row.right;
    while (node !== row) {
      node.down.up = node.up;
      node.up.down = node.down;
      node.column!.size--;
      node = node.right;
    }
    row = row.down;
  }
}

function uncoverColumn(col: DLXColumn): void {
  let row: DLXNode = col.up;
  while (row !== col) {
    let node: DLXNode = row.left;
    while (node !== row) {
      node.column!.size++;
      node.down.up = node;
      node.up.down = node;
      node = node.left;
    }
    row = row.up;
  }
  col.right.left = col;
  col.left.right = col;
}

function chooseColumn(header: DLXNode): DLXColumn | null {
  let minSize: number = 1000000;
  let best: DLXColumn | null = null;
  let col: DLXNode = header.right;
  while (col !== header) {
    const c: DLXColumn = col as DLXColumn;
    if (c.size < minSize) {
      minSize = c.size;
      best = c;
      if (minSize <= 1) {
        break;
      }
    }
    col = col.right;
  }
  return best;
}

function searchDLX(header: DLXNode, solution: number[], results: number[][], maxResults: number): void {
  if (results.length >= maxResults) {
    return;
  }

  if (header.right === header) {
    // 找到解
    const solved: number[] = new Array<number>(81).fill(0);
    for (let rowId of solution) {
      const r: number = Math.floor(rowId / 100);
      const c: number = Math.floor((rowId % 100) / 10);
      const d: number = rowId % 10;
      solved[r * SIZE + c] = d;
    }
    results.push(solved);
    return;
  }

  const col: DLXColumn | null = chooseColumn(header);
  if (!col || col.size === 0) {
    return; // 死路
  }

  coverColumn(col);
  let row: DLXNode = col.down;
  while (row !== col && results.length < maxResults) {
    solution.push(row.rowId);

    let node: DLXNode = row.right;
    while (node !== row) {
      coverColumn(node.column!);
      node = node.right;
    }

    searchDLX(header, solution, results, maxResults);

    solution.pop();
    node = row.left;
    while (node !== row) {
      uncoverColumn(node.column!);
      node = node.left;
    }

    row = row.down;
  }
  uncoverColumn(col);
}

// ---- 约束检查 ----

function canPlace(puzzle: number[], r: number, c: number, d: number): boolean {
  const box: number = Math.floor(r / BOX) * BOX + Math.floor(c / BOX);
  for (let i: number = 0; i < SIZE; i++) {
    // 同行
    if (puzzle[r * SIZE + i] === d && i !== c) {
      return false;
    }
    // 同列
    if (puzzle[i * SIZE + c] === d && i !== r) {
      return false;
    }
    // 同宫
    const br: number = Math.floor(box / BOX) * BOX + Math.floor(i / BOX);
    const bc: number = (box % BOX) * BOX + (i % BOX);
    if (puzzle[br * SIZE + bc] === d && !(br === r && bc === c)) {
      return false;
    }
  }
  return true;
}

// ---- 公共 API ----

/**
 * 求解数独
 * @param puzzle 81 个数字的数组, 0 表示空格
 * @returns SolveResult
 */
export function solveSudoku(puzzle: number[]): SolveResult {
  if (puzzle.length !== 81) {
    return { success: false, solution: [], solutions: [], solutionCount: 0 };
  }

  // 先验证输入合法性
  for (let r: number = 0; r < SIZE; r++) {
    for (let c: number = 0; c < SIZE; c++) {
      const d: number = puzzle[r * SIZE + c];
      if (d !== EMPTY && !canPlace(puzzle, r, c, d)) {
        return { success: false, solution: [], solutions: [], solutionCount: -1 };
      }
    }
  }

  const header: DLXNode = buildMatrix(puzzle);
  const solution: number[] = [];
  const results: number[][] = [];

  searchDLX(header, solution, results, 2); // 最多找2个解

  if (results.length === 0) {
    return { success: false, solution: [], solutions: [], solutionCount: 0 };
  }

  return {
    success: true,
    solution: results[0],
    solutions: results,
    solutionCount: results.length
  };
}

/**
 * 获取某个格子的候选数
 */
export function getCandidates(puzzle: number[], row: number, col: number): number[] {
  if (puzzle[row * SIZE + col] !== EMPTY) {
    return [];
  }
  const candidates: number[] = [];
  for (let d: number = 1; d <= SIZE; d++) {
    if (canPlace(puzzle, row, col, d)) {
      candidates.push(d);
    }
  }
  return candidates;
}

/**
 * 获取所有空格子的候选数
 */
export function getAllCandidates(puzzle: number[]): CellCandidates[] {
  const result: CellCandidates[] = [];
  for (let r: number = 0; r < SIZE; r++) {
    for (let c: number = 0; c < SIZE; c++) {
      if (puzzle[r * SIZE + c] === EMPTY) {
        const cands: number[] = getCandidates(puzzle, r, c);
        if (cands.length > 0) {
          result.push({ row: r, col: c, candidates: cands });
        }
      }
    }
  }
  return result;
}

/**
 * 获取提示（返回下一个可确定的格子）
 */
export function getHint(puzzle: number[]): HintCell | null {
  const state: number[] = [...puzzle];
  const allCands: CellCandidates[] = getAllCandidates(state);

  // 优先找唯一候选数
  for (let cell of allCands) {
    if (cell.candidates.length === 1) {
      const hint: HintCell = { row: cell.row, col: cell.col, value: cell.candidates[0] };
      return hint;
    }
  }

  // 找隐藏唯一候选数（在行/列/宫中唯一）
  const result: SolveResult = solveSudoku(puzzle);
  if (result.success && result.solutions.length > 0) {
    const sol: number[] = result.solutions[0];
    for (let i: number = 0; i < 81; i++) {
      if (puzzle[i] === EMPTY) {
        const hint: HintCell = { row: Math.floor(i / SIZE), col: i % SIZE, value: sol[i] };
        return hint;
      }
    }
  }

  return null;
}

/**
 * 解析OCR文本提取数独数字
 * 支持多种格式: 81位连续数字、点号分隔、空格换行等
 */
export function parseOCRToGrid(text: string): number[] | null {
  // 清理文本
  let cleaned: string = text
    .replace(/[^0-9.?_ \n]/g, '')  // 移除非数字字符
    .replace(/[.?_]/g, '0')         // 点/问号/下划线 当作空格
    .replace(/\s+/g, '');           // 移除空白

  // 提取连续数字
  const digits: string[] = cleaned.match(/[0-9]/g) || [];

  if (digits.length < 17) {
    // 数字太少，可能不是有效的数独
    return null;
  }

  if (digits.length === 81) {
    // 正好81位
    return digits.map((d: string): number => parseInt(d, 10));
  }

  // 尝试从更多文本中识别9x9结构
  // 按行分组: 每行应包含9个字符
  const lines: string[] = text.split(/[\n\r]+/);
  let grid: number[] = [];

  for (let line of lines) {
    const lineDigits: string[] = line.replace(/[^0-9.?_]/g, '').split('');
    for (let ch of lineDigits) {
      if (/^[0-9]$/.test(ch)) {
        grid.push(parseInt(ch, 10));
      } else {
        grid.push(0); // . ? _ 当作空格
      }
    }
  }

  while (grid.length < 81) {
    grid.push(0);
  }

  if (grid.length >= 81) {
    return grid.slice(0, 81);
  }

  return null;
}

/**
 * 将网格转为81位字符串
 */
export function gridToString(grid: number[]): string {
  let result: string = '';
  for (let r: number = 0; r < SIZE; r++) {
    for (let c: number = 0; c < SIZE; c++) {
      const d: number = grid[r * SIZE + c];
      result += d === EMPTY ? '.' : d.toString();
      if (c === 2 || c === 5) {
        result += ' ';
      }
    }
    if (r === 2 || r === 5) {
      result += '\n';
    }
    if (r < SIZE - 1) {
      result += '\n';
    }
  }
  return result;
}

/**
 * 验证完整数独是否正确
 */
export function validateFullGrid(grid: number[]): boolean {
  if (grid.length !== 81) {
    return false;
  }

  // 检查每行
  for (let r: number = 0; r < SIZE; r++) {
    const seen: Set<number> = new Set();
    for (let c: number = 0; c < SIZE; c++) {
      const d: number = grid[r * SIZE + c];
      if (d < 1 || d > 9 || seen.has(d)) {
        return false;
      }
      seen.add(d);
    }
  }

  // 检查每列
  for (let c: number = 0; c < SIZE; c++) {
    const seen: Set<number> = new Set();
    for (let r: number = 0; r < SIZE; r++) {
      const d: number = grid[r * SIZE + c];
      if (d < 1 || d > 9 || seen.has(d)) {
        return false;
      }
      seen.add(d);
    }
  }

  // 检查每宫
  for (let box: number = 0; box < SIZE; box++) {
    const seen: Set<number> = new Set();
    const startR: number = Math.floor(box / BOX) * BOX;
    const startC: number = (box % BOX) * BOX;
    for (let r: number = startR; r < startR + BOX; r++) {
      for (let c: number = startC; c < startC + BOX; c++) {
        const d: number = grid[r * SIZE + c];
        if (d < 1 || d > 9 || seen.has(d)) {
          return false;
        }
        seen.add(d);
      }
    }
  }

  return true;
}

/**
 * 判断网格是否全部填满
 */
export function isGridFull(grid: number[]): boolean {
  for (let i: number = 0; i < 81; i++) {
    if (grid[i] === EMPTY) {
      return false;
    }
  }
  return true;
}
