import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';

export class RecentToolsUtil {
  private static readonly PREFS_NAME: string = 'app_cache';
  private static readonly KEY_RECENT_TOOLS: string = 'recent_tool_ids';
  private static readonly MAX_COUNT: number = 8;

  static loadRecent(context: Context): string[] {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: RecentToolsUtil.PREFS_NAME });
      let json: string = prefs.getSync(RecentToolsUtil.KEY_RECENT_TOOLS, '') as string;
      if (!json) {
        return [];
      }
      let raw: Object[] = JSON.parse(json) as Object[];
      let arr: string[] = [];
      for (let i = 0; i < raw.length; i++) {
        let id: string = raw[i] as string;
        if (id) {
          arr.push(id);
        }
      }
      return arr;
    } catch (e) {
      return [];
    }
  }

  static recordUse(context: Context, toolId: string): string[] {
    let list: string[] = RecentToolsUtil.loadRecent(context);
    let next: string[] = [toolId];
    for (let i = 0; i < list.length; i++) {
      if (list[i] !== toolId) {
        next.push(list[i]);
      }
    }
    if (next.length > RecentToolsUtil.MAX_COUNT) {
      next = next.slice(0, RecentToolsUtil.MAX_COUNT);
    }
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: RecentToolsUtil.PREFS_NAME });
      prefs.putSync(RecentToolsUtil.KEY_RECENT_TOOLS, JSON.stringify(next));
      prefs.flushSync();
    } catch (e) {
      console.warn('[RecentTools] save failed');
    }
    return next;
  }
}
