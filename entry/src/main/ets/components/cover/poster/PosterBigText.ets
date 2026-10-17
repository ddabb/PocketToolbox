/**
 * 文案海报模板 · 大字金句组（1.4.7 P2-1 拆分自 CopyPosterPreview，1.4.8 批 6 分层精简）：
 * T4 大字冲击 / T19 撕纸拼贴 / T20 竖排标点 / T21 层叠色块；quoteLayout 为 T20 竖排内核。
 * 各模板拆装饰层（Decor：纯图形不读槽位）与内容层（Content：槽位排版），组合层保持树序。
 */
import { CopyPosterRatio } from '../../../model/CopyPosterModels';
import { PosterRenderCtx } from './PosterRenderCtx';
import { BodyBlock } from './PosterSharedBuilders';
import { PosterTypeset, PosterVerticalLayout } from '../../../core/cover/PosterTypeset';

// ---------- T4 大字冲击 ----------

/** T4 装饰层：右下大圆底衬，不含任何文案 */
@Builder
function ImpactDecor(c: PosterRenderCtx) {
  Circle({ width: c.f(420), height: c.f(420) })
    .fill(c.pal().block)
    .opacity(0.35)
    .position({ x: c.previewWidth - c.posX(260), y: c.h() - c.posY(300) })
}

/** T4 内容层：tag / body / 署名分隔线三段排布 */
@Builder
function ImpactContent(c: PosterRenderCtx) {
  Column({ space: c.f(24) }) {
    if (c.content.tag.trim() !== '') {
      Text(c.content.tag)
        .fontSize(c.f(26))
        .fontColor(c.pal().sub)
        .fontFamily(c.font())
        .fontWeight(FontWeight.Bold)
        .letterSpacing(c.f(8))
        .maxLines(1)
    }
    // 可用宽 = 900 - padding 56*2 = 788；预算留 2 行给署名分隔线
    BodyBlock(c, 110, true, true, 788, c.bodyBudget(2, true))
    if (c.content.sign.trim() !== '') {
      Column({ space: c.f(10) }) {
        Row().width(c.f(110)).height(c.f(2)).backgroundColor(c.pal().accent)
        Text(c.content.sign)
          .fontSize(c.f(28))
          .fontColor(c.pal().title)
          .fontFamily(c.font())
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Center)
    }
  }
  .width('100%')
  .height('100%')
  .justifyContent(FlexAlign.Center)
  .alignItems(HorizontalAlign.Center)
  .padding({ left: c.f(56), right: c.f(56), top: c.f(40), bottom: c.f(40) })
}

@Builder
export function BigImpact(c: PosterRenderCtx) {
  Stack() {
    ImpactDecor(c)
    ImpactContent(c)
  }
  .width('100%')
  .height('100%')
}

// ---------- T19 撕纸拼贴（大字金句 · 手撕边 + 胶带） ----------

/** T19 装饰层：两段斜向胶带 + 主体白纸块（带撕纸感），不含任何文案 */
@Builder
function TornDecor(c: PosterRenderCtx) {
  // 斜向胶带
  Column()
    .width(c.f(190))
    .height(c.f(46))
    .backgroundColor(c.hexA(c.pal().grid, '66'))
    .rotate({ angle: -6 })
    .position({ x: c.posX(70), y: c.posY(96) })
    .hitTestBehavior(HitTestMode.None)
  Column()
    .width(c.f(150))
    .height(c.f(46))
    .backgroundColor(c.hexA(c.pal().grid, '4D'))
    .rotate({ angle: 4 })
    .position({ x: c.previewWidth - c.posX(230), y: c.h() - c.posY(180) })
    .hitTestBehavior(HitTestMode.None)

  // 主体白纸块（带撕纸感：底边用两段错位的矩形拼出）
  Column()
    .width(c.previewWidth - c.f(96))
    .height(c.h() - c.fy(240) - c.fy(200))
    .backgroundColor(c.pal().block)
    .rotate({ angle: -1.2 })
    .position({ x: c.posX(48), y: c.posY(210) })
    .hitTestBehavior(HitTestMode.None)
}

