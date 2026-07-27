import { Context } from '@kit.AbilityKit';
import { RawFileUtil } from '../common/utils/RawFileUtil';
import { SolitaireResult, IdiomDetailItem, IdiomQueryResultItem } from '../model/IdiomModels';

export class IdiomViewModel {
  private static instance: IdiomViewModel | null = null;
  private firstIndexKeys: string[] = [];
  private firstIndexValues: string[][] = [];
  private lastIndexKeys: string[] = [];
  private lastIndexValues: string[][] = [];
  private wordToFirstPy: Record<string, string> = {};
  private wordToLastPy: Record<string, string> = {};
  private allWords: string[] = [];
  private isFirstReady: boolean = false;
  private isLastReady: boolean = false;
  private letterCache: Record<string, IdiomDetailItem[]> = {};
  private idiomFullCache: Record<string, IdiomDetailItem> = {};
  private isFullLoaded: boolean = false;
  private firstLettersCache: string[] | null = null;
  private normalizedPyCache: Record<string, string[]> = {};

  private constructor() {}

  static getInstance(): IdiomViewModel {
    if (!IdiomViewModel.instance) {
      IdiomViewModel.instance = new IdiomViewModel();
    }
    return IdiomViewModel.instance;
  }

  isFirstIndexReady(): boolean {
    return this.isFirstReady;
  }

  isLastIndexReady(): boolean {
    return this.isLastReady;
  }

  isDataLoaded(): boolean {
    return this.isFirstReady;
  }

  loadData(context: Context): boolean {
    if (this.isFirstReady) {
      return true;
    }
    let firstOk: boolean = this.loadFirstIndex(context);
    if (firstOk) {
      this.isFirstReady = true;
    }
    let lastOk: boolean = this.loadLastIndex(context);
    if (lastOk) {
      this.isLastReady = true;
    }
    return firstOk;
  }

  private loadFirstIndex(context: Context): boolean {
    try {
      let raw: Object = RawFileUtil.readJson<Object>(context, 'idiom-solitaire/idiom-first-full-index.json');
      this.applyFirstIndex(raw);
      return true;
    } catch (e) {
      console.error('[Idiom] loadFirstIndex failed: ' + (e as Error).message);
      return false;
    }
  }

  private loadLastIndex(context: Context): boolean {
    try {
      let raw: Object = RawFileUtil.readJson<Object>(context, 'idiom-solitaire/idiom-last-index.json');
      this.applyLastIndex(raw);
      return true;
    } catch (e) {
      console.error('[Idiom] loadLastIndex failed: ' + (e as Error).message);
      return false;
    }
  }

  private ensureFullData(context: Context): void {
    if (this.isFullLoaded) {
      return;
    }
    try {
      console.info('[Idiom] loading idiom.json for full data...');
      let raw: Object[] = RawFileUtil.readJson<Object[]>(context, 'idiom-solitaire/idiom.json');
      for (let i = 0; i < raw.length; i++) {
        let obj: Record<string, Object> = raw[i] as Record<string, Object>;
        let word: string = (obj['word'] as string) || '';
        let item: IdiomDetailItem = new IdiomDetailItem();
        item.word = word;
        item.pinyin = (obj['pinyin'] as string) || '';
        item.explanation = (obj['explanation'] as string) || '';
        item.derivation = (obj['derivation'] as string) || '';
        item.example = (obj['example'] as string) || '';
        this.idiomFullCache[word] = item;
        this.normalizedPyCache[word] = this.normalizePinyinToSyllables(item.pinyin);
      }
      this.isFullLoaded = true;
      console.info('[Idiom] idiom.json loaded, count=' + raw.length.toString());
    } catch (e) {
      console.error('[Idiom] loadFullData failed: ' + (e as Error).message);
    }
  }

