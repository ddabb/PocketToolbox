import { BusinessError } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { media } from '@kit.MediaKit';
import { fileIo as fs, fileUri, WriteOptions, ReadOptions } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { buildFrameOrder, resolveFrameDelayCs, composeFramePixels } from '../core/gif/GifEncoder';
import { parseGif, resizeRgba, swapBgraRgba, GifParseResult } from '../core/gif/GifParser';
import { GifExportTaskInput, runGifExportTask, cancelGifExportTask } from '../core/gif/GifExportTask';
import {
  OverlayItem,
  overlayFontPx,
  clampOverlayFont,
  clampOverlayPos,
  normalizeOverlayRotation,
  OVERLAY_KIND_TEXT,
  OVERLAY_KIND_STICKER
} from '../core/gif/GifOverlayModel';
import { renderOverlaysIntoPixels } from '../core/gif/GifOverlayRenderer';
import { GifHistoryStore, GifHistoryRecord, makeHistoryFileName, formatGifBytes } from '../core/gif/GifHistoryStore';
import { shareGifViaPanel } from '../common/utils/ShareImageUtil';
import { ToastUtil } from '../common/utils/ToastUtil';
import { VibrateUtil } from '../common/utils/VibrateUtil';

const MIN_FRAMES: number = 2;
const MAX_FRAMES: number = 30;
const MAX_ORIGINAL_EDGE: number = 720;
const MAX_VIDEO_SPAN_MS: number = 15000;

const SPEED_LABELS: string[] = ['0.25x', '0.5x', '1x', '2x', '4x'];
const SPEED_VALUES: number[] = [0.25, 0.5, 1, 2, 4];
const PLAY_MODE_LABELS: string[] = ['正放', '倒放', '来回'];
const PLAY_MODE_VALUES: string[] = ['forward', 'reverse', 'pingpong'];
const LOOP_LABELS: string[] = ['无限', '1次', '3次', '5次', '10次'];
const LOOP_VALUES: number[] = [0, 1, 3, 5, 10];
const SIZE_LABELS: string[] = ['原始', '480P', '720P'];
const QUALITY_LABELS: string[] = ['标准', '高清'];
const VIDEO_FPS_LABELS: string[] = ['5帧/秒', '10帧/秒', '15帧/秒', '24帧/秒'];
const VIDEO_FPS_VALUES: number[] = [5, 10, 15, 24];

const OVERLAY_COLORS: string[] = [
  '#FFFFFF', '#000000', '#E53E3E', '#ED8936', '#ECC94B', '#48BB78',
  '#38B2AC', '#3182CE', '#805AD5', '#ED64A6', '#A0AEC0', '#744210'
];
const STICKER_CATEGORIES: string[] = ['表情', '装饰', '气泡'];
const STICKER_SETS: string[][] = [
  ['😀', '😂', '🥹', '😍', '🥰', '😎', '🤔', '😭', '😡', '🥳', '😴', '🤡'],
  ['❤️', '🔥', '✨', '⭐', '🌈', '🎉', '🎊', '💯', '⚡', '🌸', '👍', '🥇'],
  ['💬', '🗯️', '💭', '❗', '❓', '‼️', '⁉️', '💤', '🎵', '🚫', '✅', '❌']
];

let overlayIdSeq: number = 0;

function makeOverlayId(): string {
  overlayIdSeq++;
  return 'ov' + overlayIdSeq.toString();
}

/** 可观察叠加层：@Observed 使子组件 @ObjectLink 感知手势中的属性变更 */
@Observed
class ObservedOverlayItem extends OverlayItem {
  constructor(kind: string, text: string, color: string, fontPx: number, x: number, y: number, rotation: number) {
    super(kind, text, color, fontPx, x, y, rotation, makeOverlayId());
  }
}

/**
 * 叠加层锚点：手势（拖动/捏合缩放旋转）直接修改 @ObjectLink item 触发自刷新。
 * 组件随稳定 id 键值复用，手势不会因 ForEach 重建而中断。
 */
@Component
struct OverlayAnchorView {
  @ObjectLink item: ObservedOverlayItem;
  @Link boxW: number;
  @Link boxH: number;
  @Link selectedOverlayId: string;
  onTapOverlay: (id: string, toggle: boolean) => void = (id: string, toggle: boolean) => {
  };
  onOverlayGestureEnd: () => void = () => {
  };
  private dragStartX: number = 0;
  private dragStartY: number = 0;
  private pinchStartFont: number = 32;
  private pinchStartRotation: number = 0;

  build() {
    Column() {
      Text(this.item.text)
        .fontSize(Math.max(8, overlayFontPx(this.item.fontPx, this.boxH)))
        .fontColor(this.item.kind === OVERLAY_KIND_TEXT ? this.item.color : Color.White)
        .textAlign(TextAlign.Center)
        .maxLines(2)
    }
    .alignItems(HorizontalAlign.Center)
    .padding(6)
    .border({
      width: this.item.id === this.selectedOverlayId ? 1 : 0,
      color: $r('app.color.idiom_blue'),
      style: BorderStyle.Dashed
    })
    .position({ x: this.item.x * this.boxW, y: this.item.y * this.boxH })
    .translate({ x: '-50%', y: '-50%' })
    .rotate({ angle: this.item.rotation })
    .onClick(() => {
      this.onTapOverlay(this.item.id, true);
    })
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        PanGesture({ fingers: 1 })
          .onActionStart(() => {
            this.onTapOverlay(this.item.id, false);
            this.dragStartX = this.item.x;
            this.dragStartY = this.item.y;
          })
          .onActionUpdate((event: GestureEvent) => {
            this.item.x = clampOverlayPos(this.dragStartX + event.offsetX / this.boxW);
            this.item.y = clampOverlayPos(this.dragStartY + event.offsetY / this.boxH);
          })
          .onActionEnd(() => {
            this.onOverlayGestureEnd();
          }),
        PinchGesture({ fingers: 2 })
          .onActionStart(() => {
            this.onTapOverlay(this.item.id, false);
            this.pinchStartFont = this.item.fontPx;
            this.pinchStartRotation = this.item.rotation;
          })
          .onActionUpdate((event: GestureEvent) => {
            this.item.fontPx = clampOverlayFont(this.item.kind, this.pinchStartFont * event.scale);
            this.item.rotation = normalizeOverlayRotation(this.pinchStartRotation + event.angle);
          })
          .onActionEnd(() => {
            this.onOverlayGestureEnd();
          })
      )
    )
  }
}

class GifFrameItem {
  uri: string = '';
  width: number = 0;
  height: number = 0;
  rotation: number = 0; // 0/90/180/270
  durationMs: number = 0; // 0 = 跟随全局帧时长
  pixelMap: image.PixelMap | null = null; // GIF 拆帧 / 视频抽帧来源时非空

  constructor(uri: string, width: number, height: number) {
    this.uri = uri;
    this.width = width;
    this.height = height;
  }
}

class DecodedFrame {
  pixels: Uint8Array = new Uint8Array(0);
  width: number = 0;
  height: number = 0;
}

@Component
struct GifSectionCard {
  @Prop title: string = '';
  @BuilderParam content: () => void;

