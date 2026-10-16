/**
 * 文案海报模板 · 纸质复古组（1.4.7 P2-1 拆分自 CopyPosterPreview）：
 * T9 复古车票 / T11 复古报纸 / T15 公告栏启事。
 * 1.4.6 §2.1.4 根因 D 分层（第三批，同 Festival/Screens 批纪律）：本组为纸质印刷风
 * 混合布局（T9 流式票纸、T11 流式报版、T15 全绝对定位便签），采用构建器级分层
 * （树形与渲染节点零变化，行为与 1.4.6 完全一致）：
 *   装饰层（*Punches/*Vignette/*PaperTint/*HeaderBar/*Filler/*FooterBar/*ExtraStamp/
 *     *CoffeeStain/*EdgeShade/*Board/*BoardLabel/NewsLines/CorkPin/CorkString）：
 *     纯图形与固定丝印（No. 128/PRICE 0.5/POCKET PRESS/PAGE 04 等），不读
 *     tag/body/sign/bodyLen 任何内容状态；
 *   内容层（*Main/*Stub/*Stamp/*Masthead/*Body/*Sign/*TagCard/*BodyCard/*SignCard）：
 *     tag/body/sign 槽位 + 空态/截断提示 + 实时票号（No./0-XXX-26）；
 *   组合层（VintageTicket/VintageNews/CorkNotice）：卡片定位、挂绳图钉条件编排
 *     （z 序压卡上）与暗角统一组装，树序与 1.4.6 完全一致。
 */
import { CopyPosterRatio } from '../../../model/CopyPosterModels';
import { PosterRenderCtx } from './PosterRenderCtx';
import { BodyBlock } from './PosterSharedBuilders';

// ---------- T9 复古车票（票纸 + 撕票线 + 邮戳） ----------

function ticketH(c: PosterRenderCtx): number {
  return c.h() * (c.ratioKind === CopyPosterRatio.SQUARE ? 440 : 560) / 900;
}

/** T9 票面主文案行数预算：票纸高度固定（440/560），行数按比例收紧，防止挤掉撕票线下方元素 */
function ticketBodyLines(c: PosterRenderCtx): number {
  return c.ratioKind === CopyPosterRatio.SQUARE ? 5 : 8;
}

function pad3(n: number): string {
  if (n < 10) {
    return '00' + n.toString();
  }
  if (n < 100) {
    return '0' + n.toString();
  }
  return n.toString();
}

/** T9 内容层·票面主栏：报头（QUOTATION TICKET + 实时票号）、双栏线、正文与署名 */
@Builder
function TicketMain(c: PosterRenderCtx) {
  Column() {
    Row() {
      Text('QUOTATION TICKET')
        .fontSize(c.f(17))
        .letterSpacing(c.f(5))
        .fontColor(c.pal().sub)
        .fontWeight(FontWeight.Bold)
      Text('No. ' + pad3(c.bodyLen()))
        .fontSize(c.f(17))
        .fontColor(c.pal().sub)
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)

    Column()
      .width('100%')
      .height(c.f(4))
      .margin({ top: c.f(10), bottom: c.f(16) })
      .border({ width: { top: c.f(1), bottom: c.f(1) }, color: c.pal().grid })

    if (c.content.body.trim() === '') {
      Text($r('app.string.poster_empty_hint'))
        .fontSize(c.f(28))
        .fontColor(c.pal().sub)
        .fontFamily(c.font())
    } else {
      // 可用宽 = 票纸 800 - 副券 190 - padding(26+22) = 562；预算对齐票面高度
      Text('“' + c.content.body + '”')
        .fontSize(c.bodyFont(50, false, 562, ticketBodyLines(c)))
        .lineHeight(c.bodyFont(50, false, 562, ticketBodyLines(c)) * 1.5)
        .fontColor(c.pal().title)
        .fontFamily(c.font())
        .maxLines(ticketBodyLines(c))
        .textAlign(TextAlign.Start)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (c.truncatedHint() > 0 && !c.isThumb) {
        Text($r('app.string.poster_truncated_hint', c.truncatedHint()))
          .fontSize(c.f(18))
          .fontColor(c.pal().sub)
          .fontFamily(c.font())
          .maxLines(1)
      }
    }

    Blank()

    if (c.content.sign.trim() !== '') {
      Text(c.content.sign)
        .fontSize(c.f(24))
        .fontColor(c.pal().sub)
        .fontFamily(c.font())
        .maxLines(1)
    }
  }
  .layoutWeight(1)
  .height('100%')
  .padding({ left: c.f(26), right: c.f(22), top: c.f(24), bottom: c.f(20) })
  .alignItems(HorizontalAlign.Start)
}

