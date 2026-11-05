import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';

export class DateDiffRecord {
  start: string = '';
  end: string = '';
  days: number = 0;
  ts: number = 0;

  constructor(start: string, end: string, days: number, ts: number) {
    this.start = start;
    this.end = end;
    this.days = days;
    this.ts = ts;
  }
}

export class DateDiffHistoryUtil {
  private static readonly PREFS_NAME: string = 'app_cache';
  private static readonly KEY_HISTORY: string = 'date_diff_history';
  private static readonly MAX_COUNT: number = 10;

  static load(context: Context): DateDiffRecord[] {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: DateDiffHistoryUtil.PREFS_NAME });
      let json: string = prefs.getSync(DateDiffHistoryUtil.KEY_HISTORY, '') as string;
      if (!json) {
        return [];
      }
      let raw: Object[] = JSON.parse(json) as Object[];
      let records: DateDiffRecord[] = [];
      for (let i = 0; i < raw.length; i++) {
        let obj: Record<string, Object> = raw[i] as Record<string, Object>;
        let start: string = (obj['start'] as string) || '';
        let end: string = (obj['end'] as string) || '';
        if (!start || !end) {
          continue;
        }
        let days: number = (obj['days'] as number) || 0;
        let ts: number = (obj['ts'] as number) || 0;
        records.push(new DateDiffRecord(start, end, days, ts));
      }
      return records;
    } catch (e) {
      return [];
    }
  }

  static record(context: Context, start: string, end: string, days: number): DateDiffRecord[] {
    let list: DateDiffRecord[] = DateDiffHistoryUtil.load(context);
    let next: DateDiffRecord[] = [new DateDiffRecord(start, end, days, Date.now())];
    for (let i = 0; i < list.length; i++) {
      let r: DateDiffRecord = list[i];
      if (r.start !== start || r.end !== end) {
        next.push(r);
      }
    }
    if (next.length > DateDiffHistoryUtil.MAX_COUNT) {
      next = next.slice(0, DateDiffHistoryUtil.MAX_COUNT);
    }
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: DateDiffHistoryUtil.PREFS_NAME });
      prefs.putSync(DateDiffHistoryUtil.KEY_HISTORY, JSON.stringify(next));
      prefs.flushSync();
    } catch (e) {
      console.warn('[DateDiff] save history failed');
    }
    return next;
  }

  static clear(context: Context): DateDiffRecord[] {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: DateDiffHistoryUtil.PREFS_NAME });
      prefs.putSync(DateDiffHistoryUtil.KEY_HISTORY, '[]');
      prefs.flushSync();
    } catch (e) {
      console.warn('[DateDiff] clear history failed');
    }
    return [];
  }
}
