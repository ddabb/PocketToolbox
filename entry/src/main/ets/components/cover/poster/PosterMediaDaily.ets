/**
 * 文案海报模板 · 生活质感组（1.4.7 P2-1 拆分自 CopyPosterPreview）：
 * T12 聊天气泡 / T13 黑胶唱片 / T14 电影字幕卡。
 * 1.4.6 §2.1.4 根因 D 分层（第四批，同 Festival/Screens/PaperVintage 批纪律）：
 * 采用构建器级分层（树形与渲染节点零变化，行为与 1.4.6 完全一致）：
 *   装饰层（*TimePill/*InputBar、*Spotlight/*Grooves/*Sheen/*Footer/*Vignette、
 *     *Backdrop/*Glow/*Grain、ChatAvatar/FilmStrip 参数化图形件）：
 *     纯图形与固定丝印（18:05/+ ··· ◉ 输入条/33⅓ RPM · STEREO/3:05/
 *     POCKET RECORDS · 2026/COMING SOON · OCT 2026 等），不读 tag/body/sign/bodyLen；
 *   内容层（*HeaderBar/*BodyBubble/*SignBubble、*Label/*TrackList、*Content）：
 *     tag/body/sign 槽位 + 空态/截断提示 + 头像首字实时派生；
 *   组合层（ChatBubbles/VinylRecord/CinemaCard）：按原树序组装，唱片 14° 旋转、
 *     胶片条左右压边与暗角置顶，树序与 1.4.6 完全一致。
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

/** T12 装饰件：头像圆块（参数化首字/底色/字色；1.4.8 M2 对方头像接图——avatarUri 非空渲染图片，空回退首字）
 * 组件化说明：原全局 @Builder 按值传参在 V1 下不随 content.avatarUri 变化刷新（set/remove/re-pick 均冻结），
 * 改 @Component + @Prop 后由父作用域重渲染驱动 @Prop 同步，if 分支逐帧重估（与编辑行 AvatarRow 同模式）。
 */
@Component
struct ChatAvatarNode {
  @Prop sizeVp: number = 0;
  @Prop radiusVp: number = 0;
  @Prop fontVp: number = 0;
  @Prop bg: string = '';
  @Prop ch: string = '';
  @Prop color: string = '';
  @Prop fontFam: string = '';
  @Prop avatarUri: string = '';

  build() {
    if (this.avatarUri !== '') {
      Image('file://' + this.avatarUri)
        .width(this.sizeVp)
        .height(this.sizeVp)
        .borderRadius(this.radiusVp)
        .objectFit(ImageFit.Cover)
    } else {
      Stack() {
        Text(this.ch)
          .fontSize(this.fontVp)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.color)
          .fontFamily(this.fontFam)
          .maxLines(1)
      }
      .width(this.sizeVp)
      .height(this.sizeVp)
      .borderRadius(this.radiusVp)
      .backgroundColor(this.bg)
    }
  }
}

/** T12 内容层·会话顶栏：头像 + 对方昵称（标签槽，空态兜底 POCKET）+ 副题 + ··· */
@Builder
function ChatHeaderBar(c: PosterRenderCtx) {
  Row({ space: c.f(18) }) {
    ChatAvatarNode({
      sizeVp: c.f(61), radiusVp: c.f(61 * 0.21), fontVp: c.f(61 * 0.5),
      bg: c.pal().accent, ch: avatarChar(c), color: c.pal().title,
      fontFam: c.font(), avatarUri: c.content.avatarUri,
    })
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
}

/** T12 装饰件：居中时间胶囊（固定丝印 18:05） */
@Builder
function ChatTimePill(c: PosterRenderCtx) {
  Text('18:05')
    .fontSize(c.f(16))
    .fontColor(c.pal().sub)
    .padding({ left: c.f(16), right: c.f(16), top: c.f(5), bottom: c.f(5) })
    .backgroundColor(c.hexA(c.pal().sub, '24'))
    .borderRadius(c.f(999))
    .alignSelf(ItemAlign.Center)
}

/** T12 内容层·正文气泡：空态提示 / 注音版 PinyinBody / 纯文本+截断提示三分支，共享气泡样式 */
@Builder
function ChatBodyBubble(c: PosterRenderCtx) {
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
}

/** T12 内容层·署名气泡：右对齐强调色气泡（署名首字头像收尾，有署名才渲染） */
@Builder
function ChatSignBubble(c: PosterRenderCtx) {
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
      ChatAvatarNode({
        sizeVp: c.f(55), radiusVp: c.f(55 * 0.21), fontVp: c.f(55 * 0.5),
        bg: c.pal().block, ch: c.content.sign.trim().charAt(0), color: c.pal().accent,
        fontFam: c.font(), avatarUri: '',
      })
    }
    .width('100%')
    .margin({ top: c.f(26) })
    .alignItems(VerticalAlign.Top)
  }
}

