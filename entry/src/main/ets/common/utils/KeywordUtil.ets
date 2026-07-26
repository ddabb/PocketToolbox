import { textProcessing } from '@kit.NaturalLanguageKit';
import { BusinessError } from '@kit.BasicServicesKit';

const STOP_WORDS: Set<string> = new Set([
  '的', '了', '在', '是', '我', '有', '和', '就', '不', '人', '都', '一', '一个',
  '上', '也', '很', '到', '说', '要', '去', '你', '会', '着', '没有', '看', '好',
  '自己', '这', '他', '她', '它', '们', '那', '些', '什么', '怎么', '如何', '为',
  '为什么', '因为', '所以', '但是', '但', '而', '而且', '或者', '或', '如果', '如',
  '则', '虽然', '虽', '却', '又', '及', '与', '跟', '比', '让', '被', '把', '从',
  '向', '对', '给', '以', '于', '之', '其', '此', '该', '每', '各', '某', '任',
  '些', '这些', '那些', '这个', '那个', '哪', '哪里', '哪个', '几', '多少', '许多',
  '可以', '可', '能', '能够', '应该', '应', '必须', '须', '得', '地', '着', '过',
  '来', '去', '起来', '出来', '下来', '上去', '出去', '回来', '过来', '进来',
  '吧', '吗', '呢', '啊', '呀', '哦', '哈', '嗯', '嘛', '啦', '哇', '哎', '唉',
  '已', '已经', '曾', '将', '将要', '正在', '刚刚', '才', '就', '便', '于是',
  '再', '也', '还', '更', '最', '非常', '很', '极', '太', '挺', '特别', '尤其',
  '比较', '稍', '略', '稍许', '多少', '几乎', '约', '大约', '大概', '左右',
  '不过', '只是', '然而', '否则', '不但', '不仅', '而且', '何况', '并', '并且',
  '即', '即或', '即使', '即便', '纵然', '尽管', '任凭', '无论', '不管',
  '除', '除了', '除外', '除开', '此外', '另外', '再者', '还有', '同时',
  '关于', '至于', '对于', '根据', '按照', '按', '通过', '经过', '凭借', '靠',
  '用', '拿', '作为', '当作', '成了', '变成', '等于', '是', '算是', '算是',
  '只', '仅', '仅仅', '单', '光', '惟独', '无非', '不过是', '不过是',
  '等等', '等', '之类', '一般', '似的', '一样', '这种', '那种', '某种',
  '时候', '时间', '地方', '方面', '部分', '里面', '外面', '上面', '下面',
  '前面', '后面', '左边', '右边', '中间', '旁边', '这里', '那里', '哪里',
  '出来', '起来', '下来', '上去', '出去', '回来', '过来', '进去', '过去',
  'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
  'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could',
  'should', 'may', 'might', 'must', 'shall', 'can', 'need', 'dare',
  'to', 'of', 'in', 'for', 'on', 'with', 'at', 'by', 'from', 'as',
  'into', 'through', 'during', 'before', 'after', 'above', 'below',
  'between', 'out', 'off', 'over', 'under', 'again', 'further', 'then',
  'once', 'here', 'there', 'when', 'where', 'why', 'how', 'all', 'each',
  'every', 'both', 'few', 'more', 'most', 'other', 'some', 'such', 'no',
  'not', 'only', 'own', 'same', 'so', 'than', 'too', 'very', 'just',
  'because', 'but', 'and', 'or', 'if', 'while', 'although', 'though',
  'this', 'that', 'these', 'those', 'i', 'me', 'my', 'we', 'our', 'you',
  'your', 'he', 'him', 'his', 'she', 'her', 'it', 'its', 'they', 'them',
  'their', 'what', 'which', 'who', 'whom'
]);

const CONTENT_WORD_TAGS: Set<string> = new Set([
  'n', 'nr', 'ns', 'nt', 'nz', 'v', 'vd', 'vn', 'a', 'ad', 'an',
  'i', 'l', 'eng', 'nx'
]);

const MAX_SEGMENT_LENGTH: number = 1000;
const TOP_N: number = 5;
const MIN_KEYWORD_LENGTH: number = 2;

export class KeywordUtil {
  private static extracting: boolean = false;

  static async extractKeywords(text: string, topN: number = TOP_N): Promise<string[]> {
    if (!text || text.trim().length === 0) {
      return [];
    }
    if (topN <= 0) {
      topN = TOP_N;
    }
    if (KeywordUtil.extracting) {
      return [];
    }
    KeywordUtil.extracting = true;
    try {
      let segments: textProcessing.WordSegment[] = await KeywordUtil.segmentText(text);
      let filtered: KeywordEntry[] = KeywordUtil.filterContentWords(segments);
      if (filtered.length === 0) {
        return [];
      }
      let scored: KeywordEntry[] = KeywordUtil.computeTfIdf(filtered);
      let keywords: string[] = [];
      let count: number = 0;
      for (let i = 0; i < scored.length && count < topN; i++) {
        if (scored[i].word.length >= MIN_KEYWORD_LENGTH) {
          keywords.push(scored[i].word);
          count++;
        }
      }
      return keywords;
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.warn('[KeywordUtil] extract failed: ' + err.code + ' ' + err.message);
      return [];
    } finally {
      KeywordUtil.extracting = false;
    }
  }

  static highlightText(original: string, keywords: string[]): string {
    if (!original || keywords.length === 0) {
      return original;
    }
    let result: string = original;
    let sorted: string[] = keywords.slice().sort((a: string, b: string) => b.length - a.length);
    for (let i = 0; i < sorted.length; i++) {
      let kw: string = sorted[i];
      result = KeywordUtil.wrapKeyword(result, kw);
    }
    return result;
  }

