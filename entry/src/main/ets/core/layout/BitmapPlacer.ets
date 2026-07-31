import { ShapeDef } from './ShapeDef';
import { PlacedWord } from '../../model/WordItem';

export class WordSprite {
  text: string = '';
  width: number = 0;
  height: number = 0;
  x0: number = 0;
  y0: number = 0;
  sprite: number[] = [];
  fontSize: number = 0;
  angle: number = 0;
  font: string = '';
  weight: number = 0;
}

export class BitmapPlacer {
  private canvasSize: number = 0;
  private board: Uint32Array = new Uint32Array(0);
  private boardWidth: number = 0;
  private readonly SPIRAL_STEP: number = 0.1;
  private readonly MAX_SPIRAL_FAIL: number = 500;
  private readonly WORD_PADDING: number = 2;

  constructor(canvasSize: number) {
    this.canvasSize = canvasSize;
    this.boardWidth = Math.ceil(canvasSize / 32);
    this.board = new Uint32Array(this.boardWidth * canvasSize);
  }

  place(words: WordSprite[], shapeFn: (theta: number) => number): PlacedWord[] {
    console.info('[BitmapPlacer] place START, words=' + words.length.toString() +
      ', canvasSize=' + this.canvasSize.toString() +
      ', boardWidth=' + this.boardWidth.toString());
    this.board.fill(0);
    console.info('[BitmapPlacer] board cleared, applying shape mask...');
    this.applyShapeMask(shapeFn);
    console.info('[BitmapPlacer] shape mask applied');

    let sorted: WordSprite[] = words.slice();
    sorted.sort((a: WordSprite, b: WordSprite): number => { return b.weight - a.weight; });

    let cx: number = this.canvasSize / 2;
    let cy: number = this.canvasSize / 2;
    let results: PlacedWord[] = [];
    let total: number = sorted.length;
    let headCount: number = Math.max(1, Math.floor(total * 0.2));
    let failCount: number = 0;

    for (let i: number = 0; i < sorted.length; i++) {
      let word: WordSprite = sorted[i];
      let angles: number[];
      if (i < headCount) {
        angles = [0, 90];
      } else {
        angles = [0, 90];
      }

      let placed: PlacedWord | null = null;
      for (let ai: number = 0; ai < angles.length && placed === null; ai++) {
        placed = this.trySpiralPlace(word, cx, cy, angles[ai], shapeFn);
      }

      if (placed !== null) {
        results.push(placed);
      } else {
        failCount++;
      }
    }
    console.info('[BitmapPlacer] place DONE, placed=' + results.length.toString() +
      ', failed=' + failCount.toString() + '/' + total.toString());
    return results;
  }

  private applyShapeMask(shapeFn: (theta: number) => number): void {
    let cx: number = this.canvasSize / 2;
    let cy: number = this.canvasSize / 2;
    let maxR: number = cx * 0.9;

    for (let y: number = 0; y < this.canvasSize; y++) {
      for (let x: number = 0; x < this.canvasSize; x++) {
        let dx: number = x - cx;
        let dy: number = y - cy;
        let r: number = Math.sqrt(dx * dx + dy * dy);
        let theta: number = Math.atan2(dy, dx);
        let rMax: number = shapeFn(theta) * maxR;
        if (r > rMax) {
          let wordIdx: number = Math.floor(x / 32);
          let bitIdx: number = x % 32;
          this.board[y * this.boardWidth + wordIdx] |= (1 << bitIdx);
        }
      }
    }
  }

