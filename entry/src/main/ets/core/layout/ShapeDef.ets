import { LengthMetricsUnit } from '@kit.ArkUI';

export interface GlyphMask {
  data: Uint8Array;
  size: number;
}

export class ShapeDef {
  id: string;
  label: string;
  fn: (theta: number) => number;
  shapeRatio: number;
  // parametric outline (x(t), y(t)) in [-1,1], used by heart/leaf for clean shapes
  paramOutline?: (t: number) => [number, number];
  bitmap?: GlyphMask;
  glyphChar?: string;
  glyphFont?: string;
  private angleMask?: number[];
  private paramScale?: number;

  constructor(id: string, label: string, fn: (theta: number) => number, shapeRatio: number) {
    this.id = id;
    this.label = label;
    this.fn = fn;
    this.shapeRatio = shapeRatio;
  }

  // Mask test in normalized space: angle is radians; for bitmap shapes we map the
  // point by polar radius against the maximum radius at that angle.
  maskAt(angle: number): number {
    if (!this.paramOutline) {
      return this.fn(angle);
    }
    if (!this.angleMask) {
      this.buildAngleMask();
    }
    let sectors: number = 720;
    let a: number = angle % (Math.PI * 2);
    if (a < 0) {
      a += Math.PI * 2;
    }
    let idx: number = Math.floor((a / (Math.PI * 2)) * sectors) % sectors;
    return this.angleMask![idx];
  }

  private buildAngleMask(): void {
    let sectors: number = 720;
    let mask: number[] = [];
    for (let i: number = 0; i < sectors; i++) {
      mask.push(0);
    }
    let N: number = 2000;
    this.ensureParamScale();
    for (let i: number = 0; i <= N; i++) {
      let t: number = (i / N) * Math.PI * 2;
      let p: [number, number] = this.normParam(this.paramOutline!(t));
      let r: number = Math.sqrt(p[0] * p[0] + p[1] * p[1]);
      let ang: number = Math.atan2(p[1], p[0]);
      if (ang < 0) {
        ang += Math.PI * 2;
      }
      let idx: number = Math.floor((ang / (Math.PI * 2)) * sectors) % sectors;
      if (r > mask[idx]) {
        mask[idx] = r;
      }
    }
    this.angleMask = mask;
  }

  private ensureParamScale(): void {
    if (this.paramScale !== undefined || !this.paramOutline) {
      return;
    }
    let maxR: number = 0;
    let N: number = 1000;
    for (let i: number = 0; i <= N; i++) {
      let t: number = (i / N) * Math.PI * 2;
      let p: [number, number] = this.paramOutline(t);
      let r: number = Math.sqrt(p[0] * p[0] + p[1] * p[1]);
      if (r > maxR) {
        maxR = r;
      }
    }
    this.paramScale = maxR > 1e-6 ? (0.98 / maxR) : 1;
  }

  private normParam(p: [number, number]): [number, number] {
    let s: number = this.paramScale !== undefined ? this.paramScale : 1;
    return [p[0] * s, p[1] * s];
  }

  outlinePoints(n: number): Array<[number, number]> {
    if (this.paramOutline) {
      this.ensureParamScale();
      let pts: Array<[number, number]> = [];
      for (let i: number = 0; i <= n; i++) {
        let t: number = (i / n) * Math.PI * 2;
        let p: [number, number] = this.normParam(this.paramOutline(t));
        pts.push(p);
      }
      return pts;
    }
    let pts: Array<[number, number]> = [];
    for (let i: number = 0; i <= n; i++) {
      let theta: number = (i / n) * Math.PI * 2;
      let r: number = this.fn(theta);
      pts.push([r * Math.cos(theta), r * Math.sin(theta)]);
    }
    return pts;
  }

  containsPixel(px: number, py: number): boolean {
    if (!this.bitmap) {
      return true;
    }
    let s: number = this.bitmap.size;
    let ix: number = Math.floor(px);
    let iy: number = Math.floor(py);
    if (ix < 0 || iy < 0 || ix >= s || iy >= s) {
      return false;
    }
    return this.bitmap.data[iy * s + ix] === 1;
  }

