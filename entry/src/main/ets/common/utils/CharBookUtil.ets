import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';

export class CharBookUtil {
  private static readonly PREFS_NAME: string = 'app_cache';
  private static readonly KEY: string = 'char_book';
  private static readonly SEPARATOR: string = '|';
  private static readonly MAX_CHARS: number = 200;

  static load(context: Context): string[] {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: CharBookUtil.PREFS_NAME });
      let raw: string = prefs.getSync(CharBookUtil.KEY, '') as string;
      if (!raw) {
        return [];
      }
      let parts: string[] = raw.split(CharBookUtil.SEPARATOR);
      let chars: string[] = [];
      for (let i = 0; i < parts.length; i++) {
        if (parts[i]) {
          chars.push(parts[i]);
        }
      }
      return chars;
    } catch (e) {
      return [];
    }
  }

  static addChars(context: Context, chars: string[]): number {
    let existing: string[] = CharBookUtil.load(context);
    let set: Set<string> = new Set<string>(existing);
    let added: number = 0;
    for (let i = 0; i < chars.length; i++) {
      let ch: string = chars[i];
      if (!ch || set.has(ch)) {
        continue;
      }
      if (existing.length >= CharBookUtil.MAX_CHARS) {
        break;
      }
      existing.push(ch);
      set.add(ch);
      added++;
    }
    if (added > 0) {
      CharBookUtil.save(context, existing);
    }
    return added;
  }

  static removeChar(context: Context, ch: string): void {
    let existing: string[] = CharBookUtil.load(context);
    let next: string[] = [];
    for (let i = 0; i < existing.length; i++) {
      if (existing[i] !== ch) {
        next.push(existing[i]);
      }
    }
    CharBookUtil.save(context, next);
  }

  static clear(context: Context): void {
    CharBookUtil.save(context, []);
  }

  static extractChars(content: string): string[] {
    let chars: string[] = [];
    let seen: Set<string> = new Set<string>();
    for (let i = 0; i < content.length; i++) {
      let ch: string = content.charAt(i);
      let code: number = content.charCodeAt(i);
      let isCjk: boolean = (code >= 0x4E00 && code <= 0x9FFF) || (code >= 0x3400 && code <= 0x4DBF);
      if (!isCjk || seen.has(ch)) {
        continue;
      }
      seen.add(ch);
      chars.push(ch);
    }
    return chars;
  }

  private static save(context: Context, chars: string[]): void {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: CharBookUtil.PREFS_NAME });
      prefs.putSync(CharBookUtil.KEY, chars.join(CharBookUtil.SEPARATOR));
      prefs.flushSync();
    } catch (e) {
      console.error('[CharBook] save failed: ' + (e as Error).message);
    }
  }
}
