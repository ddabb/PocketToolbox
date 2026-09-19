let storage = new LocalStorage();

@Entry(storage)
@Component
struct DailyPoemWidgetCard {
  @LocalStorageProp('title') title: string = '每日一诗';
  @LocalStorageProp('author') author: string = '';
  @LocalStorageProp('lines') lines: string = '';
  @LocalStorageProp('date') date: string = '';
  @LocalStorageProp('poemJson') poemJson: string = '';

  build() {
    Column() {
      Row() {
        Text('解语珠玑 · 每日一诗')
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.poetry_green'))
          .maxLines(1)
        Text(this.date)
          .fontSize(10)
          .fontColor($r('app.color.tertiary_text'))
          .maxLines(1)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Column() {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.author) {
          Text(this.author)
            .fontSize(11)
            .fontColor($r('app.color.secondary_text'))
            .maxLines(1)
            .margin({ top: 2 })
        }
        Text(this.lines)
          .fontSize(13)
          .fontColor($r('app.color.primary_text'))
          .lineHeight(21)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 8 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor($r('app.color.page_background'))
    .borderRadius(16)
    .onClick(() => {
      postCardAction(this, {
        'action': 'router',
        'abilityName': 'EntryAbility',
        'params': {
          'openPoem': this.poemJson
        }
      });
    })
  }
}