/** T12 装饰件：底部输入条（+ 铂 ··· 输入胶囊 ◉ 固定丝印） */
@Builder
function ChatInputBar(c: PosterRenderCtx) {
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

/** T12 组合层：顶栏 → 会话区（时间胶囊/正文气泡/署名气泡/弹性留白）→ 输入条，树序同 1.4.6 */
@Builder
export function ChatBubbles(c: PosterRenderCtx) {
  Column() {
    ChatHeaderBar(c)

    Column() {
      ChatTimePill(c)

      Row({ space: c.f(14) }) {
        ChatAvatarNode({
          sizeVp: c.f(55), radiusVp: c.f(55 * 0.21), fontVp: c.f(55 * 0.5),
          bg: c.pal().accent, ch: avatarChar(c), color: c.pal().title,
          fontFam: c.font(), avatarUri: c.content.avatarUri,
        })
        ChatBodyBubble(c)
        Row().layoutWeight(1)
      }
      .width('100%')
      .margin({ top: c.f(26) })
      .alignItems(VerticalAlign.Top)

      ChatSignBubble(c)

      Row().layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(c.pal().bg)
    .padding({ left: c.f(26), right: c.f(26), top: c.f(29), bottom: c.f(19) })

    ChatInputBar(c)
  }
  .width('100%')
  .height('100%')
}

// ---------- T13 黑胶唱片（聚光灯唱片 + 曲目单，参照 docs/文案海报候选_黑胶唱片.html） ----------

/** T13 装饰件：唱片聚光晕（739 径向渐变） */
@Builder
function RecordSpotlight(c: PosterRenderCtx) {
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
}

/** T13 装饰件：唱片纹路（同芯渐变沟槽 + 投影 + 高光描边） */
@Builder
function RecordGrooves(c: PosterRenderCtx) {
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
}

/** T13 装饰件：唱片扫光（sweep 渐变高光扇面） */
@Builder
function RecordSheen(c: PosterRenderCtx) {
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
}

/** T13 内容层·唱片标签：曲名（标签槽，空态兜底 POCKET LP）+ 33⅓ RPM 丝印 + 中轴孔 */
@Builder
function RecordLabel(c: PosterRenderCtx) {
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

/** T13 组合层·唱片盘：纹路 + 扫光 + 标签，14° 斜置 */
@Builder
function RecordDisc(c: PosterRenderCtx) {
  Stack() {
    RecordGrooves(c)
    RecordSheen(c)
    RecordLabel(c)
  }
  .width(c.f(534))
  .height(c.f(534))
  .rotate({ angle: 14 })
  .position({ x: c.previewWidth / 2 - c.posX(267), y: c.posY(106) })
}

/** T13 内容层·曲目单：SIDE A 丝印 + 分隔线 + A1 正文行（空态/截断提示）+ B1 署名行 + 3:05 */
@Builder
function RecordTrackList(c: PosterRenderCtx) {
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
}

/** T13 装饰件：板底厂牌丝印 POCKET RECORDS · 2026 */
@Builder
function RecordFooter(c: PosterRenderCtx) {
  Text('POCKET RECORDS · 2026')
    .fontSize(c.f(14))
    .letterSpacing(c.f(8))
    .fontColor(c.hexA(c.pal().sub, '8C'))
    .width('100%')
    .textAlign(TextAlign.Center)
    .position({ x: 0, y: c.h() - c.posY(26) })
}

/** T13 装饰件：全幅暗角（中心 50% 径向渐变） */
@Builder
function RecordVignette(c: PosterRenderCtx) {
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

/** T13 组合层：聚光晕 → 唱片盘 → 曲目单 → 厂牌丝印 → 暗角，树序同 1.4.6 */
@Builder
export function VinylRecord(c: PosterRenderCtx) {
  Stack() {
    RecordSpotlight(c)
    RecordDisc(c)
    RecordTrackList(c)
    RecordFooter(c)
    RecordVignette(c)
  }
  .width('100%')
  .height('100%')
}

// ---------- T14 电影字幕卡（影院片头卡，参照 docs/文案海报候选_电影字幕卡.html） ----------

/** T14 装饰件：胶片条（齿孔列 + 基带，offsetX 定位左右两侧） */
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

/** T14 装饰件：影院底幕（bg→bg2 纵向渐变） */
@Builder
function CinemaBackdrop(c: PosterRenderCtx) {
  Column()
    .width('100%')
    .height('100%')
    .linearGradient({ angle: 180, colors: [[c.pal().bg, 0], [c.pal().bg2, 0.55], [c.pal().bg2, 1]] })
    .hitTestBehavior(HitTestMode.None)
}

/** T14 装饰件：中环强调色光晕（675 径向渐变） */
@Builder
function CinemaGlow(c: PosterRenderCtx) {
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
}

/** T14 内容层·片头字幕：厂标（标签槽，空态兜底 POCKET PICTURES）+ 片名正文（空态/截断提示）+ 斜体署名 + COMING SOON 丝印 */
@Builder
function CinemaContent(c: PosterRenderCtx) {
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
}

/** T14 装饰件：胶片颗粒噪点（poster_film_grain 平铺） */
@Builder
function CinemaGrain(c: PosterRenderCtx) {
  Column()
    .width('100%')
    .height('100%')
    .backgroundImage($r('app.media.poster_film_grain'), ImageRepeat.XY)
    .backgroundImageSize({ width: c.f(3), height: c.f(3) })
    .hitTestBehavior(HitTestMode.None)
}

/** T14 装饰件：全幅暗角（中心 50% 径向渐变） */
@Builder
function CinemaVignette(c: PosterRenderCtx) {
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

/** T14 组合层：底幕 → 光晕 → 左右胶片条 → 片头字幕 → 颗粒 → 暗角，树序同 1.4.6 */
@Builder
export function CinemaCard(c: PosterRenderCtx) {
  Stack() {
    CinemaBackdrop(c)
    CinemaGlow(c)

    FilmStrip(c, 0)
    FilmStrip(c, c.previewWidth - c.f(55))

    CinemaContent(c)

    CinemaGrain(c)
    CinemaVignette(c)
  }
  .width('100%')
  .height('100%')
}
