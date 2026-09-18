/**
 * 公众号首图制作 - 单元测试
 * 覆盖：模板注册完整性 / 自动注音 / 日期与默认内容 / 内容 JSON 往返 / 推荐去重 / 历史存取
 */
import { describe, it, expect, beforeAll } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { CoverSlot, CoverTemplate, CoverContent, CoverHistoryRecord } from '../../../main/ets/model/CoverModels';
import { CoverTemplates, CoverSeries } from '../../../main/ets/core/cover/CoverTemplates';
import { CoverContentUtil } from '../../../main/ets/core/cover/CoverContentUtil';
import { CoverHistoryStore } from '../../../main/ets/core/cover/CoverHistoryStore';

/** 模块加载期 delegator 尚未就绪，必须在用例执行期懒获取 */
function appCtx(): common.Context {
  const delegator: abilityDelegatorRegistry.AbilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();
  return delegator.getAppContext();
}

export default function coverTest() {
  describe('coverTest', () => {
    beforeAll(() => {
      CoverHistoryStore.clearAll(appCtx());
    });

    /**
     * tc1: 模板注册完整性 —— 15 个模板、id 唯一、layout 非空、
     * 每个模板 >=4 配色且 fonts 非空且含 title 槽位
     */
    it('tc1_templateRegistry', 0, () => {
      let all: CoverTemplate[] = CoverTemplates.getAll();
      expect(all.length).assertEqual(15);
      let ids: Set<string> = new Set<string>();
      let layouts: Set<string> = new Set<string>();
      for (let i = 0; i < all.length; i++) {
        let t: CoverTemplate = all[i];
        expect(t.id !== '').assertTrue();
        expect(ids.has(t.id)).assertFalse();
        ids.add(t.id);
        expect(t.layout !== '').assertTrue();
        layouts.add(t.layout);
        expect(t.name !== '').assertTrue();
        expect(t.palettes.length >= 4).assertTrue();
        expect(t.fonts.length > 0).assertTrue();
        expect(t.slots.length > 0).assertTrue();
        expect(t.seed !== undefined).assertTrue();
      }
      expect(layouts.size).assertEqual(15);
    });

    /** tc2: 按 id / 系列查询（getById 未命中时回退首模板 A1） */
    it('tc2_getByIdAndSeries', 0, () => {
      let b5: CoverTemplate = CoverTemplates.getById('B5');
      expect(b5.name).assertEqual('田字格字卡');
      expect(b5.slots.indexOf(CoverSlot.PINYIN) >= 0).assertTrue();
      let missing: CoverTemplate = CoverTemplates.getById('no_such_id');
      expect(missing.id).assertEqual('A1');
      let seriesCount: number = 0;
      let allSeries: string[] = [CoverSeries.SIMPLE, CoverSeries.CULTURE, CoverSeries.BIG,
        CoverSeries.MAGAZINE, CoverSeries.PHOTO];
      let totalBySeries: number = 0;
      for (let i = 0; i < allSeries.length; i++) {
        let list: CoverTemplate[] = CoverTemplates.getBySeries(allSeries[i]);
        expect(list.length > 0).assertTrue();
        totalBySeries += list.length;
        for (let j = 0; j < list.length; j++) {
          expect(list[j].series === allSeries[i]).assertTrue();
        }
      }
      expect(totalBySeries).assertEqual(15);
      expect(seriesCount).assertEqual(0);
    });

    /** tc3: 自动注音 —— PRD 验收：学而时习之 -> xué ér shí xí zhī */
    it('tc3_autoPinyin', 0, () => {
      expect(CoverContentUtil.autoPinyin('学而时习之')).assertEqual('xué ér shí xí zhī');
      expect(CoverContentUtil.autoPinyin('你好')).assertEqual('nǐ hǎo');
      expect(CoverContentUtil.autoPinyin('')).assertEqual('');
      expect(CoverContentUtil.autoPinyin('a b')).assertEqual('a b');
    });

    /** tc4: 日期格式 YYYY.MM.DD */
    it('tc4_today', 0, () => {
      let today: string = CoverContentUtil.today();
      expect(today.length).assertEqual(10);
      expect(today.charAt(4)).assertEqual('.');
      expect(today.charAt(7)).assertEqual('.');
      let parts: string[] = today.split('.');
      expect(parts.length).assertEqual(3);
      expect(parts[0].length).assertEqual(4);
      expect(parts[1].length).assertEqual(2);
      expect(parts[2].length).assertEqual(2);
    });

    /** tc5: 默认内容 —— seed 填充 + 自动日期 + 自动注音 */
    it('tc5_defaultContent', 0, () => {
      let b5: CoverTemplate = CoverTemplates.getById('B5');
      let c: CoverContent = CoverContentUtil.defaultContent(b5);
      expect(c.title !== '').assertTrue();
      expect(c.title.length <= 8).assertTrue();
      expect(c.pinyin !== '').assertTrue();
      let a1: CoverTemplate = CoverTemplates.getById('A1');
      let c1: CoverContent = CoverContentUtil.defaultContent(a1);
      expect(c1.title !== '').assertTrue();
      expect(c1.subtitle !== '').assertTrue();
    });

    /** tc6: CoverContent JSON 往返 */
    it('tc6_contentJsonRoundtrip', 0, () => {
      let c: CoverContent = new CoverContent();
      c.title = '学而时习之';
      c.subtitle = '论语·学而';
      c.author = '孔子';
      c.issue = '2026.09.16';
      c.quote = '不亦说乎';
      c.quoteSource = '《论语》';
      c.pinyin = 'xué ér shí xí zhī';
      c.seal = '解语';
      let json: string = c.toJson();
      let back: CoverContent = CoverContent.fromJson(json);
      expect(back.title).assertEqual(c.title);
      expect(back.subtitle).assertEqual(c.subtitle);
      expect(back.author).assertEqual(c.author);
      expect(back.issue).assertEqual(c.issue);
      expect(back.quote).assertEqual(c.quote);
      expect(back.quoteSource).assertEqual(c.quoteSource);
      expect(back.pinyin).assertEqual(c.pinyin);
      expect(back.seal).assertEqual(c.seal);
      expect(back.pinyinLocked).assertTrue();
      let bad: CoverContent = CoverContent.fromJson('not a json');
      expect(bad.title).assertEqual('');
    });

    /** tc7: 内容推荐去重 —— 成语/歇后语各取 10 次不重复 */
    it('tc7_pickNoRepeat', 0, () => {
      let idiomSet: Set<string> = new Set<string>();
      for (let i = 0; i < 10; i++) {
        let pick = CoverContentUtil.randomIdiom(appCtx());
        expect(pick !== null).assertTrue();
        if (pick !== null) {
          expect(pick.quote !== '').assertTrue();
          expect(idiomSet.has(pick.quote)).assertFalse();
          idiomSet.add(pick.quote);
        }
      }
      let xhySet: Set<string> = new Set<string>();
      for (let i = 0; i < 10; i++) {
        let pick = CoverContentUtil.randomXiehouyu(appCtx());
        expect(pick !== null).assertTrue();
        if (pick !== null) {
          expect(pick.quote !== '').assertTrue();
          expect(pick.source !== '').assertTrue();
          expect(xhySet.has(pick.quote)).assertFalse();
          xhySet.add(pick.quote);
        }
      }
    });

    /** tc8: 历史存取往返 + 20 条上限 */
    it('tc8_historyRoundtrip', 0, () => {
      CoverHistoryStore.clearAll(appCtx());
      let records: CoverHistoryRecord[] = CoverHistoryStore.loadRecords(appCtx());
      expect(records.length).assertEqual(0);

      let srcPath: string = appCtx().cacheDir + '/cover_test_src.png';
      let file: fs.File = fs.openSync(srcPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, 'png-test-bytes');
      } finally {
        fs.closeSync(file.fd);
      }

      for (let i = 0; i < 25; i++) {
        let rec: CoverHistoryRecord = CoverHistoryRecord.of(
          'id_' + i.toString(),
          'cover_test_' + i.toString() + '.png',
          'b5_grid',
          i % 4,
          i % 2,
          '{"title":"测' + i.toString() + '"}',
          Date.now() + i);
        let ok: boolean = CoverHistoryStore.saveRecord(appCtx(), srcPath, rec);
        expect(ok).assertTrue();
      }

      let loaded: CoverHistoryRecord[] = CoverHistoryStore.loadRecords(appCtx());
      expect(loaded.length).assertEqual(20);
      expect(loaded[0].templateId).assertEqual('b5_grid');
      expect(loaded[0].textsJson.indexOf('24') >= 0).assertTrue();
      expect(fs.accessSync(CoverHistoryStore.filePath(appCtx(), loaded[0].fileName))).assertTrue();

      CoverHistoryStore.clearAll(appCtx());
      let after: CoverHistoryRecord[] = CoverHistoryStore.loadRecords(appCtx());
      expect(after.length).assertEqual(0);
    });
    /** tc9: 拼音音节拆分 syllables */
    it('tc9_syllables', 0, () => {
      let parts: string[] = CoverContentUtil.syllables('xué ér shí xí zhī');
      expect(parts.length).assertEqual(5);
      expect(parts[0]).assertEqual('xué');
      expect(parts[4]).assertEqual('zhī');
      expect(CoverContentUtil.syllables('  ').length).assertEqual(0);
      expect(CoverContentUtil.syllables('').length).assertEqual(0);
      let multi: string[] = CoverContentUtil.syllables('nǐ hǎo');
      expect(multi.length).assertEqual(2);
    });

    /** tc10: 音节替换 replaceSyllable —— 正常 / 越界 / 空值 / 含空白值 */
    it('tc10_replaceSyllable', 0, () => {
      let src: string = 'xué ér shí';
      expect(CoverContentUtil.replaceSyllable(src, 1, 'ér')).assertEqual('xué ér shí');
      expect(CoverContentUtil.replaceSyllable(src, 0, 'xuě')).assertEqual('xuě ér shí');
      expect(CoverContentUtil.replaceSyllable(src, 2, 'shì')).assertEqual('xué ér shì');
      // 越界返回原串
      expect(CoverContentUtil.replaceSyllable(src, -1, 'a')).assertEqual(src);
      expect(CoverContentUtil.replaceSyllable(src, 3, 'a')).assertEqual(src);
      // 空值返回原串
      expect(CoverContentUtil.replaceSyllable(src, 0, '')).assertEqual(src);
      expect(CoverContentUtil.replaceSyllable(src, 0, '  ')).assertEqual(src);
      // 值内空白被剔除
      expect(CoverContentUtil.replaceSyllable(src, 0, ' xuě ')).assertEqual('xuě ér shí');
    });

    /** tc11: 单字候选读音 pinyinCandidates —— 多音字 / 单读音 / 空串 */
    it('tc11_pinyinCandidates', 0, () => {
      let duo: string[] = CoverContentUtil.pinyinCandidates('长');
      expect(duo.length >= 2).assertTrue();
      expect(duo.indexOf('cháng') >= 0).assertTrue();
      expect(duo.indexOf('zhǎng') >= 0).assertTrue();
      let single: string[] = CoverContentUtil.pinyinCandidates('学');
      expect(single.length).assertEqual(1);
      expect(single[0]).assertEqual('xué');
      expect(CoverContentUtil.pinyinCandidates('').length).assertEqual(0);
    });
  });
}
