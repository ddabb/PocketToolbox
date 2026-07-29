import { Rect, SpatialHash } from './SpatialHash';
import { CollisionMask } from './CollisionMask';
import { PlacedWord } from '../../model/WordItem';

export interface PlaceInput {
  text: string;
  size: number;
  weight: number;
  font: string;
}

export class SpiralPlacer {
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;
  private spatialHash: SpatialHash = new SpatialHash(100);
  private collisionMask: CollisionMask | null = null;
  private placedRects: Rect[] = [];
  private readonly SPIRAL_A: number = 1;
  private readonly SPIRAL_B: number = 1;
  private readonly DELTA_THETA: number = 0.1;
  private readonly MAX_THETA: number = 360;
  private readonly MAX_SPIRAL_FAIL: number = 200;
  private readonly WORD_PADDING: number = 6;

  constructor(width: number, height: number) {
    this.canvasWidth = width;
    this.canvasHeight = height;
    this.collisionMask = new CollisionMask(width, height);
  }

  place(inputWords: PlaceInput[]): PlacedWord[] {
    this.spatialHash = new SpatialHash(100);
    this.collisionMask = new CollisionMask(this.canvasWidth, this.canvasHeight);
    this.placedRects = [];

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

    while (theta < startTheta + this.MAX_THETA * Math.PI) {
      let r: number = this.SPIRAL_A + this.SPIRAL_B * (theta - startTheta);
      let px: number = cx + r * Math.cos(theta);
      let py: number = cy + r * Math.sin(theta);

      let rect: Rect = Rect.fromCenter(px, py, w + this.WORD_PADDING * 2, h + this.WORD_PADDING * 2);

      if (this.collisionMask !== null && !this.collisionMask.isInsideCanvas(rect)) {
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
      if (this.collisionMask !== null) {
        this.collisionMask.markOccupied(rect, this.WORD_PADDING);
      }
      this.placedRects.push(rect);

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
    for (let i = 0; i < attempts; i++) {
      let px: number = w / 2 + Math.random() * (this.canvasWidth - w);
      let py: number = h / 2 + Math.random() * (this.canvasHeight - h);
      let rect: Rect = Rect.fromCenter(px, py, w + this.WORD_PADDING * 2, h + this.WORD_PADDING * 2);

      if (this.collisionMask !== null && !this.collisionMask.isInsideCanvas(rect)) {
        continue;
      }
      if (this.spatialHash.hasCollision(rect)) {
        continue;
      }

      this.spatialHash.insert(rect);
      if (this.collisionMask !== null) {
        this.collisionMask.markOccupied(rect, this.WORD_PADDING);
      }
      this.placedRects.push(rect);

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

  private estimateTextWidth(text: string, fontSize: number): number {
    let charCount: number = text.length;
    let avgCharWidth: number = fontSize * 0.7;
    return charCount * avgCharWidth;
  }
}
