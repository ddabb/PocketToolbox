/**
 * PDF 拆分核心（1.4.5 P0-2：PDF 拆分为图片）
 *
 * 链路已在 Phase 0 真机验证（docs/1.4.5开发计划_PDF工具.md §9）：
 *   new PdfDocument() → loadDocument(path, password) → getPageCount()
 *   → 逐页 getPage i → getPagePixelMap → ImagePacker.packToFile → page.release
 *
 * 约束：
 *   - loadDocument 同一 doc 不可重复调用；每次操作 new 新 doc，用完 releaseDocument；
 *   - PixelMap 用完即 release，>50 页由页面层提示分批导出（内存保护）；
 *   - 加密 PDF 走 loadDocument password 参数，PARSE_ERROR_PASSWORD 时回传「需要密码」。
 */
import { pdfService } from '@kit.PDFKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** 导出格式 */
export enum SplitFormat {
  JPEG = 0,
  PNG = 1,
}

/** 单页缩略图：页码（0 基）+ 缩略图文件路径 */
export class PdfThumb {
  index: number;
  path: string;

  constructor(index: number, path: string) {
    this.index = index;
    this.path = path;
  }
}

/** 打开结果。needPassword=true 表示需密码重试；parseErr 为 ParseResult 枚举值（0 成功） */
export class SplitOpenResult {
  ok: boolean = false;
  needPassword: boolean = false;
  parseErr: number = -1;
  pageCount: number = 0;
  thumbs: PdfThumb[] = [];
}

/** 导出结果 */
export class SplitExportResult {
  ok: boolean = false;
  paths: string[] = [];
  errMsg: string = '';
}

export class PdfSplitter {
  /**
   * 打开 PDF 并逐页渲染缩略图（JPEG 质量低、仅用于页列表辨识）。
   * onProgress(done,total) 每页回调，用于页面层进度展示。
   * thumbDir 为缩略图输出目录（沙箱），建议独立子目录便于整批清理。
   */
  static async openThumbs(srcPath: string, password: string, thumbDir: string,
    onProgress: (done: number, total: number) => void): Promise<SplitOpenResult> {
    let result: SplitOpenResult = new SplitOpenResult();
    let doc: pdfService.PdfDocument = new pdfService.PdfDocument();
    try {
      let parse: pdfService.ParseResult = doc.loadDocument(srcPath, password);
      if (parse !== pdfService.ParseResult.PARSE_SUCCESS) {
        result.parseErr = parse as number;
        result.needPassword = parse === pdfService.ParseResult.PARSE_ERROR_PASSWORD;
        return result;
      }
      let count: number = doc.getPageCount();
      if (count <= 0) {
        result.parseErr = -2;
        return result;
      }
      result.pageCount = count;
      PdfSplitter.ensureDir(thumbDir);
      let thumbs: PdfThumb[] = [];
      for (let i = 0; i < count; i++) {
        let page: pdfService.PdfPage | null = doc.getPage(i);
        if (page === null) {
          onProgress(i + 1, count);
          continue;
        }
        let pm: image.PixelMap | null = page.getPagePixelMap();
        if (pm !== null) {
          let path: string = thumbDir + '/thumb_' + i + '.jpg';
          await PdfSplitter.packToFile(pm, path, SplitFormat.JPEG, 70);
          thumbs.push(new PdfThumb(i, path));
          pm.release();
        }
        page.release();
        onProgress(i + 1, count);
      }
      if (thumbs.length === 0) {
        result.parseErr = -3;
        return result;
      }
      result.thumbs = thumbs;
      result.ok = true;
    } finally {
      doc.releaseDocument();
    }
    return result;
  }

  /**
   * 导出选中页。pageIndexes 为 0 基页码数组；namePrefix 通常为原文件名（去后缀），
   * 输出文件名 namePrefix_p{页码1基}.jpg/.png；JPEG 质量 60-100，PNG 忽略质量参数。
   */
  static async exportPages(srcPath: string, password: string, pageIndexes: number[],
    format: SplitFormat, quality: number, outDir: string, namePrefix: string,
    onProgress: (done: number, total: number) => void): Promise<SplitExportResult> {
    let result: SplitExportResult = new SplitExportResult();
    if (pageIndexes.length === 0) {
      result.errMsg = 'empty';
      return result;
    }
    let doc: pdfService.PdfDocument = new pdfService.PdfDocument();
    try {
      let parse: pdfService.ParseResult = doc.loadDocument(srcPath, password);
      if (parse !== pdfService.ParseResult.PARSE_SUCCESS) {
        result.errMsg = 'parse_' + (parse as number).toString();
        return result;
      }
      PdfSplitter.ensureDir(outDir);
      let ext: string = format === SplitFormat.PNG ? 'png' : 'jpg';
      let paths: string[] = [];
      for (let n = 0; n < pageIndexes.length; n++) {
        let idx: number = pageIndexes[n];
        let page: pdfService.PdfPage | null = doc.getPage(idx);
        if (page === null) {
          onProgress(n + 1, pageIndexes.length);
          continue;
        }
        let pm: image.PixelMap | null = page.getPagePixelMap();
        if (pm !== null) {
          let path: string = outDir + '/' + namePrefix + '_p' + (idx + 1) + '.' + ext;
          await PdfSplitter.packToFile(pm, path, format, quality);
          paths.push(path);
          pm.release();
        }
        page.release();
        onProgress(n + 1, pageIndexes.length);
      }
      if (paths.length === 0) {
        result.errMsg = 'nopage';
        return result;
      }
      result.paths = paths;
      result.ok = true;
    } finally {
      doc.releaseDocument();
    }
    return result;
  }

  /** PixelMap 打包落盘（fd 直写，不经 ArrayBuffer 中转） */
  static async packToFile(pm: image.PixelMap, path: string, format: SplitFormat,
    quality: number): Promise<void> {
    let file: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    let packer: image.ImagePacker = image.createImagePacker();
    try {
      let opts: image.PackingOption = {
        format: format === SplitFormat.PNG ? 'image/png' : 'image/jpeg',
        quality: quality
      };
      await packer.packToFile(pm, file.fd, opts);
    } finally {
      try {
        fs.closeSync(file);
      } catch (closeErr) {
        console.error('[PdfSplitter] close fd failed: ' + (closeErr as BusinessError).message);
      }
      packer.release();
    }
  }

  /** 确保目录存在（存在则跳过） */
  static ensureDir(dir: string): void {
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir, true);
    }
  }
}
