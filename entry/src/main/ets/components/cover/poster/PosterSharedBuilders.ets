/**
 * 文案海报共享子构建器（1.4.7 P2-1 拆分自 CopyPosterPreview）：
 * PinyinBody 主文案注音排版（汉字逐字拼音单元）/ BodyBlock 主文案块（空文案占位、注音、超长缩字号 + 省略兜底）。
 */
import { PosterRenderCtx, PY_RATIO } from './PosterRenderCtx';
import { CoverContentUtil, HanziUnit } from '../../../core/cover/CoverContentUtil';

/**
 * 主文案注音排版：汉字逐字单元（拼音在字上方对齐），非汉字整段合并不注音；
 * 自动按实际宽度换行，拼音行高预算 1.3 系数；maxWidthVp 为换行宽度上限（'100%' 或具体值）
 */
@Builder
export function PinyinBody(c: PosterRenderCtx, sizeVp: number, color: ResourceColor, pyColor: ResourceColor, center: boolean,
  bold: boolean, glow: string, maxWidthVp: Length) {
  Flex({ wrap: FlexWrap.Wrap, justifyContent: center ? FlexAlign.Center : FlexAlign.Start }) {
    ForEach(CoverContentUtil.hanziUnits(c.content.body), (u: HanziUnit, i: number) => {
      Column() {
        Text(u.py === '' ? ' ' : u.py)
          .fontSize(sizeVp * PY_RATIO)
          .lineHeight(sizeVp * PY_RATIO * 1.3)
          .fontColor(pyColor)
          .maxLines(1)
        Text(u.text)
          .fontSize(sizeVp)
          .lineHeight(sizeVp * 1.4)
          .fontColor(color)
          .fontFamily(c.font())
          .fontWeight(bold ? FontWeight.Bold : FontWeight.Normal)
          .maxLines(1)
          .textShadow(c.pyShadow(glow))
      }
      .constraintSize({ minWidth: u.text.length === 1 ? sizeVp : 0 })
      .alignItems(HorizontalAlign.Center)
    }, (u: HanziUnit, i: number) => i.toString() + '-' + u.text + '-' + u.py)
  }
  .constraintSize({ maxWidth: maxWidthVp })
}

/**
 * 主文案块：空文案显示占位提示；注音开启逐字注音；超长自动缩字号 + 省略兜底。
 *
 * 1.4.5 文案海报优化 P0-2/P0-3：
 *   - availWidthPx 为可选参数。传值时字号由 PosterTypeset 内核按容器宽度 + 行数预算计算；
 *     不传时行为与优化前完全一致，便于 18 个模板分批迁移。
 *   - 启用内核且发生截断时，在文案下方显示「已省略 N 字」提示，
 *     避免优化前 maxLines + Ellipsis 静默吞字、用户不知情（根因 C）。
 */
@Builder
export function BodyBlock(c: PosterRenderCtx, basePx: number, bold: boolean, big: boolean, availWidthPx: number = 0, maxLines: number = 0) {
  if (c.content.body.trim() === '') {
    Text($r('app.string.poster_empty_hint'))
      .fontSize(c.f(28))
      .fontColor(c.pal().sub)
      .fontFamily(c.font())
      .textAlign(TextAlign.Center)
  } else if (c.pyEnabled()) {
    PinyinBody(c, c.bodyFont(basePx, big, availWidthPx, maxLines), c.pal().title, c.pal().sub, true, bold,
      'none', '100%')
  } else {
    Column({ space: c.f(10) }) {
      Text(c.content.body)
        .fontSize(c.bodyFont(basePx, big, availWidthPx, maxLines))
        .lineHeight(c.bodyFont(basePx, big, availWidthPx, maxLines) * 1.4)
        .fontColor(c.pal().title)
        .fontFamily(c.font())
        .fontWeight(bold ? FontWeight.Bold : FontWeight.Normal)
        .maxLines(maxLines > 0 ? maxLines : c.maxBodyLines(big))
        .textAlign(TextAlign.Center)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (c.truncatedHint() > 0 && !c.isThumb) {
        Text($r('app.string.poster_truncated_hint', c.truncatedHint()))
          .fontSize(c.f(20))
          .fontColor(c.pal().sub)
          .fontFamily(c.font())
          .opacity(0.75)
          .textAlign(TextAlign.Center)
          .maxLines(1)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }
}
