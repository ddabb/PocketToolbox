import { Context } from '@kit.AbilityKit';
import { RawFileUtil } from '../common/utils/RawFileUtil';
import { PoetItem, DynastyItem, FullTextEntry, PoetryIndexData, PoemItem, PoetDetail, SearchResultItem } from '../model/PoetryModels';

export class PoetryViewModel {
  private static instance: PoetryViewModel | null = null;
  private indexData: PoetryIndexData | null = null;
  private poetDetailCache: Record<string, PoetDetail> = {};
  private allPoets: PoetItem[] = [];
  private dynasties: string[] = [];
  private ftEntries: FullTextEntry[] = [];
  private isLoaded: boolean = false;

  private constructor() {}

  static getInstance(): PoetryViewModel {
    if (!PoetryViewModel.instance) {
      PoetryViewModel.instance = new PoetryViewModel();
    }
    return PoetryViewModel.instance;
  }

  isDataLoaded(): boolean {
    return this.isLoaded;
  }

  getDynasties(): string[] {
    return this.dynasties;
  }

  loadIndex(context: Context): boolean {
    try {
      let raw: Object = RawFileUtil.readJson<Object>(context, 'poetry/index.json');
      let indexObj: PoetryIndexData = this.parseIndexResponse(raw);
      this.applyIndexData(indexObj);
      return true;
    } catch (e) {
      console.error('[Poetry] loadIndex failed: ' + (e as Error).message);
      return false;
    }
  }

  private parseIndexResponse(raw: Object): PoetryIndexData {
    let result: PoetryIndexData = new PoetryIndexData();
    let rawObj: Record<string, Object> = raw as Record<string, Object>;

    let poetsRaw: Object[] = rawObj['poets'] as Object[];
    result.poets = [];
    for (let i = 0; i < poetsRaw.length; i++) {
      let p: Record<string, Object> = poetsRaw[i] as Record<string, Object>;
      let item: PoetItem = new PoetItem();
      item.n = (p['n'] as string) || '';
      item.d = (p['d'] as string) || '';
      item.pc = (p['pc'] as number) || 0;
      item.i = (p['i'] as string) || '';
      result.poets.push(item);
    }

    let dynastiesRaw: Object[] = rawObj['dynasties'] as Object[];
    result.dynasties = [];
    for (let i = 0; i < dynastiesRaw.length; i++) {
      let d: Record<string, Object> = dynastiesRaw[i] as Record<string, Object>;
      let item: DynastyItem = new DynastyItem();
      item.name = (d['name'] as string) || '';
      result.dynasties.push(item);
    }

    let ftRaw: Object[] = (rawObj['ftEntry'] as Object[]) || [];
    result.ftEntry = [];
    for (let i = 0; i < ftRaw.length; i++) {
      let f: Record<string, Object> = ftRaw[i] as Record<string, Object>;
      let item: FullTextEntry = new FullTextEntry();
      item.t = (f['t'] as string) || '';
      item.a = (f['a'] as string) || '';
      item.d = (f['d'] as string) || '';
      result.ftEntry.push(item);
    }

    return result;
  }

  private static readonly DYNASTY_ORDER: string[] = [
    '先秦', '汉代', '三国两晋', '南北朝', '隋代', '唐代', '宋代', '元代', '明代', '清代', '近现代'
  ];

  private applyIndexData(data: PoetryIndexData): void {
    this.indexData = data;
    this.allPoets = data.poets;
    this.ftEntries = data.ftEntry;
    this.isLoaded = true;

    let dynSet: Set<string> = new Set();
    for (let i = 0; i < data.dynasties.length; i++) {
      let name: string = data.dynasties[i].name;
      if (name) {
        dynSet.add(name);
      }
    }
    let sorted: string[] = [];
    for (let i = 0; i < PoetryViewModel.DYNASTY_ORDER.length; i++) {
      let d: string = PoetryViewModel.DYNASTY_ORDER[i];
      if (dynSet.has(d)) {
        sorted.push(d);
      }
    }
    dynSet.forEach((d: string) => {
      if (sorted.indexOf(d) < 0) {
        sorted.push(d);
      }
    });
    this.dynasties = sorted;
    console.info('[Poetry] dynasties sorted: ' + sorted.join(', '));
  }

