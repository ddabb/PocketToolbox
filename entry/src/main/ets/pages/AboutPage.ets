import { bundleManager, common } from '@kit.AbilityKit';
import { GifHistoryStore, formatGifBytes } from '../core/gif/GifHistoryStore';
import { CheckInReminderUtil } from '../common/utils/CheckInReminderUtil';

@Builder
export function AboutPageBuilder() {
  NavDestination() {
    AboutContent()
  }
  .title($r('app.string.mine_about'))
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
      title: $r('app.string.about_clear_gif_title'),
      message: $r('app.string.about_clear_gif_msg', this.gifHistoryCount, formatGifBytes(this.gifHistoryBytes)),
      primaryButton: {
        value: $r('app.string.xhyq_cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.about_clear'),
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
          Text($r('app.string.EntryAbility_label'))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          if (this.versionName) {
            Text('v' + this.versionName)
              .fontSize(14)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ top: 4 })
          }
          Text($r('app.string.home_slogan'))
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
              Text($r('app.string.about_reminder_title'))
                .fontSize(15)
                .fontColor($r('app.color.primary_text'))
              Text($r('app.string.about_reminder_desc'))
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
            Text($r('app.string.about_gif_history'))
              .fontSize(15)
              .fontColor($r('app.color.primary_text'))
              .layoutWeight(1)
            Text($r('app.string.about_gif_history_count', this.gifHistoryCount, formatGifBytes(this.gifHistoryBytes)))
              .fontSize(14)
              .fontColor($r('app.color.tertiary_text'))
            if (this.gifHistoryCount > 0) {
              Text($r('app.string.about_clear'))
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
          Text($r('app.string.about_app_desc'))
            .fontSize(13)
            .fontColor($r('app.color.hint_text'))
            .textAlign(TextAlign.Center)
            .lineHeight(22)
          Text($r('app.string.about_copyright'))
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
