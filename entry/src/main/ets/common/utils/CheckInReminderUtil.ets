/**
 * 每日签到提醒（20:00 代理提醒）。
 *
 * 2026-10-13 修复（真机 Mate 60 Pro 实证 publishReminder 报 1700002 配额超限）：
 * 1. 旧版仅保存单个 reminderId，取消失败/数据残留时会累积重复提醒直至配额满（单应用上限 30）；
 * 2. 现所有签到提醒携带固定 groupId（同组提醒会被系统一起取消），取消保存的 id 即整组清理；
 * 3. 发布仍报 1700002 时兜底：cancelAllReminders 清空本应用全部提醒后重试一次（自愈旧版无
 *    groupId 的残留；副作用是同应用的其他代理提醒会被一并清掉，其开关状态由下次开关周期重新同步）；
 * 4. enable 失败时页面层 toast 提示（reminder_enable_fail），不再静默弹回。
 *
 * 2026-10-17 诊断（模拟器 API24 实证 + 官方错误码文档）：
 * publishReminder 报 1700002 且 getValidReminders()===0、清空重发仍 1700002，
 * 为官方定义的「无代理提醒配额」状态（应用未获 AGC「代理提醒」开放能力授权时配额视为 0），
 * 与本地残留无关（重启/卸载重装均无效）；授权通过后需重新生成 Profile 并重新签名才生效。
 * enable() 对该场景返回 NO_QUOTA，页面层提示 reminder_no_quota（不再误导用户去检查通知设置）。
 */
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { preferences } from '@kit.ArkData';
import { Context, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

export enum ReminderEnableStatus {
  OK = 0,
  NOTIFICATION_DISABLED = 1,
  NO_QUOTA = 2,
  FAILED = 3
}

export class CheckInReminderUtil {
  private static readonly PREFS_NAME: string = 'app_cache';
  private static readonly KEY_REMINDER_ON: string = 'daily_reminder_on';
  private static readonly KEY_REMINDER_ID: string = 'daily_reminder_id';
  private static readonly BUNDLE_NAME: string = 'com.ddabb.toolbox';
  private static readonly ABILITY_NAME: string = 'EntryAbility';
  private static readonly REMIND_HOUR: number = 20;
  private static readonly REMIND_MINUTE: number = 0;
  private static readonly GROUP_ID: string = 'grp_daily_checkin';
  private static readonly ERR_QUOTA: number = 1700002;

  static isOn(context: Context): boolean {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: CheckInReminderUtil.PREFS_NAME });
      return prefs.getSync(CheckInReminderUtil.KEY_REMINDER_ON, false) as boolean;
    } catch (e) {
      return false;
    }
  }

  static async enable(context: common.UIAbilityContext): Promise<ReminderEnableStatus> {
    let enabled: boolean = false;
    try {
      enabled = notificationManager.isNotificationEnabledSync();
    } catch (e) {
      enabled = false;
    }
    if (!enabled) {
      try {
        await notificationManager.requestEnableNotification(context);
      } catch (e) {
        console.warn('[CheckInReminder] notification not enabled: ' + (e as BusinessError).code.toString());
        try {
          await notificationManager.openNotificationSettings(context);
        } catch (e2) {
          console.warn('[CheckInReminder] openNotificationSettings failed: ' + (e2 as Error).message);
        }
        return ReminderEnableStatus.NOTIFICATION_DISABLED;
      }
    }
    let wantAgentInfo: reminderAgentManager.WantAgent = {
      pkgName: CheckInReminderUtil.BUNDLE_NAME,
      abilityName: CheckInReminderUtil.ABILITY_NAME
    };
    let alarm: reminderAgentManager.ReminderRequestAlarm = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
      hour: CheckInReminderUtil.REMIND_HOUR,
      minute: CheckInReminderUtil.REMIND_MINUTE,
      daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
      title: context.resourceManager.getStringByNameSync('EntryAbility_label'),
      content: context.resourceManager.getStringByNameSync('reminder_checkin_content'),
      groupId: CheckInReminderUtil.GROUP_ID,
      wantAgent: wantAgentInfo
    };
    try {
      let before: number = -1;
      try {
        before = (await reminderAgentManager.getValidReminders()).length;
      } catch (e) {
        // 诊断信息，获取失败不影响主流程
      }
      await CheckInReminderUtil.cancelPublished(context);
      console.info('[CheckInReminder] valid reminders before publish: ' + before.toString());
      let reminderId: number = await reminderAgentManager.publishReminder(alarm);
      CheckInReminderUtil.saveState(context, true, reminderId);
      console.info('[CheckInReminder] published reminder id=' + reminderId.toString());
      return ReminderEnableStatus.OK;
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[CheckInReminder] publishReminder failed: ' + err.code.toString() + ' ' + err.message);
      if (err.code === CheckInReminderUtil.ERR_QUOTA) {
        try {
          await reminderAgentManager.cancelAllReminders();
          let reminderId: number = await reminderAgentManager.publishReminder(alarm);
          CheckInReminderUtil.saveState(context, true, reminderId);
          console.warn('[CheckInReminder] quota full, wiped all reminders and republished id=' + reminderId.toString());
          return ReminderEnableStatus.OK;
        } catch (e2) {
          let err2: BusinessError = e2 as BusinessError;
          console.error('[CheckInReminder] republish after wipe failed: ' + err2.code.toString() + ' ' + err2.message);
          if (err2.code === CheckInReminderUtil.ERR_QUOTA) {
            return ReminderEnableStatus.NO_QUOTA;
          }
          return ReminderEnableStatus.FAILED;
        }
      }
      return ReminderEnableStatus.FAILED;
    }
  }

  static async disable(context: Context): Promise<void> {
    try {
      await CheckInReminderUtil.cancelPublished(context);
    } catch (e) {
      console.warn('[CheckInReminder] cancel on disable failed: ' + (e as Error).message);
    }
    CheckInReminderUtil.saveState(context, false, -1);
  }

  private static async cancelPublished(context: Context): Promise<void> {
    let reminderId: number = CheckInReminderUtil.loadReminderId(context);
    if (reminderId >= 0) {
      try {
        await reminderAgentManager.cancelReminder(reminderId);
      } catch (e) {
        console.warn('[CheckInReminder] cancelReminder failed: ' + (e as Error).message);
      }
    }
  }

  private static loadReminderId(context: Context): number {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: CheckInReminderUtil.PREFS_NAME });
      return prefs.getSync(CheckInReminderUtil.KEY_REMINDER_ID, -1) as number;
    } catch (e) {
      return -1;
    }
  }

  private static saveState(context: Context, on: boolean, reminderId: number): void {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: CheckInReminderUtil.PREFS_NAME });
      prefs.putSync(CheckInReminderUtil.KEY_REMINDER_ON, on);
      prefs.putSync(CheckInReminderUtil.KEY_REMINDER_ID, reminderId);
      prefs.flush();
    } catch (e) {
      console.error('[CheckInReminder] saveState failed: ' + (e as Error).message);
    }
  }
}
