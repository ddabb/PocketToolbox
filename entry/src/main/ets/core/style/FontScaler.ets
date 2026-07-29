export class FontScaler {
  static readonly MIN_FONT: number = 14;
  static readonly MAX_FONT: number = 96;

  static scale(weight: number, minWeight: number, maxWeight: number): number {
    if (maxWeight <= minWeight) {
      return FontScaler.MIN_FONT;
    }
    let logW: number = Math.log(weight > 0 ? weight : 1);
    let logMin: number = Math.log(minWeight > 0 ? minWeight : 1);
    let logMax: number = Math.log(maxWeight > 0 ? maxWeight : 1);
    if (logMax <= logMin) {
      return FontScaler.MIN_FONT;
    }
    let ratio: number = (logW - logMin) / (logMax - logMin);
    return FontScaler.MIN_FONT + (FontScaler.MAX_FONT - FontScaler.MIN_FONT) * ratio;
  }

  static scaleAll(items: WeightedItem[]): void {
    if (items.length === 0) {
      return;
    }
    let minW: number = items[0].weight;
    let maxW: number = items[0].weight;
    for (let i = 1; i < items.length; i++) {
      if (items[i].weight < minW) {
        minW = items[i].weight;
      }
      if (items[i].weight > maxW) {
        maxW = items[i].weight;
      }
    }
    for (let i = 0; i < items.length; i++) {
      items[i].fontSize = FontScaler.scale(items[i].weight, minW, maxW);
    }
  }
}

export class WeightedItem {
  text: string = '';
  weight: number = 1;
  fontSize: number = 14;
  tag: string = '';
}
