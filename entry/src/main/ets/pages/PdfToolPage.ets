/**
 * PDF 工具正式页（1.4.5 P0-1 / P0-2）
 *
 * 单页双 Tab「合成 / 拆分」：
 *  - 合成：PhotoViewPicker 多选（≤20 张）→ 点击两张缩略图交换顺序 / 单张删除 →
 *          页面模式（适应图片 / A4 白底）→ A4 边距（无/窄/常规）与方向（自动/纵向）→
 *          文件名（默认 PDF_yyyyMMdd_HHmm 可编辑）→ 生成 → 结果页（页数/体积）→
 *          系统保存器（DocumentViewPicker.save）/ 系统分享（ShareKit）双通道
 *  - 拆分：DocumentViewPicker 选 PDF → 拷贝沙箱 → loadDocument（加密走密码）→
 *          页缩略图列表（默认全选 / 单选切换 / 全选/清空）→
 *          格式（JPEG 质量 60-100 滑杆，默认 90 / PNG）→ 导出（相册保存对话框，多张）
 *
 * P1-3 历史 / P1-4 生成结果预览为后续待办（见计划 §2）。
 */
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { ToastUtil } from '../common/utils/ToastUtil';
import { PdfComposer, PdfPageMode, PdfMarginMode, PdfOrientation, ComposeImage, ComposeResult }
  from '../core/pdf/PdfComposer';
import { PdfSplitter, PdfThumb, SplitFormat } from '../core/pdf/PdfSplitter';

const TAG: string = '[PdfTool]';
/** 单次合成最多图片数 */
const MAX_IMAGES: number = 100;
/** 建议分批导出的页数阈值（内存保护） */
const MAX_PAGES_HINT: number = 50;

/** ParseResult 枚举值（@kit.PDFKit，页面层避免直接依赖 pdfService） */
const PARSE_ERR_FILE: number = 1;
const PARSE_ERR_FORMAT: number = 2;
const PARSE_ERR_PASSWORD: number = 3;
/** PdfSplitter 自定义错误：无可读页面 */
const PARSE_ERR_NOPAGE: number = -2;
const PARSE_ERR_NOTHUMB: number = -3;

