/**
 * 文案海报预览渲染组件（门面）：设计稿 900 宽（1:1 -> 900 高 / 3:4 -> 1200 高 / 9:16 -> 1600 高），21 种布局
 * 尺寸换算：f(px) = previewWidth * px / 900；主文案按长度分档自动缩字号（emoji 走系统字体兜底）
 * 注音开关（pinyinOn）：逐字拼音列（汉字单字带拼音、非汉字整段不注），字号按预算公式收缩防溢出
 *
 * 1.4.7 P2-1 拆分：21 模板按主题分置 poster/ 目录 7 组文件（全局 @Builder），本门面保留分发、背景层与水印层。
 * 1.4.7 修复回归：本门面按 PosterRenderCtx 接口形状提供全部成员并作为 ctx 实参传入——原 makeCtx() 快照传参不在 V1
 * 追踪图内，内容/水印/配色编辑后预览冻结；改为门面直读 @Prop 后恢复 1.4.6 单体的逐作用域刷新语义。
 */
import { CopyPosterContent, CopyPosterRatio, CopyPosterTemplate } from '../../model/CopyPosterModels';
import { CoverPalette } from '../../model/CoverModels';
import { PosterLayout, PosterTypeset } from '../../core/cover/PosterTypeset';
import { PY_SHRINK } from './poster/PosterRenderCtx';
import { WarmLabel, PureMinimal, Handwrite } from './poster/PosterSimple';
import { BigImpact, TornPaper, VerticalQuote, ColorBlocks } from './poster/PosterBigText';
import { LcdPixel, CrtTerminal, HandheldConsole } from './poster/PosterScreens';
import { NeonSign, SplitFlap } from './poster/PosterSignBoards';
import { VintageTicket, VintageNews, CorkNotice } from './poster/PosterPaperVintage';
import { ChatBubbles, VinylRecord, CinemaCard } from './poster/PosterMediaDaily';
import { SolarTerm, FestivalGreet, RedCouplet } from './poster/PosterFestival';

@Component
export struct CopyPosterPreview {
  @Prop template: CopyPosterTemplate;
  @Prop content: CopyPosterContent;
  @Prop paletteIndex: number;
  @Prop fontIndex: number;
  @Prop ratioKind: string;
  @Prop previewWidth: number;
  /** 屏幕密度（vp->px），T5 的 3D 透视按 px 计 */
  @Prop density: number;
  /** 主文案拼音注音开关（固定构图模板不生效） */
  @Prop pinyinOn: boolean = false;
  /** 是否渲染根层水印（主预览/导出开，模板缩略图关防糊点） */
  @Prop showWatermark: boolean = true;
  /**
   * 是否为模板选择器的缩略图渲染（96px 见方）。
   * 1.4.5 P2-6：T16/T17/T18 在 96px 下细节层会糊成噪点，缩略图模式需精简装饰层、
   * 突出主形，保证小尺寸下仍可辨识。关闭时行为与优化前完全一致。
   */
  @Prop isThumb: boolean = false;

  /**
   * 最近一次 bodyFont 调用（走内核时）的排版结果，供 truncatedHint 显示「已省略 N 字」提示。
   * 未启用内核（availWidthPx <= 0）时为 null，此时不显示提示，保持优化前行为。
   */
  private layoutCache: PosterLayout | null = null;

  build() {
    Stack() {
      this.PosterLayers()
    }
    .width(this.previewWidth)
    .height(this.h())
    .clip(true)
  }

  /** 背景层 + 21 模板分发 + 水印层（门面自身作 ctx：所有读取落在 @Prop getter，逐作用域刷新） */
  @Builder
  PosterLayers() {
    this.BgLayer()
    if (this.template.layout === 'warm_label') {
      WarmLabel(this)
    } else if (this.template.layout === 'pure_minimal') {
      PureMinimal(this)
    } else if (this.template.layout === 'handwrite') {
      Handwrite(this)
    } else if (this.template.layout === 'lcd_pixel') {
      LcdPixel(this)
    } else if (this.template.layout === 'crt_terminal') {
      CrtTerminal(this)
    } else if (this.template.layout === 'neon_sign') {
      NeonSign(this)
    } else if (this.template.layout === 'handheld_console') {
      HandheldConsole(this)
    } else if (this.template.layout === 'vintage_ticket') {
      VintageTicket(this)
    } else if (this.template.layout === 'split_flap') {
      SplitFlap(this)
    } else if (this.template.layout === 'vintage_news') {
      VintageNews(this)
    } else if (this.template.layout === 'chat_bubbles') {
      ChatBubbles(this)
    } else if (this.template.layout === 'vinyl_record') {
      VinylRecord(this)
    } else if (this.template.layout === 'cinema_card') {
      CinemaCard(this)
    } else if (this.template.layout === 'cork_notice') {
      CorkNotice(this)
    } else if (this.template.layout === 'solar_term') {
      SolarTerm(this)
    } else if (this.template.layout === 'festival_greet') {
      FestivalGreet(this)
    } else if (this.template.layout === 'red_couplet') {
      RedCouplet(this)
    } else if (this.template.layout === 'torn_paper') {
      TornPaper(this)
    } else if (this.template.layout === 'vertical_quote') {
      VerticalQuote(this)
    } else if (this.template.layout === 'color_blocks') {
      ColorBlocks(this)
    } else {
      BigImpact(this)
    }
    if (this.showWatermark && this.content.watermarkOn && this.content.watermarkText.trim() !== '') {
      this.WatermarkLayer()
    }
  }