/** T9 内容层·撕票副券：KEEP 丝印、条码、实时票号 0-XXX-26 与标签槽位 */
@Builder
function TicketStub(c: PosterRenderCtx) {
  Column({ space: c.f(12) }) {
    Text('KEEP')
      .fontSize(c.f(15))
      .letterSpacing(c.f(4))
      .fontColor(c.pal().sub)
      .fontWeight(FontWeight.Bold)
    Row({ space: c.f(3) }) {
      ForEach([2, 1, 3, 1, 2, 2, 1, 3, 1, 2, 3, 1, 2, 1, 3, 2, 1, 2], (w: number) => {
        Row().width(c.f(w)).height(c.f(42)).backgroundColor(c.pal().title)
      }, (w: number) => w.toString())
    }
    Text('0-' + pad3(c.bodyLen()) + '-26')
      .fontSize(c.f(13))
      .fontColor(c.pal().sub)
    if (c.content.tag.trim() !== '') {
      Text(c.content.tag)
        .fontSize(c.f(15))
        .fontColor(c.pal().sub)
        .letterSpacing(c.f(2))
        .maxLines(2)
        .textAlign(TextAlign.Center)
    }
  }
  .width(c.f(190))
  .height('100%')
  .border({
    width: { left: c.f(2) },
    color: c.pal().grid,
    style: { left: BorderStyle.Dashed },
  })
  .justifyContent(FlexAlign.Center)
  .alignItems(HorizontalAlign.Center)
}