  private applyFirstIndex(raw: Object): void {
    let obj: Record<string, Object> = raw as Record<string, Object>;
    let keys: string[] = Object.keys(obj);
    this.firstIndexKeys = [];
    this.firstIndexValues = [];
    this.wordToFirstPy = {};
    this.allWords = [];

    for (let i = 0; i < keys.length; i++) {
      let py: string = keys[i];
      let arr: Object[] = obj[py] as Object[];
      let words: string[] = [];
      for (let j = 0; j < arr.length; j++) {
        let w: string = arr[j] as string;
        words.push(w);
        if (!this.wordToFirstPy[w]) {
          this.wordToFirstPy[w] = py;
        }
        if (this.allWords.indexOf(w) < 0) {
          this.allWords.push(w);
        }
      }
      this.firstIndexKeys.push(py);
      this.firstIndexValues.push(words);
    }
  }

  private applyLastIndex(raw: Object): void {
    let obj: Record<string, Object> = raw as Record<string, Object>;
    let keys: string[] = Object.keys(obj);
    this.lastIndexKeys = [];
    this.lastIndexValues = [];
    this.wordToLastPy = {};

    for (let i = 0; i < keys.length; i++) {
      let py: string = keys[i];
      let arr: Object[] = obj[py] as Object[];
      let words: string[] = [];
      for (let j = 0; j < arr.length; j++) {
        let w: string = arr[j] as string;
        words.push(w);
        this.wordToLastPy[w] = py;
      }
      this.lastIndexKeys.push(py);
      this.lastIndexValues.push(words);
    }
  }

  hasWord(word: string): boolean {
    return this.allWords.indexOf(word) >= 0;
  }

  private getCandidates(pinyin: string): string[] {
    for (let i = 0; i < this.firstIndexKeys.length; i++) {
      if (this.firstIndexKeys[i] === pinyin) {
        return this.firstIndexValues[i];
      }
    }
    return [];
  }

  private getReverseCandidates(pinyin: string): string[] {
    for (let i = 0; i < this.lastIndexKeys.length; i++) {
      if (this.lastIndexKeys[i] === pinyin) {
        return this.lastIndexValues[i];
      }
    }
    return [];
  }

  querySolitaire(word: string, mode: string): SolitaireResult {
    let result: SolitaireResult = new SolitaireResult();
    result.candidates = [];
    result.error = '';
    result.lastIndexLoading = false;

    if (!this.isFirstReady) {
      result.error = '数据加载中\u2026';
      result.lastIndexLoading = !this.isLastReady;
      return result;
    }

    if (!this.hasWord(word)) {
      result.error = '该成语不在词库中';
      return result;
    }

    if (mode === 'reverse') {
      if (!this.isLastReady) {
        result.error = '数据加载中\u2026';
        result.lastIndexLoading = true;
        return result;
      }
      let fp: string = this.wordToFirstPy[word] || '';
      result.candidates = fp ? this.getReverseCandidates(fp) : [];
    } else {
      let lp: string = this.wordToLastPy[word] || '';
      result.candidates = lp ? this.getCandidates(lp) : [];
    }

    return result;
  }

  fuzzySearch(query: string): string[] {
    if (!query || this.allWords.length === 0) {
      return [];
    }
    let q: string = query.trim();
    let results: string[] = [];
    for (let i = 0; i < this.allWords.length; i++) {
      if (this.allWords[i].indexOf(q) >= 0) {
        results.push(this.allWords[i]);
        if (results.length >= 200) {
          break;
        }
      }
    }
    return results;
  }

  private pinyinCacheQuery: string = '';
  private pinyinCacheWords: string[] = [];
  private pinyinCachePinyins: string[] = [];

  searchByPinyinTotal(query: string): number {
    this.ensurePinyinCache(query);
    return this.pinyinCacheWords.length;
  }

  searchByPinyin(query: string, offset: number = 0, limit: number = 100): IdiomDetailItem[] {
    this.ensurePinyinCache(query);
    let end: number = Math.min(offset + limit, this.pinyinCacheWords.length);
    let results: IdiomDetailItem[] = [];
    for (let i: number = offset; i < end; i++) {
      let item: IdiomDetailItem = new IdiomDetailItem();
      item.word = this.pinyinCacheWords[i];
      item.pinyin = this.pinyinCachePinyins[i];
      results.push(item);
    }
    console.info('[Idiom] searchByPinyin q=' + query + ', offset=' + offset.toString() + ', returned=' + results.length.toString() + ', total=' + this.pinyinCacheWords.length.toString());
    return results;
  }

