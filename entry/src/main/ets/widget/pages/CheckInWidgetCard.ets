let checkInCardStorage = new LocalStorage();

@Entry(checkInCardStorage)
@Component
struct CheckInWidgetCard {
  @LocalStorageProp('title') title: string = '';
  @LocalStorageProp('checkedIn') checkedIn: string = '0';
  @LocalStorageProp('status') status: string = '';
  @LocalStorageProp('streak') streak: string = '0';
  @LocalStorageProp('streakText') streakText: string = '';
  @LocalStorageProp('hint') hint: string = '';
  @LocalStorageProp('dimension') dimension: string = '';

  build() {
    Column() {
      Row() {
        Text('\uD83D\uDCC5')
          .fontSize(13)
          .margin({ right: 4 })
        Text(this.title)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.status)
          .fontSize(10)
          .fontColor(this.checkedIn === '1' ? $r('app.color.success_green') : $r('app.color.idiom_orange'))
          .maxLines(1)
      }
      .width('100%')

      Column() {
        if (this.streak !== '0') {
          Text(this.streak)
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          Text($r('app.string.days_unit', parseInt(this.streak)))
            .fontSize(11)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 2 })
        } else {
          Text(this.streakText)
            .fontSize(14)
            .fontColor($r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)

      Text(this.hint)
        .fontSize(10)
        .fontColor($r('app.color.tertiary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor($r('app.color.page_background'))
    .borderRadius(16)
    .onClick(() => {
      postCardAction(this, {
        'action': 'router',
        'abilityName': 'EntryAbility',
        'params': {
          'openCheckIn': '1'
        }
      });
    })
  }
}
