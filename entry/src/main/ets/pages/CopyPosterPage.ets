/**
 * 文案海报页面：预览 + 比例(1:1/3:4/9:16长图) + 模板分类选择(T1-T21) + 文字/样式编辑(含注音开关) + 换一句灵感 + 导出 + 历史
 * 需求文档：docs/文案海报生成器需求文档.md；1.4.4 计划：docs/1.4.4开发计划.md
 * 分类导航与模板优化：docs/文案海报优化计划.md（1.4.5）
 * 布局改版（1.4.7 A+B）：预览与三页签（文字/模板/样式）固定在面板 Scroll 之外，编辑面板独立滚动，预览常驻可见
 */
import { display } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CoverHistoryRecord } from '../model/CoverModels';
import {
  CopyPosterCategories,
  CopyPosterCategory,
  CopyPosterContent,
  CopyPosterRatio,
  CopyPosterSlot,
  CopyPosterSlotDef,
  CopyPosterTemplate
} from '../model/CopyPosterModels';
import { CopyPosterTemplates } from '../core/cover/CopyPosterTemplates';
import { PosterAvatarStore } from '../core/cover/PosterAvatarStore';
import { CoverContentUtil } from '../core/cover/CoverContentUtil';
import { CoverHistoryStore } from '../core/cover/CoverHistoryStore';
import { CopyPosterPreview } from '../components/cover/CopyPosterPreview';
import { CopyPosterStyleEditor } from '../components/cover/CopyPosterStyleEditor';
import { CopyPosterAvatarRow } from '../components/cover/CopyPosterAvatarRow';
import { CopyPosterHistorySection } from '../components/cover/CopyPosterHistorySection';
import { ChipRow } from '../components/template/ChipRow';
import { ChipOption } from '../core/template/UnifiedTemplateModels';
import { StickinessUtil } from '../common/utils/StickinessUtil';
import { FontUtil } from '../common/utils/FontUtil';
import { ToastUtil } from '../common/utils/ToastUtil';
import { StrUtil } from '../common/utils/StrUtil';
import { savePixelMapToAlbum, shareImageViaPanel } from '../common/utils/ShareImageUtil';
import { ClipboardFillUtil } from '../common/utils/ClipboardFillUtil';
import { CopyPosterCategoryUtil } from '../common/utils/CopyPosterCategoryUtil';
import { ClipboardHintBar } from '../components/ClipboardHintBar';

const PREVIEW_ID: string = 'copyposter_preview';
const INSPIRATION_COUNT: number = 60;

