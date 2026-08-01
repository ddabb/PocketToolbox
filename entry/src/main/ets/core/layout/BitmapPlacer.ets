import { ShapeDef, GlyphMask } from './ShapeDef';
import { PlacedWord } from '../../model/WordItem';

export class RandomPoint {
  x: number = 0;
  y: number = 0;
}

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
  private shapeOutside: Uint8Array = new Uint8Array(0);
  private readonly SPIRAL_STEP: number = 0.7;
  private readonly SPIRAL_TURNS: number = 0.22;
  private readonly MAX_SPIRAL_FAIL: number = 20000;
  private readonly WORD_PADDING: number = 1;
  private readonly RANDOM_STARTS: number = 90;
  private readonly MAX_SPIRAL_T: number = 4000;

  constructor(canvasSize: number) {
    this.canvasSize = canvasSize;
    this.boardWidth = Math.ceil(canvasSize / 32);
    this.board = new Uint32Array(this.boardWidth * canvasSize);
    this.shapeOutside = new Uint8Array(canvasSize * canvasSize);
  }

  place(words: WordSprite[], shapeOrFn: ShapeDef | ((theta: number) => number)): PlacedWord[] {
    let shape: ShapeDef;
    if (typeof shapeOrFn === 'function') {
      shape = new ShapeDef('legacy', 'legacy', shapeOrFn as ((theta: number) => number), 0.6);
    } else {
      shape = shapeOrFn;
    }
    console.info('[BitmapPlacer] place START, words=' + words.length.toString() +
      ', canvasSize=' + this.canvasSize.toString() +
      ', mode=' + (shape.bitmap ? 'bitmap' : 'polar'));
    this.board.fill(0);
    this.shapeOutside.fill(0);
    this.buildShapeMask(shape);

    let sorted: WordSprite[] = words.slice();
    sorted.sort((a: WordSprite, b: WordSprite): number => { return b.weight - a.weight; });

    let cx: number = this.canvasSize / 2;
    let cy: number = this.canvasSize / 2;
    let results: PlacedWord[] = [];
    let failCount: number = 0;

    for (let i: number = 0; i < sorted.length; i++) {
      let word: WordSprite = sorted[i];
      let headCount: number = Math.max(1, Math.floor(sorted.length * 0.2));
      let angles: number[];
      if (i < headCount) {
        angles = [0, 90];
      } else {
        angles = [0, 90, 45, 135];
      }

      let placed: PlacedWord | null = null;

      for (let s: number = 0; s < this.RANDOM_STARTS && placed === null; s++) {
        let start: RandomPoint | null = this.randomPointInShape(cx, cy, shape);
        if (start === null) {
          continue;
        }
        for (let ai: number = 0; ai < angles.length && placed === null; ai++) {
          placed = this.trySpiralFrom(word, start.x, start.y, cx, cy, angles[ai], shape);
        }
      }

      if (placed === null) {
        for (let ai: number = 0; ai < angles.length && placed === null; ai++) {
          placed = this.trySpiralFrom(word, cx, cy, cx, cy, angles[ai], shape);
        }
      }

      if (placed !== null) {
        results.push(placed);
      } else {
        failCount++;
      }
    }
    console.info('[BitmapPlacer] place DONE, placed=' + results.length.toString() +
      ', failed=' + failCount.toString() + '/' + sorted.length.toString());
    return results;
  }

  private buildShapeMask(shape: ShapeDef): void {
    let cx: number = this.canvasSize / 2;
    let cy: number = this.canvasSize / 2;
    let maxR: number = cx * 0.98;

    if (shape.bitmap) {
      let bm: GlyphMask = shape.bitmap;
      let s: number = bm.size;
      let scale: number = this.canvasSize / s;
      for (let y: number = 0; y < this.canvasSize; y++) {
        let sy: number = Math.min(s - 1, Math.floor(y / scale));
        for (let x: number = 0; x < this.canvasSize; x++) {
          let sx: number = Math.min(s - 1, Math.floor(x / scale));
          if (bm.data[sy * s + sx] !== 1) {
            this.shapeOutside[y * this.canvasSize + x] = 1;
            let wordIdx: number = Math.floor(x / 32);
            let bitIdx: number = x % 32;
            this.board[y * this.boardWidth + wordIdx] |= (1 << bitIdx);
          }
        }
      }
      return;
    }

    for (let y: number = 0; y < this.canvasSize; y++) {
      for (let x: number = 0; x < this.canvasSize; x++) {
        let dx: number = x - cx;
        let dy: number = cy - y;
        let r: number = Math.sqrt(dx * dx + dy * dy);
        let theta: number = Math.atan2(dy, dx);
        let rMax: number = shape.maskAt(theta) * maxR;
        if (r > rMax) {
          this.shapeOutside[y * this.canvasSize + x] = 1;
          let wordIdx: number = Math.floor(x / 32);
          let bitIdx: number = x % 32;
          this.board[y * this.boardWidth + wordIdx] |= (1 << bitIdx);
        }
      }
    }
  }

  private isOutsideShape(x: number, y: number): boolean {
    let ix: number = Math.floor(x);
    let iy: number = Math.floor(y);
    if (ix < 0 || iy < 0 || ix >= this.canvasSize || iy >= this.canvasSize) {
      return true;
    }
    return this.shapeOutside[iy * this.canvasSize + ix] === 1;
  }

  private boxOutsideShape(x1: number, y1: number, x2: number, y2: number): boolean {
    let step: number = 3;
    for (let y: number = y1; y <= y2; y += step) {
      for (let x: number = x1; x <= x2; x += step) {
        if (this.isOutsideShape(x, y)) {
          return true;
        }
      }
    }
    let corners: number[][] = [
      [x1, y1], [x2, y1], [x1, y2], [x2, y2]
    ];
    for (let c: number = 0; c < 4; c++) {
      if (this.isOutsideShape(corners[c][0], corners[c][1])) {
        return true;
      }
    }
    return false;
  }

  private randomPointInShape(cx: number, cy: number,
    shape: ShapeDef): RandomPoint | null {
    for (let attempt: number = 0; attempt < 50; attempt++) {
      let rx: number = Math.random() * (this.canvasSize - 1);
      let ry: number = Math.random() * (this.canvasSize - 1);
      if (!this.isOutsideShape(rx, ry)) {
        let pt: RandomPoint = new RandomPoint();
        pt.x = rx;
        pt.y = ry;
        return pt;
      }
    }
    return null;
  }

  private trySpiralFrom(word: WordSprite, sx: number, sy: number,
    cx: number, cy: number, angle: number, shape: ShapeDef): PlacedWord | null {
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

    while (t < this.MAX_SPIRAL_T) {
      let r: number = this.SPIRAL_STEP * t;
      let a: number = t * this.SPIRAL_TURNS;
      let px: number = sx + r * Math.cos(a);
      let py: number = sy + r * Math.sin(a);

      let x1: number = Math.floor(px - halfW);
      let y1: number = Math.floor(py - halfH);
      let x2: number = Math.ceil(px + halfW);
      let y2: number = Math.ceil(py + halfH);

      if (x1 < 0 || y1 < 0 || x2 >= this.canvasSize || y2 >= this.canvasSize) {
        t += 1;
        continue;
      }

      if (this.boxOutsideShape(x1, y1, x2, y2)) {
        t += 1;
        continue;
      }

      if (this.checkCollision(x1, y1, x2, y2)) {
        failCount++;
        if (failCount > this.MAX_SPIRAL_FAIL) {
          return null;
        }
        t += 1;
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
