import { ReadingListStore, ReadingList, ReadingItem } from '../../model/ReadingListModels';
import { Context } from '@kit.AbilityKit';

export class AddToListResult {
  success: boolean = false;
  msg: string = '';

  constructor(success: boolean, msg: string) {
    this.success = success;
    this.msg = msg;
  }
}

export class AddToReadingListUtil {
  static getLists(context: Context): ReadingList[] {
    ReadingListStore.invalidateCache();
    return ReadingListStore.load(context);
  }

  static addItemToList(context: Context, listId: string, item: ReadingItem): boolean {
    return ReadingListStore.addItemToList(context, listId, item);
  }

  static addToListWithCheck(context: Context, listId: string, type: string, title: string,
    subtitle: string, content: string): AddToListResult {
    let item: ReadingItem = ReadingItem.create(type, title, subtitle, content);
    let ok: boolean = ReadingListStore.addItemToList(context, listId, item);
    let listName: string = '';
    let list: ReadingList | null = ReadingListStore.getList(context, listId);
    if (list) {
      listName = list.name;
    }
    if (ok) {
      return new AddToListResult(true, '已加入「' + listName + '」');
    } else {
      return new AddToListResult(false, '已在「' + listName + '」中');
    }
  }

  static isInAnyList(context: Context, type: string, title: string): boolean {
    let lists: ReadingList[] = ReadingListStore.load(context);
    for (let i: number = 0; i < lists.length; i++) {
      let items: ReadingItem[] = lists[i].items;
      for (let j: number = 0; j < items.length; j++) {
        if (items[j].type === type && items[j].title === title) {
          return true;
        }
      }
    }
    return false;
  }
}
