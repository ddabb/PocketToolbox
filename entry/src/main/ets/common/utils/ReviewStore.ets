import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { PoemItem } from '../../model/PoetryModels';

export class SentenceRecord {
  key: string = '';
  poemName: string = '';
  poemAuthor: string = '';
  poemDynasty: string = '';
  raw: string = '';
  wrongChars: number[] = [];
  errCount: number = 0;
  lastWrongAt: number = 0;
  reviewStage: number = 0;
  nextReviewAt: number = 0;
  createdAt: number = 0;
}

export class ReviewStore {
  private static readonly PREFS_NAME: string = 'app_cache';
  private static readonly KEY_RECORDS: string = 'sentence_records';
  private static readonly MAX_RECORDS: number = 300;
  private static readonly STAGE_DAYS: number[] = [1, 2, 4, 7, 15];
  private static readonly DAY_MS: number = 24 * 60 * 60 * 1000;

  static recordResult(context: Context, poem: PoemItem, raw: string, wrongIdx: number[], perfect: boolean):
  SentenceRecord | null {
    if (raw === '') {
      return null;
    }
    let records: SentenceRecord[] = ReviewStore.loadRecords(context);
    let key: string = ReviewStore.buildKey(poem, raw);
    let now: number = new Date().getTime();
    let rec: SentenceRecord | null = null;
    for (let i = 0; i < records.length; i++) {
      if (records[i].key === key) {
        rec = records[i];
        break;
      }
    }
    let isNew: boolean = rec === null;
    if (rec === null) {
      rec = new SentenceRecord();
      rec.key = key;
      rec.poemName = poem.n;
      rec.poemAuthor = poem.a;
      rec.poemDynasty = poem.d;
      rec.raw = raw;
      rec.createdAt = now;
    }
    if (perfect) {
      rec.wrongChars = [];
      let nextStage: number = isNew ? 0 : rec.reviewStage + 1;
      if (nextStage >= ReviewStore.STAGE_DAYS.length) {
        rec.reviewStage = ReviewStore.STAGE_DAYS.length - 1;
        rec.nextReviewAt = 0;
      } else {
        rec.reviewStage = nextStage;
        rec.nextReviewAt = now + ReviewStore.STAGE_DAYS[nextStage] * ReviewStore.DAY_MS;
      }
    } else {
      let merged: Set<number> = new Set<number>(rec.wrongChars);
      for (let i = 0; i < wrongIdx.length; i++) {
        merged.add(wrongIdx[i]);
      }
      let chars: string[] = Array.from(raw);
      let valid: number[] = [];
      let arr: number[] = Array.from(merged);
      for (let i = 0; i < arr.length; i++) {
        if (arr[i] >= 0 && arr[i] < chars.length) {
          valid.push(arr[i]);
        }
      }
      rec.wrongChars = valid;
      rec.errCount = rec.errCount + 1;
      rec.lastWrongAt = now;
      rec.reviewStage = 0;
      rec.nextReviewAt = now + ReviewStore.STAGE_DAYS[0] * ReviewStore.DAY_MS;
    }
    if (isNew) {
      records.push(rec);
    }
    records = ReviewStore.evictIfNeeded(records);
    ReviewStore.saveRecords(context, records);
    return records.length > 0 && records.indexOf(rec) >= 0 ? rec : null;
  }

