import { image } from '@kit.ImageKit';
import { LengthMetricsUnit } from '@kit.ArkUI';
import { PlacedWord } from '../model/WordItem';

/**
 * WordCloudView — 词云预览组件
 * 使用 OffscreenCanvas 渲染后以 Image 展示，与导出逻辑完全一致，
 * 避免 Canvas 组件像素尺寸在不同设备上的缩放异常问题。
 */
@Component
export struct WordCloudView {
  @Prop @Watch('onDataChange') placedWords: PlacedWord[] = [];
  @Prop @Watch('onDataChange') bgColor: string = '#ffffff';
  @Prop layoutSize: number = 800;
  @State private displayPixel: image.PixelMap | undefined = undefined;
  private readonly DISPLAY_SCALE: number = 2;

  build() {
    Image(this.displayPixel)
      .width('100%')
      .height('100%')
      .objectFit(ImageFit.Contain)
      .interpolation(ImageInterpolation.Medium)
  }

  aboutToAppear(): void {
    if (this.placedWords.length > 0) {
      this.renderDisplay();
    }
  }

  aboutToDisappear(): void {
    if (this.displayPixel !== undefined) {
      this.displayPixel.release();
      this.displayPixel = undefined;
    }
  }

  private onDataChange(): void {
    this.renderDisplay();
  }

  private renderDisplay(): void {
    let words: PlacedWord[] = this.placedWords;
    if (words.length === 0) {
      return;
    }
    let pixelSize: number = this.layoutSize * this.DISPLAY_SCALE;
    let off: OffscreenCanvas = new OffscreenCanvas(pixelSize, pixelSize, LengthMetricsUnit.PX);
    let ctx: OffscreenCanvasRenderingContext2D = off.getContext('2d',
      new RenderingContextSettings(true)) as OffscreenCanvasRenderingContext2D;

    ctx.clearRect(0, 0, pixelSize, pixelSize);
    ctx.fillStyle = this.bgColor;
    ctx.fillRect(0, 0, pixelSize, pixelSize);

    let scale: number = pixelSize / this.layoutSize;
    for (let i: number = 0; i < words.length; i++) {
      let pw: PlacedWord = words[i];
      ctx.save();
      ctx.translate(pw.x * scale, pw.y * scale);
      if (pw.angle !== 0) {
        ctx.rotate(pw.angle * Math.PI / 180);
      }
      ctx.font = (pw.size * scale).toString() + 'px ' + pw.font;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillStyle = pw.color;
      ctx.fillText(pw.text, 0, 0);
      ctx.restore();
    }

    let old: image.PixelMap | undefined = this.displayPixel;
    this.displayPixel = ctx.getPixelMap(0, 0, pixelSize, pixelSize);
    if (old !== undefined) {
      old.release();
    }
  }

  renderToPixelMap(pixelSize: number): image.PixelMap {
    let off: OffscreenCanvas = new OffscreenCanvas(pixelSize, pixelSize, LengthMetricsUnit.PX);
    let ctx: OffscreenCanvasRenderingContext2D = off.getContext('2d',
      new RenderingContextSettings(true)) as OffscreenCanvasRenderingContext2D;

    ctx.clearRect(0, 0, pixelSize, pixelSize);
    ctx.fillStyle = this.bgColor;
    ctx.fillRect(0, 0, pixelSize, pixelSize);

    let scale: number = pixelSize / this.layoutSize;
    let words: PlacedWord[] = this.placedWords;
    for (let i: number = 0; i < words.length; i++) {
      let pw: PlacedWord = words[i];
      ctx.save();
      ctx.translate(pw.x * scale, pw.y * scale);
      if (pw.angle !== 0) {
        ctx.rotate(pw.angle * Math.PI / 180);
      }
      ctx.font = (pw.size * scale).toString() + 'px ' + pw.font;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillStyle = pw.color;
      ctx.fillText(pw.text, 0, 0);
      ctx.restore();
    }

    return ctx.getPixelMap(0, 0, pixelSize, pixelSize);
  }
}
