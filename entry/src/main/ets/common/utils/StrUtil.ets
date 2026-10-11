import { Context } from '@kit.AbilityKit';

export class StrUtil {
  static text(context: Context, res: ResourceStr): string {
    if (typeof res === 'string') {
      return res;
    }
    if (res.params !== undefined && res.params.length > 0) {
      let args: Array<string | number> = [];
      for (let i = 0; i < res.params.length; i++) {
        let p: Object = res.params[i];
        if (typeof p === 'string') {
          args.push(p);
        } else if (typeof p === 'number') {
          args.push(p);
        } else {
          args.push(`${p}`);
        }
      }
      return context.resourceManager.getStringSync(res.id, ...args);
    }
    return context.resourceManager.getStringSync(res.id);
  }
}