  getPoetsByPage(page: number, pageSize: number): PoetItem[] {
    let start: number = page * pageSize;
    let end: number = Math.min(start + pageSize, this.allPoets.length);
    if (start >= this.allPoets.length) {
      return [];
    }
    return this.allPoets.slice(start, end);
  }

  getFilteredPoets(dynasty: string): PoetItem[] {
    if (dynasty === '全部') {
      return this.allPoets;
    }
    let result: PoetItem[] = [];
    for (let i = 0; i < this.allPoets.length; i++) {
      if (this.allPoets[i].d === dynasty) {
        result.push(this.allPoets[i]);
      }
    }
    return result;
  }

  getFilteredPoetsByPage(dynasty: string, page: number, pageSize: number): PoetItem[] {
    let filtered: PoetItem[] = this.getFilteredPoets(dynasty);
    let start: number = page * pageSize;
    let end: number = Math.min(start + pageSize, filtered.length);
    if (start >= filtered.length) {
      return [];
    }
    return filtered.slice(start, end);
  }

  hasMoreFilteredPoets(dynasty: string, currentPage: number, pageSize: number): boolean {
    let filtered: PoetItem[] = this.getFilteredPoets(dynasty);
    return (currentPage + 1) * pageSize < filtered.length;
  }

  searchPoets(query: string): PoetItem[] {
    if (!query) {
      return [];
    }
    let result: PoetItem[] = [];
    for (let i = 0; i < this.allPoets.length; i++) {
      let name: string = this.allPoets[i].n;
      if (name === query || name.indexOf(query) === 0) {
        result.push(this.allPoets[i]);
      }
    }
    return result;
  }

  searchFullText(query: string): FullTextEntry[] {
    if (!query || !this.ftEntries) {
      return [];
    }
    let result: FullTextEntry[] = [];
    for (let i = 0; i < this.ftEntries.length; i++) {
      let entry: FullTextEntry = this.ftEntries[i];
      if (entry.t.indexOf(query) >= 0 || entry.a.indexOf(query) >= 0) {
        result.push(entry);
        if (result.length >= 100) {
          break;
        }
      }
    }
    return result;
  }

  buildSearchResults(query: string, dynasty: string): SearchResultItem[] {
    let filterByDynasty: boolean = dynasty !== '全部';
    let results: SearchResultItem[] = [];
    let matchedPoets: PoetItem[] = this.searchPoets(query);
    for (let i = 0; i < matchedPoets.length; i++) {
      let poet: PoetItem = matchedPoets[i];
      if (filterByDynasty && poet.d !== dynasty) {
        continue;
      }
      let item: SearchResultItem = new SearchResultItem();
      item.type = 'poet';
      item.title = poet.n;
      item.subtitle = poet.d + ' \u00B7 ' + poet.pc.toString() + '首';
      item.poetInitial = poet.i;
      item.poetDynasty = poet.d;
      results.push(item);
    }

    let matchedPoems: FullTextEntry[] = this.searchFullText(query);
    for (let i = 0; i < matchedPoems.length; i++) {
      let poem: FullTextEntry = matchedPoems[i];
      if (filterByDynasty && poem.d !== dynasty) {
        continue;
      }
      let item: SearchResultItem = new SearchResultItem();
      item.type = 'poem';
      item.title = poem.t;
      item.subtitle = poem.a + ' \u00B7 ' + poem.d;
      item.poetInitial = '';
      item.poetDynasty = poem.d;
      item.poetName = poem.a;
      results.push(item);
    }

    return results;
  }

