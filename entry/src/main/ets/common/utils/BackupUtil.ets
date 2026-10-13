/**
 * 数据备份：DocumentViewPicker 免权限导出/导入 JSON。
 *
 * 2026-10-13 修复（用户反馈：导入有数据的文件后 GIF 制作历史无数据）：
 * 旧版（format 1）只备份 3 个 preferences，GIF 历史（filesDir/gif_history 的 index.json + GIF 文件）
 * 完全不在范围内。现升级 format 2，新增 gifHistory 段（records 索引 + files 文件名→base64 内容），
 * 导出增量写入避免大 JSON 整体驻留内存，导入按「备份优先」全量替换本地 GIF 历史。
 * format 1 旧备份仍可导入（跳过 gifHistory 段）。
 */
import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { GifHistoryStore, GifHistoryRecord } from '../../core/gif/GifHistoryStore';

export class BackupUtil {
  private static readonly PREFS_NAMES: string[] = ['app_cache', 'reading_lists', 'reading_settings'];
  private static readonly FORMAT: number = 2;
  private static readonly APP_ID: string = 'com.ddabb.toolbox';
  private static readonly MAX_IMPORT_BYTES: number = 128 * 1024 * 1024;
  private static readonly WRITE_CHUNK: number = 512 * 1024;

  static buildFileName(): string {
    let d: Date = new Date();
    let p2: (n: number) => string = (n: number): string => n < 10 ? '0' + n.toString() : n.toString();
    return 'PocketToolboxBackup_' + d.getFullYear().toString() + p2(d.getMonth() + 1) + p2(d.getDate()) +
      '_' + p2(d.getHours()) + p2(d.getMinutes()) + p2(d.getSeconds()) + '.json';
  }

