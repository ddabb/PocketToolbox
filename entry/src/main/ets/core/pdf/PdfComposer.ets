/**
 * PDF 合成核心（1.4.5 P0-1：图片合成 PDF）
 *
 * 链路已在 Phase 0 真机验证（docs/1.4.5开发计划_PDF工具.md §9）：
 *   new PdfDocument() → createDocument(w,h) → insertBlankPage(inserted,w,h)
 *   → addImageObject(sandboxPath,x,y,w,h) → deletePage(inserted,1) → saveDocument → releaseDocument
 *
 * 关键实证（2026-10-13 Mate 60 Pro）：
 *   1. createDocument(w,h) 会自带一张初始空页；
 *   2. insertBlankPage 是「在 index 处插入」，初始页被顶到页序末尾（index=inserted），
 *      deletePage(0,1) 会误删第一张图片页——必须 deletePage(inserted, 1)；
 *   3. addImageObject 直传相册媒体 URI（file://media/...）会静默不绘制，页面全空白
 *      （1.4.5 首轮真机验证发现：PDF 可生成但内容为空白页）——必须先 fs.openSync(uri)
 *      拷贝到应用沙箱，再传沙箱路径（官方 PhotoViewPicker + PDFKit 案例流程）。
 */
import { pdfService } from '@kit.PDFKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** A4 短边（pt）。PDF 单位 72dpi，1 英寸 = 72pt */
export const A4_SHORT_PT: number = 595;
/** A4 长边（pt） */
export const A4_LONG_PT: number = 842;

/** 页面尺寸模式 */
export enum PdfPageMode {
  /** 每页尺寸 = 图片尺寸，无白边（扫描件场景，默认） */
  FIT = 0,
  /** A4 白底，图片等比内缩居中 */
  A4 = 1,
}

/** A4 模式边距档位 */
export enum PdfMarginMode {
  NONE = 0,
  NARROW = 1,
  NORMAL = 2,
}

/** A4 模式页面方向 */
export enum PdfOrientation {
  /** 按首图横竖自动选 A4 横/纵 */
  AUTO = 0,
  /** 强制 A4 纵向 */
  PORTRAIT = 1,
}

/** 待合成图片：uri + 预读像素尺寸 */
export class ComposeImage {
  uri: string;
  widthPx: number;
  heightPx: number;

  constructor(uri: string, widthPx: number, heightPx: number) {
    this.uri = uri;
    this.widthPx = widthPx;
    this.heightPx = heightPx;
  }
}

/** 合成结果。ok=false 时 errMsg 为失败原因（英文短码，由页面转文案） */
export class ComposeResult {
  ok: boolean = false;
  path: string = '';
  pages: number = 0;
  bytes: number = 0;
  errMsg: string = '';
}

export class PdfComposer {
  /** px → pt（ImageKit 像素 96dpi → PDF 点 72dpi） */
  static pxToPt(px: number): number {
    return px * 72 / 96;
  }

  /** 边距档位 → pt */
  static marginPt(mode: PdfMarginMode): number {
    if (mode === PdfMarginMode.NARROW) {
      return 12;
    }
    if (mode === PdfMarginMode.NORMAL) {
      return 24;
    }
    return 0;
  }

