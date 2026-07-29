import { PlacedWord } from '../model/WordItem';
import { Palette, PaletteColor } from '../core/style/Palette';

@Component
export struct WordCloudView {
  @Prop placedWords: PlacedWord[] = [];
  @Prop bgColor: string = '#ffffff';
  @Prop paletteColors: string[] = [];
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private colorIndex: number = 0;

  build() {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      .onReady(() => {
        this.drawWordCloud();
      })
  }

  private drawWordCloud(): void {
    if (this.placedWords.length === 0) {
      return;
    }
    let ctx: CanvasRenderingContext2D = this.context;
    let w: number = ctx.width;
    let h: number = ctx.height;
    if (w <= 0 || h <= 0) {
      return;
    }

    ctx.clearRect(0, 0, w, h);
    ctx.fillStyle = this.bgColor;
    ctx.fillRect(0, 0, w, h);

    let colors: string[] = this.paletteColors.length > 0 ? this.paletteColors : ['#333333'];
    this.colorIndex = 0;

    for (let i = 0; i < this.placedWords.length; i++) {
      let pw: PlacedWord = this.placedWords[i];
      let color: string = pw.color && pw.color.length > 0 ? pw.color : this.nextColor(colors);
      ctx.save();
      ctx.translate(pw.x, pw.y);
      if (pw.angle === 90) {
        ctx.rotate(Math.PI / 2);
      }
      ctx.font = pw.size.toString() + 'px ' + (pw.font && pw.font.length > 0 ? pw.font : 'sans-serif');
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