/** T19 内容层：tag 强调条 / body / 署名三段排布 */
@Builder
function TornContent(c: PosterRenderCtx) {
  Column({ space: c.f(26) }) {
    if (c.content.tag.trim() !== '') {
      Row({ space: c.f(12) }) {
        Row().width(c.f(40)).height(c.f(4)).backgroundColor(c.pal().accent)
        Text(c.content.tag)
          .fontSize(c.f(28))
          .fontColor(c.pal().accent)
          .fontFamily(c.font())
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
      }
      .alignItems(VerticalAlign.Center)
    }
    // 满文案预算留 2 行给署名，避免署名被挤出撕纸画布
    BodyBlock(c, 96, true, true, 700, c.bodyBudget(2, true))
    if (c.content.sign.trim() !== '') {
      Text(c.content.sign)
        .fontSize(c.f(30))
        .fontColor(c.pal().sub)
        .fontFamily(c.font())
        .maxLines(1)
    }
  }
  .width('100%')
  .height('100%')
  .justifyContent(FlexAlign.Center)
  .alignItems(HorizontalAlign.Center)
  .padding({ left: c.f(100), right: c.f(100), top: c.f(60), bottom: c.f(60) })
}

@Builder
export function TornPaper(c: PosterRenderCtx) {
  Stack() {
    TornDecor(c)
    TornContent(c)
  }
  .width('100%')
  .height('100%')
}

// ---------- T20 竖排标点（大字金句 · 日式竖排 + 圆点） ----------

/**
 * T20 竖排内核（1.4.6 P0-1 A 类）：软预算 availH = 画布高 - 250（tag/署名/圆点让位，
 * Phase 0 spike 锁定）；硬上限 1:1 3 列 / 竖版 4 列；lh 1.32 / pitch 1.80。
 * 替代旧 boldPerCol/boldMaxCols/boldBodyPx 私有分档。
 */
function quoteLayout(c: PosterRenderCtx): PosterVerticalLayout {
  let dh: number = CopyPosterRatio.designHeight(c.ratioKind);
  let square: boolean = c.ratioKind === CopyPosterRatio.SQUARE;
  return PosterTypeset.layoutVertical(c.content.body, dh - 250, square ? 3 : 4,
    square ? 82 : 92, false, 1.32, 0, 1.80);
}

/** T20 装饰层：右侧竖线，不含任何文案 */
@Builder
function QuoteRule(c: PosterRenderCtx) {
  Column()
    .width(c.f(2))
    .height(c.h() * 0.58)
    .backgroundColor(c.pal().accent)
    .position({ x: c.previewWidth - c.posX(58), y: c.posY(190) })
    .hitTestBehavior(HitTestMode.None)
}

