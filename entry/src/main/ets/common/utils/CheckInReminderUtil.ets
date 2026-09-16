import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { preferences } from '@kit.ArkData';
import { Context, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class CheckInReminderUtil {
  private static readonly PREFS_NAME: string = 'app_cache';
  private static readonly KEY_REMINDER_ON: string = 'daily_reminder_on';
  private static readonly KEY_REMINDER_ID: string = 'daily_reminder_id';
  private static readonly BUNDLE_NAME: string = 'com.ddabb.toolbox';
  private static readonly ABILITY_NAME: string = 'EntryAbility';
  private static readonly REMIND_HOUR: number = 20;
  private static readonly REMIND_MINUTE: number = 0;

  static isOn(context: Context): boolean {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: CheckInReminderUtil.PREFS_NAME });
      return prefs.getSync(CheckInReminderUtil.KEY_REMINDER_ON, false) as boolean;
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
        console.warn('[CheckInReminder] notification not enabled: ' + (e as BusinessError).code.toString());
        try {
          await notificationManager.openNotificationSettings(context);
        } catch (e2) {
          console.warn('[CheckInReminder] openNotificationSettings failed: ' + (e2 as Error).message);
        }
        return false;
      }
    }
    try {
      await CheckInReminderUtil.cancelPublished(context);
      let wantAgentInfo: reminderAgentManager.WantAgent = {
        pkgName: CheckInReminderUtil.BUNDLE_NAME,
        abilityName: CheckInReminderUtil.ABILITY_NAME
      };
      let alarm: reminderAgentManager.ReminderRequestAlarm = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
        hour: CheckInReminderUtil.REMIND_HOUR,
        minute: CheckInReminderUtil.REMIND_MINUTE,
        daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
        title: '解语珠玑',
        content: '今天还没签到打卡，每日挑战等你来战！',
        wantAgent: wantAgentInfo
      };
      let reminderId: number = await reminderAgentManager.publishReminder(alarm);
      CheckInReminderUtil.saveState(context, true, reminderId);
      console.info('[CheckInReminder] published reminder id=' + reminderId.toString());
      return true;
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[CheckInReminder] publishReminder failed: ' + err.code.toString() + ' ' + err.message);
      return false;
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
        console.error('[CheckInReminder] cancelReminder failed: ' + (e as Error).message);
        throw new Error((e as Error).message);
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
