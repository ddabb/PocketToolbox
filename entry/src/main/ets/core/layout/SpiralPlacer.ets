import { Rect, SpatialHash } from './SpatialHash';
import { PlacedWord } from '../../model/WordItem';

export class PlaceInput {
  text: string = '';
  size: number = 0;
  weight: number = 0;
  font: string = '';
}

export class SpiralPlacer {
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;
  private spatialHash: SpatialHash = new SpatialHash(100);
  private readonly SPIRAL_A: number = 1;
  private readonly SPIRAL_B: number = 1;
  private readonly DELTA_THETA: number = 0.1;
  private readonly MAX_THETA: number = 360;
  private readonly MAX_SPIRAL_FAIL: number = 200;
  private readonly WORD_PADDING: number = 4;

  constructor(width: number, height: number) {
    this.canvasWidth = width;
    this.canvasHeight = height;
  }

  place(inputWords: PlaceInput[]): PlacedWord[] {
    this.spatialHash = new SpatialHash(100);

    let sorted: PlaceInput[] = inputWords.slice();
    sorted.sort((a: PlaceInput, b: PlaceInput) => b.weight - a.weight);

    let cx: number = this.canvasWidth / 2;
    let cy: number = this.canvasHeight / 2;
    let results: PlacedWord[] = [];

    for (let i = 0; i < sorted.length; i++) {
      let word: PlaceInput = sorted[i];
      let textW: number = this.estimateTextWidth(word.text, word.size);
      let textH: number = word.size * 1.2;
      let placed: PlacedWord | null = this.tryPlaceWord(word, cx, cy, textW, textH, 0);
      if (placed === null) {
        placed = this.tryPlaceWord(word, cx, cy, textH, textW, 90);
      }
      if (placed === null) {
        placed = this.tryMonteCarlo(word, textW, textH);
      }
      if (placed !== null) {
        results.push(placed);
      }
    }
    return results;
  }

  private tryPlaceWord(word: PlaceInput, cx: number, cy: number,
    w: number, h: number, angle: number): PlacedWord | null {
    let startTheta: number = Math.random() * Math.PI * 2;
    let theta: number = startTheta;
    let failCount: number = 0;
    let paddedW: number = w + this.WORD_PADDING * 2;
    let paddedH: number = h + this.WORD_PADDING * 2;

    while (theta < startTheta + this.MAX_THETA * Math.PI) {
      let r: number = this.SPIRAL_A + this.SPIRAL_B * (theta - startTheta);
      let px: number = cx + r * Math.cos(theta);
      let py: number = cy + r * Math.sin(theta);

      let rect: Rect = Rect.fromCenter(px, py, paddedW, paddedH);

      if (!this.isInsideCanvas(rect)) {
        theta += this.DELTA_THETA;
        continue;
      }

      if (this.spatialHash.hasCollision(rect)) {
        failCount++;
        if (failCount > this.MAX_SPIRAL_FAIL) {
          return null;
        }
        theta += this.DELTA_THETA;
        continue;
      }

      this.spatialHash.insert(rect);

      let pw: PlacedWord = new PlacedWord();
      pw.text = word.text;
      pw.x = px;
      pw.y = py;
      pw.size = word.size;
      pw.color = '';
      pw.angle = angle;
      pw.font = word.font;
      pw.width = w;
      pw.height = h;
      return pw;
    }
    return null;
  }

  private tryMonteCarlo(word: PlaceInput, w: number, h: number): PlacedWord | null {
    let attempts: number = 500;
    let paddedW: number = w + this.WORD_PADDING * 2;
    let paddedH: number = h + this.WORD_PADDING * 2;
    for (let i = 0; i < attempts; i++) {
      let px: number = paddedW / 2 + Math.random() * (this.canvasWidth - paddedW);
      let py: number = paddedH / 2 + Math.random() * (this.canvasHeight - paddedH);
      let rect: Rect = Rect.fromCenter(px, py, paddedW, paddedH);

      if (!this.isInsideCanvas(rect)) {
        continue;
      }
      if (this.spatialHash.hasCollision(rect)) {
        continue;
      }

      this.spatialHash.insert(rect);

      let pw: PlacedWord = new PlacedWord();
      pw.text = word.text;
      pw.x = px;
      pw.y = py;
      pw.size = word.size;
      pw.color = '';
      pw.angle = 0;
      pw.font = word.font;
      pw.width = w;
      pw.height = h;
      return pw;
    }
    return null;
  }

  private isInsideCanvas(rect: Rect): boolean {
    return rect.left >= 0 && rect.top >= 0 &&
      rect.right <= this.canvasWidth && rect.bottom <= this.canvasHeight;
  }

  private estimateTextWidth(text: string, fontSize: number): number {
    let charCount: number = text.length;
    let avgCharWidth: number = fontSize * 0.7;
    return charCount * avgCharWidth;
  }
}
