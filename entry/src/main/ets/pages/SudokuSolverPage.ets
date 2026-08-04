import { BusinessError } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { display, promptAction } from '@kit.ArkUI';
import {
  solveSudoku, getHint,
  validateFullGrid, isGridFull, SolveResult
} from '../core/sudoku/SudokuEngine';
import { recognizeSudokuFromImage, OCRResult } from '../core/sudoku/SudokuOCR';

const SIZE: number = 9;
const EMPTY: number = 0;

const PRESET_PUZZLES: number[][] = [
  [
    5,3,0,0,7,0,0,0,0,
    6,0,0,1,9,5,0,0,0,
    0,9,8,0,0,0,0,6,0,
    8,0,0,0,6,0,0,0,3,
    4,0,0,8,0,3,0,0,1,
    7,0,0,0,2,0,0,0,6,
    0,6,0,0,0,0,2,8,0,
    0,0,0,4,1,9,0,0,5,
    0,0,0,0,8,0,0,7,9
  ],
  [
    0,0,0,2,6,0,7,0,1,
    6,8,0,0,7,0,0,9,0,
    1,9,0,0,0,4,5,0,0,
    8,2,0,1,0,0,0,4,0,
    0,0,4,6,0,2,9,0,0,
    0,5,0,0,0,3,0,2,8,
    0,0,9,3,0,0,0,7,4,
    0,4,0,0,5,0,0,3,6,
    7,0,3,0,1,8,0,0,0
  ],
  [
    0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,3,0,8,5,
    0,0,1,0,2,0,0,0,0,
    0,0,0,5,0,7,0,0,0,
    0,0,4,0,0,0,1,0,0,
    0,9,0,0,0,0,0,0,0,
    5,0,0,0,0,0,0,7,3,
    0,0,2,0,1,0,0,0,0,
    0,0,0,0,4,0,0,0,9
  ]
];

const DIFFICULTY_NAMES: string[] = ['简单', '中等', '困难'];

