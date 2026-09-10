import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import { abilityAccessCtrl, common, PermissionRequestResult } from '@kit.AbilityKit';

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

  static async requestReadPermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      let result: PermissionRequestResult =
        await atManager.requestPermissionsFromUser(context, ['ohos.permission.READ_PASTEBOARD']);
      return result.authResults.length > 0 && result.authResults[0] === 0;
    } catch (e) {
      console.error('[ClipboardUtil] requestReadPermission failed: ' + (e as BusinessError).message);
      return false;
    }
  }

  static async paste(context: common.UIAbilityContext): Promise<string> {
    try {
      let granted: boolean = await ClipboardUtil.requestReadPermission(context);
      if (!granted) {
        return '';
      }
      let systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      let pasteData: pasteboard.PasteData = await systemPasteboard.getData();
      if (pasteData && pasteData.getRecordCount() > 0) {
        let record: pasteboard.PasteDataRecord = pasteData.getRecord(0);
        if (record.plainText !== null && record.plainText !== undefined) {
          return record.plainText as string;
        }
      }
    } catch (e) {
      console.error('[ClipboardUtil] paste failed: ' + (e as BusinessError).message);
    }
    return '';
  }
}
