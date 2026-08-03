import { textProcessing } from '@kit.NaturalLanguageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { HighlightKeyword, HighlightStats, HighlightResult, KeywordOccurrenceContext } from '../../model/Md2PngModels';

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
  private static extractingAllWords: boolean = false;
  private static extractingKeywords: boolean = false;

  static async extractAllWords(text: string): Promise<Array<WordCountEntry>> {
    if (!text || text.trim().length === 0) {
      return [];
    }
    if (KeywordUtil.extractingAllWords) {
      return [];
    }
    KeywordUtil.extractingAllWords = true;
    try {
      let segments: textProcessing.WordSegment[] = await KeywordUtil.segmentText(text);
      let filtered: KeywordEntry[] = KeywordUtil.filterContentWords(segments);
      if (filtered.length === 0) {
        return [];
      }
      let scored: KeywordEntry[] = KeywordUtil.computeTfIdf(filtered);
      let results: Array<WordCountEntry> = [];
      for (let i = 0; i < scored.length; i++) {
        if (scored[i].word.length >= MIN_KEYWORD_LENGTH) {
          let entry: WordCountEntry = new WordCountEntry();
          entry.word = scored[i].word;
          entry.count = scored[i].count;
          entry.tag = scored[i].tag;
          entry.score = scored[i].score;
          results.push(entry);
        }
      }
      return results;
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.warn('[KeywordUtil] extractAllWords failed: ' + err.code + ' ' + err.message);
      return [];
    } finally {
      KeywordUtil.extractingAllWords = false;
    }
  }

  static async extractKeywords(text: string, topN: number = TOP_N): Promise<string[]> {
    if (!text || text.trim().length === 0) {
      return [];
    }
    if (topN <= 0) {
      topN = TOP_N;
    }
    if (KeywordUtil.extractingKeywords) {
      return [];
    }
    KeywordUtil.extractingKeywords = true;
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
      KeywordUtil.extractingKeywords = false;
    }
  }

  static highlightText(original: string, keywords: HighlightKeyword[], highlightFont: string = '',
    accentColor: string = '', highlightBgColor: string = ''): HighlightResult {
    if (!original || keywords.length === 0) {
      return new HighlightResult(original, []);
    }
    // 关键字按长度倒序，长词优先匹配，避免短词嵌入长词中被切割
    let sorted: HighlightKeyword[] = keywords.slice().sort(
      (a: HighlightKeyword, b: HighlightKeyword) => b.word.length - a.word.length
    );
    let ranges: HighlightRange[] = [];
    let stats: HighlightStats[] = [];

    for (let i = 0; i < sorted.length; i++) {
      let kw: HighlightKeyword = sorted[i];
      // 找出该 keyword 在原文中的所有有效出现位置（过滤代码块、内联代码、链接、加粗等）
      let allPositions: number[] = KeywordUtil.findAllValidOccurrences(original, kw.word);
      let occurrences: number = allPositions.length;
      let highlightedCount: number = 0;

      // 按 selectedIndices 选择要高亮的出现序号
      // selectedIndices 中超出 occurrences 范围的序号会被自动截断
      let wanted: Set<number> = new Set<number>();
      for (let k = 0; k < kw.selectedIndices.length; k++) {
        let idx: number = kw.selectedIndices[k];
        if (idx >= 0 && idx < occurrences) {
          wanted.add(idx);
        }
      }
      // 若 selectedIndices 全部超出范围，且存在至少一次出现，则降级高亮首次出现
      if (wanted.size === 0 && occurrences > 0) {
        wanted.add(0);
      }

      for (let j = 0; j < allPositions.length; j++) {
        if (!wanted.has(j)) {
          continue;
        }
        let start: number = allPositions[j];
        let end: number = start + kw.word.length;
        // 与已加入的 ranges 去重叠（先到先得，长词优先）
        let overlaps: boolean = false;
        for (let r = 0; r < ranges.length; r++) {
          if (start < ranges[r].end && end > ranges[r].start) {
            overlaps = true;
            break;
          }
        }
        if (overlaps) {
          continue;
        }
        ranges.push(new HighlightRange(start, end, kw.word));
        highlightedCount++;
      }

      stats.push(new HighlightStats(kw.word, occurrences, highlightedCount));
    }

    if (ranges.length === 0) {
      return new HighlightResult(original, stats);
    }
    ranges.sort((a: HighlightRange, b: HighlightRange) => a.start - b.start);
    let result: string = '';
    let pos: number = 0;
    for (let i: number = 0; i < ranges.length; i++) {
      let r: HighlightRange = ranges[i];
      result += original.substring(pos, r.start);
      let word: string = original.substring(r.start, r.end);
      result += '`' + word + '`';
      pos = r.end;
    }
    result += original.substring(pos);
    return new HighlightResult(result, stats);
  }

  /**
   * 查找关键字在原文中的所有有效出现位置（已过滤代码块、内联代码、链接、加粗等）
   * 返回每个出现位置的起始字符索引，按出现顺序排列
   */
  static findOccurrences(text: string, word: string, contextRadius: number = 8): KeywordOccurrenceContext[] {
    if (!text || !word || word.length === 0) {
      return [];
    }
    let positions: number[] = KeywordUtil.findAllValidOccurrences(text, word);
    let contexts: KeywordOccurrenceContext[] = [];
    for (let i = 0; i < positions.length; i++) {
      let p: number = positions[i];
      let ctxStart: number = Math.max(0, p - contextRadius);
      let ctxEnd: number = Math.min(text.length, p + word.length + contextRadius);
      let prefix: string = ctxStart > 0 ? '…' : '';
      let suffix: string = ctxEnd < text.length ? '…' : '';
      let ctx: string = prefix + text.substring(ctxStart, ctxEnd).replace(/\n/g, ' ') + suffix;
      contexts.push(new KeywordOccurrenceContext(i, p, ctx));
    }
    return contexts;
  }

  /**
   * 统计关键字在原文中的有效出现次数（轻量方法，不计算上下文）
   */
  static countOccurrences(text: string, word: string): number {
    if (!text || !word || word.length === 0) {
      return 0;
    }
    return KeywordUtil.findAllValidOccurrences(text, word).length;
  }

  /**
   * 内部方法：查找关键字在原文中的所有有效出现位置（仅过滤 Markdown 语法区，不做去重叠）
   */
  private static findAllValidOccurrences(original: string, kw: string): number[] {
    if (!original || !kw || kw.length === 0) {
      return [];
    }
    let kwLower: string = kw.toLowerCase();
    let positions: number[] = [];
    let j: number = 0;
    while (j <= original.length - kw.length) {
      let end: number = j + kw.length;
      let candidate: string = original.substring(j, end);
      if (candidate.toLowerCase() !== kwLower) {
        j++;
        continue;
      }
      let beforeChar: string = j > 0 ? original.charAt(j - 1) : '';
      let afterChar: string = end < original.length ? original.charAt(end) : '';
      if (beforeChar === '`' || afterChar === '`') {
        j = end;
        continue;
      }
      if (beforeChar === '*' || afterChar === '*') {
        j = end;
        continue;
      }
      if (beforeChar === '[' || afterChar === ']') {
        j = end;
        continue;
      }
      if (KeywordUtil.isInsideCodeBlock(original, j)) {
        j = end;
        continue;
      }
      positions.push(j);
      j = end;
    }
    return positions;
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

  private static isInsideCodeBlock(text: string, pos: number): boolean {
    let before: string = text.substring(0, pos);
    let fenceCount: number = 0;
    let idx: number = 0;
    while (idx < before.length) {
      let tripleIdx: number = before.indexOf('```', idx);
      if (tripleIdx === -1) {
        break;
      }
      fenceCount++;
      idx = tripleIdx + 3;
    }
    return fenceCount % 2 !== 0;
  }

}

class KeywordEntry {
  word: string = '';
  count: number = 0;
  tag: string = '';
  score: number = 0;
}

export class WordCountEntry {
  word: string = '';
  count: number = 0;
  tag: string = '';
  score: number = 0;
}

class HighlightRange {
  start: number = 0;
  end: number = 0;
  keyword: string = '';

  constructor(start: number, end: number, keyword: string) {
    this.start = start;
    this.end = end;
    this.keyword = keyword;
  }
}
