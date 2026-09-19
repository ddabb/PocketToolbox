/**
 * 模板体系统一 - 共享选项 chips 组件
 * 设计文档：docs/模板体系统一设计文档.md §4.2
 * 统一"标签 + 可选 chips"行（尺寸/格型/字色/拼音等），选中态 accent 底白字
 * 根为不带固定宽度的 Row：可单独使用，也可与 Blank() 并排组成双组行
 */

import { ChipOption } from '../../core/template/UnifiedTemplateModels';

@Component
export struct ChipRow {
  @Prop label: string = '';
  @Prop labelColor: string = '#666666';
  /** 标签固定宽度（0 = 自适应），用于多行标签对齐 */
  @Prop labelWidth: number = 0;
  @Prop options: ChipOption[] = [];
  @Prop selected: string = '';
  @Prop accent: string = '#D8231A';
  @Prop chipBg: string = '#F2F2F2';
  @Prop chipText: string = '#333333';
  onSelect: (value: string) => void = () => {
  };

  build() {
    Row({ space: 8 }) {
      Text(this.label)
        .fontSize(12)
        .fontColor(this.labelColor)
        .width(this.labelWidth > 0 ? this.labelWidth : 'auto')
      ForEach(this.options, (opt: ChipOption) => {
        Text(opt.label)
          .fontSize(13)
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .backgroundColor(this.selected === opt.value ? this.accent : this.chipBg)
          .fontColor(this.selected === opt.value ? '#FFFFFF' : this.chipText)
          .borderRadius(14)
          .onClick(() => {
            this.onSelect(opt.value);
          })
      }, (opt: ChipOption) => opt.value)
    }
    .alignItems(VerticalAlign.Center)
  }
}
