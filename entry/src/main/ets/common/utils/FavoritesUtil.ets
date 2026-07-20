import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';

export class FavoriteItem {
  type: string = '';
  title: string = '';
  subtitle: string = '';
  data: string = '';
  timestamp: number = 0;
}

export interface FavoriteAddResult {
  added: boolean;
  truncated: boolean;
}

export class FavoritesUtil {
  private static readonly PREFS_NAME: string = 'app_cache';
  private static readonly MAX_FAVORITES: number = 200;
  private static readonly FAVORITES_KEY: string = 'user_favorites';
  private static cachedItems: FavoriteItem[] | null = null;
  private static cachedKeySet: Set<string> | null = null;

  private static buildKey(type: string, title: string): string {
    return type + '::' + title;
  }

  private static rebuildKeySet(): void {
    if (!FavoritesUtil.cachedItems) {
      FavoritesUtil.cachedKeySet = null;
      return;
    }
    let set: Set<string> = new Set<string>();
    for (let i = 0; i < FavoritesUtil.cachedItems.length; i++) {
      let item: FavoriteItem = FavoritesUtil.cachedItems[i];
      set.add(FavoritesUtil.buildKey(item.type, item.title));
    }
    FavoritesUtil.cachedKeySet = set;
  }

  static invalidateCache(): void {
    FavoritesUtil.cachedItems = null;
    FavoritesUtil.cachedKeySet = null;
  }

  static load(context: Context): FavoriteItem[] {
    if (FavoritesUtil.cachedItems !== null) {
      return FavoritesUtil.cachedItems;
    }
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: FavoritesUtil.PREFS_NAME });
      let json: string = prefs.getSync(FavoritesUtil.FAVORITES_KEY, '') as string;
      if (!json) {
        FavoritesUtil.cachedItems = [];
        FavoritesUtil.cachedKeySet = new Set<string>();
        return [];
      }
      let raw: Object[] = JSON.parse(json) as Object[];
      let items: FavoriteItem[] = [];
      let keySet: Set<string> = new Set<string>();
      for (let i = 0; i < raw.length; i++) {
        let obj: Record<string, Object> = raw[i] as Record<string, Object>;
        let item: FavoriteItem = new FavoriteItem();
        item.type = (obj['type'] as string) || '';
        item.title = (obj['title'] as string) || '';
        item.subtitle = (obj['subtitle'] as string) || '';
        item.data = (obj['data'] as string) || '';
        item.timestamp = (obj['timestamp'] as number) || 0;
        items.push(item);
        keySet.add(FavoritesUtil.buildKey(item.type, item.title));
      }
      FavoritesUtil.cachedItems = items;
      FavoritesUtil.cachedKeySet = keySet;
      return items;
    } catch (e) {
      console.error('[Favorites] load failed: ' + (e as Error).message);
      FavoritesUtil.cachedItems = [];
      FavoritesUtil.cachedKeySet = new Set<string>();
      return [];
    }
  }

  static save(context: Context, items: FavoriteItem[]): void {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: FavoritesUtil.PREFS_NAME });
      prefs.putSync(FavoritesUtil.FAVORITES_KEY, JSON.stringify(items));
      prefs.flush();
      FavoritesUtil.cachedItems = items;
      FavoritesUtil.rebuildKeySet();
    } catch (e) {
      console.error('[Favorites] save failed: ' + (e as Error).message);
    }
  }

  static add(context: Context, item: FavoriteItem): FavoriteAddResult {
    let items: FavoriteItem[] = FavoritesUtil.load(context);
    let key: string = FavoritesUtil.buildKey(item.type, item.title);
    if (FavoritesUtil.cachedKeySet && FavoritesUtil.cachedKeySet.has(key)) {
      console.info('[Favorites] already exists: ' + item.title);
      return { added: false, truncated: false };
    }
    item.timestamp = Date.now();
    items.unshift(item);
    let truncated: boolean = false;
    if (items.length > FavoritesUtil.MAX_FAVORITES) {
      items = items.slice(0, FavoritesUtil.MAX_FAVORITES);
      truncated = true;
    }
    FavoritesUtil.save(context, items);
    console.info('[Favorites] added: type=' + item.type + ', title=' + item.title + ', truncated=' + truncated.toString());
    return { added: true, truncated: truncated };
  }

  static remove(context: Context, type: string, title: string): void {
    let items: FavoriteItem[] = FavoritesUtil.load(context);
    let newItems: FavoriteItem[] = [];
    for (let i = 0; i < items.length; i++) {
      if (items[i].type !== type || items[i].title !== title) {
        newItems.push(items[i]);
      }
    }
    FavoritesUtil.save(context, newItems);
    console.info('[Favorites] removed: type=' + type + ', title=' + title);
  }

  static isFavorite(context: Context, type: string, title: string): boolean {
    FavoritesUtil.load(context);
    let key: string = FavoritesUtil.buildKey(type, title);
    return FavoritesUtil.cachedKeySet !== null && FavoritesUtil.cachedKeySet.has(key);
  }
}
