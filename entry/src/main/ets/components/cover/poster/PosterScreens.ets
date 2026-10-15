/**
 * 文案海报模板 · 屏幕设备组（1.4.7 P2-1 拆分自 CopyPosterPreview）：
 * T5 LCD 像素屏 / T6 CRT 终端屏 / T8 掌机游戏机；LcdSignalBars/LcdTopBar/LcdBox/LcdSoftBar 为组内局部子构建器。
 */
import { CopyPosterRatio } from '../../../model/CopyPosterModels';
import { CopyPosterTemplates } from '../../../core/cover/CopyPosterTemplates';
import { PosterRenderCtx } from './PosterRenderCtx';
import { PinyinBody } from './PosterSharedBuilders';

// ---------- T5 LCD 像素屏（功能机斜拍风，参照 docs/页面渲染失败问题排查.html） ----------

/** 辉光辅助色：accent 前加透明度（如 '#CC' -> '#CC9EC9FF'） */
function glowColor(c: PosterRenderCtx, alphaHex: string): string {
  return alphaHex + c.pal().accent.substring(1);
}

/** 信号格：4 根递增竖条 */
@Builder
function LcdSignalBars(c: PosterRenderCtx) {
  Row({ space: c.f(4) }) {
    Row().width(c.f(5)).height(c.f(8)).borderRadius(c.f(1)).backgroundColor(c.pal().accent)
    Row().width(c.f(5)).height(c.f(13)).borderRadius(c.f(1)).backgroundColor(c.pal().accent)
    Row().width(c.f(5)).height(c.f(18)).borderRadius(c.f(1)).backgroundColor(c.pal().accent)
    Row().width(c.f(5)).height(c.f(24)).borderRadius(c.f(1)).backgroundColor(c.pal().accent)
  }
  .alignItems(VerticalAlign.Bottom)
}

/** 顶部状态栏：左（信号 + 笔图标 + 标签）右（字数 + 静音 + 电池），辉光文字 */
@Builder
function LcdTopBar(c: PosterRenderCtx) {
  Row() {
    Row({ space: c.f(12) }) {
      LcdSignalBars(c)
      if (c.content.tag.trim() !== '') {
        Row({ space: c.f(9) }) {
          Row()
            .width(c.f(24))
            .height(c.f(12))
            .border({ width: { top: c.f(3.5), left: c.f(3.5) }, color: c.pal().sub })
            .rotate({ angle: -35 })
          Text(c.content.tag)
            .fontSize(c.f(34))
            .fontColor(c.pal().sub)
            .fontFamily(c.font())
            .maxLines(1)
            .textShadow([{ radius: c.f(3), color: glowColor(c, '#CC'), offsetX: 0, offsetY: 0 }])
        }
        .alignItems(VerticalAlign.Center)
      }
    }
    .alignItems(VerticalAlign.Center)

    Row({ space: c.f(13) }) {
      Text(c.bodyLen().toString() + '/' + CopyPosterTemplates.MAX_BODY.toString())
        .fontSize(c.f(30))
        .fontColor(c.pal().sub)
        .fontFamily(c.font())
        .textShadow([{ radius: c.f(4), color: glowColor(c, '#B3'), offsetX: 0, offsetY: 0 }])
      Row({ space: c.f(4) }) {
        Row()
          .width(c.f(11))
          .height(c.f(14))
          .border({ width: { left: c.f(3), top: c.f(3), bottom: c.f(3) }, color: c.pal().sub })
        Row().width(c.f(13)).height(c.f(3)).backgroundColor(c.pal().sub).rotate({ angle: 45 })
      }
      .alignItems(VerticalAlign.Center)
      Row() {
        Stack({ alignContent: Alignment.Start }) {
          Row()
            .width(c.f(15))
            .height(c.f(7))
            .backgroundColor(c.pal().sub)
            .margin({ left: c.f(3) })
        }
        .width(c.f(24))
        .height(c.f(13))
        .border({ width: c.f(3), color: c.pal().sub })
        Row().width(c.f(4)).height(c.f(6)).borderRadius(c.f(1)).backgroundColor(c.pal().sub)
      }
      .alignItems(VerticalAlign.Center)
    }
    .alignItems(VerticalAlign.Center)
  }
  .width('100%')
  .justifyContent(FlexAlign.SpaceBetween)
  .alignItems(VerticalAlign.Center)
}

