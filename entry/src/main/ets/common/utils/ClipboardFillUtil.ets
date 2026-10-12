/**
 * 剪贴板一键填入工具（文案海报/生字卡共用）。
 *
 * API 12+ 程序化读取剪贴板需受限权限 READ_PASTEBOARD（本工程未声明，读取会失败/触发授权窗），
 * 合规路径为 PasteButton 安全控件：用户点击后系统临时授权，在其 onClick 回调内调用
 * readClipboardText() 方可成功。进入页面仅做免权限的 hasClipboardText() 前置探测。
 */
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';

export class ClipboardFillUtil {
  /** 前置探测：剪贴板是否含纯文本数据（免权限元数据检查，异常一律视为无） */
  static hasClipboardText(): boolean {
    try {
      let sys: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      return sys.hasDataType(pasteboard.MIMETYPE_TEXT_PLAIN);
    } catch (e) {
      console.error('[ClipboardFillUtil] hasDataType failed: ' + (e as BusinessError).message);
      return false;
    }
  }

  /**
   * 读取剪贴板纯文本。仅在 PasteButton onClick 临时授权窗口内调用有效，失败返回空串。
   */
  static async readClipboardText(): Promise<string> {
    try {
      let sys: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      let data: pasteboard.PasteData = await sys.getData();
      let text: string = data.getPrimaryText();
      return text !== undefined ? text : '';
    } catch (e) {
      console.error('[ClipboardFillUtil] getData failed: ' + (e as BusinessError).message);
      return '';
    }
  }
}
