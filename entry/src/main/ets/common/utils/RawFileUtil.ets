import { Context } from '@kit.AbilityKit';
import { buffer } from '@kit.ArkTS';

export class RawFileUtil {
  static readJson<T>(context: Context, path: string): T {
    let content: Uint8Array = context.resourceManager.getRawFileContentSync(path);
    let text: string = buffer.from(content.buffer).toString('utf-8');
    if (!text || text.trim().length === 0) {
      throw new Error('RawFile empty after decode: ' + path + ', rawBytes=' + content.length.toString());
    }
    let trimmed: string = text.trim();
    if (trimmed.charCodeAt(0) === 0xFEFF) {
      trimmed = trimmed.substring(1);
    }
    try {
      return JSON.parse(trimmed) as T;
    } catch (parseErr) {
      let preview: string = trimmed.length > 100 ? trimmed.substring(0, 100) : trimmed;
      throw new Error('JSON parse failed for ' + path + ': ' + (parseErr as Error).message + ', preview: [' + preview + ']');
    }
  }
}
