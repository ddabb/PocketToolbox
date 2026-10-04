import { Context } from '@kit.AbilityKit';
import { StickinessUtil, CheckInData } from './StickinessUtil';

// 签到状态卡片数据构造：复用首页既有文案键（daily_checkin / checked_in / not_checked_in /
// streak_days / tap_to_checkin / streak_so_far / start_streak），无需新增业务键
export class CheckInWidgetUtil {
  static buildCardData(context: Context, dimension: string = ''): Record<string, string> {
    let data: CheckInData = StickinessUtil.loadCheckIn(context);
    let checkedIn: boolean = data.lastDate === StickinessUtil.todayStr();

    let title: string = context.resourceManager.getStringByNameSync('daily_checkin');
    let status: string = context.resourceManager.getStringByNameSync(checkedIn ? 'checked_in' : 'not_checked_in');
    let streakText: string = context.resourceManager.getStringByNameSync('streak_days', data.streak);
    let hint: string;
    if (!checkedIn) {
      hint = context.resourceManager.getStringByNameSync('tap_to_checkin');
    } else if (data.streak > 0) {
      hint = context.resourceManager.getStringByNameSync('streak_so_far', data.streak);
    } else {
      hint = context.resourceManager.getStringByNameSync('start_streak');
    }

    let cardData: Record<string, string> = {
      'title': title,
      'checkedIn': checkedIn ? '1' : '0',
      'status': status,
      'streak': data.streak.toString(),
      'streakText': streakText,
      'hint': hint,
      'dimension': dimension
    };
    return cardData;
  }
}