/** T9 内容层·批准邮戳：标签槽位 + ★★★ + APPROVED 丝印，斜压票面右上 */
@Builder
function TicketStamp(c: PosterRenderCtx) {
  Stack() {
    Column({ space: c.f(4) }) {
      Text(c.content.tag.trim() !== '' ? c.content.tag : '')
        .fontSize(c.f(22))
        .fontColor(c.pal().accent)
        .fontWeight(FontWeight.Bold)
        .maxLines(1)
      Text('★ ★ ★')
        .fontSize(c.f(13))
        .fontColor(c.pal().accent)
      Text('APPROVED')
        .fontSize(c.f(11))
        .letterSpacing(c.f(3))
        .fontColor(c.pal().accent)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
  .width(c.f(160))
  .height(c.f(160))
  .borderRadius(c.f(80))
  .border({ width: c.f(5), color: c.hexA(c.pal().accent, '#D0') })
  .rotate({ angle: -14 })
  .opacity(0.92)
  .position({ x: c.posX(520), y: -c.f(24) })
}

/** T9 装饰件：撕票线三孔（票顶两孔 + 左下小孔） */
@Builder
function TicketPunches(c: PosterRenderCtx) {
  Circle({ width: c.f(22), height: c.f(22) }).fill(c.pal().bg)
    .position({ x: c.posX(599), y: -c.f(11) })
  Circle({ width: c.f(22), height: c.f(22) }).fill(c.pal().bg)
    .position({ x: c.posX(599), y: ticketH(c) - c.f(11) })
  Circle({ width: c.f(16), height: c.f(16) }).fill(c.pal().bg)
    .position({ x: c.posX(22), y: ticketH(c) - c.f(38) })
}

/** T9 装饰件：全幅暗角（中心 45% 径向渐变） */
@Builder
function TicketVignette(c: PosterRenderCtx) {
  Column()
    .width('100%')
    .height('100%')
    .radialGradient({
      center: ['50%', '45%'],
      radius: '90%',
      colors: [['#00000000', 0], ['#00000000', 0.55], ['#96000000', 1]],
    })
    .hitTestBehavior(HitTestMode.None)
}

/** T9 组合层：票纸 Row（主栏 + 副券）+ 邮戳 + 撕票孔，暗角置顶，树序同 1.4.6 */
@Builder
export function VintageTicket(c: PosterRenderCtx) {
  Stack() {
    Stack() {
      Row() {
        TicketMain(c)
        TicketStub(c)
      }
      .width(c.f(800))
      .height(ticketH(c))
      .backgroundColor(c.pal().block)
      .borderRadius(c.f(10))
      .shadow({ radius: c.f(38), color: '#8F000000', offsetY: c.f(18) })
      .rotate({ angle: -3 })

      TicketStamp(c)
      TicketPunches(c)
    }

    TicketVignette(c)
  }
  .width('100%')
  .height('100%')
  .alignContent(Alignment.Center)
}

// ---------- T11 复古报纸（老报纸头版，参照 docs/文案海报候选_复古报纸.html） ----------

/** T11 装饰件：假文栏（灰底圆角短条组，widths 为百分比宽度列表） */
@Builder
function NewsLines(c: PosterRenderCtx, widths: string[]) {
  Column({ space: c.f(13) }) {
    ForEach(widths, (w: string) => {
      Row().width(w).height(c.f(10)).borderRadius(c.f(3)).backgroundColor(c.pal().grid)
    }, (w: string) => w)
  }
  .width('100%')
  .alignItems(HorizontalAlign.Start)
}

/** T11 装饰件：纸面做旧黄渍（顶部 28% 径向渐变） */
@Builder
function NewsPaperTint(c: PosterRenderCtx) {
  Column()
    .width('100%')
    .height('100%')
    .radialGradient({
      center: ['50%', '28%'],
      radius: '85%',
      colors: [[c.hexA(c.pal().block, 'D9'), 0], [c.hexA(c.pal().block, '59'), 0.5], ['#00000000', 1]],
    })
    .hitTestBehavior(HitTestMode.None)
}

/** T11 装饰件：报头栏（No. 128 / 日期 / PRICE 0.5 固定丝印 + 下方双栏线） */
@Builder
function NewsHeaderBar(c: PosterRenderCtx) {
  Row() {
    Text('No. 128')
      .fontSize(c.f(16))
      .fontColor(c.pal().sub)
      .letterSpacing(c.f(2.4))
    Text('SUNDAY · OCT 11, 2026')
      .fontSize(c.f(16))
      .fontColor(c.pal().sub)
      .letterSpacing(c.f(2.4))
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
    Text('PRICE 0.5')
      .fontSize(c.f(16))
      .fontColor(c.pal().sub)
      .letterSpacing(c.f(2.4))
  }
  .width('100%')
  .alignItems(VerticalAlign.Center)

  Row().width('100%').height(c.f(2.4)).backgroundColor(c.pal().title).margin({ top: c.f(11) })
  Row().width('100%').height(c.f(1.6)).backgroundColor(c.pal().title).margin({ top: c.f(5) })
}

/** T11 内容层·刊名区：kicker（有标签时 POCKET DAILY）+ 标签刊名（空态兜底 POCKET DAILY）+ 下方双粗线 */
@Builder
function NewsMasthead(c: PosterRenderCtx) {
  Column() {
    if (c.content.tag.trim() !== '') {
      Text('POCKET DAILY')
        .fontSize(c.f(18))
        .fontColor(c.pal().sub)
        .letterSpacing(c.f(11))
        .margin({ bottom: c.f(10) })
    }
    Text(c.content.tag.trim() !== '' ? c.content.tag.trim() : 'POCKET DAILY')
      .fontSize(c.f(68))
      .fontWeight(FontWeight.Bold)
      .fontColor(c.pal().title)
      .fontFamily(c.font())
      .letterSpacing(c.f(19))
      .maxLines(1)
      .width('100%')
      .textAlign(TextAlign.Center)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }
  .width('100%')
  .alignItems(HorizontalAlign.Center)
  .margin({ top: c.f(16) })

  Row().width('100%').height(c.f(4.8)).backgroundColor(c.pal().title).margin({ top: c.f(16) })
  Row().width('100%').height(c.f(1.6)).backgroundColor(c.pal().title).margin({ top: c.f(8) })
}

/** T11 内容层·正文区：接排版内核 BodyBlock */
@Builder
function NewsBody(c: PosterRenderCtx) {
  Column() {
    // 可用宽 = 900 - padding 68*2 = 764；预算留 2 行给署名/下方栏线
    BodyBlock(c, 54, true, false, 764, c.bodyBudget(2))
  }
  .width('100%')
  .margin({ top: c.f(32) })
}

/** T11 内容层·署名：—— 署名（斜体，有署名才渲染） */
@Builder
function NewsSign(c: PosterRenderCtx) {
  if (c.content.sign.trim() !== '') {
    Text('—— ' + c.content.sign)
      .fontSize(c.f(24))
      .fontColor(c.pal().sub)
      .fontFamily(c.font())
      .fontStyle(FontStyle.Italic)
      .maxLines(1)
      .margin({ top: c.f(19) })
  }
}

/** T11 装饰件：三栏假文填充（等宽三列假文条，撑满剩余版面） */
@Builder
function NewsFiller(c: PosterRenderCtx) {
  Row({ space: c.f(32) }) {
    Column() {
      NewsLines(c, ['100%', '82%', '95%', '70%', '90%', '60%'])
    }
    .layoutWeight(1)
    Column() {
      NewsLines(c, ['88%', '100%', '75%', '96%', '52%'])
    }
    .layoutWeight(1)
    Column() {
      NewsLines(c, ['92%', '65%', '100%', '84%', '45%'])
    }
    .layoutWeight(1)
  }
  .width('100%')
  .layoutWeight(1)
  .alignItems(VerticalAlign.Top)
  .margin({ top: c.f(35) })
}

/** T11 装饰件：页脚栏（POCKET PRESS / EDITOR · JIEYU ZHUJI / PAGE 04 固定丝印 + 顶栏线） */
@Builder
function NewsFooterBar(c: PosterRenderCtx) {
  Row() {
    Text('POCKET PRESS')
      .fontSize(c.f(15))
      .fontColor(c.pal().sub)
      .letterSpacing(c.f(3.2))
    Text('EDITOR · JIEYU ZHUJI')
      .fontSize(c.f(15))
      .fontColor(c.pal().sub)
      .letterSpacing(c.f(3.2))
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
    Text('PAGE 04')
      .fontSize(c.f(15))
      .fontColor(c.pal().sub)
      .letterSpacing(c.f(3.2))
  }
  .width('100%')
  .alignItems(VerticalAlign.Center)
  .border({ width: { top: c.f(1.6) }, color: c.hexA(c.pal().sub, '80') })
  .padding({ top: c.f(13) })
  .margin({ top: c.f(22) })
}

/** T11 装饰件：EXTRA 号外戳（斜置描边章，压版面右上） */
@Builder
function NewsExtraStamp(c: PosterRenderCtx) {
  Text('EXTRA')
    .fontSize(c.f(31))
    .fontWeight(FontWeight.Bold)
    .fontColor(c.pal().accent)
    .letterSpacing(c.f(10))
    .padding({ left: c.f(26), right: c.f(19), top: c.f(8), bottom: c.f(8) })
    .border({ width: c.f(4), color: c.pal().accent })
    .borderRadius(c.f(6))
    .rotate({ angle: 8 })
    .opacity(0.85)
    .position({ x: c.previewWidth - c.posX(242), y: c.posY(148) })
}

/** T11 装饰件：左下咖啡渍（241 径向渐变圆） */
@Builder
function NewsCoffeeStain(c: PosterRenderCtx) {
  Column()
    .width(c.f(241))
    .height(c.f(241))
    .borderRadius(c.f(120))
    .radialGradient({
      center: ['50%', '50%'],
      radius: '50%',
      colors: [[c.hexA(c.pal().sub, '29'), 0], ['#00000000', 0.7]],
    })
    .position({ x: -c.posX(72), y: c.h() - c.posY(185) })
    .hitTestBehavior(HitTestMode.None)
}

/** T11 装饰件：左右边缘阴影（横向线性渐变） */
@Builder
function NewsEdgeShade(c: PosterRenderCtx) {
  Column()
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 90,
      colors: [[c.hexA('#000000', '0D'), 0], ['#00000000', 0.06], ['#00000000', 0.94], [c.hexA('#000000', '12'), 1]],
    })
    .hitTestBehavior(HitTestMode.None)
}

