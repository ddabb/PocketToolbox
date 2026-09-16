import { pasteboard, BusinessError } from '@kit.BasicServicesKit';

export class ClipboardUtil {
  static copy(text: string): void {
    if (!text) {
      return;
    }
    try {
      let pasteData: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      let systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      systemPasteboard.setData(pasteData);
    } catch (e) {
      console.error('[ClipboardUtil] copy failed: ' + (e as BusinessError).message);
    }
  }
}