  // Build a shape whose boundary is the rasterized text of one or more characters
  // (e.g. "生日快乐"). The string is rendered to an OffscreenCanvas, then
  // morphologically dilated so the whole string becomes one solid fillable block.
  // Used by the "custom text shape" feature.
  static async makeGlyph(text: string, font: string, canvasSize: number): Promise<ShapeDef> {
    let off: OffscreenCanvas = new OffscreenCanvas(canvasSize, canvasSize, LengthMetricsUnit.PX);
    let ctx: OffscreenCanvasRenderingContext2D = off.getContext('2d', new RenderingContextSettings(true)) as OffscreenCanvasRenderingContext2D;
    ctx.clearRect(0, 0, canvasSize, canvasSize);
    ctx.fillStyle = '#ffffff';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

    let maxW: number = canvasSize * 0.82;
    let fontSize: number = Math.floor(canvasSize * 0.8);
    ctx.font = fontSize.toString() + 'px ' + font;
    let measured: number = ctx.measureText(text).width;
    if (measured > maxW) {
      fontSize = Math.floor(fontSize * (maxW / measured));
    }
    ctx.font = fontSize.toString() + 'px ' + font;
    ctx.fillText(text, canvasSize / 2, canvasSize / 2);

    let img: ImageData = ctx.getImageData(0, 0, canvasSize, canvasSize);
    let src: Uint8ClampedArray = img.data;
    let data: Uint8Array = new Uint8Array(canvasSize * canvasSize);
    let p: number = 0;
    for (let i: number = 3; i < src.length; i += 4) {
      if (src[i] > 100) {
        data[p] = 1;
      }
      p++;
    }

    let radius: number = Math.max(2, Math.floor(fontSize * 0.06));
    let solid: Uint8Array = ShapeDef.dilate(data, canvasSize, radius);

    let inside: number = 0;
    for (let p: number = 0; p < solid.length; p++) {
      if (solid[p] === 1) {
        inside++;
      }
    }

    let shape: ShapeDef = new ShapeDef('glyph', text, () => 1, 0.3);
    shape.bitmap = { data: solid, size: canvasSize };
    shape.glyphChar = text;
    shape.glyphFont = font;
    shape.shapeRatio = Math.min(0.85, Math.max(0.25, inside / (canvasSize * canvasSize) * 1.4));
    return shape;
  }

  // Box dilation (max filter) on a binary mask. Turns thin glyph strokes into a
  // fat, connected region so the placer can fill the interior.
  private static dilate(src: Uint8Array, size: number, radius: number): Uint8Array {
    let dst: Uint8Array = new Uint8Array(size * size);
    for (let y: number = 0; y < size; y++) {
      for (let xx: number = 0; xx < size; xx++) {
        if (src[y * size + xx] !== 1) {
          continue;
        }
        let y0: number = Math.max(0, y - radius);
        let y1: number = Math.min(size - 1, y + radius);
        let x0: number = Math.max(0, xx - radius);
        let x1: number = Math.min(size - 1, xx + radius);
        for (let yy: number = y0; yy <= y1; yy++) {
          let row: number = yy * size;
          for (let xxx: number = x0; xxx <= x1; xxx++) {
            dst[row + xxx] = 1;
          }
        }
      }
    }
    return dst;
  }