/** T11 装饰件：全幅做旧暗角（中心 45% 径向渐变） */
@Builder
function NewsVignette(c: PosterRenderCtx) {
  Column()
    .width('100%')
    .height('100%')
    .radialGradient({
      center: ['50%', '45%'],
      radius: '90%',
      colors: [['#00000000', 0], ['#00000000', 0.52], [c.hexA(c.pal().sub, '3D'), 1]],
    })
    .hitTestBehavior(HitTestMode.None)
}

/** T11 组合层：做旧黄渍 → 报版主列（报头/刊名/正文/署名/假文/页脚）→ 号外戳/咖啡渍/边缘/暗角 */
@Builder
export function VintageNews(c: PosterRenderCtx) {
  Stack() {
    NewsPaperTint(c)

    Column() {
      NewsHeaderBar(c)
      NewsMasthead(c)
      NewsBody(c)
      NewsSign(c)
      NewsFiller(c)
      NewsFooterBar(c)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: c.f(68), right: c.f(68), top: c.f(48), bottom: c.f(42) })

    NewsExtraStamp(c)
    NewsCoffeeStain(c)
    NewsEdgeShade(c)
    NewsVignette(c)
  }
  .width('100%')
  .height('100%')
}

// ---------- T15 公告栏启事（软木板图钉便签，参照 docs/文案海报候选_公告栏启事.html） ----------

