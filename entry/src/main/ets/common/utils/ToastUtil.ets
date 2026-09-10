import { BusinessError } from '@kit.BasicServicesKit';

export class ToastUtil {
  static show(uiContext: UIContext, message: string, duration: number): void {
    try {
      uiContext.getPromptAction().showToast({ message: message, duration: duration });
    } catch (e) {
      console.error('[ToastUtil] showToast failed: ' + (e as BusinessError).message);
    }
  }
}
