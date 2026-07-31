export class FontScaler {
  private static readonly POWER: number = 0.75;

  static getMinFont(canvasSize: number): number {
    return Math.max(10, canvasSize * 0.035);
  }

  static getMaxFont(canvasSize: number): number {
    let minFont: number = FontScaler.getMinFont(canvasSize);
    return Math.max(minFont + 10, canvasSize * 0.16);
  }

  static scale(weight: number, minWeight: number, maxWeight: number, canvasSize: number): number {
    let minFont: number = FontScaler.getMinFont(canvasSize);
    let maxFont: number = FontScaler.getMaxFont(canvasSize);
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

  static scaleAll(items: WeightedItem[], canvasSize: number): void {
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
    for (let i: number = 0; i < items.length; i++) {
      items[i].fontSize = FontScaler.scale(items[i].weight, minW, maxW, canvasSize);
    }
  }
}

export class WeightedItem {
  text: string = '';
  weight: number = 1;
  fontSize: number = 14;
  tag: string = '';
}