/** T15 装饰件：图钉（径向渐变钉帽 + 钉芯暗点，定位到 px/py） */
@Builder
function CorkPin(c: PosterRenderCtx, px: number, py: number) {
  Stack() {
    Column()
      .width('100%')
      .height('100%')
      .borderRadius(c.f(13.5))
      .radialGradient({
        center: ['36%', '32%'],
        radius: '90%',
        colors: [['#8CFFFFFF', 0], [c.pal().accent, 0.62], [c.hexA('#000000', '73'), 1]],
      })
    Column()
      .width(c.f(9))
      .height(c.f(9))
      .borderRadius(c.f(4.5))
      .backgroundColor(c.hexA('#000000', 'A6'))
  }
  .width(c.f(27))
  .height(c.f(27))
  .shadow({ radius: c.f(8), color: '#8C000000', offsetY: c.f(5) })
  .position({ x: c.posX(px) - c.posX(13.5), y: c.posY(py) - c.f(13.5) })
}

/** T15 装饰件：挂绳（强调色圆角细条，自 px/py 绕钉斜挂） */
@Builder
function CorkString(c: PosterRenderCtx, px: number, py: number, len: number, angle: number) {
  Row()
    .width(c.f(len))
    .height(c.f(4))
    .borderRadius(c.f(2))
    .backgroundColor(c.pal().accent)
    .opacity(0.85)
    .rotate({ angle: angle, centerX: '0%', centerY: '50%' })
    .position({ x: c.posX(px), y: c.posY(py) - c.f(2) })
}

/**
 * T15 正文行数预算（1.4.6 P0-1 B 类）：便签卡顶 posY(376) 随画布高放大（376/900 比例），
 * 卡固定开销 ~108（上下 padding 71 + 日期行 37），行高 = 40×1.65 = 66，底部留白 40。
 * 1:1 → 5 行 / 3:4 → 8 行 / 9:16 → 11 行，修复现网 8 行长文案卡片溢出画布底部的缺陷。
 */
