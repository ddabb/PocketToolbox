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

  static async paste(): Promise<string> {
    let systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
    let pasteData: pasteboard.PasteData = await systemPasteboard.getData();
    if (pasteData && pasteData.getRecordCount() > 0) {
      let record: pasteboard.PasteDataRecord = pasteData.getRecordAt(0);
      if (record.plainText !== null && record.plainText !== undefined) {
        return record.plainText as string;
      }
    }
    return '';
  }
}
