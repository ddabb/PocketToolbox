/**
 * 公众号首图内容工具：自动注音(pinyin-pro) + 内容库推荐(诗词/成语/歇后语) + 默认内容
 */
import { pinyin } from 'pinyin-pro';
import { CoverQuotePick, CoverContent, CoverSlot, CoverTemplate } from '../../model/CoverModels';
import { PoetryViewModel } from '../../viewmodel/PoetryViewModel';
import { IdiomViewModel } from '../../viewmodel/IdiomViewModel';
import { XiehouyuViewModel } from '../../viewmodel/XiehouyuViewModel';

export class CoverContentUtil {
  private static usedPoem: Set<string> = new Set<string>();
  private static usedIdiom: Set<string> = new Set<string>();
  private static usedXhy: Set<string> = new Set<string>();

  /** 生字自动注音（带音调），失败返回空串 */
  static autoPinyin(text: string): string {
    let clean: string = text.replace(new RegExp('\\s', 'g'), '');
    if (clean === '') {
      return '';
    }
    try {
      return pinyin(clean, { toneType: 'symbol', type: 'string' });
    } catch (e) {
      console.error('[Cover] autoPinyin failed: ' + (e as Error).message);
      return '';
    }
  }

  /** 拼音串按空白拆分为音节数组 */
  static syllables(pinyinText: string): string[] {
    return pinyinText.trim().split(new RegExp('\\s+', 'g')).filter((s: string) => s !== '');
  }

  /** 替换第 index 个音节（音节内不允许空白），越界或空值返回原串 */
  static replaceSyllable(pinyinText: string, index: number, value: string): string {
    let parts: string[] = CoverContentUtil.syllables(pinyinText);
    let v: string = value.replace(new RegExp('\\s', 'g'), '');
    if (index < 0 || index >= parts.length || v === '') {
      return pinyinText;
    }
    parts[index] = v;
    return parts.join(' ');
  }

  /** 单字候选读音（多音字返回多个，去重保序；无结果返回空数组） */
  static pinyinCandidates(ch: string): string[] {
    if (ch === '') {
      return [];
    }
    try {
      let raw: string[] = pinyin(ch, { multiple: true, type: 'array', toneType: 'symbol' });
      let out: string[] = [];
      for (let i = 0; i < raw.length; i++) {
        let s: string = raw[i].trim();
        if (s !== '' && out.indexOf(s) < 0) {
          out.push(s);
        }
      }
      return out;
    } catch (e) {
      console.error('[Cover] pinyinCandidates failed: ' + (e as Error).message);
      return [];
    }
  }

  /** 今日日期 YYYY.MM.DD */
  static today(): string {
    let d: Date = new Date();
    let m: string = (d.getMonth() + 1) < 10 ? '0' + (d.getMonth() + 1).toString() : (d.getMonth() + 1).toString();
    let day: string = d.getDate() < 10 ? '0' + d.getDate().toString() : d.getDate().toString();
    return d.getFullYear().toString() + '.' + m + '.' + day;
  }

  /** 模板默认内容（seed + 自动日期 + 自动注音） */
  static defaultContent(t: CoverTemplate): CoverContent {
    let c: CoverContent = new CoverContent();
    let seed: Record<string, string> = t.seed;
    c.title = seed['title'] ?? '';
    c.subtitle = seed['subtitle'] ?? '';
    c.author = seed['author'] ?? '';
    c.quote = seed['quote'] ?? '';
    c.quoteSource = seed['quoteSource'] ?? '';
    c.seal = seed['seal'] ?? '';
    if (t.slots.indexOf(CoverSlot.ISSUE) >= 0) {
      let issue: string = seed['issue'] ?? '';
      c.issue = issue !== '' ? issue : CoverContentUtil.today();
    }
    if (t.slots.indexOf(CoverSlot.PINYIN) >= 0) {
      c.pinyin = CoverContentUtil.autoPinyin(c.title);
    }
    return c;
  }

