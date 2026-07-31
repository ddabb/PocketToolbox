/**
 * 字号缩放器：根据词语权重（词频）映射到视觉字号。
 *
 * 优化策略：
 *  1. 使用对数压缩权重范围，避免少数极高频词占据过大视觉空间；
 *  2. 使用幂次（power=0.75）进一步压缩头部词与尾部词的字号差距，
 *     使画布容纳更多词语并保持可读性；
 *  3. 将最大字号限制为 60（逻辑像素），避免在 360px 画布上“头词”过大，
 *     同时最小字号提到 14，保证尾词仍清晰可辨。
 */
export class FontScaler {
  /** 最小字号（逻辑像素）：保证尾词可读性 */
  static readonly MIN_FONT: number = 14;
  /** 最大字号（逻辑像素）：避免头词挤占过多空间 */
  static readonly MAX_FONT: number = 60;
  /** 分布压缩指数：<1 压缩头部，>1 拉开头部 */
  private static readonly POWER: number = 0.75;

  /**
   * 将单个词的权重映射为字号。
   */
  static scale(weight: number, minWeight: number, maxWeight: number): number {
    if (maxWeight <= minWeight) {
      return FontScaler.MIN_FONT + (FontScaler.MAX_FONT - FontScaler.MIN_FONT) * 0.5;
    }
    let logW: number = Math.log(weight > 0 ? weight : 1);
    let logMin: number = Math.log(minWeight > 0 ? minWeight : 1);
    let logMax: number = Math.log(maxWeight > 0 ? maxWeight : 1);
    if (logMax <= logMin) {
      return FontScaler.MIN_FONT;
    }
    // 对数归一化到 [0, 1]
    let ratio: number = (logW - logMin) / (logMax - logMin);
    // 幂次压缩：减弱头部词的视觉垄断
    let shaped: number = Math.pow(ratio, FontScaler.POWER);
    return FontScaler.MIN_FONT + (FontScaler.MAX_FONT - FontScaler.MIN_FONT) * shaped;
  }

  /**
   * 批量缩放：扫描 min/max 后为每个 item 分配字号。
   */
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
