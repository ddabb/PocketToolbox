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
    if (ok) {
      return new AddToListResult(true, '已添加到朗读清单');
    } else {
      return new AddToListResult(false, '该内容已在清单中');
    }
  }
}