/** 中央文本框：浅灰底 + 像素点纹理 + 深色正文，左对齐，按长度分档缩字号 */
@Builder
function LcdBox(c: PosterRenderCtx) {
  Column() {
    if (c.content.body.trim() === '') {
      Text($r('app.string.poster_empty_hint'))
        .fontSize(c.f(26))
        .fontColor('#8A8A8A')
        .fontFamily(c.font())
        .width('100%')
        .textAlign(TextAlign.Start)
    } else if (c.pyEnabled()) {
      // 可用宽 = 面板 800 - 内容 padding 68 - 文本框 padding 41 = 691，再让 letterSpacing(1.5) 余量 -> 660
      PinyinBody(c, c.bodyFont(43, false, 660), c.pal().title, c.pal().title, false, false, 'none', '100%')
    } else {
      Text(c.content.body)
        .fontSize(c.bodyFont(43, false, 660))
        .lineHeight(c.bodyFont(43, false, 660) * 1.36)
        .fontColor(c.pal().title)
        .fontFamily(c.font())
        .letterSpacing(c.f(1.5))
        .maxLines(c.maxBodyLines(false))
        .textAlign(TextAlign.Start)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      // 1.4.6 根因 C 补缺：T5 此前 maxLines 静默吞字无提示
      if (c.truncatedHint() > 0 && !c.isThumb) {
        Text($r('app.string.poster_truncated_hint', c.truncatedHint()))
          .fontSize(c.f(16))
          .fontColor('#8A8A8A')
          .fontFamily(c.font())
          .letterSpacing(c.f(1.5))
          .opacity(0.75)
          .width('100%')
          .textAlign(TextAlign.Start)
          .maxLines(1)
      }
    }
  }
  .width('100%')
  .constraintSize({ minHeight: c.f(160) })
  .justifyContent(FlexAlign.Center)
  .alignItems(HorizontalAlign.Start)
  .padding({ left: c.f(20), right: c.f(21), top: c.f(20), bottom: c.f(24) })
  .backgroundColor(c.pal().block)
  .borderRadius(c.f(2))
  .border({ width: c.f(3), color: '#EFEFEF' })
  .backgroundImage($r('app.media.poster_lcd_dots'), ImageRepeat.XY)
  .backgroundImageSize({ width: c.f(7), height: c.f(7) })
}

/** 底部软键行：左软键 + 中间署名（运营商位）+ 右软键 */
@Builder
function LcdSoftBar(c: PosterRenderCtx) {
  Row() {
    Text($r('app.string.poster_soft_left'))
      .fontSize(c.f(33))
      .fontColor(c.pal().sub)
      .fontFamily(c.font())
      .textShadow([{ radius: c.f(3), color: glowColor(c, '#99'), offsetX: 0, offsetY: 0 }])
    if (c.content.sign.trim() !== '') {
      Text(c.content.sign)
        .fontSize(c.f(28))
        .fontColor(c.pal().sub)
        .fontFamily(c.font())
        .maxLines(1)
        .textShadow([{ radius: c.f(3), color: glowColor(c, '#99'), offsetX: 0, offsetY: 0 }])
    }
    Text($r('app.string.poster_soft_right'))
      .fontSize(c.f(33))
      .fontColor(c.pal().sub)
      .fontFamily(c.font())
      .textShadow([{ radius: c.f(3), color: glowColor(c, '#99'), offsetX: 0, offsetY: 0 }])
  }
  .width('100%')
  .justifyContent(FlexAlign.SpaceBetween)
  .alignItems(VerticalAlign.Center)
  .padding({ left: c.f(6), right: c.f(6) })
}

