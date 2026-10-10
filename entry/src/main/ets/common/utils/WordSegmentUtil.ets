/**
 * 生字卡句子模式 - 分词工具
 * 策略：空格手动分词 > NLK getWordSegment（真机）> 标点分句 + 超长子句对半切兜底
 * NLK API 起始版本 5.0.0(12)：textProcessing.getWordSegment(text): Promise<Array<WordSegment>>
 */
import { textProcessing } from '@kit.NaturalLanguageKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** 单行装箱上限：子句/词超过该长度时对半切（与生字卡单行渲染上限一致） */
const MAX_WORD_LEN: number = 8;
/** 标点符号集（分词时剔除，不参与渲染） */
const PUNCTUATIONS: string = '，。！？；：、,.!?;:…—·「」『』（）()《》<>“”"\'|/\\';

export class WordSegmentUtil {
  /** 同步快路径：空格分词 / 标点兜底（不调用 NLK，用于即时预览） */
  static segmentFast(text: string): string[] {
    let cleaned: string = text.trim();
    if (cleaned === '') {
      return [];
    }
    if (WordSegmentUtil.hasSpaces(cleaned)) {
      return WordSegmentUtil.splitBySpaces(cleaned);
    }
    return WordSegmentUtil.splitByPunctuation(cleaned);
  }

  /** 完整分词：空格 > NLK > 标点兜底 */
  static async segment(text: string): Promise<string[]> {
    let cleaned: string = text.trim();
    if (cleaned === '') {
      return [];
    }
    if (WordSegmentUtil.hasSpaces(cleaned)) {
      return WordSegmentUtil.splitBySpaces(cleaned);
    }
    try {
      let segs: textProcessing.WordSegment[] = await textProcessing.getWordSegment(cleaned);
      let words: string[] = [];
      for (let i = 0; i < segs.length; i++) {
        let w: string = WordSegmentUtil.cleanWord(segs[i].word);
        if (w !== '') {
          words.push(w);
        }
      }
      if (words.length > 0) {
        return words;
      }
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.warn('[WordSegment] NLK getWordSegment failed: ' + err.code + ' ' + err.message);
    }
    return WordSegmentUtil.splitByPunctuation(cleaned);
  }

  static hasSpaces(text: string): boolean {
    for (let i = 0; i < text.length; i++) {
      if (WordSegmentUtil.isSpaceChar(text.charAt(i))) {
        return true;
      }
    }
    return false;
  }

  /** 空格手动分词（英文/拼音场景，无需 NLK） */
  static splitBySpaces(text: string): string[] {
    let words: string[] = [];
    let cur: string = '';
    for (let i = 0; i < text.length; i++) {
      let ch: string = text.charAt(i);
      if (WordSegmentUtil.isSpaceChar(ch)) {
        if (cur !== '') {
          words.push(cur);
          cur = '';
        }
      } else {
        cur += ch;
      }
    }
    if (cur !== '') {
      words.push(cur);
    }
    return words;
  }

  /** 兜底分词：按标点分句，超长子句递归对半切至不超过 MAX_WORD_LEN */
  static splitByPunctuation(text: string): string[] {
    let clauses: string[] = [];
    let cur: string = '';
    for (let i = 0; i < text.length; i++) {
      let ch: string = text.charAt(i);
      if (WordSegmentUtil.isSpaceChar(ch) || WordSegmentUtil.isPunctuation(ch)) {
        if (cur !== '') {
          clauses.push(cur);
          cur = '';
        }
      } else {
        cur += ch;
      }
    }
    if (cur !== '') {
      clauses.push(cur);
    }
    let words: string[] = [];
    for (let i = 0; i < clauses.length; i++) {
      WordSegmentUtil.appendHalved(words, clauses[i]);
    }
    return words;
  }

  private static appendHalved(out: string[], clause: string): void {
    if (clause.length <= MAX_WORD_LEN) {
      if (clause !== '') {
        out.push(clause);
      }
      return;
    }
    let mid: number = Math.ceil(clause.length / 2);
    WordSegmentUtil.appendHalved(out, clause.substring(0, mid));
    WordSegmentUtil.appendHalved(out, clause.substring(mid));
  }

  /** 词清洗：剔除空白与标点，结果为空则丢弃该词 */
  private static cleanWord(word: string): string {
    let out: string = '';
    for (let i = 0; i < word.length; i++) {
      let ch: string = word.charAt(i);
      if (WordSegmentUtil.isSpaceChar(ch) || WordSegmentUtil.isPunctuation(ch)) {
        continue;
      }
      out += ch;
    }
    return out;
  }

  private static isSpaceChar(ch: string): boolean {
    return ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r' || ch === '\u3000';
  }

  private static isPunctuation(ch: string): boolean {
    return PUNCTUATIONS.indexOf(ch) >= 0;
  }
}