@Builder
export function CopyPosterPageBuilder() {
  NavDestination() {
    CopyPosterEditor()
  }
  .title($r('app.string.tool_poster_title'))
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct CopyPosterEditor {
  @State currentTemplateId: string = 'T1';
  @State ratioKind: string = CopyPosterRatio.SQUARE;
  @State content: CopyPosterContent = new CopyPosterContent();
  @State paletteIndex: number = 0;
  @State fontIndex: number = 0;
  @State pinyinOn: boolean = false;
  @State editorTab: number = 0;
  @State exporting: boolean = false;
  @State historyRecords: CoverHistoryRecord[] = [];
  @State showClipHint: boolean = false;
  /** 当前选中的模板分类 id（1.4.5 分类导航） */
  @State categoryId: string = CopyPosterCategories.SIMPLE;
  previewVp: number = 300;
  /** 屏幕密度（vp->px），透传给预览组件做 3D 透视 */
  densityPx: number = 3;
  /** 「换一句」已推荐文案（会话内去重） */
  private usedInspiration: Set<string> = new Set<string>();
  /**
   * 已编辑槽位（会话内追踪，不落盘，1.4.6 切换跟随）：
   * 切模板时未编辑（或已清空）的槽位跟随新模板默认值，已编辑且非空的槽位保留用户内容。
   */
  private editedSlots: Set<string> = new Set<string>();
  private ratioOptions: ChipOption[] = [
    ChipOption.of(CopyPosterRatio.SQUARE, CopyPosterRatio.label(CopyPosterRatio.SQUARE)),
    ChipOption.of(CopyPosterRatio.PORTRAIT, CopyPosterRatio.label(CopyPosterRatio.PORTRAIT)),
    ChipOption.of(CopyPosterRatio.LONG, CopyPosterRatio.label(CopyPosterRatio.LONG)),
  ];
  /** 分类 chips 选项（每项带该分类模板数，便于用户预判） */
  private categoryOptions: ChipOption[] = [];

  aboutToAppear(): void {
    FontUtil.registerAll(this.getUIContext());
    try {
      let d: display.Display = display.getDefaultDisplaySync();
      let density: number = d.densityPixels;
      let availVp: number = d.width / density - 32;
      this.previewVp = Math.min(900 / density, availVp);
      this.densityPx = density;
    } catch (e) {
      console.error('[CopyPoster] getDefaultDisplaySync failed: ' + (e as Error).message);
      this.previewVp = 360;
    }
    this.buildCategoryOptions();
    // 恢复上次选择的分类；无记录则用第一类。
    // 若当前模板不属于该分类，把分类对齐到模板所属分类，避免「模板不在当前列表」的空档
    let lastCat: string = CopyPosterCategoryUtil.loadLastCategory(this.context());
    this.categoryId = lastCat !== '' ? lastCat : CopyPosterCategories.SIMPLE;
    this.selectTemplate(CopyPosterTemplates.getById('T1'));
    if (CopyPosterCategories.categoryOfTemplate(this.currentTemplateId) !== this.categoryId) {
      this.categoryId = CopyPosterCategories.categoryOfTemplate(this.currentTemplateId);
    }
    this.historyRecords = CoverHistoryStore.loadRecords(this.context(), CoverHistoryStore.DIR_POSTER);
    this.showClipHint = ClipboardFillUtil.hasClipboardText();
  }

  /** 构建分类 chips：名称 + 该分类模板数（three 语） */
  private buildCategoryOptions(): void {
    let cats: CopyPosterCategory[] = CopyPosterCategories.all();
    let opts: ChipOption[] = [];
    for (let i = 0; i < cats.length; i++) {
      let count: number = CopyPosterCategories.templatesOf(cats[i], CopyPosterTemplates.all()).length;
      let label: string = StrUtil.text(this.context(), cats[i].name) + ' ' + count.toString();
      opts.push(ChipOption.of(cats[i].id, label));
    }
    this.categoryOptions = opts;
  }

  /** 切换分类：若当前模板不在该分类下，自动选中该分类第一个模板 */
  private onCategoryChange(catId: string): void {
    this.categoryId = catId;
    CopyPosterCategoryUtil.saveLastCategory(this.context(), catId);
    let cat: CopyPosterCategory = CopyPosterCategories.getById(catId);
    let list: CopyPosterTemplate[] = CopyPosterCategories.templatesOf(cat, CopyPosterTemplates.all());
    if (list.length === 0) {
      return;
    }
    let inThis: boolean = false;
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === this.currentTemplateId) {
        inThis = true;
        break;
      }
    }
    if (!inThis) {
      this.selectTemplate(list[0]);
    }
  }

  /** 当前分类下的模板列表 */
  private currentCategoryTemplates(): CopyPosterTemplate[] {
    return CopyPosterCategories.templatesOf(CopyPosterCategories.getById(this.categoryId),
      CopyPosterTemplates.all());
  }

  /** 剪贴板填入主文案：按上限截断后走既有 onSlotChange 管道，本会话不再提示 */
  private onClipFill(text: string): void {
    this.showClipHint = false;
    this.onSlotChange(CopyPosterSlot.BODY, text.substring(0, CopyPosterTemplates.MAX_BODY));
  }

  // ---------- 状态与业务 ----------

  private currentTemplate(): CopyPosterTemplate {
    return CopyPosterTemplates.getById(this.currentTemplateId);
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /** 预览渲染宽度：方图/竖图占满可用宽；9:16 长图同高变窄（宽 = 预览高 × 9/16，高与 3:4 持平） */
  private previewW(): number {
    return this.ratioKind === CopyPosterRatio.LONG ? this.previewVp * 0.75 : this.previewVp;
  }

  /** 组件快照缩放：保证导出宽恒 1080 像素精确（长图预览变窄后缩放同步增大） */
  private snapshotScaleFor(): number {
    return CopyPosterTemplates.EXPORT_W / (this.previewW() * this.densityPx);
  }

  /** 切换模板（1.4.6 切换跟随）：已编辑且非空的槽位保留用户内容，其余跟随新模板默认值 */
  private selectTemplate(t: CopyPosterTemplate): void {
    this.currentTemplateId = t.id;
    this.paletteIndex = 0;
    this.fontIndex = 0;
    let c: CopyPosterContent = this.content.copy();
    let d: Record<string, string> = t.defaults;
    if (!this.editedSlots.has(CopyPosterSlot.BODY) || c.body.trim() === '') {
      c.body = d['body'] ?? '';
    }
    if (!this.editedSlots.has(CopyPosterSlot.SIGN) || c.sign.trim() === '') {
      c.sign = d['sign'] ?? '';
    }
    if (!this.editedSlots.has(CopyPosterSlot.TAG) || c.tag.trim() === '') {
      c.tag = d['tag'] ?? '';
    }
    // 1.4.8 定制槽位默认跟随（对联上下联；无默认值的模板清空为 ''，与 body 行为一致）
    if (!this.editedSlots.has(CopyPosterSlot.COUPLET_UP) || c.coupletUp.trim() === '') {
      c.coupletUp = d['coupletUp'] ?? '';
    }
    if (!this.editedSlots.has(CopyPosterSlot.COUPLET_DOWN) || c.coupletDown.trim() === '') {
      c.coupletDown = d['coupletDown'] ?? '';
    }
    this.content = c;
  }

  private onSlotChange(slot: string, value: string): void {
    // 值未变化直接忽略：输入框初始渲染会触发一次 onChange，据此误标「已编辑」会让模板默认值跟随失效
    if (value === this.slotValueOf(slot)) {
      return;
    }
    let c: CopyPosterContent = this.content.copy();
    if (slot === CopyPosterSlot.BODY) {
      c.body = value;
    } else if (slot === CopyPosterSlot.SIGN) {
      c.sign = value;
    } else if (slot === CopyPosterSlot.TAG) {
      c.tag = value;
    } else if (slot === CopyPosterSlot.COUPLET_UP) {
      c.coupletUp = value;
    } else if (slot === CopyPosterSlot.COUPLET_DOWN) {
      c.coupletDown = value;
    } else {
      return;
    }
    this.editedSlots.add(slot);
    this.content = c;
  }

  /** 槽位标签语义化（1.4.8）：按模板返回语义标签，缺省回退通用标签 */
  private slotLabelFor(slot: string): ResourceStr {
    let tid: string = this.currentTemplateId;
    if (slot === CopyPosterSlot.BODY) {
      return tid === 'T12' ? $r('app.string.poster_slot_chat_msg') : $r('app.string.poster_slot_body');
    }
    if (slot === CopyPosterSlot.SIGN) {
      return tid === 'T12' ? $r('app.string.poster_slot_chat_reply') : $r('app.string.poster_slot_sign');
    }
    if (slot === CopyPosterSlot.TAG) {
      if (tid === 'T12') {
        return $r('app.string.poster_slot_chat_peer');
      }
      if (tid === 'T16') {
        return $r('app.string.poster_slot_solar_term');
      }
      if (tid === 'T18') {
        return $r('app.string.poster_slot_banner');
      }
      return $r('app.string.poster_slot_tag');
    }
    return $r('app.string.poster_slot_body');
  }

  /** 槽位当前值（基础与定制槽位统一入口；定制槽位 id 与 CopyPosterContent 字段名一致） */
  private slotValueOf(slot: string): string {
    if (slot === CopyPosterSlot.BODY) {
      return this.content.body;
    }
    if (slot === CopyPosterSlot.SIGN) {
      return this.content.sign;
    }
    if (slot === CopyPosterSlot.TAG) {
      return this.content.tag;
    }
    if (slot === CopyPosterSlot.COUPLET_UP) {
      return this.content.coupletUp;
    }
    if (slot === CopyPosterSlot.COUPLET_DOWN) {
      return this.content.coupletDown;
    }
    return '';
  }

  /** 水印开关：首次开启且文字为空时预填品牌文案；关闭仅停渲染，保留已输入文字 */
  private onWatermarkToggle(): void {
    let c: CopyPosterContent = this.content.copy();
    c.watermarkOn = !c.watermarkOn;
    if (c.watermarkOn && c.watermarkText.trim() === '') {
      c.watermarkText = StrUtil.text(this.context(), $r('app.string.poster_watermark_default'));
    }
    this.content = c;
  }

  private onWatermarkTextChange(value: string): void {
    let c: CopyPosterContent = this.content.copy();
    c.watermarkText = value;
    this.content = c;
  }

  /** T12 头像：选图拷贝入沙箱并替换（旧文件同步删除）；取消/失败保持原头像 */
  private async onPickAvatar(): Promise<void> {
    let old: string = this.content.avatarUri;
    let path: string = await PosterAvatarStore.pick(this.context());
    if (path === '') {
      return;
    }
    let c: CopyPosterContent = this.content.copy();
    c.avatarUri = path;
    this.content = c;
    if (old !== '') {
      PosterAvatarStore.remove(old);
    }
  }

  /** T12 头像：移除（删文件 + 清字段） */
  private onRemoveAvatar(): void {
    let old: string = this.content.avatarUri;
    if (old === '') {
      return;
    }
    let c: CopyPosterContent = this.content.copy();
    c.avatarUri = '';
    this.content = c;
    PosterAvatarStore.remove(old);
  }

  /** 换一句：自有内容库（诗词/成语/歇后语，出处入署名）+ 预置灵感文案，会话内去重 */
  private changeBody(): void {
    let context: common.UIAbilityContext = this.context();
    if (Math.random() < 0.5) {
      let kinds: string[] = ['poem', 'idiom', 'xiehouyu'];
      let kind: string = kinds[Math.floor(Math.random() * kinds.length)];
      let pick = CoverContentUtil.pickByKind(context, kind);
      if (pick !== null) {
        let c: CopyPosterContent = this.content.copy();
        c.body = pick.quote;
        c.sign = pick.source.length > CopyPosterTemplates.MAX_SIGN ?
          pick.source.substring(0, CopyPosterTemplates.MAX_SIGN) : pick.source;
        this.editedSlots.add(CopyPosterSlot.BODY);
        this.editedSlots.add(CopyPosterSlot.SIGN);
        this.content = c;
        return;
      }
    }
    let text: string = this.randomInspiration(context);
    if (text !== '') {
      let c: CopyPosterContent = this.content.copy();
      c.body = text;
      this.editedSlots.add(CopyPosterSlot.BODY);
      this.content = c;
      return;
    }
    ToastUtil.show(this.getUIContext(), $r('app.string.cover_pick_failed'), 1500);
  }

  private randomInspiration(context: common.UIAbilityContext): string {
    if (this.usedInspiration.size >= INSPIRATION_COUNT) {
      this.usedInspiration.clear();
    }
    for (let tries = 0; tries < INSPIRATION_COUNT + 10; tries++) {
      let idx: number = Math.floor(Math.random() * INSPIRATION_COUNT) + 1;
      let text: string = '';
      try {
        text = context.resourceManager.getStringByNameSync('poster_insp_' + idx.toString());
      } catch (e) {
        console.error('[CopyPoster] load inspiration failed: ' + (e as Error).message);
        return '';
      }
      if (text === '') {
        return '';
      }
      if (!this.usedInspiration.has(text)) {
        this.usedInspiration.add(text);
        return text;
      }
    }
    this.usedInspiration.clear();
    try {
      return context.resourceManager.getStringByNameSync('poster_insp_1');
    } catch (e) {
      return '';
    }
  }

  private restoreFromHistory(r: CoverHistoryRecord): void {
    let parts: string[] = r.templateId.split('|');
    let t: CopyPosterTemplate = CopyPosterTemplates.getById(parts.length > 0 ? parts[0] : 'T1');
    this.currentTemplateId = t.id;
    if (parts.length > 1) {
      this.ratioKind = parts[1];
    }
    this.pinyinOn = parts.length > 2 && parts[2] === 'py' && t.supportsPinyin;
    this.paletteIndex = r.paletteIndex;
    this.fontIndex = r.fontIndex;
    this.content = CopyPosterContent.fromJson(r.textsJson);
    // 头像文件失联回退首字渲染（不阻塞恢复）
    if (this.content.avatarUri !== '' && !PosterAvatarStore.exists(this.content.avatarUri)) {
      this.content.avatarUri = '';
    }
    // 历史恢复即用户内容：三槽全部标记已编辑，后续切模板不再覆盖
    this.editedSlots.add(CopyPosterSlot.BODY);
    this.editedSlots.add(CopyPosterSlot.SIGN);
    this.editedSlots.add(CopyPosterSlot.TAG);
    this.editedSlots.add(CopyPosterSlot.COUPLET_UP);
    this.editedSlots.add(CopyPosterSlot.COUPLET_DOWN);
    this.editorTab = 0;
    ToastUtil.show(this.getUIContext(), $r('app.string.cover_restored', StrUtil.text(this.context(), t.name)), 1200);
  }

  private clearHistory(): void {
    CoverHistoryStore.clearAll(this.context(), CoverHistoryStore.DIR_POSTER);
    this.historyRecords = [];
  }

  private canExport(): boolean {
    return this.content.body.trim() !== '';
  }

  private async doExport(save: boolean): Promise<void> {
    if (!this.canExport() || this.exporting) {
      return;
    }
    this.exporting = true;
    try {
      await new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, 150);
      });
      let uiCtx: UIContext = this.getUIContext();
      let snapshot = uiCtx.getComponentSnapshot();
      let pixelMap: image.PixelMap =
        await snapshot.get(PREVIEW_ID, { scale: this.snapshotScaleFor(), waitUntilRenderFinished: true });
      let packer: image.ImagePacker = image.createImagePacker();
      let context: common.UIAbilityContext = this.context();
      let fileName: string = 'poster_' + Date.now() + '.png';
      let filePath: string = context.cacheDir + '/' + fileName;
      let file: fs.File = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        await packer.packToFile(pixelMap, file.fd, { format: 'image/png', quality: 100 });
      } catch (e) {
        let err: BusinessError = e as BusinessError;
        console.error('[CopyPoster] packToFile failed: ' + err.message);
        throw new Error(err.message);
      } finally {
        fs.closeSync(file.fd);
        packer.release();
      }
      let record: CoverHistoryRecord = CoverHistoryRecord.of(
        Date.now().toString(36) + Math.floor(Math.random() * 1000).toString(),
        CoverHistoryStore.makeFileName(),
        this.currentTemplateId + '|' + this.ratioKind +
          (this.pinyinOn && this.currentTemplate().supportsPinyin ? '|py' : ''),
        this.paletteIndex, this.fontIndex, this.content.toJson(), Date.now());
      if (CoverHistoryStore.saveRecord(context, filePath, record, CoverHistoryStore.DIR_POSTER)) {
        this.historyRecords = CoverHistoryStore.loadRecords(context, CoverHistoryStore.DIR_POSTER);
      }
      StickinessUtil.recordPosterExport(context);
      if (save) {
        let ok: boolean = await savePixelMapToAlbum(uiCtx, pixelMap);
        ToastUtil.show(uiCtx, ok ? $r('app.string.md2_saved_to_album') : $r('app.string.char_save_cancelled'), 1500);
      } else {
        shareImageViaPanel(uiCtx, filePath);
      }
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[CopyPoster] export failed: ' + err.code + ' ' + err.message);
      ToastUtil.show(this.getUIContext(), $r('app.string.char_export_failed', err.message), 2000);
    }
    this.exporting = false;
  }

  // ---------- 主题色 ----------

  private inputBg(): ResourceColor {
    return $r('app.color.editor_input_bg');
  }

  private labelColor(): ResourceColor {
    return $r('app.color.editor_label_text');
  }

  private chipBg(): ResourceColor {
    return $r('app.color.editor_chip_bg');
  }

  private chipText(): ResourceColor {
    return $r('app.color.editor_chip_text');
  }

  private lineColor(): ResourceColor {
    return $r('app.color.editor_line');
  }

  // ---------- UI ----------

  // 1.4.7 A+B 布局改版：预览与页签固定在面板 Scroll 之外，预览常驻可见；
  // 编辑面板（页签内容 + 历史）独立滚动，保存/分享栏固定底部。
  build() {
    Column() {
      this.PreviewSection()
      this.EditorTabs()
      Scroll() {
        Column({ space: 14 }) {
          if (this.editorTab === 0) {
            if (this.showClipHint && this.currentTemplate().customSlots.length === 0) {
              ClipboardHintBar({
                onFill: (text: string) => {
                  this.onClipFill(text);
                },
                onDismiss: () => {
                  this.showClipHint = false;
                },
              })
            }
            this.TextEditor()
          } else if (this.editorTab === 1) {
            this.RatioChips()
            this.TemplateScroller()
          } else {
            CopyPosterStyleEditor({
              palettes: this.currentTemplate().palettes,
              fonts: this.currentTemplate().fonts,
              supportsPinyin: this.currentTemplate().supportsPinyin,
              paletteIndex: this.paletteIndex,
              fontIndex: this.fontIndex,
              pinyinOn: this.pinyinOn,
              watermarkOn: this.content.watermarkOn,
              watermarkText: this.content.watermarkText,
              onPaletteSelect: (idx: number) => {
                this.paletteIndex = idx;
              },
              onFontSelect: (idx: number) => {
                this.fontIndex = idx;
              },
              onPinyinToggle: () => {
                this.pinyinOn = !this.pinyinOn;
              },
              onWatermarkToggle: () => {
                this.onWatermarkToggle();
              },
              onWatermarkTextChange: (value: string) => {
                this.onWatermarkTextChange(value);
              },
            })
          }
          CopyPosterHistorySection({
            historyRecords: this.historyRecords,
            onRestore: (r: CoverHistoryRecord) => {
              this.restoreFromHistory(r);
            },
            onClear: () => {
              this.clearHistory();
            },
          })
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
    .constraintSize({ maxWidth: 760 })
  }

  @Builder
  PreviewSection() {
    Column({ space: 8 }) {
      Row() {
        Column() {
          CopyPosterPreview({
            template: this.currentTemplate(),
            content: this.content,
            paletteIndex: this.paletteIndex,
            fontIndex: this.fontIndex,
            ratioKind: this.ratioKind,
            previewWidth: this.previewW(),
            density: this.densityPx,
            pinyinOn: this.pinyinOn,
          })
        }
        .width(this.previewW())
        .height(this.previewW() * CopyPosterRatio.designHeight(this.ratioKind) / 900)
        .clip(true)
        .id(PREVIEW_ID)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Text($r('app.string.char_export_size',
        StrUtil.text(this.context(), CopyPosterRatio.label(this.ratioKind)),
        CopyPosterTemplates.EXPORT_W, CopyPosterRatio.exportHeight(this.ratioKind)))
        .fontSize(11)
        .fontColor(this.labelColor())
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
  }

  @Builder
  RatioChips() {
    ChipRow({
      label: StrUtil.text(this.context(), $r('app.string.poster_label_ratio')),
      labelColor: this.labelColor(),
      options: this.ratioOptions,
      selected: this.ratioKind,
      accent: $r('app.color.brand_blue'),
      chipBg: this.chipBg(),
      chipText: this.chipText(),
      onSelect: (value: string) => {
        this.ratioKind = value;
      },
    })
  }

  /**
   * 单个模板缩略图（横滑条与网格共用）
   * 缩略图用当前用户内容实时渲染，提升模板切换转化。
   */
  @Builder
  TemplateThumb(t: CopyPosterTemplate) {
    Column({ space: 5 }) {
      Column() {
        CopyPosterPreview({
          template: t,
          content: this.content,
          paletteIndex: this.currentTemplateId === t.id ? this.paletteIndex : 0,
          fontIndex: this.currentTemplateId === t.id ? this.fontIndex : 0,
          ratioKind: CopyPosterRatio.SQUARE,
          previewWidth: 96,
          density: this.densityPx,
          showWatermark: false,
          isThumb: true,
        })
      }
      .width(96)
      .height(96)
      .clip(true)
      .borderRadius(8)
      .border({
        width: this.currentTemplateId === t.id ? 2 : 1,
        color: this.currentTemplateId === t.id ? $r('app.color.brand_blue') : this.lineColor(),
      })
      .onClick(() => {
        this.selectTemplate(t);
      })

      Text(StrUtil.text(this.context(), t.name))
        .fontSize(10)
        .fontColor(this.currentTemplateId === t.id ? $r('app.color.brand_blue') : this.labelColor())
        .maxLines(1)
    }
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 模板区：顶部分类 chips + 下方模板列表。
   * 1.4.5 分类导航：原来 18 个模板平铺，一屏仅 3-4 个需横滑 5 次；
   * 分类后每类 3-6 个，仍超一屏时横滑；不多于一屏时改网格铺满，避免「3 个模板还要横滑」。
   */
  @Builder
  TemplateScroller() {
    Column({ space: 8 }) {
      // 1.4.5 真机走查修复：分类 chips 共 5 类总宽超出屏宽，ChipRow 根为不可滚动的 Row，
      // 第 5 类「节日节气」被屏幕右缘裁掉、T16-T18 无法选择。
      // 包一层横向 Scroll（同 CoverMakerPage.SeriesChips 模式）即可滚动可达。
      Scroll() {
        Column() {
          ChipRow({
            label: '',
            labelColor: this.labelColor(),
            options: this.categoryOptions,
            selected: this.categoryId,
            accent: $r('app.color.brand_blue'),
            chipBg: this.chipBg(),
            chipText: this.chipText(),
            onSelect: (value: string) => {
              this.onCategoryChange(value);
            },
          })
        }
        .padding({ right: 12 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      if (this.currentCategoryTemplates().length <= 4) {
        // 该类模板不多于一屏：每行 4 个网格铺满，省掉横滑动作
        // 用 Row 均分而非 Flex+LengthMetrics：工程内未使用过 LengthMetrics，避免 API 可用性风险
        Column({ space: 10 }) {
          Row({ space: 10 }) {
            ForEach(this.currentCategoryTemplates(), (t: CopyPosterTemplate) => {
              this.TemplateThumb(t)
            }, (t: CopyPosterTemplate) => t.id)
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
        }
        .width('100%')
      } else {
        List({ space: 10 }) {
          ForEach(this.currentCategoryTemplates(), (t: CopyPosterTemplate) => {
            ListItem() {
              this.TemplateThumb(t)
            }
          }, (t: CopyPosterTemplate) => t.id)
        }
        .listDirection(Axis.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .height(126)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
  }

  @Builder
  EditorTabs() {
    Row({ space: 0 }) {
      ForEach([0, 1, 2], (idx: number) => {
        Text(this.tabLabel(idx))
          .fontSize(14)
          .fontWeight(this.editorTab === idx ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.editorTab === idx ? $r('app.color.brand_blue') : this.labelColor())
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .onClick(() => {
            this.editorTab = idx;
          })
      }, (idx: number) => idx.toString())
    }
    .width('100%')
    .border({ width: { bottom: 1 }, color: this.lineColor() })
  }

  /** 页签文案：0 文字 / 1 模板 / 2 样式（1.4.7 三页签改版） */
  private tabLabel(idx: number): ResourceStr {
    if (idx === 0) {
      return $r('app.string.cover_tab_text');
    }
    if (idx === 1) {
      return $r('app.string.cover_tab_template');
    }
    return $r('app.string.cover_tab_style');
  }

  @Builder
  TextEditor() {
    Column({ space: 12 }) {
      if (this.currentTemplate().supportsAvatar) {
        CopyPosterAvatarRow({
          avatarUri: this.content.avatarUri,
          onPick: () => {
            this.onPickAvatar();
          },
          onRemove: () => {
            this.onRemoveAvatar();
          },
        })
      }
      if (this.currentTemplate().customSlots.length > 0) {
        // 1.4.8 定制槽位（对联上下联）：隐藏换一句与主文案，渲染模板声明的定制输入
        ForEach(this.currentTemplate().customSlots, (def: CopyPosterSlotDef) => {
          Column({ space: 5 }) {
            Text(def.label)
              .fontSize(12)
              .fontColor(this.labelColor())
            TextInput({ text: this.slotValueOf(def.id) })
              .height(40)
              .fontSize(14)
              .maxLength(def.maxLen)
              .backgroundColor(this.inputBg())
              .borderRadius(8)
              .onChange((value: string) => {
                this.onSlotChange(def.id, value);
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }, (def: CopyPosterSlotDef) => def.id + this.currentTemplateId)
      } else {
        Row() {
          Text($r('app.string.poster_insp_label'))
            .fontSize(12)
            .fontColor(this.labelColor())
            .layoutWeight(1)
          Text($r('app.string.cover_change_quote'))
            .fontSize(13)
            .fontColor($r('app.color.idiom_blue'))
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .backgroundColor($r('app.color.brand_blue_tint'))
            .borderRadius(14)
            .onClick(() => {
              this.changeBody();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Column({ space: 5 }) {
          Text(this.slotLabelFor(CopyPosterSlot.BODY))
            .fontSize(12)
            .fontColor(this.labelColor())
          TextArea({ text: this.content.body, placeholder: $r('app.string.poster_body_hint') })
            .height(88)
            .fontSize(15)
            .maxLength(CopyPosterTemplates.MAX_BODY)
            .backgroundColor(this.inputBg())
            .borderRadius(8)
            .onChange((value: string) => {
              this.onSlotChange(CopyPosterSlot.BODY, value);
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      Row({ space: 12 }) {
        Column({ space: 5 }) {
          Text(this.slotLabelFor(CopyPosterSlot.SIGN))
            .fontSize(12)
            .fontColor(this.labelColor())
          TextInput({ text: this.content.sign, placeholder: $r('app.string.poster_sign_hint') })
            .height(40)
            .fontSize(14)
            .maxLength(CopyPosterTemplates.MAX_SIGN)
            .backgroundColor(this.inputBg())
            .borderRadius(8)
            .onChange((value: string) => {
              this.onSlotChange(CopyPosterSlot.SIGN, value);
            })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 5 }) {
          Text(this.slotLabelFor(CopyPosterSlot.TAG))
            .fontSize(12)
            .fontColor(this.labelColor())
          TextInput({ text: this.content.tag, placeholder: $r('app.string.poster_tag_hint') })
            .height(40)
            .fontSize(14)
            .maxLength(CopyPosterTemplates.MAX_TAG)
            .backgroundColor(this.inputBg())
            .borderRadius(8)
            .onChange((value: string) => {
              this.onSlotChange(CopyPosterSlot.TAG, value);
            })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .padding({ top: 12 })
  }

  @Builder
  ExportBar() {
    Row({ space: 12 }) {
      Button(this.exporting ? $r('app.string.char_exporting') : $r('app.string.char_save_album'))
        .layoutWeight(1)
        .height(44)
        .fontSize(15)
        .backgroundColor($r('app.color.brand_blue'))
        .enabled(this.canExport() && !this.exporting)
        .onClick(() => {
          this.doExport(true);
        })
      Button($r('app.string.md2_share'))
        .layoutWeight(1)
        .height(44)
        .fontSize(15)
        .backgroundColor(this.chipBg())
        .fontColor(this.chipText())
        .enabled(this.canExport() && !this.exporting)
        .onClick(() => {
          this.doExport(false);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 12 })
    .border({ width: { top: 1 }, color: this.lineColor() })
  }
}
