@Builder
export function AboutPageBuilder() {
  NavDestination() {
    AboutContent()
  }
  .title('关于')
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct AboutContent {
  private uiContext: UIContext = this.getUIContext();

  build() {
    Scroll() {
      Column() {
        Column() {
          Text('\uD83D\uDCDC')
            .fontSize(56)
            .margin({ bottom: 12 })
          Text('解语珠玑')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          Text('v1.0.0')
            .fontSize(14)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 4 })
        }
        .width('100%')
        .padding({ top: 40, bottom: 24 })
        .alignItems(HorizontalAlign.Center)

        Column() {
          Row() {
            Text('应用名称')
              .fontSize(15)
              .fontColor($r('app.color.primary_text'))
              .layoutWeight(1)
            Text('解语珠玑')
              .fontSize(14)
              .fontColor($r('app.color.tertiary_text'))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })

          Divider()
            .color($r('app.color.border_color'))
            .margin({ left: 16 })

          Row() {
            Text('版本号')
              .fontSize(15)
              .fontColor($r('app.color.primary_text'))
              .layoutWeight(1)
            Text('1.0.0')
              .fontSize(14)
              .fontColor($r('app.color.tertiary_text'))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })

          Divider()
            .color($r('app.color.border_color'))
            .margin({ left: 16 })

          Row() {
            Text('包名')
              .fontSize(15)
              .fontColor($r('app.color.primary_text'))
              .layoutWeight(1)
            Text('com.ddabb.toolbox')
              .fontSize(13)
              .fontColor($r('app.color.tertiary_text'))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(14)
        .margin({ left: 16, right: 16, top: 12 })

        Column() {
          Text('解语珠玑 —— 品读经典，感悟文字之美')
            .fontSize(13)
            .fontColor($r('app.color.tertiary_text'))
            .textAlign(TextAlign.Center)
            .lineHeight(22)
          Text('包含诗词查询、成语接龙、歇后语猜谜等功能，助您领略中华文字的魅力。')
            .fontSize(13)
            .fontColor($r('app.color.hint_text'))
            .textAlign(TextAlign.Center)
            .lineHeight(22)
            .margin({ top: 8 })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 20, bottom: 20 })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
    }
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
