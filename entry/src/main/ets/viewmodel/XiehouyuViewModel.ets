import { Context } from '@kit.AbilityKit';
import { RawFileUtil } from '../common/utils/RawFileUtil';
import { XiehouyuItem, XiehouyuCategory } from '../model/XiehouyuModels';

export class XiehouyuViewModel {
  private static instance: XiehouyuViewModel | null = null;
  private allItems: XiehouyuItem[] = [];
  private isLoaded: boolean = false;
  private categoryCache: XiehouyuCategory[] = [];
  private categoryMap: Record<string, XiehouyuItem[]> = {};

  private constructor() {}

  static getInstance(): XiehouyuViewModel {
    if (!XiehouyuViewModel.instance) {
      XiehouyuViewModel.instance = new XiehouyuViewModel();
    }
    return XiehouyuViewModel.instance;
  }

  isReady(): boolean {
    return this.isLoaded;
  }

  loadData(context: Context): boolean {
    if (this.isLoaded) {
      return true;
    }
    try {
      let raw: Object[] = RawFileUtil.readJson<Object[]>(context, 'xiehouyu/xiehouyu.json');
      this.allItems = [];
      for (let i = 0; i < raw.length; i++) {
        let obj: Record<string, Object> = raw[i] as Record<string, Object>;
        let item: XiehouyuItem = new XiehouyuItem();
        item.riddle = (obj['riddle'] as string) || '';
        item.answer = (obj['answer'] as string) || '';
        if (item.riddle && item.answer) {
          this.allItems.push(item);
        }
      }
      this.isLoaded = true;
      this.buildCategories();
      console.info('[Xiehouyu] loaded, count=' + this.allItems.length.toString());
      return true;
    } catch (e) {
      console.error('[Xiehouyu] loadData failed: ' + (e as Error).message);
      return false;
    }
  }

  private buildCategories(): void {
    this.categoryMap = {};
    let order: string[] = [];
    for (let i = 0; i < this.allItems.length; i++) {
      let item: XiehouyuItem = this.allItems[i];
      let key: string = this.extractCategoryKey(item.riddle);
      if (!this.categoryMap[key]) {
        this.categoryMap[key] = [];
        order.push(key);
      }
      this.categoryMap[key].push(item);
    }
    this.categoryCache = [];
    for (let i = 0; i < order.length; i++) {
      let key: string = order[i];
      let cat: XiehouyuCategory = new XiehouyuCategory();
      cat.key = key;
      cat.label = this.getCategoryLabel(key);
      cat.items = this.categoryMap[key];
      this.categoryCache.push(cat);
    }
  }

  getCategoryItems(key: string): XiehouyuItem[] {
    if (this.categoryMap && this.categoryMap[key]) {
      return this.categoryMap[key];
    }
    for (let i = 0; i < this.categoryCache.length; i++) {
      if (this.categoryCache[i].key === key) {
        return this.categoryCache[i].items;
      }
    }
    return [];
  }

  private extractCategoryKey(riddle: string): string {
    let separators: string[] = ['、', '，', '——', '—', ',', ' '];
    for (let i = 0; i < separators.length; i++) {
      let idx: number = riddle.indexOf(separators[i]);
      if (idx > 0) {
        return riddle.substring(0, idx);
      }
    }
    return riddle.length > 3 ? riddle.substring(0, 3) : riddle;
  }

  private getCategoryLabel(key: string): string {
    if (key.indexOf('的') > 0) {
      return key.substring(0, key.indexOf('的') + 1) + '...';
    }
    return key.length > 5 ? key.substring(0, 5) + '...' : key;
  }

  search(query: string): XiehouyuItem[] {
    if (!query || !this.isLoaded) {
      return [];
    }
    let q: string = query.trim();
    let results: XiehouyuItem[] = [];
    for (let i = 0; i < this.allItems.length; i++) {
      if (this.allItems[i].riddle.indexOf(q) >= 0 || this.allItems[i].answer.indexOf(q) >= 0) {
        results.push(this.allItems[i]);
        if (results.length >= 200) {
          break;
        }
      }
    }
    return results;
  }

  getCategories(): XiehouyuCategory[] {
    return this.categoryCache;
  }

  getRandomItems(count: number): XiehouyuItem[] {
    if (this.allItems.length === 0) {
      return [];
    }
    let results: XiehouyuItem[] = [];
    let used: Set<number> = new Set();
    let attempts: number = 0;
    while (results.length < count && attempts < count * 3) {
      let idx: number = Math.floor(Math.random() * this.allItems.length);
      if (!used.has(idx)) {
        used.add(idx);
        results.push(this.allItems[idx]);
      }
      attempts++;
    }
    return results;
  }

  getDailyItem(seed: number): XiehouyuItem | null {
    if (this.allItems.length === 0) {
      return null;
    }
    let x: number = Math.sin(seed) * 10000;
    let rand: number = x - Math.floor(x);
    let idx: number = Math.floor(rand * this.allItems.length);
    return this.allItems[idx];
  }
}