  static loadRecords(context: Context): SentenceRecord[] {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: ReviewStore.PREFS_NAME });
      let text: string = prefs.getSync(ReviewStore.KEY_RECORDS, '[]') as string;
      let arr: Object[] = (JSON.parse(text) as Object[]) || [];
      let records: SentenceRecord[] = [];
      for (let i = 0; i < arr.length; i++) {
        let obj: Record<string, Object> = arr[i] as Record<string, Object>;
        let rec: SentenceRecord = new SentenceRecord();
        rec.key = (obj['key'] as string) || '';
        rec.poemName = (obj['poemName'] as string) || '';
        rec.poemAuthor = (obj['poemAuthor'] as string) || '';
        rec.poemDynasty = (obj['poemDynasty'] as string) || '';
        rec.raw = (obj['raw'] as string) || '';
        let wc: Object[] = (obj['wrongChars'] as Object[]) || [];
        let wcArr: number[] = [];
        for (let j = 0; j < wc.length; j++) {
          wcArr.push(wc[j] as number);
        }
        rec.wrongChars = wcArr;
        rec.errCount = (obj['errCount'] as number) || 0;
        rec.lastWrongAt = (obj['lastWrongAt'] as number) || 0;
        rec.reviewStage = (obj['reviewStage'] as number) || 0;
        rec.nextReviewAt = (obj['nextReviewAt'] as number) || 0;
        rec.createdAt = (obj['createdAt'] as number) || 0;
        if (rec.key !== '' && rec.raw !== '') {
          records.push(rec);
        }
      }
      return records;
    } catch (e) {
      return [];
    }
  }

  static getMistakes(context: Context): SentenceRecord[] {
    let records: SentenceRecord[] = ReviewStore.loadRecords(context);
    let list: SentenceRecord[] = [];
    for (let i = 0; i < records.length; i++) {
      if (records[i].wrongChars.length > 0) {
        list.push(records[i]);
      }
    }
    list.sort((a: SentenceRecord, b: SentenceRecord): number => b.lastWrongAt - a.lastWrongAt);
    return list;
  }

  static getDueReviews(context: Context): SentenceRecord[] {
    let now: number = new Date().getTime();
    let records: SentenceRecord[] = ReviewStore.loadRecords(context);
    let list: SentenceRecord[] = [];
    for (let i = 0; i < records.length; i++) {
      if (records[i].nextReviewAt > 0 && records[i].nextReviewAt <= now) {
        list.push(records[i]);
      }
    }
    list.sort((a: SentenceRecord, b: SentenceRecord): number => a.nextReviewAt - b.nextReviewAt);
    return list;
  }

  static getDueCount(context: Context): number {
    return ReviewStore.getDueReviews(context).length;
  }

  static getMistakeCount(context: Context): number {
    let records: SentenceRecord[] = ReviewStore.loadRecords(context);
    let count: number = 0;
    for (let i = 0; i < records.length; i++) {
      if (records[i].wrongChars.length > 0) {
        count++;
      }
    }
    return count;
  }

  private static buildKey(poem: PoemItem, raw: string): string {
    return poem.n + '|' + poem.a + '|' + raw;
  }

  private static evictIfNeeded(records: SentenceRecord[]): SentenceRecord[] {
    if (records.length <= ReviewStore.MAX_RECORDS) {
      return records;
    }
    let graduated: SentenceRecord[] = [];
    let rest: SentenceRecord[] = [];
    for (let i = 0; i < records.length; i++) {
      if (records[i].nextReviewAt === 0 && records[i].wrongChars.length === 0) {
        graduated.push(records[i]);
      } else {
        rest.push(records[i]);
      }
    }
    graduated.sort((a: SentenceRecord, b: SentenceRecord): number => a.createdAt - b.createdAt);
    let overflow: number = records.length - ReviewStore.MAX_RECORDS;
    if (graduated.length >= overflow) {
      return rest.concat(graduated.slice(overflow));
    }
    rest.sort((a: SentenceRecord, b: SentenceRecord): number => a.createdAt - b.createdAt);
    return rest.slice(overflow - graduated.length).concat(graduated);
  }

  private static saveRecords(context: Context, records: SentenceRecord[]): void {
    try {
      let arr: Object[] = [];
      for (let i = 0; i < records.length; i++) {
        let rec: SentenceRecord = records[i];
        let obj: Record<string, Object> = {
          'key': rec.key as Object,
          'poemName': rec.poemName as Object,
          'poemAuthor': rec.poemAuthor as Object,
          'poemDynasty': rec.poemDynasty as Object,
          'raw': rec.raw as Object,
          'wrongChars': rec.wrongChars as Object,
          'errCount': rec.errCount as Object,
          'lastWrongAt': rec.lastWrongAt as Object,
          'reviewStage': rec.reviewStage as Object,
          'nextReviewAt': rec.nextReviewAt as Object,
          'createdAt': rec.createdAt as Object
        };
        arr.push(obj);
      }
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: ReviewStore.PREFS_NAME });
      prefs.putSync(ReviewStore.KEY_RECORDS, JSON.stringify(arr));
      prefs.flush();
      let ver: number = (AppStorage.get('ReviewDataVersion') ?? 0) as number;
      AppStorage.setOrCreate('ReviewDataVersion', ver + 1);
    } catch (e) {
      console.error('[ReviewStore] saveRecords failed: ' + (e as Error).message);
    }
  }
}
