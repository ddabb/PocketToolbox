import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { CopyPosterCategories } from '../../model/CopyPosterModels';

/**
 * 文案海报分类偏好：记忆上次选择的分类 id。
 *
 * 复用 RecentToolsUtil 的 app_cache preferences（与 recent_tool_ids 同库，不同 key）。
 * 用户每次进来若都重置到第一类，切类频繁的场景体验差；
 * 记忆后再次进入直接落在上次那个分类，模板横滑条第一屏就是上次在用的模板。
 */
export class CopyPosterCategoryUtil {
  private static readonly PREFS_NAME: string = 'app_cache';
  private static readonly KEY_LAST_CATEGORY: string = 'poster_last_category';

  /** 读取上次分类；无记录或记录已失效（分类被改名/删除）时返回空串 */
  static loadLastCategory(context: Context): string {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context,
        { name: CopyPosterCategoryUtil.PREFS_NAME });
      let id: string = prefs.getSync(CopyPosterCategoryUtil.KEY_LAST_CATEGORY, '') as string;
      if (!id) {
        return '';
      }
      // 校验分类是否仍存在，避免读到脏数据导致分类列表为空
      let cats = CopyPosterCategories.all();
      for (let i = 0; i < cats.length; i++) {
        if (cats[i].id === id) {
          return id;
        }
      }
      return '';
    } catch (e) {
      console.error('[PosterCat] load last category failed: ' + (e as Error).message);
      return '';
    }
  }

  static saveLastCategory(context: Context, categoryId: string): void {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context,
        { name: CopyPosterCategoryUtil.PREFS_NAME });
      prefs.putSync(CopyPosterCategoryUtil.KEY_LAST_CATEGORY, categoryId);
      prefs.flushSync();
    } catch (e) {
      console.error('[PosterCat] save last category failed: ' + (e as Error).message);
    }
  }
}
