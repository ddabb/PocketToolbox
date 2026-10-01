import { Context } from '@kit.AbilityKit';

export class StrUtil {
  static text(context: Context, res: ResourceStr): string {
    if (typeof res === 'string') {
      return res;
    }
    return context.resourceManager.getStringSync(res);
  }
}
