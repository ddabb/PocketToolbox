import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';

export class ReadingItem {
  id: string = '';
  type: string = '';
  title: string = '';
  subtitle: string = '';
  content: string = '';
  timestamp: number = 0;

  static create(type: string, title: string, subtitle: string, content: string): ReadingItem {
    let item: ReadingItem = new ReadingItem();
    item.id = type + '_' + title + '_' + Date.now().toString();
    item.type = type;
    item.title = title;
    item.subtitle = subtitle;
    item.content = content;
    item.timestamp = Date.now();
    return item;
  }
}

export class ReadingList {
  id: string = '';
  name: string = '';
  items: ReadingItem[] = [];
  createdAt: number = 0;
  updatedAt: number = 0;
  lastPlayedIndex: number = -1;
  lastPlayedTime: number = 0;

  static create(name: string): ReadingList {
    let list: ReadingList = new ReadingList();
    list.id = 'rl_' + Date.now().toString();
    list.name = name;
    list.items = [];
    list.createdAt = Date.now();
    list.updatedAt = Date.now();
    list.lastPlayedIndex = -1;
    list.lastPlayedTime = 0;
    return list;
  }
}

export class ReadingListStore {
  private static readonly PREFS_NAME: string = 'reading_lists';
  private static readonly KEY: string = 'reading_lists_data';
  private static cached: ReadingList[] | null = null;

  static invalidateCache(): void {
    ReadingListStore.cached = null;
  }

  static load(context: Context): ReadingList[] {
    if (ReadingListStore.cached !== null) {
      return ReadingListStore.cached;
    }
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: ReadingListStore.PREFS_NAME });
      let json: string = prefs.getSync(ReadingListStore.KEY, '') as string;
      if (!json) {
        ReadingListStore.cached = [];
        return [];
      }
      let raw: Object[] = JSON.parse(json) as Object[];
      let lists: ReadingList[] = [];
      for (let i = 0; i < raw.length; i++) {
        let obj: Record<string, Object> = raw[i] as Record<string, Object>;
        let list: ReadingList = new ReadingList();
        list.id = (obj['id'] as string) || '';
        list.name = (obj['name'] as string) || '';
        list.createdAt = (obj['createdAt'] as number) || 0;
        list.updatedAt = (obj['updatedAt'] as number) || 0;
        list.lastPlayedIndex = (obj['lastPlayedIndex'] as number) || -1;
        list.lastPlayedTime = (obj['lastPlayedTime'] as number) || 0;
        let itemsRaw: Object[] = (obj['items'] as Object[]) || [];
        list.items = [];
        for (let j = 0; j < itemsRaw.length; j++) {
          let itemObj: Record<string, Object> = itemsRaw[j] as Record<string, Object>;
          let item: ReadingItem = new ReadingItem();
          item.id = (itemObj['id'] as string) || '';
          item.type = (itemObj['type'] as string) || '';
          item.title = (itemObj['title'] as string) || '';
          item.subtitle = (itemObj['subtitle'] as string) || '';
          item.content = (itemObj['content'] as string) || '';
          item.timestamp = (itemObj['timestamp'] as number) || 0;
          list.items.push(item);
        }
        lists.push(list);
      }
      ReadingListStore.cached = lists;
      return lists;
    } catch (e) {
      console.error('[ReadingList] load failed: ' + (e as Error).message);
      ReadingListStore.cached = [];
      return [];
    }
  }

  static save(context: Context, lists: ReadingList[]): void {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: ReadingListStore.PREFS_NAME });
      prefs.putSync(ReadingListStore.KEY, JSON.stringify(lists));
      prefs.flush();
      ReadingListStore.cached = lists;
    } catch (e) {
      console.error('[ReadingList] save failed: ' + (e as Error).message);
    }
  }

  static addList(context: Context, name: string): ReadingList {
    let lists: ReadingList[] = ReadingListStore.load(context);
    let newList: ReadingList = ReadingList.create(name);
    lists.unshift(newList);
    ReadingListStore.save(context, lists);
    return newList;
  }

  static removeList(context: Context, listId: string): void {
    let lists: ReadingList[] = ReadingListStore.load(context);
    let newLists: ReadingList[] = [];
    for (let i = 0; i < lists.length; i++) {
      if (lists[i].id !== listId) {
        newLists.push(lists[i]);
      }
    }
    ReadingListStore.save(context, newLists);
  }

  static renameList(context: Context, listId: string, newName: string): void {
    let lists: ReadingList[] = ReadingListStore.load(context);
    for (let i = 0; i < lists.length; i++) {
      if (lists[i].id === listId) {
        lists[i].name = newName;
        lists[i].updatedAt = Date.now();
        break;
      }
    }
    ReadingListStore.save(context, lists);
  }

  static addItemToList(context: Context, listId: string, item: ReadingItem): boolean {
    let lists: ReadingList[] = ReadingListStore.load(context);
    for (let i = 0; i < lists.length; i++) {
      if (lists[i].id === listId) {
        let exists: boolean = false;
        for (let j = 0; j < lists[i].items.length; j++) {
          if (lists[i].items[j].type === item.type && lists[i].items[j].title === item.title) {
            exists = true;
            break;
          }
        }
        if (exists) {
          return false;
        }
        lists[i].items.push(item);
        lists[i].updatedAt = Date.now();
        ReadingListStore.save(context, lists);
        return true;
      }
    }
    return false;
  }

  static removeItemFromList(context: Context, listId: string, itemId: string): void {
    let lists: ReadingList[] = ReadingListStore.load(context);
    for (let i = 0; i < lists.length; i++) {
      if (lists[i].id === listId) {
        let newItems: ReadingItem[] = [];
        for (let j = 0; j < lists[i].items.length; j++) {
          if (lists[i].items[j].id !== itemId) {
            newItems.push(lists[i].items[j]);
          }
        }
        lists[i].items = newItems;
        lists[i].updatedAt = Date.now();
        break;
      }
    }
    ReadingListStore.save(context, lists);
  }

  static moveItem(context: Context, listId: string, fromIndex: number, toIndex: number): void {
    let lists: ReadingList[] = ReadingListStore.load(context);
    for (let i = 0; i < lists.length; i++) {
      if (lists[i].id === listId) {
        let items: ReadingItem[] = lists[i].items;
        if (fromIndex < 0 || fromIndex >= items.length || toIndex < 0 || toIndex >= items.length) {
          return;
        }
        let moved: ReadingItem = items[fromIndex];
        items.splice(fromIndex, 1);
        items.splice(toIndex, 0, moved);
        lists[i].updatedAt = Date.now();
        break;
      }
    }
    ReadingListStore.save(context, lists);
  }

  static getList(context: Context, listId: string): ReadingList | null {
    let lists: ReadingList[] = ReadingListStore.load(context);
    for (let i = 0; i < lists.length; i++) {
      if (lists[i].id === listId) {
        return lists[i];
      }
    }
    return null;
  }
}
