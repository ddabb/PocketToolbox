/**
 * 文案海报模板 · 生活质感组（1.4.7 P2-1 拆分自 CopyPosterPreview）：
 * T12 聊天气泡 / T13 黑胶唱片 / T14 电影字幕卡；ChatAvatar/FilmStrip 为组内局部子构建器。
 */
import { PosterRenderCtx } from './PosterRenderCtx';
import { PinyinBody } from './PosterSharedBuilders';

// ---------- T12 聊天气泡（微信式对话，参照 docs/文案海报候选_聊天气泡.html） ----------

/** 对方头像首字 */
function avatarChar(c: PosterRenderCtx): string {
  let t: string = c.content.tag.trim();
  if (t !== '') {
    return t.charAt(0);
  }
  return 'P';
}

@Builder
function ChatAvatar(c: PosterRenderCtx, sizePx: number, bg: string, ch: string, color: string) {
  Stack() {
    Text(ch)
      .fontSize(c.f(sizePx * 0.5))
      .fontWeight(FontWeight.Bold)
      .fontColor(color)
      .fontFamily(c.font())
      .maxLines(1)
  }
  .width(c.f(sizePx))
  .height(c.f(sizePx))
  .borderRadius(c.f(sizePx * 0.21))
  .backgroundColor(bg)
}

