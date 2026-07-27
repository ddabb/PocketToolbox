import { bundleManager } from '@kit.AbilityKit';
import { StickinessUtil, CheckInData, UserStats, ChallengeProgress } from '../common/utils/StickinessUtil';

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
  @State versionName: string = '';
  @State checkInData: CheckInData = new CheckInData();
  @State userStats: UserStats = new UserStats();
  @State challengeProgress: ChallengeProgress = new ChallengeProgress();
  private uiContext: UIContext = this.getUIContext();

  aboutToAppear(): void {
    this.loadAppInfo();
    this.loadUserStats();
  }

  private loadAppInfo(): void {
    try {
      let info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.versionName = info.versionName;
    } catch (e) {
      this.versionName = '';
    }
  }

  private loadUserStats(): void {
    let ctx: Context = this.uiContext.getHostContext() as Context;
    this.checkInData = StickinessUtil.loadCheckIn(ctx);
    this.userStats = StickinessUtil.loadStats(ctx);
    this.challengeProgress = StickinessUtil.loadChallengeProgress(ctx);
  }

  private getTodayChallengeText(): string {
    if (this.challengeProgress.completed && this.challengeProgress.date === StickinessUtil.todayStr()) {
      return '已完成 (' + this.challengeProgress.score.toString() + '分)';
    }
    return '未完成';
  }

  build() {
    Scroll() {
      Column() {
        Column() {
          Image($r('app.media.foreground'))
            .width(72)
            .height(72)
            .borderRadius(16)
            .margin({ bottom: 12 })
          Text('解语珠玑')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          if (this.versionName) {
            Text('v' + this.versionName)
              .fontSize(14)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ top: 4 })
          }
        }
        .width('100%')
        .padding({ top: 32, bottom: 20 })
        .alignItems(HorizontalAlign.Center)

        Column() {
          Row() {
            Text('今日签到')
              .fontSize(15)
              .fontColor($r('app.color.primary_text'))
              .layoutWeight(1)
            Text(this.checkInData.lastDate === StickinessUtil.todayStr() ? '\u2713 已签到' : '未签到')
              .fontSize(14)
              .fontColor(this.checkInData.lastDate === StickinessUtil.todayStr() ? '#27ae60' : $r('app.color.tertiary_text'))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })

          Divider().color($r('app.color.border_color')).margin({ left: 16 })

          Row() {
            Text('连续签到')
              .fontSize(15)
              .fontColor($r('app.color.primary_text'))
              .layoutWeight(1)
            Text(this.checkInData.streak.toString() + '天')
              .fontSize(14)
              .fontColor($r('app.color.idiom_orange'))
              .fontWeight(FontWeight.Bold)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })

          Divider().color($r('app.color.border_color')).margin({ left: 16 })

          Row() {
            Text('累计签到')
              .fontSize(15)
              .fontColor($r('app.color.primary_text'))
              .layoutWeight(1)
            Text(this.checkInData.totalDays.toString() + '天')
              .fontSize(14)
              .fontColor($r('app.color.tertiary_text'))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(14)
        .margin({ left: 16, right: 16, top: 8 })

        Column() {
          Row() {
            Text('今日挑战')
              .fontSize(15)
              .fontColor($r('app.color.primary_text'))
              .layoutWeight(1)
            Text(this.getTodayChallengeText())
              .fontSize(14)
              .fontColor(this.challengeProgress.completed && this.challengeProgress.date === StickinessUtil.todayStr() ? '#27ae60' : $r('app.color.tertiary_text'))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })

          Divider().color($r('app.color.border_color')).margin({ left: 16 })

          Row() {
            Text('累计挑战')
              .fontSize(15)
              .fontColor($r('app.color.primary_text'))
              .layoutWeight(1)
            Text(this.challengeProgress.totalChallenges.toString() + '次')
              .fontSize(14)
              .fontColor($r('app.color.tertiary_text'))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })

          Divider().color($r('app.color.border_color')).margin({ left: 16 })

          Row() {
            Text('累计浏览')
              .fontSize(15)
              .fontColor($r('app.color.primary_text'))
              .layoutWeight(1)
            Text(this.userStats.browseCount.toString() + '次')
              .fontSize(14)
              .fontColor($r('app.color.tertiary_text'))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })

          Divider().color($r('app.color.border_color')).margin({ left: 16 })

          Row() {
            Text('收藏内容')
              .fontSize(15)
              .fontColor($r('app.color.primary_text'))
              .layoutWeight(1)
            Text(this.userStats.favTotal.toString() + '项')
              .fontSize(14)
              .fontColor($r('app.color.tertiary_text'))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })

          Divider().color($r('app.color.border_color')).margin({ left: 16 })

          Row() {
            Text('朗读内容')
              .fontSize(15)
              .fontColor($r('app.color.primary_text'))
              .layoutWeight(1)
            Text(this.userStats.readingItems.toString() + '篇')
              .fontSize(14)
              .fontColor($r('app.color.tertiary_text'))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(14)
        .margin({ left: 16, right: 16, top: 8 })

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