  @Builder
  BgLayer() {
    if (this.pal().bg2 !== '') {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({ angle: 135, colors: [[this.pal().bg, 0.0], [this.pal().bg2, 1.0]] })
    } else {
      Column().width('100%').height('100%').backgroundColor(this.pal().bg)
    }
  }

  /** 根层水印：右下角小字（模板无关，palette title 色 50% 透明，21 布局一次生效） */
  @Builder
  WatermarkLayer() {
    Column() {
      Blank()
      Row() {
        Blank()
        Text(this.content.watermarkText.trim())
          .fontSize(this.f(22))
          .fontColor(this.hexA(this.pal().title, '80'))
          .maxLines(1)
      }
      .width('100%')
      .padding({ right: this.f(24), bottom: this.f(18) })
    }
    .width('100%')
    .height('100%')
  }

  /** 设计稿 px -> vp */
  f(px: number): number {
    return this.previewWidth * px / 900;
  }

  h(): number {
    return this.previewWidth * CopyPosterRatio.designHeight(this.ratioKind) / 900;
  }

  /** 定位专用：设计稿 x（宽 900 基准）→ vp，仅作 .position 的 x 实参 */
  posX(px: number): number {
    return this.previewWidth * px / 900;
  }

  /** 定位专用：设计稿 y（高 900 基准）→ vp，仅作 .position 的 y 实参 */
  posY(py: number): number {
    return this.h() * py / 900;
  }

  pal(): CoverPalette {
    let list: CoverPalette[] = this.template.palettes;
    if (this.paletteIndex >= 0 && this.paletteIndex < list.length) {
      return list[this.paletteIndex];
    }
    return list[0];
  }

  font(): string {
    let list: string[] = this.template.fonts;
    if (this.fontIndex >= 0 && this.fontIndex < list.length) {
      return list[this.fontIndex];
    }
    return list.length > 0 ? list[0] : '';
  }

  /** 主文案有效字数（去空白） */
  bodyLen(): number {
    return this.content.body.replace(new RegExp('\\s', 'g'), '').length;
  }

  /**
   * 主文案字号。
   *
   * 兼容说明（1.4.5 文案海报优化 P0-2）：
   *   - availWidthPx 为可选参数。未传（<=0）时行为与优化前完全一致，走原 5 档阶梯；
   *     这样 18 个 Builder 调用点可分批迁移，任一中途状态工程都可编译可运行。
   *   - 传入容器可用宽度（设计稿 px）后，改由 PosterTypeset 内核按「宽度 + 行数预算」连续计算，
   *     消除 32→33 字的字号骤变，并让窄容器（T1 pad70）不再顶格、宽容器（T10 pad24）不再显小。
   *
   * @param basePx        该模板的基准字号（设计稿 px）
   * @param big           是否大字模板
   * @param availWidthPx  容器可用宽度（设计稿 px）。<=0 表示不启用内核
   * @param maxLines      行数预算覆盖（>0 生效）。用于两类场景：
   *                      1) 渲染 maxLines 与内核预算错配的模板（T7 渲染 3 行但内核按 8/12 行算字）；
   *                      2) 主文案与署名/dots 同列纵向排布的模板预留行数，避免满文案把署名挤出画布。
   */
  bodyFont(basePx: number, big: boolean, availWidthPx: number = 0, maxLines: number = 0): number {
    if (availWidthPx > 0) {
      let budget: number = maxLines > 0 ? maxLines : this.maxBodyLines(big);
      let layout: PosterLayout = PosterTypeset.layout(
        this.content.body, availWidthPx, budget, basePx, big);
      // 内核 fontPx 是设计稿 px（相对 900 宽），渲染前必须经 f() 缩放到实际预览尺寸；
      // 漏掉这步会把字号直接当 fp 用（放大 ~900/previewWidth 倍），行数膨胀把署名挤出画布。
      let px: number = this.f(layout.fontPx);
      this.layoutCache = layout;
      return this.pyEnabled() ? px * PY_SHRINK : px;
    }
    let n: number = this.bodyLen();
    let s: number;
    if (big) {
      if (n <= 4) {
        s = this.f(150);
      } else if (n <= 8) {
        s = this.f(112);
      } else if (n <= 16) {
        s = this.f(80);
      } else {
        s = this.f(52);
      }
    } else if (n <= 8) {
      s = this.f(basePx);
    } else if (n <= 16) {
      s = this.f(basePx * 0.8);
    } else if (n <= 32) {
      s = this.f(basePx * 0.62);
    } else if (n <= 60) {
      s = this.f(basePx * 0.48);
    } else {
      s = this.f(basePx * 0.38);
    }
    this.layoutCache = null;
    return this.pyEnabled() ? s * PY_SHRINK : s;
  }

