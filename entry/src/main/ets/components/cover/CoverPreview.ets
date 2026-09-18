/**
 * 公众号首图预览渲染组件：900x383 设计稿比例，15 种布局
 * 尺寸换算：f(px) = previewWidth * px / 900
 */
import { CoverContent, CoverPalette, CoverTemplate } from '../../model/CoverModels';
import { CoverContentUtil } from '../../core/cover/CoverContentUtil';

@Component
export struct CoverPreview {
  @Prop template: CoverTemplate;
  @Prop content: CoverContent;
  @Prop paletteIndex: number;
  @Prop fontIndex: number;
  @Prop previewWidth: number;

  /** 设计稿 px -> vp */
  private f(px: number): number {
    return this.previewWidth * px / 900;
  }

  private h(): number {
    return this.previewWidth * 383 / 900;
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

  /** 标题字号 3 档自动缩放 */
  private fitFont(text: string, basePx: number): number {
    let len: number = text.length;
    if (len <= 8) {
      return this.f(basePx);
    }
    if (len <= 12) {
      return this.f(basePx * 0.8);
    }
    return this.f(basePx * 0.62);
  }

  private charsOf(s: string): string[] {
    return s.split('');
  }

  private cleanChars(): string[] {
    let clean: string = this.content.title.replace(new RegExp('\\s', 'g'), '');
    return clean.split('').slice(0, 8);
  }

  private gridSize(n: number): number {
    let gap: number = this.f(20);
    let avail: number = this.previewWidth * 0.86;
    return Math.min(this.f(130), (avail - (n - 1) * gap) / n);
  }

  private lineW(): number {
    return Math.max(0.4, this.f(1));
  }

  private outerW(): number {
    return Math.max(1, this.f(3));
  }

  build() {
    Stack() {
      this.BgLayer()
      if (this.template.layout === 'a1_center') {
        this.A1()
      } else if (this.template.layout === 'a2_gradient_left') {
        this.A2()
      } else if (this.template.layout === 'a3_neon') {
        this.A3()
      } else if (this.template.layout === 'b1_poem_vertical') {
        this.B1()
      } else if (this.template.layout === 'b2_idiom') {
        this.B2()
      } else if (this.template.layout === 'b3_xiehouyu') {
        this.B3()
      } else if (this.template.layout === 'b4_solar') {
        this.B4()
      } else if (this.template.layout === 'b5_grid') {
        this.B5()
      } else if (this.template.layout === 'c1_poster') {
        this.C1()
      } else if (this.template.layout === 'c2_number') {
        this.C2()
      } else if (this.template.layout === 'c3_question') {
        this.C3()
      } else if (this.template.layout === 'd1_geoblock') {
        this.D1()
      } else if (this.template.layout === 'd2_twocolumn') {
        this.D2()
      } else if (this.template.layout === 'd3_seal') {
        this.D3()
      } else if (this.template.layout === 'e2_texture') {
        this.E2()
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

  /** 纵排文字（一字一行） */
  @Builder
  VText(text: string, fontSize: number, color: string, spacing: number) {
    Column({ space: spacing }) {
      ForEach(this.charsOf(text), (ch: string) => {
        Text(ch).fontSize(fontSize).fontColor(color).fontFamily(this.font())
      }, (ch: string, idx: number) => ch + idx.toString())
    }
  }

  /** 红色小印章（1-2 字） */
  @Builder
  SealBox(size: number, text: string) {
    Text(text)
      .fontSize(size * 0.62)
      .fontColor('#FFFFFF')
      .textAlign(TextAlign.Center)
      .backgroundColor(this.pal().grid)
      .borderRadius(size * 0.12)
      .width(size)
      .height(size)
  }

  /** 方形 2x2 印章（2-4 字） */
  @Builder
  SealGrid() {
    Column({ space: this.f(1.5) }) {
      ForEach(this.sealRows(), (row: string[]) => {
        Row({ space: this.f(1.5) }) {
          ForEach(row, (ch: string) => {
            Text(ch).fontSize(this.f(16)).fontColor('#FFFFFF').fontFamily(this.font())
          }, (ch: string, ci: number) => ch + ci.toString())
        }
      }, (row: string[], ri: number) => 'r' + ri.toString())
    }
    .padding(this.f(5))
    .backgroundColor(this.pal().grid)
    .borderRadius(this.f(4))
  }

  private sealRows(): string[][] {
    let chars: string[] = this.charsOf(this.content.seal.replace(new RegExp('\\s', 'g'), '')).slice(0, 4);
    let rows: string[][] = [];
    if (chars.length > 0) {
      let first: string[] = [];
      let second: string[] = [];
      for (let i = 0; i < chars.length; i++) {
        if (i < 2) {
          first.push(chars[i]);
        } else {
          second.push(chars[i]);
        }
      }
      rows.push(first);
      if (second.length > 0) {
        rows.push(second);
      }
    }
    return rows;
  }

  // ---------- A 系列 · 简约文字 ----------

  @Builder
  A1() {
    Column({ space: this.f(10) }) {
      Text(this.content.title)
        .fontSize(this.fitFont(this.content.title, 64))
        .fontColor(this.pal().title)
        .fontFamily(this.font())
        .fontWeight(FontWeight.Bold)
        .maxLines(2)
        .textAlign(TextAlign.Center)
      if (this.content.subtitle !== '') {
        Text(this.content.subtitle)
          .fontSize(this.f(20))
          .fontColor(this.pal().sub)
          .fontFamily(this.font())
          .maxLines(1)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: this.f(48), right: this.f(48) })
  }

  @Builder
  A2() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column({ space: this.f(8) }) {
        Row()
          .width(this.f(48))
          .height(this.f(5))
          .backgroundColor(this.pal().accent)
          .borderRadius(this.f(2))
        Text(this.content.title)
          .fontSize(this.fitFont(this.content.title, 52))
          .fontColor(this.pal().title)
          .fontFamily(this.font())
          .fontWeight(FontWeight.Bold)
          .maxLines(2)
          .textAlign(TextAlign.Start)
        if (this.content.subtitle !== '') {
          Text(this.content.subtitle)
            .fontSize(this.f(19))
            .fontColor(this.pal().sub)
            .fontFamily(this.font())
            .maxLines(1)
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: this.f(56), right: this.f(56) })

      if (this.content.author !== '') {
        Text(this.content.author)
          .fontSize(this.f(13))
          .fontColor(this.pal().sub)
          .padding({ right: this.f(28), bottom: this.f(20) })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  A3() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column({ space: this.f(8) }) {
        Row({ space: this.f(6) }) {
          Row().width(this.f(6)).height(this.f(6)).borderRadius(this.f(3)).backgroundColor(this.pal().accent)
          Row().width(this.f(36)).height(this.f(2)).backgroundColor(this.pal().accent)
        }
        if (this.content.subtitle !== '') {
          Text(this.content.subtitle)
            .fontSize(this.f(14))
            .fontColor(this.pal().sub)
            .letterSpacing(this.f(2))
            .maxLines(1)
        }
        Text(this.content.title)
          .fontSize(this.fitFont(this.content.title, 54))
          .fontColor(this.pal().title)
          .fontFamily(this.font())
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textAlign(TextAlign.Center)
        Row().width(this.f(120)).height(this.f(2)).backgroundColor(this.pal().accent)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      if (this.content.author !== '') {
        Text(this.content.author)
          .fontSize(this.f(14))
          .fontColor(this.pal().sub)
          .padding({ bottom: this.f(24) })
      }
    }
    .width('100%')
    .height('100%')
  }

  // ---------- B 系列 · 文化内容 ----------

  @Builder
  B1() {
    Row({ space: this.f(20) }) {
      Column() {
        Blank()
        if (this.content.seal !== '') {
          Row({ space: this.f(8) }) {
            this.SealBox(this.f(26), this.content.seal.substring(0, 2))
            Column({ space: this.f(2) }) {
              Text(this.content.quoteSource).fontSize(this.f(13)).fontColor(this.pal().sub).maxLines(1)
              if (this.content.author !== '') {
                Text(this.content.author).fontSize(this.f(12)).fontColor(this.pal().sub).maxLines(1)
              }
            }
            .alignItems(HorizontalAlign.Start)
          }
          .alignItems(VerticalAlign.Bottom)
        } else if (this.content.quoteSource !== '') {
          Text(this.content.quoteSource).fontSize(this.f(13)).fontColor(this.pal().sub).maxLines(1)
        }
      }
      .height('100%')
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.content.quote !== '') {
        this.VText(this.content.quote, this.quoteFontSize(), this.pal().title, this.f(4))
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: this.f(44), right: this.f(44), top: this.f(24), bottom: this.f(24) })
  }

  private quoteFontSize(): number {
    let len: number = this.charsOf(this.content.quote).length;
    if (len === 0) {
      return this.f(30);
    }
    return Math.min(this.f(30), (this.h() * 0.84 - len * this.f(2)) / len);
  }

  @Builder
  B2() {
    Column({ space: this.f(10) }) {
      Row({ space: this.f(6) }) {
        Row().width(this.f(20)).height(this.f(2)).backgroundColor(this.pal().accent)
        Row().width(this.f(6)).height(this.f(6)).borderRadius(this.f(3)).backgroundColor(this.pal().accent)
        Row().width(this.f(20)).height(this.f(2)).backgroundColor(this.pal().accent)
      }
      Text(this.content.quote)
        .fontSize(this.fitFont(this.content.quote, 52))
        .fontColor(this.pal().title)
        .fontFamily(this.font())
        .fontWeight(FontWeight.Bold)
        .maxLines(1)
      if (this.content.subtitle !== '') {
        Text(this.content.subtitle)
          .fontSize(this.f(14))
          .fontColor(this.pal().sub)
          .maxLines(2)
          .textAlign(TextAlign.Center)
      }
      if (this.content.quoteSource !== '') {
        Text(this.content.quoteSource)
          .fontSize(this.f(11))
          .fontColor(this.pal().sub)
          .opacity(0.8)
          .maxLines(1)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: this.f(60), right: this.f(60) })
  }

  @Builder
  B3() {
    Column({ space: this.f(12) }) {
      Text(this.content.quote)
        .fontSize(this.fitFont(this.content.quote, 38))
        .fontColor(this.pal().title)
        .fontFamily(this.font())
        .fontWeight(FontWeight.Bold)
        .maxLines(1)
      if (this.content.subtitle !== '') {
        Row({ space: this.f(8) }) {
          Row().width(this.f(24)).height(this.f(2)).backgroundColor(this.pal().accent)
          Text('—— ' + this.content.subtitle)
            .fontSize(this.f(26))
            .fontColor(this.pal().accent)
            .fontFamily(this.font())
            .fontWeight(FontWeight.Bold)
            .maxLines(1)
          Row().width(this.f(24)).height(this.f(2)).backgroundColor(this.pal().accent)
        }
        .alignItems(VerticalAlign.Center)
      }
      if (this.content.author !== '') {
        Text(this.content.author).fontSize(this.f(12)).fontColor(this.pal().sub)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: this.f(52), right: this.f(52) })
  }

  @Builder
  B4() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column({ space: this.f(8) }) {
        Text(this.content.title)
          .fontSize(this.fitFont(this.content.title, 72))
          .fontColor(this.pal().title)
          .fontFamily(this.font())
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
        if (this.content.quote !== '') {
          Text(this.content.quote)
            .fontSize(this.f(20))
            .fontColor(this.pal().sub)
            .fontFamily(this.font())
            .maxLines(2)
        }
        if (this.content.quoteSource !== '') {
          Text(this.content.quoteSource).fontSize(this.f(12)).fontColor(this.pal().sub).maxLines(1)
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: this.f(56), right: this.f(140) })

      if (this.content.issue !== '') {
        Text(this.content.issue)
          .fontSize(this.f(13))
          .fontColor('#FFFFFF')
          .padding({ left: this.f(10), right: this.f(10), top: this.f(5), bottom: this.f(5) })
          .backgroundColor(this.pal().grid)
          .borderRadius(this.f(4))
          .margin({ right: this.f(36), bottom: this.f(32) })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  B5() {
    Column({ space: this.f(26) }) {
      if (this.content.pinyin !== '') {
        if (this.b5Syllables().length === this.cleanChars().length) {
          this.B5PinyinSlots()
        } else {
          Text(this.content.pinyin)
            .fontSize(this.f(20))
            .fontColor(this.pal().title)
            .fontFamily(this.font())
            .maxLines(1)
        }
      }
      Row({ space: this.f(20) }) {
        ForEach(this.cleanChars(), (ch: string) => {
          this.GridCell(this.gridSize(this.cleanChars().length), ch)
        }, (ch: string, idx: number) => ch + idx.toString())
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  private b5Syllables(): string[] {
    return CoverContentUtil.syllables(this.content.pinyin);
  }

  /** 逐格拼音槽：槽宽=格边长、槽距=格间距，与格子行几何一致实现一一对应 */
  @Builder
  B5PinyinSlots() {
    Row({ space: this.f(20) }) {
      ForEach(this.b5Syllables(), (sy: string, idx: number) => {
        Text(sy)
          .width(this.gridSize(this.cleanChars().length))
          .fontSize(this.f(20))
          .minFontSize(this.f(12))
          .maxFontSize(this.f(20))
          .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
          .fontColor(this.pal().title)
          .fontFamily(this.font())
          .maxLines(1)
          .textAlign(TextAlign.Center)
      }, (sy: string, idx: number) => sy + idx.toString())
    }
    .alignItems(VerticalAlign.Center)
  }

  /** 田字格单元格：外框实线 + 十字虚线 + 居中汉字 */
  @Builder
  GridCell(size: number, ch: string) {
    Stack({ alignContent: Alignment.Center }) {
      Text(ch)
        .fontSize(size * 0.7)
        .fontColor(this.pal().title)
        .fontFamily(this.font())
      Row()
        .width('100%')
        .height(this.lineW())
        .border({ width: { top: this.lineW() }, color: this.pal().grid, style: BorderStyle.Dashed })
      Column()
        .height('100%')
        .width(this.lineW())
        .border({ width: { left: this.lineW() }, color: this.pal().grid, style: BorderStyle.Dashed })
    }
    .width(size)
    .height(size)
    .border({ width: this.outerW(), color: this.pal().grid })
  }

  // ---------- C 系列 · 大字冲击 ----------

  @Builder
  C1() {
    Column() {
      Text(this.content.title)
        .fontSize(this.fitFont(this.content.title, 84))
        .fontColor(this.pal().title)
        .fontFamily(this.font())
        .fontWeight(FontWeight.Bold)
        .maxLines(1)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: this.f(40), right: this.f(40) })
  }

  @Builder
  C2() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Column() {
        Text(this.content.issue)
          .fontSize(this.f(110))
          .fontColor(this.pal().accent)
          .fontFamily(this.font())
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .margin({ top: this.f(-14) })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column({ space: this.f(4) }) {
        Row().width(this.f(30)).height(this.f(2)).backgroundColor(this.pal().accent)
        Text(this.content.title)
          .fontSize(this.f(22))
          .fontColor(this.pal().title)
          .fontFamily(this.font())
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
        if (this.content.author !== '') {
          Text(this.content.author).fontSize(this.f(12)).fontColor(this.pal().sub)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: this.f(44), bottom: this.f(28) })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  C3() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column({ space: this.f(10) }) {
        Text() {
          Span(this.content.title)
            .fontSize(this.fitFont(this.content.title, 44))
            .fontColor(this.pal().title)
            .fontFamily(this.font())
          Span('？')
            .fontSize(this.f(48))
            .fontColor(this.pal().accent)
            .fontFamily(this.font())
        }
        .maxLines(2)
        .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding({ left: this.f(56), right: this.f(56), bottom: this.f(30) })

      Row({ space: this.f(10) }) {
        if (this.content.author !== '') {
          Text(this.content.author).fontSize(this.f(13)).fontColor(this.pal().sub)
        }
        Row().width(this.f(60)).height(this.f(1.5)).backgroundColor(this.pal().accent)
      }
      .alignItems(VerticalAlign.Center)
      .padding({ bottom: this.f(22) })
    }
    .width('100%')
    .height('100%')
  }

  // ---------- D 系列 · 杂志设计 ----------

  @Builder
  D1() {
    Stack() {
      Stack({ alignContent: Alignment.TopStart }) {
        Circle({ width: this.f(56), height: this.f(56) })
          .fill(this.pal().block)
          .opacity(0.6)
          .margin({ left: this.f(-14), top: this.f(-14) })
      }
      .width('100%')
      .height('100%')

      Stack({ alignContent: Alignment.TopEnd }) {
        if (this.content.author !== '') {
          Text(this.content.author)
            .fontSize(this.f(13))
            .fontColor(this.pal().sub)
            .padding({ right: this.f(24), top: this.f(20) })
        }
      }
      .width('100%')
      .height('100%')

      Stack({ alignContent: Alignment.Bottom }) {
        Column()
          .width('100%')
          .height('33%')
          .backgroundColor(this.pal().block)
        Column({ space: this.f(6) }) {
          Row({ space: this.f(8) }) {
            Row().width(this.f(10)).height(this.f(10)).backgroundColor(this.pal().accent)
            if (this.content.subtitle !== '') {
              Text(this.content.subtitle)
                .fontSize(this.f(14))
                .fontColor(this.pal().sub)
                .maxLines(1)
            }
          }
          .alignItems(VerticalAlign.Center)
          Text(this.content.title)
            .fontSize(this.fitFont(this.content.title, 34))
            .fontColor(this.pal().title)
            .fontFamily(this.font())
            .fontWeight(FontWeight.Bold)
            .maxLines(1)
        }
        .width('100%')
        .height('33%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)
        .padding({ left: this.f(40), right: this.f(40) })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  D2() {
    Row() {
      Column({ space: this.f(6) }) {
        if (this.content.author !== '') {
          this.VText(this.content.author, this.f(18), this.pal().sub, this.f(2))
        }
        Blank()
        if (this.content.issue !== '') {
          Text(this.content.issue).fontSize(this.f(13)).fontColor(this.pal().sub).maxLines(1)
        }
      }
      .width('32%')
      .height('100%')
      .backgroundColor(this.pal().block)
      .padding({ left: this.f(20), right: this.f(8), top: this.f(24), bottom: this.f(24) })
      .alignItems(HorizontalAlign.Start)

      Column({ space: this.f(8) }) {
        Text(this.content.title)
          .fontSize(this.fitFont(this.content.title, 34))
          .fontColor(this.pal().title)
          .fontFamily(this.font())
          .fontWeight(FontWeight.Bold)
          .maxLines(2)
        if (this.content.subtitle !== '') {
          Text(this.content.subtitle)
            .fontSize(this.f(14))
            .fontColor(this.pal().sub)
            .maxLines(2)
        }
        Row().width(this.f(44)).height(this.f(3)).backgroundColor(this.pal().accent)
      }
      .layoutWeight(1)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: this.f(28), right: this.f(36) })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  D3() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column({ space: this.f(6) }) {
        Text(this.content.title)
          .fontSize(this.fitFont(this.content.title, 36))
          .fontColor(this.pal().title)
          .fontFamily(this.font())
          .fontWeight(FontWeight.Bold)
          .maxLines(2)
        if (this.content.subtitle !== '') {
          Text(this.content.subtitle)
            .fontSize(this.f(14))
            .fontColor(this.pal().sub)
            .maxLines(1)
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: this.f(44), top: this.f(44) })

      Column({ space: this.f(8) }) {
        if (this.content.author !== '') {
          Text(this.content.author).fontSize(this.f(12)).fontColor(this.pal().sub)
        }
        if (this.content.seal !== '') {
          this.SealGrid()
        }
      }
      .alignItems(HorizontalAlign.End)
      .padding({ right: this.f(36), bottom: this.f(30) })
    }
    .width('100%')
    .height('100%')
  }

  // ---------- E 系列 · 图片背景 ----------

  @Builder
  E2() {
    Stack() {
      Circle({ width: this.f(220), height: this.f(220) })
        .fill(this.pal().bg2)
        .opacity(0.85)
        .position({ x: -this.f(60), y: -this.f(90) })
      Circle({ width: this.f(140), height: this.f(140) })
        .fill(this.pal().accent)
        .opacity(0.12)
        .position({ x: this.previewWidth - this.f(70), y: this.h() - this.f(80) })
      Column({ space: this.f(8) }) {
        Text(this.content.title)
          .fontSize(this.fitFont(this.content.title, 44))
          .fontColor(this.pal().title)
          .fontFamily(this.font())
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
        if (this.content.author !== '') {
          Text(this.content.author).fontSize(this.f(13)).fontColor(this.pal().sub)
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
  }
}
