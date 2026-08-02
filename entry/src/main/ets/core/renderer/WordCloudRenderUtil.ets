import { LengthMetricsUnit } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { PlacedWord } from '../../model/WordItem';
import { ShapeDef, GlyphMask } from '../layout/ShapeDef';

// Renders a word cloud (optionally clipped to a shape) onto an OffscreenCanvas and
// returns a PixelMap suitable for display via an <Image> component or export via
// ImagePacker. This off-screen approach is required because the on-screen Canvas
// cannot do per-pixel compositing, which glyph (bitmap) shapes need.
export class WordCloudRenderUtil {
  static async renderToPixelMap(placedWords: PlacedWord[], canvasSize: number,
    outerBg: string, paletteColors: string[], shape: ShapeDef,
    shapeInnerBg: string): Promise<image.PixelMap> {
    let off: OffscreenCanvas = new OffscreenCanvas(canvasSize, canvasSize, LengthMetricsUnit.PX);
    let ctx: OffscreenCanvasRenderingContext2D = off.getContext('2d', new RenderingContextSettings(true)) as OffscreenCanvasRenderingContext2D;

    // outer background
    ctx.clearRect(0, 0, canvasSize, canvasSize);
    if (outerBg && outerBg !== 'transparent') {
      ctx.fillStyle = outerBg;
      ctx.fillRect(0, 0, canvasSize, canvasSize);
    }

    // shape interior background (for polar/param shapes we clip; for glyph we
    // composite per-pixel after drawing text)
    if (shape.bitmap) {
      // draw text first, then mask against glyph alpha
      WordCloudRenderUtil.drawWords(ctx, placedWords, canvasSize, paletteColors, 1, false);
      let masked: ImageData = WordCloudRenderUtil.applyGlyphMask(ctx, canvasSize, shape, outerBg, shapeInnerBg);
      ctx.putImageData(masked, 0, 0);
    } else {
      ctx.save();
      if (shape.paramOutline) {
        WordCloudRenderUtil.clipParamOutline(ctx, shape, canvasSize);
      } else {
        WordCloudRenderUtil.clipPolarOutline(ctx, shape, canvasSize);
      }
      if (shapeInnerBg && shapeInnerBg !== 'transparent') {
        ctx.fillStyle = shapeInnerBg;
        ctx.fillRect(0, 0, canvasSize, canvasSize);
      }
      WordCloudRenderUtil.drawWords(ctx, placedWords, canvasSize, paletteColors, 1, true);
      ctx.restore();
    }

    return ctx.getPixelMap(0, 0, canvasSize, canvasSize);
  }

  private static drawWords(ctx: OffscreenCanvasRenderingContext2D, placedWords: PlacedWord[],
    canvasSize: number, paletteColors: string[], scale: number, _clipped: boolean): void {
    let colors: string[] = paletteColors.length > 0 ? paletteColors : ['#333333'];
    for (let i: number = 0; i < placedWords.length; i++) {
      let pw: PlacedWord = placedWords[i];
      let color: string = pw.color && pw.color.length > 0 ? pw.color : colors[i % colors.length];
      let drawSize: number = pw.size * scale;
      let drawX: number = pw.x * scale;
      let drawY: number = pw.y * scale;
      ctx.save();
      ctx.translate(drawX, drawY);
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

  private static clipPolarOutline(ctx: OffscreenCanvasRenderingContext2D, shape: ShapeDef, size: number): void {
    let cx: number = size / 2;
    let cy: number = size / 2;
    let maxR: number = cx * 0.98;
    let pts: Array<[number, number]> = shape.outlinePoints(240);
    ctx.beginPath();
    for (let i: number = 0; i < pts.length; i++) {
      let x: number = cx + pts[i][0] * maxR;
      let y: number = cy - pts[i][1] * maxR;
      if (i === 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    }
    ctx.closePath();
    ctx.clip();
  }

  private static clipParamOutline(ctx: OffscreenCanvasRenderingContext2D, shape: ShapeDef, size: number): void {
    let cx: number = size / 2;
    let cy: number = size / 2;
    let maxR: number = cx * 0.92;
    let pts: Array<[number, number]> = shape.outlinePoints(240);
    ctx.beginPath();
    for (let i: number = 0; i < pts.length; i++) {
      let x: number = cx + pts[i][0] * maxR;
      let y: number = cy - pts[i][1] * maxR;
      if (i === 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    }
    ctx.closePath();
    ctx.clip();
  }

  // Composite the drawn words with the glyph alpha mask: outside the glyph keeps
  // the outer/inner background; inside the glyph keeps the word color.
  private static applyGlyphMask(ctx: OffscreenCanvasRenderingContext2D, size: number,
    shape: ShapeDef, outerBg: string, shapeInnerBg: string): ImageData {
    let bm: GlyphMask = shape.bitmap as GlyphMask;
    let s: number = bm.size;
    let scale: number = size / s;
    let src: ImageData = ctx.getImageData(0, 0, size, size);
    let out: ImageData = ctx.createImageData(size, size);
    let outData: Uint8ClampedArray = out.data;
    let srcData: Uint8ClampedArray = src.data;

    // resolve background colors to rgba bytes
    let bgOuter: [number, number, number, number] = WordCloudRenderUtil.parseColor(outerBg, [0, 0, 0, 0]);
    let bgInner: [number, number, number, number] = WordCloudRenderUtil.parseColor(shapeInnerBg, bgOuter);

    for (let y: number = 0; y < size; y++) {
      let sy: number = Math.min(s - 1, Math.floor(y / scale));
      for (let x: number = 0; x < size; x++) {
        let sx: number = Math.min(s - 1, Math.floor(x / scale));
        let inside: boolean = bm.data[sy * s + sx] === 1;
        let o: number = (y * size + x) * 4;
        if (inside) {
          outData[o] = srcData[o];
          outData[o + 1] = srcData[o + 1];
          outData[o + 2] = srcData[o + 2];
          outData[o + 3] = srcData[o + 3];
        } else {
          outData[o] = bgOuter[0];
          outData[o + 1] = bgOuter[1];
          outData[o + 2] = bgOuter[2];
          outData[o + 3] = bgOuter[3];
        }
      }
    }
    return out;
  }

  private static parseColor(c: string, fallback: [number, number, number, number]): [number, number, number, number] {
    if (!c || c === 'transparent') {
      return [0, 0, 0, 0];
    }
    if (c.startsWith('#')) {
      let hex: string = c.substring(1);
      if (hex.length === 3) {
        hex = hex[0] + hex[0] + hex[1] + hex[1] + hex[2] + hex[2];
      }
      if (hex.length !== 6) {
        return fallback;
      }
      return [
        parseInt(hex.substring(0, 2), 16),
        parseInt(hex.substring(2, 4), 16),
        parseInt(hex.substring(4, 6), 16),
        255
      ];
    }
    return fallback;
  }
}
