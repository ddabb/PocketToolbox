/**
 * PDF 工具选项 chip：选中蓝底白字，未选灰底。
 * 选中态经 @Prop 从父组件单向同步——不可改回页内 @Builder 按值传参
 * （boolean 传值在首次渲染固化，状态变化后选中态不刷新，1.4.9 修复）。
 */
@Component
export struct PdfModeChip {
  @Prop selected: boolean = false;
  text: ResourceStr = '';
  onAction: () => void = () => {
  };

  build() {
    Text(this.text)
      .fontSize(13)
      .fontColor(this.selected ? Color.White : $r('app.color.editor_chip_text'))
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .backgroundColor(this.selected ? $r('app.color.brand_blue') : $r('app.color.editor_chip_bg'))
      .borderRadius(14)
      .onClick(() => {
        this.onAction();
      })
  }
}
