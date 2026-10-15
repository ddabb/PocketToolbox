/**
 * 数据备份单元测试（1.4.7 Phase 1 测试安全网）
 * 覆盖：备份文件名 / format 1（仅偏好）与 format 2（偏好+GIF 历史）兼容矩阵 / 非法输入拒绝
 * 前置：1.4.7 Phase 1 将 importBackup 的解析应用段抽为 applyBackupText（行为零变化）
 */
import { describe, it, expect, beforeAll, afterAll } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BackupUtil } from '../../../main/ets/common/utils/BackupUtil';
import { GifHistoryStore, GifHistoryRecord } from '../../../main/ets/core/gif/GifHistoryStore';

/** 模块加载期 delegator 尚未就绪，必须在用例执行期懒获取 */
function appCtx(): common.Context {
  const delegator: abilityDelegatorRegistry.AbilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();
  return delegator.getAppContext();
}

function seedRecord(id: string, fileName: string): GifHistoryRecord {
  let r: GifHistoryRecord = new GifHistoryRecord();
  r.id = id;
  r.fileName = fileName;
  r.sizeBytes = 6;
  r.exportedAt = 111;
  r.width = 2;
  r.height = 2;
  r.frameCount = 1;
  r.paramsText = '{}';
  return r;
}

export default function backupUtilTest() {
  describe('backupUtilTest', () => {
    beforeAll(() => {
      GifHistoryStore.replaceAll(appCtx(), []);
    });

    afterAll(() => {
      let p: preferences.Preferences = preferences.getPreferencesSync(appCtx(), { name: 'app_cache' });
      p.deleteSync('bk_test_n');
      p.deleteSync('bk_test_s');
      p.deleteSync('bk_test_b');
      p.flush();
      GifHistoryStore.replaceAll(appCtx(), []);
    });

    /** tc1: 备份文件名 PocketToolboxBackup_YYYYMMDD_HHmmss.json */
    it('tc1_buildFileName', 0, () => {
      let name: string = BackupUtil.buildFileName();
      let re: RegExp = new RegExp('^PocketToolboxBackup_\\d{8}_\\d{6}\\.json$');
      expect(re.test(name)).assertTrue();
    });

    /** tc2: format 1 旧备份 —— 仅偏好生效，GIF 历史不受影响 */
    it('tc2_format1PrefsOnly', 0, () => {
      GifHistoryStore.replaceAll(appCtx(), [seedRecord('seed1', 'seed1.gif')]);
      let fixture: string = '{"app":"com.ddabb.toolbox","format":1,"exportedAt":1700000000000,' +
        '"prefs":{"app_cache":{"bk_test_n":42,"bk_test_s":"hello","bk_test_b":true},' +
        '"reading_lists":{},"reading_settings":{}}}';
      expect(BackupUtil.applyBackupText(appCtx(), fixture)).assertTrue();
      let p: preferences.Preferences = preferences.getPreferencesSync(appCtx(), { name: 'app_cache' });
      expect(p.getSync('bk_test_n', 0)).assertEqual(42);
      expect(p.getSync('bk_test_s', '')).assertEqual('hello');
      expect(p.getSync('bk_test_b', false)).assertTrue();
      let recs: GifHistoryRecord[] = GifHistoryStore.loadRecords(appCtx());
      expect(recs.length).assertEqual(1);
      expect(recs[0].id).assertEqual('seed1');
    });

    /** tc3: format 2 —— 偏好 + GIF 历史全量替换（索引与文件本体 base64 落盘） */
    it('tc3_format2WithGifHistory', 0, () => {
      let b64: string = new util.Base64Helper()
        .encodeToStringSync(new Uint8Array([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]));
      let fixture: string = '{"app":"com.ddabb.toolbox","format":2,"exportedAt":1,' +
        '"prefs":{"app_cache":{},"reading_lists":{},"reading_settings":{}},' +
        '"gifHistory":{"records":[' +
        '{"id":"bk1","fileName":"bk1.gif","sizeBytes":6,"exportedAt":111,"width":2,"height":2,' +
        '"frameCount":1,"paramsText":"{}"}],' +
        '"files":{"bk1.gif":"' + b64 + '"}}}';
      expect(BackupUtil.applyBackupText(appCtx(), fixture)).assertTrue();
      let recs: GifHistoryRecord[] = GifHistoryStore.loadRecords(appCtx());
      expect(recs.length).assertEqual(1);
      expect(recs[0].id).assertEqual('bk1');
      expect(recs[0].fileName).assertEqual('bk1.gif');
      expect(recs[0].frameCount).assertEqual(1);
      let path: string = GifHistoryStore.historyDir(appCtx()) + '/bk1.gif';
      expect(fs.accessSync(path)).assertTrue();
      let f: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
      let buf: ArrayBuffer = new ArrayBuffer(6);
      fs.readSync(f.fd, buf);
      fs.closeSync(f);
      let bytes: Uint8Array = new Uint8Array(buf);
      expect(bytes[0]).assertEqual(0x47);
      expect(bytes[1]).assertEqual(0x49);
      expect(bytes[2]).assertEqual(0x46);
      expect(bytes[3]).assertEqual(0x38);
      expect(bytes[4]).assertEqual(0x39);
      expect(bytes[5]).assertEqual(0x61);
    });

    /** tc4: 非法输入 —— 非本应用 / 未知 format / 非 JSON 一律拒绝（抛错不落盘） */
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

    /** tc5: format 2 空 gifHistory 段 —— 全量替换语义：清空本地历史 */
    it('tc5_format2EmptyHistory', 0, () => {
      let recs: GifHistoryRecord[] = GifHistoryStore.loadRecords(appCtx());
      expect(recs.length).assertEqual(1);
      let fixture: string = '{"app":"com.ddabb.toolbox","format":2,"exportedAt":2,' +
        '"prefs":{"app_cache":{},"reading_lists":{},"reading_settings":{}},' +
        '"gifHistory":{"records":[],"files":{}}}';
      expect(BackupUtil.applyBackupText(appCtx(), fixture)).assertTrue();
      expect(GifHistoryStore.loadRecords(appCtx()).length).assertEqual(0);
    });
  });
}
