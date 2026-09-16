/**
 * 叠加层渲染器：用 @ohos.graphics.drawing 把文字/贴纸(emoji)光栅化到整帧 RGBA 像素上。
 * 在主线程逐帧调用（导出时对每帧 decode → compose 后再渲染叠加层）。
 */
import { drawing } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import { OverlayItem, overlayColorToArgb, overlayFontPx } from './GifOverlayModel';

/**
 * 将 overlays 绘制到 width×height 的 RGBA 像素上，返回紧凑(无行距)像素。
 * overlays 为空时原样返回 pixels。
 */
export async function renderOverlaysIntoPixels(pixels: Uint8Array, width: number, height: number,
  overlays: OverlayItem[]): Promise<Uint8Array> {
  if (overlays.length === 0 || width <= 0 || height <= 0) {
    return pixels;
  }
  let srcBuffer: ArrayBuffer = pixels.buffer.slice(pixels.byteOffset, pixels.byteOffset + pixels.byteLength);
  let opts: image.InitializationOptions = {
    size: { width: width, height: height },
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    srcPixelFormat: image.PixelMapFormat.RGBA_8888
  };
  let pm: image.PixelMap = await image.createPixelMap(srcBuffer, opts);
  try {
    let canvas: drawing.Canvas = new drawing.Canvas(pm);
    for (let i: number = 0; i < overlays.length; i++) {
      let item: OverlayItem = overlays[i];
      if (item.text.length === 0) {
        continue;
      }
      let font: drawing.Font = new drawing.Font();
      font.setSize(overlayFontPx(item.fontPx, height));
      let blob: drawing.TextBlob = drawing.TextBlob.makeFromString(item.text, font);
      let metrics: drawing.FontMetrics = font.getMetrics();
      let brush: drawing.Brush = new drawing.Brush();
      brush.setColor(overlayColorToArgb(item.color));
      canvas.save();
      canvas.translate(item.x * width, item.y * height);
      canvas.rotate(item.rotation, 0, 0);
      canvas.attachBrush(brush);
      // 垂直居中：基线位于 (ascent+descent)/2 的反向偏移处
      canvas.drawTextBlob(blob, 0, -(metrics.ascent + metrics.descent) / 2);
      canvas.detachBrush();
      canvas.restore();
    }
    let info: image.ImageInfo = pm.getImageInfoSync();
    let rowBytes: number = width * 4;
    let stride: number = info.stride !== undefined && info.stride > 0 ? info.stride : rowBytes;
    let readBuf: ArrayBuffer = new ArrayBuffer(stride * height);
    pm.readPixelsToBufferSync(readBuf);
    let out: Uint8Array = new Uint8Array(rowBytes * height);
    let src: Uint8Array = new Uint8Array(readBuf);
    for (let row: number = 0; row < height; row++) {
      let from: number = row * stride;
      let to: number = row * rowBytes;
      for (let col: number = 0; col < rowBytes; col++) {
        out[to + col] = src[from + col];
      }
    }
    return out;
  } catch (e) {
    console.error('[GifOverlayRenderer] renderOverlaysIntoPixels failed: ' + (e as Error).message);
    return pixels;
  } finally {
    pm.release();
  }
}
