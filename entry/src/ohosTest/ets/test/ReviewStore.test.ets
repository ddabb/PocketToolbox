/**
 * 复习到期纯逻辑 - 单元测试（1.4.9 M4-B2）
 * 覆盖：ReviewStore.filterDue 过滤边界（已毕业 0 剔除/恰等于 now 保留/未来剔除）与到期时间升序排序。
 * 注：prefs I/O 不在本套件——模拟器 aa test 进程 context 为壳（见 CopyPoster.test.ets 头注），
 *     到期数持久化链路由 E2E 反向验证（无 due 数据时首页提示条不渲染，见计划 §10-M4）。
 */
import { describe, it, expect } from '@ohos/hypium';
import { ReviewStore, SentenceRecord } from '../../../main/ets/common/utils/ReviewStore';

export default function reviewStoreTest() {
  describe('reviewStoreTest', () => {
    const NOW: number = 1000000000000;
    const makeRec = (key: string, nextReviewAt: number): SentenceRecord => {
      let rec: SentenceRecord = new SentenceRecord();
      rec.key = key;
      rec.raw = key + '-raw';
      rec.nextReviewAt = nextReviewAt;
      return rec;
    };

    /** tc1: 过滤边界 —— 已毕业(nextReviewAt=0)与未来到期剔除，过去与恰等于 now 保留 */
    it('tc1_filterBoundary', 0, () => {
      let records: SentenceRecord[] = [
        makeRec('graduated', 0),
        makeRec('future', NOW + 1),
        makeRec('justNow', NOW),
        makeRec('past', NOW - 86400000)
      ];
      let due: SentenceRecord[] = ReviewStore.filterDue(records, NOW);
      expect(due.length).assertEqual(2);
      expect(due[0].key).assertEqual('past');
      expect(due[1].key).assertEqual('justNow');
    });

    /** tc2: 排序 —— 到期时间升序（最早到期优先复习） */
    it('tc2_sortAsc', 0, () => {
      let records: SentenceRecord[] = [
        makeRec('c', NOW - 100),
        makeRec('a', NOW - 300),
        makeRec('b', NOW - 200)
      ];
      let due: SentenceRecord[] = ReviewStore.filterDue(records, NOW);
      expect(due.length).assertEqual(3);
      expect(due[0].key).assertEqual('a');
      expect(due[1].key).assertEqual('b');
      expect(due[2].key).assertEqual('c');
    });

    /** tc3: 空列表与全未到期 —— 返回空数组不抛异常 */
    it('tc3_emptyAndNoneDue', 0, () => {
      expect(ReviewStore.filterDue([], NOW).length).assertEqual(0);
      let none: SentenceRecord[] = [makeRec('x', NOW + 60000), makeRec('y', 0)];
      expect(ReviewStore.filterDue(none, NOW).length).assertEqual(0);
    });
  });
}
