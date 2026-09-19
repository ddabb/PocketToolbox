/**
 * 模板体系统一 - 共享配色选择组件
 * 设计文档：docs/模板体系统一设计文档.md §4.1
 * 统一生字卡/首图页重复的配色选择块：38vp 圆底 + 14vp 圆点 + 44vp 选中描边
 * 状态留在页面，本组件纯展示 + onSelect 回调
 */

import { CoverPalette } from '../../model/CoverModels';

@Component
export struct PaletteSection {
  @Prop palettes: CoverPalette[] = [];
  @Prop selectedIndex: number = 0;
  /** 选中描边色（生字卡 #D8231A / 首图 #2E6FD6） */
  @Prop accentColor: string = '#D8231A';
  @Prop labelColor: string = '#666666';
  @Prop title: string = '配色方案';
  onSelect: (index: number) => void = () => {
  };

  build() {
    Column({ space: 10 }) {
      Text(this.title)
        .fontSize(12)
        .fontColor(this.labelColor)
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.palettes, (p: CoverPalette, idx: number) => {
          Stack() {
            Column()
              .width(38)
              .height(38)
              .borderRadius(19)
              .backgroundColor(p.bg)
            Column()
              .width(14)
              .height(14)
              .borderRadius(7)
              .backgroundColor(p.accent)
            Column()
              .width(44)
              .height(44)
              .borderRadius(22)
              .border({
                width: this.selectedIndex === idx ? 2 : 0,
                color: this.accentColor,
              })
          }
          .width(44)
          .height(44)
          .margin(6)
          .onClick(() => {
            this.onSelect(idx);
          })
        }, (p: CoverPalette, idx: number) => p.name + idx.toString())
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
