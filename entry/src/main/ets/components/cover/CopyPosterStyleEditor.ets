/**
 * 文案海报样式面板（1.4.8 自 CopyPosterPage 抽离）：配色 + 字体 + 注音/水印开关 + 水印输入
 * 状态留在页面（paletteIndex/fontIndex/pinyinOn/watermark*），本组件纯展示 + 回调
 */

import { CoverPalette } from '../../model/CoverModels';
import { CoverFont } from '../../core/cover/CoverTemplates';
import { CopyPosterTemplates } from '../../core/cover/CopyPosterTemplates';
import { PaletteSection } from '../template/PaletteSection';

@Component
export struct CopyPosterStyleEditor {
  @Prop palettes: CoverPalette[] = [];
  @Prop fonts: string[] = [];
  @Prop supportsPinyin: boolean = false;
  @Prop paletteIndex: number = 0;
  @Prop fontIndex: number = 0;
  @Prop pinyinOn: boolean = false;
  @Prop watermarkOn: boolean = false;
  @Prop watermarkText: string = '';
  /** 1.5.1 B2：当前模板是否带可关纹理（仅 T11/T14/T15 渲染「纹理」开关） */
  @Prop hasTexture: boolean = false;
  @Prop textureOn: boolean = true;
  onPaletteSelect: (index: number) => void = () => {
  };
  onFontSelect: (index: number) => void = () => {
  };
  onPinyinToggle: () => void = () => {
  };
  onWatermarkToggle: () => void = () => {
  };
  onWatermarkTextChange: (value: string) => void = () => {
  };
  onTextureToggle: () => void = () => {
  };

  build() {
    Column({ space: 16 }) {
      PaletteSection({
        palettes: this.palettes,
        selectedIndex: this.paletteIndex,
        accentColor: $r('app.color.brand_blue'),
        labelColor: $r('app.color.editor_label_text'),
        onSelect: (idx: number) => {
          this.onPaletteSelect(idx);
        },
      })

      Column({ space: 10 }) {
        Text($r('app.string.cover_font_label'))
          .fontSize(12)
          .fontColor($r('app.color.editor_label_text'))
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.fonts, (f: string, idx: number) => {
            Text(CoverFont.label(f))
              .fontSize(13)
              .fontFamily(f)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .backgroundColor(this.fontIndex === idx ? $r('app.color.brand_blue') : $r('app.color.editor_chip_bg'))
              .fontColor(this.fontIndex === idx ? $r('app.color.on_accent_text') : $r('app.color.editor_chip_text'))
              .borderRadius(14)
              .margin(4)
              .onClick(() => {
                this.onFontSelect(idx);
              })
          }, (f: string, idx: number) => f + idx.toString())
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // 1.4.7 注音/水印压成一行开关，缩短样式面板纵深（自然宽度排列，注音缺失时水印靠左不悬空）
      Row({ space: 24 }) {
        if (this.supportsPinyin) {
          Column({ space: 6 }) {
            Text($r('app.string.poster_pinyin_label'))
              .fontSize(12)
              .fontColor($r('app.color.editor_label_text'))
            Text(this.pinyinOn ? $r('app.string.poster_pinyin_on') : $r('app.string.poster_pinyin_off'))
              .fontSize(13)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .backgroundColor(this.pinyinOn ? $r('app.color.brand_blue') : $r('app.color.editor_chip_bg'))
              .fontColor(this.pinyinOn ? $r('app.color.on_accent_text') : $r('app.color.editor_chip_text'))
              .borderRadius(14)
              .onClick(() => {
                this.onPinyinToggle();
              })
          }
          .alignItems(HorizontalAlign.Start)
        }
        Column({ space: 6 }) {
          Text($r('app.string.poster_watermark_label'))
            .fontSize(12)
            .fontColor($r('app.color.editor_label_text'))
          Text(this.watermarkOn ? $r('app.string.poster_watermark_on') : $r('app.string.poster_watermark_off'))
            .fontSize(13)
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .backgroundColor(this.watermarkOn ? $r('app.color.brand_blue') : $r('app.color.editor_chip_bg'))
            .fontColor(this.watermarkOn ? $r('app.color.on_accent_text') : $r('app.color.editor_chip_text'))
            .borderRadius(14)
            .onClick(() => {
              this.onWatermarkToggle();
            })
        }
        .alignItems(HorizontalAlign.Start)
        // 1.5.1 B2 纹理开关：仅带固定纹理/做旧装饰的模板渲染（T11/T14/T15）
        if (this.hasTexture) {
          Column({ space: 6 }) {
            Text($r('app.string.poster_texture_label'))
              .fontSize(12)
              .fontColor($r('app.color.editor_label_text'))
            Text(this.textureOn ? $r('app.string.poster_texture_on') : $r('app.string.poster_texture_off'))
              .fontSize(13)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .backgroundColor(this.textureOn ? $r('app.color.brand_blue') : $r('app.color.editor_chip_bg'))
              .fontColor(this.textureOn ? $r('app.color.on_accent_text') : $r('app.color.editor_chip_text'))
              .borderRadius(14)
              .onClick(() => {
                this.onTextureToggle();
              })
          }
          .alignItems(HorizontalAlign.Start)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (this.watermarkOn) {
        TextInput({ text: this.watermarkText, placeholder: $r('app.string.poster_watermark_hint') })
          .height(40)
          .fontSize(14)
          .maxLength(CopyPosterTemplates.MAX_WATERMARK)
          .backgroundColor($r('app.color.editor_input_bg'))
          .borderRadius(8)
          .onChange((value: string) => {
            this.onWatermarkTextChange(value);
          })
      }
    }
    .width('100%')
    .padding({ top: 12 })
  }
}
