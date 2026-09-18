/**
 * 生字卡页面：尺寸/格型/字色/配色选择 + 整课生字输入 + 自动注音
 * 单卡导出（1080x1080 / 1080x1440）+ 批量导出（每字一卡）+ 制作历史
 */
import { display, mediaquery } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CoverHistoryRecord, CoverPalette } from '../model/CoverModels';
import { CharCards, CharCardCharMode, CharCardGridType, CharCardSize } from '../core/cover/CharCardTemplates';
import { CoverContentUtil } from '../core/cover/CoverContentUtil';
import { CoverHistoryStore } from '../core/cover/CoverHistoryStore';
import { CharCardPreview } from '../components/cover/CharCardPreview';
import { FontUtil } from '../common/utils/FontUtil';
import { ToastUtil } from '../common/utils/ToastUtil';
import { savePixelMapToAlbum, saveFilesToAlbum, shareImageViaPanel } from '../common/utils/ShareImageUtil';

const PREVIEW_ID: string = 'charcard_preview';
const HISTORY_DIR: string = CoverHistoryStore.DIR_CHAR_CARD;

@Builder
export function CharCardPageBuilder() {
  NavDestination() {
    CharCardContent()
  }
  .title('生字卡')
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct CharCardContent {
  @State charsText: string = '学而时习之';
  @State pinyinText: string = '';
  @State pinyinLocked: boolean = false;
  @State pinyinOn: boolean = true;
  @State paletteIndex: number = 0;
  @State gridType: string = CharCardGridType.TIAN;
  @State charMode: string = CharCardCharMode.READ;
  @State sizeKind: string = CharCardSize.SQUARE;
  @State exporting: boolean = false;
  @State batchRunning: boolean = false;
  @State batchProgress: number = 0;
  @State batchTotal: number = 0;
  @State historyRecords: CoverHistoryRecord[] = [];
  @State isDark: boolean = false;
  previewVp: number = 300;
  snapshotScale: number = 1;
  batchChar: string = '';
  /** 焦点守卫：拼音框仅在聚焦时才把 onChange 视为手动编辑（防止程序化 text 更新误触发锁定） */
  pinyinFocused: boolean = false;
  private darkListener: mediaquery.MediaQueryListener | null = null;

  aboutToAppear(): void {
    FontUtil.registerAll(this.getUIContext());
    let listener: mediaquery.MediaQueryListener =
      this.getUIContext().getMediaQuery().matchMediaSync('(prefers-color-scheme: dark)');
    this.darkListener = listener;
    this.isDark = listener.matches;
    listener.on('change', (result: mediaquery.MediaQueryResult) => {
      this.isDark = result.matches;
    });
    let d: display.Display = display.getDefaultDisplaySync();
    let density: number = d.densityPixels;
    let availVp: number = d.width / density - 32;
    this.previewVp = Math.min(CharCards.DESIGN_W / density, availVp);
    this.snapshotScale = CharCards.EXPORT_W / (this.previewVp * density);
    this.pinyinText = CoverContentUtil.autoPinyin(CharCards.cleanChars(this.charsText));
    this.historyRecords = CoverHistoryStore.loadRecords(this.context(), HISTORY_DIR);
  }

  // ---------- 状态与业务 ----------

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private cleanChars(): string {
    return CharCards.cleanChars(this.charsText);
  }

  /** 预览/导出使用的字串：批量模式下逐字替换 */
  private displayChars(): string {
    return this.batchChar !== '' ? this.batchChar : this.cleanChars();
  }

  private displayPinyin(): string {
    if (this.batchChar !== '') {
      return CoverContentUtil.autoPinyin(this.batchChar);
    }
    return this.pinyinText;
  }

  private onCharsChange(value: string): void {
    this.charsText = value;
    if (!this.pinyinLocked) {
      this.pinyinText = CoverContentUtil.autoPinyin(CharCards.cleanChars(value));
    }
  }

  private resetPinyin(): void {
    this.pinyinLocked = false;
    this.pinyinText = CoverContentUtil.autoPinyin(this.cleanChars());
  }

  private canExport(): boolean {
    return this.cleanChars().length > 0;
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }

  private currentRecord(fileName: string): CoverHistoryRecord {
    let r: Record<string, Object> = {
      'chars': this.charsText,
      'pinyin': this.pinyinText,
      'pinyinOn': this.pinyinOn,
      'locked': this.pinyinLocked,
    };
    return CoverHistoryRecord.of(
      Date.now().toString(36) + Math.floor(Math.random() * 1000).toString(),
      fileName, this.sizeKind + '|' + this.gridType + '|' + this.charMode,
      this.paletteIndex, 0, JSON.stringify(r), Date.now());
  }

  private restoreFromHistory(r: CoverHistoryRecord): void {
    let parts: string[] = r.templateId.split('|');
    if (parts.length === 3) {
      this.sizeKind = parts[0];
      this.gridType = parts[1];
      this.charMode = parts[2];
    }
    this.paletteIndex = r.paletteIndex;
    try {
      let t: Record<string, Object> = JSON.parse(r.textsJson) as Record<string, Object>;
      this.charsText = String(t['chars'] ?? '');
      this.pinyinText = String(t['pinyin'] ?? '');
      this.pinyinOn = Boolean(t['pinyinOn'] ?? true);
      this.pinyinLocked = Boolean(t['locked'] ?? false);
    } catch (e) {
      console.error('[CharCard] restore failed: ' + (e as Error).message);
    }
    ToastUtil.show(this.getUIContext(), '已恢复', 1200);
  }

  private clearHistory(): void {
    CoverHistoryStore.clearAll(this.context(), HISTORY_DIR);
    this.historyRecords = [];
  }

  /** 当前预览快照 -> PNG 文件，返回文件路径 */
  private async snapshotToFile(context: common.UIAbilityContext, tag: string): Promise<string> {
    let uiCtx: UIContext = this.getUIContext();
    let snapshot = uiCtx.getComponentSnapshot();
    let pixelMap: image.PixelMap =
      await snapshot.get(PREVIEW_ID, { scale: this.snapshotScale, waitUntilRenderFinished: true });
    return this.pixelMapToFile(context, pixelMap, tag);
  }

  /** PixelMap -> PNG 文件（缓存目录），返回文件路径 */
  private async pixelMapToFile(context: common.UIAbilityContext, pixelMap: image.PixelMap,
    tag: string): Promise<string> {
    let packer: image.ImagePacker = image.createImagePacker();
    let fileName: string = 'card_' + Date.now().toString(36) + '_' + tag + '.png';
    let filePath: string = context.cacheDir + '/' + fileName;
    let file: fs.File = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      await packer.packToFile(pixelMap, file.fd, { format: 'image/png', quality: 100 });
    } finally {
      fs.closeSync(file.fd);
      packer.release();
    }
    return filePath;
  }

  private async doExport(save: boolean): Promise<void> {
    if (!this.canExport() || this.exporting || this.batchRunning) {
      return;
    }
    this.exporting = true;
    try {
      await this.sleep(150);
      let context: common.UIAbilityContext = this.context();
      let filePath: string = await this.snapshotToFile(context, 'single');
      if (CoverHistoryStore.saveRecord(context, filePath, this.currentRecord(
        CoverHistoryStore.makeFileName()), HISTORY_DIR)) {
        this.historyRecords = CoverHistoryStore.loadRecords(context, HISTORY_DIR);
      }
      if (save) {
        let uiCtx: UIContext = this.getUIContext();
        let snapshot = uiCtx.getComponentSnapshot();
        let pixelMap: image.PixelMap =
          await snapshot.get(PREVIEW_ID, { scale: this.snapshotScale, waitUntilRenderFinished: true });
        let ok: boolean = await savePixelMapToAlbum(uiCtx, pixelMap);
        pixelMap.release();
        ToastUtil.show(uiCtx, ok ? '已保存到相册' : '已取消保存', 1500);
      } else {
        shareImageViaPanel(this.getUIContext(), filePath);
      }
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[CharCard] export failed: ' + err.code + ' ' + err.message);
      ToastUtil.show(this.getUIContext(), '导出失败：' + err.message, 2000);
    }
    this.exporting = false;
  }

  /** 批量导出：每字一卡逐张渲染落盘，最后单次保存弹窗统一入相册 */
  private async doBatchExport(): Promise<void> {
    let chars: string[] = this.cleanChars().split('');
    if (chars.length < 2 || this.batchRunning || this.exporting) {
      return;
    }
    this.batchRunning = true;
    this.batchTotal = chars.length;
    this.batchProgress = 0;
    let batchFiles: string[] = [];
    try {
      let uiCtx: UIContext = this.getUIContext();
      let context: common.UIAbilityContext = this.context();
      for (let i = 0; i < chars.length; i++) {
        this.batchChar = chars[i];
        this.batchProgress = i + 1;
        await this.sleep(150);
        let snapshot = uiCtx.getComponentSnapshot();
        let pixelMap: image.PixelMap =
          await snapshot.get(PREVIEW_ID, { scale: this.snapshotScale, waitUntilRenderFinished: true });
        batchFiles.push(await this.pixelMapToFile(context, pixelMap, 'batch_' + i.toString()));
        pixelMap.release();
      }
      this.batchChar = '';
      if (batchFiles.length > 0) {
        if (CoverHistoryStore.saveRecord(context, batchFiles[0], this.currentRecord(
          CoverHistoryStore.makeFileName()), HISTORY_DIR)) {
          this.historyRecords = CoverHistoryStore.loadRecords(context, HISTORY_DIR);
        }
      }
      let saved: number = await saveFilesToAlbum(uiCtx, batchFiles);
      if (saved > 0) {
        ToastUtil.show(uiCtx, '已保存 ' + saved.toString() + ' 张到相册', 1800);
      } else {
        ToastUtil.show(uiCtx, '已取消导出', 1500);
      }
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[CharCard] batch export failed: ' + err.code + ' ' + err.message);
      ToastUtil.show(this.getUIContext(), '导出失败：' + err.message, 2000);
    } finally {
      for (let i = 0; i < batchFiles.length; i++) {
        try {
          fs.unlinkSync(batchFiles[i]);
        } catch (e) {
          console.warn('[CharCard] remove batch temp failed: ' + (e as Error).message);
        }
      }
      this.batchChar = '';
      this.batchRunning = false;
    }
  }

  // ---------- 主题色 ----------

  private inputBg(): string {
    return this.isDark ? '#2A2A2C' : '#F5F5F5';
  }

  private labelColor(): string {
    return this.isDark ? '#AAAAAA' : '#666666';
  }

  private chipBg(): string {
    return this.isDark ? '#333336' : '#F2F2F2';
  }

  private chipText(): string {
    return this.isDark ? '#E0E0E0' : '#333333';
  }

  private lineColor(): string {
    return this.isDark ? '#3A3A3C' : '#E5E5E5';
  }

  private accent(): string {
    return '#D8231A';
  }

  // ---------- UI ----------

  build() {
    Column() {
      Scroll() {
        Column({ space: 14 }) {
          this.PreviewSection()
          this.SizeChips()
          this.StyleChips()
          this.PaletteSection()
          this.TextEditor()
          this.HistorySection()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')

      this.ExportBar()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  PreviewSection() {
    Column({ space: 8 }) {
      Row() {
        Column() {
          CharCardPreview({
            charsText: this.displayChars(),
            pinyinText: this.displayPinyin(),
            pinyinOn: this.pinyinOn,
            paletteIndex: this.paletteIndex,
            gridType: this.gridType,
            charMode: this.charMode,
            sizeKind: this.sizeKind,
            previewWidth: this.previewVp,
          })
        }
        .width(this.previewVp)
        .height(this.previewVp * CharCards.designHeight(this.sizeKind) / CharCards.DESIGN_W)
        .clip(true)
        .id(PREVIEW_ID)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Text(CharCardSize.label(this.sizeKind) + ' · ' +
        CharCards.EXPORT_W.toString() + ' × ' + CharCards.exportHeight(this.sizeKind).toString())
        .fontSize(11)
        .fontColor(this.labelColor())
    }
    .width('100%')
  }

  @Builder
  SizeChips() {
    Row({ space: 8 }) {
      Text('尺寸')
        .fontSize(12)
        .fontColor(this.labelColor())
      ForEach([CharCardSize.SQUARE, CharCardSize.PRACTICE], (kind: string) => {
        Text(CharCardSize.label(kind))
          .fontSize(13)
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .backgroundColor(this.sizeKind === kind ? this.accent() : this.chipBg())
          .fontColor(this.sizeKind === kind ? '#FFFFFF' : this.chipText())
          .borderRadius(14)
          .onClick(() => {
            this.sizeKind = kind;
          })
      }, (kind: string) => kind)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  StyleChips() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('格型')
          .fontSize(12)
          .fontColor(this.labelColor())
          .width(30)
        ForEach([CharCardGridType.TIAN, CharCardGridType.MI], (kind: string) => {
          Text(CharCardGridType.label(kind))
            .fontSize(13)
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .backgroundColor(this.gridType === kind ? this.accent() : this.chipBg())
            .fontColor(this.gridType === kind ? '#FFFFFF' : this.chipText())
            .borderRadius(14)
            .onClick(() => {
              this.gridType = kind;
            })
        }, (kind: string) => kind)
        Blank()
        Text('字色')
          .fontSize(12)
          .fontColor(this.labelColor())
        ForEach([CharCardCharMode.READ, CharCardCharMode.TRACE], (mode: string) => {
          Text(CharCardCharMode.label(mode))
            .fontSize(13)
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .backgroundColor(this.charMode === mode ? this.accent() : this.chipBg())
            .fontColor(this.charMode === mode ? '#FFFFFF' : this.chipText())
            .borderRadius(14)
            .onClick(() => {
              this.charMode = mode;
            })
        }, (mode: string) => mode)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 8 }) {
        Text('拼音')
          .fontSize(12)
          .fontColor(this.labelColor())
          .width(30)
        Text('显示')
          .fontSize(13)
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .backgroundColor(this.pinyinOn ? this.accent() : this.chipBg())
          .fontColor(this.pinyinOn ? '#FFFFFF' : this.chipText())
          .borderRadius(14)
          .onClick(() => {
            this.pinyinOn = true;
          })
        Text('隐藏')
          .fontSize(13)
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .backgroundColor(!this.pinyinOn ? this.accent() : this.chipBg())
          .fontColor(!this.pinyinOn ? '#FFFFFF' : this.chipText())
          .borderRadius(14)
          .onClick(() => {
            this.pinyinOn = false;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }

  @Builder
  PaletteSection() {
    Column({ space: 10 }) {
      Text('配色方案')
        .fontSize(12)
        .fontColor(this.labelColor())
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(CharCards.palettes(), (p: CoverPalette, idx: number) => {
          Stack() {
            Column()
              .width(38)
              .height(38)
              .borderRadius(19)
              .backgroundColor(p.bg)
            Column()
              .width(14)
              .height(14)
              .borderRadius(2)
              .backgroundColor(p.accent)
            Column()
              .width(44)
              .height(44)
              .borderRadius(22)
              .border({
                width: this.paletteIndex === idx ? 2 : 0,
                color: this.accent(),
              })
          }
          .width(44)
          .height(44)
          .margin(6)
          .onClick(() => {
            this.paletteIndex = idx;
          })
        }, (p: CoverPalette, idx: number) => p.name + idx.toString())
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  TextEditor() {
    Column({ space: 12 }) {
      Column({ space: 5 }) {
        Text('生字（1-12 个汉字）')
          .fontSize(12)
          .fontColor(this.labelColor())
        TextInput({ text: this.charsText })
          .height(40)
          .fontSize(16)
          .maxLength(CharCards.MAX_CHARS)
          .backgroundColor(this.inputBg())
          .borderRadius(8)
          .onChange((value: string) => {
            this.onCharsChange(value);
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.pinyinOn) {
        Column({ space: 5 }) {
          Text(this.pinyinLocked ? '拼音（已手动锁定）' : '拼音（自动生成，可修改）')
            .fontSize(12)
            .fontColor(this.labelColor())
          Row({ space: 8 }) {
            TextInput({ text: this.pinyinText })
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .maxLength(48)
              .backgroundColor(this.inputBg())
              .borderRadius(8)
              .onFocus(() => {
                this.pinyinFocused = true;
              })
              .onBlur(() => {
                this.pinyinFocused = false;
              })
              .onChange((value: string) => {
                if (this.pinyinFocused) {
                  this.pinyinText = value;
                  this.pinyinLocked = true;
                }
              })
            if (this.pinyinLocked) {
              Text('恢复自动')
                .fontSize(12)
                .fontColor(this.accent())
                .padding({ left: 10, right: 10, top: 9, bottom: 9 })
                .backgroundColor('#1AD8231A')
                .borderRadius(12)
                .onClick(() => {
                  this.resetPinyin();
                })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
  }

  @Builder
  HistorySection() {
    if (this.historyRecords.length > 0) {
      Column({ space: 8 }) {
        Row() {
          Text('最近制作')
            .fontSize(12)
            .fontColor(this.labelColor())
            .layoutWeight(1)
          Text('清空')
            .fontSize(12)
            .fontColor(this.labelColor())
            .padding(6)
            .onClick(() => {
              this.clearHistory();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        List({ space: 10 }) {
          ForEach(this.historyRecords, (r: CoverHistoryRecord) => {
            ListItem() {
              Column({ space: 4 }) {
                Image('file://' + CoverHistoryStore.filePath(this.context(), r.fileName, HISTORY_DIR))
                  .width(64)
                  .height(64)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(4)
                  .border({ width: 1, color: this.lineColor() })
                Text(this.historyLabel(r))
                  .fontSize(10)
                  .fontColor(this.labelColor())
                  .maxLines(1)
              }
              .alignItems(HorizontalAlign.Center)
              .onClick(() => {
                this.restoreFromHistory(r);
              })
            }
          }, (r: CoverHistoryRecord) => r.id)
        }
        .listDirection(Axis.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .height(92)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .padding({ top: 8 })
      .border({ width: { top: 1 }, color: this.lineColor() })
    }
  }

  private historyLabel(r: CoverHistoryRecord): string {
    let chars: string = '';
    try {
      let t: Record<string, Object> = JSON.parse(r.textsJson) as Record<string, Object>;
      chars = String(t['chars'] ?? '');
    } catch (e) {
      chars = '';
    }
    if (chars.length > 6) {
      chars = chars.substring(0, 6) + '…';
    }
    return chars;
  }

  @Builder
  ExportBar() {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Button(this.exporting ? '导出中…' : '保存到相册')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .backgroundColor(this.accent())
          .enabled(this.canExport() && !this.exporting && !this.batchRunning)
          .onClick(() => {
            this.doExport(true);
          })
        Button('分享')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .backgroundColor(this.chipBg())
          .fontColor(this.chipText())
          .enabled(this.canExport() && !this.exporting && !this.batchRunning)
          .onClick(() => {
            this.doExport(false);
          })
      }
      .width('100%')

      if (this.cleanChars().length >= 2) {
        Button(this.batchRunning ?
          '导出中 ' + this.batchProgress.toString() + ' / ' + this.batchTotal.toString() :
          '全部导出（每字一卡，共 ' + this.cleanChars().length.toString() + ' 张）')
          .width('100%')
          .height(42)
          .fontSize(14)
          .backgroundColor('#1AD8231A')
          .fontColor(this.accent())
          .enabled(!this.exporting && !this.batchRunning)
          .onClick(() => {
            this.doBatchExport();
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 12 })
    .border({ width: { top: 1 }, color: this.lineColor() })
  }
}