@Builder
export function PdfToolPageBuilder() {
  NavDestination() {
    PdfToolPanel()
  }
  .title($r('app.string.pdf_tool_title'))
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct PdfToolPanel {
  @State activeTab: number = 0;

  // ---------- 合成 ----------
  @State composeImages: ComposeImage[] = [];
  @State pageMode: PdfPageMode = PdfPageMode.FIT;
  @State marginMode: PdfMarginMode = PdfMarginMode.NORMAL;
  @State orientMode: PdfOrientation = PdfOrientation.AUTO;
  @State fileName: string = '';
  @State composing: boolean = false;
  @State composeResult: ComposeResult | null = null;
  @State composeFailMsg: string = '';
  /** 交换排序：点击的第一张缩略图下标，-1 未开始 */
  @State swapIndex: number = -1;
  @State savingPdf: boolean = false;

  // ---------- 拆分 ----------
  @State splitPath: string = '';
  @State splitName: string = '';
  @State splitSize: number = 0;
  @State splitPwd: string = '';
  @State splitOpening: boolean = false;
  @State openDone: number = 0;
  @State openTotal: number = 0;
  @State splitNeedPwd: boolean = false;
  /** 错误 key：pwd / file / format / zero / other:N */
  @State splitErrKey: string = '';
  @State thumbs: PdfThumb[] = [];
  @State thumbSel: boolean[] = [];
  @State splitFormat: SplitFormat = SplitFormat.JPEG;
  @State jpegQuality: number = 90;
  @State exporting: boolean = false;
  @State exportDone: number = 0;
  @State exportTotal: number = 0;

  aboutToAppear(): void {
    this.fileName = this.defaultFileName();
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private formatBytes(bytes: number): string {
    if (bytes >= 1024 * 1024) {
      return (bytes / 1024 / 1024).toFixed(1) + ' MB';
    }
    return Math.max(1, Math.round(bytes / 1024)) + ' KB';
  }

  private pad2(n: number): string {
    return n < 10 ? '0' + n.toString() : n.toString();
  }

  private defaultFileName(): string {
    let d: Date = new Date();
    return 'PDF_' + d.getFullYear().toString() + this.pad2(d.getMonth() + 1) + this.pad2(d.getDate()) +
      '_' + this.pad2(d.getHours()) + this.pad2(d.getMinutes());
  }

  /** 文件名清洗：去 .pdf 后缀与路径非法字符，空则回退默认名 */
  private cleanFileName(): string {
    let n: string = this.fileName.trim();
    if (n.length > 4 && n.toLowerCase().endsWith('.pdf')) {
      n = n.substring(0, n.length - 4);
    }
    n = n.replace(/[\\/:*?"<>|]/g, '');
    if (n.length === 0) {
      n = this.defaultFileName();
    }
    return n;
  }

  private clearDir(dir: string): void {
    if (!fs.accessSync(dir)) {
      return;
    }
    let names: string[] = fs.listFileSync(dir);
    for (let i = 0; i < names.length; i++) {
      try {
        fs.unlinkSync(dir + '/' + names[i]);
      } catch (e) {
        console.warn(TAG + ' unlink failed: ' + (e as BusinessError).message);
      }
    }
  }

  // ==================== 合成：选图与排序 ====================

  private async pickImages(): Promise<void> {
    if (this.composing) {
      return;
    }
    let remain: number = MAX_IMAGES - this.composeImages.length;
    if (remain <= 0) {
      ToastUtil.show(this.getUIContext(), $r('app.string.pdf_compose_max'), 1800);
      return;
    }
    try {
      let options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = remain;
      let pv: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      let result: photoAccessHelper.PhotoSelectResult = await pv.select(options);
      if (result.photoUris.length === 0) {
        return;
      }
      let existing: Set<string> = new Set<string>();
      for (let i = 0; i < this.composeImages.length; i++) {
        existing.add(this.composeImages[i].uri);
      }
      let added: ComposeImage[] = [];
      for (let i = 0; i < result.photoUris.length; i++) {
        let uri: string = result.photoUris[i];
        if (existing.has(uri)) {
          continue;
        }
        let size: number[] = await PdfComposer.queryImageSize(uri);
        if (size[0] <= 0 || size[1] <= 0) {
          continue;
        }
        added.push(new ComposeImage(uri, size[0], size[1]));
        existing.add(uri);
      }
      if (added.length === 0) {
        return;
      }
      this.composeImages = this.composeImages.concat(added);
      this.composeResult = null;
      this.composeFailMsg = '';
      this.swapIndex = -1;
    } catch (e) {
      console.error(TAG + ' pickImages failed: ' + (e as BusinessError).message);
      ToastUtil.show(this.getUIContext(), $r('app.string.pdf_pick_image_fail'), 2000);
    }
  }

  /** 点击缩略图：第一次选中高亮，第二次点击另一张交换顺序 */
  private onThumbTap(index: number): void {
    if (this.swapIndex < 0) {
      this.swapIndex = index;
      return;
    }
    if (this.swapIndex === index) {
      this.swapIndex = -1;
      return;
    }
    let arr: ComposeImage[] = this.composeImages.slice();
    let tmp: ComposeImage = arr[this.swapIndex];
    arr[this.swapIndex] = arr[index];
    arr[index] = tmp;
    this.composeImages = arr;
    this.composeResult = null;
    this.swapIndex = -1;
  }

  private removeImage(index: number): void {
    let arr: ComposeImage[] = [];
    for (let i = 0; i < this.composeImages.length; i++) {
      if (i !== index) {
        arr.push(this.composeImages[i]);
      }
    }
    this.composeImages = arr;
    this.swapIndex = -1;
    this.composeResult = null;
  }

  // ==================== 合成：生成 / 保存 / 分享 ====================

  private async generate(): Promise<void> {
    if (this.composing || this.composeImages.length === 0) {
      return;
    }
    this.composing = true;
    this.composeResult = null;
    this.composeFailMsg = '';
    try {
      let name: string = this.cleanFileName();
      this.fileName = name;
      let outPath: string = this.ctx().filesDir + '/' + name + '.pdf';
      let result: ComposeResult = await PdfComposer.compose(
        this.composeImages, this.pageMode, this.marginMode, this.orientMode, outPath);
      if (result.ok) {
        this.composeResult = result;
      } else {
        this.composeFailMsg = result.errMsg;
        ToastUtil.show(this.getUIContext(), $r('app.string.pdf_compose_fail'), 2000);
      }
    } catch (e) {
      this.composeFailMsg = (e as BusinessError).message;
      ToastUtil.show(this.getUIContext(), $r('app.string.pdf_compose_fail'), 2000);
    }
    this.composing = false;
  }

  /** 通过系统保存器导出沙箱 PDF（文件管理器选目录） */
  private async savePdf(): Promise<void> {
    let r: ComposeResult | null = this.composeResult;
    if (r === null || this.savingPdf) {
      return;
    }
    this.savingPdf = true;
    try {
      let opts: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      opts.newFileNames = [this.fileName + '.pdf'];
      opts.fileSuffixChoices = ['.pdf'];
      let dp: picker.DocumentViewPicker = new picker.DocumentViewPicker(this.ctx());
      let uris: Array<string> = await dp.save(opts);
      if (uris.length === 0) {
        ToastUtil.show(this.getUIContext(), $r('app.string.pdf_save_cancel'), 1500);
        return;
      }
      let src: fs.File = fs.openSync(r.path, fs.OpenMode.READ_ONLY);
      let dst: fs.File = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.copyFileSync(src.fd, dst.fd);
      } finally {
        fs.closeSync(src);
        fs.closeSync(dst);
      }
      ToastUtil.show(this.getUIContext(), $r('app.string.pdf_saved'), 1500);
    } catch (e) {
      console.error(TAG + ' savePdf failed: ' + (e as BusinessError).message);
      ToastUtil.show(this.getUIContext(), $r('app.string.pdf_save_cancel'), 2000);
    }
    this.savingPdf = false;
  }

  /** 系统分享面板分享沙箱 PDF */
  private sharePdf(): void {
    let r: ComposeResult | null = this.composeResult;
    if (r === null) {
      return;
    }
    try {
      let uriStr: string = fileUri.getUriFromPath(r.path);
      let utdId: string = utd.getUniformDataTypeByFilenameExtension('.pdf');
      let shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utdId,
        uri: uriStr,
      });
      let controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      controller.on('dismiss', () => {
        console.info(TAG + ' share panel closed');
      });
      controller.show(this.ctx(), {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE,
      });
    } catch (e) {
      console.error(TAG + ' sharePdf failed: ' + (e as BusinessError).message);
      ToastUtil.show(this.getUIContext(), $r('app.string.pdf_share_fail'), 2000);
    }
  }

  // ==================== 拆分：选 PDF / 解析 ====================

  private async pickPdf(): Promise<void> {
    if (this.splitOpening || this.exporting) {
      return;
    }
    try {
      let options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.pdf', 'PDF'];
      let dp: picker.DocumentViewPicker = new picker.DocumentViewPicker(this.ctx());
      let uris: Array<string> = await dp.select(options);
      if (uris.length === 0) {
        return;
      }
      let dest: string = this.ctx().cacheDir + '/pdftool_src_' + Date.now() + '.pdf';
      let src: fs.File = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
      let dst: fs.File = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.copyFileSync(src.fd, dst.fd);
      } finally {
        fs.closeSync(src);
        fs.closeSync(dst);
      }
      this.splitPath = dest;
      this.splitSize = fs.statSync(dest).size;
      this.splitName = this.displayNameOf(uris[0]);
      this.splitPwd = '';
      this.thumbs = [];
      this.thumbSel = [];
      this.splitNeedPwd = false;
      this.splitErrKey = '';
      this.splitOpening = false;
      await this.openSplit();
    } catch (e) {
      console.error(TAG + ' pickPdf failed: ' + (e as BusinessError).message);
      ToastUtil.show(this.getUIContext(), $r('app.string.pdf_split_pick_fail'), 2000);
    }
  }

  /** 从 uri 解析显示文件名（去 .pdf 后缀），失败回退 PDF */
  private displayNameOf(uriStr: string): string {
    try {
      let u: fileUri.FileUri = new fileUri.FileUri(uriStr);
      let name: string = u.name;
      if (name.length > 4 && name.toLowerCase().endsWith('.pdf')) {
        name = name.substring(0, name.length - 4);
      }
      if (name.length > 0) {
        return name;
      }
    } catch (e) {
      console.warn(TAG + ' displayNameOf failed: ' + (e as BusinessError).message);
    }
    return 'PDF';
  }

  private async openSplit(): Promise<void> {
    if (this.splitOpening) {
      return;
    }
    this.splitOpening = true;
    this.splitNeedPwd = false;
    this.splitErrKey = '';
    this.openDone = 0;
    this.openTotal = 0;
    try {
      let thumbDir: string = this.ctx().cacheDir + '/pdftool_thumbs';
      this.clearDir(thumbDir);
      let result = await PdfSplitter.openThumbs(this.splitPath, this.splitPwd, thumbDir,
        (done: number, total: number): void => {
          this.openDone = done;
          this.openTotal = total;
        });
      if (result.needPassword) {
        this.splitNeedPwd = true;
        return;
      }
      if (!result.ok) {
        this.splitErrKey = this.parseErrKey(result.parseErr);
        return;
      }
      this.thumbs = result.thumbs;
      let sel: boolean[] = [];
      for (let i = 0; i < result.thumbs.length; i++) {
        sel.push(true);
      }
      this.thumbSel = sel;
      if (result.pageCount > MAX_PAGES_HINT) {
        ToastUtil.show(this.getUIContext(), $r('app.string.pdf_split_max'), 2500);
      }
    } catch (e) {
      this.splitErrKey = 'other:' + (e as BusinessError).code.toString();
    }
    this.splitOpening = false;
  }

  /** ParseResult 枚举值 → 错误 key（页面文案映射用） */
  private parseErrKey(err: number): string {
    if (err === PARSE_ERR_PASSWORD) {
      return 'pwd';
    }
    if (err === PARSE_ERR_FILE) {
      return 'file';
    }
    if (err === PARSE_ERR_FORMAT) {
      return 'format';
    }
    if (err === PARSE_ERR_NOPAGE || err === PARSE_ERR_NOTHUMB) {
      return 'zero';
    }
    return 'other:' + err.toString();
  }

  private parseErrText(): string {
    if (this.splitErrKey === 'pwd') {
      return this.resText($r('app.string.pdf_parse_pwd_err'));
    }
    if (this.splitErrKey === 'file') {
      return this.resText($r('app.string.pdf_parse_file_err'));
    }
    if (this.splitErrKey === 'format') {
      return this.resText($r('app.string.pdf_parse_format_err'));
    }
    if (this.splitErrKey === 'zero') {
      return this.resText($r('app.string.pdf_parse_zero_err'));
    }
    let code: string = this.splitErrKey.startsWith('other:') ? this.splitErrKey.substring(6) : this.splitErrKey;
    return this.resText($r('app.string.pdf_parse_other_err', code));
  }

  private resText(res: Resource): string {
    try {
      return this.getUIContext().getHostContext()!.resourceManager.getStringSync(res);
    } catch (e) {
      return '';
    }
  }

  // ==================== 拆分：选择与导出 ====================

  private toggleThumbSel(index: number): void {
    if (index < 0 || index >= this.thumbSel.length) {
      return;
    }
    this.thumbSel[index] = !this.thumbSel[index];
  }

  private setAllSel(sel: boolean): void {
    let arr: boolean[] = [];
    for (let i = 0; i < this.thumbSel.length; i++) {
      arr.push(sel);
    }
    this.thumbSel = arr;
  }

  private selCount(): number {
    let n: number = 0;
    for (let i = 0; i < this.thumbSel.length; i++) {
      if (this.thumbSel[i]) {
        n++;
      }
    }
    return n;
  }

  private async exportSplit(): Promise<void> {
    if (this.exporting) {
      return;
    }
    let selIdx: number[] = [];
    for (let i = 0; i < this.thumbs.length; i++) {
      if (this.thumbSel[i]) {
        selIdx.push(this.thumbs[i].index);
      }
    }
    if (selIdx.length === 0) {
      ToastUtil.show(this.getUIContext(), $r('app.string.pdf_split_no_select'), 1800);
      return;
    }
    this.exporting = true;
    this.exportDone = 0;
    this.exportTotal = selIdx.length;
    try {
      let outDir: string = this.ctx().cacheDir + '/pdftool_out';
      this.clearDir(outDir);
      let result = await PdfSplitter.exportPages(this.splitPath, this.splitPwd, selIdx,
        this.splitFormat, this.jpegQuality, outDir, this.splitName,
        (done: number, total: number): void => {
          this.exportDone = done;
          this.exportTotal = total;
        });
      if (!result.ok) {
        ToastUtil.show(this.getUIContext(), $r('app.string.pdf_split_export_fail'), 2000);
        return;
      }
      let okCount: number = await this.saveImagesToAlbum(result.paths);
      if (okCount === result.paths.length) {
        ToastUtil.show(this.getUIContext(), $r('app.string.pdf_split_export_done', okCount), 2000);
      } else if (okCount > 0) {
        ToastUtil.show(this.getUIContext(), $r('app.string.pdf_split_export_done', okCount), 2000);
      } else {
        ToastUtil.show(this.getUIContext(), $r('app.string.pdf_save_album_fail'), 2000);
      }
    } catch (e) {
      console.error(TAG + ' exportSplit failed: ' + (e as BusinessError).message);
      ToastUtil.show(this.getUIContext(), $r('app.string.pdf_split_export_fail'), 2000);
    }
    this.exporting = false;
  }

  /** 多张图片经相册保存对话框落盘（showAssetsCreationDialog 多选） */
  private async saveImagesToAlbum(paths: string[]): Promise<number> {
    let ctx: common.UIAbilityContext = this.ctx();
    let helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(ctx);
    let ext: string = this.splitFormat === SplitFormat.PNG ? 'png' : 'jpg';
    let srcUris: string[] = [];
    let configs: Array<photoAccessHelper.PhotoCreationConfig> = [];
    for (let i = 0; i < paths.length; i++) {
      let cfg: photoAccessHelper.PhotoCreationConfig = {
        title: this.splitName + '_p' + (i + 1),
        fileNameExtension: ext,
        photoType: photoAccessHelper.PhotoType.IMAGE,
      };
      srcUris.push(fileUri.getUriFromPath(paths[i]));
      configs.push(cfg);
    }
    let desUris: Array<string> = await helper.showAssetsCreationDialog(srcUris, configs);
    let ok: number = 0;
    for (let i = 0; i < desUris.length && i < paths.length; i++) {
      let src: fs.File = fs.openSync(paths[i], fs.OpenMode.READ_ONLY);
      let dst: fs.File = await fs.open(desUris[i], fs.OpenMode.READ_WRITE);
      try {
        await fs.copyFile(src.fd, dst.fd);
        ok++;
      } finally {
        fs.closeSync(src);
        await fs.close(dst);
      }
    }
    return ok;
  }

  // ==================== UI ====================

  @Builder
  TabBar() {
    Row() {
      Text($r('app.string.pdf_tab_compose'))
        .fontSize(15)
        .fontWeight(this.activeTab === 0 ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.activeTab === 0 ? $r('app.color.brand_blue') : $r('app.color.editor_label_text'))
        .padding({ left: 18, right: 18, top: 10, bottom: 10 })
        .onClick(() => {
          this.activeTab = 0;
        })
      Text($r('app.string.pdf_tab_split'))
        .fontSize(15)
        .fontWeight(this.activeTab === 1 ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.activeTab === 1 ? $r('app.color.brand_blue') : $r('app.color.editor_label_text'))
        .padding({ left: 18, right: 18, top: 10, bottom: 10 })
        .onClick(() => {
          this.activeTab = 1;
        })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .border({ width: { bottom: 1 }, color: $r('app.color.editor_line') })
  }

  /** 通用 chip：选中蓝底白字，未选灰底 */
  @Builder
  ModeChip(text: ResourceStr, selected: boolean, action: () => void) {
    Text(text)
      .fontSize(13)
      .fontColor(selected ? Color.White : $r('app.color.editor_chip_text'))
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .backgroundColor(selected ? $r('app.color.brand_blue') : $r('app.color.editor_chip_bg'))
      .borderRadius(14)
      .onClick(() => {
        action();
      })
  }

  @Builder
  FieldLabel(text: ResourceStr) {
    Text(text)
      .fontSize(12)
      .fontColor($r('app.color.editor_label_text'))
  }

  // ---------- 合成面板 ----------

  @Builder
  ComposeEmpty() {
    Column({ space: 12 }) {
      Button($r('app.string.pdf_compose_pick'))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_accent_text'))
        .backgroundColor($r('app.color.brand_blue'))
        .borderRadius(22)
        .height(44)
        .padding({ left: 32, right: 32 })
        .enabled(!this.composing)
        .onClick(() => {
          this.pickImages();
        })
      Text($r('app.string.pdf_compose_empty'))
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
        .lineHeight(19)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 46, bottom: 46 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  ImageThumb(item: ComposeImage, index: number) {
    Column({ space: 4 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(item.uri)
          .width(72)
          .height(72)
          .objectFit(ImageFit.Cover)
          .borderRadius(10)
          .border({
            width: this.swapIndex === index ? 2 : 0,
            color: $r('app.color.brand_blue')
          })
        Text('×')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .width(20)
          .height(20)
          .textAlign(TextAlign.Center)
          .backgroundColor('#99DC2626')
          .borderRadius(10)
          .onClick(() => {
            this.removeImage(index);
          })
      }
      Text((index + 1).toString())
        .fontSize(11)
        .fontColor(this.swapIndex === index ? $r('app.color.brand_blue') : $r('app.color.secondary_text'))
    }
    .onClick(() => {
      this.onThumbTap(index);
    })
  }

  @Builder
  ComposePanel() {
    Column({ space: 14 }) {
      // 已选图片
      Column({ space: 10 }) {
        Row() {
          Text($r('app.string.pdf_compose_count', this.composeImages.length))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .layoutWeight(1)
          Text($r('app.string.pdf_compose_add'))
            .fontSize(13)
            .fontColor($r('app.color.brand_blue'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor($r('app.color.brand_blue_tint'))
            .borderRadius(13)
            .enabled(this.composeImages.length < MAX_IMAGES && !this.composing)
            .onClick(() => {
              this.pickImages();
            })
        }
        .width('100%')

        Scroll() {
          Row({ space: 10 }) {
            ForEach(this.composeImages, (item: ComposeImage, index: number) => {
              this.ImageThumb(item, index)
            }, (item: ComposeImage, index: number) => item.uri + '_' + index.toString())
          }
          .padding({ bottom: 2 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Auto)
        .width('100%')

        Text($r('app.string.pdf_compose_swap_hint'))
          .fontSize(11)
          .fontColor($r('app.color.tertiary_text'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(14)
      .borderRadius(12)
      .backgroundColor($r('app.color.card_background'))

      // 配置
      Column({ space: 14 }) {
        Column({ space: 8 }) {
          this.FieldLabel($r('app.string.pdf_compose_mode'))
          Row({ space: 8 }) {
            this.ModeChip($r('app.string.pdf_compose_fit'), this.pageMode === PdfPageMode.FIT, () => {
              this.pageMode = PdfPageMode.FIT;
            })
            this.ModeChip($r('app.string.pdf_compose_a4'), this.pageMode === PdfPageMode.A4, () => {
              this.pageMode = PdfPageMode.A4;
            })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        if (this.pageMode === PdfPageMode.A4) {
          Column({ space: 8 }) {
            this.FieldLabel($r('app.string.pdf_compose_margin'))
            Row({ space: 8 }) {
              this.ModeChip($r('app.string.pdf_margin_none'), this.marginMode === PdfMarginMode.NONE, () => {
                this.marginMode = PdfMarginMode.NONE;
              })
              this.ModeChip($r('app.string.pdf_margin_narrow'), this.marginMode === PdfMarginMode.NARROW, () => {
                this.marginMode = PdfMarginMode.NARROW;
              })
              this.ModeChip($r('app.string.pdf_margin_normal'), this.marginMode === PdfMarginMode.NORMAL, () => {
                this.marginMode = PdfMarginMode.NORMAL;
              })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 8 }) {
            this.FieldLabel($r('app.string.pdf_compose_orient'))
            Row({ space: 8 }) {
              this.ModeChip($r('app.string.pdf_orient_auto'), this.orientMode === PdfOrientation.AUTO, () => {
                this.orientMode = PdfOrientation.AUTO;
              })
              this.ModeChip($r('app.string.pdf_orient_portrait'), this.orientMode === PdfOrientation.PORTRAIT, () => {
                this.orientMode = PdfOrientation.PORTRAIT;
              })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        Column({ space: 8 }) {
          this.FieldLabel($r('app.string.pdf_compose_name'))
          TextInput({ text: this.fileName, placeholder: $r('app.string.pdf_compose_name_hint') })
            .height(40)
            .fontSize(14)
            .backgroundColor($r('app.color.editor_input_bg'))
            .borderRadius(8)
            .enabled(!this.composing)
            .onChange((value: string) => {
              this.fileName = value;
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(14)
      .borderRadius(12)
      .backgroundColor($r('app.color.card_background'))

      // 生成
      Button(this.composing ? $r('app.string.pdf_compose_generating') : $r('app.string.pdf_compose_generate'))
        .width('100%')
        .height(46)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_accent_text'))
        .backgroundColor($r('app.color.brand_blue'))
        .borderRadius(23)
        .enabled(!this.composing && this.composeImages.length > 0)
        .onClick(() => {
          this.generate();
        })

      if (this.composing) {
        LoadingProgress()
          .width(28)
          .height(28)
          .color($r('app.color.brand_blue'))
      }

      // 结果
      if (this.composeResult !== null) {
        Column({ space: 12 }) {
          Text($r('app.string.pdf_compose_done', this.composeResult.pages,
            this.formatBytes(this.composeResult.bytes)))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.success_green'))
          Row({ space: 10 }) {
            Button($r('app.string.pdf_save'))
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.on_accent_text'))
              .backgroundColor($r('app.color.brand_blue'))
              .borderRadius(20)
              .enabled(!this.savingPdf)
              .onClick(() => {
                this.savePdf();
              })
            Button($r('app.string.pdf_share'))
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.on_accent_text'))
              .backgroundColor($r('app.color.brand_blue'))
              .borderRadius(20)
              .onClick(() => {
                this.sharePdf();
              })
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(14)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_background'))
      }

      if (this.composeFailMsg.length > 0) {
        Text($r('app.string.pdf_compose_fail'))
          .fontSize(13)
          .fontColor($r('app.color.error_red'))
      }
    }
    .width('100%')
  }

  // ---------- 拆分面板 ----------

  @Builder
  SplitEmpty() {
    Column({ space: 12 }) {
      Button($r('app.string.pdf_split_pick'))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_accent_text'))
        .backgroundColor($r('app.color.brand_blue'))
        .borderRadius(22)
        .height(44)
        .padding({ left: 32, right: 32 })
        .enabled(!this.splitOpening && !this.exporting)
        .onClick(() => {
          this.pickPdf();
        })
      Text($r('app.string.pdf_split_empty'))
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
        .lineHeight(19)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 46, bottom: 46 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  PageThumbCell(item: PdfThumb, index: number) {
    Column({ space: 4 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(fileUri.getUriFromPath(item.path))
          .width('100%')
          .aspectRatio(0.78)
          .objectFit(ImageFit.Contain)
          .borderRadius(8)
          .backgroundColor(Color.White)
        Text(this.thumbSel[index] ? '✓' : '')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .width(20)
          .height(20)
          .textAlign(TextAlign.Center)
          .backgroundColor(this.thumbSel[index] ? $r('app.color.brand_blue') : '#66000000')
          .borderRadius(10)
      }
      Text($r('app.string.pdf_split_page_no', item.index + 1))
        .fontSize(11)
        .fontColor(this.thumbSel[index] ? $r('app.color.brand_blue') : $r('app.color.secondary_text'))
    }
    .width('31%')
    .onClick(() => {
      this.toggleThumbSel(index);
    })
  }

  @Builder
  SplitPanel() {
    Column({ space: 14 }) {
      // 文件信息
      Column({ space: 6 }) {
        Row() {
          Text(this.splitName)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.formatBytes(this.splitSize))
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(14)
      .borderRadius(12)
      .backgroundColor($r('app.color.card_background'))

      // 解析中
      if (this.splitOpening) {
        Column({ space: 10 }) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color($r('app.color.brand_blue'))
          if (this.openTotal > 0) {
            Text($r('app.string.pdf_split_parsing', this.openDone, this.openTotal))
              .fontSize(13)
              .fontColor($r('app.color.secondary_text'))
          }
        }
        .width('100%')
        .padding(14)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_background'))
      }

      // 需要密码
      if (this.splitNeedPwd && !this.splitOpening) {
        Column({ space: 10 }) {
          Text($r('app.string.pdf_split_need_pwd'))
            .fontSize(13)
            .fontColor($r('app.color.warning_orange'))
            .lineHeight(19)
          TextInput({ placeholder: $r('app.string.pdf_split_pwd_hint'), text: this.splitPwd })
            .height(40)
            .fontSize(14)
            .backgroundColor($r('app.color.editor_input_bg'))
            .borderRadius(8)
            .onChange((value: string) => {
              this.splitPwd = value;
            })
          Button($r('app.string.pdf_split_parse'))
            .width('100%')
            .height(40)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_accent_text'))
            .backgroundColor($r('app.color.brand_blue'))
            .borderRadius(20)
            .onClick(() => {
              this.openSplit();
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(14)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_background'))
      }

      // 解析失败
      if (this.splitErrKey.length > 0 && !this.splitNeedPwd && !this.splitOpening) {
        Column({ space: 10 }) {
          Text(this.parseErrText())
            .fontSize(13)
            .fontColor($r('app.color.error_red'))
            .lineHeight(19)
          Button($r('app.string.pdf_split_retry'))
            .height(38)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_accent_text'))
            .backgroundColor($r('app.color.brand_blue'))
            .borderRadius(19)
            .padding({ left: 22, right: 22 })
            .onClick(() => {
              this.openSplit();
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(14)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_background'))
      }

      // 页列表
      if (this.thumbs.length > 0 && !this.splitOpening) {
        Column({ space: 10 }) {
          Row() {
            Text($r('app.string.pdf_split_pages', this.thumbs.length))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))
              .layoutWeight(1)
            Text($r('app.string.pdf_split_select_all'))
              .fontSize(13)
              .fontColor($r('app.color.brand_blue'))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor($r('app.color.brand_blue_tint'))
              .borderRadius(13)
              .enabled(!this.exporting)
              .onClick(() => {
                this.setAllSel(true);
              })
            Text($r('app.string.pdf_split_deselect_all'))
              .fontSize(13)
              .fontColor($r('app.color.secondary_text'))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor($r('app.color.editor_chip_bg'))
              .borderRadius(13)
              .enabled(!this.exporting)
              .onClick(() => {
                this.setAllSel(false);
              })
          }
          .width('100%')

          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            ForEach(this.thumbs, (item: PdfThumb, index: number) => {
              this.PageThumbCell(item, index)
            }, (item: PdfThumb, index: number) => item.index.toString() + '_' + index.toString())
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(14)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_background'))
      }

      // 格式与质量
      if (this.thumbs.length > 0 && !this.splitOpening && !this.exporting) {
        Column({ space: 14 }) {
          Column({ space: 8 }) {
            this.FieldLabel($r('app.string.pdf_split_format'))
            Row({ space: 8 }) {
              this.ModeChip($r('app.string.pdf_format_jpeg'), this.splitFormat === SplitFormat.JPEG, () => {
                this.splitFormat = SplitFormat.JPEG;
              })
              this.ModeChip($r('app.string.pdf_format_png'), this.splitFormat === SplitFormat.PNG, () => {
                this.splitFormat = SplitFormat.PNG;
              })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          if (this.splitFormat === SplitFormat.JPEG) {
            Column({ space: 6 }) {
              Text($r('app.string.pdf_split_quality', this.jpegQuality))
                .fontSize(12)
                .fontColor($r('app.color.editor_label_text'))
              Slider({ value: this.jpegQuality, min: 60, max: 100, step: 1, style: SliderStyle.OutSet })
                .width('100%')
                .blockColor($r('app.color.brand_blue'))
                .selectedColor($r('app.color.brand_blue'))
                .onChange((value: number) => {
                  this.jpegQuality = Math.round(value);
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(14)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_background'))
      }

      // 导出按钮与进度
      if (this.thumbs.length > 0 && !this.splitOpening) {
        Button($r('app.string.pdf_split_export', this.selCount()))
          .width('100%')
          .height(46)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_accent_text'))
          .backgroundColor(this.selCount() > 0 ? $r('app.color.brand_blue') : $r('app.color.border_color'))
          .borderRadius(23)
          .enabled(!this.exporting && this.selCount() > 0)
          .onClick(() => {
            this.exportSplit();
          })

        if (this.exporting) {
          Text($r('app.string.pdf_split_exporting', this.exportDone, this.exportTotal))
            .fontSize(13)
            .fontColor($r('app.color.secondary_text'))
        }
      }
    }
    .width('100%')
  }

  build() {
    Column() {
      this.TabBar()
      Scroll() {
        Column({ space: 14 }) {
          if (this.activeTab === 0) {
            if (this.composeImages.length === 0) {
              this.ComposeEmpty()
            } else {
              this.ComposePanel()
            }
          } else {
            if (this.splitPath.length === 0) {
              this.SplitEmpty()
            } else {
              this.SplitPanel()
            }
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .constraintSize({ maxWidth: 760 })
  }
}
