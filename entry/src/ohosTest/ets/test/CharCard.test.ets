/**
 * 生字卡 - 单元测试
 * 覆盖：配色/尺寸常量、格数自适应公式、行拆分、拼音行分配、清洗截断、
 * 逐字注音（批量导出拼音正确性）、历史目录隔离（card_history vs cover_history）
 */
import { describe, it, expect, beforeAll } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { CoverHistoryRecord } from '../../../main/ets/model/CoverModels';
import { CharCards, CharCardSize, CharCardGridType, CharCardCharMode } from '../../../main/ets/core/cover/CharCardTemplates';
import { CoverContentUtil } from '../../../main/ets/core/cover/CoverContentUtil';
import { CoverHistoryStore } from '../../../main/ets/core/cover/CoverHistoryStore';

/** 模块加载期 delegator 尚未就绪，必须在用例执行期懒获取 */
function appCtx(): common.Context {
  const delegator: abilityDelegatorRegistry.AbilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();
  return delegator.getAppContext();
}

export default function charCardTest() {
  describe('charCardTest', () => {
    beforeAll(() => {
      CoverHistoryStore.clearAll(appCtx(), CoverHistoryStore.DIR_CHAR_CARD);
    });

    /** tc1: 配色 5 套，首套为 B5 同款蓝底红格黑字 */
    it('tc1_palettes', 0, () => {
      let list = CharCards.palettes();
      expect(list.length).assertEqual(5);
      expect(list[0].bg).assertEqual('#2E6FD6');
      expect(list[0].accent).assertEqual('#D8231A');
      expect(list[0].title).assertEqual('#1F1F1F');
      for (let i = 0; i < list.length; i++) {
        expect(list[i].bg !== '').assertTrue();
        expect(list[i].accent !== '').assertTrue();
        expect(list[i].title !== '').assertTrue();
      }
    });

    /** tc2: 尺寸常量 —— 方卡 1080x1080、练习卡 1080x1440 */
    it('tc2_sizes', 0, () => {
      expect(CharCards.EXPORT_W).assertEqual(1080);
      expect(CharCards.EXPORT_H_SQUARE).assertEqual(1080);
      expect(CharCards.EXPORT_H_PRACTICE).assertEqual(1440);
      expect(CharCards.designHeight(CharCardSize.SQUARE)).assertEqual(900);
      expect(CharCards.designHeight(CharCardSize.PRACTICE)).assertEqual(1200);
      expect(CharCardSize.label(CharCardSize.PRACTICE)).assertEqual('练习卡 3:4');
      expect(CharCardGridType.label(CharCardGridType.MI)).assertEqual('米字格');
      expect(CharCardCharMode.label(CharCardCharMode.TRACE)).assertEqual('描红');
    });

    /** tc3: 行拆分 —— <=8 字一行，>8 字两行前多后少 */
    it('tc3_splitRows', 0, () => {
      expect(CharCards.splitRows(0).length).assertEqual(0);
      expect(CharCards.splitRows(1)[0]).assertEqual(1);
      expect(CharCards.splitRows(8)[0]).assertEqual(8);
      let r9: number[] = CharCards.splitRows(9);
      expect(r9.length).assertEqual(2);
      expect(r9[0]).assertEqual(5);
      expect(r9[1]).assertEqual(4);
      let r12: number[] = CharCards.splitRows(12);
      expect(r12.length).assertEqual(2);
      expect(r12[0]).assertEqual(6);
      expect(r12[1]).assertEqual(6);
    });

    /** tc4: 格边自适应 —— 上限 320，行宽不超内容区 740 */
    it('tc4_cellSize', 0, () => {
      expect(CharCards.cellSize(1)).assertEqual(320);
      expect(CharCards.cellSize(4)).assertEqual(170);
      expect(CharCards.cellSize(8)).assertEqual(75);
      for (let n = 1; n <= 12; n++) {
        let rows: number[] = CharCards.splitRows(n);
        for (let i = 0; i < rows.length; i++) {
          let s: number = CharCards.cellSize(rows[i]);
          let total: number = rows[i] * s + (rows[i] - 1) * CharCards.GAP;
          expect(total <= CharCards.CONTENT_W).assertTrue();
          expect(s > 0).assertTrue();
        }
      }
    });

    /** tc5: 输入清洗 —— 去空白、12 字截断 */
    it('tc5_cleanChars', 0, () => {
      expect(CharCards.cleanChars('学 而 时习之')).assertEqual('学而时习之');
      expect(CharCards.cleanChars('  ')).assertEqual('');
      let long: string = '一二三四五六七八九十甲乙丙';
      expect(CharCards.cleanChars(long).length).assertEqual(12);
      expect(CharCards.cleanChars(long)).assertEqual('一二三四五六七八九十甲乙');
    });

    /** tc6: 拼音行分配 —— 音节数匹配时逐行对齐，不匹配时整串置首行 */
    it('tc6_splitPinyinRows', 0, () => {
      let ok: string[] = CharCards.splitPinyinRows('chūn xià qiū dōng', [2, 2]);
      expect(ok.length).assertEqual(2);
      expect(ok[0]).assertEqual('chūn xià');
      expect(ok[1]).assertEqual('qiū dōng');
      let one: string[] = CharCards.splitPinyinRows('xué', [1]);
      expect(one[0]).assertEqual('xué');
      let bad: string[] = CharCards.splitPinyinRows('shēng zì kǎ', [2, 2]);
      expect(bad[0]).assertEqual('shēng zì kǎ');
      expect(bad[1]).assertEqual('');
    });

    /** tc7: 逐字注音（批量导出每卡拼音独立正确）—— PRD 验收 3 */
    it('tc7_perCharPinyin', 0, () => {
      expect(CoverContentUtil.autoPinyin('学')).assertEqual('xué');
      let batch: string[] = ['春', '夏', '秋', '冬'];
      let expectPy: string[] = ['chūn', 'xià', 'qiū', 'dōng'];
      for (let i = 0; i < batch.length; i++) {
        expect(CoverContentUtil.autoPinyin(batch[i])).assertEqual(expectPy[i]);
      }
      expect(CoverContentUtil.autoPinyin('学而时习之')).assertEqual('xué ér shí xí zhī');
    });

    /** tc8: 历史目录隔离 —— card_history 与 cover_history 互不干扰 */
    it('tc8_historyDirIsolation', 0, () => {
      CoverHistoryStore.clearAll(appCtx(), CoverHistoryStore.DIR_CHAR_CARD);
      CoverHistoryStore.clearAll(appCtx(), CoverHistoryStore.DIR_COVER);

      let srcPath: string = appCtx().cacheDir + '/charcard_test_src.png';
      let file: fs.File = fs.openSync(srcPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, 'png-test-bytes');
      } finally {
        fs.closeSync(file.fd);
      }

      let rec: CoverHistoryRecord = CoverHistoryRecord.of(
        'cc1', 'cc_test_1.png', 'square|tian|read', 2, 0,
        '{"chars":"春夏秋冬","pinyin":"chūn xià qiū dōng","pinyinOn":true,"locked":false}', Date.now());
      expect(CoverHistoryStore.saveRecord(appCtx(), srcPath, rec, CoverHistoryStore.DIR_CHAR_CARD)).assertTrue();

      let cardRecords: CoverHistoryRecord[] =
        CoverHistoryStore.loadRecords(appCtx(), CoverHistoryStore.DIR_CHAR_CARD);
      expect(cardRecords.length).assertEqual(1);
      expect(cardRecords[0].templateId).assertEqual('square|tian|read');
      expect(cardRecords[0].textsJson.indexOf('春夏秋冬') >= 0).assertTrue();
      expect(fs.accessSync(CoverHistoryStore.filePath(appCtx(), 'cc_test_1.png',
        CoverHistoryStore.DIR_CHAR_CARD))).assertTrue();

      let coverRecords: CoverHistoryRecord[] =
        CoverHistoryStore.loadRecords(appCtx(), CoverHistoryStore.DIR_COVER);
      expect(coverRecords.length).assertEqual(0);

      CoverHistoryStore.clearAll(appCtx(), CoverHistoryStore.DIR_CHAR_CARD);
      expect(CoverHistoryStore.loadRecords(appCtx(), CoverHistoryStore.DIR_CHAR_CARD).length).assertEqual(0);
    });
  });
}
