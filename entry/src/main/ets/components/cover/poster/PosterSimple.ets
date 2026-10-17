/**
 * 文案海报模板 · 生活简约组（1.4.7 P2-1 拆分自 CopyPosterPreview，1.4.8 批 7 分层精简）：
 * T1 暖调标签卡 / T2 纯色简约 / T3 文艺手写。
 * 各模板拆装饰层（Decor：纯图形不读槽位）与内容层（Content：槽位排版），组合层保持树序；
 * TagPill / WarmDots / MinimalDash / SignDash 为组内局部子构建器。
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

/** T1 装饰层：右下大圆底衬，不含任何文案 */
@Builder
function WarmDecor(c: PosterRenderCtx) {
  Circle({ width: c.f(320), height: c.f(320) })
    .fill(c.pal().block)
    .opacity(0.5)
    .position({ x: c.previewWidth - c.posX(150), y: c.h() - c.posY(240) })
}

/** T1 内容层装饰：圆点 + 短线分隔（body 与署名之间） */
@Builder
function WarmDots(c: PosterRenderCtx) {
  Row({ space: c.f(10) }) {
    Circle({ width: c.f(10), height: c.f(10) }).fill(c.pal().accent)
    Row().width(c.f(64)).height(c.f(3)).borderRadius(c.f(2)).backgroundColor(c.pal().accent)
    Circle({ width: c.f(10), height: c.f(10) }).fill(c.pal().accent)
  }
  .alignItems(VerticalAlign.Center)
}

/** T1 内容层：tag 胶囊 / body / 圆点分隔 / 署名四段排布 */
@Builder
function WarmContent(c: PosterRenderCtx) {
  Column({ space: c.f(30) }) {
    TagPill(c)
    // 可用宽 = 900 - padding.left(70) - padding.right(70) = 760
    // 预算留 2 行给 dots/署名：走查发现 120 字满文案时署名被挤出画布
    BodyBlock(c, 72, false, false, 760, c.bodyBudget(2))
    WarmDots(c)
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

@Builder
export function WarmLabel(c: PosterRenderCtx) {
  Stack() {
    WarmDecor(c)
    WarmContent(c)
  }
  .width('100%')
  .height('100%')
}

// ---------- T2 纯色简约 ----------

/** T2 内容层装饰：tag 与 body 之间的强调短线 */
@Builder
function MinimalDash(c: PosterRenderCtx) {
  Row().width(c.f(44)).height(c.f(5)).borderRadius(c.f(3)).backgroundColor(c.pal().accent)
}

/** T2：tag / 强调线 / body / 署名单列流式排布（无装饰层画布） */
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
    MinimalDash(c)
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

/** T3 装饰层：对角两枚旋转小方块，不含任何文案 */
@Builder
function WriteDecor(c: PosterRenderCtx) {
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
}

/** T3 内容层：tag 圆点行 / body / 署名短线行三段排布 */
@Builder
function WriteContent(c: PosterRenderCtx) {
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

@Builder
export function Handwrite(c: PosterRenderCtx) {
  Stack() {
    WriteDecor(c)
    WriteContent(c)
  }
  .width('100%')
  .height('100%')
}
