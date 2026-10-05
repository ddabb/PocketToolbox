import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

export class BackupUtil {
  private static readonly PREFS_NAMES: string[] = ['app_cache', 'reading_lists', 'reading_settings'];
  private static readonly FORMAT: number = 1;
  private static readonly APP_ID: string = 'com.ddabb.toolbox';

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
    let payload: Record<string, Object> = {
      'app': BackupUtil.APP_ID as Object,
      'format': BackupUtil.FORMAT as Object,
      'exportedAt': new Date().getTime() as Object,
      'prefs': prefsDump as Object
    };
    let file: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, JSON.stringify(payload));
    } finally {
      fileIo.closeSync(file);
    }
    return uris[0];
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
      let buf: ArrayBuffer = new ArrayBuffer(size);
      fileIo.readSync(file.fd, buf);
      let decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      text = decoder.decodeToString(new Uint8Array(buf));
    } finally {
      fileIo.closeSync(file);
    }
    let obj: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
    if ((obj['app'] as string) !== BackupUtil.APP_ID || (obj['format'] as number) !== BackupUtil.FORMAT) {
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
    return true;
  }
}