  /** 主文案行数上限：竖图更宽容 */
  maxBodyLines(big: boolean): number {
    if (big && this.bodyLen() <= 16) {
      return 4;
    }
    return this.ratioKind === CopyPosterRatio.SQUARE ? 8 : 12;
  }

  /**
   * 长文案行数预算预留（1.4.5 真机走查 P1）：主文案与署名/dots/tag 同列纵向排布的模板，
   * 满文案（8/12 行）会把署名挤出画布（T1 走查：120 字时署名从 dump 消失）。
   * 从预算里预留 reserve 行给兄弟元素；紧凑块（大字短文案 ≤4 行）本就克制，不压缩。
   */
  bodyBudget(reserve: number, big: boolean = false): number {
    let max: number = this.maxBodyLines(big);
    if (max <= 4) {
      return max;
    }
    return Math.max(3, max - reserve);
  }

  /** 注音是否生效：开关开 + 模板支持 + 主文案非空 */
  pyEnabled(): boolean {
    return this.pinyinOn && this.template.supportsPinyin && this.content.body.trim() !== '';
  }

  /** 注音模式字/拼音阴影：neon=霓虹三层 / soft=荧光单层 / none=无（透明零半径兜底保持数组非空） */
  pyShadow(glow: string): ShadowOptions[] {
    if (glow === 'neon') {
      return [
        { radius: this.f(4), color: '#FFFFFFFF', offsetX: 0, offsetY: 0 },
        { radius: this.f(10), color: this.hexA(this.pal().accent, '#E6'), offsetX: 0, offsetY: 0 },
        { radius: this.f(26), color: this.hexA(this.pal().accent, '#8C'), offsetX: 0, offsetY: 0 },
      ];
    }
    if (glow === 'soft') {
      return [{ radius: this.f(3), color: this.hexA(this.pal().accent, '#B3'), offsetX: 0, offsetY: 0 }];
    }
    return [{ radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 }];
  }

  /**
   * 截断提示字数：仅在启用内核（availWidthPx > 0）且判定为截断时返回，其余返回 0（不显示提示）。
   * 需在 bodyFont 调用之后取值（layoutCache 由 bodyFont 写入）。
   */
  truncatedHint(): number {
    let cache: PosterLayout | null = this.layoutCache;
    if (cache !== null && cache.truncated && cache.truncatedChars > 0) {
      return cache.truncatedChars;
    }
    return 0;
  }

  /** 竖排列渲染序：内核返回阅读序（首列在前），渲染需首列在最右，反转并滤空列 */
  vertRenderCols(cols: string[][]): string[][] {
    let out: string[][] = [];
    for (let i = cols.length - 1; i >= 0; i--) {
      if (cols[i].length > 0) {
        out.push(cols[i]);
      }
    }
    return out;
  }

  /** 任意色加透明度前缀（如 hexA('#FF4FD8', '#80') -> '#80FF4FD8'；alpha 也接受不带 # 的 '80'） */
  hexA(color: string, alphaHex: string): string {
    let a: string = alphaHex.startsWith('#') ? alphaHex.substring(1) : alphaHex;
    return '#' + a + color.substring(1);
  }

  /** 设计稿 y（1:1 基准 900 高）按实际画布高换算，3:4 时按比例下沉 */
  fy(py: number): number {
    return this.h() * py / 900;
  }
}