  private trySpiralPlace(word: WordSprite, cx: number, cy: number,
    angle: number, shapeFn: (theta: number) => number): PlacedWord | null {
    let w: number = word.width;
    let h: number = word.height;
    if (angle === 90) {
      w = word.height;
      h = word.width;
    }

    let pad: number = this.WORD_PADDING;
    let halfW: number = (w + pad * 2) / 2;
    let halfH: number = (h + pad * 2) / 2;

    let t: number = 0;
    let failCount: number = 0;
    let maxR: number = (this.canvasSize / 2) * 0.9;

    while (t < 200) {
      let r: number = 0.1 * t;
      let px: number = cx + r * Math.cos(t);
      let py: number = cy + r * Math.sin(t);

      let dx: number = px - cx;
      let dy: number = py - cy;
      let dist: number = Math.sqrt(dx * dx + dy * dy);
      let theta: number = Math.atan2(dy, dx);
      let rMax: number = shapeFn(theta) * maxR;
      if (dist > rMax) {
        t += this.SPIRAL_STEP;
        continue;
      }

      let x1: number = Math.floor(px - halfW);
      let y1: number = Math.floor(py - halfH);
      let x2: number = Math.ceil(px + halfW);
      let y2: number = Math.ceil(py + halfH);

      if (x1 < 0 || y1 < 0 || x2 >= this.canvasSize || y2 >= this.canvasSize) {
        t += this.SPIRAL_STEP;
        continue;
      }

      if (this.checkCollision(x1, y1, x2, y2)) {
        failCount++;
        if (failCount > this.MAX_SPIRAL_FAIL) {
          return null;
        }
        t += this.SPIRAL_STEP;
        continue;
      }

      this.markBoardOccupied(x1, y1, x2, y2);

      let pw: PlacedWord = new PlacedWord();
      pw.text = word.text;
      pw.x = px;
      pw.y = py;
      pw.size = word.fontSize;
      pw.color = '';
      pw.angle = angle;
      pw.font = word.font;
      pw.width = w;
      pw.height = h;
      return pw;
    }
    return null;
  }

  private checkCollision(x1: number, y1: number, x2: number, y2: number): boolean {
    for (let y: number = y1; y <= y2; y++) {
      let rowOff: number = y * this.boardWidth;
      for (let x: number = x1; x <= x2;) {
        let wordIdx: number = Math.floor(x / 32);
        let bitStart: number = x % 32;
        let xEnd: number = Math.min(x + (32 - bitStart), x2 + 1);
        let bitLen: number = xEnd - x;
        let mask: number;
        if (bitLen >= 32) {
          mask = 0xFFFFFFFF;
        } else {
          mask = (1 << bitLen) - 1;
        }
        mask = mask << bitStart;
        if ((this.board[rowOff + wordIdx] & mask) !== 0) {
          return true;
        }
        x = xEnd;
      }
    }
    return false;
  }

  private markBoardOccupied(x1: number, y1: number, x2: number, y2: number): void {
    for (let y: number = y1; y <= y2; y++) {
      let rowOff: number = y * this.boardWidth;
      for (let x: number = x1; x <= x2;) {
        let wordIdx: number = Math.floor(x / 32);
        let bitStart: number = x % 32;
        let xEnd: number = Math.min(x + (32 - bitStart), x2 + 1);
        let bitLen: number = xEnd - x;
        let mask: number;
        if (bitLen >= 32) {
          mask = 0xFFFFFFFF;
        } else {
          mask = (1 << bitLen) - 1;
        }
        mask = mask << bitStart;
        this.board[rowOff + wordIdx] |= mask;
        x = xEnd;
      }
    }
  }

  makeSprite(text: string, fontSize: number, font: string, weight: number,
    angle: number): WordSprite {
    let sprite: WordSprite = new WordSprite();
    sprite.text = text;
    sprite.fontSize = fontSize;
    sprite.font = font;
    sprite.weight = weight;
    sprite.angle = angle;
    let textW: number = this.estimateTextWidth(text, fontSize);
    let textH: number = this.estimateTextHeight(fontSize);
    if (angle === 90) {
      sprite.width = textH;
      sprite.height = textW;
    } else {
      sprite.width = textW;
      sprite.height = textH;
    }
    return sprite;
  }

  private estimateTextWidth(text: string, fontSize: number): number {
    if (!text || text.length === 0) {
      return fontSize;
    }
    let width: number = 0;
    for (let i: number = 0; i < text.length; i++) {
      let code: number = text.charCodeAt(i);
      if ((code >= 0x4e00 && code <= 0x9fff) ||
        (code >= 0x3400 && code <= 0x4dbf) ||
        (code >= 0x3040 && code <= 0x30ff) ||
        (code >= 0xac00 && code <= 0xd7af)) {
        width += fontSize * 1.0;
      } else if (text.charAt(i) === ' ' || text.charAt(i) === '-') {
        width += fontSize * 0.3;
      } else {
        width += fontSize * 0.58;
      }
    }
    return width;
  }

  private estimateTextHeight(fontSize: number): number {
    return fontSize * 1.2;
  }
}
