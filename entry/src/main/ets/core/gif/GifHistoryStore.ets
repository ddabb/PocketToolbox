/**
 * GIF 制作历史存储：沙箱 filesDir/gif_history/ 下保存成品 GIF 文件 + 单一 index.json 索引。
 * 记录按时间倒序（最新在前），上限 50 条，超出时淘汰最旧记录及其文件。
 */
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

export class GifHistoryRecord {
  id: string = '';
  fileName: string = '';
  sizeBytes: number = 0;
  exportedAt: number = 0;
  width: number = 0;
  height: number = 0;
  frameCount: number = 0;
  paramsText: string = '';
}

export class GifHistoryStore {
  private static readonly DIR_NAME: string = 'gif_history';
  private static readonly INDEX_FILE: string = 'index.json';
  private static readonly MAX_RECORDS: number = 50;

  static historyDir(context: Context): string {
    return context.filesDir + '/' + GifHistoryStore.DIR_NAME;
  }

  static recordFilePath(context: Context, record: GifHistoryRecord): string {
    return GifHistoryStore.historyDir(context) + '/' + record.fileName;
  }

  static ensureDir(context: Context): void {
    try {
      let dir: string = GifHistoryStore.historyDir(context);
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
    } catch (e) {
      console.error('[GifHistoryStore] ensureDir failed: ' + (e as Error).message);
    }
  }

  private static indexFilePath(context: Context): string {
    return GifHistoryStore.historyDir(context) + '/' + GifHistoryStore.INDEX_FILE;
  }

  private static writeRecords(context: Context, records: GifHistoryRecord[]): void {
    let arr: object[] = [];
    for (let i: number = 0; i < records.length; i++) {
      let r: GifHistoryRecord = records[i];
      let obj: Record<string, Object> = {
        'id': r.id,
        'fileName': r.fileName,
        'sizeBytes': r.sizeBytes,
        'exportedAt': r.exportedAt,
        'width': r.width,
        'height': r.height,
        'frameCount': r.frameCount,
        'paramsText': r.paramsText
      };
      arr.push(obj);
    }
    try {
      let file: fs.File = fs.openSync(GifHistoryStore.indexFilePath(context), fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, JSON.stringify(arr));
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      console.error('[GifHistoryStore] writeRecords failed: ' + (e as Error).message);
    }
  }

  static loadRecords(context: Context): GifHistoryRecord[] {
    let indexFile: string = GifHistoryStore.indexFilePath(context);
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
          console.error('[GifHistoryStore] close index file failed: ' + (e as Error).message);
        }
      }
      if (json.trim().length === 0) {
        return [];
      }
      let raw: Object[] = JSON.parse(json) as Object[];
      let records: GifHistoryRecord[] = [];
      for (let i: number = 0; i < raw.length; i++) {
        let obj: Record<string, Object> = raw[i] as Record<string, Object>;
        let r: GifHistoryRecord = new GifHistoryRecord();
        r.id = obj['id'] as string;
        r.fileName = obj['fileName'] as string;
        r.sizeBytes = Number(obj['sizeBytes']);
        r.exportedAt = Number(obj['exportedAt']);
        r.width = Number(obj['width']);
        r.height = Number(obj['height']);
        r.frameCount = Number(obj['frameCount']);
        r.paramsText = obj['paramsText'] as string;
        if (typeof r.id === 'string' && r.id.length > 0 && typeof r.fileName === 'string' && r.fileName.length > 0) {
          records.push(r);
        }
      }
      return records;
    } catch (e) {
      console.error('[GifHistoryStore] loadRecords failed: ' + (e as Error).message);
      return [];
    }
  }

  /**
   * 保存一条记录：把 srcPath 的 GIF 复制进历史目录，插入索引头部，超出上限淘汰最旧记录。
   */
  static saveRecord(context: Context, srcPath: string, record: GifHistoryRecord): boolean {
    try {
      GifHistoryStore.ensureDir(context);
      let destPath: string = GifHistoryStore.historyDir(context) + '/' + record.fileName;
      fs.copyFileSync(srcPath, destPath);
      try {
        let stat: fs.Stat = fs.statSync(destPath);
        record.sizeBytes = stat.size;
      } catch (e) {
        record.sizeBytes = 0;
      }
      let records: GifHistoryRecord[] = GifHistoryStore.loadRecords(context);
      records.unshift(record);
      while (records.length > GifHistoryStore.MAX_RECORDS) {
        let removed: GifHistoryRecord = records.pop() as GifHistoryRecord;
        GifHistoryStore.removeFile(context, removed);
      }
      GifHistoryStore.writeRecords(context, records);
      return true;
    } catch (e) {
      console.error('[GifHistoryStore] saveRecord failed: ' + (e as Error).message);
      return false;
    }
  }

  static deleteRecord(context: Context, id: string): void {
    let records: GifHistoryRecord[] = GifHistoryStore.loadRecords(context);
    let rest: GifHistoryRecord[] = [];
    for (let i: number = 0; i < records.length; i++) {
      if (records[i].id !== id) {
        rest.push(records[i]);
      } else {
        GifHistoryStore.removeFile(context, records[i]);
      }
    }
    GifHistoryStore.writeRecords(context, rest);
  }

  static clearAll(context: Context): void {
    let records: GifHistoryRecord[] = GifHistoryStore.loadRecords(context);
    for (let i: number = 0; i < records.length; i++) {
      GifHistoryStore.removeFile(context, records[i]);
    }
    GifHistoryStore.writeRecords(context, []);
  }

  static totalBytes(context: Context): number {
    let records: GifHistoryRecord[] = GifHistoryStore.loadRecords(context);
    let total: number = 0;
    for (let i: number = 0; i < records.length; i++) {
      total += records[i].sizeBytes;
    }
    return total;
  }

  static recordCount(context: Context): number {
    return GifHistoryStore.loadRecords(context).length;
  }

  private static removeFile(context: Context, record: GifHistoryRecord): void {
    try {
      let path: string = GifHistoryStore.recordFilePath(context, record);
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      console.warn('[GifHistoryStore] removeFile failed: ' + (e as Error).message);
    }
  }
}

/** 生成历史记录文件名：gif_<时间戳36进制>_<随机>.gif */
export function makeHistoryFileName(): string {
  let ts: string = Date.now().toString(36);
  let rand: number = Math.floor(Math.random() * 100000);
  return 'gif_' + ts + '_' + rand.toString() + '.gif';
}

/** 字节数格式化：<1KB 显示 B，<1MB 显示 KB，否则 MB，保留 1 位小数 */
export function formatGifBytes(bytes: number): string {
  if (bytes < 1024) {
    return bytes + ' B';
  }
  if (bytes < 1024 * 1024) {
    return (bytes / 1024).toFixed(1) + ' KB';
  }
  return (bytes / 1024 / 1024).toFixed(1) + ' MB';
}
