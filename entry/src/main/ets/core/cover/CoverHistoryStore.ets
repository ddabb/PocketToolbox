/**
 * 公众号首图制作历史存储：沙箱目录 + index.json 索引，最多保留 20 条
 */
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { CoverHistoryRecord } from '../../model/CoverModels';

const INDEX_FILE: string = 'index.json';
const MAX_RECORDS: number = 20;

export class CoverHistoryStore {
  static readonly DIR_COVER: string = 'cover_history';
  static readonly DIR_CHAR_CARD: string = 'card_history';

  private static dir(context: common.Context, dirName: string = CoverHistoryStore.DIR_COVER): string {
    return context.filesDir + '/' + dirName;
  }

  static ensureDir(context: common.Context, dirName: string = CoverHistoryStore.DIR_COVER): void {
    let dir: string = CoverHistoryStore.dir(context, dirName);
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir, true);
    }
  }

  static loadRecords(context: common.Context, dirName: string = CoverHistoryStore.DIR_COVER): CoverHistoryRecord[] {
    try {
      let indexPath: string = CoverHistoryStore.dir(context, dirName) + '/' + INDEX_FILE;
      if (!fs.accessSync(indexPath)) {
        return [];
      }
      let text: string = fs.readTextSync(indexPath);
      if (text.trim() === '') {
        return [];
      }
      let arr: Array<Object> = JSON.parse(text) as Array<Object>;
      let records: CoverHistoryRecord[] = [];
      for (let i = 0; i < arr.length; i++) {
        let r: Record<string, Object> = arr[i] as Record<string, Object>;
        records.push(CoverHistoryRecord.of(
          String(r['id'] ?? ''),
          String(r['fileName'] ?? ''),
          String(r['templateId'] ?? ''),
          Number(r['paletteIndex'] ?? 0),
          Number(r['fontIndex'] ?? 0),
          String(r['textsJson'] ?? '{}'),
          Number(r['exportedAt'] ?? 0)));
      }
      return records;
    } catch (e) {
      console.error('[Cover] loadRecords failed: ' + (e as Error).message);
      return [];
    }
  }

  static filePath(context: common.Context, fileName: string,
    dirName: string = CoverHistoryStore.DIR_COVER): string {
    return CoverHistoryStore.dir(context, dirName) + '/' + fileName;
  }

  /** 复制导出文件入历史目录并写索引，返回是否成功 */
  static saveRecord(context: common.Context, srcPath: string, record: CoverHistoryRecord,
    dirName: string = CoverHistoryStore.DIR_COVER): boolean {
    try {
      CoverHistoryStore.ensureDir(context, dirName);
      let desPath: string = CoverHistoryStore.filePath(context, record.fileName, dirName);
      fs.copyFileSync(srcPath, desPath);
      let records: CoverHistoryRecord[] = CoverHistoryStore.loadRecords(context, dirName);
      records.unshift(record);
      while (records.length > MAX_RECORDS) {
        let removed: CoverHistoryRecord = records.pop()!;
        try {
          fs.unlinkSync(CoverHistoryStore.filePath(context, removed.fileName, dirName));
        } catch (e) {
          console.warn('[Cover] remove old history file failed: ' + (e as Error).message);
        }
      }
      let arr: Array<Object> = [];
      for (let i = 0; i < records.length; i++) {
        let r: Record<string, Object> = {
          'id': records[i].id,
          'fileName': records[i].fileName,
          'templateId': records[i].templateId,
          'paletteIndex': records[i].paletteIndex,
          'fontIndex': records[i].fontIndex,
          'textsJson': records[i].textsJson,
          'exportedAt': records[i].exportedAt,
        };
        arr.push(r);
      }
      let file: fs.File = fs.openSync(CoverHistoryStore.dir(context, dirName) + '/' + INDEX_FILE,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, JSON.stringify(arr));
      } finally {
        fs.closeSync(file.fd);
      }
      return true;
    } catch (e) {
      console.error('[Cover] saveRecord failed: ' + (e as Error).message);
      return false;
    }
  }

  static clearAll(context: common.Context, dirName: string = CoverHistoryStore.DIR_COVER): void {
    try {
      let dir: string = CoverHistoryStore.dir(context, dirName);
      if (!fs.accessSync(dir)) {
        return;
      }
      let names: string[] = fs.listFileSync(dir);
      for (let i = 0; i < names.length; i++) {
        fs.unlinkSync(dir + '/' + names[i]);
      }
    } catch (e) {
      console.error('[Cover] clearAll failed: ' + (e as Error).message);
    }
  }

  static makeFileName(): string {
    return 'cover_' + Date.now().toString(36) + '_' + Math.floor(Math.random() * 1000).toString() + '.png';
  }
}
