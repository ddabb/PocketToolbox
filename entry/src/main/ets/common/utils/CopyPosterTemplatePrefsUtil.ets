import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { CopyPosterTemplates } from '../../core/cover/CopyPosterTemplates';

/**
 * 文案海报模板偏好（1.4.9 A2）：收藏模板 + 最近使用模板。
 *
 * 复用 app_cache preferences（与 recent_tool_ids/poster_last_category 同库，不同 key）。
 * 收藏：模板缩略图右上角 star 角标切换，分类内收藏置前；
 * 最近：保存/导出成功时记录模板 id（头插去重 top 5），模板面板顶部「最近使用」分组置顶。
 * 读取时校验模板 id 仍注册，防脏数据（模板下线/改名后不渲染幽灵项）。
 */
export class CopyPosterTemplatePrefsUtil {
  private static readonly PREFS_NAME: string = 'app_cache';
  private static readonly KEY_FAVORITES: string = 'poster_favorite_templates';
  private static readonly KEY_RECENT: string = 'poster_recent_templates';
  private static readonly MAX_RECENT: number = 5;

  private static isValidTemplateId(id: string): boolean {
    return id !== '' && CopyPosterTemplates.getById(id).id === id;
  }

  /**
   * 纯函数（无 context 依赖，ohosTest 直测）：JSON 字符串 -> 校验有效性的 id 数组。
   * 防御：坏 JSON/非数组/null 安全回退空表；非字符串元素与未注册 id 剔除；重复去重；limit>0 截前 limit 项。
   */
  static parseIds(json: string, limit: number): string[] {
    let result: string[] = [];
    if (!json) {
      return result;
    }
    try {
      let raw: Object[] = JSON.parse(json) as Object[];
      for (let i = 0; i < raw.length; i++) {
        if (typeof raw[i] === 'string') {
          let id: string = raw[i] as string;
          if (CopyPosterTemplatePrefsUtil.isValidTemplateId(id) && result.indexOf(id) < 0) {
            result.push(id);
          }
        }
      }
    } catch (e) {
      // 坏 JSON（含 null/标量）安全回退空表
    }
    if (limit > 0 && result.length > limit) {
      result = result.slice(0, limit);
    }
    return result;
  }

  /** 纯函数（无 context 依赖，ohosTest 直测）：头插去重，超 MAX_RECENT 截尾（即存即 top5） */
  static mergeRecentIds(prevIds: string[], usedId: string): string[] {
    let next: string[] = [usedId];
    for (let i = 0; i < prevIds.length; i++) {
      if (prevIds[i] !== usedId) {
        next.push(prevIds[i]);
      }
    }
    if (next.length > CopyPosterTemplatePrefsUtil.MAX_RECENT) {
      next = next.slice(0, CopyPosterTemplatePrefsUtil.MAX_RECENT);
    }
    return next;
  }

  /** 收藏模板 id 列表（已校验注册有效性，顺序即收藏先后） */
  static loadFavoriteIds(context: Context): string[] {
    return CopyPosterTemplatePrefsUtil.readIds(context, CopyPosterTemplatePrefsUtil.KEY_FAVORITES, 0);
  }

  /** 是否已收藏 */
  static isFavorite(context: Context, templateId: string): boolean {
    return CopyPosterTemplatePrefsUtil.loadFavoriteIds(context).indexOf(templateId) >= 0;
  }

  /** 切换收藏状态；返回切换后是否为已收藏 */
  static toggleFavorite(context: Context, templateId: string): boolean {
    let ids: string[] = CopyPosterTemplatePrefsUtil.loadFavoriteIds(context);
    let idx: number = ids.indexOf(templateId);
    let nowFavorite: boolean;
    if (idx >= 0) {
      ids.splice(idx, 1);
      nowFavorite = false;
    } else {
      ids.push(templateId);
      nowFavorite = true;
    }
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context,
        { name: CopyPosterTemplatePrefsUtil.PREFS_NAME });
      prefs.putSync(CopyPosterTemplatePrefsUtil.KEY_FAVORITES, JSON.stringify(ids));
      prefs.flushSync();
    } catch (e) {
      console.error('[PosterTplPrefs] toggle favorite failed: ' + (e as Error).message);
    }
    return nowFavorite;
  }

  /** 最近使用模板 id 列表（最新在前，top 5） */
  static loadRecentIds(context: Context): string[] {
    return CopyPosterTemplatePrefsUtil.readIds(context, CopyPosterTemplatePrefsUtil.KEY_RECENT,
      CopyPosterTemplatePrefsUtil.MAX_RECENT);
  }

  /** 记录一次模板使用（保存/导出成功时调用）：mergeRecentIds 头插去重 top5 后落盘 */
  static recordTemplateUse(context: Context, templateId: string): void {
    let next: string[] = CopyPosterTemplatePrefsUtil.mergeRecentIds(
      CopyPosterTemplatePrefsUtil.loadRecentIds(context), templateId);
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context,
        { name: CopyPosterTemplatePrefsUtil.PREFS_NAME });
      prefs.putSync(CopyPosterTemplatePrefsUtil.KEY_RECENT, JSON.stringify(next));
      prefs.flushSync();
    } catch (e) {
      console.error('[PosterTplPrefs] record use failed: ' + (e as Error).message);
    }
  }

  /** 通用读取：prefs JSON 字符串 -> parseIds 校验过滤（limit>0 时截取前 limit 项） */
  private static readIds(context: Context, key: string, limit: number): string[] {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context,
        { name: CopyPosterTemplatePrefsUtil.PREFS_NAME });
      return CopyPosterTemplatePrefsUtil.parseIds(prefs.getSync(key, '') as string, limit);
    } catch (e) {
      console.error('[PosterTplPrefs] load ' + key + ' failed: ' + (e as Error).message);
      return [];
    }
  }
}