  static readonly circleFn: (theta: number) => number = () => 1;
  static readonly cardioidFn: (theta: number) => number = (theta: number) => {
    let t: number = -theta;
    let sinT: number = Math.sin(t);
    let cosT: number = Math.cos(t);
    let r: number = (Math.sqrt(Math.abs(cosT)) * sinT) / (sinT + 1.4) - 2 * sinT + 2;
    return r / 2.2;
  };
  static readonly heartParam: (t: number) => [number, number] = (t: number) => {
    let sinT: number = Math.sin(t);
    let cosT: number = Math.cos(t);
    let x: number = 16 * sinT * sinT * sinT;
    let y: number = 13 * cosT - 5 * Math.cos(2 * t) - 2 * Math.cos(3 * t) - Math.cos(4 * t);
    return [x, y];
  };
  static readonly star5Fn: (theta: number) => number = (theta: number) => {
    let points: number = 5;
    let outerR: number = 1.0;
    let innerR: number = 0.382;
    let sector: number = Math.PI / points;
    let t: number = theta - Math.PI / 2;
    t = ((t % (2 * sector)) + (2 * sector)) % (2 * sector);
    if (t < sector) {
      let ratio: number = t / sector;
      return outerR + (innerR - outerR) * ratio;
    } else {
      let ratio: number = (t - sector) / sector;
      return innerR + (outerR - innerR) * ratio;
    }
  };
  static readonly diamondFn: (theta: number) => number = (theta: number) => {
    let t: number = ((theta % (Math.PI / 2)) + (Math.PI / 2)) % (Math.PI / 2);
    return 1 / (Math.cos(t) + Math.sin(t));
  };
  static readonly triangleFn: (theta: number) => number = (theta: number) => {
    let sector: number = (2 * Math.PI) / 3;
    let t: number = (((theta + Math.PI / 2) % sector) + sector) % sector;
    return 1 / (Math.cos(t) + Math.sqrt(3) * Math.sin(t));
  };
  static readonly triangleUpFn: (theta: number) => number = (theta: number) => {
    let sector: number = (2 * Math.PI) / 3;
    let t: number = (((theta - Math.PI / 2) % sector) + sector) % sector;
    return 1 / (Math.cos(t) + Math.sqrt(3) * Math.sin(t));
  };
  static readonly triangleLeftFn: (theta: number) => number = (theta: number) => {
    let sector: number = (2 * Math.PI) / 3;
    let t: number = (((theta - Math.PI) % sector) + sector) % sector;
    return 1 / (Math.cos(t) + Math.sqrt(3) * Math.sin(t));
  };
  static readonly triangleRightFn: (theta: number) => number = (theta: number) => {
    let sector: number = (2 * Math.PI) / 3;
    let t: number = ((theta % sector) + sector) % sector;
    return 1 / (Math.cos(t) + Math.sqrt(3) * Math.sin(t));
  };
  static readonly squareFn: (theta: number) => number = (theta: number) => {
    let absCos: number = Math.abs(Math.cos(theta));
    let absSin: number = Math.abs(Math.sin(theta));
    let maxVal: number = Math.max(absCos, absSin);
    if (maxVal < 1e-10) {
      return 1;
    }
    let SQRT1_2: number = 0.7071067811865476;
    return SQRT1_2 / maxVal;
  };
  static readonly pentagonFn: (theta: number) => number = (theta: number) => {
    let sides: number = 5;
    let sector: number = (2 * Math.PI) / sides;
    let t: number = (((theta + Math.PI / 2) % sector) + sector) % sector;
    return 1 / (Math.cos(t) + 0.7265 * Math.sin(t));
  };
  static readonly hexagonFn: (theta: number) => number = (theta: number) => {
    let sector: number = Math.PI / 3;
    let t: number = ((theta % sector) + sector) % sector;
    let phi: number = Math.abs(t - sector / 2);
    return Math.cos(Math.PI / 6) / Math.cos(phi);
  };
  static readonly crossFn: (theta: number) => number = (theta: number) => {
    let armWidth: number = 0.28;
    let absCos: number = Math.abs(Math.cos(theta));
    let absSin: number = Math.abs(Math.sin(theta));
    let rH: number = Infinity;
    let rV: number = Infinity;
    if (absSin > 1e-8) {
      rH = armWidth / absSin;
    }
    if (absCos > 1e-8) {
      rV = armWidth / absCos;
    }
    return Math.min(Math.max(rH, rV), 1.0);
  };
  static readonly cloudFn: (theta: number) => number = (theta: number) => {
    let bump: number = 0.16 * Math.cos(5 * theta) + 0.06 * Math.cos(3 * theta + 0.6);
    let r: number = 0.9 + bump;
    let s: number = Math.sin(theta);
    if (s < 0) {
      r = r * (1 + 0.12 * s);
    }
    return r / 1.05;
  };
  static readonly ovalFn: (theta: number) => number = (theta: number) => {
    let b: number = 0.7;
    let cosT: number = Math.cos(theta);
    let sinT: number = Math.sin(theta);
    return b / Math.sqrt(b * b * cosT * cosT + sinT * sinT);
  };
  static readonly leafFn: (theta: number) => number = (theta: number) => {
    let s: number = Math.abs(Math.sin(theta));
    return Math.pow(s, 0.55);
  };
  static readonly leafParam: (t: number) => [number, number] = (t: number) => {
    let x: number = 0.5 * Math.sin(t) * (1 + 0.25 * Math.cos(t)) + 0.05 * Math.sin(2 * t);
    let y: number = Math.cos(t);
    return [x, y];
  };
  static readonly star8Fn: (theta: number) => number = (theta: number) => {
    let points: number = 8;
    let outerR: number = 1.0;
    let innerR: number = 0.65;
    let sector: number = Math.PI / points;
    let t: number = theta - Math.PI / 2;
    t = ((t % (2 * sector)) + (2 * sector)) % (2 * sector);
    if (t < sector) {
      let ratio: number = t / sector;
      return outerR + (innerR - outerR) * ratio;
    } else {
      let ratio: number = (t - sector) / sector;
      return innerR + (outerR - innerR) * ratio;
    }
  };
  static readonly flowerFn: (theta: number) => number = (theta: number) => {
    let base: number = 0.6;
    let amplitude: number = 0.4;
    let petals: number = 5;
    return base + amplitude * Math.cos(petals * theta);
  };
  static readonly octagonFn: (theta: number) => number = (theta: number) => {
    let sector: number = Math.PI / 4;
    let t: number = (((theta + Math.PI / 2) % sector) + sector) % sector;
    return 1 / (Math.cos(t) + 0.4142 * Math.sin(t));
  };

