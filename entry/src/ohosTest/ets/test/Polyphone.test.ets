/**
 * 多音字标注强化 - 单元测试（1.5.0 M1-A4）
 * 覆盖：类型① 常规词组/成语词典命中正例锚定、类型② 对抗性重复字现状锚定（防无意识回归）、
 *       batchReplaceSyllable 同字批量替换纯函数（计划 §9-1 语义=覆盖全部同字含已修正位）。
 * 锚定值实测于 pinyin-pro 3.26.0（node + oh_modules，2026-10-25，计划 §2.2）。
 * 纯逻辑直测（无 context/prefs），运行协议见 List.test.ets 头注。
 */
import { describe, it, expect } from '@ohos/hypium';
import { CoverContentUtil } from '../../../main/ets/core/cover/CoverContentUtil';

export default function polyphoneTest() {
  describe('polyphoneTest', () => {
    /** tc1: 类型① 正例锚定 —— 常规多音字词组/成语词典命中 */
    it('tc1_dictHits', 0, () => {
      expect(CoverContentUtil.autoPinyin('银行')).assertEqual('yín háng');
      expect(CoverContentUtil.autoPinyin('重庆')).assertEqual('chóng qìng');
      expect(CoverContentUtil.autoPinyin('长大')).assertEqual('zhǎng dà');
      expect(CoverContentUtil.autoPinyin('人参')).assertEqual('rén shēn');
      expect(CoverContentUtil.autoPinyin('重复')).assertEqual('chóng fù');
      expect(CoverContentUtil.autoPinyin('行行出状元')).assertEqual('háng háng chū zhuàng yuan');
    });

    /** tc2: 类型② 现状锚定 —— 用户样例句逐段注音现状（对抗性重复字自动不可解，
     *  修正链路（批量+逐字+恢复自动）由 tc3-tc5 单测与 E2E 承担） */
    it('tc2_adversarialBaseline', 0, () => {
      expect(CoverContentUtil.autoPinyin('干一行，爱一行，行行行则行行行'))
        .assertEqual('gàn yì háng ài yì háng xíng xíng xíng zé xíng xíng xíng');
      expect(CoverContentUtil.autoPinyin('行行行则行行行'))
        .assertEqual('xíng xíng xíng zé xíng xíng xíng');
      expect(CoverContentUtil.autoPinyin('一行行')).assertEqual('yì háng xíng');
    });

    /** tc3: batchReplaceSyllable 全量替换 —— 样例句 6 个「行」统一改 háng（「则」不动） */
    it('tc3_batchReplaceAll', 0, () => {
      let out: string = CoverContentUtil.batchReplaceSyllable('行行行则行行行',
        'xíng xíng xíng zé xíng xíng xíng', '行', 'háng');
      expect(out).assertEqual('háng háng háng zé háng háng háng');
    });

    /** tc4: 覆盖语义 —— 同字含已手动修正位一并覆盖（§9-1 裁定），混合读音靠逐字再修正兜底 */
    it('tc4_overwriteLocked', 0, () => {
      // 「一行行」行#2 已手动修正为 háng（yì háng háng），批量「行」→xíng 覆盖全部同字
      let out: string = CoverContentUtil.batchReplaceSyllable('一行行', 'yì háng háng', '行', 'xíng');
      expect(out).assertEqual('yì xíng xíng');
    });

    /** tc5: 防御 —— 非汉字目标/空白音节/无同字/幂等（全部已等）/音节数少于汉字数越界位跳过，均不抛异常 */
    it('tc5_guards', 0, () => {
      let py: string = 'gàn yì háng';
      expect(CoverContentUtil.batchReplaceSyllable('干一行', py, 'a', 'xíng')).assertEqual(py);
      expect(CoverContentUtil.batchReplaceSyllable('干一行', py, '行', '  ')).assertEqual(py);
      expect(CoverContentUtil.batchReplaceSyllable('床前明月光', 'chuáng qián míng yuè guāng', '行', 'háng'))
        .assertEqual('chuáng qián míng yuè guāng');
      let done: string = 'háng háng háng';
      expect(CoverContentUtil.batchReplaceSyllable('行行行', done, '行', 'háng')).assertEqual(done);
      expect(CoverContentUtil.batchReplaceSyllable('行行行', 'háng', '行', 'xíng')).assertEqual('xíng');
    });
  });
}