/** T5 面板最小高：1:1 内容自适应（返回 0 视觉不变）；3:4/9:16 按 h() 放大填满画布，消除上下留白（2026-10-14 裁定） */
function lcdPanelMinH(c: PosterRenderCtx): number {
  if (c.ratioKind === CopyPosterRatio.SQUARE) {
    return 0;
  }
  return c.h() * 0.68;
}

/**
 * T5 斜拍角：1:1 保持 -12°；画布越高角度越小（3:4 → -5°，9:16 → -3°）。
 * 面板 800 宽 × 高 H 旋转 θ 后包围盒宽 800·cosθ + H·sinθ 须 ≤ 画布 900：
 * 面板按 h() 放大后仍用 -12° 会横向溢出画布（3:4 H=816 时包围盒 952>900），
 * 动态收缩角度后面板既填满画布又不出框。
 */
function lcdAngle(c: PosterRenderCtx): number {
  if (c.ratioKind === CopyPosterRatio.SQUARE) {
    return -12;
  }
  return c.ratioKind === CopyPosterRatio.PORTRAIT ? -5 : -3;
}

/** LCD 面板整体：状态栏 + 文本框 + 软键 + 暗角，3D 斜拍透视（斜着拍的感觉也要在） */
@Builder
export function LcdPixel(c: PosterRenderCtx) {
  Column() {
    Column() {
      Stack() {
        Column({ space: c.f(15) }) {
          LcdTopBar(c)
          LcdBox(c)
          LcdSoftBar(c)
        }
        .width('100%')
        .constraintSize({ minHeight: lcdPanelMinH(c) })
        .justifyContent(FlexAlign.SpaceBetween)
        .padding({ left: c.f(34), right: c.f(34), top: c.f(28), bottom: c.f(26) })

        Column()
          .width('100%')
          .height('100%')
          .radialGradient({
            center: ['50%', '50%'],
            radius: '85%',
            colors: [['#00000000', 0], ['#00000000', 0.42], ['#CC000000', 1]],
          })
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .backgroundColor(c.pal().grid)
      .borderRadius(c.f(2))
      .clip(true)
      .shadow({ radius: c.f(34), color: glowColor(c, '#2E'), offsetX: 0, offsetY: c.f(8) })
    }
    .width(c.f(800))
    .rotate({
      x: 0.45,
      y: -0.28,
      z: 1,
      angle: lcdAngle(c),
      centerX: '50%',
      centerY: '50%',
      perspective: c.f(1000) * c.density,
    })
  }
  .width('100%')
  .height('100%')
  .justifyContent(FlexAlign.Center)
  .alignItems(HorizontalAlign.Center)
}

// ---------- T6 CRT 终端屏（米色复古显示器 + 荧光屏） ----------


@Builder
export function CrtTerminal(c: PosterRenderCtx) {
  Stack() {
    Column() {
      Stack() {
        Column() {
          Text('C:\\> type ' + (c.content.tag.trim() !== '' ? c.content.tag.trim() : 'quote') + '.txt')
            .fontSize(c.f(28))
            .fontColor(c.pal().sub)
            .fontFamily(c.font())
            .maxLines(1)
            .width('100%')
            .textAlign(TextAlign.Start)
          Row()
            .width('100%')
            .height(c.f(2))
            .backgroundColor(c.pal().accent)
            .opacity(0.5)
            .margin({ top: c.f(12), bottom: c.f(18) })
          if (c.content.body.trim() === '') {
            Text($r('app.string.poster_empty_hint'))
              .fontSize(c.f(28))
              .fontColor(c.pal().sub)
              .fontFamily(c.font())
              .width('100%')
              .textAlign(TextAlign.Start)
          } else if (c.pyEnabled()) {
            // 可用宽 = 显示器 720 - 壳 padding 44 - 屏 padding 60 = 616
            PinyinBody(c, c.bodyFont(50, false, 616), c.pal().title, c.pal().sub, false, false, 'soft', '100%')
          } else {
            Text(c.content.body)
              .fontSize(c.bodyFont(50, false, 616))
              .lineHeight(c.bodyFont(50, false, 616) * 1.5)
              .fontColor(c.pal().title)
              .fontFamily(c.font())
              .maxLines(c.maxBodyLines(false))
              .textAlign(TextAlign.Start)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textShadow([{ radius: c.f(3), color: c.hexA(c.pal().accent, '#B3'), offsetX: 0, offsetY: 0 }])
              .width('100%')
            // 1.4.6 根因 C 补缺：T6 此前 maxLines 静默吞字无提示
            if (c.truncatedHint() > 0 && !c.isThumb) {
              Text($r('app.string.poster_truncated_hint', c.truncatedHint()))
                .fontSize(c.f(18))
                .fontColor(c.pal().sub)
                .fontFamily(c.font())
                .opacity(0.75)
                .width('100%')
                .textAlign(TextAlign.Start)
                .maxLines(1)
            }
          }
          Text('> -- ' + (c.content.sign.trim() !== '' ? c.content.sign : '_') + ' ▌')
            .fontSize(c.f(32))
            .fontColor(c.pal().sub)
            .fontFamily(c.font())
            .maxLines(1)
            .margin({ top: c.f(20) })
            .width('100%')
            .textAlign(TextAlign.Start)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: c.f(30), right: c.f(30), top: c.f(28), bottom: c.f(28) })

        Column()
          .width('64%')
          .height('42%')
          .linearGradient({ angle: 115, colors: [['#17FFFFFF', 0], ['#06FFFFFF', 0.55], ['#00FFFFFF', 1]] })
          .position({ x: 0, y: 0 })
          .hitTestBehavior(HitTestMode.None)

        Column()
          .width('100%')
          .height('100%')
          .backgroundImage($r('app.media.poster_crt_scanlines'), ImageRepeat.Y)
          .backgroundImageSize({ width: c.f(4), height: c.f(4) })
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .backgroundColor(c.pal().grid)
      .borderRadius(c.f(14))
      .clip(true)
      .shadow({ radius: c.f(26), color: c.hexA(c.pal().accent, '#30'), offsetX: 0, offsetY: 0 })

      Row() {
        Circle({ width: c.f(12), height: c.f(12) })
          .fill('#FF4433')
          .shadow({ radius: c.f(6), color: '#80FF4433' })
        Text('PHOSPHOR · 80C')
          .fontSize(c.f(16))
          .letterSpacing(c.f(5))
          .fontColor('#8D8471')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Row({ space: c.f(10) }) {
          Stack({ alignContent: Alignment.Top }) {
            Row().width(c.f(2)).height(c.f(8)).backgroundColor('#8D8471')
          }
          .width(c.f(22))
          .height(c.f(22))
          .borderRadius(c.f(11))
          .backgroundColor('#EFEADE')
          .shadow({ radius: c.f(3), color: '#4D000000', offsetY: c.f(1) })
          .rotate({ angle: -30 })
          Stack({ alignContent: Alignment.Top }) {
            Row().width(c.f(2)).height(c.f(8)).backgroundColor('#8D8471')
          }
          .width(c.f(22))
          .height(c.f(22))
          .borderRadius(c.f(11))
          .backgroundColor('#EFEADE')
          .shadow({ radius: c.f(3), color: '#4D000000', offsetY: c.f(1) })
          .rotate({ angle: 20 })
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height(c.f(72))
      .padding({ left: c.f(8), right: c.f(18) })
      .alignItems(VerticalAlign.Center)
    }
    .width(c.f(720))
    .padding({ left: c.f(22), right: c.f(22), top: c.f(22), bottom: c.f(0) })
    .backgroundColor(c.pal().block)
    .borderRadius({ topLeft: c.f(26), topRight: c.f(26), bottomLeft: c.f(30), bottomRight: c.f(30) })
    .shadow({ radius: c.f(46), color: '#8C000000', offsetY: c.f(16) })
    .rotate({
      x: 0.25,
      y: -0.14,
      z: 1,
      angle: -5,
      centerX: '50%',
      centerY: '50%',
      perspective: c.f(1100) * c.density,
    })

    Column()
      .width('100%')
      .height('100%')
      .radialGradient({
        center: ['50%', '50%'],
        radius: '88%',
        colors: [['#00000000', 0], ['#00000000', 0.55], ['#B3000000', 1]],
      })
      .hitTestBehavior(HitTestMode.None)
  }
  .width('100%')
  .height('100%')
  .alignContent(Alignment.Center)
}

// ---------- T8 掌机游戏机（橄榄绿点阵屏） ----------

@Builder
export function HandheldConsole(c: PosterRenderCtx) {
  Stack() {
    Column({ space: c.f(16) }) {
      Row() {
        Row({ space: c.f(5) }) {
          Circle({ width: c.f(8), height: c.f(8) })
            .fill('#E33B22')
            .shadow({ radius: c.f(4), color: '#80FF4433' })
          Text('BATTERY')
            .fontSize(c.f(10))
            .fontColor('#8B909A')
            .letterSpacing(c.f(1))
        }
        .alignItems(VerticalAlign.Center)
        Text(c.content.tag.trim() !== '' ? c.content.tag : 'POCKET-8')
          .fontSize(c.f(14))
          .fontColor('#AEB3BD')
          .letterSpacing(c.f(3))
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)

      Column() {
        Stack() {
          Column({ space: c.f(12) }) {
            Row() {
              Text('♥♥♥✦')
                .fontSize(c.f(20))
                .fontColor(c.pal().accent)
                .fontWeight(FontWeight.Bold)
              Text('SCORE ' + c.bodyLen().toString())
                .fontSize(c.f(17))
                .fontColor(c.pal().accent)
                .fontWeight(FontWeight.Bold)
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)

            Column() {
              if (c.content.body.trim() === '') {
                Text($r('app.string.poster_empty_hint'))
                  .fontSize(c.f(24))
                  .fontColor(c.pal().accent)
                  .fontFamily(c.font())
                  .width('100%')
                  .textAlign(TextAlign.Start)
              } else if (c.pyEnabled()) {
                // 可用宽 = 主机 440 - padding 48 - 屏 padding 28 - 边框 6 - 内 padding 28 - 文本框边框 6+padding 26 = 298
                PinyinBody(c, c.bodyFont(38, false, 298, 5), c.pal().title, c.pal().accent, false, false,
                  'none', '100%')
              } else {
                Text(c.content.body)
                  .fontSize(c.bodyFont(38, false, 298, 5))
                  .lineHeight(c.bodyFont(38, false, 298, 5) * 1.55)
                  .fontColor(c.pal().title)
                  .fontFamily(c.font())
                  .maxLines(5)
                  .textAlign(TextAlign.Start)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                if (c.truncatedHint() > 0 && !c.isThumb) {
                  Text($r('app.string.poster_truncated_hint', c.truncatedHint()))
                    .fontSize(c.f(16))
                    .fontColor(c.pal().accent)
                    .fontFamily(c.font())
                    .width('100%')
                    .textAlign(TextAlign.Start)
                    .maxLines(1)
                }
              }
            }
            .width('100%')
            .border({ width: c.f(3), color: c.pal().accent })
            .padding(c.f(13))

            if (c.content.sign.trim() !== '') {
              Text('▶ ' + c.content.sign + ' ▼')
                .fontSize(c.f(20))
                .fontColor(c.pal().accent)
                .fontWeight(FontWeight.Bold)
                .letterSpacing(c.f(2))
                .maxLines(1)
            }
          }
          .width('100%')
          .padding(c.f(14))

          Column()
            .width('100%')
            .height('100%')
            .backgroundImage($r('app.media.poster_lcd_dots'), ImageRepeat.XY)
            .backgroundImageSize({ width: c.f(6), height: c.f(6) })
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .backgroundColor(c.pal().grid)
        .border({ width: c.f(3), color: c.pal().accent })
        .clip(true)

        Text('DOT MATRIX TEXT SYSTEM')
          .fontSize(c.f(9))
          .letterSpacing(c.f(3))
          .fontColor('#7D828D')
          .margin({ top: c.f(9) })
      }
      .width('100%')
      .backgroundColor('#171920')
      .borderRadius({ topLeft: c.f(10), topRight: c.f(10), bottomLeft: c.f(18), bottomRight: c.f(18) })
      .padding(c.f(14))

      Row() {
        Stack() {
          Row().width(c.f(78)).height(c.f(25)).borderRadius(c.f(6)).backgroundColor('#212329')
          Row().width(c.f(25)).height(c.f(78)).borderRadius(c.f(6)).backgroundColor('#212329')
          Circle({ width: c.f(19), height: c.f(19) }).fill('#15171B')
        }
        .width(c.f(78))
        .height(c.f(78))

        Row({ space: c.f(13) }) {
          Column({ space: c.f(5) }) {
            Circle({ width: c.f(37), height: c.f(37) }).fill('#B04A70')
            Text('B')
              .fontSize(c.f(12))
              .fontColor('#C9CDD6')
              .fontWeight(FontWeight.Bold)
          }
          .alignItems(HorizontalAlign.Center)
          Column({ space: c.f(5) }) {
            Circle({ width: c.f(37), height: c.f(37) }).fill('#B04A70')
            Text('A')
              .fontSize(c.f(12))
              .fontColor('#C9CDD6')
              .fontWeight(FontWeight.Bold)
          }
          .alignItems(HorizontalAlign.Center)
        }
        .rotate({ angle: -16 })
        .margin({ right: c.f(4) })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
      .padding({ left: c.f(4), right: c.f(10) })

      Row({ space: c.f(26) }) {
        Column({ space: c.f(4) }) {
          Row().width(c.f(34)).height(c.f(10)).borderRadius(c.f(6)).backgroundColor('#212329')
          Text('SELECT')
            .fontSize(c.f(9))
            .fontColor('#AEB3BD')
            .letterSpacing(c.f(2))
        }
        .alignItems(HorizontalAlign.Center)
        Column({ space: c.f(4) }) {
          Row().width(c.f(34)).height(c.f(10)).borderRadius(c.f(6)).backgroundColor('#212329')
          Text('START')
            .fontSize(c.f(9))
            .fontColor('#AEB3BD')
            .letterSpacing(c.f(2))
        }
        .alignItems(HorizontalAlign.Center)
      }
      .rotate({ angle: -16 })

      Row() {
        Row({ space: c.f(5) }) {
          Row().width(c.f(30)).height(c.f(4)).borderRadius(c.f(2)).backgroundColor('#1C1E23')
          Row().width(c.f(30)).height(c.f(4)).borderRadius(c.f(2)).backgroundColor('#1C1E23')
          Row().width(c.f(30)).height(c.f(4)).borderRadius(c.f(2)).backgroundColor('#1C1E23')
          Row().width(c.f(30)).height(c.f(4)).borderRadius(c.f(2)).backgroundColor('#1C1E23')
          Row().width(c.f(30)).height(c.f(4)).borderRadius(c.f(2)).backgroundColor('#1C1E23')
        }
        .rotate({ angle: -28 })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ right: c.f(18), bottom: c.f(6) })
    }
    .width(c.f(440))
    .padding({ left: c.f(24), right: c.f(24), top: c.f(18), bottom: c.f(22) })
    .backgroundColor(c.pal().block)
    .borderRadius({ topLeft: c.f(16), topRight: c.f(16), bottomLeft: c.f(38), bottomRight: c.f(38) })
    .shadow({ radius: c.f(36), color: '#73000000', offsetY: c.f(14) })
    .rotate({
      x: 0.35,
      y: -0.2,
      z: 1,
      angle: -5,
      centerX: '50%',
      centerY: '50%',
      perspective: c.f(1000) * c.density,
    })

    Column()
      .width('100%')
      .height('100%')
      .radialGradient({
        center: ['50%', '50%'],
        radius: '85%',
        colors: [['#00000000', 0], ['#00000000', 0.5], ['#A6000000', 1]],
      })
      .hitTestBehavior(HitTestMode.None)
  }
  .width('100%')
  .height('100%')
  .alignContent(Alignment.Center)
}