  static readonly SHAPES: ShapeDef[] = [
    new ShapeDef('circle', '圆形', ShapeDef.circleFn, 1.0),
    new ShapeDef('cardioid', '心形', ShapeDef.cardioidFn, 0.5).setParam(ShapeDef.heartParam),
    new ShapeDef('star5', '五角星', ShapeDef.star5Fn, 0.4),
    new ShapeDef('diamond', '菱形', ShapeDef.diamondFn, 0.5),
    new ShapeDef('triangle', '倒三角', ShapeDef.triangleFn, 0.38),
    new ShapeDef('triangleUp', '正三角', ShapeDef.triangleUpFn, 0.38),
    new ShapeDef('triangleLeft', '左三角', ShapeDef.triangleLeftFn, 0.38),
    new ShapeDef('triangleRight', '右三角', ShapeDef.triangleRightFn, 0.38),
    new ShapeDef('square', '方形', ShapeDef.squareFn, 0.6),
    new ShapeDef('pentagon', '五边', ShapeDef.pentagonFn, 0.76),
    new ShapeDef('hexagon', '六边', ShapeDef.hexagonFn, 0.83),
    new ShapeDef('cross', '十字', ShapeDef.crossFn, 0.35),
    new ShapeDef('cloud', '云朵', ShapeDef.cloudFn, 0.58),
    new ShapeDef('oval', '椭圆', ShapeDef.ovalFn, 0.7),
    new ShapeDef('leaf', '叶片', ShapeDef.leafFn, 0.42).setParam(ShapeDef.leafParam),
    new ShapeDef('star8', '八角星', ShapeDef.star8Fn, 0.55),
    new ShapeDef('flower', '花朵', ShapeDef.flowerFn, 0.5),
    new ShapeDef('octagon', '八边形', ShapeDef.octagonFn, 0.9),
  ];

  setParam(p: (t: number) => [number, number]): ShapeDef {
    this.paramOutline = p;
    return this;
  }

  renderGlyphMask(ctx: OffscreenCanvasRenderingContext2D, pixelSize: number): void {
    let bm: GlyphMask | undefined = this.bitmap;
    if (!bm) {
      ctx.clearRect(0, 0, pixelSize, pixelSize);
      ctx.fillStyle = '#ffffff';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      let fs: number = Math.floor(pixelSize * 0.8);
      ctx.font = fs.toString() + 'px ' + (this.glyphFont !== undefined ? this.glyphFont : 'sans-serif');
      ctx.fillText(this.glyphChar !== undefined ? this.glyphChar : '', pixelSize / 2, pixelSize / 2);
      return;
    }
    let src: number = bm.size;
    let scale: number = pixelSize / src;
    let img: ImageData = ctx.createImageData(pixelSize, pixelSize);
    let d: Uint8ClampedArray = img.data;
    for (let y: number = 0; y < pixelSize; y++) {
      let sy: number = Math.min(src - 1, Math.floor(y / scale));
      for (let xx: number = 0; xx < pixelSize; xx++) {
        let sx: number = Math.min(src - 1, Math.floor(xx / scale));
        let on: boolean = bm.data[sy * src + sx] === 1;
        let o: number = (y * pixelSize + xx) * 4;
        d[o] = 255;
        d[o + 1] = 255;
        d[o + 2] = 255;
        d[o + 3] = on ? 255 : 0;
      }
    }
    ctx.clearRect(0, 0, pixelSize, pixelSize);
    ctx.putImageData(img, 0, 0);
  }

  static getShapeById(id: string): ShapeDef {
    for (let i = 0; i < ShapeDef.SHAPES.length; i++) {
      if (ShapeDef.SHAPES[i].id === id) {
        return ShapeDef.SHAPES[i];
      }
    }
    return ShapeDef.SHAPES[0];
  }
}