  /** 诗词随机推荐（换一句），quote=首句 source=出处 */
  static randomPoem(context: Context): CoverQuotePick | null {
    try {
      let vm: PoetryViewModel = PoetryViewModel.getInstance();
      if (!vm.loadIndex(context)) {
        return null;
      }
      let poets = vm.getFilteredPoets('');
      if (poets.length === 0) {
        return null;
      }
      let tries: number = 0;
      while (tries < 30) {
        let pi: number = Math.floor(Math.random() * poets.length);
        let poet = poets[pi];
        let detail = vm.loadPoetDetail(context, poet.n, poet.i, poet.d);
        if (detail === null || detail.poems.length === 0) {
          tries++;
          continue;
        }
        let si: number = Math.floor(Math.random() * detail.poems.length);
        let poem = detail.poems[si];
        let key: string = detail.name + '|' + poem.n;
        if (CoverContentUtil.usedPoem.has(key)) {
          if (CoverContentUtil.usedPoem.size > 200) {
            CoverContentUtil.usedPoem.clear();
          }
          tries++;
          continue;
        }
        CoverContentUtil.usedPoem.add(key);
        let quote: string = CoverContentUtil.firstPoemLine(poem.c);
        if (quote === '') {
          tries++;
          continue;
        }
        let source: string = '《' + poem.n + '》·' + poem.a;
        return CoverQuotePick.of(quote, source, '');
      }
    } catch (e) {
      console.error('[Cover] randomPoem failed: ' + (e as Error).message);
    }
    return null;
  }

  /** 成语随机推荐，quote=成语 source=出处 extra=释义 */
  static randomIdiom(context: Context): CoverQuotePick | null {
    try {
      let vm: IdiomViewModel = IdiomViewModel.getInstance();
      if (!vm.loadData(context)) {
        return null;
      }
      let tries: number = 0;
      while (tries < 20) {
        let item = vm.getRandomIdiom(context);
        if (item === null) {
          return null;
        }
        if (CoverContentUtil.usedIdiom.has(item.word)) {
          if (CoverContentUtil.usedIdiom.size > 200) {
            CoverContentUtil.usedIdiom.clear();
          }
          tries++;
          continue;
        }
        CoverContentUtil.usedIdiom.add(item.word);
        return CoverQuotePick.of(item.word, CoverContentUtil.truncate(item.derivation, 24),
          CoverContentUtil.truncate(item.explanation, 50));
      }
    } catch (e) {
      console.error('[Cover] randomIdiom failed: ' + (e as Error).message);
    }
    return null;
  }

  /** 歇后语随机推荐，quote=上句 source=下句 */
  static randomXiehouyu(context: Context): CoverQuotePick | null {
    try {
      let vm: XiehouyuViewModel = XiehouyuViewModel.getInstance();
      if (!vm.loadData(context)) {
        return null;
      }
      let tries: number = 0;
      while (tries < 20) {
        let items = vm.getRandomItems(1);
        if (items.length === 0) {
          return null;
        }
        let item = items[0];
        if (CoverContentUtil.usedXhy.has(item.riddle)) {
          if (CoverContentUtil.usedXhy.size > 200) {
            CoverContentUtil.usedXhy.clear();
          }
          tries++;
          continue;
        }
        CoverContentUtil.usedXhy.add(item.riddle);
        return CoverQuotePick.of(item.riddle, item.answer, '');
      }
    } catch (e) {
      console.error('[Cover] randomXiehouyu failed: ' + (e as Error).message);
    }
    return null;
  }

  /** 按 contentKind 推荐内容 */
  static pickByKind(context: Context, kind: string): CoverQuotePick | null {
    if (kind === 'poem') {
      return CoverContentUtil.randomPoem(context);
    } else if (kind === 'idiom') {
      return CoverContentUtil.randomIdiom(context);
    } else if (kind === 'xiehouyu') {
      return CoverContentUtil.randomXiehouyu(context);
    }
    return null;
  }

  private static firstPoemLine(content: string): string {
    let lines: string[] = content.split('\n');
    let first: string = '';
    for (let i = 0; i < lines.length; i++) {
      let s: string = lines[i].trim();
      if (s !== '') {
        first = s;
        break;
      }
    }
    if (first === '') {
      return '';
    }
    // 过短时拼接第二行
    if (first.length < 5 && lines.length >= 2) {
      for (let i = 0; i < lines.length; i++) {
        if (lines[i].trim() !== '' && lines[i].trim() !== first) {
          first = first + '，' + lines[i].trim();
          break;
        }
      }
    }
    return CoverContentUtil.truncate(first, 16);
  }

  private static truncate(s: string, maxLen: number): string {
    let t: string = s.trim();
    if (t.length <= maxLen) {
      return t;
    }
    return t.substring(0, maxLen) + '…';
  }
}