/** T20 内容层：tag / 竖排 body（含截断提示）/ 署名三段排布 */
@Builder
function QuoteContent(c: PosterRenderCtx) {
  Column({ space: c.f(30) }) {
    if (c.content.tag.trim() !== '') {
      Text(c.content.tag)
        .fontSize(c.f(24))
        .fontColor(c.pal().sub)
        .fontFamily(c.font())
        .letterSpacing(c.f(10))
        .maxLines(1)
    }
    if (c.content.body.trim() === '') {
      Text($r('app.string.poster_empty_hint'))
        .fontSize(c.f(28))
        .fontColor(c.pal().sub)
        .fontFamily(c.font())
        .textAlign(TextAlign.Center)
    } else {
      Row({ space: c.f(quoteLayout(c).fontPx * 0.8) }) {
        ForEach(c.vertRenderCols(quoteLayout(c).columns),
          (col: string[], i: number) => {
            Text(col.join('\n'))
              .fontSize(c.f(quoteLayout(c).fontPx))
              .lineHeight(c.f(quoteLayout(c).fontPx * 1.32))
              .fontColor(c.pal().title)
              .fontFamily(c.font())
              .fontWeight(FontWeight.Bold)
              .textAlign(TextAlign.Center)
          }, (col: string[], i: number) => 'vq-' + i.toString() + '-' + col.length.toString())
      }
      .alignItems(VerticalAlign.Top)
      if (quoteLayout(c).truncated && !c.isThumb) {
        Text($r('app.string.poster_truncated_hint', quoteLayout(c).truncatedChars))
          .fontSize(c.f(18))
          .fontColor(c.pal().sub)
          .fontFamily(c.font())
          .opacity(0.75)
          .maxLines(1)
      }
    }
    if (c.content.sign.trim() !== '') {
      Text('— ' + c.content.sign)
        .fontSize(c.f(26))
        .fontColor(c.pal().accent)
        .fontFamily(c.font())
        .maxLines(1)
    }
  }
  .width('100%')
  .height('100%')
  .justifyContent(FlexAlign.Center)
  .alignItems(HorizontalAlign.Center)
  .padding({ left: c.f(80), right: c.f(140) })
}

@Builder
export function VerticalQuote(c: PosterRenderCtx) {
  Stack() {
    QuoteRule(c)
    QuoteContent(c)
  }
  .width('100%')
  .height('100%')
}

// ---------- T21 层叠色块（大字金句 · 三色错位叠压） ----------

/** T21 装饰层：两块错位色块（accent / block 派生，营造印刷错版感），不含任何文案 */
@Builder
function BlocksDecor(c: PosterRenderCtx) {
  Column()
    .width(c.previewWidth - c.f(80))
    .height(c.h() - c.fy(300) - c.fy(240))
    .backgroundColor(c.pal().accent)
    .opacity(0.9)
    .rotate({ angle: -2.4 })
    .position({ x: c.posX(56), y: c.posY(230) })
    .hitTestBehavior(HitTestMode.None)
  Column()
    .width(c.previewWidth - c.f(80))
    .height(c.h() - c.fy(300) - c.fy(240))
    .backgroundColor(c.pal().block)
    .rotate({ angle: 1.8 })
    .position({ x: c.posX(46), y: c.posY(262) })
    .hitTestBehavior(HitTestMode.None)
}

/** T21 内容层：tag / body / 署名分隔线+署名（两段独立 if，保持既有树结构） */
@Builder
function BlocksContent(c: PosterRenderCtx) {
  Column({ space: c.f(24) }) {
    if (c.content.tag.trim() !== '') {
      Text(c.content.tag)
        .fontSize(c.f(26))
        .fontColor(c.pal().accent)
        .fontFamily(c.font())
        .fontWeight(FontWeight.Bold)
        .letterSpacing(c.f(6))
        .maxLines(1)
    }
    // 满文案预算留 2 行给署名分隔线/署名
    BodyBlock(c, 92, true, true, 660, c.bodyBudget(2, true))
    if (c.content.sign.trim() !== '') {
      Row().width(c.f(90)).height(c.f(3)).backgroundColor(c.pal().accent)
    }
    if (c.content.sign.trim() !== '') {
      Text(c.content.sign)
        .fontSize(c.f(26))
        .fontColor(c.pal().sub)
        .fontFamily(c.font())
        .maxLines(1)
    }
  }
  .width('100%')
  .height('100%')
  .justifyContent(FlexAlign.Center)
  .alignItems(HorizontalAlign.Center)
  .padding({ left: c.f(92), right: c.f(92), top: c.f(56), bottom: c.f(56) })
}

@Builder
export function ColorBlocks(c: PosterRenderCtx) {
  Stack() {
    BlocksDecor(c)
    BlocksContent(c)
  }
  .width('100%')
  .height('100%')
}
