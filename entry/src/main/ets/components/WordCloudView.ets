import { PlacedWord } from '../model/WordItem';

@Component
export struct WordCloudView {
  @Prop @Watch('onDataChange') placedWords: PlacedWord[] = [];
  @Prop @Watch('onDataChange') bgColor: string = '#ffffff';
  @Prop @Watch('onDataChange') paletteColors: string[] = [];
  @Prop canvasPixelSize: number = 720;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private colorIndex: number = 0;
  private ready: boolean = false;

  build() {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      .onReady(() => {
        this.ready = true;
        this.drawWordCloud();
      })
  }

  private onDataChange(): void {
    if (this.ready) {
      this.drawWordCloud();
    }
  }

  private drawWordCloud(): void {
    if (this.placedWords.length === 0) {
      return;
    }
    let ctx: CanvasRenderingContext2D = this.context;
    let w: number = this.canvasPixelSize;
    let h: number = this.canvasPixelSize;
    if (w <= 0 || h <= 0) {
      return;
    }

    ctx.clearRect(0, 0, w, h);
    ctx.fillStyle = this.bgColor;
    ctx.fillRect(0, 0, w, h);

    let scale: number = w / 360;
    let colors: string[] = this.paletteColors.length > 0 ? this.paletteColors : ['#333333'];
    this.colorIndex = 0;

    for (let i = 0; i < this.placedWords.length; i++) {
      let pw: PlacedWord = this.placedWords[i];
      let color: string = pw.color && pw.color.length > 0 ? pw.color : this.nextColor(colors);
      let drawSize: number = pw.size * scale;
      let drawX: number = pw.x * scale;
      let drawY: number = pw.y * scale;
      ctx.save();
      ctx.translate(drawX, drawY);
      // 支持任意角度（0 / ±45 / 90 等）的旋转绘制，单位为度
      if (pw.angle !== 0) {
        ctx.rotate(pw.angle * Math.PI / 180);
      }
      ctx.font = drawSize.toString() + 'px ' + (pw.font && pw.font.length > 0 ? pw.font : 'sans-serif');
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillStyle = color;
      ctx.fillText(pw.text, 0, 0);
      ctx.restore();
    }
  }

  private nextColor(colors: string[]): string {
    if (colors.length === 0) {
      return '#333333';
    }
    let c: string = colors[this.colorIndex % colors.length];
    this.colorIndex++;
    return c;
  }
}
