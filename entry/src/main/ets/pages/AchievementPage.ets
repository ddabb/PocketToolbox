import { StickinessUtil, AchievementItem, UserStats, CheckInData } from '../common/utils/StickinessUtil';

@Builder
export function AchievementPageBuilder() {
  NavDestination() {
    AchievementContent()
  }
  .title('我的成就')
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct AchievementContent {
  @State achievements: AchievementItem[] = [];
  @State stats: UserStats = new UserStats();
  @State checkInData: CheckInData = new CheckInData();
  private uiContext: UIContext = this.getUIContext();

  aboutToAppear(): void {
    this.loadData();
  }

  private loadData(): void {
    let ctx: Context = this.uiContext.getHostContext() as Context;
    this.achievements = StickinessUtil.loadAchievements(ctx);
    this.stats = StickinessUtil.loadStats(ctx);
    this.checkInData = StickinessUtil.loadCheckIn(ctx);
  }

  private getUnlockedCount(): number {
    let count: number = 0;
    for (let i = 0; i < this.achievements.length; i++) {
      if (this.achievements[i].unlocked) {
        count++;
      }
    }
    return count;
  }

  build() {
    Scroll() {
      Column() {
        Row() {
          Column() {
            Text(this.getUnlockedCount().toString() + '/' + this.achievements.length.toString())
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.poetry_green'))
            Text('已解锁成就')
              .fontSize(12)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)

          Divider()
            .vertical(true)
            .height(40)
            .color($r('app.color.border_color'))

          Column() {
            Text(this.checkInData.streak.toString() + '天')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.idiom_orange'))
            Text('连续签到')
              .fontSize(12)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)

          Divider()
            .vertical(true)
            .height(40)
            .color($r('app.color.border_color'))

          Column() {
            Text(this.stats.browseCount.toString())
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.idiom_blue'))
            Text('累计浏览')
              .fontSize(12)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .padding({ top: 20, bottom: 20 })
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(14)
        .margin({ left: 16, right: 16, top: 12 })

        Text('成就列表')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .width('100%')
          .padding({ left: 16, top: 20, bottom: 8 })

        Column({ space: 8 }) {
          ForEach(this.achievements, (item: AchievementItem) => {
            Row() {
              Column() {
                Text(item.icon)
                  .fontSize(24)
              }
              .width(48)
              .height(48)
              .borderRadius(24)
              .backgroundColor(item.unlocked ? item.color + '18' : $r('app.color.border_color') + '')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .margin({ right: 12 })

              Column() {
                Text(item.title)
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(item.unlocked ? $r('app.color.primary_text') : $r('app.color.tertiary_text'))
                Text(item.desc)
                  .fontSize(12)
                  .fontColor($r('app.color.tertiary_text'))
                  .margin({ top: 2 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              if (item.unlocked) {
                Text('\u2713')
                  .fontSize(16)
                  .fontColor('#ffffff')
                  .width(28)
                  .height(28)
                  .borderRadius(14)
                  .backgroundColor('#27ae60')
                  .textAlign(TextAlign.Center)
              } else {
                Column() {
                  Text(item.current.toString() + '/' + item.target.toString())
                    .fontSize(11)
                    .fontColor($r('app.color.tertiary_text'))
                  Progress({ value: item.current, total: item.target, type: ProgressType.Linear })
                    .width(60)
                    .height(4)
                    .color($r('app.color.poetry_green'))
                    .backgroundColor($r('app.color.border_color'))
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.End)
                .width(70)
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)
            .margin({ left: 16, right: 16 })
            .opacity(item.unlocked ? 1.0 : 0.7)
          }, (item: AchievementItem) => item.id)
        }
        .width('100%')
        .padding({ bottom: 24 })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }
}
