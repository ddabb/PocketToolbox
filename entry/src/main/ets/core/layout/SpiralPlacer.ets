import { Rect, SpatialHash } from './SpatialHash';
import { PlacedWord } from '../../model/WordItem';

/**
 * 词云布局输入
 * text  - 词语文本
 * size  - 渲染字号（逻辑像素）
 * weight - 原始权重（词频）
 * font  - 字体名
 */
export class PlaceInput {
  text: string = '';
  size: number = 0;
  weight: number = 0;
  font: string = '';
}

/**
 * 阿基米德螺旋 + 空间哈希碰撞检测 + 多方向回退 布局器。
 *
 * 相比朴素的线性扫描，本实现使用以下优化策略以提升词云的填充率与观感：
 *  1. 按词频降序放置，使关键词占据视觉中心；
 *  2. 使用更紧凑的螺旋参数（更小的螺距与角步长），避免词语稀疏；
 *  3. 对中英文分别估算文本宽度，显著降低“错位/留白过大/重叠”；
 *  4. 支持 0°/±45°/90° 多方向回退，使整体布局更灵动；
 *  5. 对头部高频词叠加额外旋转角（±45°）以增强视觉层次。
 */
export class SpiralPlacer {
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;
  private spatialHash: SpatialHash = new SpatialHash(100);
  /** 画布半径（短边一半） */
  private canvasRadius: number = 0;

  /** 螺旋起始半径（逻辑像素）：较小值使首个词更贴近中心 */
  private readonly SPIRAL_A: number = 2;
  /**
   * 螺距：构造时根据画布尺寸自适应计算。
   *  目标：让螺旋在 MAX_TURNS 圈内恰好覆盖画布半径的 ~110%（留有余地），
   *  这样既能保证外侧词也能被螺旋触达，又不会造成外圈过密。
   */
  private spiralB: number = 40;
  /** 螺旋角步长（弧度）：越小采样越密，填充越饱满 */
  private readonly DELTA_THETA: number = 0.05;
  /** 最大螺旋尝试圈数（4 圈），避免无效计算 */
  private readonly MAX_TURNS: number = 4;
  /** 螺旋路径上最大失败次数：超过则放弃该词，交给回退策略 */
  private readonly MAX_SPIRAL_FAIL: number = 150;
  /**
   * 词语间留白（逻辑像素）。
   *  注意：这里不使用固定像素，而是结合画布尺寸与字号进行自适应 padding。
   */
  private readonly WORD_PADDING_RATIO: number = 0.15;
  private readonly WORD_PADDING_MIN: number = 2;

  constructor(width: number, height: number) {
    this.canvasWidth = width;
    this.canvasHeight = height;
    // 画布半径取短边一半，确保词云不出界
    this.canvasRadius = Math.min(width, height) / 2;
    // 自适应螺距：每圈半径增长 = 画布半径 / 圈数，覆盖至画布边缘
    this.spiralB = Math.max(
      16,
      (this.canvasRadius - this.SPIRAL_A) / this.MAX_TURNS
    );
    // 根据画布尺寸自适应空间哈希格子大小，以减少碰撞查询次数
    let cellSize: number = Math.max(48, Math.min(128, Math.min(width, height) / 6));
    this.spatialHash = new SpatialHash(cellSize);
  }

  /**
   * 按权重降序依次放置词语，返回已成功放置的词语列表。
   */
  place(inputWords: PlaceInput[]): PlacedWord[] {
    this.spatialHash.clear();

    let sorted: PlaceInput[] = inputWords.slice();
    // 按权重（词频）降序：大词先放中央，小词填充周边
    sorted.sort((a: PlaceInput, b: PlaceInput) => b.weight - a.weight);

    let cx: number = this.canvasWidth / 2;
    let cy: number = this.canvasHeight / 2;
    let results: PlacedWord[] = [];
    let total: number = sorted.length;

    // 头部高频词叠加随机倾斜角，增加视觉层次
    let headCount: number = Math.max(1, Math.floor(total * 0.2));

    for (let i = 0; i < sorted.length; i++) {
      let word: PlaceInput = sorted[i];
      let textW: number = this.estimateTextWidth(word.text, word.size);
      let textH: number = this.estimateTextHeight(word.size);

      // 头部 20% 的词尝试 0° 与 ±45°，增强视觉层次；其余仅尝试 0° 与 90°
      let isHead: boolean = i < headCount;
      let angles: number[] = isHead
        ? [0, 90, 45, -45]
        : [0, 90];

      let placed: PlacedWord | null = null;
      for (let ai = 0; ai < angles.length && placed === null; ai++) {
        let angle: number = angles[ai];
        // 45° 等倾斜方向采用较大的外接框估算（1.41x）以避免斜排时重叠
        let w: number = textW;
        let h: number = textH;
        if (angle === 45 || angle === -45) {
          let diag: number = (textW + textH) * 0.7071; // 1/sqrt(2)
          w = diag;
          h = diag;
        } else if (angle === 90) {
          w = textH;
          h = textW;
        }
        placed = this.tryPlaceWord(word, cx, cy, w, h, angle);
      }

      // 螺旋失败则退化为蒙特卡洛随机撒点
      if (placed === null) {
        placed = this.tryMonteCarlo(word, textW, textH);
      }

      if (placed !== null) {
        results.push(placed);
      }
      // 放置失败的词语直接丢弃（不返回给上层）
    }
    return results;
  }