@Builder
export function ChatBubbles(c: PosterRenderCtx) {
  Column() {
    Row({ space: c.f(18) }) {
      ChatAvatar(c, 61, c.pal().accent, avatarChar(c), c.pal().title)
      Column() {
        Text(c.content.tag.trim() !== '' ? c.content.tag.trim() : 'POCKET')
          .fontSize(c.f(26))
          .fontWeight(FontWeight.Bold)
          .fontColor(c.pal().title)
          .fontFamily(c.font())
          .maxLines(1)
        Text($r('app.string.poster_chat_sub'))
          .fontSize(c.f(16))
          .fontColor(c.pal().sub)
          .margin({ top: c.f(3) })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Blank()
      Text('···')
        .fontSize(c.f(29))
        .fontColor(c.hexA(c.pal().title, '66'))
        .letterSpacing(c.f(3))
    }
    .width('100%')
    .height(c.f(106))
    .padding({ left: c.f(26), right: c.f(26) })
    .backgroundColor(c.pal().grid)
    .border({ width: { bottom: c.f(1.6) }, color: c.hexA(c.pal().sub, '33') })
    .alignItems(VerticalAlign.Center)

    Column() {
      Text('18:05')
        .fontSize(c.f(16))
        .fontColor(c.pal().sub)
        .padding({ left: c.f(16), right: c.f(16), top: c.f(5), bottom: c.f(5) })
        .backgroundColor(c.hexA(c.pal().sub, '24'))
        .borderRadius(c.f(999))
        .alignSelf(ItemAlign.Center)

      Row({ space: c.f(14) }) {
        ChatAvatar(c, 55, c.pal().accent, avatarChar(c), c.pal().title)
        if (c.content.body.trim() === '') {
          Text($r('app.string.poster_empty_hint'))
            .fontSize(c.f(25))
            .fontColor(c.pal().sub)
            .fontFamily(c.font())
            .lineHeight(c.f(25) * 1.55)
            .padding({ left: c.f(22), right: c.f(22), top: c.f(18), bottom: c.f(18) })
            .backgroundColor(c.pal().block)
            .borderRadius({ topLeft: c.f(7), topRight: c.f(19), bottomLeft: c.f(19), bottomRight: c.f(19) })
            .constraintSize({ maxWidth: c.previewWidth * 0.64 })
            .shadow({ radius: c.f(8), color: '#12000000', offsetY: c.f(3) })
        } else if (c.pyEnabled()) {
          // 1.4.6 P0-1 B 类：气泡接内核，可用宽 = 0.64×900 - 左右 padding 44 = 532
          Column() {
            PinyinBody(c, c.bodyFont(25, false, 532, c.maxBodyLines(false)), c.pal().title,
              c.pal().sub, false, false, 'none', c.previewWidth * 0.64 - c.f(44))
          }
          .padding({ left: c.f(22), right: c.f(22), top: c.f(18), bottom: c.f(18) })
          .backgroundColor(c.pal().block)
          .borderRadius({ topLeft: c.f(7), topRight: c.f(19), bottomLeft: c.f(19), bottomRight: c.f(19) })
          .constraintSize({ maxWidth: c.previewWidth * 0.64 })
          .shadow({ radius: c.f(8), color: '#12000000', offsetY: c.f(3) })
        } else {
          // 1.4.6 P0-1 B 类 + 根因 C：字号走内核（消阶梯骤变），截断提示共享气泡样式
          Column() {
            Text(c.content.body)
              .fontSize(c.bodyFont(25, false, 532, c.maxBodyLines(false)))
              .lineHeight(c.bodyFont(25, false, 532, c.maxBodyLines(false)) * 1.55)
              .fontColor(c.pal().title)
              .fontFamily(c.font())
              .maxLines(c.maxBodyLines(false))
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (c.truncatedHint() > 0 && !c.isThumb) {
              Text($r('app.string.poster_truncated_hint', c.truncatedHint()))
                .fontSize(c.f(16))
                .fontColor(c.pal().sub)
                .fontFamily(c.font())
                .opacity(0.75)
                .maxLines(1)
                .margin({ top: c.f(4) })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .padding({ left: c.f(22), right: c.f(22), top: c.f(18), bottom: c.f(18) })
          .backgroundColor(c.pal().block)
          .borderRadius({ topLeft: c.f(7), topRight: c.f(19), bottomLeft: c.f(19), bottomRight: c.f(19) })
          .constraintSize({ maxWidth: c.previewWidth * 0.64 })
          .shadow({ radius: c.f(8), color: '#12000000', offsetY: c.f(3) })
        }
        Row().layoutWeight(1)
      }
      .width('100%')
      .margin({ top: c.f(26) })
      .alignItems(VerticalAlign.Top)

      if (c.content.sign.trim() !== '') {
        Row({ space: c.f(14) }) {
          Row().layoutWeight(1)
          Text(c.content.sign)
            .fontSize(c.f(25))
            .lineHeight(c.f(25) * 1.55)
            .fontColor(c.pal().title)
            .fontFamily(c.font())
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: c.f(22), right: c.f(22), top: c.f(18), bottom: c.f(18) })
            .backgroundColor(c.pal().accent)
            .borderRadius({ topLeft: c.f(19), topRight: c.f(7), bottomLeft: c.f(19), bottomRight: c.f(19) })
            .constraintSize({ maxWidth: c.previewWidth * 0.64 })
            .shadow({ radius: c.f(8), color: '#12000000', offsetY: c.f(3) })
          ChatAvatar(c, 55, c.pal().block, c.content.sign.trim().charAt(0), c.pal().accent)
        }
        .width('100%')
        .margin({ top: c.f(26) })
        .alignItems(VerticalAlign.Top)
      }

      Row().layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(c.pal().bg)
    .padding({ left: c.f(26), right: c.f(26), top: c.f(29), bottom: c.f(19) })

    Row({ space: c.f(16) }) {
      Stack() {
        Text('+')
          .fontSize(c.f(32))
          .fontWeight(FontWeight.Lighter)
          .fontColor(c.pal().sub)
      }
      .width(c.f(51))
      .height(c.f(51))
      .borderRadius(c.f(25.5))
      .border({ width: c.f(3), color: c.hexA(c.pal().sub, '73') })

      Row() {
        Text('···')
          .fontSize(c.f(20))
          .letterSpacing(c.f(3))
          .fontColor(c.hexA(c.pal().sub, '99'))
          .margin({ left: c.f(24) })
      }
      .layoutWeight(1)
      .height(c.f(58))
      .backgroundColor(c.pal().bg)
      .borderRadius(c.f(999))
      .border({ width: c.f(2), color: c.hexA(c.pal().sub, '33') })
      .alignItems(VerticalAlign.Center)

      Stack() {
        Text('◉')
          .fontSize(c.f(24))
          .fontColor(c.pal().sub)
      }
      .width(c.f(51))
      .height(c.f(51))
      .borderRadius(c.f(25.5))
      .border({ width: c.f(3), color: c.hexA(c.pal().sub, '73') })
    }
    .width('100%')
    .height(c.f(93))
    .padding({ left: c.f(22), right: c.f(22) })
    .backgroundColor(c.pal().block)
    .border({ width: { top: c.f(1.6) }, color: c.hexA(c.pal().sub, '40') })
    .alignItems(VerticalAlign.Center)
  }
  .width('100%')
  .height('100%')
}

// ---------- T13 黑胶唱片（聚光灯唱片 + 曲目单，参照 docs/文案海报候选_黑胶唱片.html） ----------

@Builder
export function VinylRecord(c: PosterRenderCtx) {
  Stack() {
    Column()
      .width(c.f(739))
      .height(c.f(739))
      .borderRadius(c.f(370))
      .radialGradient({
        center: ['50%', '50%'],
        radius: '50%',
        colors: [[c.hexA(c.pal().accent, '21'), 0], ['#00000000', 0.62], ['#00000000', 1]],
      })
      .position({ x: c.previewWidth / 2 - c.posX(370), y: c.posY(208) })
      .hitTestBehavior(HitTestMode.None)

    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(c.f(267))
        .radialGradient({
          center: ['50%', '50%'],
          radius: '100%',
          colors: [
            [c.pal().grid, 0], ['#12100D', 0.05], [c.pal().grid, 0.1], ['#12100D', 0.15],
            [c.pal().grid, 0.2], ['#12100D', 0.25], [c.pal().grid, 0.3], ['#12100D', 0.35],
            [c.pal().grid, 0.4], ['#12100D', 0.45], [c.pal().grid, 0.5], ['#12100D', 0.55],
            [c.pal().grid, 0.6], ['#12100D', 0.65], [c.pal().grid, 0.7], ['#12100D', 0.75],
            [c.pal().grid, 0.8], ['#12100D', 0.85], [c.pal().grid, 0.9], ['#12100D', 0.95],
            ['#12100D', 1],
          ],
        })
        .shadow({ radius: c.f(96), color: '#BF000000', offsetY: c.f(39) })
        .border({ width: c.f(2), color: c.hexA('#FFFFFF', '14') })

      Column()
        .width('100%')
        .height('100%')
        .borderRadius(c.f(267))
        .sweepGradient({
          center: ['50%', '50%'],
          start: 0,
          end: 360,
          colors: [
            ['#00FFFFFF', 0], ['#00FFFFFF', 0.333], ['#1CFFFFFF', 0.334], ['#05FFFFFF', 0.45],
            ['#00FFFFFF', 0.528], ['#00FFFFFF', 0.828], ['#12FFFFFF', 0.878], ['#00FFFFFF', 0.978],
            ['#00FFFFFF', 1],
          ],
        })

      Column() {
        Text(c.content.tag.trim() !== '' ? c.content.tag.trim() : 'POCKET LP')
          .fontSize(c.f(19))
          .fontWeight(FontWeight.Bold)
          .fontColor(c.pal().block)
          .fontFamily(c.font())
          .letterSpacing(c.f(2.4))
          .maxLines(1)
          .constraintSize({ maxWidth: c.f(186) })
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('33⅓ RPM · STEREO')
          .fontSize(c.f(13))
          .fontColor(c.hexA(c.pal().block, 'BF'))
          .letterSpacing(c.f(3.2))
          .margin({ top: c.f(4) })
        Column()
          .width(c.f(14))
          .height(c.f(14))
          .borderRadius(c.f(7))
          .backgroundColor(c.pal().bg)
          .margin({ top: c.f(6) })
      }
      .width(c.f(190))
      .height(c.f(190))
      .borderRadius(c.f(95))
      .backgroundColor(c.pal().accent)
      .border({ width: c.f(1.6), color: c.hexA('#000000', '66') })
      .radialGradient({
        center: ['50%', '38%'],
        radius: '75%',
        colors: [['#2BFFFFFF', 0], ['#00FFFFFF', 0.55], ['#26000000', 1]],
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width(c.f(534))
    .height(c.f(534))
    .rotate({ angle: 14 })
    .position({ x: c.previewWidth / 2 - c.posX(267), y: c.posY(106) })

    Column() {
      Text('SIDE A')
        .fontSize(c.f(18))
        .letterSpacing(c.f(10))
        .fontColor(c.pal().sub)
      Row()
        .width(c.f(55))
        .height(c.f(3))
        .backgroundColor(c.hexA(c.pal().title, '2E'))
        .margin({ top: c.f(16), bottom: c.f(26) })
      Row({ space: c.f(19) }) {
        Text('A1')
          .fontSize(c.f(18))
          .fontColor(c.pal().sub)
          .letterSpacing(c.f(1.6))
        if (c.content.body.trim() === '') {
          Text($r('app.string.poster_empty_hint'))
            .fontSize(c.f(24))
            .fontColor(c.pal().sub)
            .fontFamily(c.font())
            .maxLines(1)
        } else {
          // 1.4.6 P0-1 B 类：曲目行接内核，可用宽 = 行宽 780 - A1/时长/字距让位 = 620，行数预算 2
          Text(c.content.body)
            .fontSize(c.bodyFont(31, false, 620, 2))
            .fontColor(c.pal().title)
            .fontFamily(c.font())
            .letterSpacing(c.f(3))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: c.previewWidth - c.f(120) })
        }
      }
      .alignItems(VerticalAlign.Bottom)
      .margin({ bottom: c.f(16) })

      // 1.4.6 根因 C：曲目行截断提示（body 非空才判 layoutCache，防空文案读到上一帧缓存）
      if (c.content.body.trim() !== '' && c.truncatedHint() > 0 && !c.isThumb) {
        Text($r('app.string.poster_truncated_hint', c.truncatedHint()))
          .fontSize(c.f(16))
          .fontColor(c.pal().sub)
          .fontFamily(c.font())
          .opacity(0.75)
          .maxLines(1)
      }

      Row({ space: c.f(19) }) {
        Text('B1')
          .fontSize(c.f(18))
          .fontColor(c.pal().sub)
          .letterSpacing(c.f(1.6))
        Text(c.content.sign)
          .fontSize(c.f(31))
          .fontColor(c.pal().title)
          .fontFamily(c.font())
          .letterSpacing(c.f(3))
          .maxLines(1)
          .constraintSize({ maxWidth: c.previewWidth - c.f(120) })
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('3:05')
          .fontSize(c.f(16))
          .fontColor(c.pal().sub)
      }
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .position({ x: 0, y: c.posY(688) })

    Text('POCKET RECORDS · 2026')
      .fontSize(c.f(14))
      .letterSpacing(c.f(8))
      .fontColor(c.hexA(c.pal().sub, '8C'))
      .width('100%')
      .textAlign(TextAlign.Center)
      .position({ x: 0, y: c.h() - c.posY(26) })

    Column()
      .width('100%')
      .height('100%')
      .radialGradient({
        center: ['50%', '50%'],
        radius: '80%',
        colors: [['#00000000', 0], ['#00000000', 0.5], ['#A8000000', 1]],
      })
      .hitTestBehavior(HitTestMode.None)
  }
  .width('100%')
  .height('100%')
}

// ---------- T14 电影字幕卡（影院片头卡，参照 docs/文案海报候选_电影字幕卡.html） ----------

@Builder
function FilmStrip(c: PosterRenderCtx, offsetX: number) {
  Column() {
    Column() {
      ForEach([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], (i: number) => {
        Row()
          .width(c.f(26))
          .height(c.f(19))
          .borderRadius(c.f(5))
          .backgroundColor(c.pal().grid)
      }, (i: number) => i.toString())
    }
    .width(c.f(26))
    .height('100%')
    .justifyContent(FlexAlign.SpaceEvenly)
    .alignItems(HorizontalAlign.Center)
  }
  .width(c.f(55))
  .height('100%')
  .backgroundColor(c.pal().block)
  .alignItems(HorizontalAlign.Center)
  .position({ x: offsetX, y: 0 })
}

@Builder
export function CinemaCard(c: PosterRenderCtx) {
  Stack() {
    Column()
      .width('100%')
      .height('100%')
      .linearGradient({ angle: 180, colors: [[c.pal().bg, 0], [c.pal().bg2, 0.55], [c.pal().bg2, 1]] })
      .hitTestBehavior(HitTestMode.None)

    Column()
      .width(c.f(675))
      .height(c.f(675))
      .borderRadius(c.f(337))
      .radialGradient({
        center: ['50%', '50%'],
        radius: '50%',
        colors: [[c.hexA(c.pal().accent, '1A'), 0], ['#00000000', 0.62], ['#00000000', 1]],
      })
      .position({ x: c.previewWidth / 2 - c.posX(337), y: c.posY(378) - c.f(337) })
      .hitTestBehavior(HitTestMode.None)

    FilmStrip(c, 0)
    FilmStrip(c, c.previewWidth - c.f(55))

    Column() {
      Text(c.content.tag.trim() !== '' ? c.content.tag.trim() : 'POCKET PICTURES')
        .fontSize(c.f(19))
        .letterSpacing(c.f(11))
        .fontColor(c.pal().sub)
        .fontFamily(c.font())
        .maxLines(1)
      Row()
        .width(c.f(68))
        .height(c.f(3))
        .backgroundColor(c.pal().accent)
        .margin({ top: c.f(29), bottom: c.f(42) })
      if (c.content.body.trim() === '') {
        Text($r('app.string.poster_empty_hint'))
          .fontSize(c.f(28))
          .fontColor(c.pal().sub)
          .fontFamily(c.font())
          .textAlign(TextAlign.Center)
      } else {
        // 可用宽 = 900 - padding 141*2 = 618，再让 letterSpacing(8) 余量 -> 540；预算留 2 行给署名
        Text(c.content.body)
          .fontSize(c.bodyFont(55, false, 540, c.bodyBudget(2)))
          .lineHeight(c.bodyFont(55, false, 540, c.bodyBudget(2)) * 1.5)
          .fontColor(c.pal().title)
          .fontFamily(c.font())
          .fontWeight(FontWeight.Bold)
          .letterSpacing(c.f(8))
          .maxLines(c.bodyBudget(2))
          .textAlign(TextAlign.Center)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textShadow([{ radius: c.f(29), color: '#CC000000', offsetX: 0, offsetY: c.f(3) }])
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
      if (c.content.sign.trim() !== '') {
        Text(c.content.sign)
          .fontSize(c.f(27))
          .fontColor(c.hexA(c.pal().title, 'B3'))
          .fontFamily(c.font())
          .fontStyle(FontStyle.Italic)
          .letterSpacing(c.f(5))
          .maxLines(1)
          .margin({ top: c.f(39) })
      }
      Row()
        .width(c.f(42))
        .height(c.f(2.5))
        .backgroundColor(c.hexA(c.pal().accent, '8C'))
        .margin({ top: c.f(42), bottom: c.f(29) })
      Text('COMING SOON · OCT 2026')
        .fontSize(c.f(16))
        .letterSpacing(c.f(8))
        .fontColor(c.pal().sub)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: c.f(141), right: c.f(141) })

    Column()
      .width('100%')
      .height('100%')
      .backgroundImage($r('app.media.poster_film_grain'), ImageRepeat.XY)
      .backgroundImageSize({ width: c.f(3), height: c.f(3) })
      .hitTestBehavior(HitTestMode.None)

    Column()
      .width('100%')
      .height('100%')
      .radialGradient({
        center: ['50%', '50%'],
        radius: '80%',
        colors: [['#00000000', 0], ['#00000000', 0.46], ['#C7000000', 1]],
      })
      .hitTestBehavior(HitTestMode.None)
  }
  .width('100%')
  .height('100%')
}
