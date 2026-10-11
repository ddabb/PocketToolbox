/**
 * 文案海报预览渲染组件：设计稿 900 宽（1:1 -> 900 高 / 3:4 -> 1200 高），15 种布局
 * 尺寸换算：f(px) = previewWidth * px / 900；主文案按长度分档自动缩字号（emoji 走系统字体兜底）
 */
import { CopyPosterContent, CopyPosterRatio, CopyPosterTemplate } from '../../model/CopyPosterModels';
import { CoverPalette } from '../../model/CoverModels';
import { CopyPosterTemplates } from '../../core/cover/CopyPosterTemplates';

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

  /** 设计稿 px -> vp */
  private f(px: number): number {
    return this.previewWidth * px / 900;
  }

  private h(): number {
    return this.previewWidth * CopyPosterRatio.designHeight(this.ratioKind) / 900;
  }

  private pal(): CoverPalette {
    let list: CoverPalette[] = this.template.palettes;
    if (this.paletteIndex >= 0 && this.paletteIndex < list.length) {
      return list[this.paletteIndex];
    }
    return list[0];
  }

  private font(): string {
    let list: string[] = this.template.fonts;
    if (this.fontIndex >= 0 && this.fontIndex < list.length) {
      return list[this.fontIndex];
    }
    return list.length > 0 ? list[0] : '';
  }

  /** 主文案有效字数（去空白） */
  private bodyLen(): number {
    return this.content.body.replace(new RegExp('\\s', 'g'), '').length;
  }

  /** 主文案字号：常规模板按长度 5 档缩放；大字模板 3 档 + 超 16 字降级常规 */
  private bodyFont(basePx: number, big: boolean): number {
    let n: number = this.bodyLen();
    if (big) {
      if (n <= 4) {
        return this.f(150);
      }
      if (n <= 8) {
        return this.f(112);
      }
      if (n <= 16) {
        return this.f(80);
      }
      return this.f(52);
    }
    if (n <= 8) {
      return this.f(basePx);
    }
    if (n <= 16) {
      return this.f(basePx * 0.8);
    }
    if (n <= 32) {
      return this.f(basePx * 0.62);
    }
    if (n <= 60) {
      return this.f(basePx * 0.48);
    }
    return this.f(basePx * 0.38);
  }

  /** 主文案行数上限：竖图更宽容 */
  private maxBodyLines(big: boolean): number {
    if (big && this.bodyLen() <= 16) {
      return 4;
    }
    return this.ratioKind === CopyPosterRatio.PORTRAIT ? 12 : 8;
  }

  build() {
    Stack() {
      this.BgLayer()
      if (this.template.layout === 'warm_label') {
        this.WarmLabel()
      } else if (this.template.layout === 'pure_minimal') {
        this.PureMinimal()
      } else if (this.template.layout === 'handwrite') {
        this.Handwrite()
      } else if (this.template.layout === 'lcd_pixel') {
        this.LcdPixel()
      } else if (this.template.layout === 'crt_terminal') {
        this.CrtTerminal()
      } else if (this.template.layout === 'neon_sign') {
        this.NeonSign()
      } else if (this.template.layout === 'handheld_console') {
        this.HandheldConsole()
      } else if (this.template.layout === 'vintage_ticket') {
        this.VintageTicket()
      } else if (this.template.layout === 'split_flap') {
        this.SplitFlap()
      } else if (this.template.layout === 'vintage_news') {
        this.VintageNews()
      } else if (this.template.layout === 'chat_bubbles') {
        this.ChatBubbles()
      } else if (this.template.layout === 'vinyl_record') {
        this.VinylRecord()
      } else if (this.template.layout === 'cinema_card') {
        this.CinemaCard()
      } else if (this.template.layout === 'cork_notice') {
        this.CorkNotice()
      } else {
        this.BigImpact()
      }
    }
    .width(this.previewWidth)
    .height(this.h())
    .clip(true)
  }

  @Builder
  BgLayer() {
    if (this.pal().bg2 !== '') {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({ angle: 135, colors: [[this.pal().bg, 0.0], [this.pal().bg2, 1.0]] })
    } else {
      Column().width('100%').height('100%').backgroundColor(this.pal().bg)
    }
  }

  /** 顶部装饰标签胶囊（示例图 "pinyin" 位） */
  @Builder
  TagPill() {
    if (this.content.tag.trim() !== '') {
      Text(this.content.tag)
        .fontSize(this.f(26))
        .fontColor('#FFFFFF')
        .fontFamily(this.font())
        .letterSpacing(this.f(2))
        .maxLines(1)
        .padding({ left: this.f(22), right: this.f(22), top: this.f(9), bottom: this.f(9) })
        .backgroundColor(this.pal().grid)
        .borderRadius(this.f(999))
    }
  }

  /** 主文案块：空文案显示占位提示；超长自动缩字号 + 省略兜底 */
  @Builder
  BodyBlock(basePx: number, bold: boolean, big: boolean) {
    if (this.content.body.trim() === '') {
      Text($r('app.string.poster_empty_hint'))
        .fontSize(this.f(28))
        .fontColor(this.pal().sub)
        .fontFamily(this.font())
        .textAlign(TextAlign.Center)
    } else {
      Text(this.content.body)
        .fontSize(this.bodyFont(basePx, big))
        .lineHeight(this.bodyFont(basePx, big) * 1.4)
        .fontColor(this.pal().title)
        .fontFamily(this.font())
        .fontWeight(bold ? FontWeight.Bold : FontWeight.Normal)
        .maxLines(this.maxBodyLines(big))
        .textAlign(TextAlign.Center)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }

  // ---------- T1 暖调标签卡（示例图同款） ----------

  @Builder
  WarmLabel() {
    Stack() {
      Circle({ width: this.f(320), height: this.f(320) })
        .fill(this.pal().block)
        .opacity(0.5)
        .position({ x: this.previewWidth - this.f(150), y: this.h() - this.f(240) })
      Column({ space: this.f(30) }) {
        this.TagPill()
        this.BodyBlock(72, false, false)
        Row({ space: this.f(10) }) {
          Circle({ width: this.f(10), height: this.f(10) }).fill(this.pal().accent)
          Row().width(this.f(64)).height(this.f(3)).borderRadius(this.f(2)).backgroundColor(this.pal().accent)
          Circle({ width: this.f(10), height: this.f(10) }).fill(this.pal().accent)
        }
        .alignItems(VerticalAlign.Center)
        if (this.content.sign.trim() !== '') {
          Text(this.content.sign)
            .fontSize(this.f(28))
            .fontColor(this.pal().sub)
            .fontFamily(this.font())
            .maxLines(1)
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding({ left: this.f(70), right: this.f(70), top: this.f(50), bottom: this.f(50) })
    }
    .width('100%')
    .height('100%')
  }

  // ---------- T2 纯色简约 ----------

  @Builder
  PureMinimal() {
    Column({ space: this.f(26) }) {
      if (this.content.tag.trim() !== '') {
        Text(this.content.tag)
          .fontSize(this.f(24))
          .fontColor(this.pal().sub)
          .fontFamily(this.font())
          .letterSpacing(this.f(6))
          .maxLines(1)
      }
      Row().width(this.f(44)).height(this.f(5)).borderRadius(this.f(3)).backgroundColor(this.pal().accent)
      this.BodyBlock(60, false, false)
      if (this.content.sign.trim() !== '') {
        Text(this.content.sign)
          .fontSize(this.f(26))
          .fontColor(this.pal().sub)
          .fontFamily(this.font())
          .maxLines(1)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: this.f(64), right: this.f(64), top: this.f(50), bottom: this.f(50) })
  }

  // ---------- T3 文艺手写 ----------

  @Builder
  Handwrite() {
    Stack() {
      Row()
        .width(this.f(14))
        .height(this.f(14))
        .backgroundColor(this.pal().accent)
        .opacity(0.7)
        .rotate({ angle: 45 })
        .position({ x: this.f(40), y: this.f(40) })
      Row()
        .width(this.f(14))
        .height(this.f(14))
        .backgroundColor(this.pal().accent)
        .opacity(0.7)
        .rotate({ angle: 45 })
        .position({ x: this.previewWidth - this.f(54), y: this.h() - this.f(54) })
      Column({ space: this.f(28) }) {
        if (this.content.tag.trim() !== '') {
          Row({ space: this.f(8) }) {
            Circle({ width: this.f(8), height: this.f(8) }).fill(this.pal().accent)
            Text(this.content.tag)
              .fontSize(this.f(24))
              .fontColor(this.pal().sub)
              .fontFamily(this.font())
              .maxLines(1)
          }
          .alignItems(VerticalAlign.Center)
        }
        this.BodyBlock(56, false, false)
        if (this.content.sign.trim() !== '') {
          Row({ space: this.f(10) }) {
            Row().width(this.f(26)).height(this.f(2)).backgroundColor(this.pal().accent)
            Text(this.content.sign)
              .fontSize(this.f(30))
              .fontColor(this.pal().title)
              .fontFamily(this.font())
              .maxLines(1)
          }
          .alignItems(VerticalAlign.Center)
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding({ left: this.f(66), right: this.f(66), top: this.f(50), bottom: this.f(50) })
    }
    .width('100%')
    .height('100%')
  }

  // ---------- T4 大字冲击 ----------

  @Builder
  BigImpact() {
    Stack() {
      Circle({ width: this.f(420), height: this.f(420) })
        .fill(this.pal().block)
        .opacity(0.35)
        .position({ x: this.previewWidth - this.f(260), y: this.h() - this.f(300) })
      Column({ space: this.f(24) }) {
        if (this.content.tag.trim() !== '') {
          Text(this.content.tag)
            .fontSize(this.f(26))
            .fontColor(this.pal().sub)
            .fontFamily(this.font())
            .fontWeight(FontWeight.Bold)
            .letterSpacing(this.f(8))
            .maxLines(1)
        }
        this.BodyBlock(110, true, true)
        if (this.content.sign.trim() !== '') {
          Column({ space: this.f(10) }) {
            Row().width(this.f(110)).height(this.f(2)).backgroundColor(this.pal().accent)
            Text(this.content.sign)
              .fontSize(this.f(28))
              .fontColor(this.pal().title)
              .fontFamily(this.font())
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding({ left: this.f(56), right: this.f(56), top: this.f(40), bottom: this.f(40) })
    }
    .width('100%')
    .height('100%')
  }

  // ---------- T5 LCD 像素屏（功能机斜拍风，参照 docs/页面渲染失败问题排查.html） ----------

  /** 辉光辅助色：accent 前加透明度（如 '#CC' -> '#CC9EC9FF'） */
  private glowColor(alphaHex: string): string {
    return alphaHex + this.pal().accent.substring(1);
  }

  /** 信号格：4 根递增竖条 */
  @Builder
  LcdSignalBars() {
    Row({ space: this.f(4) }) {
      Row().width(this.f(5)).height(this.f(8)).borderRadius(this.f(1)).backgroundColor(this.pal().accent)
      Row().width(this.f(5)).height(this.f(13)).borderRadius(this.f(1)).backgroundColor(this.pal().accent)
      Row().width(this.f(5)).height(this.f(18)).borderRadius(this.f(1)).backgroundColor(this.pal().accent)
      Row().width(this.f(5)).height(this.f(24)).borderRadius(this.f(1)).backgroundColor(this.pal().accent)
    }
    .alignItems(VerticalAlign.Bottom)
  }

  /** 顶部状态栏：左（信号 + 笔图标 + 标签）右（字数 + 静音 + 电池），辉光文字 */
  @Builder
  LcdTopBar() {
    Row() {
      Row({ space: this.f(12) }) {
        this.LcdSignalBars()
        if (this.content.tag.trim() !== '') {
          Row({ space: this.f(9) }) {
            Row()
              .width(this.f(24))
              .height(this.f(12))
              .border({ width: { top: this.f(3.5), left: this.f(3.5) }, color: this.pal().sub })
              .rotate({ angle: -35 })
            Text(this.content.tag)
              .fontSize(this.f(34))
              .fontColor(this.pal().sub)
              .fontFamily(this.font())
              .maxLines(1)
              .textShadow([{ radius: this.f(3), color: this.glowColor('#CC'), offsetX: 0, offsetY: 0 }])
          }
          .alignItems(VerticalAlign.Center)
        }
      }
      .alignItems(VerticalAlign.Center)

      Row({ space: this.f(13) }) {
        Text(this.bodyLen().toString() + '/' + CopyPosterTemplates.MAX_BODY.toString())
          .fontSize(this.f(30))
          .fontColor(this.pal().sub)
          .fontFamily(this.font())
          .textShadow([{ radius: this.f(4), color: this.glowColor('#B3'), offsetX: 0, offsetY: 0 }])
        Row({ space: this.f(4) }) {
          Row()
            .width(this.f(11))
            .height(this.f(14))
            .border({ width: { left: this.f(3), top: this.f(3), bottom: this.f(3) }, color: this.pal().sub })
          Row().width(this.f(13)).height(this.f(3)).backgroundColor(this.pal().sub).rotate({ angle: 45 })
        }
        .alignItems(VerticalAlign.Center)
        Row() {
          Stack({ alignContent: Alignment.Start }) {
            Row()
              .width(this.f(15))
              .height(this.f(7))
              .backgroundColor(this.pal().sub)
              .margin({ left: this.f(3) })
          }
          .width(this.f(24))
          .height(this.f(13))
          .border({ width: this.f(3), color: this.pal().sub })
          Row().width(this.f(4)).height(this.f(6)).borderRadius(this.f(1)).backgroundColor(this.pal().sub)
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
  LcdBox() {
    Column() {
      if (this.content.body.trim() === '') {
        Text($r('app.string.poster_empty_hint'))
          .fontSize(this.f(26))
          .fontColor('#8A8A8A')
          .fontFamily(this.font())
          .width('100%')
          .textAlign(TextAlign.Start)
      } else {
        Text(this.content.body)
          .fontSize(this.bodyFont(43, false))
          .lineHeight(this.bodyFont(43, false) * 1.36)
          .fontColor(this.pal().title)
          .fontFamily(this.font())
          .letterSpacing(this.f(1.5))
          .maxLines(this.maxBodyLines(false))
          .textAlign(TextAlign.Start)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .constraintSize({ minHeight: this.f(160) })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .padding({ left: this.f(20), right: this.f(21), top: this.f(20), bottom: this.f(24) })
    .backgroundColor(this.pal().block)
    .borderRadius(this.f(2))
    .border({ width: this.f(3), color: '#EFEFEF' })
    .backgroundImage($r('app.media.poster_lcd_dots'), ImageRepeat.XY)
    .backgroundImageSize({ width: this.f(7), height: this.f(7) })
  }

  /** 底部软键行：左软键 + 中间署名（运营商位）+ 右软键 */
  @Builder
  LcdSoftBar() {
    Row() {
      Text($r('app.string.poster_soft_left'))
        .fontSize(this.f(33))
        .fontColor(this.pal().sub)
        .fontFamily(this.font())
        .textShadow([{ radius: this.f(3), color: this.glowColor('#99'), offsetX: 0, offsetY: 0 }])
      if (this.content.sign.trim() !== '') {
        Text(this.content.sign)
          .fontSize(this.f(28))
          .fontColor(this.pal().sub)
          .fontFamily(this.font())
          .maxLines(1)
          .textShadow([{ radius: this.f(3), color: this.glowColor('#99'), offsetX: 0, offsetY: 0 }])
      }
      Text($r('app.string.poster_soft_right'))
        .fontSize(this.f(33))
        .fontColor(this.pal().sub)
        .fontFamily(this.font())
        .textShadow([{ radius: this.f(3), color: this.glowColor('#99'), offsetX: 0, offsetY: 0 }])
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .padding({ left: this.f(6), right: this.f(6) })
  }

  /** LCD 面板整体：状态栏 + 文本框 + 软键 + 暗角，3D 斜拍透视（斜着拍的感觉也要在） */
  @Builder
  LcdPixel() {
    Column() {
      Column() {
        Stack() {
          Column({ space: this.f(15) }) {
            this.LcdTopBar()
            this.LcdBox()
            this.LcdSoftBar()
          }
          .width('100%')
          .padding({ left: this.f(34), right: this.f(34), top: this.f(28), bottom: this.f(26) })

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
        .backgroundColor(this.pal().grid)
        .borderRadius(this.f(2))
        .clip(true)
        .shadow({ radius: this.f(34), color: this.glowColor('#2E'), offsetX: 0, offsetY: this.f(8) })
      }
      .width(this.f(800))
      .rotate({
        x: 0.45,
        y: -0.28,
        z: 1,
        angle: -12,
        centerX: '50%',
        centerY: '50%',
        perspective: this.f(1000) * this.density,
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // ---------- T6 CRT 终端屏（米色复古显示器 + 荧光屏） ----------

  /** 任意色加透明度前缀（如 hexA('#FF4FD8', '#80') -> '#80FF4FD8'；alpha 也接受不带 # 的 '80'） */
  private hexA(color: string, alphaHex: string): string {
    let a: string = alphaHex.startsWith('#') ? alphaHex.substring(1) : alphaHex;
    return '#' + a + color.substring(1);
  }

  @Builder
  CrtTerminal() {
    Stack() {
      Column() {
        Stack() {
          Column() {
            Text('C:\\> type ' + (this.content.tag.trim() !== '' ? this.content.tag.trim() : 'quote') + '.txt')
              .fontSize(this.f(28))
              .fontColor(this.pal().sub)
              .fontFamily(this.font())
              .maxLines(1)
              .width('100%')
              .textAlign(TextAlign.Start)
            Row()
              .width('100%')
              .height(this.f(2))
              .backgroundColor(this.pal().accent)
              .opacity(0.5)
              .margin({ top: this.f(12), bottom: this.f(18) })
            if (this.content.body.trim() === '') {
              Text($r('app.string.poster_empty_hint'))
                .fontSize(this.f(28))
                .fontColor(this.pal().sub)
                .fontFamily(this.font())
                .width('100%')
                .textAlign(TextAlign.Start)
            } else {
              Text(this.content.body)
                .fontSize(this.bodyFont(50, false))
                .lineHeight(this.bodyFont(50, false) * 1.5)
                .fontColor(this.pal().title)
                .fontFamily(this.font())
                .maxLines(this.maxBodyLines(false))
                .textAlign(TextAlign.Start)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .textShadow([{ radius: this.f(3), color: this.hexA(this.pal().accent, '#B3'), offsetX: 0, offsetY: 0 }])
                .width('100%')
            }
            Text('> -- ' + (this.content.sign.trim() !== '' ? this.content.sign : '_') + ' ▌')
              .fontSize(this.f(32))
              .fontColor(this.pal().sub)
              .fontFamily(this.font())
              .maxLines(1)
              .margin({ top: this.f(20) })
              .width('100%')
              .textAlign(TextAlign.Start)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: this.f(30), right: this.f(30), top: this.f(28), bottom: this.f(28) })

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
            .backgroundImageSize({ width: this.f(4), height: this.f(4) })
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .backgroundColor(this.pal().grid)
        .borderRadius(this.f(14))
        .clip(true)
        .shadow({ radius: this.f(26), color: this.hexA(this.pal().accent, '#30'), offsetX: 0, offsetY: 0 })

        Row() {
          Circle({ width: this.f(12), height: this.f(12) })
            .fill('#FF4433')
            .shadow({ radius: this.f(6), color: '#80FF4433' })
          Text('PHOSPHOR · 80C')
            .fontSize(this.f(16))
            .letterSpacing(this.f(5))
            .fontColor('#8D8471')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Row({ space: this.f(10) }) {
            Stack({ alignContent: Alignment.Top }) {
              Row().width(this.f(2)).height(this.f(8)).backgroundColor('#8D8471')
            }
            .width(this.f(22))
            .height(this.f(22))
            .borderRadius(this.f(11))
            .backgroundColor('#EFEADE')
            .shadow({ radius: this.f(3), color: '#4D000000', offsetY: this.f(1) })
            .rotate({ angle: -30 })
            Stack({ alignContent: Alignment.Top }) {
              Row().width(this.f(2)).height(this.f(8)).backgroundColor('#8D8471')
            }
            .width(this.f(22))
            .height(this.f(22))
            .borderRadius(this.f(11))
            .backgroundColor('#EFEADE')
            .shadow({ radius: this.f(3), color: '#4D000000', offsetY: this.f(1) })
            .rotate({ angle: 20 })
          }
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .height(this.f(72))
        .padding({ left: this.f(8), right: this.f(18) })
        .alignItems(VerticalAlign.Center)
      }
      .width(this.f(720))
      .padding({ left: this.f(22), right: this.f(22), top: this.f(22), bottom: this.f(0) })
      .backgroundColor(this.pal().block)
      .borderRadius({ topLeft: this.f(26), topRight: this.f(26), bottomLeft: this.f(30), bottomRight: this.f(30) })
      .shadow({ radius: this.f(46), color: '#8C000000', offsetY: this.f(16) })
      .rotate({
        x: 0.25,
        y: -0.14,
        z: 1,
        angle: -5,
        centerX: '50%',
        centerY: '50%',
        perspective: this.f(1100) * this.density,
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

  // ---------- T7 霓虹灯招牌（夜墙灯管） ----------

  private neonSignH(): number {
    return this.f(this.ratioKind === CopyPosterRatio.PORTRAIT ? 620 : 470);
  }

  @Builder
  NeonSign() {
    Stack() {
      Column()
        .width('86%')
        .height(this.f(180))
        .radialGradient({
          center: ['50%', '100%'],
          radius: '75%',
          colors: [[this.hexA(this.pal().accent, '#2E'), 0], ['#00000000', 0.72]],
        })
        .position({ x: '7%', y: this.h() - this.f(180) })
        .hitTestBehavior(HitTestMode.None)

      Stack() {
        Column({ space: this.f(22) }) {
          if (this.content.tag.trim() !== '') {
            Text('✦ ' + this.content.tag + ' ✦')
              .fontSize(this.f(24))
              .fontColor(this.pal().sub)
              .fontFamily(this.font())
              .letterSpacing(this.f(8))
              .maxLines(1)
              .textShadow([
                { radius: this.f(2), color: this.hexA(this.pal().accent, '#E6'), offsetX: 0, offsetY: 0 },
                { radius: this.f(9), color: this.hexA(this.pal().accent, '#99'), offsetX: 0, offsetY: 0 },
              ])
          }
          if (this.content.body.trim() === '') {
            Text($r('app.string.poster_empty_hint'))
              .fontSize(this.f(32))
              .fontColor(this.pal().sub)
              .fontFamily(this.font())
              .textAlign(TextAlign.Center)
          } else {
            Text(this.content.body)
              .fontSize(this.bodyFont(96, false))
              .lineHeight(this.bodyFont(96, false) * 1.35)
              .fontColor(this.pal().title)
              .fontFamily(this.font())
              .fontWeight(FontWeight.Bold)
              .maxLines(3)
              .textAlign(TextAlign.Center)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textShadow([
                { radius: this.f(4), color: '#FFFFFFFF', offsetX: 0, offsetY: 0 },
                { radius: this.f(10), color: this.hexA(this.pal().accent, '#E6'), offsetX: 0, offsetY: 0 },
                { radius: this.f(26), color: this.hexA(this.pal().accent, '#8C'), offsetX: 0, offsetY: 0 },
              ])
          }
          if (this.content.sign.trim() !== '') {
            Text('—— ' + this.content.sign + ' ——')
              .fontSize(this.f(30))
              .fontColor(this.pal().sub)
              .fontFamily(this.font())
              .letterSpacing(this.f(6))
              .maxLines(1)
              .textShadow([
                { radius: this.f(2), color: '#66FFFFFF', offsetX: 0, offsetY: 0 },
                { radius: this.f(10), color: this.hexA(this.pal().block, '#B3'), offsetX: 0, offsetY: 0 },
              ])
          }
        }
        .width('100%')
        .height(this.neonSignH())
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ left: this.f(30), right: this.f(30) })
        .border({ width: this.f(6), color: this.pal().block })
        .borderRadius(this.f(34))
        .shadow({ radius: this.f(40), color: this.hexA(this.pal().block, '#66') })

        Circle({ width: this.f(10), height: this.f(10) }).fill('#D8DEE9').position({ x: this.f(12), y: this.f(12) })
        Circle({ width: this.f(10), height: this.f(10) }).fill('#D8DEE9')
          .position({ x: this.f(800) - this.f(22), y: this.f(12) })
        Circle({ width: this.f(10), height: this.f(10) }).fill('#D8DEE9')
          .position({ x: this.f(12), y: this.neonSignH() - this.f(22) })
        Circle({ width: this.f(10), height: this.f(10) }).fill('#D8DEE9')
          .position({ x: this.f(800) - this.f(22), y: this.neonSignH() - this.f(22) })
      }
      .width(this.f(800))

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

  // ---------- T8 掌机游戏机（橄榄绿点阵屏） ----------

  @Builder
  HandheldConsole() {
    Stack() {
      Column({ space: this.f(16) }) {
        Row() {
          Row({ space: this.f(5) }) {
            Circle({ width: this.f(8), height: this.f(8) })
              .fill('#E33B22')
              .shadow({ radius: this.f(4), color: '#80FF4433' })
            Text('BATTERY')
              .fontSize(this.f(10))
              .fontColor('#8B909A')
              .letterSpacing(this.f(1))
          }
          .alignItems(VerticalAlign.Center)
          Text(this.content.tag.trim() !== '' ? this.content.tag : 'POCKET-8')
            .fontSize(this.f(14))
            .fontColor('#AEB3BD')
            .letterSpacing(this.f(3))
            .fontWeight(FontWeight.Bold)
            .maxLines(1)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)

        Column() {
          Stack() {
            Column({ space: this.f(12) }) {
              Row() {
                Text('♥♥♥✦')
                  .fontSize(this.f(20))
                  .fontColor(this.pal().accent)
                  .fontWeight(FontWeight.Bold)
                Text('SCORE ' + this.bodyLen().toString())
                  .fontSize(this.f(17))
                  .fontColor(this.pal().accent)
                  .fontWeight(FontWeight.Bold)
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)

              Column() {
                if (this.content.body.trim() === '') {
                  Text($r('app.string.poster_empty_hint'))
                    .fontSize(this.f(24))
                    .fontColor(this.pal().accent)
                    .fontFamily(this.font())
                    .width('100%')
                    .textAlign(TextAlign.Start)
                } else {
                  Text(this.content.body)
                    .fontSize(this.bodyFont(38, false))
                    .lineHeight(this.bodyFont(38, false) * 1.55)
                    .fontColor(this.pal().title)
                    .fontFamily(this.font())
                    .maxLines(5)
                    .textAlign(TextAlign.Start)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                }
              }
              .width('100%')
              .border({ width: this.f(3), color: this.pal().accent })
              .padding(this.f(13))

              if (this.content.sign.trim() !== '') {
                Text('▶ ' + this.content.sign + ' ▼')
                  .fontSize(this.f(20))
                  .fontColor(this.pal().accent)
                  .fontWeight(FontWeight.Bold)
                  .letterSpacing(this.f(2))
                  .maxLines(1)
              }
            }
            .width('100%')
            .padding(this.f(14))

            Column()
              .width('100%')
              .height('100%')
              .backgroundImage($r('app.media.poster_lcd_dots'), ImageRepeat.XY)
              .backgroundImageSize({ width: this.f(6), height: this.f(6) })
              .hitTestBehavior(HitTestMode.None)
          }
          .width('100%')
          .backgroundColor(this.pal().grid)
          .border({ width: this.f(3), color: this.pal().accent })
          .clip(true)

          Text('DOT MATRIX TEXT SYSTEM')
            .fontSize(this.f(9))
            .letterSpacing(this.f(3))
            .fontColor('#7D828D')
            .margin({ top: this.f(9) })
        }
        .width('100%')
        .backgroundColor('#171920')
        .borderRadius({ topLeft: this.f(10), topRight: this.f(10), bottomLeft: this.f(18), bottomRight: this.f(18) })
        .padding(this.f(14))

        Row() {
          Stack() {
            Row().width(this.f(78)).height(this.f(25)).borderRadius(this.f(6)).backgroundColor('#212329')
            Row().width(this.f(25)).height(this.f(78)).borderRadius(this.f(6)).backgroundColor('#212329')
            Circle({ width: this.f(19), height: this.f(19) }).fill('#15171B')
          }
          .width(this.f(78))
          .height(this.f(78))

          Row({ space: this.f(13) }) {
            Column({ space: this.f(5) }) {
              Circle({ width: this.f(37), height: this.f(37) }).fill('#B04A70')
              Text('B')
                .fontSize(this.f(12))
                .fontColor('#C9CDD6')
                .fontWeight(FontWeight.Bold)
            }
            .alignItems(HorizontalAlign.Center)
            Column({ space: this.f(5) }) {
              Circle({ width: this.f(37), height: this.f(37) }).fill('#B04A70')
              Text('A')
                .fontSize(this.f(12))
                .fontColor('#C9CDD6')
                .fontWeight(FontWeight.Bold)
            }
            .alignItems(HorizontalAlign.Center)
          }
          .rotate({ angle: -16 })
          .margin({ right: this.f(4) })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)
        .padding({ left: this.f(4), right: this.f(10) })

        Row({ space: this.f(26) }) {
          Column({ space: this.f(4) }) {
            Row().width(this.f(34)).height(this.f(10)).borderRadius(this.f(6)).backgroundColor('#212329')
            Text('SELECT')
              .fontSize(this.f(9))
              .fontColor('#AEB3BD')
              .letterSpacing(this.f(2))
          }
          .alignItems(HorizontalAlign.Center)
          Column({ space: this.f(4) }) {
            Row().width(this.f(34)).height(this.f(10)).borderRadius(this.f(6)).backgroundColor('#212329')
            Text('START')
              .fontSize(this.f(9))
              .fontColor('#AEB3BD')
              .letterSpacing(this.f(2))
          }
          .alignItems(HorizontalAlign.Center)
        }
        .rotate({ angle: -16 })

        Row() {
          Row({ space: this.f(5) }) {
            Row().width(this.f(30)).height(this.f(4)).borderRadius(this.f(2)).backgroundColor('#1C1E23')
            Row().width(this.f(30)).height(this.f(4)).borderRadius(this.f(2)).backgroundColor('#1C1E23')
            Row().width(this.f(30)).height(this.f(4)).borderRadius(this.f(2)).backgroundColor('#1C1E23')
            Row().width(this.f(30)).height(this.f(4)).borderRadius(this.f(2)).backgroundColor('#1C1E23')
            Row().width(this.f(30)).height(this.f(4)).borderRadius(this.f(2)).backgroundColor('#1C1E23')
          }
          .rotate({ angle: -28 })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: this.f(18), bottom: this.f(6) })
      }
      .width(this.f(440))
      .padding({ left: this.f(24), right: this.f(24), top: this.f(18), bottom: this.f(22) })
      .backgroundColor(this.pal().block)
      .borderRadius({ topLeft: this.f(16), topRight: this.f(16), bottomLeft: this.f(38), bottomRight: this.f(38) })
      .shadow({ radius: this.f(36), color: '#73000000', offsetY: this.f(14) })
      .rotate({
        x: 0.35,
        y: -0.2,
        z: 1,
        angle: -5,
        centerX: '50%',
        centerY: '50%',
        perspective: this.f(1000) * this.density,
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

  // ---------- T9 复古车票（票纸 + 撕票线 + 邮戳） ----------

  private ticketH(): number {
    return this.f(this.ratioKind === CopyPosterRatio.PORTRAIT ? 560 : 440);
  }

  private pad3(n: number): string {
    if (n < 10) {
      return '00' + n.toString();
    }
    if (n < 100) {
      return '0' + n.toString();
    }
    return n.toString();
  }

  @Builder
  VintageTicket() {
    Stack() {
      Stack() {
        Row() {
          Column() {
            Row() {
              Text('QUOTATION TICKET')
                .fontSize(this.f(17))
                .letterSpacing(this.f(5))
                .fontColor(this.pal().sub)
                .fontWeight(FontWeight.Bold)
              Text('No. ' + this.pad3(this.bodyLen()))
                .fontSize(this.f(17))
                .fontColor(this.pal().sub)
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)

            Column()
              .width('100%')
              .height(this.f(4))
              .margin({ top: this.f(10), bottom: this.f(16) })
              .border({ width: { top: this.f(1), bottom: this.f(1) }, color: this.pal().grid })

            if (this.content.body.trim() === '') {
              Text($r('app.string.poster_empty_hint'))
                .fontSize(this.f(28))
                .fontColor(this.pal().sub)
                .fontFamily(this.font())
            } else {
              Text('“' + this.content.body + '”')
                .fontSize(this.bodyFont(50, false))
                .lineHeight(this.bodyFont(50, false) * 1.5)
                .fontColor(this.pal().title)
                .fontFamily(this.font())
                .maxLines(this.maxBodyLines(false))
                .textAlign(TextAlign.Start)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }

            Blank()

            if (this.content.sign.trim() !== '') {
              Text(this.content.sign)
                .fontSize(this.f(24))
                .fontColor(this.pal().sub)
                .fontFamily(this.font())
                .maxLines(1)
            }
          }
          .layoutWeight(1)
          .height('100%')
          .padding({ left: this.f(26), right: this.f(22), top: this.f(24), bottom: this.f(20) })
          .alignItems(HorizontalAlign.Start)

          Column({ space: this.f(12) }) {
            Text('KEEP')
              .fontSize(this.f(15))
              .letterSpacing(this.f(4))
              .fontColor(this.pal().sub)
              .fontWeight(FontWeight.Bold)
            Row({ space: this.f(3) }) {
              ForEach([2, 1, 3, 1, 2, 2, 1, 3, 1, 2, 3, 1, 2, 1, 3, 2, 1, 2], (w: number) => {
                Row().width(this.f(w)).height(this.f(42)).backgroundColor(this.pal().title)
              }, (w: number) => w.toString())
            }
            Text('0-' + this.pad3(this.bodyLen()) + '-26')
              .fontSize(this.f(13))
              .fontColor(this.pal().sub)
            if (this.content.tag.trim() !== '') {
              Text(this.content.tag)
                .fontSize(this.f(15))
                .fontColor(this.pal().sub)
                .letterSpacing(this.f(2))
                .maxLines(2)
                .textAlign(TextAlign.Center)
            }
          }
          .width(this.f(190))
          .height('100%')
          .border({
            width: { left: this.f(2) },
            color: this.pal().grid,
            style: { left: BorderStyle.Dashed },
          })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
        .width(this.f(800))
        .height(this.ticketH())
        .backgroundColor(this.pal().block)
        .borderRadius(this.f(10))
        .shadow({ radius: this.f(38), color: '#8F000000', offsetY: this.f(18) })
        .rotate({ angle: -3 })

        Stack() {
          Column({ space: this.f(4) }) {
            Text(this.content.tag.trim() !== '' ? this.content.tag : '')
              .fontSize(this.f(22))
              .fontColor(this.pal().accent)
              .fontWeight(FontWeight.Bold)
              .maxLines(1)
            Text('★ ★ ★')
              .fontSize(this.f(13))
              .fontColor(this.pal().accent)
            Text('APPROVED')
              .fontSize(this.f(11))
              .letterSpacing(this.f(3))
              .fontColor(this.pal().accent)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
        .width(this.f(160))
        .height(this.f(160))
        .borderRadius(this.f(80))
        .border({ width: this.f(5), color: this.hexA(this.pal().accent, '#D0') })
        .rotate({ angle: -14 })
        .opacity(0.92)
        .position({ x: this.f(520), y: -this.f(24) })

        Circle({ width: this.f(22), height: this.f(22) }).fill(this.pal().bg)
          .position({ x: this.f(599), y: -this.f(11) })
        Circle({ width: this.f(22), height: this.f(22) }).fill(this.pal().bg)
          .position({ x: this.f(599), y: this.ticketH() - this.f(11) })
        Circle({ width: this.f(16), height: this.f(16) }).fill(this.pal().bg)
          .position({ x: this.f(22), y: this.ticketH() - this.f(38) })
      }

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
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }

  // ---------- T10 翻牌显示屏（车站翻牌板） ----------

  /** 正文去空白后按每行 12 字拆行（最多 6 行） */
  private flapRows(): string[][] {
    let src: string[] = [];
    if (this.content.body.trim() === '') {
      src = ['·', '·', '·'];
    } else {
      src = this.content.body.replace(new RegExp('\\s', 'g'), '').split('');
    }
    let rows: string[][] = [];
    for (let i = 0; i < src.length && rows.length < 6; i += 12) {
      let end: number = Math.min(i + 12, src.length);
      let r: string[] = [];
      for (let j = i; j < end; j++) {
        r.push(src[j]);
      }
      rows.push(r);
    }
    if (rows.length === 0) {
      rows.push([' ']);
    }
    return rows;
  }

  @Builder
  FlapModule(ch: string) {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.pal().grid)
        .linearGradient({
          angle: 180,
          colors: [['#38FFFFFF', 0], ['#00000000', 0.45], ['#00000000', 0.55], ['#4D000000', 1]],
        })
      Row().width('90%').height(this.f(2.5)).backgroundColor('#A6000000')
      Text(ch === ' ' ? '' : ch)
        .fontSize(this.f(34))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().title)
        .fontFamily(this.font())
        .maxLines(1)
    }
    .width(this.f(50))
    .height(this.f(72))
    .borderRadius(this.f(5))
    .clip(true)
    .shadow({ radius: this.f(4), color: '#55000000', offsetY: this.f(2) })
  }

  @Builder
  SplitFlap() {
    Stack() {
      Column({ space: this.f(18) }) {
        Row() {
          Text('QUOTE BOARD · ' + this.content.tag)
            .fontSize(this.f(20))
            .letterSpacing(this.f(4))
            .fontColor(this.pal().accent)
            .fontWeight(FontWeight.Bold)
            .maxLines(1)
          Row({ space: this.f(6) }) {
            Circle({ width: this.f(9), height: this.f(9) })
              .fill('#39D353')
              .shadow({ radius: this.f(5), color: '#8039D353' })
            Circle({ width: this.f(9), height: this.f(9) })
              .fill('#FF5544')
              .shadow({ radius: this.f(5), color: '#80FF5544' })
          }
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)

        Column({ space: this.f(9) }) {
          ForEach(this.flapRows(), (row: string[], ri: number) => {
            Row({ space: this.f(8) }) {
              ForEach(row, (ch: string, ci: number) => {
                this.FlapModule(ch)
              }, (ch: string, ci: number) => ci.toString() + ch)
            }
          }, (row: string[], ri: number) => ri.toString() + '-' + row.length.toString())
        }

        Row({ space: this.f(12) }) {
          Circle({ width: this.f(8), height: this.f(8) })
            .fill('#39D353')
            .shadow({ radius: this.f(4), color: '#8039D353' })
          Text('——')
            .fontSize(this.f(16))
            .fontColor(this.pal().sub)
          if (this.content.sign.trim() !== '') {
            Text(this.content.sign)
              .fontSize(this.f(19))
              .letterSpacing(this.f(4))
              .fontColor(this.pal().accent)
              .maxLines(1)
          }
          Text('——')
            .fontSize(this.f(16))
            .fontColor(this.pal().sub)
          Circle({ width: this.f(8), height: this.f(8) })
            .fill('#39D353')
            .shadow({ radius: this.f(4), color: '#8039D353' })
        }
        .alignItems(VerticalAlign.Center)
      }
      .width(this.f(790))
      .padding({ left: this.f(24), right: this.f(24), top: this.f(22), bottom: this.f(24) })
      .backgroundColor(this.pal().block)
      .borderRadius(this.f(14))
      .border({ width: this.f(2), color: this.pal().grid })
      .shadow({ radius: this.f(44), color: '#8C000000', offsetY: this.f(18) })
      .rotate({ angle: -1.5 })
      .alignItems(HorizontalAlign.Center)

      Column()
        .width('100%')
        .height('100%')
        .radialGradient({
          center: ['50%', '50%'],
          radius: '85%',
          colors: [['#00000000', 0], ['#00000000', 0.5], ['#96000000', 1]],
        })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }

  // ---------- T11 复古报纸（老报纸头版，参照 docs/文案海报候选_复古报纸.html） ----------

  /** 设计稿 y（1:1 基准 900 高）按实际画布高换算，3:4 时按比例下沉 */
  private fy(py: number): number {
    return this.h() * py / 900;
  }

  @Builder
  NewsLines(widths: string[]) {
    Column({ space: this.f(13) }) {
      ForEach(widths, (w: string) => {
        Row().width(w).height(this.f(10)).borderRadius(this.f(3)).backgroundColor(this.pal().grid)
      }, (w: string) => w)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  VintageNews() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .radialGradient({
          center: ['50%', '28%'],
          radius: '85%',
          colors: [[this.hexA(this.pal().block, 'D9'), 0], [this.hexA(this.pal().block, '59'), 0.5], ['#00000000', 1]],
        })
        .hitTestBehavior(HitTestMode.None)

      Column() {
        Row() {
          Text('No. 128')
            .fontSize(this.f(16))
            .fontColor(this.pal().sub)
            .letterSpacing(this.f(2.4))
          Text('SUNDAY · OCT 11, 2026')
            .fontSize(this.f(16))
            .fontColor(this.pal().sub)
            .letterSpacing(this.f(2.4))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Text('PRICE 0.5')
            .fontSize(this.f(16))
            .fontColor(this.pal().sub)
            .letterSpacing(this.f(2.4))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row().width('100%').height(this.f(2.4)).backgroundColor(this.pal().title).margin({ top: this.f(11) })
        Row().width('100%').height(this.f(1.6)).backgroundColor(this.pal().title).margin({ top: this.f(5) })

        Column() {
          if (this.content.tag.trim() !== '') {
            Text('POCKET DAILY')
              .fontSize(this.f(18))
              .fontColor(this.pal().sub)
              .letterSpacing(this.f(11))
              .margin({ bottom: this.f(10) })
          }
          Text(this.content.tag.trim() !== '' ? this.content.tag.trim() : 'POCKET DAILY')
            .fontSize(this.f(68))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal().title)
            .fontFamily(this.font())
            .letterSpacing(this.f(19))
            .maxLines(1)
            .width('100%')
            .textAlign(TextAlign.Center)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .margin({ top: this.f(16) })

        Row().width('100%').height(this.f(4.8)).backgroundColor(this.pal().title).margin({ top: this.f(16) })
        Row().width('100%').height(this.f(1.6)).backgroundColor(this.pal().title).margin({ top: this.f(8) })

        Column() {
          this.BodyBlock(54, true, false)
        }
        .width('100%')
        .margin({ top: this.f(32) })

        if (this.content.sign.trim() !== '') {
          Text('—— ' + this.content.sign)
            .fontSize(this.f(24))
            .fontColor(this.pal().sub)
            .fontFamily(this.font())
            .fontStyle(FontStyle.Italic)
            .maxLines(1)
            .margin({ top: this.f(19) })
        }

        Row({ space: this.f(32) }) {
          Column() {
            this.NewsLines(['100%', '82%', '95%', '70%', '90%', '60%'])
          }
          .layoutWeight(1)
          Column() {
            this.NewsLines(['88%', '100%', '75%', '96%', '52%'])
          }
          .layoutWeight(1)
          Column() {
            this.NewsLines(['92%', '65%', '100%', '84%', '45%'])
          }
          .layoutWeight(1)
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(VerticalAlign.Top)
        .margin({ top: this.f(35) })

        Row() {
          Text('POCKET PRESS')
            .fontSize(this.f(15))
            .fontColor(this.pal().sub)
            .letterSpacing(this.f(3.2))
          Text('EDITOR · JIEYU ZHUJI')
            .fontSize(this.f(15))
            .fontColor(this.pal().sub)
            .letterSpacing(this.f(3.2))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Text('PAGE 04')
            .fontSize(this.f(15))
            .fontColor(this.pal().sub)
            .letterSpacing(this.f(3.2))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .border({ width: { top: this.f(1.6) }, color: this.hexA(this.pal().sub, '80') })
        .padding({ top: this.f(13) })
        .margin({ top: this.f(22) })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ left: this.f(68), right: this.f(68), top: this.f(48), bottom: this.f(42) })

      Text('EXTRA')
        .fontSize(this.f(31))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().accent)
        .letterSpacing(this.f(10))
        .padding({ left: this.f(26), right: this.f(19), top: this.f(8), bottom: this.f(8) })
        .border({ width: this.f(4), color: this.pal().accent })
        .borderRadius(this.f(6))
        .rotate({ angle: 8 })
        .opacity(0.85)
        .position({ x: this.previewWidth - this.f(242), y: this.f(148) })

      Column()
        .width(this.f(241))
        .height(this.f(241))
        .borderRadius(this.f(120))
        .radialGradient({
          center: ['50%', '50%'],
          radius: '50%',
          colors: [[this.hexA(this.pal().sub, '29'), 0], ['#00000000', 0.7]],
        })
        .position({ x: -this.f(72), y: this.h() - this.f(185) })
        .hitTestBehavior(HitTestMode.None)

      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 90,
          colors: [[this.hexA('#000000', '0D'), 0], ['#00000000', 0.06], ['#00000000', 0.94], [this.hexA('#000000', '12'), 1]],
        })
        .hitTestBehavior(HitTestMode.None)

      Column()
        .width('100%')
        .height('100%')
        .radialGradient({
          center: ['50%', '45%'],
          radius: '90%',
          colors: [['#00000000', 0], ['#00000000', 0.52], [this.hexA(this.pal().sub, '3D'), 1]],
        })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
  }

  // ---------- T12 聊天气泡（微信式对话，参照 docs/文案海报候选_聊天气泡.html） ----------

  /** 对方头像首字 */
  private avatarChar(): string {
    let t: string = this.content.tag.trim();
    if (t !== '') {
      return t.charAt(0);
    }
    return 'P';
  }

  @Builder
  ChatAvatar(sizePx: number, bg: string, ch: string, color: string) {
    Stack() {
      Text(ch)
        .fontSize(this.f(sizePx * 0.5))
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
        .fontFamily(this.font())
        .maxLines(1)
    }
    .width(this.f(sizePx))
    .height(this.f(sizePx))
    .borderRadius(this.f(sizePx * 0.21))
    .backgroundColor(bg)
  }

  @Builder
  ChatBubbles() {
    Column() {
      Row({ space: this.f(18) }) {
        this.ChatAvatar(61, this.pal().accent, this.avatarChar(), this.pal().title)
        Column() {
          Text(this.content.tag.trim() !== '' ? this.content.tag.trim() : 'POCKET')
            .fontSize(this.f(26))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal().title)
            .fontFamily(this.font())
            .maxLines(1)
          Text($r('app.string.poster_chat_sub'))
            .fontSize(this.f(16))
            .fontColor(this.pal().sub)
            .margin({ top: this.f(3) })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Blank()
        Text('···')
          .fontSize(this.f(29))
          .fontColor(this.hexA(this.pal().title, '66'))
          .letterSpacing(this.f(3))
      }
      .width('100%')
      .height(this.f(106))
      .padding({ left: this.f(26), right: this.f(26) })
      .backgroundColor(this.pal().grid)
      .border({ width: { bottom: this.f(1.6) }, color: this.hexA(this.pal().sub, '33') })
      .alignItems(VerticalAlign.Center)

      Column() {
        Text('18:05')
          .fontSize(this.f(16))
          .fontColor(this.pal().sub)
          .padding({ left: this.f(16), right: this.f(16), top: this.f(5), bottom: this.f(5) })
          .backgroundColor(this.hexA(this.pal().sub, '24'))
          .borderRadius(this.f(999))
          .alignSelf(ItemAlign.Center)

        Row({ space: this.f(14) }) {
          this.ChatAvatar(55, this.pal().accent, this.avatarChar(), this.pal().title)
          if (this.content.body.trim() === '') {
            Text($r('app.string.poster_empty_hint'))
              .fontSize(this.f(25))
              .fontColor(this.pal().sub)
              .fontFamily(this.font())
              .lineHeight(this.f(25) * 1.55)
              .padding({ left: this.f(22), right: this.f(22), top: this.f(18), bottom: this.f(18) })
              .backgroundColor(this.pal().block)
              .borderRadius({ topLeft: this.f(7), topRight: this.f(19), bottomLeft: this.f(19), bottomRight: this.f(19) })
              .constraintSize({ maxWidth: this.previewWidth * 0.64 })
              .shadow({ radius: this.f(8), color: '#12000000', offsetY: this.f(3) })
          } else {
            Text(this.content.body)
              .fontSize(this.f(25))
              .lineHeight(this.f(25) * 1.55)
              .fontColor(this.pal().title)
              .fontFamily(this.font())
              .maxLines(this.maxBodyLines(false))
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: this.f(22), right: this.f(22), top: this.f(18), bottom: this.f(18) })
              .backgroundColor(this.pal().block)
              .borderRadius({ topLeft: this.f(7), topRight: this.f(19), bottomLeft: this.f(19), bottomRight: this.f(19) })
              .constraintSize({ maxWidth: this.previewWidth * 0.64 })
              .shadow({ radius: this.f(8), color: '#12000000', offsetY: this.f(3) })
          }
          Row().layoutWeight(1)
        }
        .width('100%')
        .margin({ top: this.f(26) })
        .alignItems(VerticalAlign.Top)

        if (this.content.sign.trim() !== '') {
          Row({ space: this.f(14) }) {
            Row().layoutWeight(1)
            Text(this.content.sign)
              .fontSize(this.f(25))
              .lineHeight(this.f(25) * 1.55)
              .fontColor(this.pal().title)
              .fontFamily(this.font())
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: this.f(22), right: this.f(22), top: this.f(18), bottom: this.f(18) })
              .backgroundColor(this.pal().accent)
              .borderRadius({ topLeft: this.f(19), topRight: this.f(7), bottomLeft: this.f(19), bottomRight: this.f(19) })
              .constraintSize({ maxWidth: this.previewWidth * 0.64 })
              .shadow({ radius: this.f(8), color: '#12000000', offsetY: this.f(3) })
            this.ChatAvatar(55, this.pal().block, this.content.sign.trim().charAt(0), this.pal().accent)
          }
          .width('100%')
          .margin({ top: this.f(26) })
          .alignItems(VerticalAlign.Top)
        }

        Row().layoutWeight(1)
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(this.pal().bg)
      .padding({ left: this.f(26), right: this.f(26), top: this.f(29), bottom: this.f(19) })

      Row({ space: this.f(16) }) {
        Stack() {
          Text('+')
            .fontSize(this.f(32))
            .fontWeight(FontWeight.Lighter)
            .fontColor(this.pal().sub)
        }
        .width(this.f(51))
        .height(this.f(51))
        .borderRadius(this.f(25.5))
        .border({ width: this.f(3), color: this.hexA(this.pal().sub, '73') })

        Row() {
          Text('···')
            .fontSize(this.f(20))
            .letterSpacing(this.f(3))
            .fontColor(this.hexA(this.pal().sub, '99'))
            .margin({ left: this.f(24) })
        }
        .layoutWeight(1)
        .height(this.f(58))
        .backgroundColor(this.pal().bg)
        .borderRadius(this.f(999))
        .border({ width: this.f(2), color: this.hexA(this.pal().sub, '33') })
        .alignItems(VerticalAlign.Center)

        Stack() {
          Text('◉')
            .fontSize(this.f(24))
            .fontColor(this.pal().sub)
        }
        .width(this.f(51))
        .height(this.f(51))
        .borderRadius(this.f(25.5))
        .border({ width: this.f(3), color: this.hexA(this.pal().sub, '73') })
      }
      .width('100%')
      .height(this.f(93))
      .padding({ left: this.f(22), right: this.f(22) })
      .backgroundColor(this.pal().block)
      .border({ width: { top: this.f(1.6) }, color: this.hexA(this.pal().sub, '40') })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
  }

  // ---------- T13 黑胶唱片（聚光灯唱片 + 曲目单，参照 docs/文案海报候选_黑胶唱片.html） ----------

  @Builder
  VinylRecord() {
    Stack() {
      Column()
        .width(this.f(739))
        .height(this.f(739))
        .borderRadius(this.f(370))
        .radialGradient({
          center: ['50%', '50%'],
          radius: '50%',
          colors: [[this.hexA(this.pal().accent, '21'), 0], ['#00000000', 0.62], ['#00000000', 1]],
        })
        .position({ x: this.previewWidth / 2 - this.f(370), y: this.fy(208) })
        .hitTestBehavior(HitTestMode.None)

      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .borderRadius(this.f(267))
          .radialGradient({
            center: ['50%', '50%'],
            radius: '100%',
            colors: [
              [this.pal().grid, 0], ['#12100D', 0.05], [this.pal().grid, 0.1], ['#12100D', 0.15],
              [this.pal().grid, 0.2], ['#12100D', 0.25], [this.pal().grid, 0.3], ['#12100D', 0.35],
              [this.pal().grid, 0.4], ['#12100D', 0.45], [this.pal().grid, 0.5], ['#12100D', 0.55],
              [this.pal().grid, 0.6], ['#12100D', 0.65], [this.pal().grid, 0.7], ['#12100D', 0.75],
              [this.pal().grid, 0.8], ['#12100D', 0.85], [this.pal().grid, 0.9], ['#12100D', 0.95],
              ['#12100D', 1],
            ],
          })
          .shadow({ radius: this.f(96), color: '#BF000000', offsetY: this.f(39) })
          .border({ width: this.f(2), color: this.hexA('#FFFFFF', '14') })

        Column()
          .width('100%')
          .height('100%')
          .borderRadius(this.f(267))
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
          Text(this.content.tag.trim() !== '' ? this.content.tag.trim() : 'POCKET LP')
            .fontSize(this.f(19))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal().block)
            .fontFamily(this.font())
            .letterSpacing(this.f(2.4))
            .maxLines(1)
            .constraintSize({ maxWidth: this.f(186) })
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('33⅓ RPM · STEREO')
            .fontSize(this.f(13))
            .fontColor(this.hexA(this.pal().block, 'BF'))
            .letterSpacing(this.f(3.2))
            .margin({ top: this.f(4) })
          Column()
            .width(this.f(14))
            .height(this.f(14))
            .borderRadius(this.f(7))
            .backgroundColor(this.pal().bg)
            .margin({ top: this.f(6) })
        }
        .width(this.f(190))
        .height(this.f(190))
        .borderRadius(this.f(95))
        .backgroundColor(this.pal().accent)
        .border({ width: this.f(1.6), color: this.hexA('#000000', '66') })
        .radialGradient({
          center: ['50%', '38%'],
          radius: '75%',
          colors: [['#2BFFFFFF', 0], ['#00FFFFFF', 0.55], ['#26000000', 1]],
        })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width(this.f(534))
      .height(this.f(534))
      .rotate({ angle: 14 })
      .position({ x: this.previewWidth / 2 - this.f(267), y: this.fy(106) })

      Column() {
        Text('SIDE A')
          .fontSize(this.f(18))
          .letterSpacing(this.f(10))
          .fontColor(this.pal().sub)
        Row()
          .width(this.f(55))
          .height(this.f(3))
          .backgroundColor(this.hexA(this.pal().title, '2E'))
          .margin({ top: this.f(16), bottom: this.f(26) })
        Row({ space: this.f(19) }) {
          Text('A1')
            .fontSize(this.f(18))
            .fontColor(this.pal().sub)
            .letterSpacing(this.f(1.6))
          if (this.content.body.trim() === '') {
            Text($r('app.string.poster_empty_hint'))
              .fontSize(this.f(24))
              .fontColor(this.pal().sub)
              .fontFamily(this.font())
              .maxLines(1)
          } else {
            Text(this.content.body)
              .fontSize(this.f(31))
              .fontColor(this.pal().title)
              .fontFamily(this.font())
              .letterSpacing(this.f(3))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: this.previewWidth - this.f(120) })
          }
          Text('4:26')
            .fontSize(this.f(16))
            .fontColor(this.pal().sub)
        }
        .alignItems(VerticalAlign.Bottom)
        .margin({ bottom: this.f(16) })

        Row({ space: this.f(19) }) {
          Text('B1')
            .fontSize(this.f(18))
            .fontColor(this.pal().sub)
            .letterSpacing(this.f(1.6))
          Text(this.content.sign)
            .fontSize(this.f(31))
            .fontColor(this.pal().title)
            .fontFamily(this.font())
            .letterSpacing(this.f(3))
            .maxLines(1)
            .constraintSize({ maxWidth: this.previewWidth - this.f(120) })
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('3:05')
            .fontSize(this.f(16))
            .fontColor(this.pal().sub)
        }
        .alignItems(VerticalAlign.Bottom)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .position({ x: 0, y: this.fy(688) })

      Text('POCKET RECORDS · 2026')
        .fontSize(this.f(14))
        .letterSpacing(this.f(8))
        .fontColor(this.hexA(this.pal().sub, '8C'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .position({ x: 0, y: this.h() - this.f(26) })

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
  FilmStrip(offsetX: number) {
    Column() {
      Column() {
        ForEach([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], (i: number) => {
          Row()
            .width(this.f(26))
            .height(this.f(19))
            .borderRadius(this.f(5))
            .backgroundColor(this.pal().grid)
        }, (i: number) => i.toString())
      }
      .width(this.f(26))
      .height('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .alignItems(HorizontalAlign.Center)
    }
    .width(this.f(55))
    .height('100%')
    .backgroundColor(this.pal().block)
    .alignItems(HorizontalAlign.Center)
    .position({ x: offsetX, y: 0 })
  }

  @Builder
  CinemaCard() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({ angle: 180, colors: [[this.pal().bg, 0], [this.pal().bg2, 0.55], [this.pal().bg2, 1]] })
        .hitTestBehavior(HitTestMode.None)

      Column()
        .width(this.f(675))
        .height(this.f(675))
        .borderRadius(this.f(337))
        .radialGradient({
          center: ['50%', '50%'],
          radius: '50%',
          colors: [[this.hexA(this.pal().accent, '1A'), 0], ['#00000000', 0.62], ['#00000000', 1]],
        })
        .position({ x: this.previewWidth / 2 - this.f(337), y: this.fy(378) - this.f(337) })
        .hitTestBehavior(HitTestMode.None)

      this.FilmStrip(0)
      this.FilmStrip(this.previewWidth - this.f(55))

      Column() {
        Text(this.content.tag.trim() !== '' ? this.content.tag.trim() : 'POCKET PICTURES')
          .fontSize(this.f(19))
          .letterSpacing(this.f(11))
          .fontColor(this.pal().sub)
          .fontFamily(this.font())
          .maxLines(1)
        Row()
          .width(this.f(68))
          .height(this.f(3))
          .backgroundColor(this.pal().accent)
          .margin({ top: this.f(29), bottom: this.f(42) })
        if (this.content.body.trim() === '') {
          Text($r('app.string.poster_empty_hint'))
            .fontSize(this.f(28))
            .fontColor(this.pal().sub)
            .fontFamily(this.font())
            .textAlign(TextAlign.Center)
        } else {
          Text(this.content.body)
            .fontSize(this.bodyFont(55, false))
            .lineHeight(this.bodyFont(55, false) * 1.5)
            .fontColor(this.pal().title)
            .fontFamily(this.font())
            .fontWeight(FontWeight.Bold)
            .letterSpacing(this.f(8))
            .maxLines(this.maxBodyLines(false))
            .textAlign(TextAlign.Center)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textShadow([{ radius: this.f(29), color: '#CC000000', offsetX: 0, offsetY: this.f(3) }])
        }
        if (this.content.sign.trim() !== '') {
          Text(this.content.sign)
            .fontSize(this.f(27))
            .fontColor(this.hexA(this.pal().title, 'B3'))
            .fontFamily(this.font())
            .fontStyle(FontStyle.Italic)
            .letterSpacing(this.f(5))
            .maxLines(1)
            .margin({ top: this.f(39) })
        }
        Row()
          .width(this.f(42))
          .height(this.f(2.5))
          .backgroundColor(this.hexA(this.pal().accent, '8C'))
          .margin({ top: this.f(42), bottom: this.f(29) })
        Text('COMING SOON · OCT 2026')
          .fontSize(this.f(16))
          .letterSpacing(this.f(8))
          .fontColor(this.pal().sub)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding({ left: this.f(141), right: this.f(141) })

      Column()
        .width('100%')
        .height('100%')
        .backgroundImage($r('app.media.poster_film_grain'), ImageRepeat.XY)
        .backgroundImageSize({ width: this.f(3), height: this.f(3) })
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

  // ---------- T15 公告栏启事（软木板图钉便签，参照 docs/文案海报候选_公告栏启事.html） ----------

  @Builder
  CorkPin(px: number, py: number) {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(this.f(13.5))
        .radialGradient({
          center: ['36%', '32%'],
          radius: '90%',
          colors: [['#8CFFFFFF', 0], [this.pal().accent, 0.62], [this.hexA('#000000', '73'), 1]],
        })
      Column()
        .width(this.f(9))
        .height(this.f(9))
        .borderRadius(this.f(4.5))
        .backgroundColor(this.hexA('#000000', 'A6'))
    }
    .width(this.f(27))
    .height(this.f(27))
    .shadow({ radius: this.f(8), color: '#8C000000', offsetY: this.f(5) })
    .position({ x: this.f(px) - this.f(13.5), y: this.fy(py) - this.f(13.5) })
  }

  @Builder
  CorkString(px: number, py: number, len: number, angle: number) {
    Row()
      .width(this.f(len))
      .height(this.f(4))
      .borderRadius(this.f(2))
      .backgroundColor(this.pal().accent)
      .opacity(0.85)
      .rotate({ angle: angle, centerX: '0%', centerY: '50%' })
      .position({ x: this.f(px), y: this.fy(py) - this.f(2) })
  }

  @Builder
  CorkNotice() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundImage($r('app.media.poster_cork_grain'), ImageRepeat.XY)
        .backgroundImageSize({ width: this.f(46), height: this.f(46) })
        .hitTestBehavior(HitTestMode.None)

      Column()
        .width('100%')
        .height('100%')
        .border({ width: this.f(31), color: this.hexA('#000000', '40') })
        .hitTestBehavior(HitTestMode.None)
      Column()
        .width('100%')
        .height('100%')
        .border({ width: this.f(29), color: this.pal().grid })
        .hitTestBehavior(HitTestMode.None)

      if (this.content.tag.trim() !== '') {
        Column() {
          Text(this.content.tag)
            .fontSize(this.f(40))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal().title)
            .fontFamily(this.font())
            .letterSpacing(this.f(5))
            .maxLines(2)
            .textAlign(TextAlign.Center)
          Text('NOTICE')
            .fontSize(this.f(14))
            .fontColor(this.pal().sub)
            .letterSpacing(this.f(2))
            .margin({ top: this.f(10) })
        }
        .width(this.f(286))
        .padding({ left: this.f(22), right: this.f(22), top: this.f(32), bottom: this.f(21) })
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.pal().block)
        .linearGradient({ angle: 170, colors: [[this.hexA(this.pal().grid, '1F'), 0], [this.hexA(this.pal().grid, '0D'), 1]] })
        .borderRadius(this.f(2))
        .shadow({ radius: this.f(42), color: '#6B28180A', offsetY: this.f(19) })
        .rotate({ angle: 2.5 })
        .position({ x: this.f(511), y: this.fy(129) })
      }

      Column() {
        if (this.content.body.trim() === '') {
          Text($r('app.string.poster_empty_hint'))
            .fontSize(this.f(30))
            .fontColor(this.pal().sub)
            .fontFamily(this.font())
            .textAlign(TextAlign.Center)
        } else {
          Text(this.content.body)
            .fontSize(this.f(40))
            .lineHeight(this.f(40) * 1.65)
            .fontColor(this.pal().title)
            .fontFamily(this.font())
            .letterSpacing(this.f(1.6))
            .maxLines(this.maxBodyLines(false))
            .textAlign(TextAlign.Center)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Text('2026.10.11')
          .fontSize(this.f(18))
          .fontColor(this.pal().sub)
          .letterSpacing(this.f(3))
          .margin({ top: this.f(19) })
      }
      .width(this.f(485))
      .padding({ left: this.f(35), right: this.f(35), top: this.f(42), bottom: this.f(29) })
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.pal().block)
      .linearGradient({ angle: 165, colors: [[this.hexA('#FFFFFF', '17'), 0], ['#00FFFFFF', 1]] })
      .borderRadius(this.f(2))
      .shadow({ radius: this.f(42), color: '#6B28180A', offsetY: this.f(19) })
      .rotate({ angle: -1.5 })
      .position({ x: this.f(235), y: this.fy(376) })

      if (this.content.sign.trim() !== '') {
        Column() {
          Text('—— ' + this.content.sign)
            .fontSize(this.f(30))
            .fontColor(this.pal().title)
            .fontFamily(this.font())
            .letterSpacing(this.f(1.6))
            .maxLines(2)
            .textAlign(TextAlign.Center)
          Row()
            .width(this.f(119))
            .height(this.f(3))
            .backgroundColor(this.pal().accent)
            .opacity(0.65)
            .margin({ top: this.f(14) })
        }
        .width(this.f(305))
        .padding({ left: this.f(22), right: this.f(22), top: this.f(29), bottom: this.f(19) })
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.pal().block)
        .linearGradient({ angle: 170, colors: [[this.hexA('#FFFFFF', '14'), 0], ['#00FFFFFF', 1]] })
        .borderRadius(this.f(2))
        .shadow({ radius: this.f(42), color: '#6B28180A', offsetY: this.f(19) })
        .rotate({ angle: 3 })
        .position({ x: this.f(556), y: this.fy(669) })
      }

      if (this.content.tag.trim() !== '') {
        this.CorkString(653, 129, 302, 125.3)
      }
      if (this.content.tag.trim() !== '' && this.content.sign.trim() !== '') {
        this.CorkString(478, 377, 368, 51.8)
      }
      if (this.content.tag.trim() !== '') {
        this.CorkPin(653, 129)
      }
      this.CorkPin(478, 377)
      if (this.content.sign.trim() !== '') {
        this.CorkPin(708, 669)
      }

      Text('CORK BOARD · NOTICE')
        .fontSize(this.f(19))
        .letterSpacing(this.f(5))
        .fontColor(this.hexA(this.pal().title, 'A6'))
        .rotate({ angle: -1 })
        .position({ x: this.f(84), y: this.h() - this.f(52) })

      Column()
        .width('100%')
        .height('100%')
        .radialGradient({
          center: ['50%', '50%'],
          radius: '95%',
          colors: [['#00000000', 0.55], [this.hexA('#000000', '38'), 1]],
        })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
  }
}