@Builder
export function SudokuSolverPageBuilder() {
  NavDestination() {
    SudokuSolverPage()
  }
  .title('数独求解器')
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct SudokuSolverPage {
  @State puzzle: number[] = Array.from<number>(new Array<number>(81).fill(0));
  @State currentGrid: number[] = Array.from<number>(new Array<number>(81).fill(0));
  @State fixedCells: boolean[] = new Array<boolean>(81).fill(false);
  @State selectedRow: number = -1;
  @State selectedCol: number = -1;
  @State candidateMode: boolean = false;
  @State candidates: Array<Set<number>> = new Array<Set<number>>(81);
  @State message: string = '';
  @State messageType: number = 0;
  @State solving: boolean = false;
  @State recognizing: boolean = false;
  @State showNumberPad: boolean = false;
  @State hasUserInput: boolean = false;
  @State currentDifficulty: number = 0;
  @State conflictCells: boolean[] = new Array<boolean>(81).fill(false);
  @State boardCellSize: number = 0;
  @State highlightDigit: number = 0;

  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const displayInfo = display.getDefaultDisplaySync();
    const screenWidthVp: number = displayInfo.width / displayInfo.densityPixels;
    const maxBoardVp: number = Math.min(screenWidthVp - 32, 400);
    this.boardCellSize = Math.floor(maxBoardVp / 9);

    for (let i: number = 0; i < 81; i++) {
      this.candidates[i] = new Set<number>();
    }
    this.loadPuzzle(0);
  }

  loadPuzzle(difficulty: number): void {
    const puzzle: number[] = [...PRESET_PUZZLES[difficulty]];
    this.puzzle = puzzle;
    this.currentGrid = [...puzzle];
    this.fixedCells = new Array<boolean>(81).fill(false);
    for (let i: number = 0; i < 81; i++) {
      if (puzzle[i] !== EMPTY) {
        this.fixedCells[i] = true;
      }
    }
    this.clearCandidates();
    this.clearSelection();
    this.hasUserInput = false;
    this.currentDifficulty = difficulty;
    this.clearMessage();
    this.updateConflicts();
    this.highlightDigit = 0;
  }

  clearGrid(): void {
    this.puzzle = new Array<number>(81).fill(0);
    this.currentGrid = new Array<number>(81).fill(0);
    this.fixedCells = new Array<boolean>(81).fill(false);
    this.clearCandidates();
    this.clearSelection();
    this.hasUserInput = false;
    this.clearMessage();
    this.conflictCells = new Array<boolean>(81).fill(false);
    this.highlightDigit = 0;
  }

  solve(): void {
    const result: SolveResult = solveSudoku(this.currentGrid);

    if (!result.success && result.solutionCount === -1) {
      this.showMessage('当前棋盘存在冲突，请检查输入', 2);
      return;
    }

    if (result.success) {
      for (let i: number = 0; i < 81; i++) {
        if (this.currentGrid[i] !== EMPTY) {
          this.fixedCells[i] = true;
        }
      }
      this.currentGrid = [...result.solution];
      this.puzzle = [...this.currentGrid];
      this.clearCandidates();
      this.showMessage('求解完成！', 1);

      if (result.solutionCount > 1) {
        this.showMessage('求解完成（提示：该题目有多个解）', 0);
      }
    } else {
      this.showMessage('该数独无解，请检查输入是否正确', 2);
    }
  }

  showHint(): void {
    const hint = getHint(this.currentGrid);
    if (hint) {
      this.selectedRow = hint.row;
      this.selectedCol = hint.col;
      const idx: number = hint.row * SIZE + hint.col;
      this.currentGrid[idx] = hint.value;
      this.puzzle[idx] = hint.value;
      this.fixedCells[idx] = true;
      this.hasUserInput = true;
      this.showNumberPad = false;
      this.clearCandidates();
      this.updateConflicts();
      this.highlightDigit = hint.value;
      this.showMessage(`提示: R${hint.row + 1}C${hint.col + 1} = ${hint.value}`, 0);
    } else if (isGridFull(this.currentGrid)) {
      if (validateFullGrid(this.currentGrid)) {
        this.showMessage('恭喜！已完成且正确！', 1);
      } else {
        this.showMessage('棋盘已填满但存在错误，请检查', 2);
      }
    } else {
      this.showMessage('无法确定下一步，请尝试手动推理', 0);
    }
  }

  updateConflicts(): void {
    this.conflictCells = new Array<boolean>(81).fill(false);
    for (let i: number = 0; i < 81; i++) {
      if (this.currentGrid[i] === EMPTY) {
        continue;
      }
      const r: number = Math.floor(i / SIZE);
      const c: number = i % SIZE;
      const d: number = this.currentGrid[i];

      for (let j: number = 0; j < SIZE; j++) {
        if (j !== c && this.currentGrid[r * SIZE + j] === d) {
          this.conflictCells[i] = true;
          this.conflictCells[r * SIZE + j] = true;
        }
      }
      for (let j: number = 0; j < SIZE; j++) {
        if (j !== r && this.currentGrid[j * SIZE + c] === d) {
          this.conflictCells[i] = true;
          this.conflictCells[j * SIZE + c] = true;
        }
      }
      const boxR: number = Math.floor(r / 3) * 3;
      const boxC: number = Math.floor(c / 3) * 3;
      for (let br: number = boxR; br < boxR + 3; br++) {
        for (let bc: number = boxC; bc < boxC + 3; bc++) {
          if (!(br === r && bc === c) && this.currentGrid[br * SIZE + bc] === d) {
            this.conflictCells[i] = true;
            this.conflictCells[br * SIZE + bc] = true;
          }
        }
      }
    }
  }

  async pickFromGallery(): Promise<void> {
    try {
      const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;

      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const result: photoAccessHelper.PhotoSelectResult = await photoPicker.select(photoSelectOptions);

      if (result.photoUris.length === 0) {
        return;
      }

      const uri: string = result.photoUris[0];
      await this.processImageOCR(uri);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      if (error.code !== 0) {
        this.showMessage(`选择图片失败: ${error.message}`, 2);
      }
    }
  }

  async takePhoto(): Promise<void> {
    try {
      const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;

      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const result: photoAccessHelper.PhotoSelectResult = await photoPicker.select(photoSelectOptions);

      if (result.photoUris.length > 0) {
        const uri: string = result.photoUris[0];
        await this.processImageOCR(uri);
      }
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      if (error.code !== 0) {
        this.showMessage('拍照/选图取消', 0);
      }
    }
  }

  async processImageOCR(uri: string): Promise<void> {
    this.recognizing = true;
    this.showMessage('正在识别图片中的数独...', 0);

    try {
      const ocrResult: OCRResult = await recognizeSudokuFromImage(uri);

      if (ocrResult.success && ocrResult.grid) {
        this.loadGridFromArray(ocrResult.grid);

        const digitCount: number = ocrResult.grid.filter((d: number) => d > 0).length;
        this.showMessage(`识别成功！检测到 ${digitCount} 个数字`, 1);
      } else {
        this.showMessage(ocrResult.error || '未能识别出数独', 2);
      }
    } catch (_err) {
      this.showMessage('图片处理异常，请重试', 2);
    } finally {
      this.recognizing = false;
    }
  }

  showPasteDialog(): void {
    const uiPrompt = this.getUIContext().getPromptAction();
    uiPrompt.showDialog({
      title: '粘贴数独题目',
      message: '请输入 81 位数字字符串（空格用0或.代替）\n\n示例: 530070000\n600195000 ...',
      buttons: [
        { text: '取消', color: '#999999' },
        { text: '加载', color: '#6366f1' }
      ],
      alignment: DialogAlignment.Center
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        this.showMessage('请直接编辑下方棋盘（长按数字可以修改）', 0);
      }
    });
  }

  loadGridFromArray(grid: number[]): void {
    this.puzzle = [...grid];
    this.currentGrid = [...grid];
    this.fixedCells = new Array<boolean>(81).fill(false);
    for (let i: number = 0; i < 81; i++) {
      if (grid[i] !== EMPTY) {
        this.fixedCells[i] = true;
      }
    }
    this.clearCandidates();
    this.clearSelection();
    this.updateConflicts();
    this.highlightDigit = 0;
  }

  toggleCandidateMode(): void {
    this.candidateMode = !this.candidateMode;
    if (!this.candidateMode) {
      this.clearCandidates();
    }
  }

  clearCandidates(): void {
    for (let i: number = 0; i < 81; i++) {
      this.candidates[i] = new Set<number>();
    }
    this.candidateMode = false;
  }

  handleCellClick(row: number, col: number): void {
    if (this.fixedCells[row * SIZE + col]) {
      this.selectedRow = row;
      this.selectedCol = col;
      this.highlightDigit = this.currentGrid[row * SIZE + col];
      this.showNumberPad = false;
      return;
    }
    if (this.selectedRow === row && this.selectedCol === col) {
      const idx: number = row * SIZE + col;
      this.currentGrid[idx] = EMPTY;
      this.hasUserInput = true;
      this.showNumberPad = false;
      this.highlightDigit = 0;
      this.updateConflicts();
      return;
    }
    this.selectedRow = row;
    this.selectedCol = col;
    this.showNumberPad = true;
    this.highlightDigit = this.currentGrid[row * SIZE + col];
  }

  inputNumber(num: number): void {
    if (this.selectedRow < 0 || this.selectedCol < 0) {
      return;
    }

    const idx: number = this.selectedRow * SIZE + this.selectedCol;
    if (this.fixedCells[idx]) {
      return;
    }

    if (this.candidateMode) {
      const set: Set<number> = this.candidates[idx];
      if (set.has(num)) {
        set.delete(num);
      } else {
        set.add(num);
      }
      this.candidates[idx] = new Set(set);
    } else {
      this.currentGrid[idx] = num;
      this.showNumberPad = false;
      this.hasUserInput = true;
      this.highlightDigit = num;
      this.updateConflicts();
    }
  }

  eraseCell(): void {
    if (this.selectedRow < 0 || this.selectedCol < 0) {
      return;
    }
    const idx: number = this.selectedRow * SIZE + this.selectedCol;
    if (!this.fixedCells[idx]) {
      this.currentGrid[idx] = EMPTY;
      this.candidates[idx] = new Set<number>();
      this.showNumberPad = false;
      this.hasUserInput = true;
      this.highlightDigit = 0;
      this.updateConflicts();
    }
  }

  clearSelection(): void {
    this.selectedRow = -1;
    this.selectedCol = -1;
    this.showNumberPad = false;
  }

  showMessage(text: string, type: number): void {
    this.message = text;
    this.messageType = type;
    setTimeout(() => {
      if (this.message === text) {
        this.message = '';
      }
    }, 3000);
  }

  clearMessage(): void {
    this.message = '';
  }

  getMessageColor(): string {
    if (this.messageType === 1) {
      return '#16a34a';
    }
    if (this.messageType === 2) {
      return '#dc2626';
    }
    return '#6366f1';
  }

  getCellBg(row: number, col: number): ResourceColor {
    const boxParity: number = (Math.floor(row / 3) + Math.floor(col / 3)) % 2;

    if (row === this.selectedRow && col === this.selectedCol) {
      return '#c7d2fe';
    }

    const val: number = this.currentGrid[row * SIZE + col];
    if (this.highlightDigit > 0 && val === this.highlightDigit) {
      return '#ddd6fe';
    }

    if (this.selectedRow >= 0) {
      const sameRow: boolean = row === this.selectedRow;
      const sameCol: boolean = col === this.selectedCol;
      const sameBox: boolean = Math.floor(this.selectedRow / 3) === Math.floor(row / 3) &&
        Math.floor(this.selectedCol / 3) === Math.floor(col / 3);
      if (sameRow || sameCol || sameBox) {
        return boxParity === 0 ? '#eef2ff' : '#eef4ff';
      }
    }

    return boxParity === 0 ? '#ffffff' : '#f8fafc';
  }

  getCellTextColor(row: number, col: number): ResourceColor {
    const idx: number = row * SIZE + col;
    if (this.conflictCells[idx]) {
      return '#dc2626';
    }
    if (this.fixedCells[idx]) {
      return $r('app.color.primary_text');
    }
    return '#6366f1';
  }

  getCellBorderWidth(row: number, col: number): EdgeWidths {
    const top: number = row % 3 === 0 ? 2 : 0.5;
    const left: number = col % 3 === 0 ? 2 : 0.5;
    const bottom: number = row === 8 ? 2 : (row % 3 === 2 ? 2 : 0.5);
    const right: number = col === 8 ? 2 : (col % 3 === 2 ? 2 : 0.5);
    return { top, left, bottom, right };
  }

  getDigitCount(d: number): number {
    let count: number = 0;
    for (let i: number = 0; i < 81; i++) {
      if (this.currentGrid[i] === d) {
        count++;
      }
    }
    return count;
  }

  build() {
    Column() {
      this.TopBar()

      if (this.message.length > 0) {
        Row() {
          Text(this.message)
            .fontSize(13)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Medium)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .borderRadius({ topLeft: 0, topRight: 0, bottomLeft: 8, bottomRight: 8 })
        .backgroundColor(this.getMessageColor())
        .margin({ left: 16, right: 16 })
      }

      Scroll(this.scroller) {
        Column() {
          this.OCRToolbar()

          this.SudokuBoard()

          if (this.showNumberPad) {
            this.NumberPad()
          }

          this.ActionButtons()

          this.DifficultySelector()

          Column().height(24)
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  TopBar() {
    Row() {
      Row({ space: 4 }) {
        Text('🧩')
          .fontSize(16)
        Text('数独求解器')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
      }

      Blank()

      if (this.hasUserInput) {
        Text('清空')
          .fontSize(13)
          .fontColor('#ef4444')
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(12)
          .backgroundColor('#fef2f2')
          .onClick(() => { this.clearGrid(); })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 4 })
  }

  @Builder
  OCRToolbar() {
    Row({ space: 8 }) {
      Button() {
        Row({ space: 4 }) {
          Text('\u{1F4F7}').fontSize(14)
          Text(this.recognizing ? '识别中...' : '拍照识别').fontSize(12)
        }
      }
      .fontColor(Color.White)
      .backgroundColor('#6366f1')
      .borderRadius(16)
      .height(32)
      .enabled(!this.recognizing)
      .layoutWeight(1)
      .onClick(() => { this.takePhoto(); })

      Button() {
        Row({ space: 4 }) {
          Text('\u{1F5BC}').fontSize(14)
          Text('相册选图').fontSize(12)
        }
      }
      .fontColor('#6366f1')
      .backgroundColor('#eef2ff')
      .borderRadius(16)
      .height(32)
      .enabled(!this.recognizing)
      .layoutWeight(1)
      .onClick(() => { this.pickFromGallery(); })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 4 })
  }

  @Builder
  SudokuBoard() {
    Column() {
      Column() {
        ForEach([0, 1, 2], (boxRow: number) => {
          Row() {
            ForEach([0, 1, 2], (boxCol: number) => {
              Column() {
                ForEach([0, 1, 2], (cellR: number) => {
                  Row() {
                    ForEach([0, 1, 2], (cellC: number) => {
                      this.Cell(boxRow * 3 + cellR, boxCol * 3 + cellC)
                    })
                  }
                })
              }
            })
          }
        })
      }
      .border({ width: 2.5, color: '#334155', radius: 8 })
      .shadow({ radius: 8, color: '#1e293b1a', offsetX: 0, offsetY: 2 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  Cell(row: number, col: number) {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.getCellBg(row, col))

      if (this.currentGrid[row * SIZE + col] !== EMPTY) {
        Text(this.currentGrid[row * SIZE + col].toString())
          .fontSize(this.boardCellSize * 0.42)
          .fontWeight(this.fixedCells[row * SIZE + col] ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.getCellTextColor(row, col))
          .textAlign(TextAlign.Center)
      } else if (this.candidates[row * SIZE + col].size > 0) {
        this.CandidateGrid(row * SIZE + col)
      }
    }
    .width(this.boardCellSize)
    .height(this.boardCellSize)
    .border({
      width: this.getCellBorderWidth(row, col),
      color: '#94a3b8',
      style: BorderStyle.Solid
    })
    .onClick(() => { this.handleCellClick(row, col); })
  }

  @Builder
  CandidateGrid(idx: number) {
    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center, alignItems: ItemAlign.Center }) {
      ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9], (d: number) => {
        if (this.candidates[idx].has(d)) {
          Text(d.toString())
            .fontSize(this.boardCellSize * 0.18)
            .fontColor('#94a3b8')
            .width(this.boardCellSize * 0.3)
            .height(this.boardCellSize * 0.3)
            .textAlign(TextAlign.Center)
        } else {
          Text('')
            .width(this.boardCellSize * 0.3)
            .height(this.boardCellSize * 0.3)
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding(1)
  }

  @Builder
  NumberPad() {
    Column() {
      Row({ space: 4 }) {
        ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9], (num: number) => {
          Stack() {
            Button(num.toString())
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.getDigitCount(num) >= 9 ? '#cbd5e1' : $r('app.color.primary_text'))
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(10)
              .width(34)
              .height(34)
              .padding(0)
              .enabled(this.getDigitCount(num) < 9)
              .onClick(() => { this.inputNumber(num); })

            if (this.getDigitCount(num) >= 9) {
              Text('\u2713')
                .fontSize(10)
                .fontColor('#22c55e')
                .fontWeight(FontWeight.Bold)
                .margin({ top: 2 })
            }
          }
          .width(34)
          .height(34)
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Row({ space: 8 }) {
        Button(this.candidateMode ? '\u270E 候选中' : '\u270E 候选数')
          .fontSize(11)
          .fontColor(this.candidateMode ? Color.White : '#6366f1')
          .backgroundColor(this.candidateMode ? '#6366f1' : '#eef2ff')
          .borderRadius(10)
          .height(28)
          .layoutWeight(1)
          .onClick(() => { this.toggleCandidateMode(); })

        Button('\u232B 擦除')
          .fontSize(11)
          .fontColor('#ef4444')
          .backgroundColor('#fef2f2')
          .borderRadius(10)
          .height(28)
          .layoutWeight(1)
          .onClick(() => { this.eraseCell(); })

        Text('\u2715')
          .fontSize(14)
          .fontColor($r('app.color.tertiary_text'))
          .width(28)
          .height(28)
          .textAlign(TextAlign.Center)
          .borderRadius(10)
          .backgroundColor($r('app.color.card_background'))
          .onClick(() => { this.showNumberPad = false; })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 6 })
    }
    .width('100%')
    .padding({ top: 8, bottom: 4, left: 16, right: 16 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius({ topLeft: 12, topRight: 12 })
    .shadow({ radius: 4, color: '#1e293b0d', offsetX: 0, offsetY: -2 })
  }

  @Builder
  ActionButtons() {
    Row({ space: 8 }) {
      Button(this.solving ? '求解中...' : '\u{1F50D} 求解')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .backgroundColor('#6366f1')
        .borderRadius(20)
        .height(40)
        .layoutWeight(1)
        .enabled(!this.solving)
        .onClick(() => { this.solve(); })

      Button('\u{1F4A1} 提示')
        .fontSize(14)
        .fontColor('#6366f1')
        .backgroundColor('#eef2ff')
        .borderRadius(20)
        .height(40)
        .layoutWeight(1)
        .onClick(() => { this.showHint(); })

      Button('\u{1F4CB} 粘贴')
        .fontSize(14)
        .fontColor($r('app.color.tertiary_text'))
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(20)
        .height(40)
        .layoutWeight(1)
        .onClick(() => { this.showPasteDialog(); })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 6 })
  }

  @Builder
  DifficultySelector() {
    Column() {
      Row() {
        Row({ space: 2 }) {
          ForEach(DIFFICULTY_NAMES, (name: string, index: number) => {
            Text(name)
              .fontSize(13)
              .fontWeight(this.currentDifficulty === index ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.currentDifficulty === index ? '#6366f1' : $r('app.color.tertiary_text'))
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .borderRadius(16)
              .backgroundColor(
                this.currentDifficulty === index ? '#eef2ff' : Color.Transparent
              )
              .onClick(() => { this.loadPuzzle(index); })
          })
        }
        .border({ width: 1, color: '#e2e8f0', radius: 20 })
        .backgroundColor($r('app.color.card_background'))
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Text('点击空格输入数字 | 相同数字高亮显示 | 长按清空')
        .fontSize(11)
        .fontColor($r('app.color.tertiary_text'))
        .textAlign(TextAlign.Center)
        .margin({ top: 8 })
        .padding({ left: 24, right: 24 })
    }
    .width('100%')
    .padding({ top: 6 })
  }
}
