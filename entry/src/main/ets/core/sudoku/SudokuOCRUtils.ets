import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AdaptiveResizeParams } from './SudokuOCRTypes';

export const DOMAIN: number = 0xA03D00;
export const TAG: string = 'SudokuOCR';

export const TARGET_CELL_PX: number = 100;
export const OCR_MAX_DIM: number = 4096;
export const OCR_MIN_DIM: number = 360;
export const BOARD_CROP_PAD_RATIO: number = 0.10;
export const CELL_CROP_PAD_FACTOR: number = 0.50;
export const CELL_UPSCALE_FACTOR: number = 5;
export const CELL_CROP_PAD_FACTOR_RETRY: number = 0.15;
export const CELL_UPSCALE_FACTOR_RETRY: number = 8;
export const EMPTY_FILL_PIXEL_CONF: number = 0.55;
export const EMPTY_FILL_PIXEL_CONF_NO_RAW_DIGITS: number = 0.72;
export const MIN_CELL_CROP_DIM: number = 10;
export const PER_CELL_VK_TIMEOUT_MS: number = 2000;
export const MAX_FIX_CELLS: number = 180;
export const VK_SLOW_CALL_THRESHOLD_MS: number = 1500;
export const VK_MAX_CONSECUTIVE_NULL: number = 36;
export const WIDE_CELL_PAD_X_FACTOR: number = 1.10;
export const WIDE_CELL_PAD_Y_FACTOR: number = 0.25;
export const WIDE_CELL_UPSCALE_FACTOR: number = 5;
export const OCR_PIPELINE_TOTAL_TIMEOUT_MS: number = 30000;
export const RESIZE_LARGE_THRESHOLD: number = 2000;
export const RESIZE_LARGE_TARGET: number = 1600;
export const RESIZE_MEDIUM_THRESHOLD: number = 1280;
export const RESIZE_SMALL_THRESHOLD: number = 800;
export const RESIZE_SMALL_TARGET: number = 800;
export const LOW_CONFIDENCE_THRESHOLD: number = 0.5;
export const CONFUSABLE_DIGITS: number[] = [2, 3, 4, 5, 6, 7, 8, 9];
export const CONFUSABLE_RECHECK_CONFIDENCE: number = 0.85;
export const CONFUSABLE_PIXEL_OVERRIDE_CONF: number = 0.6;
export const EXISTING_PIXEL_ONLY_OVERRIDE_CONF: number = 0.72;
export const STABLE_PIXEL_ONLY_OVERRIDE_CONF: number = 0.66;
export const POSITIONAL_CONFIDENCE: number = 0.7;
export const TEXT_FALLBACK_CONFIDENCE: number = 0.5;
export const WARP_SIZE_MULTIPLIER: number = 1.1;
export const BG_DARK_THRESHOLD: number = 128;
export const OCR_CELL_OCCUPANCY_MIN_RATIO: number = 0.035;
export const WARP_BG_SAMPLE_DIV: number = 20000;
export const PIXEL_MAX_DIM: number = 1200;

export function yieldThread(): Promise<void> {
  return new Promise<void>((resolve: Function) => { setTimeout(() => { resolve(); }, 1); });
}

export function withTimeout<T>(promise: Promise<T>, ms: number, fallback: T): Promise<T> {
  return new Promise<T>((resolve: Function) => {
    let settled: boolean = false;
    const timer: number = setTimeout(() => {
      if (!settled) {
        settled = true;
        hilog.warn(DOMAIN, TAG, 'withTimeout: %{public}dms超时', ms);
        resolve(fallback);
      }
    }, ms);
    promise.then((result: T) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        resolve(result);
      }
    }).catch((_err: Object) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        hilog.warn(DOMAIN, TAG, 'withTimeout: 异常 %{public}s', `${_err}`);
        resolve(fallback);
      }
    });
  });
}

export function computeAdaptiveResize(origW: number, origH: number): AdaptiveResizeParams {
  const maxDim: number = Math.max(origW, origH);
  let targetW: number = origW;
  let targetH: number = origH;
  let targetCellPx: number = TARGET_CELL_PX;
  const MAX_UPSCALE: number = 2.0;

  if (maxDim > RESIZE_LARGE_THRESHOLD) {
    const scale: number = RESIZE_LARGE_TARGET / maxDim;
    targetW = Math.round(origW * scale);
    targetH = Math.round(origH * scale);
  } else if (maxDim >= RESIZE_SMALL_THRESHOLD) {
    if (maxDim > RESIZE_MEDIUM_THRESHOLD) {
      const scale: number = RESIZE_MEDIUM_THRESHOLD / maxDim;
      targetW = Math.round(origW * scale);
      targetH = Math.round(origH * scale);
    }
  } else {
    const scale: number = Math.min(MAX_UPSCALE, RESIZE_SMALL_TARGET / maxDim);
    targetW = Math.round(origW * scale);
    targetH = Math.round(origH * scale);
  }

  const params: AdaptiveResizeParams = { targetW: targetW, targetH: targetH, targetCellPx: targetCellPx };
  return params;
}

export function openImageSource(uri: string): image.ImageSource {
  const file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
  return image.createImageSource(file.fd);
}

export function openImageSourceFromBuffer(buf: ArrayBuffer): image.ImageSource {
  return image.createImageSource(buf);
}

export function cropCellFromBuffer(
  pixels: Uint8Array, imgW: number, imgH: number,
  cropX: number, cropY: number, cropW: number, cropH: number,
  upscale: number
): image.PixelMap | null {
  try {
    const dstStride: number = cropW * 4;
    const bufSize: number = dstStride * cropH;
    const buf: ArrayBuffer = new ArrayBuffer(bufSize);
    const dst: Uint8Array = new Uint8Array(buf);
    for (let y: number = 0; y < cropH; y++) {
      const srcRowOff: number = ((cropY + y) * imgW + cropX) * 4;
      const dstRowOff: number = y * dstStride;
      for (let x: number = 0; x < dstStride; x++) {
        dst[dstRowOff + x] = pixels[srcRowOff + x];
      }
    }
    const opts: image.InitializationOptions = {
      editable: true,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      size: { height: cropH, width: cropW }
    };
    const snapshot: image.PixelMap = image.createPixelMapSync(opts);
    const destArea: image.PositionArea = {
      pixels: buf,
      offset: 0,
      stride: dstStride,
      region: { size: { width: cropW, height: cropH }, x: 0, y: 0 }
    };
    snapshot.writePixelsSync(destArea);
    snapshot.scaleSync(upscale, upscale);
    return snapshot;
  } catch (_e) {
    return null;
  }
}
