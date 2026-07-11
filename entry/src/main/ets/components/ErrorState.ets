@Component
export struct ErrorState {
  @Prop text: string = '加载失败';
  @Prop subText: string = '';
  @Prop showButton: boolean = true;
  @Prop buttonText: string = '重试';
  onRetry: () => void = () => {};

  build() {
    Column() {
      Text('!')
        .fontSize(36)
        .fontColor($r('app.color.error_red'))
        .fontWeight(FontWeight.Bold)
        .width(64)
        .height(64)
        .borderRadius(32)
        .backgroundColor($r('app.color.error_red') + '18')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 16 })

      Text(this.text)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .margin({ bottom: 4 })

      if (this.subText) {
        Text(this.subText)
          .fontSize(14)
          .fontColor($r('app.color.tertiary_text'))
          .lineHeight(22)
          .margin({ bottom: 16 })
      }

      if (this.showButton) {
        Button(this.buttonText)
        .fontSize(14)
        .fontColor('#ffffff')
        .backgroundColor($r('app.color.error_red'))
          .borderRadius(8)
          .width(140)
          .height(44)
          .onClick(() => {
            this.onRetry();
          })
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 40, right: 40, top: 40, bottom: 40 })
  }
}
