import { Context } from '@kit.AbilityKit';
import { BackupUtil } from '../common/utils/BackupUtil';
import { ToastUtil } from '../common/utils/ToastUtil';

@Builder
export function DataBackupPageBuilder() {
  NavDestination() {
    DataBackupContent()
  }
  .title($r('app.string.bk_title'))
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct DataBackupContent {
  @State busy: boolean = false;
  private uiContext: UIContext = this.getUIContext();

  private doExport(): void {
    if (this.busy) {
      return;
    }
    this.busy = true;
    let ctx: Context = this.uiContext.getHostContext() as Context;
    BackupUtil.exportBackup(ctx)
      .then((uri: string) => {
        this.busy = false;
        if (uri === '') {
          ToastUtil.show(this.uiContext, $r('app.string.bk_export_cancel'), 1500);
        } else {
          ToastUtil.show(this.uiContext, $r('app.string.bk_export_ok'), 1500);
        }
      })
      .catch(() => {
        this.busy = false;
        ToastUtil.show(this.uiContext, $r('app.string.bk_export_fail'), 1500);
      });
  }

  private doImport(): void {
    if (this.busy) {
      return;
    }
    let dialogParam: AlertDialogParamWithButtons = {
      title: $r('app.string.bk_import_confirm_title'),
      message: $r('app.string.bk_import_confirm_msg'),
      primaryButton: {
        value: $r('app.string.xhyq_cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.bk_import'),
        action: () => {
          this.runImport();
        }
      }
    };
    this.uiContext.showAlertDialog(dialogParam);
  }

  private runImport(): void {
    this.busy = true;
    let ctx: Context = this.uiContext.getHostContext() as Context;
    BackupUtil.importBackup(ctx)
      .then((ok: boolean) => {
        this.busy = false;
        if (ok) {
          ToastUtil.show(this.uiContext, $r('app.string.bk_import_ok'), 1500);
        } else {
          ToastUtil.show(this.uiContext, $r('app.string.bk_import_cancel'), 1500);
        }
      })
      .catch(() => {
        this.busy = false;
        ToastUtil.show(this.uiContext, $r('app.string.bk_import_fail'), 1500);
      });
  }

  build() {
    Column() {
      Column() {
        Column() {
          Text($r('app.string.bk_scope_title'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          Text($r('app.string.bk_scope_desc'))
            .fontSize(13)
            .fontColor($r('app.color.tertiary_text'))
            .lineHeight(22)
            .margin({ top: 10 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(14)

        Text($r('app.string.bk_export'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_accent_text'))
          .backgroundColor($r('app.color.poetry_green'))
          .borderRadius(16)
          .padding({ left: 24, right: 24, top: 12, bottom: 12 })
          .margin({ top: 24 })
          .width('100%')
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.doExport();
          })

        Text($r('app.string.bk_import'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.busy ? $r('app.color.hint_text') : $r('app.color.poetry_green'))
          .backgroundColor($r('app.color.poetry_green') + '18')
          .borderRadius(16)
          .padding({ left: 24, right: 24, top: 12, bottom: 12 })
          .margin({ top: 14 })
          .width('100%')
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.doImport();
          })

        if (this.busy) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color($r('app.color.poetry_green'))
            .margin({ top: 20 })
        }
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: 720 })
      .padding({ left: 16, right: 16, top: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
