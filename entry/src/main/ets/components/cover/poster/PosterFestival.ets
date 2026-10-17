/**
 * 文案海报模板 · 节令风物组（1.4.7 P2-1 拆分自 CopyPosterPreview）：
 * T16 二十四节气卡 / T17 节日祝福卡 / T18 红包对联风；FestStar/CoupletCoin/CoupletCorner 为组内局部子构建器。
 * 1.4.6 根因 D 分层（第二批，同 T7 NeonDecor/NeonContent 样板）：每模板拆装饰层（纯图形 + HitTestMode.None，
 * isThumb 精简逻辑收拢于此）+ 内容层（tag/body/sign 槽位 + 截断提示），组合层仅三层堆叠，行为零变化。
 */
import { CopyPosterRatio } from '../../../model/CopyPosterModels';
import { PosterRenderCtx } from './PosterRenderCtx';
import { PinyinBody } from './PosterSharedBuilders';
import { PosterTypeset, PosterVerticalLayout } from '../../../core/cover/PosterTypeset';

// ---------- T16 二十四节气卡（竖排主文案 + 节气名/印章/节气歌，参照 docs/文案海报候选_二十四节气卡.html） ----------

/** 竖排字符序列：去空白逐字拆分 */
function vertChars(text: string): string[] {
  return Array.from(text.replace(new RegExp('\\s', 'g'), ''));
}

/** T16 节气名（tag）字数 */
function termCharCount(c: PosterRenderCtx): number {
  return vertChars(c.content.tag).length;
}

/** T16 节气名字号分档：≤2 字 74 / ≤4 字 52 / 其余 38（设计 px） */
function vertTermSize(c: PosterRenderCtx): number {
  let n: number = termCharCount(c);
  if (n <= 2) {
    return c.f(74);
  }
  if (n <= 4) {
    return c.f(52);
  }
  return c.f(38);
}

/**
 * T16 竖排内核（1.4.6 P0-1 A 类）：盒几何与渲染盒恒等——
 * 盒高 = h() - fy(122) - f(209) → availH = 画布高×778/900 - 209；盒宽 900-270-167 = 463；
 * lh 1.30 / pitch 1.63（列间距 = 字号×0.63）。替代旧 solarBodyPx 3 档私有分档。
 */
function solarLayout(c: PosterRenderCtx): PosterVerticalLayout {
  let dh: number = CopyPosterRatio.designHeight(c.ratioKind);
  return PosterTypeset.layoutVertical(c.content.body, dh * 778 / 900 - 209, 99, 48, false,
    1.30, 463, 1.63);
}

/** T16 装饰层：顶光渐变 / 双层边框 / 四角菱形 / 正文分隔线，不含任何文案 */
@Builder
function SolarTermDecor(c: PosterRenderCtx) {
  Stack() {
    Column()
      .width('100%')
      .height('100%')
      .radialGradient({
        center: ['30%', '18%'],
        radius: '80%',
        colors: [[c.hexA('#FFFFFF', '12'), 0], ['#00FFFFFF', 1]],
      })
      .hitTestBehavior(HitTestMode.None)

    // 外层细边框
    Column()
      .width(c.previewWidth - c.f(29) * 2)
      .height(c.h() - c.f(29) * 2)
      .border({ width: c.f(1.6), color: c.hexA(c.pal().grid, '80') })
      .position({ x: c.posX(29), y: c.posY(29) })
    // 内层粗边框：缩略图下两层边框会糊成灰块，只保留一层（1.4.5 P2-6）
    if (!c.isThumb) {
      Column()
        .width(c.previewWidth - c.f(40) * 2)
        .height(c.h() - c.f(40) * 2)
        .border({ width: c.f(3.2), color: c.pal().sub })
        .position({ x: c.posX(40), y: c.posY(40) })
    }

    // 四角菱形：96px 下退化为 2px 噪点，缩略图模式跳过（1.4.5 P2-6）
    if (!c.isThumb) {
      Row().width(c.f(14)).height(c.f(14)).backgroundColor(c.pal().sub).rotate({ angle: 45 })
        .position({ x: c.posX(64), y: c.posY(64) })
      Row().width(c.f(14)).height(c.f(14)).backgroundColor(c.pal().sub).rotate({ angle: 45 })
        .position({ x: c.previewWidth - c.posX(64) - c.posX(14), y: c.posY(64) })
      Row().width(c.f(14)).height(c.f(14)).backgroundColor(c.pal().sub).rotate({ angle: 45 })
        .position({ x: c.posX(64), y: c.h() - c.posY(64) - c.f(14) })
      Row().width(c.f(14)).height(c.f(14)).backgroundColor(c.pal().sub).rotate({ angle: 45 })
        .position({ x: c.previewWidth - c.posX(64) - c.posX(14), y: c.h() - c.posY(64) - c.f(14) })
    }

    Column()
      .width(c.f(1.6))
      .height(c.h() - c.fy(135) - c.f(135))
      .linearGradient({
        angle: 180,
        colors: [[c.hexA(c.pal().grid, '00'), 0], [c.pal().grid, 0.18],
          [c.pal().grid, 0.82], [c.hexA(c.pal().grid, '00'), 1]],
      })
      .position({ x: c.posX(270), y: c.posY(135) })
  }
  .width('100%')
  .height('100%')
  .hitTestBehavior(HitTestMode.None)
}

