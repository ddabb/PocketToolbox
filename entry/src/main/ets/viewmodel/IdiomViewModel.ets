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

  searchByPinyin(pinyin: string): IdiomDetailItem[] {
    if (!pinyin || !this.isFirstReady) {
      return [];
    }
    let q: string = pinyin.trim().toLowerCase();
    let results: IdiomDetailItem[] = [];
    let matchedWords: string[] = [];
    for (let i = 0; i < this.firstIndexKeys.length; i++) {
      if (this.firstIndexKeys[i] === q || this.firstIndexKeys[i].indexOf(q) === 0) {
        matchedWords = matchedWords.concat(this.firstIndexValues[i]);
      }
    }
    for (let i = 0; i < matchedWords.length && i < 100; i++) {
      let item: IdiomDetailItem = new IdiomDetailItem();
      item.word = matchedWords[i];
      let py: string = this.wordToFirstPy[matchedWords[i]] || '';
      item.pinyin = py;
      results.push(item);
    }
    console.info('[Idiom] searchByPinyin q=' + q + ', results=' + results.length.toString());
    return results;
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
