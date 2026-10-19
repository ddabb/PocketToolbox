/**
 * 生字卡 - 单元测试
 * 覆盖：配色/尺寸常量、格数自适应公式、行拆分、句子模式词装箱、清洗截断、
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

    /**
     * tc2: 尺寸常量 —— 方卡 1080x1080、练习卡 1080x1440
     * 1.4.9 C1 修复：label 自 zh_Hant 迁移后为 $r 资源引用。断言语义=id 接线比对——测试构建与
     * 主代码同表编译，label.id 与测试内 $r 常量同表同值即接线正确且 locale 无关；解析式断言不可用
     * （测试进程资源管理器未加载测试包索引，getStringSync(id) 报 Invalid resource ID），zh 值由
     * E2E 渲染与 check_strings.py 兜底。
     */
    it('tc2_sizes', 0, () => {
      expect(CharCards.EXPORT_W).assertEqual(1080);
      expect(CharCards.EXPORT_H_SQUARE).assertEqual(1080);
      expect(CharCards.EXPORT_H_PRACTICE).assertEqual(1440);
      expect(CharCards.designHeight(CharCardSize.SQUARE)).assertEqual(900);
      expect(CharCards.designHeight(CharCardSize.PRACTICE)).assertEqual(1200);
      let sizeLabel: ResourceStr = CharCardSize.label(CharCardSize.PRACTICE);
      expect(typeof sizeLabel !== 'string').assertTrue();
      if (typeof sizeLabel !== 'string') {
        expect(sizeLabel.id).assertEqual($r('app.string.tmpl_size_practice').id);
      }
      let gridLabel: ResourceStr = CharCardGridType.label(CharCardGridType.MI);
      expect(typeof gridLabel !== 'string').assertTrue();
      if (typeof gridLabel !== 'string') {
        expect(gridLabel.id).assertEqual($r('app.string.tmpl_grid_mi').id);
      }
      let modeLabel: ResourceStr = CharCardCharMode.label(CharCardCharMode.TRACE);
      expect(typeof modeLabel !== 'string').assertTrue();
      if (typeof modeLabel !== 'string') {
        expect(modeLabel.id).assertEqual($r('app.string.tmpl_mode_trace').id);
      }
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

    /** tc4: 格边自适应 —— min(maxCell, (CONTENT_W-(rowLen-1)*GAP)/rowLen)，行宽不超内容区 740 */
    it('tc4_cellSize', 0, () => {
      expect(CharCards.cellSize(1, CharCards.MAX_CELL)).assertEqual(320);
      expect(CharCards.cellSize(4, CharCards.MAX_CELL)).assertEqual(170);
      expect(CharCards.cellSize(8, CharCards.MAX_CELL)).assertEqual(75);
      expect(CharCards.cellSize(0, CharCards.MAX_CELL)).assertEqual(0);
      expect(CharCards.cellSize(1, CharCards.MAX_CELL_COVER)).assertEqual(280);
      for (let n = 1; n <= 12; n++) {
        let rows: number[] = CharCards.splitRows(n);
        for (let i = 0; i < rows.length; i++) {
          let s: number = CharCards.cellSize(rows[i], CharCards.MAX_CELL);
          let total: number = rows[i] * s + (rows[i] - 1) * CharCards.GAP;
          expect(total <= CharCards.CONTENT_W + 1e-6).assertTrue();
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

    /** tc6: 句子模式 —— 词截断 capWords（整词溢出即丢弃）与按词行拆分 splitRowsByWords（词不跨行）
     *  注：旧版 splitPinyinRows 已随拼音槽位逻辑移入 CharCardPreview 删除，此处改测现行 API */
    it('tc6_sentenceRows', 0, () => {
      let kept: string[] = CharCards.capWords(['春天', '夏天'], 12);
      expect(kept.length).assertEqual(2);
      let drop: string[] = CharCards.capWords(['一二三四五六七八', '九'], 8);
      expect(drop.length).assertEqual(1);
      expect(drop[0]).assertEqual('一二三四五六七八');
      let head: string[] = CharCards.capWords(['一二三四五六七八九十'], 5);
      expect(head.length).assertEqual(1);
      expect(head[0]).assertEqual('一二三四五');

      let one: number[] = CharCards.splitRowsByWords(CharCardSize.SQUARE, ['春天', '夏天', '秋天', '冬天']);
      expect(one.length).assertEqual(1);
      expect(one[0]).assertEqual(8);
      let two: number[] = CharCards.splitRowsByWords(CharCardSize.SQUARE, ['春天', '夏天', '秋天', '冬雪啊']);
      expect(two.length).assertEqual(2);
      expect(two[0]).assertEqual(6);
      expect(two[1]).assertEqual(3);
      let chunk: number[] = CharCards.splitRowsByWords(CharCardSize.SQUARE, ['一二三四五六七八九']);
      expect(chunk.length).assertEqual(2);
      expect(chunk[0]).assertEqual(8);
      expect(chunk[1]).assertEqual(1);
      let cover: number[] = CharCards.splitRowsByWords(CharCardSize.COVER, ['春天', '夏天', '秋天', '冬天']);
      expect(cover.length).assertEqual(1);
      expect(cover[0]).assertEqual(8);
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
