import { Context } from '@kit.AbilityKit';
import { PoetryViewModel } from '../../viewmodel/PoetryViewModel';
import { PoemItem, PoetItem, PoetDetail } from '../../model/PoetryModels';
import { CoverContentUtil } from '../../core/cover/CoverContentUtil';

const PY_CLEAN_RE: RegExp = new RegExp('[^a-zA-Z\u0101\u00e1\u01ce\u00e0\u0113\u00e9\u011b\u00e8\u012b\u00ed\u01d0\u00ec\u014d\u00f3\u01d2\u00f2\u016b\u00fa\u01d4\u00f9\u01d6\u01d8\u01da\u01dc\u00fc\u0144\u0148\u01f9\u0304\u0301\u030c\u0300]', 'g');

export class DictationChar {
  ch: string = '';
  py: string = '';
  blank: boolean = false;
}

export class DictationSentence {
  raw: string = '';
  chars: DictationChar[] = [];
}

export class DictationUtil {
  static splitSentences(content: string): string[] {
    let parts: string[] = content.split(new RegExp('[，。！？；、]'));
    let result: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      let s: string = parts[i].replace(new RegExp('\\s', 'g'), '');
      if (s !== '') {
        result.push(s);
      }
    }
    return result;
  }

  static buildSentence(raw: string): DictationSentence {
    return DictationUtil.buildSentenceWithBlanks(raw, []);
  }

  static buildSentenceWithBlanks(raw: string, preferIdx: number[]): DictationSentence {
    let sentence: DictationSentence = new DictationSentence();
    sentence.raw = raw;
    let chars: string[] = Array.from(raw);
    let pyList: string[] = DictationUtil.buildPinyinList(raw, chars);
    let hanIdx: number[] = [];
    for (let i = 0; i < chars.length; i++) {
      if (DictationUtil.isHan(chars[i])) {
        hanIdx.push(i);
      }
    }
    let blankCount: number = 0;
    if (chars.length >= 4) {
      blankCount = Math.min(4, Math.ceil(chars.length * 0.25));
      if (blankCount < 1) {
        blankCount = 1;
      }
    } else if (chars.length >= 2) {
      blankCount = 1;
    }
    if (blankCount > hanIdx.length) {
      blankCount = hanIdx.length;
    }
    let picked: Set<number> = new Set<number>();
    for (let i = 0; i < preferIdx.length && picked.size < blankCount; i++) {
      let idx: number = preferIdx[i];
      if (idx >= 0 && idx < chars.length && DictationUtil.isHan(chars[idx])) {
        picked.add(idx);
      }
    }
    let guard: number = 0;
    let guardMax: number = blankCount * 20 + 50;
    while (picked.size < blankCount && guard < guardMax) {
      let r: number = Math.floor(Math.random() * hanIdx.length);
      picked.add(hanIdx[r]);
      guard++;
    }
    for (let i = 0; i < chars.length; i++) {
      let dc: DictationChar = new DictationChar();
      dc.ch = chars[i];
      dc.py = pyList[i];
      dc.blank = picked.has(i);
      sentence.chars.push(dc);
    }
    return sentence;
  }

  static filterHan(input: string): string {
    return input.replace(new RegExp('[^\u4e00-\u9fa5]', 'g'), '');
  }

  static loadTodayPoem(context: Context): PoemItem | null {
    try {
      let vm: PoetryViewModel = PoetryViewModel.getInstance();
      if (!vm.isDataLoaded()) {
        let ok: boolean = vm.loadIndex(context);
        if (!ok) {
          return null;
        }
      }
      let poets: PoetItem[] = vm.getFilteredPoets('全部');
      if (poets.length === 0) {
        return null;
      }
      let now: Date = new Date();
      let seed: number = now.getFullYear() * 10000 + (now.getMonth() + 1) * 100 + now.getDate();
      let poetIdx: number = Math.floor(DictationUtil.seededRandom(seed) * poets.length);
      let poet: PoetItem = poets[poetIdx];
      let detail: PoetDetail = vm.loadPoetDetail(context, poet.n, poet.i, poet.d);
      if (detail.poems.length === 0) {
        return null;
      }
      let poemIdx: number = Math.floor(DictationUtil.seededRandom(seed + 1) * detail.poems.length);
      let poem: PoemItem = detail.poems[poemIdx];
      let result: PoemItem = new PoemItem();
      result.n = poem.n;
      result.c = poem.c;
      result.f = poem.f;
      result.a = detail.name;
      result.d = detail.dynasty;
      return result;
    } catch (e) {
      console.error('[Dictation] loadTodayPoem failed: ' + (e as Error).message);
      return null;
    }
  }

  private static buildPinyinList(raw: string, chars: string[]): string[] {
    let result: string[] = [];
    let pyText: string = CoverContentUtil.autoPinyin(raw);
    if (pyText === '') {
      for (let i = 0; i < chars.length; i++) {
        result.push('');
      }
      return result;
    }
    let syllables: string[] = CoverContentUtil.syllables(pyText);
    let si: number = 0;
    for (let i = 0; i < chars.length; i++) {
      let ch: string = chars[i];
      let py: string = '';
      if (DictationUtil.isHan(ch)) {
        while (si < syllables.length && !DictationUtil.hasLetter(syllables[si])) {
          si++;
        }
        if (si < syllables.length) {
          py = syllables[si].replace(PY_CLEAN_RE, '');
          si++;
        }
      } else if (ch !== ' ' && ch !== '\u3000') {
        if (si < syllables.length && syllables[si] === ch) {
          si++;
        }
      }
      result.push(py);
    }
    return result;
  }

  private static seededRandom(seed: number): number {
    let x: number = Math.sin(seed) * 10000;
    return x - Math.floor(x);
  }

  private static isHan(ch: string): boolean {
    let code: number = ch.charCodeAt(0);
    return code >= 0x4E00 && code <= 0x9FA5;
  }

  private static hasLetter(token: string): boolean {
    return new RegExp('[a-zA-Z]').test(token);
  }
}
