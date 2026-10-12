/**
 * ClipboardHintBar - 剪贴板内容提示条（文案海报/生字卡共用）
 *
 * 进入页面探测到剪贴板含文本时，在输入区上方显示的非侵入提示条：
 * 左侧提示文案 + PasteButton 安全控件（点击临时授权读取剪贴板并回调 onFill）+ 关闭按钮。
 * 因读取需用户点击授权，提示条无法展示内容预览（受限场景静默降级，见计划文档决策记录）。
 */
import { BusinessError } from '@kit.BasicServicesKit';
import { ClipboardFillUtil } from '../common/utils/ClipboardFillUtil';

@Component
export struct ClipboardHintBar {
  onFill: (text: string) => void = (text: string) => {};
  onDismiss: () => void = () => {};

  private async pasteFromClipboard(): Promise<void> {
    let text: string = await ClipboardFillUtil.readClipboardText();
    if (text.trim().length === 0) {
      this.onDismiss();
      return;
    }
    this.onFill(text);
  }

  build() {
    Row({ space: 8 }) {
      Text($r('app.string.clip_hint_text'))
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      PasteButton()
        .fontColor($r('app.color.on_accent_text'))
        .backgroundColor($r('app.color.brand_blue'))
        .borderRadius(16)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .onClick((event: ClickEvent, result: PasteButtonOnClickResult, error?: BusinessError<void>) => {
          if (result !== PasteButtonOnClickResult.SUCCESS) {
            return;
          }
          this.pasteFromClipboard();
        })
      Text('\u00D7')
        .fontSize(16)
        .fontColor($r('app.color.tertiary_text'))
        .padding({ left: 6, right: 6, top: 4, bottom: 4 })
        .onClick(() => {
          this.onDismiss();
        })
    }
    .width('100%')
    .padding({ left: 12, right: 8, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(10)
  }
}
