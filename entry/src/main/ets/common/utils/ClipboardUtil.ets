import { pasteboard } from '@kit.BasicServicesKit';

export class ClipboardUtil {
  static copy(text: string): void {
    if (!text) {
      return;
    }
    let pasteData: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    let systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
    systemPasteboard.setData(pasteData);
  }
}
