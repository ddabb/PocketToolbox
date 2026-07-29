export class Rect {
  x: number = 0;
  y: number = 0;
  width: number = 0;
  height: number = 0;

  get left(): number {
    return this.x;
  }

  get right(): number {
    return this.x + this.width;
  }

  get top(): number {
    return this.y;
  }

  get bottom(): number {
    return this.y + this.height;
  }

  static fromCenter(cx: number, cy: number, w: number, h: number): Rect {
    let r: Rect = new Rect();
    r.x = cx - w / 2;
    r.y = cy - h / 2;
    r.width = w;
    r.height = h;
    return r;
  }

  intersects(other: Rect): boolean {
    return !(this.right <= other.left || other.right <= this.left ||
      this.bottom <= other.top || other.bottom <= this.top);
  }
}

export class SpatialHash {
  private cellSize: number = 96;
  private grid: Map<number, Rect[]> = new Map();

  constructor(cellSize: number) {
    this.cellSize = cellSize > 0 ? cellSize : 96;
  }

  clear(): void {
    this.grid.clear();
  }

  private key(col: number, row: number): number {
    return col * 73856093 ^ row * 19349663;
  }

  private cellIndices(rect: Rect): CellRange {
    let c1: number = Math.floor(rect.left / this.cellSize);
    let r1: number = Math.floor(rect.top / this.cellSize);
    let c2: number = Math.floor(rect.right / this.cellSize);
    let r2: number = Math.floor(rect.bottom / this.cellSize);
    let range: CellRange = new CellRange();
    range.c1 = c1;
    range.r1 = r1;
    range.c2 = c2;
    range.r2 = r2;
    return range;
  }

  insert(rect: Rect): void {
    let range: CellRange = this.cellIndices(rect);
    for (let c = range.c1; c <= range.c2; c++) {
      for (let r = range.r1; r <= range.r2; r++) {
        let k: number = this.key(c, r);
        let bucket: Rect[] | undefined = this.grid.get(k);
        if (bucket === undefined) {
          bucket = [];
          this.grid.set(k, bucket);
        }
        bucket.push(rect);
      }
    }
  }

  hasCollision(rect: Rect): boolean {
    let range: CellRange = this.cellIndices(rect);
    for (let c = range.c1; c <= range.c2; c++) {
      for (let r = range.r1; r <= range.r2; r++) {
        let k: number = this.key(c, r);
        let bucket: Rect[] | undefined = this.grid.get(k);
        if (bucket === undefined) {
          continue;
        }
        for (let i = 0; i < bucket.length; i++) {
          if (rect.intersects(bucket[i])) {
            return true;
          }
        }
      }
    }
    return false;
  }
}

class CellRange {
  c1: number = 0;
  r1: number = 0;
  c2: number = 0;
  r2: number = 0;
}
