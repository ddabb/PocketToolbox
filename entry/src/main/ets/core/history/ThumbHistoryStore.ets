/**
 * 缩略图历史存储（词云/文字转图片共用）：沙箱 filesDir/<dirName>/ 下保存缩略图 PNG + 单一 index.json 索引。
 * 记录按时间倒序（最新在前），上限 20 条，超出时淘汰最旧记录及其缩略图文件。
 * 参数以 paramsText(JSON 字符串) 形式存储，由各页自行解析恢复。
 */
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { Context } from '@kit.AbilityKit';

export class ThumbHistoryRecord {
  id: string = '';
  thumbName: string = '';
  createdAt: number = 0;
  summary: string = '';
  paramsText: string = '';
}

export class ThumbHistoryStore {
  private static readonly INDEX_FILE: string = 'index.json';
  private static readonly MAX_RECORDS: number = 20;

  static historyDir(context: Context, dirName: string): string {
    return context.filesDir + '/' + dirName;
  }

  static thumbFilePath(context: Context, dirName: string, record: ThumbHistoryRecord): string {
    return ThumbHistoryStore.historyDir(context, dirName) + '/' + record.thumbName;
  }

  static ensureDir(context: Context, dirName: string): void {
    try {
      let dir: string = ThumbHistoryStore.historyDir(context, dirName);
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
    } catch (e) {
      console.error('[ThumbHistoryStore] ensureDir failed: ' + (e as Error).message);
    }
  }

  private static indexFilePath(context: Context, dirName: string): string {
    return ThumbHistoryStore.historyDir(context, dirName) + '/' + ThumbHistoryStore.INDEX_FILE;
  }

  private static writeRecords(context: Context, dirName: string, records: ThumbHistoryRecord[]): void {
    let arr: object[] = [];
    for (let i: number = 0; i < records.length; i++) {
      let r: ThumbHistoryRecord = records[i];
      let obj: Record<string, Object> = {
        'id': r.id,
        'thumbName': r.thumbName,
        'createdAt': r.createdAt,
        'summary': r.summary,
        'paramsText': r.paramsText
      };
      arr.push(obj);
    }
    try {
      let file: fs.File = fs.openSync(ThumbHistoryStore.indexFilePath(context, dirName),
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, JSON.stringify(arr));
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      console.error('[ThumbHistoryStore] writeRecords failed: ' + (e as Error).message);
    }
  }

  static loadRecords(context: Context, dirName: string): ThumbHistoryRecord[] {
    let indexFile: string = ThumbHistoryStore.indexFilePath(context, dirName);
    try {
      if (!fs.accessSync(indexFile)) {
        return [];
      }
      let file: fs.File = fs.openSync(indexFile, fs.OpenMode.READ_ONLY);
      let json: string = '';
      try {
        let stat: fs.Stat = fs.statSync(file.fd);
        let buf: ArrayBuffer = new ArrayBuffer(stat.size);
        fs.readSync(file.fd, buf);
        let decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
        json = decoder.decodeToString(new Uint8Array(buf));
      } finally {
        try {
          fs.closeSync(file);
        } catch (e) {
          console.error('[ThumbHistoryStore] close index file failed: ' + (e as Error).message);
        }
      }
      if (json.trim().length === 0) {
        return [];
      }
      let raw: Object[] = JSON.parse(json) as Object[];
      let records: ThumbHistoryRecord[] = [];
      for (let i: number = 0; i < raw.length; i++) {
        let obj: Record<string, Object> = raw[i] as Record<string, Object>;
        let r: ThumbHistoryRecord = new ThumbHistoryRecord();
        r.id = obj['id'] as string;
        r.thumbName = obj['thumbName'] as string;
        r.createdAt = Number(obj['createdAt']);
        r.summary = obj['summary'] as string;
        r.paramsText = obj['paramsText'] as string;
        if (typeof r.id === 'string' && r.id.length > 0 && typeof r.thumbName === 'string' && r.thumbName.length > 0) {
          records.push(r);
        }
      }
      return records;
    } catch (e) {
      console.error('[ThumbHistoryStore] loadRecords failed: ' + (e as Error).message);
      return [];
    }
  }

  /** 最新一条记录参数是否与 paramsText 完全一致（用于避免重复生成刷屏） */
  static isSameAsLatest(context: Context, dirName: string, paramsText: string): boolean {
    let records: ThumbHistoryRecord[] = ThumbHistoryStore.loadRecords(context, dirName);
    if (records.length === 0) {
      return false;
    }
    return records[0].paramsText === paramsText;
  }

  /**
   * 保存一条记录：把 thumbPixelMap 打包为 PNG 缩略图写入历史目录，插入索引头部，超出上限淘汰最旧记录。
   */
  static async saveRecord(context: Context, dirName: string, record: ThumbHistoryRecord,
    thumbPixelMap: image.PixelMap): Promise<boolean> {
    try {
      ThumbHistoryStore.ensureDir(context, dirName);
      let thumbPath: string = ThumbHistoryStore.thumbFilePath(context, dirName, record);
      let file: fs.File = fs.openSync(thumbPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      let packer: image.ImagePacker = image.createImagePacker();
      let packOpts: image.PackingOption = { format: 'image/png', quality: 90 };
      try {
        await packer.packToFile(thumbPixelMap, file.fd, packOpts);
      } finally {
        try {
          fs.closeSync(file.fd);
        } catch (e) {
          console.error('[ThumbHistoryStore] closeSync failed: ' + (e as Error).message);
        }
        packer.release();
      }
      let records: ThumbHistoryRecord[] = ThumbHistoryStore.loadRecords(context, dirName);
      records.unshift(record);
      while (records.length > ThumbHistoryStore.MAX_RECORDS) {
        let removed: ThumbHistoryRecord | undefined = records.pop();
        if (removed !== undefined) {
          ThumbHistoryStore.removeFile(context, dirName, removed);
        }
      }
      ThumbHistoryStore.writeRecords(context, dirName, records);
      return true;
    } catch (e) {
      console.error('[ThumbHistoryStore] saveRecord failed: ' + (e as Error).message);
      return false;
    }
  }

  static deleteRecord(context: Context, dirName: string, id: string): void {
    let records: ThumbHistoryRecord[] = ThumbHistoryStore.loadRecords(context, dirName);
    let rest: ThumbHistoryRecord[] = [];
    for (let i: number = 0; i < records.length; i++) {
      if (records[i].id !== id) {
        rest.push(records[i]);
      } else {
        ThumbHistoryStore.removeFile(context, dirName, records[i]);
      }
    }
    ThumbHistoryStore.writeRecords(context, dirName, rest);
  }

  static recordCount(context: Context, dirName: string): number {
    return ThumbHistoryStore.loadRecords(context, dirName).length;
  }

  private static removeFile(context: Context, dirName: string, record: ThumbHistoryRecord): void {
    try {
      let path: string = ThumbHistoryStore.thumbFilePath(context, dirName, record);
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      console.warn('[ThumbHistoryStore] removeFile failed: ' + (e as Error).message);
    }
  }
}

/** 生成历史记录 id：<prefix>_<时间戳36进制>_<随机> */
export function makeHistoryId(prefix: string): string {
  let ts: string = Date.now().toString(36);
  let rand: number = Math.floor(Math.random() * 100000);
  return prefix + '_' + ts + '_' + rand.toString();
}
