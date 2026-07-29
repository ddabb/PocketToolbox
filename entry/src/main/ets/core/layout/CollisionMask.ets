import { Rect } from './SpatialHash';

export class CollisionMask {
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;
  private occupied: Set<number> = new Set();
  private padding: number = 4;

  constructor(width: number, height: number) {
    this.canvasWidth = width;
    this.canvasHeight = height;
  }

  markOccupied(rect: Rect, padding: number): void {
    let p: number = padding > 0 ? padding : this.padding;
    let x1: number = Math.max(0, Math.floor(rect.left - p));
    let y1: number = Math.max(0, Math.floor(rect.top - p));
    let x2: number = Math.min(this.canvasWidth - 1, Math.ceil(rect.right + p));
    let y2: number = Math.min(this.canvasHeight - 1, Math.ceil(rect.bottom + p));
    for (let x = x1; x <= x2; x++) {
      for (let y = y1; y <= y2; y++) {
        this.occupied.add(y * this.canvasWidth + x);
      }
    }
  }

  hasCollision(rect: Rect): boolean {
    let x1: number = Math.max(0, Math.floor(rect.left));
    let y1: number = Math.max(0, Math.floor(rect.top));
    let x2: number = Math.min(this.canvasWidth - 1, Math.ceil(rect.right));
    let y2: number = Math.min(this.canvasHeight - 1, Math.ceil(rect.bottom));
    for (let x = x1; x <= x2; x++) {
      for (let y = y1; y <= y2; y++) {
        if (this.occupied.has(y * this.canvasWidth + x)) {
          return true;
        }
      }
    }
    return false;
  }

  isInsideCanvas(rect: Rect): boolean {
    return rect.left >= 0 && rect.top >= 0 &&
      rect.right <= this.canvasWidth && rect.bottom <= this.canvasHeight;
  }

  clear(): void {
    this.occupied.clear();
  }
}
