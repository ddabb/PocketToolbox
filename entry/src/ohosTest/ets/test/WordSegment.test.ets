/**
 * 生字卡句子分词 - 单元测试
 * 覆盖：标点跟随保留（快路径/完整分词/空格路径）、连续标点并入前句、纯汉字对半切兜底、
 * 标点判定公开 API、词装箱标点计数（2026-10-18 标点渲染修复回归）
 */
import { describe, it, expect } from '@ohos/hypium';
import { WordSegmentUtil } from '../../../main/ets/common/utils/WordSegmentUtil';
import { CharCards } from '../../../main/ets/core/cover/CharCardTemplates';

export default function wordSegmentTest() {
  describe('wordSegmentTest', () => {
    /** tc1: 标点跟随 —— 快路径分句保留标点且跟随前句（不再整段丢弃） */
    it('tc1_punctFollowsFast', 0, () => {
      let words: string[] = WordSegmentUtil.segmentFast('床前明月光，疑是地上霜。');
      expect(words.length).assertEqual(2);
      expect(words[0]).assertEqual('床前明月光，');
      expect(words[1]).assertEqual('疑是地上霜。');
      let single: string[] = WordSegmentUtil.segmentFast('学而时习之。');
      expect(single.length).assertEqual(1);
      expect(single[0]).assertEqual('学而时习之。');
      let lead: string[] = WordSegmentUtil.segmentFast('，你好');
      expect(lead.length).assertEqual(2);
      expect(lead[0]).assertEqual('，');
      expect(lead[1]).assertEqual('你好');
      let chain: string[] = WordSegmentUtil.segmentFast('你好。。世界');
      expect(chain.length).assertEqual(2);
      expect(chain[0]).assertEqual('你好。。');
      expect(chain[1]).assertEqual('世界');
    });

    /** tc2: 完整分词 —— 含标点走标点分句不进 NLK（真机 NLK 词级切分会丢标点），与快路径一致 */
    it('tc2_segmentPunctShortCircuit', 0, async (): Promise<void> => {
      let words: string[] = await WordSegmentUtil.segment('床前明月光，疑是地上霜。');
      expect(words.length).assertEqual(2);
      expect(words[0]).assertEqual('床前明月光，');
      expect(words[1]).assertEqual('疑是地上霜。');
    });

    /** tc3: 空格路径标点保留（既有行为回归） */
    it('tc3_punctWithSpaces', 0, () => {
      let words: string[] = WordSegmentUtil.segmentFast('你好， 世界');
      expect(words.length).assertEqual(2);
      expect(words[0]).assertEqual('你好，');
      expect(words[1]).assertEqual('世界');
    });

    /** tc4: 纯汉字无标点 —— 单子句 ≤8 整词、>8 对半切（既有兜底行为回归） */
    it('tc4_pureHanFallback', 0, () => {
      let eight: string[] = WordSegmentUtil.segmentFast('一二三四五六七八');
      expect(eight.length).assertEqual(1);
      expect(eight[0]).assertEqual('一二三四五六七八');
      let nine: string[] = WordSegmentUtil.segmentFast('一二三四五六七八九');
      expect(nine.length).assertEqual(2);
      expect(nine[0]).assertEqual('一二三四五');
      expect(nine[1]).assertEqual('六七八九');
    });

    /** tc5: 标点判定公开 API（渲染层标点格复用） */
    it('tc5_punctDetect', 0, () => {
      expect(WordSegmentUtil.hasPunctuation('床前，')).assertTrue();
      expect(WordSegmentUtil.hasPunctuation('床前')).assertFalse();
      expect(WordSegmentUtil.hasPunctuation('')).assertFalse();
      expect(WordSegmentUtil.isPunctuation('，')).assertTrue();
      expect(WordSegmentUtil.isPunctuation('。')).assertTrue();
      expect(WordSegmentUtil.isPunctuation('！')).assertTrue();
      expect(WordSegmentUtil.isPunctuation(',')).assertTrue();
      expect(WordSegmentUtil.isPunctuation('床')).assertFalse();
      expect(WordSegmentUtil.isPunctuation('a')).assertFalse();
    });

    /** tc6: 词装箱 —— 标点计入字数上限（capWords 整词溢出即丢弃不变） */
    it('tc6_capWordsWithPunct', 0, () => {
      let kept: string[] = CharCards.capWords(['床前明月光，', '疑是地上霜。'], 12);
      expect(kept.length).assertEqual(2);
      let drop: string[] = CharCards.capWords(['床前明月光，', '疑是地上霜。'], 8);
      expect(drop.length).assertEqual(1);
      expect(drop[0]).assertEqual('床前明月光，');
    });
  });
}
