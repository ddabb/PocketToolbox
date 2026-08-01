export class FontScaler {
  private static readonly POWER: number = 0.75;

  static getMinFont(canvasSize: number, shapeRatio: number, wordCount: number): number {
    let base: number = canvasSize * 0.035;
    let shapeAdj: number = Math.max(0.7, shapeRatio);
    let countAdj: number = Math.max(0.6, 1.0 - wordCount * 0.003);
    return Math.max(8, Math.floor(base * shapeAdj * countAdj));
  }

  static getMaxFont(canvasSize: number, shapeRatio: number, wordCount: number): number {
    let base: number = canvasSize * 0.16;
    let shapeAdj: number = Math.min(1.2, 0.5 + shapeRatio * 0.7);
    let countAdj: number = Math.max(0.5, 1.0 - wordCount * 0.005);
    let minFont: number = FontScaler.getMinFont(canvasSize, shapeRatio, wordCount);
    return Math.max(minFont + 10, Math.floor(base * shapeAdj * countAdj));
  }

  static scale(weight: number, minWeight: number, maxWeight: number, canvasSize: number,
    shapeRatio: number, wordCount: number): number {
    let minFont: number = FontScaler.getMinFont(canvasSize, shapeRatio, wordCount);
    let maxFont: number = FontScaler.getMaxFont(canvasSize, shapeRatio, wordCount);
    if (maxWeight <= minWeight) {
      return minFont + (maxFont - minFont) * 0.5;
    }
    let logW: number = Math.log(weight > 0 ? weight : 1);
    let logMin: number = Math.log(minWeight > 0 ? minWeight : 1);
    let logMax: number = Math.log(maxWeight > 0 ? maxWeight : 1);
    if (logMax <= logMin) {
      return minFont;
    }
    let ratio: number = (logW - logMin) / (logMax - logMin);
    let shaped: number = Math.pow(ratio, FontScaler.POWER);
    return minFont + (maxFont - minFont) * shaped;
  }

  static scaleAll(items: WeightedItem[], canvasSize: number, shapeRatio: number): void {
    if (items.length === 0) {
      return;
    }
    let minW: number = items[0].weight;
    let maxW: number = items[0].weight;
    for (let i: number = 1; i < items.length; i++) {
      if (items[i].weight < minW) {
        minW = items[i].weight;
      }
      if (items[i].weight > maxW) {
        maxW = items[i].weight;
      }
    }
    let wordCount: number = items.length;
    for (let i: number = 0; i < items.length; i++) {
      items[i].fontSize = FontScaler.scale(items[i].weight, minW, maxW, canvasSize, shapeRatio, wordCount);
    }
  }
}

export class WeightedItem {
  text: string = '';
  weight: number = 1;
  fontSize: number = 14;
  tag: string = '';
}
