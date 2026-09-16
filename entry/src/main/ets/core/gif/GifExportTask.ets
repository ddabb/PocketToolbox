import { taskpool } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { GifFrameData, GifEncodeOptions, encodeGif, composeFramePixels } from './GifEncoder';

/**
 * GIF 导出任务入参：主线程完成图片解码后，把各帧 RGBA 像素传入 taskpool 编码。
 * framePixels 为源帧像素（保持宽高比缩放后），order 为播放顺序（源帧下标序列）。
 * delays 与 order 等长（每个播放位次的帧延迟）；frameRotations 与源帧等长（0/90/180/270）。
 */
export interface GifExportTaskInput {
  frameCount: number;
  canvasWidth: number;
  canvasHeight: number;
  frameWidths: number[];
  frameHeights: number[];
  framePixels: Uint8Array[];
  order: number[];
  delays: number[];
  frameRotations?: number[];
  loopCount: number;
  dither: boolean;
}

@Concurrent
function encodeGifTask(input: GifExportTaskInput): Uint8Array {
  let canvasW: number = input.canvasWidth;
  let canvasH: number = input.canvasHeight;
  let frames: GifFrameData[] = [];
  for (let o: number = 0; o < input.order.length; o++) {
    let src: number = input.order[o];
    let fw: number = input.frameWidths[src];
    let fh: number = input.frameHeights[src];
    let rotation: number = input.frameRotations !== undefined ? input.frameRotations[src] : 0;
    let px: Uint8Array = composeFramePixels(input.framePixels[src], fw, fh, rotation, canvasW, canvasH);
    let frame: GifFrameData = new GifFrameData();
    frame.width = canvasW;
    frame.height = canvasH;
    frame.delayCs = input.delays[o];
    frame.pixels = px;
    frames.push(frame);
  }
  let opts: GifEncodeOptions = new GifEncodeOptions();
  opts.loopCount = input.loopCount;
  opts.dither = input.dither;
  return encodeGif(frames, opts);
}

let currentTask: taskpool.Task | null = null;

export async function runGifExportTask(input: GifExportTaskInput): Promise<Uint8Array> {
  let task: taskpool.Task = new taskpool.Task(encodeGifTask, input);
  currentTask = task;
  try {
    return await taskpool.execute(task, taskpool.Priority.HIGH) as Uint8Array;
  } catch (e) {
    console.error('[GifExportTask] execute failed: ' + (e as BusinessError).message);
    throw e as Error;
  } finally {
    currentTask = null;
  }
}

export function cancelGifExportTask(): void {
  if (currentTask !== null) {
    try {
      taskpool.cancel(currentTask);
    } catch (e) {
      console.warn('[GifExportTask] cancel failed: ' + (e as BusinessError).message);
    }
  }
}