  private ensurePinyinCache(query: string): void {
    let q: string = (query || '').trim().toLowerCase();
    if (this.pinyinCacheQuery === q) {
      return;
    }
    this.pinyinCacheQuery = q;
    this.pinyinCacheWords = [];
    this.pinyinCachePinyins = [];
    if (!q || !this.isFirstReady) {
      return;
    }
    let chineseRegex: RegExp = new RegExp('[\\u4e00-\\u9fa5]');
    if (chineseRegex.test(q)) {
      let m: RegExpMatchArray | null = q.match(/[\u4e00-\u9fa5]/);
      let ch: string = m ? m[0] : q;
      let ctx: Context | null = this.getCachedContext();
      for (let i: number = 0; i < this.allWords.length; i++) {
        let word: string = this.allWords[i];
        if (word.indexOf(ch) >= 0) {
          this.pinyinCacheWords.push(word);
          this.pinyinCachePinyins.push(this.getFullPinyin(word, ctx));
        }
      }
      return;
    }
    let syllables: string[] = this.splitPinyin(q);
    if (syllables.length === 0) {
      return;
    }
    if (syllables.length === 1) {
      let firstPy: string = syllables[0];
      let ctx: Context | null = this.getCachedContext();
      this.ensureFullData(ctx as Context);
      for (let i = 0; i < this.firstIndexKeys.length; i++) {
        if (this.firstIndexKeys[i] === firstPy) {
          let arr: string[] = this.firstIndexValues[i];
          for (let j = 0; j < arr.length; j++) {
            let word: string = arr[j];
            this.pinyinCacheWords.push(word);
            let detail = this.idiomFullCache[word];
            this.pinyinCachePinyins.push(detail ? detail.pinyin : firstPy);
          }
        }
      }
      return;
    }
    let ctx: Context | null = this.getCachedContext();
    this.ensureFullData(ctx as Context);
    for (let i: number = 0; i < this.allWords.length; i++) {
      let word: string = this.allWords[i];
      let npy: string[] = this.getNormalizedPinyin(word);
      if (this.pinyinMatches(npy, syllables)) {
        let detail = this.idiomFullCache[word];
        this.pinyinCacheWords.push(word);
        this.pinyinCachePinyins.push(detail ? detail.pinyin : (this.wordToFirstPy[word] || ''));
      }
    }
  }