  private static async segmentText(text: string): Promise<textProcessing.WordSegment[]> {
    let parts: string[] = KeywordUtil.splitText(text);
    let allSegments: textProcessing.WordSegment[] = [];
    for (let i = 0; i < parts.length; i++) {
      let part: string = parts[i].trim();
      if (part.length === 0) {
        continue;
      }
      try {
        let segs: textProcessing.WordSegment[] = await textProcessing.getWordSegment(part);
        for (let j = 0; j < segs.length; j++) {
          allSegments.push(segs[j]);
        }
      } catch (e) {
        let err: BusinessError = e as BusinessError;
        console.warn('[KeywordUtil] segment part failed: ' + err.code + ' ' + err.message);
      }
    }
    return allSegments;
  }

  static splitText(text: string): string[] {
    if (text.length <= MAX_SEGMENT_LENGTH) {
      return [text];
    }
    let parts: string[] = [];
    let remaining: string = text;
    while (remaining.length > 0) {
      if (remaining.length <= MAX_SEGMENT_LENGTH) {
        parts.push(remaining);
        break;
      }
      let cutPos: number = -1;
      let searchStart: number = MAX_SEGMENT_LENGTH - 1;
      if (searchStart >= remaining.length) {
        searchStart = remaining.length - 1;
      }
      for (let i = searchStart; i > searchStart - 200 && i >= 0; i--) {
        let ch: string = remaining.charAt(i);
        if (ch === '。' || ch === '！' || ch === '？' || ch === '\n' || ch === '；' ||
          ch === '.' || ch === '!' || ch === '?' || ch === ';') {
          cutPos = i + 1;
          break;
        }
      }
      if (cutPos <= 0) {
        cutPos = MAX_SEGMENT_LENGTH;
      }
      parts.push(remaining.substring(0, cutPos));
      remaining = remaining.substring(cutPos);
    }
    return parts;
  }

  private static filterContentWords(segments: textProcessing.WordSegment[]): KeywordEntry[] {
    let wordMap: Map<string, KeywordEntry> = new Map();
    for (let i = 0; i < segments.length; i++) {
      let word: string = segments[i].word;
      let tag: string = segments[i].wordTag;
      if (!CONTENT_WORD_TAGS.has(tag)) {
        continue;
      }
      if (STOP_WORDS.has(word)) {
        continue;
      }
      if (word.trim().length < MIN_KEYWORD_LENGTH) {
        continue;
      }
      let existing: KeywordEntry | undefined = wordMap.get(word);
      if (existing !== undefined) {
        existing.count += 1;
      } else {
        let entry: KeywordEntry = new KeywordEntry();
        entry.word = word;
        entry.count = 1;
        entry.tag = tag;
        wordMap.set(word, entry);
      }
    }
    let result: KeywordEntry[] = [];
    wordMap.forEach((value: KeywordEntry) => {
      result.push(value);
    });
    return result;
  }

  private static computeTfIdf(words: KeywordEntry[]): KeywordEntry[] {
    let totalWords: number = 0;
    for (let i = 0; i < words.length; i++) {
      totalWords += words[i].count;
    }
    if (totalWords === 0) {
      return words;
    }
    for (let i = 0; i < words.length; i++) {
      let tf: number = words[i].count / totalWords;
      let idf: number = STOP_WORDS.has(words[i].word) ? 0.01 : 1.0;
      if (words[i].tag === 'nr' || words[i].tag === 'ns' || words[i].tag === 'nt') {
        idf = 2.0;
      } else if (words[i].tag === 'nz') {
        idf = 1.8;
      } else if (words[i].tag === 'n') {
        idf = 1.5;
      } else if (words[i].tag === 'v' || words[i].tag === 'vn') {
        idf = 1.0;
      } else if (words[i].tag === 'a' || words[i].tag === 'ad' || words[i].tag === 'an') {
        idf = 1.3;
      }
      words[i].score = tf * idf;
    }
    words.sort((a: KeywordEntry, b: KeywordEntry) => b.score - a.score);
    return words;
  }

  private static wrapKeyword(text: string, keyword: string): string {
    let result: string = '';
    let i: number = 0;
    let kwLower: string = keyword.toLowerCase();
    while (i < text.length) {
      let end: number = i + keyword.length;
      if (end > text.length) {
        result += text.charAt(i);
        i++;
        continue;
      }
      let candidate: string = text.substring(i, end);
      if (candidate.toLowerCase() !== kwLower) {
        result += text.charAt(i);
        i++;
        continue;
      }
      let beforeChar: string = i > 0 ? text.charAt(i - 1) : '';
      let afterChar: string = end < text.length ? text.charAt(end) : '';
      if (beforeChar === '`' || afterChar === '`') {
        result += candidate;
        i = end;
        continue;
      }
      if (beforeChar === '*' || afterChar === '*') {
        result += candidate;
        i = end;
        continue;
      }
      if (KeywordUtil.isInsideMarkdownTag(text, i)) {
        result += candidate;
        i = end;
        continue;
      }
      result += '**`' + candidate + '`**';
      i = end;
    }
    return result;
  }

  private static isInsideMarkdownTag(text: string, pos: number): boolean {
    let before: string = text.substring(Math.max(0, pos - 20), pos);
    let after: string = text.substring(pos, Math.min(text.length, pos + 20));
    if (before.lastIndexOf('[') > before.lastIndexOf(']') && after.indexOf(']') >= 0 &&
      after.indexOf(']') < after.indexOf('(')) {
      return true;
    }
    if (before.lastIndexOf('<') > before.lastIndexOf('>') && after.indexOf('>') >= 0) {
      return true;
    }
    return false;
  }
}

class KeywordEntry {
  word: string = '';
  count: number = 0;
  tag: string = '';
  score: number = 0;
}
