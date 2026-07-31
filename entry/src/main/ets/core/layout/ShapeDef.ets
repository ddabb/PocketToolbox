export class ShapeDef {
  id: string = '';
  name: string = '';
  fn: (theta: number) => number = (_theta: number): number => { return 1; };

  constructor(id: string, name: string, fn: (theta: number) => number) {
    this.id = id;
    this.name = name;
    this.fn = fn;
  }

  static getAll(): ShapeDef[] {
    return ShapeDef.SHAPES.slice();
  }

  static getById(id: string): ShapeDef {
    for (let i: number = 0; i < ShapeDef.SHAPES.length; i++) {
      if (ShapeDef.SHAPES[i].id === id) {
        return ShapeDef.SHAPES[i];
      }
    }
    return ShapeDef.SHAPES[0];
  }

  static getByIndex(index: number): ShapeDef {
    if (index >= 0 && index < ShapeDef.SHAPES.length) {
      return ShapeDef.SHAPES[index];
    }
    return ShapeDef.SHAPES[0];
  }

  static readonly SHAPES: ShapeDef[] = [
    new ShapeDef('circle', '圆形', ShapeDef.circleFn),
    new ShapeDef('cardioid', '心形', ShapeDef.cardioidFn),
    new ShapeDef('star5', '星形', ShapeDef.star5Fn),
    new ShapeDef('diamond', '菱形', ShapeDef.diamondFn),
    new ShapeDef('triangle', '三角', ShapeDef.triangleFn),
    new ShapeDef('square', '方形', ShapeDef.squareFn),
    new ShapeDef('pentagon', '五边', ShapeDef.pentagonFn),
    new ShapeDef('hexagon', '六边', ShapeDef.hexagonFn),
    new ShapeDef('cross', '十字', ShapeDef.crossFn),
    new ShapeDef('cloud', '云朵', ShapeDef.cloudFn),
  ];

  private static circleFn(_theta: number): number {
    return 1;
  }

  private static cardioidFn(theta: number): number {
    return 1 - Math.sin(theta);
  }

  private static star5Fn(theta: number): number {
    let t: number = ((theta % (2 * Math.PI / 5)) + (2 * Math.PI / 5)) % (2 * Math.PI / 5);
    let halfAngle: number = Math.PI / 5;
    if (t < halfAngle) {
      let ratio: number = t / halfAngle;
      let innerR: number = 0.38;
      return innerR + (1 - innerR) * ratio;
    } else {
      let ratio: number = (t - halfAngle) / halfAngle;
      let innerR: number = 0.38;
      return 1 - (1 - innerR) * ratio;
    }
  }

  private static diamondFn(theta: number): number {
    let t: number = ((theta % (Math.PI / 2)) + (Math.PI / 2)) % (Math.PI / 2);
    return 1 / (Math.cos(t) + Math.sin(t));
  }

  private static triangleFn(theta: number): number {
    let sector: number = (2 * Math.PI) / 3;
    let t: number = ((theta % sector) + sector) % sector;
    return 1 / (Math.cos(t) + Math.sqrt(3) * Math.sin(t));
  }

  private static squareFn(theta: number): number {
    let absCos: number = Math.abs(Math.cos(theta));
    let absSin: number = Math.abs(Math.sin(theta));
    let maxVal: number = Math.max(absCos, absSin);
    if (maxVal < 1e-10) {
      return 1;
    }
    return 1 / maxVal;
  }

  private static pentagonFn(theta: number): number {
    let sector: number = (2 * Math.PI) / 5;
    let t: number = ((theta % sector) + sector) % sector;
    return 1 / (Math.cos(t) + 0.7265 * Math.sin(t));
  }

  private static hexagonFn(theta: number): number {
    let sector: number = Math.PI / 3;
    let t: number = ((theta % sector) + sector) % sector;
    return 1 / (Math.cos(t) + Math.sqrt(3) * Math.sin(t));
  }

  private static crossFn(theta: number): number {
    let absCos: number = Math.abs(Math.cos(theta));
    let absSin: number = Math.abs(Math.sin(theta));
    let armWidth: number = 0.35;
    let halfPi: number = Math.PI / 2;
    let t: number = ((theta % halfPi) + halfPi) % halfPi;
    let cosT: number = Math.cos(t);
    let sinT: number = Math.sin(t);
    let crossR: number = cosT + sinT;
    if (crossR < 1e-10) {
      return 1;
    }
    let shapeR: number = 1 / crossR;
    let armThreshold: number = armWidth * shapeR;
    if (absCos > armThreshold && absSin > armThreshold) {
      let cornerCos: number = absCos - armThreshold;
      let cornerSin: number = absSin - armThreshold;
      let cornerR: number = Math.sqrt(cornerCos * cornerCos + cornerSin * cornerSin);
      let maxCorner: number = shapeR * (1 - armWidth) * Math.sqrt(2);
      if (cornerR > maxCorner) {
        return armThreshold / Math.max(absCos, absSin);
      }
    }
    return shapeR;
  }

  private static cloudFn(theta: number): number {
    return 0.5 + 0.15 * Math.sin(3 * theta) + 0.1 * Math.cos(5 * theta) +
      0.08 * Math.sin(7 * theta) + 0.05 * Math.cos(11 * theta);
  }
}
