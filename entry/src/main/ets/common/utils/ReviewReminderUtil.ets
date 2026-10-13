/**
 * 复习提醒（每日 19:30 代理提醒）。
 *
 * 2026-10-13 与 CheckInReminderUtil 同批修复（真机实证 publishReminder 报 1700002 配额超限）：
 * 1. 提醒携带固定 groupId（同组一起取消），取消保存的 id 即整组清理，不再累积重复提醒；
 * 2. 发布报 1700002 时兜底 cancelAllReminders 后重试一次（自愈旧版残留）；
 * 3. enable 失败时页面层 toast 提示（reminder_enable_fail）。
 */
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { preferences } from '@kit.ArkData';
import { Context, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class ReviewReminderUtil {
  private static readonly PREFS_NAME: string = 'app_cache';
  private static readonly KEY_REMINDER_ON: string = 'review_reminder_on';
  private static readonly KEY_REMINDER_ID: string = 'review_reminder_id';
  private static readonly BUNDLE_NAME: string = 'com.ddabb.toolbox';
  private static readonly ABILITY_NAME: string = 'EntryAbility';
  private static readonly REMIND_HOUR: number = 19;
  private static readonly REMIND_MINUTE: number = 30;
  private static readonly GROUP_ID: string = 'grp_review';
  private static readonly ERR_QUOTA: number = 1700002;

  static isOn(context: Context): boolean {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: ReviewReminderUtil.PREFS_NAME });
      return prefs.getSync(ReviewReminderUtil.KEY_REMINDER_ON, false) as boolean;
    } catch (e) {
      return false;
    }
  }

  static async enable(context: common.UIAbilityContext): Promise<boolean> {
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
        console.warn('[ReviewReminder] notification not enabled: ' + (e as BusinessError).code.toString());
        try {
          await notificationManager.openNotificationSettings(context);
        } catch (e2) {
          console.warn('[ReviewReminder] openNotificationSettings failed: ' + (e2 as Error).message);
        }
        return false;
      }
    }
    let wantAgentInfo: reminderAgentManager.WantAgent = {
      pkgName: ReviewReminderUtil.BUNDLE_NAME,
      abilityName: ReviewReminderUtil.ABILITY_NAME
    };
    let alarm: reminderAgentManager.ReminderRequestAlarm = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
      hour: ReviewReminderUtil.REMIND_HOUR,
      minute: ReviewReminderUtil.REMIND_MINUTE,
      daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
      title: context.resourceManager.getStringByNameSync('EntryAbility_label'),
      content: context.resourceManager.getStringByNameSync('reminder_review_content'),
      groupId: ReviewReminderUtil.GROUP_ID,
      wantAgent: wantAgentInfo
    };
    try {
      let before: number = -1;
      try {
        before = (await reminderAgentManager.getValidReminders()).length;
      } catch (e) {
        // 诊断信息，获取失败不影响主流程
      }
      await ReviewReminderUtil.cancelPublished(context);
      console.info('[ReviewReminder] valid reminders before publish: ' + before.toString());
      let reminderId: number = await reminderAgentManager.publishReminder(alarm);
      ReviewReminderUtil.saveState(context, true, reminderId);
      console.info('[ReviewReminder] published reminder id=' + reminderId.toString());
      return true;
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[ReviewReminder] publishReminder failed: ' + err.code.toString() + ' ' + err.message);
      if (err.code === ReviewReminderUtil.ERR_QUOTA) {
        try {
          await reminderAgentManager.cancelAllReminders();
          let reminderId: number = await reminderAgentManager.publishReminder(alarm);
          ReviewReminderUtil.saveState(context, true, reminderId);
          console.warn('[ReviewReminder] quota full, wiped all reminders and republished id=' + reminderId.toString());
          return true;
        } catch (e2) {
          console.error('[ReviewReminder] republish after wipe failed: ' + (e2 as BusinessError).message);
          return false;
        }
      }
      return false;
    }
  }

  static async disable(context: common.UIAbilityContext): Promise<void> {
    try {
      await ReviewReminderUtil.cancelPublished(context);
    } catch (e) {
      console.warn('[ReviewReminder] cancel on disable failed: ' + (e as Error).message);
    }
    ReviewReminderUtil.saveState(context, false, -1);
  }

  private static async cancelPublished(context: Context): Promise<void> {
    let reminderId: number = ReviewReminderUtil.loadReminderId(context);
    if (reminderId >= 0) {
      try {
        await reminderAgentManager.cancelReminder(reminderId);
      } catch (e) {
        console.warn('[ReviewReminder] cancelReminder failed: ' + (e as Error).message);
      }
    }
  }

  private static loadReminderId(context: Context): number {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: ReviewReminderUtil.PREFS_NAME });
      return prefs.getSync(ReviewReminderUtil.KEY_REMINDER_ID, -1) as number;
    } catch (e) {
      return -1;
    }
  }

  private static saveState(context: Context, on: boolean, reminderId: number): void {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: ReviewReminderUtil.PREFS_NAME });
      prefs.putSync(ReviewReminderUtil.KEY_REMINDER_ON, on);
      prefs.putSync(ReviewReminderUtil.KEY_REMINDER_ID, reminderId);
      prefs.flush();
    } catch (e) {
      console.error('[ReviewReminder] saveState failed: ' + (e as Error).message);
    }
  }
}