/** T16 内容层：节气名竖排列 / 竖排正文 / 署名 / 节气歌，字号交由内核计算 */
@Builder
function SolarTermContent(c: PosterRenderCtx) {
  Stack() {
    Column({ space: c.f(29) }) {
      if (termCharCount(c) > 0) {
        Text(vertChars(c.content.tag).join('\n'))
          .fontSize(vertTermSize(c))
          .lineHeight(vertTermSize(c) * 1.3)
          .fontWeight(FontWeight.Bold)
          .fontColor(c.pal().block)
          .fontFamily(c.font())
          .textAlign(TextAlign.Center)
      }
      // SOLAR TERM 竖排英文：缩略图下字号不足 3px 不可辨，跳过（1.4.5 P2-6）
      if (!c.isThumb && termCharCount(c) > 0 && termCharCount(c) <= 4) {
        Text('S\nO\nL\nA\nR\n \nT\nE\nR\nM')
          .fontSize(c.f(18))
          .lineHeight(c.f(24))
          .letterSpacing(c.f(3))
          .fontColor(c.pal().sub)
          .textAlign(TextAlign.Center)
      }
      Column() {
        Text('节\n气')
          .fontSize(c.f(20))
          .lineHeight(c.f(24))
          .fontWeight(FontWeight.Bold)
          .fontColor('#F6EFDE')
          .textAlign(TextAlign.Center)
      }
      .width(c.f(64))
      .height(c.f(64))
      .backgroundColor(c.pal().accent)
      .borderRadius(c.f(6.4))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .shadow({ radius: c.f(10), color: c.hexA(c.pal().accent, '59'), offsetY: c.f(3) })
    }
    .alignItems(HorizontalAlign.Center)
    .position({ x: c.posX(119), y: c.posY(148) })

    Column() {
      if (c.content.body.trim() === '') {
        Text($r('app.string.poster_empty_hint'))
          .fontSize(c.f(28))
          .fontColor(c.pal().sub)
          .fontFamily(c.font())
          .width('100%')
          .textAlign(TextAlign.Center)
      } else {
        Row({ space: c.f(solarLayout(c).fontPx * 0.63) }) {
          ForEach(c.vertRenderCols(solarLayout(c).columns),
            (col: string[], i: number) => {
              Text(col.join('\n'))
                .fontSize(c.f(solarLayout(c).fontPx))
                .lineHeight(c.f(solarLayout(c).fontPx * 1.3))
                .fontColor(c.pal().title)
                .fontFamily(c.font())
                .textAlign(TextAlign.Center)
            }, (col: string[], i: number) =>
            i.toString() + '-' + col.length.toString() + '-' + (col.length > 0 ? col[0] : ''))
        }
        .alignItems(VerticalAlign.Top)
        // 1.4.6 根因 C：竖排截断改内核 truncatedChars 口径，替代旧 vertColsRtl 的 '…' 静默截断
        if (solarLayout(c).truncated && !c.isThumb) {
          Text($r('app.string.poster_truncated_hint', solarLayout(c).truncatedChars))
            .fontSize(c.f(18))
            .fontColor(c.pal().sub)
            .fontFamily(c.font())
            .opacity(0.75)
            .maxLines(1)
        }
      }
    }
    .width(c.previewWidth - c.f(270) - c.f(167))
    .height(c.h() - c.fy(122) - c.f(209))
    .alignItems(HorizontalAlign.End)
    .position({ x: c.posX(270), y: c.posY(122) })

    if (c.content.sign.trim() !== '') {
      Column() {
        Text(vertChars(c.content.sign).join('\n'))
          .fontSize(c.f(21))
          .lineHeight(c.f(27))
          .fontColor(c.pal().sub)
          .fontFamily(c.font())
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(HorizontalAlign.End)
      .padding({ right: c.f(122), bottom: c.f(125) })
    }

    Row({ space: c.f(19) }) {
      Row().width(c.f(54)).height(c.f(1.6)).backgroundColor(c.pal().grid)
      Text('春雨惊春清谷天 · 夏满芒夏暑相连')
        .fontSize(c.f(18))
        .letterSpacing(c.f(6))
        .fontColor(c.pal().sub)
        .fontFamily(c.font())
      Row().width(c.f(54)).height(c.f(1.6)).backgroundColor(c.pal().grid)
    }
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .position({ x: 0, y: c.h() - c.f(102) })
  }
  .width('100%')
  .height('100%')
}

@Builder
export function SolarTerm(c: PosterRenderCtx) {
  Stack() {
    SolarTermDecor(c)
    SolarTermContent(c)

    Column()
      .width('100%')
      .height('100%')
      .radialGradient({
        center: ['50%', '50%'],
        radius: '95%',
        colors: [['#00000000', 0.62], [c.hexA('#3E301A', '29'), 1]],
      })
      .hitTestBehavior(HitTestMode.None)
  }
  .width('100%')
  .height('100%')
}

// ---------- T17 节日祝福卡（圆月星点几何 + 居中祝福，参照 docs/文案海报候选_节日祝福卡.html） ----------

@Builder
function FestStar(c: PosterRenderCtx, dx: number, dy: number, opacity: number) {
  Circle({ width: c.f(5), height: c.f(5) })
    .fill(c.pal().grid)
    .opacity(opacity)
    .position({ x: c.posX(dx), y: c.posY(dy) })
}

/** 远山剪影 Path 命令（commands 单位为 px，取 vp × density） */
function hillPath(w: number, h: number, x1: number, y1: number, x2: number, y2: number,
  x3: number, y3: number): string {
  return 'M0 ' + h + ' L' + (w * x1) + ' ' + (h * y1) + ' L' + (w * x2) + ' ' + (h * y2) +
    ' L' + (w * x3) + ' ' + (h * y3) + ' L' + w + ' ' + h + ' Z';
}

/** T17 祝福区行数预算：正文槽位是 fy(518)-fy(726) 的固定高度区，按比例收紧防溢出月窗 */
function festBodyLines(c: PosterRenderCtx): number {
  return c.ratioKind === CopyPosterRatio.SQUARE ? 3 : 4;
}

/** T17 装饰层：星点 / 月晕 / 圆月 / 月环 / 云带 / 远山剪影，不含任何文案 */
@Builder
function FestivalGreetDecor(c: PosterRenderCtx) {
  Stack() {
    // 星点：96px 下直径不足 2px，与圆环混成噪点，缩略图模式只保留 3 颗大星（1.4.5 P2-6）
    if (c.isThumb) {
      FestStar(c, 206, 71, 0.85)
      FestStar(c, 691, 135, 0.9)
      FestStar(c, 135, 289, 0.6)
    } else {
      FestStar(c, 103, 125, 0.85)
      FestStar(c, 206, 71, 0.6)
      FestStar(c, 350, 154, 0.8)
      FestStar(c, 517, 90, 0.5)
      FestStar(c, 691, 135, 0.9)
      FestStar(c, 798, 225, 0.55)
      FestStar(c, 135, 289, 0.4)
      FestStar(c, 755, 373, 0.65)
    }

    Column()
      .width(c.f(512))
      .height(c.f(512))
      .borderRadius(c.f(256))
      .radialGradient({
        center: ['50%', '50%'],
        radius: '70%',
        colors: [[c.hexA(c.pal().accent, '38'), 0], [c.hexA(c.pal().accent, '0D'), 0.62],
          [c.hexA(c.pal().accent, '00'), 1]],
      })
      .position({ x: c.previewWidth / 2 - c.posX(256), y: c.posY(173) })

    Column()
      .width(c.f(240))
      .height(c.f(240))
      .borderRadius(c.f(120))
      .radialGradient({
        center: ['42%', '38%'],
        radius: '75%',
        colors: [[c.hexA('#FFFFFF', 'B3'), 0], [c.pal().accent, 0.6], [c.hexA('#000000', '2E'), 1]],
      })
      .shadow({ radius: c.f(70), color: c.hexA(c.pal().accent, '73') })
      .position({ x: c.previewWidth / 2 - c.posX(120), y: c.posY(237) })

    Column()
      .width(c.f(272))
      .height(c.f(272))
      .borderRadius(c.f(136))
      .border({ width: c.f(1.6), color: c.hexA(c.pal().accent, '59') })
      .position({ x: c.previewWidth / 2 - c.posX(136), y: c.posY(221) })

    // 云带：96px 下高度不足 4px，与底色混成脏块，缩略图模式跳过（1.4.5 P2-6）
    if (!c.isThumb) {
      Row().width(c.f(238)).height(c.f(35)).borderRadius(c.f(18))
        .backgroundColor(c.hexA(c.pal().block, '24'))
        .position({ x: c.posX(122), y: c.posY(379) })
      Row().width(c.f(145)).height(c.f(35)).borderRadius(c.f(18))
        .backgroundColor(c.hexA(c.pal().block, '1A'))
        .position({ x: c.posX(193), y: c.posY(421) })
      Row().width(c.f(199)).height(c.f(35)).borderRadius(c.f(18))
        .backgroundColor(c.hexA(c.pal().block, '1A'))
        .position({ x: c.previewWidth - c.posX(315), y: c.posY(334) })
      Row().width(c.f(116)).height(c.f(35)).borderRadius(c.f(18))
        .backgroundColor(c.hexA(c.pal().block, '14'))
        .position({ x: c.previewWidth - c.posX(302), y: c.posY(376) })
    }

    Path()
      .width(c.f(482))
      .height(c.f(177))
      .commands(hillPath(c.f(482) * c.density, c.f(177) * c.density,
        0.22, 0.34, 0.46, 0.78, 0.68, 0.08))
      .fill(c.hexA('#05070D', '99'))
      .position({ x: -c.posX(48), y: c.h() - c.posY(119) - c.f(177) })
    Path()
      .width(c.f(530))
      .height(c.f(154))
      .commands(hillPath(c.f(530) * c.density, c.f(154) * c.density,
        0.26, 0.52, 0.52, 0.86, 0.76, 0.22))
      .fill(c.hexA('#05070D', 'CC'))
      .position({ x: c.previewWidth - c.posX(466), y: c.h() - c.posY(119) - c.f(154) })
  }
  .width('100%')
  .height('100%')
  .hitTestBehavior(HitTestMode.None)
}

/** T17 内容层：tag 胶囊 / 祝福正文 / 题注 / 署名，字号交由内核计算 */
@Builder
function FestivalGreetContent(c: PosterRenderCtx) {
  Stack() {
    if (c.content.tag.trim() !== '') {
      Column() {
        Text(c.content.tag)
          .fontSize(c.f(27))
          .fontColor(c.pal().accent)
          .fontFamily(c.font())
          .letterSpacing(c.f(16))
          .maxLines(1)
          .padding({ left: c.f(42) + c.f(16), right: c.f(42), top: c.f(11), bottom: c.f(11) })
          .border({ width: c.f(1.6), color: c.hexA(c.pal().accent, '66') })
          .backgroundColor(c.hexA(c.pal().accent, '12'))
          .borderRadius(c.f(999))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .position({ x: 0, y: c.posY(84) })
    }

    Column() {
      if (c.content.body.trim() === '') {
        Text($r('app.string.poster_empty_hint'))
          .fontSize(c.f(28))
          .fontColor(c.pal().sub)
          .fontFamily(c.font())
          .textAlign(TextAlign.Center)
      } else if (c.pyEnabled()) {
        Column() {
          // 可用宽 = 900 - padding 96*2 = 708，再让 letterSpacing(10) 余量 -> 590
          PinyinBody(c, c.bodyFont(54, false, 590, festBodyLines(c)), c.pal().title, c.pal().sub,
            true, false, 'none', '100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      } else {
        Text(c.content.body)
          .fontSize(c.bodyFont(54, false, 590, festBodyLines(c)))
          .lineHeight(c.bodyFont(54, false, 590, festBodyLines(c)) * 1.55)
          .fontColor(c.pal().title)
          .fontFamily(c.font())
          .letterSpacing(c.f(10))
          .maxLines(festBodyLines(c))
          .textAlign(TextAlign.Center)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .shadow({ radius: c.f(35), color: '#8C000000', offsetY: c.f(5) })
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
    }
    .width('100%')
    .height(c.fy(726) - c.fy(518))
    .justifyContent(FlexAlign.Center)
    .padding({ left: c.f(96), right: c.f(96) })
    .position({ x: 0, y: c.posY(518) })

    Text('HAPPY FESTIVAL · POCKET GREETING')
      .fontSize(c.f(19))
      .letterSpacing(c.f(11))
      .fontColor(c.hexA(c.pal().sub, '99'))
      .width('100%')
      .textAlign(TextAlign.Center)
      .position({ x: 0, y: c.posY(726) })

    if (c.content.sign.trim() !== '') {
      Text('— ' + c.content.sign + ' —')
        .fontSize(c.f(21))
        .letterSpacing(c.f(6))
        .fontColor(c.hexA(c.pal().accent, 'B8'))
        .fontFamily(c.font())
        .width('100%')
        .textAlign(TextAlign.Center)
        .position({ x: 0, y: c.h() - c.posY(96) })
    }
  }
  .width('100%')
  .height('100%')
}

@Builder
export function FestivalGreet(c: PosterRenderCtx) {
  Stack() {
    FestivalGreetDecor(c)
    FestivalGreetContent(c)

    Column()
      .width('100%')
      .height('100%')
      .radialGradient({
        center: ['50%', '50%'],
        radius: '95%',
        colors: [['#00000000', 0.55], [c.hexA('#03050C', '80'), 1]],
      })
      .hitTestBehavior(HitTestMode.None)
  }
  .width('100%')
  .height('100%')
}

// ---------- T18 红包对联风（红金竖批 + 铜钱团花，参照 docs/文案海报候选_红包对联风.html） ----------

/**
 * T18 竖排内核（1.4.6 P0-1 A 类）：盒高 = h() - fy(238) - fy(174) → availH = 画布高×488/900；
 * 盒宽 900-212×2 = 476；lh 1.36 / pitch 1.90（列间距 = 字号×0.9）。
 * 替代旧 coupletBodyPx 3 档私有分档。
 */
function coupletLayout(c: PosterRenderCtx): PosterVerticalLayout {
  let dh: number = CopyPosterRatio.designHeight(c.ratioKind);
  return PosterTypeset.layoutVertical(c.content.body, dh * 488 / 900, 99, 70, false,
    1.36, 476, 1.90);
}

/** 1.4.8 上下联内核：各单列竖排（右=上联 左=下联），字号取两联较小值保持对称 */
function coupletUpLayout(c: PosterRenderCtx): PosterVerticalLayout {
  let dh: number = CopyPosterRatio.designHeight(c.ratioKind);
  return PosterTypeset.layoutVertical(c.content.coupletUp, dh * 488 / 900, 1, 70, false,
    1.36, 476, 1.90);
}

function coupletDownLayout(c: PosterRenderCtx): PosterVerticalLayout {
  let dh: number = CopyPosterRatio.designHeight(c.ratioKind);
  return PosterTypeset.layoutVertical(c.content.coupletDown, dh * 488 / 900, 1, 70, false,
    1.36, 476, 1.90);
}

function coupletPairFontPx(c: PosterRenderCtx): number {
  return Math.min(coupletUpLayout(c).fontPx, coupletDownLayout(c).fontPx);
}

function coupletPairTruncated(c: PosterRenderCtx): number {
  return coupletUpLayout(c).truncatedChars + coupletDownLayout(c).truncatedChars;
}

function coupletColText(l: PosterVerticalLayout): string {
  return l.columns.length > 0 ? l.columns[0].join('\n') : '';
}

@Builder
function CoupletCoin(c: PosterRenderCtx, xVp: number, yVp: number) {
  Stack({ alignContent: Alignment.Center }) {
    Circle({ width: c.f(74), height: c.f(74) })
      .fill('#00000000')
      .stroke(c.hexA(c.pal().accent, '29'))
      .strokeWidth(c.f(3.2))
    Circle({ width: c.f(38), height: c.f(38) })
      .fill('#00000000')
      .stroke(c.hexA(c.pal().accent, '29'))
      .strokeWidth(c.f(3.2))
    Row()
      .width(c.f(38))
      .height(c.f(38))
      .border({ width: c.f(3.2), color: c.hexA(c.pal().accent, '1A') })
      .borderRadius(c.f(6.4))
  }
  .width(c.f(74))
  .height(c.f(74))
  .position({ x: xVp, y: yVp })
}

@Builder
function CoupletCorner(c: PosterRenderCtx, xVp: number, yVp: number, align: Alignment) {
  Stack({ alignContent: align }) {
    Row().width(c.f(54)).height(c.f(4.8)).backgroundColor(c.pal().accent)
    Row().width(c.f(4.8)).height(c.f(54)).backgroundColor(c.pal().accent)
  }
  .width(c.f(54))
  .height(c.f(54))
  .position({ x: xVp, y: yVp })
}

/** T18 装饰层：铜钱团花 / 双层金框 / 四角描金纹 / 对联垂线坠点，不含任何文案 */
@Builder
function RedCoupletDecor(c: PosterRenderCtx) {
  Stack() {
    // 铜钱团花：96px 下直径约 4px，5 枚连排糊成噪点，缩略图只留 2 枚大纹（1.4.5 P2-6）
    if (c.isThumb) {
      CoupletCoin(c, c.posX(42), c.posY(200))
      CoupletCoin(c, c.previewWidth - c.posX(42) - c.posX(74), c.posY(200))
    } else {
      CoupletCoin(c, c.posX(42), c.posY(154))
      CoupletCoin(c, c.posX(42), c.posY(305))
      CoupletCoin(c, c.posX(42), c.posY(456))
      CoupletCoin(c, c.previewWidth - c.posX(42) - c.posX(74), c.posY(154))
      CoupletCoin(c, c.previewWidth - c.posX(42) - c.posX(74), c.posY(305))
    }

    Column()
      .width(c.previewWidth - c.f(32) * 2)
      .height(c.h() - c.posY(32) * 2)
      .border({ width: c.f(3.2), color: c.hexA(c.pal().accent, 'D9') })
      .position({ x: c.posX(32), y: c.posY(32) })
    // 内层细框：缩略图下两层金框糊成一块，只保留一层（1.4.5 P2-6）
    if (!c.isThumb) {
      Column()
        .width(c.previewWidth - c.f(43) * 2)
        .height(c.h() - c.posY(43) * 2)
        .border({ width: c.f(1.6), color: c.hexA(c.pal().accent, '73') })
        .position({ x: c.posX(43), y: c.posY(43) })
    }

    // 四角描金纹：96px 下退化为噪点，缩略图模式跳过（1.4.5 P2-6）
    if (!c.isThumb) {
      CoupletCorner(c, c.posX(55), c.posY(55), Alignment.TopStart)
      CoupletCorner(c, c.previewWidth - c.posX(55) - c.posX(54), c.posY(55), Alignment.TopEnd)
      CoupletCorner(c, c.posX(55), c.h() - c.posY(55) - c.f(54), Alignment.BottomStart)
      CoupletCorner(c, c.previewWidth - c.posX(55) - c.posX(54), c.h() - c.posY(55) - c.f(54),
        Alignment.BottomEnd)
    }

    Column()
      .width(c.f(2.4))
      .height(c.h() - c.fy(225) - c.fy(161))
      .linearGradient({
        angle: 180,
        colors: [[c.hexA(c.pal().accent, '00'), 0], [c.hexA(c.pal().accent, 'BF'), 0.14],
          [c.hexA(c.pal().accent, 'BF'), 0.86], [c.hexA(c.pal().accent, '00'), 1]],
      })
      .position({ x: c.posX(212), y: c.posY(225) })
    Column()
      .width(c.f(2.4))
      .height(c.h() - c.fy(225) - c.fy(161))
      .linearGradient({
        angle: 180,
        colors: [[c.hexA(c.pal().accent, '00'), 0], [c.hexA(c.pal().accent, 'BF'), 0.14],
          [c.hexA(c.pal().accent, 'BF'), 0.86], [c.hexA(c.pal().accent, '00'), 1]],
      })
      .position({ x: c.previewWidth - c.posX(212) - c.posX(2.4), y: c.posY(225) })

    Circle({ width: c.f(16), height: c.f(16) }).fill(c.pal().accent)
      .shadow({ radius: c.f(8), color: '#66000000', offsetY: c.f(2) })
      .position({ x: c.posX(212) + c.posX(1.2) - c.posX(8), y: c.posY(225) - c.f(19) })
    Circle({ width: c.f(16), height: c.f(16) }).fill(c.pal().accent)
      .shadow({ radius: c.f(8), color: '#66000000', offsetY: c.f(2) })
      .position({ x: c.previewWidth - c.posX(212) - c.posX(1.2) - c.posX(8), y: c.posY(225) - c.f(19) })
    Circle({ width: c.f(16), height: c.f(16) }).fill(c.pal().accent)
      .shadow({ radius: c.f(8), color: '#66000000', offsetY: c.f(2) })
      .position({ x: c.posX(212) + c.posX(1.2) - c.posX(8), y: c.h() - c.posY(161) + c.f(3) })
    Circle({ width: c.f(16), height: c.f(16) }).fill(c.pal().accent)
      .shadow({ radius: c.f(8), color: '#66000000', offsetY: c.f(2) })
      .position({ x: c.previewWidth - c.posX(212) - c.posX(1.2) - c.posX(8), y: c.h() - c.posY(161) + c.f(3) })
  }
  .width('100%')
  .height('100%')
  .hitTestBehavior(HitTestMode.None)
}

/** T18 内容层：横批 / 竖排正文 / 署名 / 题注，字号交由内核计算 */
@Builder
function RedCoupletContent(c: PosterRenderCtx) {
  Stack() {
    if (c.content.tag.trim() !== '') {
      Column() {
        Text(c.content.tag)
          .fontSize(c.f(38))
          .fontWeight(FontWeight.Bold)
          .fontColor(c.pal().title)
          .fontFamily(c.font())
          .letterSpacing(c.f(19))
          .maxLines(1)
          .padding({ left: c.f(48) + c.f(19), right: c.f(48), top: c.f(14), bottom: c.f(14) })
          .backgroundColor(c.pal().block)
          .border({ width: c.f(2.4), color: c.pal().accent })
          .shadow({ radius: c.f(26), color: '#59000000', offsetY: c.f(6) })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .position({ x: 0, y: c.posY(87) })
    }

    Column() {
      if (c.content.coupletUp.trim() !== '' || c.content.coupletDown.trim() !== '') {
        // 1.4.8 上下联双列：Row 左->右为 [下联, 上联]，即上联居右（传统右起阅读序）
        Row({ space: c.f(coupletPairFontPx(c) * 1.8) }) {
          if (c.content.coupletDown.trim() !== '') {
            Text(coupletColText(coupletDownLayout(c)))
              .fontSize(c.f(coupletPairFontPx(c)))
              .lineHeight(c.f(coupletPairFontPx(c) * 1.36))
              .fontWeight(FontWeight.Bold)
              .fontColor(c.pal().title)
              .fontFamily(c.font())
              .textAlign(TextAlign.Center)
              .shadow({ radius: c.f(16), color: '#66000000', offsetY: c.f(3) })
          }
          if (c.content.coupletUp.trim() !== '') {
            Text(coupletColText(coupletUpLayout(c)))
              .fontSize(c.f(coupletPairFontPx(c)))
              .lineHeight(c.f(coupletPairFontPx(c) * 1.36))
              .fontWeight(FontWeight.Bold)
              .fontColor(c.pal().title)
              .fontFamily(c.font())
              .textAlign(TextAlign.Center)
              .shadow({ radius: c.f(16), color: '#66000000', offsetY: c.f(3) })
          }
        }
        .alignItems(VerticalAlign.Top)
        if (coupletPairTruncated(c) > 0 && !c.isThumb) {
          Text($r('app.string.poster_truncated_hint', coupletPairTruncated(c)))
            .fontSize(c.f(18))
            .fontColor(c.hexA(c.pal().title, 'B3'))
            .fontFamily(c.font())
            .opacity(0.75)
            .maxLines(1)
        }
      } else if (c.content.body.trim() === '') {
        Text($r('app.string.poster_empty_hint'))
          .fontSize(c.f(30))
          .fontColor(c.hexA(c.pal().title, 'CC'))
          .fontFamily(c.font())
          .width('100%')
          .textAlign(TextAlign.Center)
      } else {
        Row({ space: c.f(coupletLayout(c).fontPx * 0.9) }) {
          ForEach(c.vertRenderCols(coupletLayout(c).columns),
            (col: string[], i: number) => {
              Text(col.join('\n'))
                .fontSize(c.f(coupletLayout(c).fontPx))
                .lineHeight(c.f(coupletLayout(c).fontPx * 1.36))
                .fontWeight(FontWeight.Bold)
                .fontColor(c.pal().title)
                .fontFamily(c.font())
                .textAlign(TextAlign.Center)
                .shadow({ radius: c.f(16), color: '#66000000', offsetY: c.f(3) })
            }, (col: string[], i: number) =>
            i.toString() + '-' + col.length.toString() + '-' + (col.length > 0 ? col[0] : ''))
        }
        .alignItems(VerticalAlign.Top)
        // 1.4.6 根因 C：竖排截断改内核 truncatedChars 口径，替代旧 vertColsRtl 的 '…' 静默截断
        if (coupletLayout(c).truncated && !c.isThumb) {
          Text($r('app.string.poster_truncated_hint', coupletLayout(c).truncatedChars))
            .fontSize(c.f(18))
            .fontColor(c.hexA(c.pal().title, 'B3'))
            .fontFamily(c.font())
            .opacity(0.75)
            .maxLines(1)
        }
      }
    }
    .width(c.previewWidth - c.f(212) * 2)
    .height(c.h() - c.fy(238) - c.fy(174))
    .alignItems(HorizontalAlign.Center)
    .position({ x: c.posX(212), y: c.posY(238) })

    if (c.content.sign.trim() !== '') {
      Column() {
        Text(vertChars(c.content.sign).join('\n'))
          .fontSize(c.f(22))
          .lineHeight(c.f(29))
          .fontColor(c.hexA(c.pal().title, 'D9'))
          .fontFamily(c.font())
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(HorizontalAlign.End)
      .padding({ right: c.f(100), bottom: c.f(148) })
    }

    Text('HAPPY NEW YEAR · POCKET BLESSING')
      .fontSize(c.f(19))
      .letterSpacing(c.f(10))
      .fontColor(c.hexA(c.pal().sub, '99'))
      .width('100%')
      .textAlign(TextAlign.Center)
      .position({ x: 0, y: c.h() - c.posY(93) })
  }
  .width('100%')
  .height('100%')
}

@Builder
export function RedCouplet(c: PosterRenderCtx) {
  Stack() {
    RedCoupletDecor(c)
    RedCoupletContent(c)

    Column()
      .width('100%')
      .height('100%')
      .radialGradient({
        center: ['50%', '50%'],
        radius: '95%',
        colors: [['#00000000', 0.58], [c.hexA('#3C0204', '6B'), 1]],
      })
      .hitTestBehavior(HitTestMode.None)
  }
  .width('100%')
  .height('100%')
}
