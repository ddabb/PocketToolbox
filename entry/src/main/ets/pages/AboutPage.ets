import { bundleManager, common } from '@kit.AbilityKit';
import { GifHistoryStore, formatGifBytes } from '../core/gif/GifHistoryStore';
import { CheckInReminderUtil } from '../common/utils/CheckInReminderUtil';

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
  @State gifHistoryCount: number = 0;
  @State gifHistoryBytes: number = 0;
  @State reminderOn: boolean = false;
  private uiContext: UIContext = this.getUIContext();

  aboutToAppear(): void {
    this.loadAppInfo();
    this.loadGifHistory();
    this.loadReminderState();
  }

  private loadReminderState(): void {
    let ctx: Context = this.uiContext.getHostContext() as Context;
    this.reminderOn = CheckInReminderUtil.isOn(ctx);
  }

  private onReminderToggle(on: boolean): void {
    if (on) {
      let ctx: common.UIAbilityContext = this.uiContext.getHostContext() as common.UIAbilityContext;
      CheckInReminderUtil.enable(ctx).then((ok: boolean) => {
        if (ok) {
          this.reminderOn = true;
        } else {
          this.reminderOn = false;
        }
      });
    } else {
      let ctx: Context = this.uiContext.getHostContext() as Context;
      this.reminderOn = false;
      CheckInReminderUtil.disable(ctx);
    }
  }

  private loadGifHistory(): void {
    let ctx: Context = this.uiContext.getHostContext() as Context;
    this.gifHistoryCount = GifHistoryStore.recordCount(ctx);
    this.gifHistoryBytes = GifHistoryStore.totalBytes(ctx);
  }

  private clearGifHistory(): void {
    if (this.gifHistoryCount === 0) {
      return;
    }
    let dialogParam: AlertDialogParamWithButtons = {
      title: '清空 GIF 制作历史',
      message: `将删除全部 ${this.gifHistoryCount} 条 GIF 制作记录（约 ${formatGifBytes(this.gifHistoryBytes)}），已保存到相册的副本不受影响。确定清空？`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清空',
        action: () => {
          let ctx: Context = this.uiContext.getHostContext() as Context;
          GifHistoryStore.clearAll(ctx);
          this.loadGifHistory();
        }
      }
    };
    this.uiContext.showAlertDialog(dialogParam);
  }

  private loadAppInfo(): void {
    try {
      let info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.versionName = info.versionName;
    } catch (e) {
      this.versionName = '';
    }
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
          Text('品读经典，感悟文字之美')
            .fontSize(13)
            .fontColor($r('app.color.hint_text'))
            .margin({ top: 10 })
        }
        .width('100%')
        .padding({ top: 32, bottom: 24 })
        .alignItems(HorizontalAlign.Center)

        Column() {
          Row() {
            Column() {
              Text('每日签到提醒')
                .fontSize(15)
                .fontColor($r('app.color.primary_text'))
              Text('开启后每天 20:00 系统提醒签到与每日挑战')
                .fontSize(12)
                .fontColor($r('app.color.hint_text'))
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.reminderOn })
              .onChange((isOn: boolean) => {
                this.onReminderToggle(isOn);
              })
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
            Text('GIF 制作历史')
              .fontSize(15)
              .fontColor($r('app.color.primary_text'))
              .layoutWeight(1)
            Text(this.gifHistoryCount.toString() + ' 条 · ' + formatGifBytes(this.gifHistoryBytes))
              .fontSize(14)
              .fontColor($r('app.color.tertiary_text'))
            if (this.gifHistoryCount > 0) {
              Text('清空')
                .fontSize(13)
                .fontColor($r('app.color.danger_red'))
                .padding({ left: 10, right: 0 })
                .onClick(() => {
                  this.clearGifHistory();
                })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(14)
        .margin({ left: 16, right: 16, top: 8 })

        Column() {
          Text('包含诗词查询、成语接龙、歇后语猜谜，以及 GIF 制作、数独求解、单位转换等实用工具，助您领略文字之美、提升日常效率。')
            .fontSize(13)
            .fontColor($r('app.color.hint_text'))
            .textAlign(TextAlign.Center)
            .lineHeight(22)
          Text('© 2026 解语珠玑')
            .fontSize(12)
            .fontColor($r('app.color.hint_text'))
            .margin({ top: 8 })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 24, bottom: 20 })
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
