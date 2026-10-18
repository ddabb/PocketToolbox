/**
 * 文案海报内容模型 - 单元测试（1.4.8 §4 验收项；1.4.9 M1-A1 附加槽位）
 * 覆盖：CopyPosterContent 序列化回环（coupletUp/coupletDown/avatarUri/1.4.9 附加槽位缺省容错）
 *      / copy 深拷贝独立性 / T18 定制槽位声明 / T12 头像能力声明 / T5-T10 附加槽位声明
 */
import { describe, it, expect } from '@ohos/hypium';
import { CopyPosterContent, CopyPosterSlot, CopyPosterSlotDef } from '../../../main/ets/model/CopyPosterModels';
import { CopyPosterTemplates } from '../../../main/ets/core/cover/CopyPosterTemplates';

export default function copyPosterTest() {
  describe('copyPosterTest', () => {

    /** tc1: 序列化回环 —— 8 字段全量 toJson→fromJson 逐字段相等 */
    it('tc1_contentRoundTrip', 0, () => {
      let c: CopyPosterContent = new CopyPosterContent();
      c.body = '岁岁平安，万事胜意';
      c.sign = '随身工具宝';
      c.tag = '新春大吉';
      c.coupletUp = '岁岁平安福常在';
      c.coupletDown = '年年顺意喜盈门';
      c.softLeft = '菜单';
      c.softRight = '返回';
      c.screenSlogan = 'POCKET SYSTEM';
      c.boardTitle = 'INFO BOARD';
      c.avatarUri = '/data/app/el2/100/base/com.ddabb.toolbox/files/poster_avatar/test.png';
      c.watermarkOn = true;
      c.watermarkText = '@解语珠玑';
      let back: CopyPosterContent = CopyPosterContent.fromJson(c.toJson());
      expect(back.body).assertEqual(c.body);
      expect(back.sign).assertEqual(c.sign);
      expect(back.tag).assertEqual(c.tag);
      expect(back.coupletUp).assertEqual(c.coupletUp);
      expect(back.coupletDown).assertEqual(c.coupletDown);
      expect(back.softLeft).assertEqual(c.softLeft);
      expect(back.softRight).assertEqual(c.softRight);
      expect(back.screenSlogan).assertEqual(c.screenSlogan);
      expect(back.boardTitle).assertEqual(c.boardTitle);
      expect(back.avatarUri).assertEqual(c.avatarUri);
      expect(back.watermarkOn).assertTrue();
      expect(back.watermarkText).assertEqual(c.watermarkText);
    });

    /** tc2: 旧记录缺省容错 —— 1.4.8 前历史 JSON 无 coupletUp/coupletDown/avatarUri/watermark 键 */
    it('tc2_legacyDefaults', 0, () => {
      let legacy: string = JSON.stringify({ 'body': '世界很大', 'sign': '记者 木木', 'tag': '随身日报' });
      let c: CopyPosterContent = CopyPosterContent.fromJson(legacy);
      expect(c.body).assertEqual('世界很大');
      expect(c.sign).assertEqual('记者 木木');
      expect(c.tag).assertEqual('随身日报');
      expect(c.coupletUp).assertEqual('');
      expect(c.coupletDown).assertEqual('');
      expect(c.softLeft).assertEqual('');
      expect(c.softRight).assertEqual('');
      expect(c.screenSlogan).assertEqual('');
      expect(c.boardTitle).assertEqual('');
      expect(c.avatarUri).assertEqual('');
      expect(c.watermarkOn).assertFalse();
      expect(c.watermarkText).assertEqual('');
    });

    /** tc3: 非法 JSON 容错 —— 解析失败回退全缺省，不抛异常 */
    it('tc3_malformedJson', 0, () => {
      let c: CopyPosterContent = CopyPosterContent.fromJson('not a json {{{');
      expect(c.body).assertEqual('');
      expect(c.coupletUp).assertEqual('');
      expect(c.coupletDown).assertEqual('');
      expect(c.avatarUri).assertEqual('');
      expect(c.watermarkOn).assertFalse();
    });

    /** tc4: copy 深拷贝独立 —— 改副本不影响原对象（onSlotChange 的 copy→mutate→reassign 依赖） */
    it('tc4_copyIndependence', 0, () => {
      let c: CopyPosterContent = new CopyPosterContent();
      c.body = '原文';
      c.coupletUp = '上联';
      c.avatarUri = '/a/b.png';
      let copy: CopyPosterContent = c.copy();
      copy.body = '改后';
      copy.coupletUp = '改联';
      copy.avatarUri = '';
      expect(c.body).assertEqual('原文');
      expect(c.coupletUp).assertEqual('上联');
      expect(c.avatarUri).assertEqual('/a/b.png');
      expect(copy.body).assertEqual('改后');
    });

    /** tc5: T18 定制槽位声明 —— 上/下联各 maxLen 14，默认值含对联键，固定构图不支持注音 */
    it('tc5_t18CustomSlots', 0, () => {
      let t18 = CopyPosterTemplates.getById('T18');
      expect(t18.customSlots.length).assertEqual(2);
      expect(t18.customSlots[0].id).assertEqual(CopyPosterSlot.COUPLET_UP);
      expect(t18.customSlots[0].maxLen).assertEqual(14);
      expect(t18.customSlots[1].id).assertEqual(CopyPosterSlot.COUPLET_DOWN);
      expect(t18.customSlots[1].maxLen).assertEqual(14);
      expect(t18.defaults['coupletUp'] !== undefined).assertTrue();
      expect(t18.defaults['coupletDown'] !== undefined).assertTrue();
      expect(t18.supportsPinyin).assertFalse();
    });

    /** tc6: T12 头像能力唯一性 —— 全注册表仅 T12 声明 supportsAvatar */
    it('tc6_t12AvatarOnly', 0, () => {
      let all = CopyPosterTemplates.all();
      let avatarIds: string[] = [];
      for (let i = 0; i < all.length; i++) {
        if (all[i].supportsAvatar) {
          avatarIds.push(all[i].id);
        }
      }
      expect(avatarIds.length).assertEqual(1);
      expect(avatarIds[0]).assertEqual('T12');
    });

    /** tc7: 槽位 id 与内容字段名一致性 —— onSlotChange/slotValueOf 泛化取值的隐式契约 */
    it('tc7_slotIdFieldContract', 0, () => {
      expect(CopyPosterSlot.COUPLET_UP).assertEqual('coupletUp');
      expect(CopyPosterSlot.COUPLET_DOWN).assertEqual('coupletDown');
      expect(CopyPosterSlot.BODY).assertEqual('body');
      expect(CopyPosterSlot.SIGN).assertEqual('sign');
      expect(CopyPosterSlot.TAG).assertEqual('tag');
      let d: CopyPosterSlotDef = CopyPosterSlotDef.of('coupletUp', '上联', 14);
      expect(d.id).assertEqual('coupletUp');
      expect(d.maxLen).assertEqual(14);
      expect(CopyPosterSlot.SOFT_LEFT).assertEqual('softLeft');
      expect(CopyPosterSlot.SOFT_RIGHT).assertEqual('softRight');
      expect(CopyPosterSlot.SCREEN_SLOGAN).assertEqual('screenSlogan');
      expect(CopyPosterSlot.BOARD_TITLE).assertEqual('boardTitle');
    });

    /** tc8: 1.4.9 附加槽位声明 —— T5 软键×2 / T8 屏下标语 / T10 表头标题；全注册表仅此 3 模板，customSlots 替换语义不混用 */
    it('tc8_extraSlots', 0, () => {
      let t5 = CopyPosterTemplates.getById('T5');
      expect(t5.extraSlots.length).assertEqual(2);
      expect(t5.extraSlots[0].id).assertEqual(CopyPosterSlot.SOFT_LEFT);
      expect(t5.extraSlots[0].maxLen).assertEqual(4);
      expect(t5.extraSlots[1].id).assertEqual(CopyPosterSlot.SOFT_RIGHT);
      expect(t5.extraSlots[1].maxLen).assertEqual(4);
      expect(t5.customSlots.length).assertEqual(0);
      let t8 = CopyPosterTemplates.getById('T8');
      expect(t8.extraSlots.length).assertEqual(1);
      expect(t8.extraSlots[0].id).assertEqual(CopyPosterSlot.SCREEN_SLOGAN);
      expect(t8.extraSlots[0].maxLen).assertEqual(24);
      expect(t8.customSlots.length).assertEqual(0);
      let t10 = CopyPosterTemplates.getById('T10');
      expect(t10.extraSlots.length).assertEqual(1);
      expect(t10.extraSlots[0].id).assertEqual(CopyPosterSlot.BOARD_TITLE);
      expect(t10.extraSlots[0].maxLen).assertEqual(16);
      expect(t10.customSlots.length).assertEqual(0);
      let all = CopyPosterTemplates.all();
      let extraIds: string[] = [];
      for (let i = 0; i < all.length; i++) {
        if (all[i].extraSlots.length > 0) {
          extraIds.push(all[i].id);
        }
      }
      expect(extraIds.length).assertEqual(3);
      expect(extraIds[0]).assertEqual('T5');
      expect(extraIds[1]).assertEqual('T8');
      expect(extraIds[2]).assertEqual('T10');
    });
  });
}
