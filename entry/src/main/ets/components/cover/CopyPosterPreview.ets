/**
 * 文案海报预览渲染组件：设计稿 900 宽（1:1 -> 900 高 / 3:4 -> 1200 高），4 种布局
 * 尺寸换算：f(px) = previewWidth * px / 900；主文案按长度分档自动缩字号（emoji 走系统字体兜底）
 */
import { CopyPosterContent, CopyPosterRatio, CopyPosterTemplate } from '../../model/CopyPosterModels';
import { CoverPalette } from '../../model/CoverModels';

@Component
export struct CopyPosterPreview {
  @Prop template: CopyPosterTemplate;
  @Prop content: CopyPosterContent;
  @Prop paletteIndex: number;
  @Prop fontIndex: number;
  @Prop ratioKind: string;
  @Prop previewWidth: number;

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
}
