/**
 * 文案海报模板 · 生活简约组（1.4.7 P2-1 拆分自 CopyPosterPreview）：
 * T1 暖调标签卡 / T2 纯色简约 / T3 文艺手写；TagPill 顶部装饰标签胶囊为本组局部子构建器。
 */
import { PosterRenderCtx } from './PosterRenderCtx';
import { BodyBlock } from './PosterSharedBuilders';

/** 顶部装饰标签胶囊（示例图 "pinyin" 位） */
@Builder
function TagPill(c: PosterRenderCtx) {
  if (c.content.tag.trim() !== '') {
    Text(c.content.tag)
      .fontSize(c.f(26))
      .fontColor('#FFFFFF')
      .fontFamily(c.font())
      .letterSpacing(c.f(2))
      .maxLines(1)
      .padding({ left: c.f(22), right: c.f(22), top: c.f(9), bottom: c.f(9) })
      .backgroundColor(c.pal().grid)
      .borderRadius(c.f(999))
  }
}

// ---------- T1 暖调标签卡（示例图同款） ----------

@Builder
export function WarmLabel(c: PosterRenderCtx) {
  Stack() {
    Circle({ width: c.f(320), height: c.f(320) })
      .fill(c.pal().block)
      .opacity(0.5)
      .position({ x: c.previewWidth - c.posX(150), y: c.h() - c.posY(240) })
    Column({ space: c.f(30) }) {
      TagPill(c)
      // 可用宽 = 900 - padding.left(70) - padding.right(70) = 760
      // 预算留 2 行给 dots/署名：走查发现 120 字满文案时署名被挤出画布
      BodyBlock(c, 72, false, false, 760, c.bodyBudget(2))
      Row({ space: c.f(10) }) {
        Circle({ width: c.f(10), height: c.f(10) }).fill(c.pal().accent)
        Row().width(c.f(64)).height(c.f(3)).borderRadius(c.f(2)).backgroundColor(c.pal().accent)
        Circle({ width: c.f(10), height: c.f(10) }).fill(c.pal().accent)
      }
      .alignItems(VerticalAlign.Center)
      if (c.content.sign.trim() !== '') {
        Text(c.content.sign)
          .fontSize(c.f(28))
          .fontColor(c.pal().sub)
          .fontFamily(c.font())
          .maxLines(1)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: c.f(70), right: c.f(70), top: c.f(50), bottom: c.f(50) })
  }
  .width('100%')
  .height('100%')
}

// ---------- T2 纯色简约 ----------

@Builder
export function PureMinimal(c: PosterRenderCtx) {
  Column({ space: c.f(26) }) {
    if (c.content.tag.trim() !== '') {
      Text(c.content.tag)
        .fontSize(c.f(24))
        .fontColor(c.pal().sub)
        .fontFamily(c.font())
        .letterSpacing(c.f(6))
        .maxLines(1)
    }
    Row().width(c.f(44)).height(c.f(5)).borderRadius(c.f(3)).backgroundColor(c.pal().accent)
    // 可用宽 = 900 - padding 64*2 = 772；预算留 2 行给署名
    BodyBlock(c, 60, false, false, 772, c.bodyBudget(2))
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
  .padding({ left: c.f(64), right: c.f(64), top: c.f(50), bottom: c.f(50) })
}

// ---------- T3 文艺手写 ----------

@Builder
export function Handwrite(c: PosterRenderCtx) {
  Stack() {
    Row()
      .width(c.f(14))
      .height(c.f(14))
      .backgroundColor(c.pal().accent)
      .opacity(0.7)
      .rotate({ angle: 45 })
      .position({ x: c.posX(40), y: c.posY(40) })
    Row()
      .width(c.f(14))
      .height(c.f(14))
      .backgroundColor(c.pal().accent)
      .opacity(0.7)
      .rotate({ angle: 45 })
      .position({ x: c.previewWidth - c.posX(54), y: c.h() - c.posY(54) })
    Column({ space: c.f(28) }) {
      if (c.content.tag.trim() !== '') {
        Row({ space: c.f(8) }) {
          Circle({ width: c.f(8), height: c.f(8) }).fill(c.pal().accent)
          Text(c.content.tag)
            .fontSize(c.f(24))
            .fontColor(c.pal().sub)
            .fontFamily(c.font())
            .maxLines(1)
        }
        .alignItems(VerticalAlign.Center)
      }
      // 可用宽 = 900 - padding 66*2 = 768；预算留 2 行给署名
      BodyBlock(c, 56, false, false, 768, c.bodyBudget(2))
      if (c.content.sign.trim() !== '') {
        Row({ space: c.f(10) }) {
          Row().width(c.f(26)).height(c.f(2)).backgroundColor(c.pal().accent)
          Text(c.content.sign)
            .fontSize(c.f(30))
            .fontColor(c.pal().title)
            .fontFamily(c.font())
            .maxLines(1)
        }
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: c.f(66), right: c.f(66), top: c.f(50), bottom: c.f(50) })
  }
  .width('100%')
  .height('100%')
}
