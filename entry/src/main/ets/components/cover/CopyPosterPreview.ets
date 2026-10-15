/**
 * 文案海报预览渲染组件（门面）：设计稿 900 宽（1:1 -> 900 高 / 3:4 -> 1200 高 / 9:16 -> 1600 高），21 种布局
 * 尺寸换算：f(px) = previewWidth * px / 900；主文案按长度分档自动缩字号（emoji 走系统字体兜底）
 * 注音开关（pinyinOn）：逐字拼音列（汉字单字带拼音、非汉字整段不注），字号按预算公式收缩防溢出
 *
 * 1.4.7 P2-1 拆分：21 模板按主题分置 poster/ 目录 7 组文件（全局 @Builder + PosterRenderCtx 上下文），
 * 本门面仅保留 build() 分发、背景层与水印层，行为零变化。
 */
import { CopyPosterContent, CopyPosterTemplate } from '../../model/CopyPosterModels';
import { PosterRenderCtx } from './poster/PosterRenderCtx';
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

  build() {
    Stack() {
      this.PosterLayers(this.makeCtx())
    }
    .width(this.previewWidth)
    .height(this.makeCtx().h())
    .clip(true)
  }

  /** 每次渲染新建上下文（不跨渲染缓存）；高度实例与内容实例互不影响（h() 为纯计算） */
  private makeCtx(): PosterRenderCtx {
    return new PosterRenderCtx(this.template, this.content, this.paletteIndex, this.fontIndex,
      this.ratioKind, this.previewWidth, this.density, this.pinyinOn, this.isThumb);
  }

  /** 背景层 + 21 模板分发 + 水印层（同一 ctx 实例贯穿单次渲染，保证排版缓存有效） */
  @Builder
  PosterLayers(c: PosterRenderCtx) {
    this.BgLayer(c)
    if (this.template.layout === 'warm_label') {
      WarmLabel(c)
    } else if (this.template.layout === 'pure_minimal') {
      PureMinimal(c)
    } else if (this.template.layout === 'handwrite') {
      Handwrite(c)
    } else if (this.template.layout === 'lcd_pixel') {
      LcdPixel(c)
    } else if (this.template.layout === 'crt_terminal') {
      CrtTerminal(c)
    } else if (this.template.layout === 'neon_sign') {
      NeonSign(c)
    } else if (this.template.layout === 'handheld_console') {
      HandheldConsole(c)
    } else if (this.template.layout === 'vintage_ticket') {
      VintageTicket(c)
    } else if (this.template.layout === 'split_flap') {
      SplitFlap(c)
    } else if (this.template.layout === 'vintage_news') {
      VintageNews(c)
    } else if (this.template.layout === 'chat_bubbles') {
      ChatBubbles(c)
    } else if (this.template.layout === 'vinyl_record') {
      VinylRecord(c)
    } else if (this.template.layout === 'cinema_card') {
      CinemaCard(c)
    } else if (this.template.layout === 'cork_notice') {
      CorkNotice(c)
    } else if (this.template.layout === 'solar_term') {
      SolarTerm(c)
    } else if (this.template.layout === 'festival_greet') {
      FestivalGreet(c)
    } else if (this.template.layout === 'red_couplet') {
      RedCouplet(c)
    } else if (this.template.layout === 'torn_paper') {
      TornPaper(c)
    } else if (this.template.layout === 'vertical_quote') {
      VerticalQuote(c)
    } else if (this.template.layout === 'color_blocks') {
      ColorBlocks(c)
    } else {
      BigImpact(c)
    }
    if (this.showWatermark && this.content.watermarkOn && this.content.watermarkText.trim() !== '') {
      this.WatermarkLayer(c)
    }
  }

  @Builder
  BgLayer(c: PosterRenderCtx) {
    if (c.pal().bg2 !== '') {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({ angle: 135, colors: [[c.pal().bg, 0.0], [c.pal().bg2, 1.0]] })
    } else {
      Column().width('100%').height('100%').backgroundColor(c.pal().bg)
    }
  }

  /** 根层水印：右下角小字（模板无关，palette title 色 50% 透明，21 布局一次生效） */
  @Builder
  WatermarkLayer(c: PosterRenderCtx) {
    Column() {
      Blank()
      Row() {
        Blank()
        Text(c.content.watermarkText.trim())
          .fontSize(c.f(22))
          .fontColor(c.hexA(c.pal().title, '80'))
          .maxLines(1)
      }
      .width('100%')
      .padding({ right: c.f(24), bottom: c.f(18) })
    }
    .width('100%')
    .height('100%')
  }
}