  private normalizePinyinToSyllables(raw: string): string[] {
    if (!raw) {
      return [];
    }
    let s: string = raw.toLowerCase();
    s = s
      .replace(/[āáǎà]/g, 'a')
      .replace(/[ēéěè]/g, 'e')
      .replace(/[īíǐì]/g, 'i')
      .replace(/[ōóǒò]/g, 'o')
      .replace(/[ūúǔù]/g, 'u')
      .replace(/[ǖǘǚǜ]/g, 'ü')
      .replace(/[ńň]/g, 'n')
      .replace(/v/g, 'ü');
    let parts: string[] = s.split(/\s+/);
    let result: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      if (parts[i].length > 0) {
        result.push(parts[i]);
      }
    }
    return result;
  }

  private getNormalizedPinyin(word: string): string[] {
    if (this.normalizedPyCache[word]) {
      return this.normalizedPyCache[word];
    }
    let detail = this.idiomFullCache[word];
    let raw: string = detail ? detail.pinyin : (this.wordToFirstPy[word] || '');
    let npy: string[] = this.normalizePinyinToSyllables(raw);
    this.normalizedPyCache[word] = npy;
    return npy;
  }

  private searchByChinese(ch: string): IdiomDetailItem[] {
    let results: IdiomDetailItem[] = [];
    let limit: number = 100;
    let ctx: Context | null = this.getCachedContext();
    for (let i: number = 0; i < this.allWords.length && results.length < limit; i++) {
      let word: string = this.allWords[i];
      if (word.indexOf(ch) >= 0) {
        let item: IdiomDetailItem = new IdiomDetailItem();
        item.word = word;
        item.pinyin = this.getFullPinyin(word, ctx);
        results.push(item);
      }
    }
    console.info('[Idiom] searchByChinese ch=' + ch + ', results=' + results.length.toString());
    return results;
  }

  private splitPinyin(input: string): string[] {
    let result: string[] = [];
    let i: number = 0;
    while (i < input.length) {
      let matched: string = '';
      for (let len: number = Math.min(6, input.length - i); len >= 1; len--) {
        let sub: string = input.substring(i, i + len);
        let isKey: boolean = false;
        for (let k: number = 0; k < this.firstIndexKeys.length; k++) {
          if (this.firstIndexKeys[k] === sub) {
            isKey = true;
            break;
          }
        }
        if (isKey) {
          matched = sub;
          break;
        }
      }
      if (matched.length > 0) {
        result.push(matched);
        i += matched.length;
      } else {
        if (result.length > 0) {
          result[result.length - 1] = result[result.length - 1] + input.charAt(i);
        } else {
          result.push(input.charAt(i));
        }
        i++;
      }
    }
    return result;
  }

  private getFullPinyin(word: string, context: Context | null): string {
    if (context) {
      let detail: IdiomDetailItem | null = this.findIdiomDetail(context, word);
      if (detail && detail.pinyin) {
        return detail.pinyin.toLowerCase().replace(new RegExp('\\s+', 'g'), '');
      }
    }
    return this.wordToFirstPy[word] || '';
  }

  // 将成语转为可直接录入拼音搜索框的查询串（去声调、去空格，如 yixinyiyi）
  getPinyinSearchQuery(word: string, context: Context | null): string {
    let raw: string = this.getFullPinyin(word, context);
    if (!raw) {
      return word;
    }
    let syls: string[] = this.normalizePinyinToSyllables(raw);
    return syls.join('');
  }

  private pinyinMatches(fullSyllables: string[], syllables: string[]): boolean {
    if (syllables.length === 0 || fullSyllables.length < syllables.length) {
      return false;
    }
    for (let start: number = 0; start <= fullSyllables.length - syllables.length; start++) {
      let ok: boolean = true;
      for (let k: number = 0; k < syllables.length; k++) {
        if (fullSyllables[start + k] !== syllables[k].toLowerCase()) {
          ok = false;
          break;
        }
      }
      if (ok) {
        return true;
      }
    }
    return false;
  }

  private cachedContext: Context | null = null;

  private getCachedContext(): Context | null {
    return this.cachedContext;
  }

  setContext(context: Context): void {
    this.cachedContext = context;
  }

  getFirstLetter(word: string): string {
    let py: string = this.wordToFirstPy[word] || '';
    if (py.length > 0) {
      return py.charAt(0);
    }
    return '';
  }

  getFirstLetters(): string[] {
    if (this.firstLettersCache !== null) {
      return this.firstLettersCache;
    }
    let letters: Set<string> = new Set();
    for (let i = 0; i < this.allWords.length; i++) {
      let py: string = this.wordToFirstPy[this.allWords[i]] || '';
      if (py.length > 0) {
        letters.add(py.charAt(0));
      }
    }
    let result: string[] = [];
    let order: string = 'abcdefghijklmnopqrstuvwxyz';
    for (let i = 0; i < order.length; i++) {
      let ch: string = order.charAt(i);
      if (letters.has(ch)) {
        result.push(ch);
      }
    }
    this.firstLettersCache = result;
    return result;
  }

  getIdiomsByLetter(context: Context, letter: string): IdiomDetailItem[] {
    if (this.letterCache[letter]) {
      return this.letterCache[letter];
    }
    try {
      let path: string = 'idiom-solitaire/letter/' + letter + '.json';
      let raw: Object[] = RawFileUtil.readJson<Object[]>(context, path);
      let items: IdiomDetailItem[] = this.parseIdiomDetails(raw);
      this.letterCache[letter] = items;
      console.info('[Idiom] getIdiomsByLetter letter=' + letter + ', count=' + items.length.toString());
      return items;
    } catch (e) {
      console.error('[Idiom] getIdiomsByLetter failed: ' + (e as Error).message);
      return [];
    }
  }

  private parseIdiomDetails(raw: Object[]): IdiomDetailItem[] {
    let result: IdiomDetailItem[] = [];
    for (let i = 0; i < raw.length; i++) {
      let obj: Record<string, Object> = raw[i] as Record<string, Object>;
      let item: IdiomDetailItem = new IdiomDetailItem();
      item.word = (obj['w'] as string) || '';
      item.pinyin = (obj['p'] as string) || '';
      item.explanation = (obj['e'] as string) || '';
      item.derivation = (obj['d'] as string) || '';
      result.push(item);
    }
    return result;
  }

  buildQueryResults(candidates: string[], inputWord: string, mode: string): IdiomQueryResultItem[] {
    let results: IdiomQueryResultItem[] = [];
    for (let i = 0; i < candidates.length; i++) {
      let candidate: string = candidates[i];
      let item: IdiomQueryResultItem = new IdiomQueryResultItem();

      if (mode === 'reverse') {
        item.leftWord = candidate;
        item.rightWord = inputWord;
        item.leftClass = 'candidate';
        item.rightClass = 'query';
        item.continueWord = candidate;
        item.actionText = '逆查接龙';
        let nextResult: SolitaireResult = this.querySolitaire(candidate, 'forward');
        item.canContinue = nextResult.candidates.length > 0;
      } else {
        item.leftWord = inputWord;
        item.rightWord = candidate;
        item.leftClass = 'query';
        item.rightClass = 'candidate';
        item.continueWord = candidate;
        item.actionText = '继续接龙';
        item.canContinue = true;
      }

      results.push(item);
    }
    return results;
  }

  findIdiomDetail(context: Context, word: string): IdiomDetailItem | null {
    this.ensureFullData(context);
    if (this.idiomFullCache[word]) {
      return this.idiomFullCache[word];
    }
    let letter: string = this.getFirstLetter(word);
    if (!letter) {
      return null;
    }
    let items: IdiomDetailItem[] = this.getIdiomsByLetter(context, letter);
    for (let i = 0; i < items.length; i++) {
      if (items[i].word === word) {
        return items[i];
      }
    }
    return null;
  }

  getDailyIdiom(context: Context, seed: number): IdiomDetailItem | null {
    if (this.allWords.length === 0) {
      return null;
    }
    let x: number = Math.sin(seed + 7) * 10000;
    let rand: number = x - Math.floor(x);
    let idx: number = Math.floor(rand * this.allWords.length);
    let word: string = this.allWords[idx];
    let detail: IdiomDetailItem | null = this.findIdiomDetail(context, word);
    if (!detail) {
      detail = new IdiomDetailItem();
      detail.word = word;
      detail.pinyin = this.wordToFirstPy[word] || '';
    }
    console.info('[Idiom] getDailyIdiom: ' + word);
    return detail;
  }

  getAllWords(): string[] {
    return this.allWords;
  }

  getRandomIdiom(context: Context): IdiomDetailItem | null {
    if (this.allWords.length === 0) {
      return null;
    }
    let idx: number = Math.floor(Math.random() * this.allWords.length);
    let word: string = this.allWords[idx];
    let detail: IdiomDetailItem | null = this.findIdiomDetail(context, word);
    if (!detail) {
      detail = new IdiomDetailItem();
      detail.word = word;
      detail.pinyin = this.wordToFirstPy[word] || '';
    }
    console.info('[Idiom] getRandomIdiom: ' + word);
    return detail;
  }
}