  /** 读取图片像素尺寸（px）。失败返回 [0,0] */
  static async queryImageSize(uri: string): Promise<number[]> {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      let source: image.ImageSource = image.createImageSource(file.fd);
      let info: image.ImageInfo = await source.getImageInfo();
      source.release();
      return [info.size.width, info.size.height];
    } catch (e) {
      console.error('[PdfComposer] queryImageSize failed: ' + (e as BusinessError).message);
      return [0, 0];
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (closeErr) {
          console.error('[PdfComposer] close fd failed: ' + (closeErr as BusinessError).message);
        }
      }
    }
  }

  /** 取 uri 后缀（含点）；无有效后缀返回 .img */
  private static extOf(uri: string): string {
    let dot: number = uri.lastIndexOf('.');
    if (dot < 0 || dot < uri.lastIndexOf('/')) {
      return '.img';
    }
    return uri.substring(dot);
  }

  /** 删除沙箱临时目录（目录内平铺文件 + 目录本身），不存在则忽略 */
  private static removeTree(dir: string): void {
    try {
      if (!fs.accessSync(dir)) {
        return;
      }
      let names: string[] = fs.listFileSync(dir);
      for (let i = 0; i < names.length; i++) {
        fs.unlinkSync(dir + '/' + names[i]);
      }
      fs.rmdirSync(dir);
    } catch (e) {
      console.warn('[PdfComposer] removeTree failed: ' + (e as BusinessError).message);
    }
  }

  /**
   * 合成主流程。images 顺序即页序；outPath 为沙箱输出路径（.pdf 结尾）。
   * FIT 模式 margin/orientation 不生效；A4 模式 AUTO 方向按首图横竖判定。
   * 相册 URI 图片先拷贝到 outPath 同级 pdftool_tmp 目录再喂给 addImageObject，
   * 合成结束（含失败路径）自动清理。
   */
  static async compose(images: ComposeImage[], pageMode: PdfPageMode, margin: PdfMarginMode,
    orientation: PdfOrientation, outPath: string): Promise<ComposeResult> {
    let result: ComposeResult = new ComposeResult();
    if (images.length === 0) {
      result.errMsg = 'empty';
      return result;
    }
    let slash: number = outPath.lastIndexOf('/');
    if (slash < 0) {
      result.errMsg = 'path';
      return result;
    }
    let doc: pdfService.PdfDocument = new pdfService.PdfDocument();
    let created: boolean = doc.createDocument(A4_SHORT_PT, A4_LONG_PT);
    if (!created) {
      result.errMsg = 'create';
      return result;
    }
    let tmpDir: string = outPath.substring(0, slash) + '/pdftool_tmp';
    PdfComposer.removeTree(tmpDir);
    let tmpReady: boolean = true;
    try {
      fs.mkdirSync(tmpDir, true);
    } catch (e) {
      console.error('[PdfComposer] mkdir tmp failed: ' + (e as BusinessError).message);
      tmpReady = false;
    }
    if (!tmpReady) {
      result.errMsg = 'tmp';
      doc.releaseDocument();
      return result;
    }
    try {
      let marginPt: number = pageMode === PdfPageMode.FIT ? 0 : PdfComposer.marginPt(margin);
      let a4Landscape: boolean = false;
      if (pageMode === PdfPageMode.A4 && orientation === PdfOrientation.AUTO) {
        a4Landscape = images[0].widthPx > images[0].heightPx;
      }
      let baseW: number = a4Landscape ? A4_LONG_PT : A4_SHORT_PT;
      let baseH: number = a4Landscape ? A4_SHORT_PT : A4_LONG_PT;
      let inserted: number = 0;
      for (let i = 0; i < images.length; i++) {
        let img: ComposeImage = images[i];
        let pageW: number = pageMode === PdfPageMode.FIT ? PdfComposer.pxToPt(img.widthPx) : baseW;
        let pageH: number = pageMode === PdfPageMode.FIT ? PdfComposer.pxToPt(img.heightPx) : baseH;
        if (pageW <= 0 || pageH <= 0) {
          continue;
        }
        // 相册 URI 直传 addImageObject 会静默不绘制（空白页），必须先拷贝到沙箱
        let tmpPath: string = tmpDir + '/img_' + i + PdfComposer.extOf(img.uri);
        try {
          let srcFile: fs.File = fs.openSync(img.uri, fs.OpenMode.READ_ONLY);
          try {
            fs.copyFileSync(srcFile.fd, tmpPath);
          } finally {
            fs.closeSync(srcFile);
          }
        } catch (e) {
          console.error('[PdfComposer] copy image failed: ' + (e as BusinessError).message);
          result.errMsg = 'copy';
          return result;
        }
        let page: pdfService.PdfPage = doc.insertBlankPage(inserted, pageW, pageH);
        if (page === null) {
          continue;
        }
        inserted++;
        let drawW: number = pageW - marginPt * 2;
        let drawH: number = pageH - marginPt * 2;
        let x: number = marginPt;
        let y: number = marginPt;
        if (pageMode === PdfPageMode.A4) {
          let imgWpt: number = PdfComposer.pxToPt(img.widthPx);
          let imgHpt: number = PdfComposer.pxToPt(img.heightPx);
          let scale: number = Math.min(drawW / imgWpt, drawH / imgHpt);
          drawW = imgWpt * scale;
          drawH = imgHpt * scale;
          x = (pageW - drawW) / 2;
          y = (pageH - drawH) / 2;
        }
        page.addImageObject(tmpPath, x, y, drawW, drawH);
      }
      if (inserted === 0) {
        result.errMsg = 'nopage';
        return result;
      }
      // 初始空页被 insertBlankPage 顶到末尾（真机实证），删末尾这张
      let total: number = doc.getPageCount();
      if (total === inserted + 1) {
        doc.deletePage(inserted, 1);
      } else {
        console.warn('[PdfComposer] page count abnormal total=' + total + ' inserted=' + inserted);
      }
      let saved: boolean = doc.saveDocument(outPath);
      if (!saved) {
        result.errMsg = 'save';
        return result;
      }
      result.ok = true;
      result.path = outPath;
      result.pages = inserted;
      result.bytes = fs.statSync(outPath).size;
    } finally {
      doc.releaseDocument();
      PdfComposer.removeTree(tmpDir);
    }
    return result;
  }
}