  loadPoetDetail(context: Context, poetName: string, initial: string, dynasty: string): PoetDetail {
    let cacheKey: string = initial + '_' + poetName;
    if (this.poetDetailCache[cacheKey]) {
      console.info('[Poetry] loadPoetDetail cache hit: ' + poetName);
      return this.poetDetailCache[cacheKey];
    }

    try {
      let path: string = 'poetry/poet/' + initial + '.json';
      console.info('[Poetry] loadPoetDetail reading: ' + path + ', looking for: ' + poetName);
      let raw: Object[] = RawFileUtil.readJson<Object[]>(context, path);

      for (let i = 0; i < raw.length; i++) {
        let poetObj: Record<string, Object> = raw[i] as Record<string, Object>;
        let name: string = (poetObj['n'] as string) || '';
        if (name !== poetName) {
          continue;
        }

        let detail: PoetDetail = new PoetDetail();
        detail.name = name;
        detail.dynasty = (poetObj['d'] as string) || dynasty;
        detail.desc = (poetObj['desc'] as string) || '';
        detail.initial = initial;

        let poemsRaw: Object[] = (poetObj['p'] as Object[]) || [];
        detail.poems = [];
        for (let j = 0; j < poemsRaw.length; j++) {
          let pObj: Record<string, Object> = poemsRaw[j] as Record<string, Object>;
          let poem: PoemItem = new PoemItem();
          poem.n = (pObj['n'] as string) || '';
          poem.c = (pObj['c'] as string) || '';
          poem.f = (pObj['f'] as string) || '';
          poem.a = name;
          poem.d = detail.dynasty;
          detail.poems.push(poem);
        }

        this.poetDetailCache[cacheKey] = detail;
        console.info('[Poetry] loadPoetDetail ok: ' + poetName + ', poems=' + detail.poems.length.toString());
        return detail;
      }

      console.warn('[Poetry] loadPoetDetail poet not found: ' + poetName + ' in ' + path);
      let fallback: PoetDetail = new PoetDetail();
      fallback.name = poetName;
      fallback.dynasty = dynasty;
      fallback.desc = '';
      fallback.initial = initial;
      fallback.poems = [];
      return fallback;
    } catch (e) {
      console.error('[Poetry] loadPoetDetail failed: poet=' + poetName + ', error=' + (e as Error).message);
      let fallback: PoetDetail = new PoetDetail();
      fallback.name = poetName;
      fallback.dynasty = dynasty;
      fallback.desc = '';
      fallback.initial = initial;
      fallback.poems = [];
      return fallback;
    }
  }

  parsePoetDetailFromParam(raw: Record<string, Object>): PoetDetail {
    let detail: PoetDetail = new PoetDetail();
    detail.name = (raw['name'] as string) || '';
    detail.dynasty = (raw['dynasty'] as string) || '';
    detail.desc = (raw['desc'] as string) || '';
    detail.initial = (raw['initial'] as string) || '';
    let poemsRaw: Object[] = (raw['poems'] as Object[]) || [];
    detail.poems = [];
    for (let i: number = 0; i < poemsRaw.length; i++) {
      let obj: Record<string, Object> = poemsRaw[i] as Record<string, Object>;
      let item: PoemItem = new PoemItem();
      item.n = (obj['n'] as string) || '';
      item.c = (obj['c'] as string) || '';
      item.f = (obj['f'] as string) || '';
      item.a = (obj['a'] as string) || '';
      item.d = (obj['d'] as string) || '';
      detail.poems.push(item);
    }
    return detail;
  }

  parsePoemFromParam(raw: Record<string, Object>): PoemItem {
    let item: PoemItem = new PoemItem();
    item.n = (raw['n'] as string) || '';
    item.c = (raw['c'] as string) || '';
    item.f = (raw['f'] as string) || '';
    item.a = (raw['a'] as string) || '';
    item.d = (raw['d'] as string) || '';
    return item;
  }

  getPoetByName(name: string): PoetItem | null {
    for (let i = 0; i < this.allPoets.length; i++) {
      if (this.allPoets[i].n === name) {
        return this.allPoets[i];
      }
    }
    return null;
  }
}