  build() {
    Column({ space: 12 }) {
      Text(this.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .alignSelf(ItemAlign.Start)
      this.content()
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }
}

@Builder
export function GifMakerPageBuilder() {
  NavDestination() {
    GifMakerPage()
  }
  .title('GIF 制作')
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct GifMakerPage {
  @State viewMode: string = 'select'; // select | videoConfig | edit | result | history | historyPreview
  @State frames: GifFrameItem[] = [];
  @State selectedFrameIndex: number = -1;
  @State perFrameDurationInput: string = '';
  // 参数
  @State frameDurationMs: number = 500;
  @State durationInput: string = '0.50';
  @State speedIndex: number = 2;
  @State playModeIndex: number = 0;
  @State loopIndex: number = 0;
  @State sizeIndex: number = 1; // 默认 480P
  @State qualityIndex: number = 0;
  // 预览
  @State playing: boolean = true;
  @State previewPos: number = 0;
  // 视频转 GIF 配置
  @State videoUri: string = '';
  @State videoDurationMs: number = 0;
  @State videoStartMs: number = 0;
  @State videoSpanMs: number = 3000;
  @State videoFpsIndex: number = 1; // 默认 10fps
  @State videoThumb: image.PixelMap | null = null;
  // 导出
  @State exporting: boolean = false;
  @State exportPhase: string = '';
  @State exportProgress: number = 0;
  @State exportedPath: string = '';
  @State exportedSize: number = 0;
  @State exportedWidth: number = 0;
  @State exportedHeight: number = 0;
  // 贴纸与文字
  @State overlays: ObservedOverlayItem[] = [];
  @State selectedOverlayId: string = '';
  @State overlayTextInput: string = '';
  @State stickerCategoryIndex: number = 0;
  @State customColorInput: string = '';
  @State previewBoxAvailW: number = 320;
  @State previewBoxW: number = 320;
  @State previewBoxH: number = 200;
  @State overlayUiRev: number = 0;
  // 制作历史
  @State historyRecords: GifHistoryRecord[] = [];
  @State historyBytes: number = 0;
  @State historyPreviewPath: string = '';

  private previewTimerId: number = -1;
  private exportCancelled: boolean = false;

  aboutToAppear(): void {
    this.syncPreviewTimer();
    this.refreshHistory();
  }

  aboutToDisappear(): void {
    this.stopPreviewTimer();
    this.releaseAllFramePixels();
    this.releaseVideoThumb();
  }

  // ---------- 预览 ----------

  private displayOrder(): number[] {
    return buildFrameOrder(this.frames.length, PLAY_MODE_VALUES[this.playModeIndex]);
  }

  private previewIntervalMs(): number {
    let speed: number = SPEED_VALUES[this.speedIndex];
    let interval: number = this.frameDurationMs / speed;
    return interval < 50 ? 50 : interval;
  }

  /** 当前预览位次的实际间隔：单帧时长覆盖 > 全局帧时长，均受倍速影响 */
  private currentPreviewIntervalMs(): number {
    let order: number[] = this.displayOrder();
    if (order.length === 0) {
      return this.previewIntervalMs();
    }
    let item: GifFrameItem = this.frames[order[this.previewPos % order.length]];
    let ms: number = item.durationMs > 0 ? item.durationMs : this.frameDurationMs;
    let interval: number = ms / SPEED_VALUES[this.speedIndex];
    return interval < 50 ? 50 : interval;
  }

  private currentPreviewItem(): GifFrameItem | null {
    let order: number[] = this.displayOrder();
    if (order.length === 0) {
      return null;
    }
    return this.frames[order[this.previewPos % order.length]];
  }

  private currentPreviewSrc(): image.PixelMap | string {
    let item: GifFrameItem | null = this.currentPreviewItem();
    if (item === null) {
      return '';
    }
    return item.pixelMap !== null ? item.pixelMap : item.uri;
  }

  private currentPreviewRotation(): number {
    let item: GifFrameItem | null = this.currentPreviewItem();
    return item !== null ? item.rotation : 0;
  }

  private isCurrentPreviewRotated(): boolean {
    let r: number = this.currentPreviewRotation();
    return r === 90 || r === 270;
  }

  /** 画布预览盒：把输出画布按宽高比适配到 (可用宽度, 220) 内，白底与导出一致 */
  private canvasPreviewBox(): number[] {
    let canvas: number[] = this.outputCanvasSize();
    let availW: number = this.previewBoxAvailW > 80 ? this.previewBoxAvailW : 80;
    let availH: number = 220;
    let w: number = availW;
    let h: number = w * canvas[1] / canvas[0];
    if (h > availH) {
      h = availH;
      w = h * canvas[0] / canvas[1];
    }
    return [w, h];
  }

  /** 当前帧在预览盒中的显示区域：顶左对齐，匹配导出 composeFramePixels 几何 */
  private frameBoxInPreview(): number[] {
    let box: number[] = this.canvasPreviewBox();
    let item: GifFrameItem | null = this.currentPreviewItem();
    let canvas: number[] = this.outputCanvasSize();
    if (item === null || item.width <= 0 || item.height <= 0) {
      return [box[0], box[1]];
    }
    let boxEdge: number = Math.max(canvas[0], canvas[1]);
    let scale: number = Math.min(1, boxEdge / Math.max(item.width, item.height));
    let k: number = box[0] / canvas[0];
    let fw: number = item.width * scale * k;
    let fh: number = item.height * scale * k;
    if (this.isCurrentPreviewRotated()) {
      return [fh, fw];
    }
    return [fw, fh];
  }

  private advancePreview(): void {
    let order: number[] = this.displayOrder();
    if (order.length === 0) {
      return;
    }
    this.previewPos = (this.previewPos + 1) % order.length;
  }

  private syncPreviewTimer(): void {
    let shouldRun: boolean = this.viewMode === 'edit' && this.playing && this.frames.length >= MIN_FRAMES;
    if (!shouldRun) {
      this.stopPreviewTimer();
      return;
    }
    this.stopPreviewTimer();
    this.schedulePreviewTick();
  }

  private schedulePreviewTick(): void {
    this.previewTimerId = setTimeout(() => {
      this.advancePreview();
      this.schedulePreviewTick();
    }, this.currentPreviewIntervalMs());
  }

  private stopPreviewTimer(): void {
    if (this.previewTimerId >= 0) {
      clearTimeout(this.previewTimerId);
      this.previewTimerId = -1;
    }
  }

  private onFramesChanged(): void {
    if (this.selectedFrameIndex >= this.frames.length) {
      this.selectedFrameIndex = this.frames.length - 1;
    }
    if (this.previewPos >= this.displayOrder().length) {
      this.previewPos = 0;
    }
    this.syncPreviewBox();
    this.syncPreviewTimer();
  }

  // ---------- 选图与帧管理 ----------

  private async pickImages(): Promise<void> {
    if (this.frames.length >= MAX_FRAMES) {
      ToastUtil.show(this.getUIContext(), `最多支持 ${MAX_FRAMES} 张图片`, 2000);
      return;
    }
    try {
      let options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = MAX_FRAMES - this.frames.length;
      let picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      let result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
      if (result.photoUris.length === 0) {
        return;
      }
      if (this.frames.length === 0 && result.photoUris.length < MIN_FRAMES) {
        ToastUtil.show(this.getUIContext(), '至少选择 2 张图片', 2000);
        return;
      }
      let willFull: number = this.frames.length + result.photoUris.length;
      if (willFull > MAX_FRAMES) {
        ToastUtil.show(this.getUIContext(), `最多支持 ${MAX_FRAMES} 张，已保留前 ${MAX_FRAMES - this.frames.length} 张`, 2000);
      }
      for (let i = 0; i < result.photoUris.length && this.frames.length < MAX_FRAMES; i++) {
        let uri: string = result.photoUris[i];
        let size: number[] = await this.queryImageSize(uri);
        this.frames.push(new GifFrameItem(uri, size[0], size[1]));
      }
      this.onFramesChanged();
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      if (err.code !== 0) {
        ToastUtil.show(this.getUIContext(), '选择图片失败: ' + err.message, 2000);
      }
    }
  }

  private async queryImageSize(uri: string): Promise<number[]> {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      let source: image.ImageSource = image.createImageSource(file.fd);
      let info: image.ImageInfo = await source.getImageInfo();
      let w: number = info.size.width;
      let h: number = info.size.height;
      source.release();
      return [w, h];
    } catch (e) {
      return [0, 0];
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file.fd);
        } catch (e) {
          console.error('[GifMaker] close file failed: ' + (e as Error).message);
        }
      }
    }
  }

  // ---------- 像素帧资源管理 ----------

  private releaseFramePixels(item: GifFrameItem): void {
    let pm: image.PixelMap | null = item.pixelMap;
    if (pm !== null) {
      pm.release();
      item.pixelMap = null;
    }
  }

  private releaseAllFramePixels(): void {
    for (let i = 0; i < this.frames.length; i++) {
      this.releaseFramePixels(this.frames[i]);
    }
  }

  private releaseVideoThumb(): void {
    let pm: image.PixelMap | null = this.videoThumb;
    if (pm !== null) {
      pm.release();
      this.videoThumb = null;
    }
  }

  private resetEditorState(): void {
    this.releaseAllFramePixels();
    this.frames = [];
    this.selectedFrameIndex = -1;
    this.perFrameDurationInput = '';
    this.previewPos = 0;
    this.playing = true;
    this.overlays = [];
    this.selectedOverlayId = '';
    this.overlayTextInput = '';
  }

  // ---------- 编辑 GIF（F30~F33） ----------

  private readFileBytes(uri: string): Uint8Array {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      let stat: fs.Stat = fs.statSync(file.fd);
      let size: number = stat.size;
      let buffer: ArrayBuffer = new ArrayBuffer(size);
      let readOpts: ReadOptions = { length: size };
      let bytesRead: number = fs.readSync(file.fd, buffer, readOpts);
      let raw: Uint8Array = new Uint8Array(buffer);
      return raw.subarray(0, bytesRead);
    } catch (e) {
      console.error('[GifMaker] read file failed: ' + (e as Error).message);
      throw new Error((e as Error).message);
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file.fd);
        } catch (e) {
          console.error('[GifMaker] close file failed: ' + (e as Error).message);
        }
      }
    }
  }

  /** GIF 拆帧导入的画布像素 → RGBA PixelMap */
  private async createRgbaPixelMap(pixels: Uint8Array, width: number, height: number): Promise<image.PixelMap> {
    let buffer: ArrayBuffer = pixels.buffer.slice(pixels.byteOffset, pixels.byteOffset + pixels.byteLength);
    let opts: image.InitializationOptions = {
      size: { width: width, height: height },
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888
    };
    return image.createPixelMap(buffer, opts);
  }

  /** 将解析出的循环次数映射到循环选项档位 */
  private applyParsedLoop(loopCount: number): void {
    let idx: number = 1;
    if (loopCount === 0) {
      idx = 0;
    } else if (loopCount === 3) {
      idx = 2;
    } else if (loopCount === 5) {
      idx = 3;
    } else if (loopCount === 10) {
      idx = 4;
    }
    this.loopIndex = idx;
  }

  private async pickGif(): Promise<void> {
    try {
      let options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      let picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      let result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
      if (result.photoUris.length === 0) {
        return;
      }
      let uri: string = result.photoUris[0];
      this.exporting = true;
      this.exportCancelled = false;
      this.exportProgress = 5;
      this.exportPhase = '解析 GIF 中...';
      let bytes: Uint8Array = this.readFileBytes(uri);
      if (bytes.length < 13 || bytes[0] !== 0x47 || bytes[1] !== 0x49 || bytes[2] !== 0x46 || bytes[3] !== 0x38) {
        ToastUtil.show(this.getUIContext(), '不是有效的 GIF 文件', 2000);
        return;
      }
      let parsed: GifParseResult = parseGif(bytes);
      if (parsed.frames.length < MIN_FRAMES) {
        ToastUtil.show(this.getUIContext(), '该 GIF 帧数不足，无法编辑', 2000);
        return;
      }
      let count: number = Math.min(parsed.frames.length, MAX_FRAMES);
      if (parsed.frames.length > MAX_FRAMES) {
        ToastUtil.show(this.getUIContext(), `帧数超过 ${MAX_FRAMES}，已保留前 ${MAX_FRAMES} 帧`, 2000);
      }
      let longEdge: number = Math.max(parsed.width, parsed.height);
      let scale: number = longEdge > MAX_ORIGINAL_EDGE ? MAX_ORIGINAL_EDGE / longEdge : 1;
      let targetW: number = Math.max(1, Math.round(parsed.width * scale));
      let targetH: number = Math.max(1, Math.round(parsed.height * scale));
      let newFrames: GifFrameItem[] = [];
      for (let i = 0; i < count; i++) {
        if (this.exportCancelled) {
          break;
        }
        this.exportPhase = `解析帧 ${i + 1}/${count}`;
        this.exportProgress = 5 + Math.round((i / count) * 90);
        let src: Uint8Array = parsed.frames[i].pixels;
        if (scale < 1) {
          src = resizeRgba(src, parsed.width, parsed.height, targetW, targetH);
        }
        let pm: image.PixelMap = await this.createRgbaPixelMap(src, targetW, targetH);
        let item: GifFrameItem = new GifFrameItem('', targetW, targetH);
        item.pixelMap = pm;
        let ms: number = parsed.frames[i].delayCs * 10;
        if (ms > 0) {
          if (ms < 50) {
            ms = 50;
          }
          if (ms > 2000) {
            ms = 2000;
          }
          item.durationMs = Math.round(ms / 50) * 50;
        }
        newFrames.push(item);
      }
      if (this.exportCancelled) {
        for (let i = 0; i < newFrames.length; i++) {
          this.releaseFramePixels(newFrames[i]);
        }
        ToastUtil.show(this.getUIContext(), '已取消导入', 1500);
        return;
      }
      this.resetEditorState();
      this.frames = newFrames;
      this.applyParsedLoop(parsed.loopCount);
      this.viewMode = 'edit';
      this.onFramesChanged();
      ToastUtil.show(this.getUIContext(), `已导入 ${count} 帧`, 1500);
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[GifMaker] parse gif failed: ' + err.code + ' ' + err.message);
      ToastUtil.show(this.getUIContext(), '解析 GIF 失败: ' + err.message, 2500);
    } finally {
      this.exporting = false;
    }
  }

  // ---------- 视频转 GIF（F20~F24） ----------

  private videoSpanMaxMs(): number {
    let max: number = Math.min(MAX_VIDEO_SPAN_MS, this.videoDurationMs);
    return max < 500 ? 500 : max;
  }

  private videoStartMaxMs(): number {
    let max: number = this.videoDurationMs - this.videoSpanMs;
    return max < 0 ? 0 : max;
  }

  private plannedVideoFrameCount(): number {
    let fps: number = VIDEO_FPS_VALUES[this.videoFpsIndex];
    let count: number = Math.floor(this.videoSpanMs * fps / 1000);
    if (count < MIN_FRAMES) {
      count = MIN_FRAMES;
    }
    if (count > MAX_FRAMES) {
      count = MAX_FRAMES;
    }
    return count;
  }

  private async queryVideoDurationMs(uri: string): Promise<number> {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      let extractor: media.AVMetadataExtractor = await media.createAVMetadataExtractor();
      let fdSrc: media.AVFileDescriptor = { fd: file.fd };
      extractor.fdSrc = fdSrc;
      let metadata: media.AVMetadata = await extractor.fetchMetadata();
      await extractor.release();
      if (metadata.duration !== undefined) {
        let ms: number = parseFloat(metadata.duration);
        if (!isNaN(ms) && ms > 0) {
          return Math.floor(ms);
        }
      }
      return 0;
    } catch (e) {
      console.warn('[GifMaker] query video duration failed: ' + (e as Error).message);
      return 0;
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file.fd);
        } catch (e) {
          console.error('[GifMaker] close video file failed: ' + (e as Error).message);
        }
      }
    }
  }

  /** 抽取指定时间点的视频帧（可不缩放），调用方负责释放 */
  private async fetchVideoFrame(
    generator: media.AVImageGenerator,
    timeUs: number,
    targetW: number,
    targetH: number
  ): Promise<image.PixelMap> {
    let param: media.PixelMapParams = {};
    if (targetW > 0) {
      param.width = targetW;
    }
    if (targetH > 0) {
      param.height = targetH;
    }
    try {
      return generator.fetchFrameByTime(
        timeUs,
        media.AVImageQueryOptions.AV_IMAGE_QUERY_CLOSEST,
        param
      );
    } catch (e) {
      console.error('[GifMaker] fetch video frame failed: ' + (e as Error).message);
      throw new Error((e as Error).message);
    }
  }

  /** 读取 PixelMap 的紧凑 RGBA 像素（处理行对齐 stride） */
  private async readPixelMapFrame(pm: image.PixelMap): Promise<DecodedFrame> {
    let result: DecodedFrame = new DecodedFrame();
    let info: image.ImageInfo = await pm.getImageInfo();
    let w: number = info.size.width;
    let h: number = info.size.height;
    let stride: number = info.stride > 0 ? info.stride : w * 4;
    let buffer: ArrayBuffer = new ArrayBuffer(stride * h);
    try {
      pm.readPixelsToBufferSync(buffer);
    } catch (e) {
      console.error('[GifMaker] read pixels failed: ' + (e as Error).message);
      throw new Error((e as Error).message);
    }
    let raw: Uint8Array = new Uint8Array(buffer);
    result.width = w;
    result.height = h;
    if (stride === w * 4) {
      result.pixels = raw;
      return result;
    }
    let tight: Uint8Array = new Uint8Array(w * h * 4);
    for (let y = 0; y < h; y++) {
      for (let b = 0; b < w * 4; b++) {
        tight[y * w * 4 + b] = raw[y * stride + b];
      }
    }
    result.pixels = tight;
    return result;
  }

  /** 视频帧 PixelMap 归一化为 RGBA_8888（BGRA 时转换，其余格式报错） */
  private async normalizeFramePixelMap(pm: image.PixelMap): Promise<image.PixelMap> {
    let info: image.ImageInfo = await pm.getImageInfo();
    if (info.pixelFormat === image.PixelMapFormat.RGBA_8888) {
      return pm;
    }
    if (info.pixelFormat === image.PixelMapFormat.BGRA_8888) {
      let decoded: DecodedFrame = await this.readPixelMapFrame(pm);
      let rgba: Uint8Array = swapBgraRgba(decoded.pixels);
      pm.release();
      return this.createRgbaPixelMap(rgba, decoded.width, decoded.height);
    }
    pm.release();
    throw new Error('不支持的视频帧格式');
  }

  private async pickVideo(): Promise<void> {
    try {
      let options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE;
      options.maxSelectNumber = 1;
      let picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      let result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
      if (result.photoUris.length === 0) {
        return;
      }
      let uri: string = result.photoUris[0];
      this.exporting = true;
      this.exportCancelled = false;
      this.exportProgress = 30;
      this.exportPhase = '读取视频信息...';
      let durationMs: number = await this.queryVideoDurationMs(uri);
      if (durationMs <= 0) {
        ToastUtil.show(this.getUIContext(), '无法读取视频时长，可能是不支持的格式', 2500);
        return;
      }
      let file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      let thumb: image.PixelMap | null = null;
      try {
        let generator: media.AVImageGenerator = await media.createAVImageGenerator();
        let fdSrc: media.AVFileDescriptor = { fd: file.fd };
        generator.fdSrc = fdSrc;
        let thumbTimeUs: number = Math.min(1000, Math.floor(durationMs / 2)) * 1000;
        thumb = await this.fetchVideoFrame(generator, thumbTimeUs, 0, 0);
        await generator.release();
      } finally {
        try {
          fs.closeSync(file.fd);
        } catch (e) {
          console.error('[GifMaker] close video file failed: ' + (e as Error).message);
        }
      }
      this.videoUri = uri;
      this.videoDurationMs = durationMs;
      this.videoStartMs = 0;
      this.videoSpanMs = Math.min(3000, durationMs);
      this.videoFpsIndex = 1;
      this.releaseVideoThumb();
      this.videoThumb = thumb;
      this.viewMode = 'videoConfig';
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[GifMaker] pick video failed: ' + err.code + ' ' + err.message);
      ToastUtil.show(this.getUIContext(), '读取视频失败: ' + err.message, 2500);
    } finally {
      this.exporting = false;
    }
  }

  private async extractVideoFrames(): Promise<void> {
    if (this.videoUri.length === 0 || this.exporting) {
      return;
    }
    this.exporting = true;
    this.exportCancelled = false;
    this.exportProgress = 0;
    this.exportPhase = '准备抽帧...';
    let file: fs.File | null = null;
    let generator: media.AVImageGenerator | null = null;
    let partial: GifFrameItem[] = [];
    try {
      let frameCount: number = this.plannedVideoFrameCount();
      let stepMs: number = this.videoSpanMs / frameCount;
      file = fs.openSync(this.videoUri, fs.OpenMode.READ_ONLY);
      generator = await media.createAVImageGenerator();
      let fdSrc: media.AVFileDescriptor = { fd: file.fd };
      generator.fdSrc = fdSrc;
      // 首帧探测原始尺寸，用于下采样（长边 ≤720，防 OOM）
      let probeTimeUs: number = this.videoStartMs * 1000;
      let probe: image.PixelMap = await this.fetchVideoFrame(generator, probeTimeUs, 0, 0);
      let probeInfo: image.ImageInfo = await probe.getImageInfo();
      let origW: number = probeInfo.size.width;
      let origH: number = probeInfo.size.height;
      probe.release();
      let scale: number = Math.min(1, MAX_ORIGINAL_EDGE / Math.max(origW, origH));
      let targetW: number = Math.max(1, Math.round(origW * scale));
      let targetH: number = Math.max(1, Math.round(origH * scale));
      for (let i = 0; i < frameCount; i++) {
        if (this.exportCancelled) {
          break;
        }
        this.exportPhase = `抽帧 ${i + 1}/${frameCount}`;
        this.exportProgress = Math.round((i / frameCount) * 95);
        let tMs: number = this.videoStartMs + i * stepMs;
        let tMaxMs: number = Math.max(0, this.videoDurationMs - 20);
        if (tMs > tMaxMs) {
          tMs = tMaxMs;
        }
        let fetched: image.PixelMap = await this.fetchVideoFrame(generator, tMs * 1000, targetW, targetH);
        let normalized: image.PixelMap = await this.normalizeFramePixelMap(fetched);
        let normInfo: image.ImageInfo = await normalized.getImageInfo();
        let item: GifFrameItem = new GifFrameItem('', normInfo.size.width, normInfo.size.height);
        item.pixelMap = normalized;
        partial.push(item);
      }
      if (this.exportCancelled) {
        for (let i = 0; i < partial.length; i++) {
          this.releaseFramePixels(partial[i]);
        }
        ToastUtil.show(this.getUIContext(), '已取消抽帧', 1500);
        return;
      }
      if (partial.length < MIN_FRAMES) {
        throw new Error('抽帧数量不足');
      }
      let fps: number = VIDEO_FPS_VALUES[this.videoFpsIndex];
      let frameMs: number = Math.round(1000 / fps / 50) * 50;
      if (frameMs < 50) {
        frameMs = 50;
      }
      this.resetEditorState();
      this.frames = partial;
      this.frameDurationMs = frameMs;
      this.durationInput = (frameMs / 1000).toFixed(2);
      this.viewMode = 'edit';
      this.onFramesChanged();
      ToastUtil.show(this.getUIContext(), `已抽取 ${partial.length} 帧`, 1500);
    } catch (e) {
      for (let i = 0; i < partial.length; i++) {
        this.releaseFramePixels(partial[i]);
      }
      let err: BusinessError = e as BusinessError;
      console.error('[GifMaker] extract frames failed: ' + err.code + ' ' + err.message);
      ToastUtil.show(this.getUIContext(), '抽帧失败: ' + err.message, 2500);
    } finally {
      if (generator !== null) {
        try {
          generator.release();
        } catch (e) {
          console.error('[GifMaker] release generator failed: ' + (e as Error).message);
        }
      }
      if (file !== null) {
        try {
          fs.closeSync(file.fd);
        } catch (e) {
          console.error('[GifMaker] close video file failed: ' + (e as Error).message);
        }
      }
      this.exporting = false;
    }
  }

  private deleteSelectedFrame(): void {
    if (this.selectedFrameIndex < 0 || this.selectedFrameIndex >= this.frames.length) {
      ToastUtil.show(this.getUIContext(), '请先点选一个帧', 1500);
      return;
    }
    this.releaseFramePixels(this.frames[this.selectedFrameIndex]);
    this.frames.splice(this.selectedFrameIndex, 1);
    this.selectedFrameIndex = -1;
    this.perFrameDurationInput = '';
    this.onFramesChanged();
    if (this.frames.length < MIN_FRAMES) {
      ToastUtil.show(this.getUIContext(), '帧数不足 2 张，无法导出', 1500);
    }
  }

  private moveSelectedFrame(delta: number): void {
    if (this.selectedFrameIndex < 0 || this.selectedFrameIndex >= this.frames.length) {
      ToastUtil.show(this.getUIContext(), '请先点选一个帧', 1500);
      return;
    }
    let target: number = this.selectedFrameIndex + delta;
    if (target < 0 || target >= this.frames.length) {
      return;
    }
    let tmp: GifFrameItem = this.frames[this.selectedFrameIndex];
    this.frames[this.selectedFrameIndex] = this.frames[target];
    this.frames[target] = tmp;
    this.selectedFrameIndex = target;
    this.onFramesChanged();
  }

  private reverseFrames(): void {
    if (this.frames.length < MIN_FRAMES) {
      return;
    }
    let left: number = 0;
    let right: number = this.frames.length - 1;
    while (left < right) {
      let tmp: GifFrameItem = this.frames[left];
      this.frames[left] = this.frames[right];
      this.frames[right] = tmp;
      left++;
      right--;
    }
    this.selectedFrameIndex = -1;
    this.perFrameDurationInput = '';
    this.onFramesChanged();
  }

  private rotateSelectedFrame(): void {
    if (this.selectedFrameIndex < 0 || this.selectedFrameIndex >= this.frames.length) {
      ToastUtil.show(this.getUIContext(), '请先点选一个帧', 1500);
      return;
    }
    let item: GifFrameItem = this.frames[this.selectedFrameIndex];
    item.rotation = (item.rotation + 90) % 360;
    // GifFrameItem 非可观察对象，重新赋值数组触发预览/缩略图刷新
    this.frames = this.frames.slice();
    this.syncPreviewBox();
  }

  private applyPerFrameDuration(): void {
    if (this.selectedFrameIndex < 0 || this.selectedFrameIndex >= this.frames.length) {
      return;
    }
    let raw: string = this.perFrameDurationInput.trim();
    if (raw.length === 0) {
      this.clearPerFrameDuration();
      return;
    }
    let seconds: number = parseFloat(raw);
    if (isNaN(seconds)) {
      this.syncPerFrameInput();
      return;
    }
    if (seconds < 0.05) {
      seconds = 0.05;
    }
    if (seconds > 2.0) {
      seconds = 2.0;
    }
    let ms: number = Math.round(seconds * 1000 / 50) * 50;
    this.frames[this.selectedFrameIndex].durationMs = ms;
    this.perFrameDurationInput = (ms / 1000).toFixed(2);
    this.syncPreviewTimer();
  }

  private clearPerFrameDuration(): void {
    if (this.selectedFrameIndex < 0 || this.selectedFrameIndex >= this.frames.length) {
      return;
    }
    this.frames[this.selectedFrameIndex].durationMs = 0;
    this.perFrameDurationInput = '';
    this.syncPreviewTimer();
  }

  private syncPerFrameInput(): void {
    if (this.selectedFrameIndex < 0 || this.selectedFrameIndex >= this.frames.length) {
      this.perFrameDurationInput = '';
      return;
    }
    let ms: number = this.frames[this.selectedFrameIndex].durationMs;
    this.perFrameDurationInput = ms > 0 ? (ms / 1000).toFixed(2) : '';
  }

  // ---------- 参数 ----------

  private applyDurationInput(): void {
    let seconds: number = parseFloat(this.durationInput);
    if (isNaN(seconds)) {
      seconds = 0.5;
    }
    if (seconds < 0.05) {
      seconds = 0.05;
    }
    if (seconds > 2.0) {
      seconds = 2.0;
    }
    let ms: number = Math.round(seconds * 1000 / 50) * 50;
    this.frameDurationMs = ms;
    this.durationInput = (ms / 1000).toFixed(2);
    this.syncPreviewTimer();
  }

  private outputCanvasSize(): number[] {
    let boxEdge: number = 0;
    if (this.sizeIndex === 1) {
      boxEdge = 480;
    } else if (this.sizeIndex === 2) {
      boxEdge = 720;
    }
    let maxLong: number = 0;
    for (let i = 0; i < this.frames.length; i++) {
      let longEdge: number = Math.max(this.frames[i].width, this.frames[i].height);
      if (longEdge > maxLong) {
        maxLong = longEdge;
      }
    }
    if (boxEdge === 0) {
      // 原始尺寸：以最大帧为基准，长边上限 720 防止内存超限
      boxEdge = Math.min(MAX_ORIGINAL_EDGE, maxLong > 0 ? maxLong : MAX_ORIGINAL_EDGE);
    }
    let canvasW: number = 0;
    let canvasH: number = 0;
    for (let i = 0; i < this.frames.length; i++) {
      let w: number = this.frames[i].width;
      let h: number = this.frames[i].height;
      if (w === 0 || h === 0) {
        continue;
      }
      let scale: number = Math.min(1, boxEdge / Math.max(w, h));
      let sw: number = Math.max(1, Math.round(w * scale));
      let sh: number = Math.max(1, Math.round(h * scale));
      // 旋转 90/270 的帧有效尺寸宽高互换
      if (this.frames[i].rotation === 90 || this.frames[i].rotation === 270) {
        let tmp: number = sw;
        sw = sh;
        sh = tmp;
      }
      if (sw > canvasW) {
        canvasW = sw;
      }
      if (sh > canvasH) {
        canvasH = sh;
      }
    }
    if (canvasW === 0 || canvasH === 0) {
      canvasW = boxEdge;
      canvasH = boxEdge;
    }
    return [canvasW, canvasH];
  }

  // ---------- 贴纸与文字（F70~F75） ----------

  /** 同步预览盒尺寸（子组件 @Link 依赖），帧/尺寸/可用宽度变化时调用 */
  private syncPreviewBox(): void {
    let box: number[] = this.canvasPreviewBox();
    this.previewBoxW = box[0];
    this.previewBoxH = box[1];
  }

  private indexOfOverlay(id: string): number {
    for (let i = 0; i < this.overlays.length; i++) {
      if (this.overlays[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  /** 按叠加层位置取项 */
  private overlayAt(index: number): OverlayItem | null {
    if (index < 0 || index >= this.overlays.length) {
      return null;
    }
    return this.overlays[index];
  }

  private updateOverlayById(id: string, mutator: (item: OverlayItem) => void): void {
    let index: number = this.indexOfOverlay(id);
    if (index < 0) {
      return;
    }
    mutator(this.overlays[index]);
    // 重赋数组触发页面级绑定刷新（子组件由 @ObjectLink 自行刷新）
    this.overlays = this.overlays.slice();
  }

  private addTextOverlay(): void {
    let text: string = this.overlayTextInput.trim();
    if (text.length === 0) {
      ToastUtil.show(this.getUIContext(), '请输入文字内容', 1500);
      return;
    }
    let item: ObservedOverlayItem = new ObservedOverlayItem(OVERLAY_KIND_TEXT, text, '#FFFFFF', 32, 0.5, 0.5, 0);
    this.overlays.push(item);
    this.overlays = this.overlays.slice();
    this.selectedOverlayId = item.id;
    this.overlayTextInput = '';
  }

  private addStickerOverlay(sticker: string): void {
    let offset: number = (this.overlays.length % 5) * 0.06 - 0.12;
    let item: ObservedOverlayItem = new ObservedOverlayItem(OVERLAY_KIND_STICKER, sticker, '#FFFFFF', 48,
      clampOverlayPos(0.5 + offset), clampOverlayPos(0.5 + offset), 0);
    this.overlays.push(item);
    this.overlays = this.overlays.slice();
    this.selectedOverlayId = item.id;
  }

  private deleteSelectedOverlay(): void {
    let pos: number = this.indexOfOverlay(this.selectedOverlayId);
    if (pos < 0) {
      return;
    }
    this.overlays.splice(pos, 1);
    this.overlays = this.overlays.slice();
    this.selectedOverlayId = '';
  }

  private selectedOverlay(): OverlayItem | null {
    let pos: number = this.indexOfOverlay(this.selectedOverlayId);
    return this.overlayAt(pos);
  }

  private selectedFontMax(): number {
    let item: OverlayItem | null = this.selectedOverlay();
    return item !== null && item.kind === OVERLAY_KIND_STICKER ? 160 : 72;
  }

  private nudgeSelectedRotation(delta: number): void {
    this.updateOverlayById(this.selectedOverlayId, (item: OverlayItem) => {
      item.rotation = normalizeOverlayRotation(item.rotation + delta);
    });
  }

  private applyOverlayText(value: string): void {
    this.updateOverlayById(this.selectedOverlayId, (item: OverlayItem) => {
      item.text = value;
    });
  }

  private applyOverlayFont(value: number): void {
    this.updateOverlayById(this.selectedOverlayId, (item: OverlayItem) => {
      item.fontPx = clampOverlayFont(item.kind, value);
    });
  }

  private applyOverlayColor(color: string): void {
    this.updateOverlayById(this.selectedOverlayId, (item: OverlayItem) => {
      item.color = color;
    });
  }

  private applyCustomColor(): void {
    let raw: string = this.customColorInput.trim();
    if (!/^#[0-9a-fA-F]{6}$/.test(raw)) {
      ToastUtil.show(this.getUIContext(), '请输入 #RRGGBB 格式颜色', 1500);
      return;
    }
    this.applyOverlayColor(raw.toUpperCase());
  }

  // ---------- 制作历史（F100~F104） ----------

  private refreshHistory(): void {
    let context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.historyRecords = GifHistoryStore.loadRecords(context);
    let total: number = 0;
    for (let i = 0; i < this.historyRecords.length; i++) {
      total += this.historyRecords[i].sizeBytes;
    }
    this.historyBytes = total;
  }

  private recordExportHistory(context: common.UIAbilityContext, w: number, h: number, frameCount: number): void {
    try {
      let record: GifHistoryRecord = new GifHistoryRecord();
      record.id = Date.now().toString(36) + '_' + Math.floor(Math.random() * 10000).toString();
      record.fileName = makeHistoryFileName();
      record.exportedAt = Date.now();
      record.width = w;
      record.height = h;
      record.frameCount = frameCount;
      record.paramsText = SIZE_LABELS[this.sizeIndex] + ' · ' + (this.frameDurationMs / 1000).toFixed(2) + 's/帧 · '
        + SPEED_LABELS[this.speedIndex] + ' · ' + PLAY_MODE_LABELS[this.playModeIndex] + ' · '
        + LOOP_LABELS[this.loopIndex] + ' · ' + QUALITY_LABELS[this.qualityIndex];
      if (!GifHistoryStore.saveRecord(context, this.exportedPath, record)) {
        console.warn('[GifMaker] save history record failed');
      }
      this.refreshHistory();
    } catch (e) {
      console.warn('[GifMaker] record history failed: ' + (e as Error).message);
    }
  }

  private formatTimestamp(ms: number): string {
    let d: Date = new Date(ms);
    let mm: string = (d.getMonth() + 1) < 10 ? '0' + (d.getMonth() + 1) : (d.getMonth() + 1).toString();
    let dd: string = d.getDate() < 10 ? '0' + d.getDate() : d.getDate().toString();
    let hh: string = d.getHours() < 10 ? '0' + d.getHours() : d.getHours().toString();
    let mi: string = d.getMinutes() < 10 ? '0' + d.getMinutes() : d.getMinutes().toString();
    return `${mm}-${dd} ${hh}:${mi}`;
  }

  private openHistory(): void {
    this.refreshHistory();
    this.viewMode = 'history';
  }

  private deleteHistoryRecord(record: GifHistoryRecord): void {
    let dialogParam: AlertDialogParamWithButtons = {
      title: '删除记录',
      message: '删除后该成品 GIF 将从沙箱中移除，已保存到相册的副本不受影响。确定删除？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        action: () => {
          let context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
          GifHistoryStore.deleteRecord(context, record.id);
          this.refreshHistory();
          ToastUtil.show(this.getUIContext(), '已删除', 1200);
        }
      }
    };
    this.getUIContext().showAlertDialog(dialogParam);
  }

  private clearHistoryAll(): void {
    if (this.historyRecords.length === 0) {
      return;
    }
    let dialogParam: AlertDialogParamWithButtons = {
      title: '清空历史',
      message: `将删除全部 ${this.historyRecords.length} 条记录（约 ${formatGifBytes(this.historyBytes)}），已保存到相册的副本不受影响。确定清空？`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清空',
        action: () => {
          let context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
          GifHistoryStore.clearAll(context);
          this.refreshHistory();
          ToastUtil.show(this.getUIContext(), '已清空', 1200);
        }
      }
    };
    this.getUIContext().showAlertDialog(dialogParam);
  }

  // ---------- 导出 ----------

  private estimateOutputBytes(): number {
    let canvas: number[] = this.outputCanvasSize();
    let order: number[] = this.displayOrder();
    // 经验估算：LZW 压缩后约 0.25 字节/像素
    return canvas[0] * canvas[1] * order.length * 0.25;
  }

  private async decodeFramePixels(
    item: GifFrameItem,
    boxEdge: number
  ): Promise<DecodedFrame> {
    // 像素帧来源（GIF 拆帧 / 视频抽帧）：像素已在导入时归一化为 RGBA
    if (item.pixelMap !== null) {
      let decoded: DecodedFrame = await this.readPixelMapFrame(item.pixelMap);
      if (Math.max(decoded.width, decoded.height) > boxEdge) {
        let scale: number = Math.min(1, boxEdge / Math.max(decoded.width, decoded.height));
        let tw: number = Math.max(1, Math.round(decoded.width * scale));
        let th: number = Math.max(1, Math.round(decoded.height * scale));
        decoded.pixels = resizeRgba(decoded.pixels, decoded.width, decoded.height, tw, th);
        decoded.width = tw;
        decoded.height = th;
      }
      return decoded;
    }
    let result: DecodedFrame = new DecodedFrame();
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    try {
      file = fs.openSync(item.uri, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      let info: image.ImageInfo = await source.getImageInfo();
      let origW: number = info.size.width;
      let origH: number = info.size.height;
      let scale: number = Math.min(1, boxEdge / Math.max(origW, origH));
      let targetW: number = Math.max(1, Math.round(origW * scale));
      let targetH: number = Math.max(1, Math.round(origH * scale));
      let pixelMap: image.PixelMap = await source.createPixelMap({
        desiredSize: { width: targetW, height: targetH },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
      try {
        source.release();
      } catch (e) {
        console.error('[GifMaker] release image source failed: ' + (e as Error).message);
      }
      source = null;
      try {
        fs.closeSync(file.fd);
      } catch (e) {
        console.error('[GifMaker] close file failed: ' + (e as Error).message);
      }
      file = null;
      let decoded: image.ImageInfo = await pixelMap.getImageInfo();
      let w: number = decoded.size.width;
      let h: number = decoded.size.height;
      let buffer: ArrayBuffer = new ArrayBuffer(w * h * 4);
      pixelMap.readPixelsToBufferSync(buffer);
      pixelMap.release();
      result.pixels = new Uint8Array(buffer);
      result.width = w;
      result.height = h;
      return result;
    } catch (e) {
      console.error('[GifMaker] decode frame failed: ' + (e as Error).message);
      throw new Error((e as Error).message);
    } finally {
      if (source !== null) {
        try {
          source.release();
        } catch (e) {
          console.error('[GifMaker] release image source failed: ' + (e as Error).message);
        }
      }
      if (file !== null) {
        try {
          fs.closeSync(file.fd);
        } catch (e) {
          console.error('[GifMaker] close file failed: ' + (e as Error).message);
        }
      }
    }
  }

  private startExport(): void {
    if (this.frames.length < MIN_FRAMES) {
      ToastUtil.show(this.getUIContext(), '至少需要 2 张图片', 2000);
      return;
    }
    if (this.estimateOutputBytes() > 30 * 1024 * 1024) {
      let dialogParam: AlertDialogParamWithButtons = {
        title: '体积提示',
        message: '按当前参数预计生成文件较大（可能超过 30MB），建议降低尺寸或减少帧数。是否继续？',
        primaryButton: {
          value: '取消',
          action: () => {
          }
        },
        secondaryButton: {
          value: '继续',
          action: () => {
            this.doExport();
          }
        }
      };
      this.getUIContext().showAlertDialog(dialogParam);
      return;
    }
    this.doExport();
  }

  private async doExport(): Promise<void> {
    if (this.exporting) {
      return;
    }
    this.exporting = true;
    this.exportCancelled = false;
    this.exportProgress = 0;
    this.exportPhase = '准备中...';
    const exportT0: number = Date.now();
    console.info('[GifMaker] export start: ' + this.frames.length + ' frames ' + this.outputCanvasSize()[0] + 'x' + this.outputCanvasSize()[1]);
    try {
      let canvas: number[] = this.outputCanvasSize();
      let canvasW: number = canvas[0];
      let canvasH: number = canvas[1];
      let boxEdge: number = Math.max(canvasW, canvasH);
      let hasOverlays: boolean = this.overlays.length > 0;
      let widths: number[] = [];
      let heights: number[] = [];
      let pixelsList: Uint8Array[] = [];
      for (let i = 0; i < this.frames.length; i++) {
        if (this.exportCancelled) {
          return;
        }
        this.exportPhase = hasOverlays ? `合成 ${i + 1}/${this.frames.length}` : `解码 ${i + 1}/${this.frames.length}`;
        this.exportProgress = Math.round((i / this.frames.length) * 75);
        let decoded: DecodedFrame = await this.decodeFramePixels(this.frames[i], boxEdge);
        if (hasOverlays) {
          // 有叠加层：主线程先合成到画布并渲染贴纸/文字，任务池直接使用画布尺寸像素
          let composed: Uint8Array = composeFramePixels(decoded.pixels, decoded.width, decoded.height,
            this.frames[i].rotation, canvasW, canvasH);
          composed = await renderOverlaysIntoPixels(composed, canvasW, canvasH, this.overlays);
          pixelsList.push(composed);
          widths.push(canvasW);
          heights.push(canvasH);
        } else {
          pixelsList.push(decoded.pixels);
          widths.push(decoded.width);
          heights.push(decoded.height);
        }
      }
      if (this.exportCancelled) {
        return;
      }
      this.exportPhase = '编码中...';
      console.info('[GifMaker] decode done in ' + (Date.now() - exportT0) + 'ms');
      this.exportProgress = 85;
      let order: number[] = this.displayOrder();
      let speed: number = SPEED_VALUES[this.speedIndex];
      let delays: number[] = order.map((src: number): number => {
        return resolveFrameDelayCs(this.frames[src].durationMs, this.frameDurationMs, speed);
      });
      let rotations: number[] = this.frames.map((item: GifFrameItem): number => {
        return item.rotation;
      });
      if (hasOverlays) {
        // 预合成像素已是画布尺寸且朝向正确，任务池跳过旋转合成
        rotations = this.frames.map((item: GifFrameItem): number => {
          return 0;
        });
      }
      let input: GifExportTaskInput = {
        frameCount: this.frames.length,
        canvasWidth: canvasW,
        canvasHeight: canvasH,
        frameWidths: widths,
        frameHeights: heights,
        framePixels: pixelsList,
        order: order,
        delays: delays,
        frameRotations: rotations,
        loopCount: LOOP_VALUES[this.loopIndex],
        dither: this.qualityIndex === 1
      };
      let gifBytes: Uint8Array = await runGifExportTask(input);
      if (this.exportCancelled) {
        return;
      }
      this.exportProgress = 96;
      this.exportPhase = '写入文件...';
      let context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      let filePath: string = context.cacheDir + '/gifmaker_' + Date.now() + '.gif';
      let file: fs.File = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        let writeOpts: WriteOptions = {
          offset: gifBytes.byteOffset,
          length: gifBytes.byteLength
        };
        fs.writeSync(file.fd, gifBytes.buffer, writeOpts);
      } catch (e) {
        console.error('[GifMaker] write gif file failed: ' + (e as Error).message);
        throw new Error((e as Error).message);
      } finally {
        try {
          fs.closeSync(file.fd);
        } catch (e) {
          console.error('[GifMaker] close file failed: ' + (e as Error).message);
        }
      }
      this.exportedPath = filePath;
      this.exportedSize = gifBytes.length;
      console.info('[GifMaker] export done: ' + this.frames.length + ' frames ' + canvasW + 'x' + canvasH
        + ' ' + gifBytes.length + ' bytes in ' + (Date.now() - exportT0) + 'ms');
      this.exportedWidth = canvasW;
      this.exportedHeight = canvasH;
      this.exportProgress = 100;
      this.viewMode = 'result';
      this.stopPreviewTimer();
      this.recordExportHistory(context, canvasW, canvasH, order.length);
      VibrateUtil.success();
      ToastUtil.show(this.getUIContext(), 'GIF 生成完成', 1500);
    } catch (e) {
      if (this.exportCancelled) {
        ToastUtil.show(this.getUIContext(), '已取消导出', 1500);
      } else {
        let err: BusinessError = e as BusinessError;
        console.error('[GifMaker] export failed: ' + err.code + ' ' + err.message);
        VibrateUtil.error();
        ToastUtil.show(this.getUIContext(), '导出失败: ' + err.message, 2500);
      }
    } finally {
      this.exporting = false;
      this.exportTaskCleanup();
    }
  }

  private exportTaskCleanup(): void {
    cancelGifExportTask();
  }

  private cancelExport(): void {
    if (!this.exporting) {
      return;
    }
    this.exportCancelled = true;
    cancelGifExportTask();
  }

  // ---------- 保存与分享 ----------

  private async saveToAlbum(): Promise<void> {
    if (!this.exportedPath) {
      return;
    }
    await this.saveGifPathToAlbum(this.exportedPath);
  }

  private async saveGifPathToAlbum(path: string): Promise<void> {
    if (!path) {
      return;
    }
    let uiCtx: UIContext = this.getUIContext();
    try {
      let context: common.UIAbilityContext = uiCtx.getHostContext() as common.UIAbilityContext;
      let helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      let srcFileUri: string = fileUri.getUriFromPath(path);
      let srcFileUris: Array<string> = [srcFileUri];
      let photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [{
        title: 'GIF_' + Date.now(),
        fileNameExtension: 'gif',
        photoType: photoAccessHelper.PhotoType.IMAGE,
      }];
      let desFileUris: Array<string> = await helper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs);
      if (desFileUris.length > 0) {
        let srcFile: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
        let desFile: fs.File = await fs.open(desFileUris[0], fs.OpenMode.WRITE_ONLY);
        await fs.copyFile(srcFile.fd, desFile.fd);
        fs.closeSync(srcFile);
        await fs.close(desFile.fd);
        ToastUtil.show(uiCtx, '已保存到相册', 1500);
      }
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[GifMaker] save failed: ' + err.code + ' ' + err.message);
      ToastUtil.show(uiCtx, '保存失败', 2000);
    }
  }

  private shareGif(): void {
    if (!this.exportedPath) {
      return;
    }
    shareGifViaPanel(this.getUIContext(), this.exportedPath);
  }

  private formatBytes(bytes: number): string {
    if (bytes >= 1024 * 1024) {
      return (bytes / 1024 / 1024).toFixed(1) + ' MB';
    }
    return Math.max(1, Math.round(bytes / 1024)) + ' KB';
  }

  // ---------- UI ----------

  @Builder
  ModeCard(icon: string, title: string, subtitle: string, color: string, enabled: boolean, action: () => void) {
    Row({ space: 14 }) {
      Text(icon)
        .fontSize(28)
        .width(52)
        .height(52)
        .textAlign(TextAlign.Center)
        .backgroundColor(color + '18')
        .borderRadius(14)
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
          if (!enabled) {
            Text('敬请期待')
              .fontSize(10)
              .fontColor($r('app.color.tertiary_text'))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor($r('app.color.page_background'))
              .borderRadius(8)
          }
        }
        Text(subtitle)
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›')
        .fontSize(20)
        .fontColor($r('app.color.tertiary_text'))
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
    .opacity(enabled ? 1 : 0.6)
    .onClick(() => {
      if (enabled) {
        action();
      } else {
        ToastUtil.show(this.getUIContext(), '敬请期待', 1500);
      }
    })
  }

  @Builder
  OptionChips(labels: string[], selected: number, onPick: (index: number) => void) {
    Row({ space: 8 }) {
      ForEach(labels, (label: string, index: number) => {
        Text(label)
          .fontSize(13)
          .fontColor(index === selected ? Color.White : $r('app.color.secondary_text'))
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .backgroundColor(index === selected ? $r('app.color.idiom_blue') : $r('app.color.page_background'))
          .borderRadius(14)
          .border({
            width: 1,
            color: index === selected ? $r('app.color.idiom_blue') : $r('app.color.border_color')
          })
          .onClick(() => {
            onPick(index);
          })
      }, (label: string, index: number) => label + '_' + index.toString())
    }
  }

  @Builder
  ParamLabel(text: string) {
    Text(text)
      .fontSize(12)
      .fontColor($r('app.color.tertiary_text'))
      .alignSelf(ItemAlign.Start)
  }

  @Builder
  FrameThumb(item: GifFrameItem, index: number) {
    Column({ space: 4 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Image(item.pixelMap !== null ? item.pixelMap : item.uri)
          .width(64)
          .height(64)
          .objectFit(ImageFit.Cover)
          .borderRadius(10)
        Text((index + 1).toString())
          .fontSize(10)
          .fontColor(Color.White)
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .backgroundColor('#99000000')
          .borderRadius(8)
          .position({ x: 4, y: 4 })
        if (item.rotation > 0) {
          Text(item.rotation + '°')
            .fontSize(10)
            .fontColor(Color.White)
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .backgroundColor('#99000000')
            .borderRadius(8)
            .margin(4)
        }
      }
      .border({
        width: index === this.selectedFrameIndex ? 2 : 0,
        color: $r('app.color.idiom_blue')
      })
      .borderRadius(12)
    }
    .onClick(() => {
      if (index === this.selectedFrameIndex) {
        this.selectedFrameIndex = -1;
      } else {
        this.selectedFrameIndex = index;
      }
      this.syncPerFrameInput();
    })
  }

  @Builder
  FrameOpsButton(text: string, action: () => void) {
    Text(text)
      .fontSize(13)
      .fontColor($r('app.color.secondary_text'))
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .backgroundColor($r('app.color.page_background'))
      .borderRadius(14)
      .border({ width: 1, color: $r('app.color.border_color') })
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        action();
      })
  }

  @Builder
  SelectView() {
    Column({ space: 12 }) {
      this.ModeCard('🖼️', '图片合成 GIF', '选择 2~30 张图片，合成动态 GIF', '#ec4899', true, () => {
        this.viewMode = 'edit';
        this.pickImages();
      })
      this.ModeCard('🎬', '视频转 GIF', '截取视频片段，抽帧生成 GIF', '#f59e0b', true, () => {
        this.pickVideo();
      })
      this.ModeCard('✏️', '编辑 GIF', '拆解已有 GIF，二次编辑加工', '#10b981', true, () => {
        this.pickGif();
      })
      this.ModeCard('🕘', '制作历史', `最近成品 ${this.historyRecords.length} 条 · 占用 ${formatGifBytes(this.historyBytes)}`, '#6366f1', true, () => {
        this.openHistory();
      })
      Text('纯本地处理，不上传任何图片；导出无水印')
        .fontSize(11)
        .fontColor($r('app.color.tertiary_text'))
        .margin({ top: 8 })
    }
    .width('100%')
  }

  @Builder
  VideoConfigView() {
    Column({ space: 12 }) {
      GifSectionCard({ title: '视频片段' }) {
        Column({ space: 12 }) {
          if (this.videoThumb !== null) {
            Image(this.videoThumb)
              .width('100%')
              .height(180)
              .objectFit(ImageFit.Contain)
              .borderRadius(10)
              .backgroundColor($r('app.color.page_background'))
          }
          Text(`视频时长 ${(this.videoDurationMs / 1000).toFixed(1)}s · 已选 ${(this.videoSpanMs / 1000).toFixed(1)}s 片段`)
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))

          Column({ space: 6 }) {
            this.ParamLabel(`起始时间 ${(this.videoStartMs / 1000).toFixed(1)}s`)
            Slider({
              value: this.videoStartMs,
              min: 0,
              max: this.videoStartMaxMs(),
              step: 100
            })
              .selectedColor($r('app.color.idiom_blue'))
              .width('100%')
              .onChange((value: number) => {
                let ms: number = Math.round(value / 100) * 100;
                if (ms > this.videoStartMaxMs()) {
                  ms = this.videoStartMaxMs();
                }
                this.videoStartMs = ms;
              })
          }

          Column({ space: 6 }) {
            this.ParamLabel(`截取时长 ${(this.videoSpanMs / 1000).toFixed(1)}s（最长 15s）`)
            Slider({
              value: this.videoSpanMs,
              min: 500,
              max: this.videoSpanMaxMs(),
              step: 100
            })
              .selectedColor($r('app.color.idiom_blue'))
              .width('100%')
              .onChange((value: number) => {
                let ms: number = Math.round(value / 100) * 100;
                if (ms < 500) {
                  ms = 500;
                }
                if (ms > this.videoSpanMaxMs()) {
                  ms = this.videoSpanMaxMs();
                }
                this.videoSpanMs = ms;
                if (this.videoStartMs > this.videoStartMaxMs()) {
                  this.videoStartMs = this.videoStartMaxMs();
                }
              })
          }

          Column({ space: 6 }) {
            this.ParamLabel('抽帧帧率')
            this.OptionChips(VIDEO_FPS_LABELS, this.videoFpsIndex, (index: number) => {
              this.videoFpsIndex = index;
            })
          }

          Text(`预计抽取 ${this.plannedVideoFrameCount()} 帧（上限 ${MAX_FRAMES} 帧）`)
            .fontSize(12)
            .fontColor($r('app.color.tertiary_text'))
        }
        .width('100%')
      }

      Button('开始抽帧')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .height(46)
        .backgroundColor($r('app.color.idiom_blue'))
        .onClick(() => {
          this.extractVideoFrames();
        })

      Button('重新选择视频')
        .fontSize(14)
        .width('100%')
        .height(42)
        .backgroundColor($r('app.color.card_background'))
        .fontColor($r('app.color.secondary_text'))
        .border({ width: 1, color: $r('app.color.border_color') })
        .onClick(() => {
          this.viewMode = 'select';
        })
    }
    .width('100%')
  }

  @Builder
  PreviewArea() {
    if (this.frames.length === 0) {
      Column({ space: 12 }) {
        Text('🖼️')
          .fontSize(44)
        Text('尚未选择图片')
          .fontSize(14)
          .fontColor($r('app.color.secondary_text'))
        Button('选择图片')
          .fontSize(14)
          .height(38)
          .backgroundColor($r('app.color.idiom_blue'))
          .onClick(() => {
            this.pickImages();
          })
      }
      .width('100%')
      .padding({ top: 24, bottom: 24 })
    } else {
      Column({ space: 10 }) {
        Stack() {
          // 当前帧：顶左对齐（与导出 composeFramePixels 几何一致）
          Image(this.currentPreviewSrc())
            .width(this.frameBoxInPreview()[0])
            .height(this.frameBoxInPreview()[1])
            .objectFit(ImageFit.Fill)
            .rotate({ angle: this.currentPreviewRotation() })
            .position({ x: 0, y: 0 })
          // 叠加层：按归一化坐标锚定画布中心点，手势在子组件内处理
          ForEach(this.overlays, (item: ObservedOverlayItem) => {
            OverlayAnchorView({
              item: item,
              boxW: this.previewBoxW,
              boxH: this.previewBoxH,
              selectedOverlayId: this.selectedOverlayId,
              onTapOverlay: (id: string, toggle: boolean) => {
                if (toggle) {
                  this.selectedOverlayId = this.selectedOverlayId === id ? '' : id;
                } else {
                  this.selectedOverlayId = id;
                }
              },
              onOverlayGestureEnd: () => {
                // 手势结束后刷新页面级编辑面板显示
                this.overlayUiRev++;
              }
            })
          }, (item: ObservedOverlayItem) => item.id)
        }
        .width(this.canvasPreviewBox()[0])
        .height(this.canvasPreviewBox()[1])
        .backgroundColor(Color.White)
        .borderRadius(10)
        .clip(true)
        .alignContent(Alignment.TopStart)
        .onClick(() => {
          // 点击空白处取消选中
          this.selectedOverlayId = '';
        })

        Row({ space: 10 }) {
          Text(this.playing ? '⏸' : '▶')
            .fontSize(16)
            .fontColor($r('app.color.idiom_blue'))
            .width(36)
            .height(36)
            .textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.page_background'))
            .borderRadius(18)
            .border({ width: 1, color: $r('app.color.border_color') })
            .onClick(() => {
              this.playing = !this.playing;
              this.syncPreviewTimer();
            })
          Column({ space: 2 }) {
            Text(`${(this.previewPos % this.displayOrder().length) + 1}/${this.displayOrder().length}`)
              .fontSize(13)
              .fontColor($r('app.color.primary_text'))
            Text(`实际帧间隔 ${(this.currentPreviewIntervalMs() / 1000).toFixed(2)}s · 输出 ${this.outputCanvasSize()[0]}×${this.outputCanvasSize()[1]}`)
              .fontSize(11)
              .fontColor($r('app.color.tertiary_text'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (this.overlays.length > 0) {
            Text(`贴纸 ${this.overlays.length}`)
              .fontSize(11)
              .fontColor($r('app.color.tertiary_text'))
          }
        }
        .width('100%')
      }
      .width('100%')
      .onAreaChange((oldArea: Area, newArea: Area) => {
        let w: number = Number(newArea.width);
        if (!isNaN(w) && w > 0) {
          this.previewBoxAvailW = w;
          this.syncPreviewBox();
        }
      })
    }
  }

  @Builder
  AddFrameTile() {
    Column({ space: 4 }) {
      Text('＋')
        .fontSize(22)
        .fontColor($r('app.color.tertiary_text'))
        .width(64)
        .height(64)
        .textAlign(TextAlign.Center)
        .backgroundColor($r('app.color.page_background'))
        .borderRadius(10)
        .border({ width: 1, color: $r('app.color.border_color') })
    }
    .onClick(() => {
      this.pickImages();
    })
  }

  @Builder
  FrameStrip() {
    Column({ space: 10 }) {
      List({ space: 8 }) {
        ForEach(this.frames, (item: GifFrameItem, index: number) => {
          ListItem() {
            this.FrameThumb(item, index)
          }
        }, (item: GifFrameItem, index: number) => item.uri + '_' + index.toString() + '_' + item.rotation.toString())
        if (this.frames.length < MAX_FRAMES) {
          ListItem() {
            this.AddFrameTile()
          }
        }
      }
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .onItemDragStart((event: ItemDragInfo, index: number): CustomBuilder => {
        if (index < 0 || index >= this.frames.length) {
          return () => {
          };
        }
        let dragged: GifFrameItem = this.frames[index];
        return () => {
          this.FrameThumb(dragged, index);
        };
      })
      .onItemMove((from: number, to: number): boolean => {
        if (from < 0 || from >= this.frames.length || to < 0 || to >= this.frames.length) {
          return false;
        }
        if (from === to) {
          return true;
        }
        let moved: GifFrameItem = this.frames[from];
        this.frames.splice(from, 1);
        this.frames.splice(to, 0, moved);
        if (this.selectedFrameIndex === from) {
          this.selectedFrameIndex = to;
        } else if (from < this.selectedFrameIndex && to >= this.selectedFrameIndex) {
          this.selectedFrameIndex--;
        } else if (from > this.selectedFrameIndex && to <= this.selectedFrameIndex) {
          this.selectedFrameIndex++;
        }
        this.onFramesChanged();
        return true;
      })

      Flex({ wrap: FlexWrap.Wrap }) {
        this.FrameOpsButton('左移', () => {
          this.moveSelectedFrame(-1);
        })
        this.FrameOpsButton('右移', () => {
          this.moveSelectedFrame(1);
        })
        this.FrameOpsButton('倒序', () => {
          this.reverseFrames();
        })
        this.FrameOpsButton('旋转', () => {
          this.rotateSelectedFrame();
        })
        this.FrameOpsButton('删除', () => {
          this.deleteSelectedFrame();
        })
        Text(`已选 ${this.frames.length}/${MAX_FRAMES} · 长按可拖拽排序`)
          .fontSize(11)
          .fontColor($r('app.color.tertiary_text'))
          .margin({ left: 4, right: 8, bottom: 8 })
      }
      .width('100%')

      if (this.selectedFrameIndex >= 0 && this.selectedFrameIndex < this.frames.length) {
        Row({ space: 8 }) {
          Text(`第 ${this.selectedFrameIndex + 1} 帧`)
            .fontSize(12)
            .fontColor($r('app.color.tertiary_text'))
          TextInput({ text: this.perFrameDurationInput, placeholder: '单帧时长(秒)，留空跟随全局' })
            .fontSize(13)
            .height(34)
            .layoutWeight(1)
            .padding({ left: 8, right: 8 })
            .borderRadius(8)
            .onChange((value: string) => {
              this.perFrameDurationInput = value;
            })
            .onSubmit(() => {
              this.applyPerFrameDuration();
            })
            .onBlur(() => {
              this.applyPerFrameDuration();
            })
          this.FrameOpsButton('恢复全局', () => {
            this.clearPerFrameDuration();
          })
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  OverlayArea() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        TextInput({ text: this.overlayTextInput, placeholder: '输入文字内容' })
          .fontSize(13)
          .height(36)
          .layoutWeight(1)
          .padding({ left: 8, right: 8 })
          .borderRadius(8)
          .onChange((value: string) => {
            this.overlayTextInput = value;
          })
          .onSubmit(() => {
            this.addTextOverlay();
          })
        Button('添加文字')
          .fontSize(13)
          .height(36)
          .padding({ left: 12, right: 12 })
          .backgroundColor($r('app.color.idiom_blue'))
          .onClick(() => {
            this.addTextOverlay();
          })
      }
      .width('100%')

      Column({ space: 8 }) {
        this.OptionChips(STICKER_CATEGORIES, this.stickerCategoryIndex, (index: number) => {
          this.stickerCategoryIndex = index;
        })
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(STICKER_SETS[this.stickerCategoryIndex], (sticker: string) => {
            Text(sticker)
              .fontSize(24)
              .width(44)
              .height(44)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.addStickerOverlay(sticker);
              })
          }, (sticker: string) => sticker)
        }
        .width('100%')
      }

      if (this.overlays.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.overlays, (item: OverlayItem, index: number) => {
            Text(item.kind === OVERLAY_KIND_TEXT ? '✍️ ' + item.text : item.text)
              .fontSize(13)
              .fontColor(item.id === this.selectedOverlayId ? Color.White : $r('app.color.secondary_text'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 160 })
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(item.id === this.selectedOverlayId ? $r('app.color.idiom_blue') : $r('app.color.page_background'))
              .borderRadius(14)
              .border({
                width: 1,
                color: item.id === this.selectedOverlayId ? $r('app.color.idiom_blue') : $r('app.color.border_color')
              })
              .margin({ right: 8, bottom: 8 })
              .onClick(() => {
                this.selectedOverlayId = this.selectedOverlayId === item.id ? '' : item.id;
              })
          }, (item: OverlayItem) => item.id + '_' + item.text + '_' + (item.id === this.selectedOverlayId ? '1' : '0'))
        }
        .width('100%')
      }

      if (this.selectedOverlay() !== null) {
        this.OverlayEditor()
      }

      Text(this.overlays.length > 0
        ? '拖动调整位置，双指捏合缩放旋转；叠加层应用于全部帧'
        : '添加的文字与贴纸将叠加在所有帧上')
        .fontSize(11)
        .fontColor($r('app.color.tertiary_text'))
    }
    .width('100%')
  }

  @Builder
  OverlayEditor() {
    Column({ space: 10 }) {
      if (this.selectedOverlay()!.kind === OVERLAY_KIND_TEXT) {
        Row({ space: 8 }) {
          Text('内容')
            .fontSize(12)
            .fontColor($r('app.color.tertiary_text'))
          TextInput({ text: this.selectedOverlay()!.text })
            .fontSize(13)
            .height(34)
            .layoutWeight(1)
            .padding({ left: 8, right: 8 })
            .borderRadius(8)
            .onChange((value: string) => {
              this.applyOverlayText(value);
            })
        }
        .width('100%')

        Column({ space: 6 }) {
          this.ParamLabel('文字颜色')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(OVERLAY_COLORS, (color: string) => {
              Text('字')
                .fontSize(13)
                .fontColor(color)
                .width(32)
                .height(32)
                .textAlign(TextAlign.Center)
                .backgroundColor($r('app.color.page_background'))
                .borderRadius(16)
                .border({
                  width: this.selectedOverlay()!.color === color ? 2 : 1,
                  color: this.selectedOverlay()!.color === color ? $r('app.color.idiom_blue') : $r('app.color.border_color')
                })
                .margin({ right: 8, bottom: 8 })
                .onClick(() => {
                  this.applyOverlayColor(color);
                })
            }, (color: string) => color + '_' + this.selectedOverlay()!.color)
            Row({ space: 6 }) {
              TextInput({ text: this.customColorInput, placeholder: '#RRGGBB' })
                .fontSize(12)
                .width(96)
                .height(32)
                .padding({ left: 6, right: 6 })
                .borderRadius(8)
                .onChange((value: string) => {
                  this.customColorInput = value;
                })
              this.FrameOpsButton('自定义', () => {
                this.applyCustomColor();
              })
            }
            .margin({ bottom: 8 })
          }
          .width('100%')
        }
      }

      Column({ space: 6 }) {
        this.ParamLabel(`大小（${this.selectedOverlay()!.fontPx}）`)
        Slider({
          value: this.selectedOverlay()!.fontPx,
          min: 12,
          max: this.selectedFontMax(),
          step: 1
        })
          .selectedColor($r('app.color.idiom_blue'))
          .width('100%')
          .onChange((value: number) => {
            this.applyOverlayFont(Math.round(value));
          })
      }

      Row({ space: 8 }) {
        Text('旋转')
          .fontSize(12)
          .fontColor($r('app.color.tertiary_text'))
        this.FrameOpsButton('-15°', () => {
          this.nudgeSelectedRotation(-15);
        })
        Text(`${Math.round(this.selectedOverlay()!.rotation)}°`)
          .fontSize(13)
          .fontColor($r('app.color.primary_text'))
        this.FrameOpsButton('+15°', () => {
          this.nudgeSelectedRotation(15);
        })
      }

      Button('删除该叠加层')
        .fontSize(13)
        .height(34)
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .fontColor($r('app.color.danger_red'))
        .border({ width: 1, color: $r('app.color.danger_red') })
        .onClick(() => {
          this.deleteSelectedOverlay();
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.page_background'))
    .borderRadius(12)
  }

  @Builder
  ParamsArea() {
    Column({ space: 14 }) {
      Column({ space: 6 }) {
        this.ParamLabel('帧时长（秒）')
        Row({ space: 10 }) {
          Slider({
            value: this.frameDurationMs,
            min: 50,
            step: 50,
            max: 2000
          })
            .selectedColor($r('app.color.idiom_blue'))
            .layoutWeight(1)
            .onChange((value: number) => {
              let ms: number = Math.round(value / 50) * 50;
              if (ms !== this.frameDurationMs) {
                this.frameDurationMs = ms;
                this.durationInput = (ms / 1000).toFixed(2);
                this.syncPreviewTimer();
              }
            })
          TextInput({ text: this.durationInput })
            .fontSize(13)
            .width(64)
            .height(34)
            .padding({ left: 6, right: 6 })
            .borderRadius(8)
            .onChange((value: string) => {
              this.durationInput = value;
            })
            .onSubmit(() => {
              this.applyDurationInput();
            })
            .onBlur(() => {
              this.applyDurationInput();
            })
        }
        .width('100%')
      }

      Column({ space: 6 }) {
        this.ParamLabel('倍速（与帧时长叠加生效）')
        this.OptionChips(SPEED_LABELS, this.speedIndex, (index: number) => {
          this.speedIndex = index;
          this.syncPreviewTimer();
        })
      }

      Column({ space: 6 }) {
        this.ParamLabel('播放模式')
        this.OptionChips(PLAY_MODE_LABELS, this.playModeIndex, (index: number) => {
          this.playModeIndex = index;
          this.previewPos = 0;
          this.onFramesChanged();
        })
      }

      Column({ space: 6 }) {
        this.ParamLabel('循环播放')
        this.OptionChips(LOOP_LABELS, this.loopIndex, (index: number) => {
          this.loopIndex = index;
        })
      }

      Column({ space: 6 }) {
        this.ParamLabel('输出尺寸')
        this.OptionChips(SIZE_LABELS, this.sizeIndex, (index: number) => {
          this.sizeIndex = index;
          this.syncPreviewBox();
        })
      }

      Column({ space: 6 }) {
        this.ParamLabel('画质')
        this.OptionChips(QUALITY_LABELS, this.qualityIndex, (index: number) => {
          this.qualityIndex = index;
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ExportPanel() {
    Column({ space: 14 }) {
      Button(this.exporting ? '取消' : '生成 GIF')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .height(46)
        .backgroundColor(this.exporting ? $r('app.color.danger_red') : $r('app.color.idiom_blue'))
        .enabled(this.frames.length >= MIN_FRAMES || this.exporting)
        .opacity(this.frames.length >= MIN_FRAMES || this.exporting ? 1 : 0.5)
        .onClick(() => {
          if (this.exporting) {
            this.cancelExport();
          } else {
            this.startExport();
          }
        })
      if (this.exporting) {
        Column({ space: 8 }) {
          Progress({ value: this.exportProgress, total: 100, type: ProgressType.Linear })
            .color($r('app.color.idiom_blue'))
            .width('100%')
          Text(this.exportPhase)
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  ResultView() {
    Column({ space: 14 }) {
      GifSectionCard({ title: '生成结果' }) {
        Column({ space: 12 }) {
          Image(fileUri.getUriFromPath(this.exportedPath))
            .width('100%')
            .height(220)
            .objectFit(ImageFit.Contain)
            .borderRadius(10)
            .backgroundColor($r('app.color.page_background'))
          Text(`${this.exportedWidth}×${this.exportedHeight} · ${this.displayOrder().length} 帧 · ${this.formatBytes(this.exportedSize)}`)
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
        }
        .width('100%')
      }

      Row({ space: 10 }) {
        Button('保存到相册')
          .fontSize(14)
          .layoutWeight(1)
          .height(42)
          .backgroundColor($r('app.color.idiom_blue'))
          .onClick(() => {
            this.saveToAlbum();
          })
        Button('分享')
          .fontSize(14)
          .layoutWeight(1)
          .height(42)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.idiom_blue'))
          .border({ width: 1, color: $r('app.color.idiom_blue') })
          .onClick(() => {
            this.shareGif();
          })
      }
      .width('100%')

      Button('返回编辑')
        .fontSize(14)
        .width('100%')
        .height(42)
        .backgroundColor($r('app.color.card_background'))
        .fontColor($r('app.color.secondary_text'))
        .border({ width: 1, color: $r('app.color.border_color') })
        .onClick(() => {
          this.viewMode = 'edit';
          this.syncPreviewTimer();
        })
    }
    .width('100%')
  }

  @Builder
  HistoryRecordCard(record: GifHistoryRecord) {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Image(fileUri.getUriFromPath(GifHistoryStore.recordFilePath(this.getUIContext().getHostContext() as common.UIAbilityContext, record)))
          .width(96)
          .height(72)
          .objectFit(ImageFit.Cover)
          .borderRadius(8)
          .backgroundColor($r('app.color.page_background'))
        Column({ space: 3 }) {
          Text(`${record.width}×${record.height} · ${record.frameCount} 帧 · ${formatGifBytes(record.sizeBytes)}`)
            .fontSize(13)
            .fontColor($r('app.color.primary_text'))
          Text(record.paramsText)
            .fontSize(11)
            .fontColor($r('app.color.secondary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.formatTimestamp(record.exportedAt))
            .fontSize(11)
            .fontColor($r('app.color.tertiary_text'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      Row({ space: 8 }) {
        Button('预览')
          .fontSize(12)
          .height(32)
          .layoutWeight(1)
          .backgroundColor($r('app.color.idiom_blue'))
          .onClick(() => {
            let context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
            this.historyPreviewPath = GifHistoryStore.recordFilePath(context, record);
            this.viewMode = 'historyPreview';
          })
        Button('保存')
          .fontSize(12)
          .height(32)
          .layoutWeight(1)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.idiom_blue'))
          .border({ width: 1, color: $r('app.color.idiom_blue') })
          .onClick(() => {
            let context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
            this.saveGifPathToAlbum(GifHistoryStore.recordFilePath(context, record));
          })
        Button('分享')
          .fontSize(12)
          .height(32)
          .layoutWeight(1)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.idiom_blue'))
          .border({ width: 1, color: $r('app.color.idiom_blue') })
          .onClick(() => {
            let context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
            shareGifViaPanel(this.getUIContext(), GifHistoryStore.recordFilePath(context, record));
          })
        Button('删除')
          .fontSize(12)
          .height(32)
          .layoutWeight(1)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.danger_red'))
          .border({ width: 1, color: $r('app.color.danger_red') })
          .onClick(() => {
            this.deleteHistoryRecord(record);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
  }

  @Builder
  HistoryView() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text(`共 ${this.historyRecords.length} 条 · 占用 ${formatGifBytes(this.historyBytes)}`)
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
          .layoutWeight(1)
        if (this.historyRecords.length > 0) {
          Button('清空全部')
            .fontSize(12)
            .height(30)
            .padding({ left: 10, right: 10 })
            .backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.danger_red'))
            .border({ width: 1, color: $r('app.color.danger_red') })
            .onClick(() => {
              this.clearHistoryAll();
            })
        }
      }
      .width('100%')

      if (this.historyRecords.length === 0) {
        Column({ space: 10 }) {
          Text('🕘')
            .fontSize(40)
          Text('暂无制作历史')
            .fontSize(14)
            .fontColor($r('app.color.secondary_text'))
          Text('导出的成品 GIF 会自动保存在这里（沙箱内，最多保留 50 条）')
            .fontSize(11)
            .fontColor($r('app.color.tertiary_text'))
        }
        .width('100%')
        .padding({ top: 48, bottom: 48 })
      } else {
        ForEach(this.historyRecords, (record: GifHistoryRecord) => {
          this.HistoryRecordCard(record)
        }, (record: GifHistoryRecord) => record.id + '_' + record.sizeBytes.toString())
      }

      Button('返回')
        .fontSize(14)
        .width('100%')
        .height(42)
        .backgroundColor($r('app.color.card_background'))
        .fontColor($r('app.color.secondary_text'))
        .border({ width: 1, color: $r('app.color.border_color') })
        .onClick(() => {
          this.viewMode = 'select';
          this.refreshHistory();
        })
    }
    .width('100%')
  }

  @Builder
  HistoryPreviewView() {
    Column({ space: 14 }) {
      Image(fileUri.getUriFromPath(this.historyPreviewPath))
        .width('100%')
        .objectFit(ImageFit.Contain)
        .borderRadius(10)
        .backgroundColor($r('app.color.page_background'))
        .layoutWeight(1)
      Button('返回')
        .fontSize(14)
        .width('100%')
        .height(42)
        .backgroundColor($r('app.color.card_background'))
        .fontColor($r('app.color.secondary_text'))
        .border({ width: 1, color: $r('app.color.border_color') })
        .onClick(() => {
          this.viewMode = 'history';
        })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Column() {
      if (this.exporting) {
        Column({ space: 16 }) {
          Text('⏳')
            .fontSize(40)
          Text('正在生成 GIF')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
          Progress({ value: this.exportProgress, total: 100, type: ProgressType.Linear })
            .color($r('app.color.idiom_blue'))
            .width('70%')
          Text(`${this.exportPhase}  ${this.exportProgress}%`)
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
          Button('取消')
            .fontSize(14)
            .height(36)
            .backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.danger_red'))
            .border({ width: 1, color: $r('app.color.danger_red') })
            .onClick(() => {
              this.cancelExport();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.viewMode === 'select') {
        Column() {
          Scroll() {
            Column() {
              this.SelectView()
            }
            .padding(16)
          }
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
          .width('100%')
          .layoutWeight(1)
        }
        .width('100%')
        .layoutWeight(1)
      } else if (this.viewMode === 'videoConfig') {
        Column() {
          Scroll() {
            Column() {
              this.VideoConfigView()
            }
            .padding(16)
          }
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
          .width('100%')
          .layoutWeight(1)
        }
        .width('100%')
        .layoutWeight(1)
      } else if (this.viewMode === 'result') {
        Column() {
          Scroll() {
            Column() {
              this.ResultView()
            }
            .padding(16)
          }
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
          .width('100%')
          .layoutWeight(1)
        }
        .width('100%')
        .layoutWeight(1)
      } else if (this.viewMode === 'history') {
        Column() {
          Scroll() {
            Column() {
              this.HistoryView()
            }
            .padding(16)
          }
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
          .width('100%')
          .layoutWeight(1)
        }
        .width('100%')
        .layoutWeight(1)
      } else if (this.viewMode === 'historyPreview') {
        Column() {
          this.HistoryPreviewView()
        }
        .padding(16)
        .width('100%')
        .layoutWeight(1)
      } else {
        Column() {
          Scroll() {
            Column({ space: 12 }) {
              GifSectionCard({ title: '预览' }) {
                this.PreviewArea()
              }
              GifSectionCard({ title: '帧管理（点选缩略图后可调整）' }) {
                this.FrameStrip()
              }
              GifSectionCard({ title: '贴纸与文字' }) {
                this.OverlayArea()
              }
              GifSectionCard({ title: '参数' }) {
                this.ParamsArea()
              }
              this.ExportPanel()
            }
            .padding(16)
          }
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
          .width('100%')
          .layoutWeight(1)
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
