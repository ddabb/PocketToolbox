import { BusinessError } from '@kit.BasicServicesKit';
import { ComponentContent } from '@kit.ArkUI';

class ToastParams {
  message: ResourceStr;

  constructor(message: ResourceStr) {
    this.message = message;
  }
}

@Builder
function ToastBody(params: ToastParams) {
  Column() {
    Text(params.message)
      .fontSize(14)
      .fontColor($r('app.color.toast_text'))
      .maxLines(3)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .textAlign(TextAlign.Center)
  }
  .padding({ left: 24, right: 24, top: 11, bottom: 11 })
  .constraintSize({ maxWidth: '80%' })
  .backgroundColor($r('app.color.toast_bg'))
  .borderRadius(24)
}

/**
 * 全应用统一 toast（1.4.9 B4）：
 * 系统 showToast 子窗口无法被 uitest a11y 采集，且样式不可控；
 * 改用 openCustomDialog + ComponentContent（主窗口渲染，可 a11y 采集），
 * 底部对齐上移 140vp 避开操作区（ExportBar/TabBar），duration 毫秒后自动关闭，
 * 新 toast 顶替旧 toast（同系统语义）。
 */
export class ToastUtil {
  private static current: ComponentContent<ToastParams> | null = null;

  static show(uiContext: UIContext, message: ResourceStr, duration: number): void {
    try {
      ToastUtil.dismiss(uiContext);
      let content: ComponentContent<ToastParams> =
        new ComponentContent(uiContext, wrapBuilder(ToastBody), new ToastParams(message));
      ToastUtil.current = content;
      uiContext.getPromptAction().openCustomDialog(content, {
        alignment: DialogAlignment.Bottom,
        offset: { dx: 0, dy: -140 },
        isModal: false,
        autoCancel: false,
        showInSubWindow: false,
        transition: TransitionEffect.OPACITY
      }).then(() => {
        if (ToastUtil.current !== content) {
          uiContext.getPromptAction().closeCustomDialog(content).catch(() => {
          });
          return;
        }
        setTimeout(() => {
          if (ToastUtil.current === content) {
            ToastUtil.dismiss(uiContext);
          }
        }, duration);
      }).catch((e: BusinessError) => {
        if (ToastUtil.current === content) {
          ToastUtil.current = null;
        }
        console.error('[ToastUtil] openCustomDialog failed: ' + e.message);
      });
    } catch (e) {
      console.error('[ToastUtil] show failed: ' + (e as BusinessError).message);
    }
  }

  private static dismiss(uiContext: UIContext): void {
    let content: ComponentContent<ToastParams> | null = ToastUtil.current;
    if (content === null) {
      return;
    }
    let contentRef: ComponentContent<ToastParams> = content;
    ToastUtil.current = null;
    uiContext.getPromptAction().closeCustomDialog(contentRef).catch((e: BusinessError) => {
      console.warn('[ToastUtil] closeCustomDialog: ' + e.message);
    });
    setTimeout(() => {
      contentRef.dispose();
    }, 450);
  }
}