  /**
   * 阿基米德螺旋线放置：从中心向外沿螺旋线寻找第一个不发生碰撞的位置。
   * 螺旋参数：r = A + B * theta
   */
  private tryPlaceWord(word: PlaceInput, cx: number, cy: number,
    w: number, h: number, angle: number): PlacedWord | null {
    let startTheta: number = Math.random() * Math.PI * 2;
    let theta: number = startTheta;
    let failCount: number = 0;
    // 字号越大，padding 越大，保证可读性与呼吸感
    let pad: number = Math.max(this.WORD_PADDING_MIN,
      Math.min(w, h) * this.WORD_PADDING_RATIO);
    let paddedW: number = w + pad * 2;
    let paddedH: number = h + pad * 2;
    let maxTheta: number = startTheta + this.MAX_TURNS * Math.PI * 2;

    while (theta < maxTheta) {
      // 螺旋半径：随圈数线性增长，使 4 圈时恰好覆盖画布半径
      let turns: number = (theta - startTheta) / (Math.PI * 2);
      let r: number = this.SPIRAL_A + this.spiralB * turns;
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

  /**
   * 蒙特卡洛回退：在画布范围内随机采样寻找可行位置。
   * 当螺旋尝试失败或词语过长时使用。
   */
  private tryMonteCarlo(word: PlaceInput, w: number, h: number): PlacedWord | null {
    // 基于画布尺寸与词语大小动态调整尝试次数，兼顾密度与耗时
    let area: number = this.canvasWidth * this.canvasHeight;
    let wordArea: number = w * h;
    let attempts: number = Math.min(300, Math.max(60, Math.floor(area / Math.max(1, wordArea * 4))));

    let pad: number = Math.max(this.WORD_PADDING_MIN,
      Math.min(w, h) * this.WORD_PADDING_RATIO);
    let paddedW: number = w + pad * 2;
    let paddedH: number = h + pad * 2;

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

  /** 判断矩形是否完全位于画布内 */
  private isInsideCanvas(rect: Rect): boolean {
    return rect.left >= 0 && rect.top >= 0 &&
      rect.right <= this.canvasWidth && rect.bottom <= this.canvasHeight;
  }

  /**
   * 文本宽度估算：区分中文（方块字）与英文/数字。
   * 中文宽度约等于字号，英文/数字约为字号的 0.55~0.6 倍。
   * 相比统一 0.7 的粗略估算，该方法显著降低混排场景下的碰撞与空白。
   */
  private estimateTextWidth(text: string, fontSize: number): number {
    if (!text || text.length === 0) {
      return fontSize;
    }
    let width: number = 0;
    for (let i = 0; i < text.length; i++) {
      let ch: string = text.charAt(i);
      // CJK 统一汉字区及扩展区（粗略判断为汉字/日文方块字）
      let code: number = ch.charCodeAt(0);
      if ((code >= 0x4e00 && code <= 0x9fff) ||
        (code >= 0x3400 && code <= 0x4dbf) ||
        (code >= 0x3040 && code <= 0x30ff) ||
        (code >= 0xac00 && code <= 0xd7af)) {
        width += fontSize * 1.0;
      } else if (ch === ' ' || ch === '-') {
        width += fontSize * 0.3;
      } else {
        width += fontSize * 0.58;
      }
    }
    return width;
  }

  /** 文本高度估算：行高通常为字号的 1.15~1.25 倍 */
  private estimateTextHeight(fontSize: number): number {
    return fontSize * 1.2;
  }
}