  static async exportBackup(context: Context): Promise<string> {
    let saveOptions: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
    saveOptions.newFileNames = [BackupUtil.buildFileName()];
    let docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    let uris: Array<string> = await docPicker.save(saveOptions);
    if (!uris || uris.length === 0) {
      return '';
    }
    let prefsDump: Record<string, Object> = {};
    for (let i = 0; i < BackupUtil.PREFS_NAMES.length; i++) {
      let name: string = BackupUtil.PREFS_NAMES[i];
      let p: preferences.Preferences = preferences.getPreferencesSync(context, { name: name });
      let all: Record<string, preferences.ValueType> = p.getAllSync() as Record<string, preferences.ValueType>;
      let section: Record<string, Object> = {};
      let keys: string[] = Object.keys(all);
      for (let j = 0; j < keys.length; j++) {
        let k: string = keys[j];
        let v: preferences.ValueType = all[k];
        if (typeof v === 'number') {
          section[k] = v as number as Object;
        } else if (typeof v === 'boolean') {
          section[k] = v as boolean as Object;
        } else if (typeof v === 'string') {
          section[k] = v as string as Object;
        } else {
          section[k] = (v as Array<number | string | boolean>) as Object;
        }
      }
      prefsDump[name] = section as Object;
    }
    let payloadHead: Record<string, Object> = {
      'app': BackupUtil.APP_ID as Object,
      'format': BackupUtil.FORMAT as Object,
      'exportedAt': new Date().getTime() as Object,
      'prefs': prefsDump as Object
    };
    let file: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      let headJson: string = JSON.stringify(payloadHead);
      // 去掉结尾 '}'，追加 gifHistory 段后补回
      fileIo.writeSync(file.fd, headJson.substring(0, headJson.length - 1));
      fileIo.writeSync(file.fd, ',"gifHistory":');
      BackupUtil.writeGifHistorySection(context, file.fd);
      fileIo.writeSync(file.fd, '}');
    } finally {
      fileIo.closeSync(file);
    }
    return uris[0];
  }

  /** 增量写入 gifHistory 段：{"records":[...],"files":{"<fileName>":"<base64>"}}（大文件分块写，避免超长字符串） */
  private static writeGifHistorySection(context: Context, fd: number): void {
    let records: GifHistoryRecord[] = GifHistoryStore.loadRecords(context);
    let arr: object[] = [];
    for (let i = 0; i < records.length; i++) {
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
    fileIo.writeSync(fd, '{"records":' + JSON.stringify(arr) + ',"files":{');
    let base64Helper: util.Base64Helper = new util.Base64Helper();
    let written: number = 0;
    for (let i = 0; i < records.length; i++) {
      let rec: GifHistoryRecord = records[i];
      let path: string = GifHistoryStore.historyDir(context) + '/' + rec.fileName;
      if (!fileIo.accessSync(path)) {
        console.warn('[BackupUtil] gif file missing, skip: ' + rec.fileName);
        continue;
      }
      let f: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      try {
        let size: number = fileIo.statSync(f.fd).size;
        let buf: ArrayBuffer = new ArrayBuffer(size);
        fileIo.readSync(f.fd, buf);
        let b64: string = base64Helper.encodeToStringSync(new Uint8Array(buf));
        if (written > 0) {
          fileIo.writeSync(fd, ',');
        }
        fileIo.writeSync(fd, JSON.stringify(rec.fileName) + ':"');
        for (let off: number = 0; off < b64.length; off += BackupUtil.WRITE_CHUNK) {
          let end: number = Math.min(off + BackupUtil.WRITE_CHUNK, b64.length);
          fileIo.writeSync(fd, b64.substring(off, end));
        }
        fileIo.writeSync(fd, '"');
        written++;
      } finally {
        fileIo.closeSync(f);
      }
    }
    fileIo.writeSync(fd, '}}');
  }

  static async importBackup(context: Context): Promise<boolean> {
    let selectOptions: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    selectOptions.maxSelectNumber = 1;
    let docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    let uris: Array<string> = await docPicker.select(selectOptions);
    if (!uris || uris.length === 0) {
      return false;
    }
    let file: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);
    let text: string = '';
    try {
      let size: number = fileIo.statSync(file.fd).size;
      if (size > BackupUtil.MAX_IMPORT_BYTES) {
        throw new Error('backup file too large');
      }
      let buf: ArrayBuffer = new ArrayBuffer(size);
      fileIo.readSync(file.fd, buf);
      let decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      text = decoder.decodeToString(new Uint8Array(buf));
    } finally {
      fileIo.closeSync(file);
    }
    let obj: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
    let fmt: number = obj['format'] as number;
    if ((obj['app'] as string) !== BackupUtil.APP_ID || (fmt !== 1 && fmt !== BackupUtil.FORMAT)) {
      throw new Error('invalid backup format');
    }
    let prefsObj: Record<string, Object> = obj['prefs'] as Record<string, Object>;
    for (let i = 0; i < BackupUtil.PREFS_NAMES.length; i++) {
      let name: string = BackupUtil.PREFS_NAMES[i];
      let section: Object = prefsObj[name];
      if (section === undefined) {
        continue;
      }
      let kv: Record<string, Object> = section as Record<string, Object>;
      let p: preferences.Preferences = preferences.getPreferencesSync(context, { name: name });
      let keys: string[] = Object.keys(kv);
      for (let j = 0; j < keys.length; j++) {
        let k: string = keys[j];
        let v: Object = kv[k];
        if (typeof v === 'number') {
          p.putSync(k, v as number);
        } else if (typeof v === 'boolean') {
          p.putSync(k, v as boolean);
        } else if (typeof v === 'string') {
          p.putSync(k, v as string);
        } else {
          p.putSync(k, v as Array<number | string | boolean>);
        }
      }
      p.flush();
    }
    // format 2 新增：GIF 制作历史恢复（备份优先全量替换；旧版备份无此段则跳过）
    if (fmt >= 2) {
      let gh: Object = obj['gifHistory'];
      if (gh !== undefined) {
        BackupUtil.restoreGifHistory(context, gh as Record<string, Object>);
      }
    }
    return true;
  }

  /** 全量替换本地 GIF 制作历史：先落索引（replaceAll 内部清空本地），再写文件本体 */
  private static restoreGifHistory(context: Context, gh: Record<string, Object>): void {
    let records: GifHistoryRecord[] = [];
    let recsObj: Object = gh['records'];
    if (recsObj !== undefined) {
      let raw: Object[] = recsObj as Object[];
      for (let i: number = 0; i < raw.length; i++) {
        let o: Record<string, Object> = raw[i] as Record<string, Object>;
        let r: GifHistoryRecord = new GifHistoryRecord();
        r.id = o['id'] as string;
        r.fileName = o['fileName'] as string;
        r.sizeBytes = Number(o['sizeBytes']);
        r.exportedAt = Number(o['exportedAt']);
        r.width = Number(o['width']);
        r.height = Number(o['height']);
        r.frameCount = Number(o['frameCount']);
        r.paramsText = o['paramsText'] as string;
        if (typeof r.id === 'string' && r.id.length > 0 && typeof r.fileName === 'string' && r.fileName.length > 0) {
          records.push(r);
        }
      }
    }
    GifHistoryStore.replaceAll(context, records);
    let filesObj: Object = gh['files'];
    if (filesObj !== undefined) {
      let kv: Record<string, Object> = filesObj as Record<string, Object>;
      let keys: string[] = Object.keys(kv);
      let base64Helper: util.Base64Helper = new util.Base64Helper();
      let okCount: number = 0;
      for (let i: number = 0; i < keys.length; i++) {
        let name: string = keys[i];
        try {
          let bytes: Uint8Array = base64Helper.decodeSync(kv[name] as string);
          let dest: string = GifHistoryStore.historyDir(context) + '/' + name;
          let f: fileIo.File = fileIo.openSync(dest, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
          try {
            let ab: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
            fileIo.writeSync(f.fd, ab);
          } finally {
            fileIo.closeSync(f);
          }
          okCount++;
        } catch (e) {
          console.error('[BackupUtil] restore gif file failed: ' + (e as Error).message);
        }
      }
      console.info('[BackupUtil] gif history restored: records=' + records.length.toString() + ' files=' + okCount.toString());
    }
  }
}
