/**
 * 文案海报预览渲染组件：设计稿 900 宽（1:1 -> 900 高 / 3:4 -> 1200 高 / 9:16 -> 1600 高），18 种布局
 * 尺寸换算：f(px) = previewWidth * px / 900；主文案按长度分档自动缩字号（emoji 走系统字体兜底）
 * 注音开关（pinyinOn）：逐字拼音列（汉字单字带拼音、非汉字整段不注），字号按预算公式收缩防溢出
 */
import { CopyPosterContent, CopyPosterRatio, CopyPosterTemplate } from '../../model/CopyPosterModels';
import { CoverPalette } from '../../model/CoverModels';
import { CopyPosterTemplates } from '../../core/cover/CopyPosterTemplates';
import { CoverContentUtil, HanziUnit } from '../../core/cover/CoverContentUtil';

/** 拼音字号 / 主文案字号比（拼音走系统字体兜底，1.4.1 声调字符教训） */
const PY_RATIO: number = 0.3;
/** 注音开启时主文案字号收缩系数：拼音行高≈1.17×拼音字号(0.3×字号)，预算取 1.3 系数 -> 1/(1+0.3×1.3)≈0.72 */
const PY_SHRINK: number = 0.72;

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
  /** 主文案拼音注音开关（固定构图模板不生效） */
  @Prop pinyinOn: boolean = false;
  /** 是否渲染根层水印（主预览/导出开，模板缩略图关防糊点） */
  @Prop showWatermark: boolean = true;

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

  /** 主文案字号：常规模板按长度 5 档缩放；大字模板 3 档 + 超 16 字降级常规；注音开启时按预算公式收缩 */
  private bodyFont(basePx: number, big: boolean): number {
    let n: number = this.bodyLen();
    let s: number;
    if (big) {
      if (n <= 4) {
        s = this.f(150);
      } else if (n <= 8) {
        s = this.f(112);
      } else if (n <= 16) {
        s = this.f(80);
      } else {
        s = this.f(52);
      }
    } else if (n <= 8) {
      s = this.f(basePx);
    } else if (n <= 16) {
      s = this.f(basePx * 0.8);
    } else if (n <= 32) {
      s = this.f(basePx * 0.62);
    } else if (n <= 60) {
      s = this.f(basePx * 0.48);
    } else {
      s = this.f(basePx * 0.38);
    }
    return this.pyEnabled() ? s * PY_SHRINK : s;
  }

  /** 主文案行数上限：竖图更宽容 */
  private maxBodyLines(big: boolean): number {
    if (big && this.bodyLen() <= 16) {
      return 4;
    }
    return this.ratioKind === CopyPosterRatio.SQUARE ? 8 : 12;
  }

  /** 注音是否生效：开关开 + 模板支持 + 主文案非空 */
  private pyEnabled(): boolean {
    return this.pinyinOn && this.template.supportsPinyin && this.content.body.trim() !== '';
  }

  /** 注音模式字/拼音阴影：neon=霓虹三层 / soft=荧光单层 / none=无（透明零半径兜底保持数组非空） */
  private pyShadow(glow: string): ShadowOptions[] {
    if (glow === 'neon') {
      return [
        { radius: this.f(4), color: '#FFFFFFFF', offsetX: 0, offsetY: 0 },
        { radius: this.f(10), color: this.hexA(this.pal().accent, '#E6'), offsetX: 0, offsetY: 0 },
        { radius: this.f(26), color: this.hexA(this.pal().accent, '#8C'), offsetX: 0, offsetY: 0 },
      ];
    }
    if (glow === 'soft') {
      return [{ radius: this.f(3), color: this.hexA(this.pal().accent, '#B3'), offsetX: 0, offsetY: 0 }];
    }
    return [{ radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 }];
  }

  /**
   * 主文案注音排版：汉字逐字单元（拼音在字上方对齐），非汉字整段合并不注音；
   * 自动按实际宽度换行，拼音行高预算 1.3 系数；maxWidthVp 为换行宽度上限（'100%' 或具体值）
   */
  @Builder
  PinyinBody(sizeVp: number, color: ResourceColor, pyColor: ResourceColor, center: boolean,
    bold: boolean, glow: string, maxWidthVp: Length) {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: center ? FlexAlign.Center : FlexAlign.Start }) {
      ForEach(CoverContentUtil.hanziUnits(this.content.body), (u: HanziUnit, i: number) => {
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
            .fontFamily(this.font())
            .fontWeight(bold ? FontWeight.Bold : FontWeight.Normal)
            .maxLines(1)
            .textShadow(this.pyShadow(glow))
        }
        .constraintSize({ minWidth: u.text.length === 1 ? sizeVp : 0 })
        .alignItems(HorizontalAlign.Center)
      }, (u: HanziUnit, i: number) => i.toString() + '-' + u.text + '-' + u.py)
    }
    .constraintSize({ maxWidth: maxWidthVp })
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
      } else if (this.template.layout === 'solar_term') {
        this.SolarTerm()
      } else if (this.template.layout === 'festival_greet') {
        this.FestivalGreet()
      } else if (this.template.layout === 'red_couplet') {
        this.RedCouplet()
      } else {
        this.BigImpact()
      }
      if (this.showWatermark && this.content.watermarkOn && this.content.watermarkText.trim() !== '') {
        this.WatermarkLayer()
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

  /** 根层水印：右下角小字（模板无关，palette title 色 50% 透明，18 布局一次生效） */
  @Builder
  WatermarkLayer() {
    Column() {
      Blank()
      Row() {
        Blank()
        Text(this.content.watermarkText.trim())
          .fontSize(this.f(22))
          .fontColor(this.hexA(this.pal().title, '80'))
          .maxLines(1)
      }
      .width('100%')
      .padding({ right: this.f(24), bottom: this.f(18) })
    }
    .width('100%')
    .height('100%')
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

  /** 主文案块：空文案显示占位提示；注音开启逐字注音；超长自动缩字号 + 省略兜底 */
  @Builder
  BodyBlock(basePx: number, bold: boolean, big: boolean) {
    if (this.content.body.trim() === '') {
      Text($r('app.string.poster_empty_hint'))
        .fontSize(this.f(28))
        .fontColor(this.pal().sub)
        .fontFamily(this.font())
        .textAlign(TextAlign.Center)
    } else if (this.pyEnabled()) {
      this.PinyinBody(this.bodyFont(basePx, big), this.pal().title, this.pal().sub, true, bold, 'none', '100%')
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
      } else if (this.pyEnabled()) {
        this.PinyinBody(this.bodyFont(43, false), this.pal().title, this.pal().title, false, false, 'none', '100%')
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
            } else if (this.pyEnabled()) {
              this.PinyinBody(this.bodyFont(50, false), this.pal().title, this.pal().sub, false, false, 'soft', '100%')
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
    return this.f(this.ratioKind === CopyPosterRatio.SQUARE ? 470 : 620);
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
          } else if (this.pyEnabled()) {
            this.PinyinBody(this.bodyFont(96, false), this.pal().title, this.pal().sub, true, true, 'neon', '100%')
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
                } else if (this.pyEnabled()) {
                  this.PinyinBody(this.bodyFont(38, false), this.pal().title, this.pal().accent, false, false, 'none', '100%')
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
    return this.f(this.ratioKind === CopyPosterRatio.SQUARE ? 440 : 560);
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
          } else if (this.pyEnabled()) {
            Column() {
              this.PinyinBody(this.f(25) * PY_SHRINK, this.pal().title, this.pal().sub, false, false, 'none',
                this.previewWidth * 0.64 - this.f(44))
            }
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

  // ---------- T16 二十四节气卡（竖排主文案 + 节气名/印章/节气歌，参照 docs/文案海报候选_二十四节气卡.html） ----------

  /** 竖排字符序列：去空白逐字拆分 */
  private vertChars(text: string): string[] {
    return Array.from(text.replace(new RegExp('\\s', 'g'), ''));
  }

  /** 竖排列切分（自右向左读）：perCol 字/列、maxCols 列封顶，超限末列末字换 '…'；返回自左向右渲染顺序（首列在最右） */
  private vertColsRtl(text: string, perCol: number, maxCols: number): string[][] {
    let chars: string[] = this.vertChars(text);
    let per: number = Math.max(1, perCol);
    let cols: string[][] = [];
    if (chars.length === 0) {
      return cols;
    }
    let total: number = per * Math.max(1, maxCols);
    if (chars.length > total) {
      chars = chars.slice(0, total);
      chars[chars.length - 1] = '…';
    }
    let natural: string[][] = [];
    for (let i = 0; i < chars.length; i += per) {
      natural.push(chars.slice(i, i + per));
    }
    for (let i = natural.length - 1; i >= 0; i--) {
      cols.push(natural[i]);
    }
    return cols;
  }

  /** T16 节气名（tag）字数 */
  private termCharCount(): number {
    return this.vertChars(this.content.tag).length;
  }

  /** T16 节气名字号分档：≤2 字 74 / ≤4 字 52 / 其余 38（设计 px） */
  private vertTermSize(): number {
    let n: number = this.termCharCount();
    if (n <= 2) {
      return this.f(74);
    }
    if (n <= 4) {
      return this.f(52);
    }
    return this.f(38);
  }

  /** T16 竖排主文案字号分档（设计 px） */
  private solarBodyPx(): number {
    let n: number = this.vertChars(this.content.body).length;
    if (n <= 20) {
      return 48;
    }
    if (n <= 45) {
      return 38;
    }
    return 30;
  }

  /** T16 每列字数：可用高度 / 行高 */
  private solarPerCol(): number {
    let lh: number = this.f(this.solarBodyPx() * 1.3);
    let avail: number = this.h() - this.fy(122) - this.f(209);
    return Math.max(1, Math.floor(avail / lh));
  }

  /** T16 列数上限：可用宽度 / 列距（字号 × 1.63） */
  private solarMaxCols(): number {
    let pitch: number = this.f(this.solarBodyPx() * 1.63);
    let avail: number = this.previewWidth - this.f(270) - this.f(167);
    return Math.max(1, Math.floor(avail / pitch));
  }

  @Builder
  SolarTerm() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .radialGradient({
          center: ['30%', '18%'],
          radius: '80%',
          colors: [[this.hexA('#FFFFFF', '12'), 0], ['#00FFFFFF', 1]],
        })
        .hitTestBehavior(HitTestMode.None)

      Column()
        .width(this.previewWidth - this.f(29) * 2)
        .height(this.h() - this.f(29) * 2)
        .border({ width: this.f(1.6), color: this.hexA(this.pal().grid, '80') })
        .position({ x: this.f(29), y: this.f(29) })
      Column()
        .width(this.previewWidth - this.f(40) * 2)
        .height(this.h() - this.f(40) * 2)
        .border({ width: this.f(3.2), color: this.pal().sub })
        .position({ x: this.f(40), y: this.f(40) })

      Row().width(this.f(14)).height(this.f(14)).backgroundColor(this.pal().sub).rotate({ angle: 45 })
        .position({ x: this.f(64), y: this.fy(64) })
      Row().width(this.f(14)).height(this.f(14)).backgroundColor(this.pal().sub).rotate({ angle: 45 })
        .position({ x: this.previewWidth - this.f(64) - this.f(14), y: this.fy(64) })
      Row().width(this.f(14)).height(this.f(14)).backgroundColor(this.pal().sub).rotate({ angle: 45 })
        .position({ x: this.f(64), y: this.h() - this.fy(64) - this.f(14) })
      Row().width(this.f(14)).height(this.f(14)).backgroundColor(this.pal().sub).rotate({ angle: 45 })
        .position({ x: this.previewWidth - this.f(64) - this.f(14), y: this.h() - this.fy(64) - this.f(14) })

      Column({ space: this.f(29) }) {
        if (this.termCharCount() > 0) {
          Text(this.vertChars(this.content.tag).join('\n'))
            .fontSize(this.vertTermSize())
            .lineHeight(this.vertTermSize() * 1.3)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal().block)
            .fontFamily(this.font())
            .textAlign(TextAlign.Center)
        }
        if (this.termCharCount() > 0 && this.termCharCount() <= 4) {
          Text('S\nO\nL\nA\nR\n \nT\nE\nR\nM')
            .fontSize(this.f(18))
            .lineHeight(this.f(24))
            .letterSpacing(this.f(3))
            .fontColor(this.pal().sub)
            .textAlign(TextAlign.Center)
        }
        Column() {
          Text('节\n气')
            .fontSize(this.f(20))
            .lineHeight(this.f(24))
            .fontWeight(FontWeight.Bold)
            .fontColor('#F6EFDE')
            .textAlign(TextAlign.Center)
        }
        .width(this.f(64))
        .height(this.f(64))
        .backgroundColor(this.pal().accent)
        .borderRadius(this.f(6.4))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .shadow({ radius: this.f(10), color: this.hexA(this.pal().accent, '59'), offsetY: this.f(3) })
      }
      .alignItems(HorizontalAlign.Center)
      .position({ x: this.f(119), y: this.fy(148) })

      Column()
        .width(this.f(1.6))
        .height(this.h() - this.fy(135) - this.f(135))
        .linearGradient({
          angle: 180,
          colors: [[this.hexA(this.pal().grid, '00'), 0], [this.pal().grid, 0.18],
            [this.pal().grid, 0.82], [this.hexA(this.pal().grid, '00'), 1]],
        })
        .position({ x: this.f(270), y: this.fy(135) })

      Column() {
        if (this.content.body.trim() === '') {
          Text($r('app.string.poster_empty_hint'))
            .fontSize(this.f(28))
            .fontColor(this.pal().sub)
            .fontFamily(this.font())
            .width('100%')
            .textAlign(TextAlign.Center)
        } else {
          Row({ space: this.f(this.solarBodyPx() * 0.63) }) {
            ForEach(this.vertColsRtl(this.content.body, this.solarPerCol(), this.solarMaxCols()),
              (col: string[], i: number) => {
                Text(col.join('\n'))
                  .fontSize(this.f(this.solarBodyPx()))
                  .lineHeight(this.f(this.solarBodyPx() * 1.3))
                  .fontColor(this.pal().title)
                  .fontFamily(this.font())
                  .textAlign(TextAlign.Center)
              }, (col: string[], i: number) =>
              i.toString() + '-' + col.length.toString() + '-' + (col.length > 0 ? col[0] : ''))
          }
          .alignItems(VerticalAlign.Top)
        }
      }
      .width(this.previewWidth - this.f(270) - this.f(167))
      .height(this.h() - this.fy(122) - this.f(209))
      .alignItems(HorizontalAlign.End)
      .position({ x: this.f(270), y: this.fy(122) })

      if (this.content.sign.trim() !== '') {
        Column() {
          Text(this.vertChars(this.content.sign).join('\n'))
            .fontSize(this.f(21))
            .lineHeight(this.f(27))
            .fontColor(this.pal().sub)
            .fontFamily(this.font())
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.End)
        .padding({ right: this.f(122), bottom: this.f(125) })
      }

      Row({ space: this.f(19) }) {
        Row().width(this.f(54)).height(this.f(1.6)).backgroundColor(this.pal().grid)
        Text('春雨惊春清谷天 · 夏满芒夏暑相连')
          .fontSize(this.f(18))
          .letterSpacing(this.f(6))
          .fontColor(this.pal().sub)
          .fontFamily(this.font())
        Row().width(this.f(54)).height(this.f(1.6)).backgroundColor(this.pal().grid)
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .position({ x: 0, y: this.h() - this.f(102) })

      Column()
        .width('100%')
        .height('100%')
        .radialGradient({
          center: ['50%', '50%'],
          radius: '95%',
          colors: [['#00000000', 0.62], [this.hexA('#3E301A', '29'), 1]],
        })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
  }

  // ---------- T17 节日祝福卡（圆月星点几何 + 居中祝福，参照 docs/文案海报候选_节日祝福卡.html） ----------

  @Builder
  FestStar(dx: number, dy: number, opacity: number) {
    Circle({ width: this.f(5), height: this.f(5) })
      .fill(this.pal().grid)
      .opacity(opacity)
      .position({ x: this.f(dx), y: this.fy(dy) })
  }

  /** 远山剪影 Path 命令（commands 单位为 px，取 vp × density） */
  private hillPath(w: number, h: number, x1: number, y1: number, x2: number, y2: number,
    x3: number, y3: number): string {
    return 'M0 ' + h + ' L' + (w * x1) + ' ' + (h * y1) + ' L' + (w * x2) + ' ' + (h * y2) +
      ' L' + (w * x3) + ' ' + (h * y3) + ' L' + w + ' ' + h + ' Z';
  }

  @Builder
  FestivalGreet() {
    Stack() {
      this.FestStar(103, 125, 0.85)
      this.FestStar(206, 71, 0.6)
      this.FestStar(350, 154, 0.8)
      this.FestStar(517, 90, 0.5)
      this.FestStar(691, 135, 0.9)
      this.FestStar(798, 225, 0.55)
      this.FestStar(135, 289, 0.4)
      this.FestStar(755, 373, 0.65)

      Column()
        .width(this.f(512))
        .height(this.f(512))
        .borderRadius(this.f(256))
        .radialGradient({
          center: ['50%', '50%'],
          radius: '70%',
          colors: [[this.hexA(this.pal().accent, '38'), 0], [this.hexA(this.pal().accent, '0D'), 0.62],
            [this.hexA(this.pal().accent, '00'), 1]],
        })
        .position({ x: this.previewWidth / 2 - this.f(256), y: this.fy(173) })

      Column()
        .width(this.f(240))
        .height(this.f(240))
        .borderRadius(this.f(120))
        .radialGradient({
          center: ['42%', '38%'],
          radius: '75%',
          colors: [[this.hexA('#FFFFFF', 'B3'), 0], [this.pal().accent, 0.6], [this.hexA('#000000', '2E'), 1]],
        })
        .shadow({ radius: this.f(70), color: this.hexA(this.pal().accent, '73') })
        .position({ x: this.previewWidth / 2 - this.f(120), y: this.fy(237) })

      Column()
        .width(this.f(272))
        .height(this.f(272))
        .borderRadius(this.f(136))
        .border({ width: this.f(1.6), color: this.hexA(this.pal().accent, '59') })
        .position({ x: this.previewWidth / 2 - this.f(136), y: this.fy(221) })

      Row().width(this.f(238)).height(this.f(35)).borderRadius(this.f(18))
        .backgroundColor(this.hexA(this.pal().block, '24'))
        .position({ x: this.f(122), y: this.fy(379) })
      Row().width(this.f(145)).height(this.f(35)).borderRadius(this.f(18))
        .backgroundColor(this.hexA(this.pal().block, '1A'))
        .position({ x: this.f(193), y: this.fy(421) })
      Row().width(this.f(199)).height(this.f(35)).borderRadius(this.f(18))
        .backgroundColor(this.hexA(this.pal().block, '1A'))
        .position({ x: this.previewWidth - this.f(315), y: this.fy(334) })
      Row().width(this.f(116)).height(this.f(35)).borderRadius(this.f(18))
        .backgroundColor(this.hexA(this.pal().block, '14'))
        .position({ x: this.previewWidth - this.f(302), y: this.fy(376) })

      Path()
        .width(this.f(482))
        .height(this.f(177))
        .commands(this.hillPath(this.f(482) * this.density, this.f(177) * this.density,
          0.22, 0.34, 0.46, 0.78, 0.68, 0.08))
        .fill(this.hexA('#05070D', '99'))
        .position({ x: -this.f(48), y: this.h() - this.f(119) - this.f(177) })
      Path()
        .width(this.f(530))
        .height(this.f(154))
        .commands(this.hillPath(this.f(530) * this.density, this.f(154) * this.density,
          0.26, 0.52, 0.52, 0.86, 0.76, 0.22))
        .fill(this.hexA('#05070D', 'CC'))
        .position({ x: this.previewWidth - this.f(466), y: this.h() - this.f(119) - this.f(154) })

      if (this.content.tag.trim() !== '') {
        Column() {
          Text(this.content.tag)
            .fontSize(this.f(27))
            .fontColor(this.pal().accent)
            .fontFamily(this.font())
            .letterSpacing(this.f(16))
            .maxLines(1)
            .padding({ left: this.f(42) + this.f(16), right: this.f(42), top: this.f(11), bottom: this.f(11) })
            .border({ width: this.f(1.6), color: this.hexA(this.pal().accent, '66') })
            .backgroundColor(this.hexA(this.pal().accent, '12'))
            .borderRadius(this.f(999))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .position({ x: 0, y: this.fy(84) })
      }

      Column() {
        if (this.content.body.trim() === '') {
          Text($r('app.string.poster_empty_hint'))
            .fontSize(this.f(28))
            .fontColor(this.pal().sub)
            .fontFamily(this.font())
            .textAlign(TextAlign.Center)
        } else if (this.pyEnabled()) {
          Column() {
            this.PinyinBody(this.bodyFont(54, false), this.pal().title, this.pal().sub, true, false, 'none', '100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        } else {
          Text(this.content.body)
            .fontSize(this.bodyFont(54, false))
            .lineHeight(this.bodyFont(54, false) * 1.55)
            .fontColor(this.pal().title)
            .fontFamily(this.font())
            .letterSpacing(this.f(10))
            .maxLines(5)
            .textAlign(TextAlign.Center)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .shadow({ radius: this.f(35), color: '#8C000000', offsetY: this.f(5) })
        }
      }
      .width('100%')
      .height(this.fy(726) - this.fy(518))
      .justifyContent(FlexAlign.Center)
      .padding({ left: this.f(96), right: this.f(96) })
      .position({ x: 0, y: this.fy(518) })

      Text('HAPPY FESTIVAL · POCKET GREETING')
        .fontSize(this.f(19))
        .letterSpacing(this.f(11))
        .fontColor(this.hexA(this.pal().sub, '99'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .position({ x: 0, y: this.fy(726) })

      if (this.content.sign.trim() !== '') {
        Text('— ' + this.content.sign + ' —')
          .fontSize(this.f(21))
          .letterSpacing(this.f(6))
          .fontColor(this.hexA(this.pal().accent, 'B8'))
          .fontFamily(this.font())
          .width('100%')
          .textAlign(TextAlign.Center)
          .position({ x: 0, y: this.h() - this.f(96) })
      }

      Column()
        .width('100%')
        .height('100%')
        .radialGradient({
          center: ['50%', '50%'],
          radius: '95%',
          colors: [['#00000000', 0.55], [this.hexA('#03050C', '80'), 1]],
        })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
  }

  // ---------- T18 红包对联风（红金竖批 + 铜钱团花，参照 docs/文案海报候选_红包对联风.html） ----------

  /** T18 竖批主文案字号分档（设计 px） */
  private coupletBodyPx(): number {
    let n: number = this.vertChars(this.content.body).length;
    if (n <= 12) {
      return 70;
    }
    if (n <= 24) {
      return 56;
    }
    return 44;
  }

  /** T18 每列字数 */
  private coupletPerCol(): number {
    let lh: number = this.f(this.coupletBodyPx() * 1.36);
    let avail: number = this.h() - this.fy(238) - this.fy(174);
    return Math.max(1, Math.floor(avail / lh));
  }

  /** T18 列数上限 */
  private coupletMaxCols(): number {
    let pitch: number = this.f(this.coupletBodyPx() * 1.9);
    let avail: number = this.previewWidth - this.f(212) * 2;
    return Math.max(1, Math.floor(avail / pitch));
  }

  @Builder
  CoupletCoin(xVp: number, yVp: number) {
    Stack({ alignContent: Alignment.Center }) {
      Circle({ width: this.f(74), height: this.f(74) })
        .fill('#00000000')
        .stroke(this.hexA(this.pal().accent, '29'))
        .strokeWidth(this.f(3.2))
      Circle({ width: this.f(38), height: this.f(38) })
        .fill('#00000000')
        .stroke(this.hexA(this.pal().accent, '29'))
        .strokeWidth(this.f(3.2))
      Row()
        .width(this.f(38))
        .height(this.f(38))
        .border({ width: this.f(3.2), color: this.hexA(this.pal().accent, '1A') })
        .borderRadius(this.f(6.4))
    }
    .width(this.f(74))
    .height(this.f(74))
    .position({ x: xVp, y: yVp })
  }

  @Builder
  CoupletCorner(xVp: number, yVp: number, align: Alignment) {
    Stack({ alignContent: align }) {
      Row().width(this.f(54)).height(this.f(4.8)).backgroundColor(this.pal().accent)
      Row().width(this.f(4.8)).height(this.f(54)).backgroundColor(this.pal().accent)
    }
    .width(this.f(54))
    .height(this.f(54))
    .position({ x: xVp, y: yVp })
  }

  @Builder
  RedCouplet() {
    Stack() {
      this.CoupletCoin(this.f(42), this.fy(154))
      this.CoupletCoin(this.f(42), this.fy(305))
      this.CoupletCoin(this.f(42), this.fy(456))
      this.CoupletCoin(this.previewWidth - this.f(42) - this.f(74), this.fy(154))
      this.CoupletCoin(this.previewWidth - this.f(42) - this.f(74), this.fy(305))

      Column()
        .width(this.previewWidth - this.f(32) * 2)
        .height(this.h() - this.f(32) * 2)
        .border({ width: this.f(3.2), color: this.hexA(this.pal().accent, 'D9') })
        .position({ x: this.f(32), y: this.f(32) })
      Column()
        .width(this.previewWidth - this.f(43) * 2)
        .height(this.h() - this.f(43) * 2)
        .border({ width: this.f(1.6), color: this.hexA(this.pal().accent, '73') })
        .position({ x: this.f(43), y: this.f(43) })

      this.CoupletCorner(this.f(55), this.fy(55), Alignment.TopStart)
      this.CoupletCorner(this.previewWidth - this.f(55) - this.f(54), this.fy(55), Alignment.TopEnd)
      this.CoupletCorner(this.f(55), this.h() - this.fy(55) - this.f(54), Alignment.BottomStart)
      this.CoupletCorner(this.previewWidth - this.f(55) - this.f(54), this.h() - this.fy(55) - this.f(54),
        Alignment.BottomEnd)

      if (this.content.tag.trim() !== '') {
        Column() {
          Text(this.content.tag)
            .fontSize(this.f(38))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal().title)
            .fontFamily(this.font())
            .letterSpacing(this.f(19))
            .maxLines(1)
            .padding({ left: this.f(48) + this.f(19), right: this.f(48), top: this.f(14), bottom: this.f(14) })
            .backgroundColor(this.pal().block)
            .border({ width: this.f(2.4), color: this.pal().accent })
            .shadow({ radius: this.f(26), color: '#59000000', offsetY: this.f(6) })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .position({ x: 0, y: this.fy(87) })
      }

      Column()
        .width(this.f(2.4))
        .height(this.h() - this.fy(225) - this.fy(161))
        .linearGradient({
          angle: 180,
          colors: [[this.hexA(this.pal().accent, '00'), 0], [this.hexA(this.pal().accent, 'BF'), 0.14],
            [this.hexA(this.pal().accent, 'BF'), 0.86], [this.hexA(this.pal().accent, '00'), 1]],
        })
        .position({ x: this.f(212), y: this.fy(225) })
      Column()
        .width(this.f(2.4))
        .height(this.h() - this.fy(225) - this.fy(161))
        .linearGradient({
          angle: 180,
          colors: [[this.hexA(this.pal().accent, '00'), 0], [this.hexA(this.pal().accent, 'BF'), 0.14],
            [this.hexA(this.pal().accent, 'BF'), 0.86], [this.hexA(this.pal().accent, '00'), 1]],
        })
        .position({ x: this.previewWidth - this.f(212) - this.f(2.4), y: this.fy(225) })

      Circle({ width: this.f(16), height: this.f(16) }).fill(this.pal().accent)
        .shadow({ radius: this.f(8), color: '#66000000', offsetY: this.f(2) })
        .position({ x: this.f(212) + this.f(1.2) - this.f(8), y: this.fy(225) - this.f(19) })
      Circle({ width: this.f(16), height: this.f(16) }).fill(this.pal().accent)
        .shadow({ radius: this.f(8), color: '#66000000', offsetY: this.f(2) })
        .position({ x: this.previewWidth - this.f(212) - this.f(1.2) - this.f(8), y: this.fy(225) - this.f(19) })
      Circle({ width: this.f(16), height: this.f(16) }).fill(this.pal().accent)
        .shadow({ radius: this.f(8), color: '#66000000', offsetY: this.f(2) })
        .position({ x: this.f(212) + this.f(1.2) - this.f(8), y: this.h() - this.fy(161) + this.f(3) })
      Circle({ width: this.f(16), height: this.f(16) }).fill(this.pal().accent)
        .shadow({ radius: this.f(8), color: '#66000000', offsetY: this.f(2) })
        .position({ x: this.previewWidth - this.f(212) - this.f(1.2) - this.f(8), y: this.h() - this.fy(161) + this.f(3) })

      Column() {
        if (this.content.body.trim() === '') {
          Text($r('app.string.poster_empty_hint'))
            .fontSize(this.f(30))
            .fontColor(this.hexA(this.pal().title, 'CC'))
            .fontFamily(this.font())
            .width('100%')
            .textAlign(TextAlign.Center)
        } else {
          Row({ space: this.f(this.coupletBodyPx() * 0.9) }) {
            ForEach(this.vertColsRtl(this.content.body, this.coupletPerCol(), this.coupletMaxCols()),
              (col: string[], i: number) => {
                Text(col.join('\n'))
                  .fontSize(this.f(this.coupletBodyPx()))
                  .lineHeight(this.f(this.coupletBodyPx() * 1.36))
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.pal().title)
                  .fontFamily(this.font())
                  .textAlign(TextAlign.Center)
                  .shadow({ radius: this.f(16), color: '#66000000', offsetY: this.f(3) })
              }, (col: string[], i: number) =>
              i.toString() + '-' + col.length.toString() + '-' + (col.length > 0 ? col[0] : ''))
          }
          .alignItems(VerticalAlign.Top)
        }
      }
      .width(this.previewWidth - this.f(212) * 2)
      .height(this.h() - this.fy(238) - this.fy(174))
      .alignItems(HorizontalAlign.Center)
      .position({ x: this.f(212), y: this.fy(238) })

      if (this.content.sign.trim() !== '') {
        Column() {
          Text(this.vertChars(this.content.sign).join('\n'))
            .fontSize(this.f(22))
            .lineHeight(this.f(29))
            .fontColor(this.hexA(this.pal().title, 'D9'))
            .fontFamily(this.font())
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.End)
        .padding({ right: this.f(100), bottom: this.f(148) })
      }

      Text('HAPPY NEW YEAR · POCKET BLESSING')
        .fontSize(this.f(19))
        .letterSpacing(this.f(10))
        .fontColor(this.hexA(this.pal().sub, '99'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .position({ x: 0, y: this.h() - this.f(93) })

      Column()
        .width('100%')
        .height('100%')
        .radialGradient({
          center: ['50%', '50%'],
          radius: '95%',
          colors: [['#00000000', 0.58], [this.hexA('#3C0204', '6B'), 1]],
        })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
  }
}