function corkBodyLines(c: PosterRenderCtx): number {
  let dh: number = CopyPosterRatio.designHeight(c.ratioKind);
  let avail: number = dh - dh * 376 / 900 - 40 - 108;
  return Math.max(3, Math.floor(avail / 66));
}

/** T15 装饰件：软木板（木纹贴图平铺 + 内外双描边框） */
@Builder
function CorkBoard(c: PosterRenderCtx) {
  Column()
    .width('100%')
    .height('100%')
    .backgroundImage($r('app.media.poster_cork_grain'), ImageRepeat.XY)
    .backgroundImageSize({ width: c.f(46), height: c.f(46) })
    .hitTestBehavior(HitTestMode.None)

  Column()
    .width('100%')
    .height('100%')
    .border({ width: c.f(31), color: c.hexA('#000000', '40') })
    .hitTestBehavior(HitTestMode.None)
  Column()
    .width('100%')
    .height('100%')
    .border({ width: c.f(29), color: c.pal().grid })
    .hitTestBehavior(HitTestMode.None)
}

/** T15 内容层·标签便签：标签大字 + NOTICE 丝印（有标签才渲染） */
@Builder
function CorkTagCard(c: PosterRenderCtx) {
  Column() {
    Text(c.content.tag)
      .fontSize(c.f(40))
      .fontWeight(FontWeight.Bold)
      .fontColor(c.pal().title)
      .fontFamily(c.font())
      .letterSpacing(c.f(5))
      .maxLines(2)
      .textAlign(TextAlign.Center)
    Text('NOTICE')
      .fontSize(c.f(14))
      .fontColor(c.pal().sub)
      .letterSpacing(c.f(2))
      .margin({ top: c.f(10) })
  }
  .width(c.f(286))
  .padding({ left: c.f(22), right: c.f(22), top: c.f(32), bottom: c.f(21) })
  .alignItems(HorizontalAlign.Center)
  .backgroundColor(c.pal().block)
  .linearGradient({ angle: 170, colors: [[c.hexA(c.pal().grid, '1F'), 0], [c.hexA(c.pal().grid, '0D'), 1]] })
  .borderRadius(c.f(2))
  .shadow({ radius: c.f(42), color: '#6B28180A', offsetY: c.f(19) })
  .rotate({ angle: 2.5 })
  .position({ x: c.posX(511), y: c.posY(129) })
}

/** T15 内容层·正文便签：正文（空态提示/截断提示）+ 固定日期丝印 2026.10.11 */
@Builder
function CorkBodyCard(c: PosterRenderCtx) {
  Column() {
    if (c.content.body.trim() === '') {
      Text($r('app.string.poster_empty_hint'))
        .fontSize(c.f(30))
        .fontColor(c.pal().sub)
        .fontFamily(c.font())
        .textAlign(TextAlign.Center)
    } else {
      // 1.4.6 P0-1 B 类：正文接内核，可用宽 = 卡宽 485 - padding 70 - 字距余量 15 = 400，行数预算 corkBodyLines()
      Text(c.content.body)
        .fontSize(c.bodyFont(40, false, 400, corkBodyLines(c)))
        .lineHeight(c.bodyFont(40, false, 400, corkBodyLines(c)) * 1.65)
        .fontColor(c.pal().title)
        .fontFamily(c.font())
        .letterSpacing(c.f(1.6))
        .maxLines(corkBodyLines(c))
        .textAlign(TextAlign.Center)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      // 1.4.6 根因 C：截断提示（原 maxLines 静默吞字）
      if (c.truncatedHint() > 0 && !c.isThumb) {
        Text($r('app.string.poster_truncated_hint', c.truncatedHint()))
          .fontSize(c.f(16))
          .fontColor(c.pal().sub)
          .fontFamily(c.font())
          .opacity(0.75)
          .textAlign(TextAlign.Center)
          .maxLines(1)
      }
    }
    Text('2026.10.11')
      .fontSize(c.f(18))
      .fontColor(c.pal().sub)
      .letterSpacing(c.f(3))
      .margin({ top: c.f(19) })
  }
  .width(c.f(485))
  .padding({ left: c.f(35), right: c.f(35), top: c.f(42), bottom: c.f(29) })
  .alignItems(HorizontalAlign.Center)
  .backgroundColor(c.pal().block)
  .linearGradient({ angle: 165, colors: [[c.hexA('#FFFFFF', '17'), 0], ['#00FFFFFF', 1]] })
  .borderRadius(c.f(2))
  .shadow({ radius: c.f(42), color: '#6B28180A', offsetY: c.f(19) })
  .rotate({ angle: -1.5 })
  .position({ x: c.posX(235), y: c.posY(376) })
}

