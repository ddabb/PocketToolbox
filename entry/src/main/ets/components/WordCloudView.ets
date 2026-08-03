import { image } from '@kit.ImageKit';
import { LengthMetricsUnit } from '@kit.ArkUI';
import { PlacedWord } from '../model/WordItem';

@Component
export struct WordCloudView {
  @Prop @Watch('onDataChange') placedWords: PlacedWord[] = [];
  @Prop @Watch('onDataChange') bgColor: string = '#ffffff';
  @Prop @Watch('onDataChange') paletteColors: string[] = [];
  @Prop canvasPixelSize: number = 720;
  @Prop canvasSize: number = 360;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;
  private pendingDraw: boolean = false;

  build() {
    Canvas(this.context)
      .width(this.canvasPixelSize + 'px')
      .height(this.canvasPixelSize + 'px')
      .onReady(() => {
        this.ready = true;
        if (this.placedWords.length > 0 || this.pendingDraw) {
          this.pendingDraw = false;
          this.drawWordCloud();
        }
      })
  }

  private onDataChange(): void {
    if (this.ready) {
      this.drawWordCloud();
    } else {
      this.pendingDraw = true;
    }
  }

  // P1优化: 提取公共绘制逻辑, 消除 drawWordCloud 与 renderToPixelMap 之间的重复代码
  // color/font 由 generateWordCloud/refreshColors/refreshFont 保证有效, 移除冗余空检查和参数
  private drawWords(ctx: CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D,
    scale: number, bgColor: string, width: number, height: number): void {
    ctx.clearRect(0, 0, width, height);
    ctx.fillStyle = bgColor;
    ctx.fillRect(0, 0, width, height);

    let words: PlacedWord[] = this.placedWords;
    let count: number = words.length;
    for (let i: number = 0; i < count; i++) {
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
  }

  private drawWordCloud(): void {
    if (this.placedWords.length === 0) {
      return;
    }
    let w: number = this.canvasPixelSize;
    if (w <= 0) {
      return;
    }
    this.drawWords(this.context,
      this.canvasPixelSize / this.canvasSize,
      this.bgColor, w, w);
  }

  renderToPixelMap(pixelSize: number): image.PixelMap {
    let off: OffscreenCanvas = new OffscreenCanvas(pixelSize, pixelSize, LengthMetricsUnit.PX);
    let ctx: OffscreenCanvasRenderingContext2D = off.getContext('2d', new RenderingContextSettings(true)) as OffscreenCanvasRenderingContext2D;

    this.drawWords(ctx,
      pixelSize / this.canvasSize,
      this.bgColor, pixelSize, pixelSize);

    return ctx.getPixelMap(0, 0, pixelSize, pixelSize);
  }

}
