/**
 * 数据备份单元测试（1.4.7 Phase 1 测试安全网；1.4.9 M5-C1 纯逻辑化改造）
 * 覆盖：备份文件名 / format 1 与 format 2 解析矩阵（prefs 段收录、gifHistory records
 *       字段还原与非法条目剔除、files base64 解码）/ 非法输入拒绝
 * 前置：1.4.7 将 importBackup 解析段抽为 applyBackupText；1.4.9 C1 进一步抽
 *      parseBackupText + parseGifHistoryRecords 纯函数（applyBackupText 行为零变化）。
 * 注：prefs I/O 回环不在本套件——模拟器 aa test class 过滤模式下进程 context 为壳
 *     （getPreferencesSync 报 "Parameter error. The context is invalid."，1.4.9 M2
 *     四连实验定论），按「用例只测纯逻辑」哲学直测解析纯函数；prefs 落盘与文件恢复
 *     链路由 E2E 备份导入验证 + 真机全套回归（M5 真机）承担。
 */
import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BackupUtil, BackupPayload } from '../../../main/ets/common/utils/BackupUtil';
import { GifHistoryRecord } from '../../../main/ets/core/gif/GifHistoryStore';

/** 模块加载期 delegator 尚未就绪，必须在用例执行期懒获取（仅 tc4 非法输入路径需要，解析抛错不触 I/O） */
function appCtx(): common.Context {
  const delegator: abilityDelegatorRegistry.AbilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();
  return delegator.getAppContext();
}

export default function backupUtilTest() {
  describe('backupUtilTest', () => {

    /** tc1: 备份文件名 PocketToolboxBackup_YYYYMMDD_HHmmss.json */
    it('tc1_buildFileName', 0, () => {
      let name: string = BackupUtil.buildFileName();
      let re: RegExp = new RegExp('^PocketToolboxBackup_\\d{8}_\\d{6}\\.json$');
      expect(re.test(name)).assertTrue();
    });

    /** tc2: format 1 旧备份解析 —— 仅偏好段落收录、gifHistory 恒缺省（GIF 历史不受影响语义） */
    it('tc2_format1PrefsOnly', 0, () => {
      let fixture: string = '{"app":"com.ddabb.toolbox","format":1,"exportedAt":1700000000000,' +
        '"prefs":{"app_cache":{"bk_test_n":42,"bk_test_s":"hello","bk_test_b":true},' +
        '"reading_lists":{},"reading_settings":{}}}';
      let payload: BackupPayload = BackupUtil.parseBackupText(fixture);
      expect(payload.format).assertEqual(1);
      expect(payload.gifHistory === undefined).assertTrue();
      expect(Object.keys(payload.prefsSections).length).assertEqual(3);
      let appCache: Record<string, Object> = payload.prefsSections['app_cache'];
      expect(Number(appCache['bk_test_n'])).assertEqual(42);
      expect(String(appCache['bk_test_s'])).assertEqual('hello');
      expect(appCache['bk_test_b']).assertTrue();
    });

    /** tc3: format 2 解析 —— gifHistory records 字段全量还原（空 id 非法条目剔除）+ files base64 解码 */
    it('tc3_format2WithGifHistory', 0, () => {
      let b64: string = new util.Base64Helper()
        .encodeToStringSync(new Uint8Array([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]));
      let fixture: string = '{"app":"com.ddabb.toolbox","format":2,"exportedAt":1,' +
        '"prefs":{"app_cache":{},"reading_lists":{},"reading_settings":{}},' +
        '"gifHistory":{"records":[' +
        '{"id":"bk1","fileName":"bk1.gif","sizeBytes":6,"exportedAt":111,"width":2,"height":2,' +
        '"frameCount":1,"paramsText":"{}"},' +
        '{"id":"","fileName":"bad.gif","sizeBytes":1,"exportedAt":1,"width":1,"height":1,' +
        '"frameCount":1,"paramsText":"{}"}],' +
        '"files":{"bk1.gif":"' + b64 + '"}}}';
      let payload: BackupPayload = BackupUtil.parseBackupText(fixture);
      expect(payload.format).assertEqual(2);
      let gh: Record<string, Object> | undefined = payload.gifHistory;
      expect(gh !== undefined).assertTrue();
      if (gh === undefined) {
        return;
      }
      let records: GifHistoryRecord[] = BackupUtil.parseGifHistoryRecords(gh);
      expect(records.length).assertEqual(1);
      expect(records[0].id).assertEqual('bk1');
      expect(records[0].fileName).assertEqual('bk1.gif');
      expect(records[0].sizeBytes).assertEqual(6);
      expect(records[0].exportedAt).assertEqual(111);
      expect(records[0].width).assertEqual(2);
      expect(records[0].height).assertEqual(2);
      expect(records[0].frameCount).assertEqual(1);
      expect(records[0].paramsText).assertEqual('{}');
      let files: Record<string, Object> = gh['files'] as Record<string, Object>;
      let bytes: Uint8Array = new util.Base64Helper().decodeSync(files['bk1.gif'] as string);
      expect(bytes.length).assertEqual(6);
      expect(bytes[0]).assertEqual(0x47);
      expect(bytes[1]).assertEqual(0x49);
      expect(bytes[2]).assertEqual(0x46);
      expect(bytes[3]).assertEqual(0x38);
      expect(bytes[4]).assertEqual(0x39);
      expect(bytes[5]).assertEqual(0x61);
    });

    /** tc4: 非法输入 —— 非本应用 / 未知 format / 非 JSON 一律拒绝（解析段抛错，不触 I/O） */
    it('tc4_invalidInput', 0, () => {
      let wrongApp: string = '{"app":"com.other.app","format":2,"prefs":{}}';
      let threw: boolean = false;
      try {
        BackupUtil.applyBackupText(appCtx(), wrongApp);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();

      threw = false;
      try {
        BackupUtil.applyBackupText(appCtx(), '{"app":"com.ddabb.toolbox","format":3,"prefs":{}}');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();

      threw = false;
      try {
        BackupUtil.applyBackupText(appCtx(), 'not a json');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    /** tc5: format 2 空 gifHistory 段 —— 空数组解析为 0 条（全量替换清空语义）；缺 records 键容错 */
    it('tc5_format2EmptyHistory', 0, () => {
      let fixture: string = '{"app":"com.ddabb.toolbox","format":2,"exportedAt":2,' +
        '"prefs":{"app_cache":{},"reading_lists":{},"reading_settings":{}},' +
        '"gifHistory":{"records":[],"files":{}}}';
      let payload: BackupPayload = BackupUtil.parseBackupText(fixture);
      let gh: Record<string, Object> | undefined = payload.gifHistory;
      expect(gh !== undefined).assertTrue();
      if (gh === undefined) {
        return;
      }
      expect(BackupUtil.parseGifHistoryRecords(gh).length).assertEqual(0);
      let noRecs: Record<string, Object> = JSON.parse('{"files":{}}') as Record<string, Object>;
      expect(BackupUtil.parseGifHistoryRecords(noRecs).length).assertEqual(0);
    });
  });
}