/** T15 内容层·署名便签：—— 署名 + 强调色下划条（有署名才渲染） */
@Builder
function CorkSignCard(c: PosterRenderCtx) {
  Column() {
    Text('—— ' + c.content.sign)
      .fontSize(c.f(30))
      .fontColor(c.pal().title)
      .fontFamily(c.font())
      .letterSpacing(c.f(1.6))
      .maxLines(2)
      .textAlign(TextAlign.Center)
    Row()
      .width(c.f(119))
      .height(c.f(3))
      .backgroundColor(c.pal().accent)
      .opacity(0.65)
      .margin({ top: c.f(14) })
  }
  .width(c.f(305))
  .padding({ left: c.f(22), right: c.f(22), top: c.f(29), bottom: c.f(19) })
  .alignItems(HorizontalAlign.Center)
  .backgroundColor(c.pal().block)
  .linearGradient({ angle: 170, colors: [[c.hexA('#FFFFFF', '14'), 0], ['#00FFFFFF', 1]] })
  .borderRadius(c.f(2))
  .shadow({ radius: c.f(42), color: '#6B28180A', offsetY: c.f(19) })
  .rotate({ angle: 3 })
  .position({ x: c.posX(556), y: c.posY(669) })
}

/** T15 装饰件：板底品牌丝印 CORK BOARD · NOTICE */
@Builder
function CorkBoardLabel(c: PosterRenderCtx) {
  Text('CORK BOARD · NOTICE')
    .fontSize(c.f(19))
    .letterSpacing(c.f(5))
    .fontColor(c.hexA(c.pal().title, 'A6'))
    .rotate({ angle: -1 })
    .position({ x: c.posX(84), y: c.h() - c.posY(52) })
}

/** T15 装饰件：全幅暗角（中心 50% 径向渐变） */
@Builder
function CorkVignette(c: PosterRenderCtx) {
  Column()
    .width('100%')
    .height('100%')
    .radialGradient({
      center: ['50%', '50%'],
      radius: '95%',
      colors: [['#00000000', 0.55], [c.hexA('#000000', '38'), 1]],
    })
    .hitTestBehavior(HitTestMode.None)
}

/** T15 组合层：软木板 → 三便签（标签/正文/署名条件渲染）→ 挂绳图钉（z 序压卡上）→ 丝印 → 暗角 */
@Builder
export function CorkNotice(c: PosterRenderCtx) {
  Stack() {
    CorkBoard(c)

    if (c.content.tag.trim() !== '') {
      CorkTagCard(c)
    }

    CorkBodyCard(c)

    if (c.content.sign.trim() !== '') {
      CorkSignCard(c)
    }

    if (c.content.tag.trim() !== '') {
      CorkString(c, 653, 129, 302, 125.3)
    }
    if (c.content.tag.trim() !== '' && c.content.sign.trim() !== '') {
      CorkString(c, 478, 377, 368, 51.8)
    }
    if (c.content.tag.trim() !== '') {
      CorkPin(c, 653, 129)
    }
    CorkPin(c, 478, 377)
    if (c.content.sign.trim() !== '') {
      CorkPin(c, 708, 669)
    }

    CorkBoardLabel(c)

    CorkVignette(c)
  }
  .width('100%')
  .height('100%')
}
