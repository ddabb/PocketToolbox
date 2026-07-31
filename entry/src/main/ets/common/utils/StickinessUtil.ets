import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';

export class CheckInData {
  lastDate: string = '';
  streak: number = 0;
  totalDays: number = 0;
  dates: string[] = [];
}

export class AchievementItem {
  id: string = '';
  title: string = '';
  desc: string = '';
  icon: string = '';
  color: string = '';
  target: number = 0;
  current: number = 0;
  unlocked: boolean = false;
  unlockedAt: number = 0;

  static create(id: string, title: string, desc: string, icon: string, color: string,
    target: number): AchievementItem {
    let item: AchievementItem = new AchievementItem();
    item.id = id;
    item.title = title;
    item.desc = desc;
    item.icon = icon;
    item.color = color;
    item.target = target;
    item.current = 0;
    item.unlocked = false;
    item.unlockedAt = 0;
    return item;
  }
}

export class UserStats {
  favPoems: number = 0;
  favIdioms: number = 0;
  favXiehouyu: number = 0;
  favTotal: number = 0;
  browseCount: number = 0;
  checkInStreak: number = 0;
  checkInTotal: number = 0;
  challengeTotal: number = 0;
  readingItems: number = 0;
  readingMinutes: number = 0;
  toolUseCount: number = 0;
}

class AchievementDef {
  id: string = '';
  title: string = '';
  desc: string = '';
  icon: string = '';
  color: string = '';
  target: number = 0;
  statKey: string = '';

  constructor(id: string, title: string, desc: string, icon: string, color: string,
    target: number, statKey: string) {
    this.id = id;
    this.title = title;
    this.desc = desc;
    this.icon = icon;
    this.color = color;
    this.target = target;
    this.statKey = statKey;
  }
}

export class StickinessUtil {
  private static readonly PREFS_NAME: string = 'app_cache';
  private static readonly KEY_CHECK_IN: string = 'stickiness_check_in';
  private static readonly KEY_ACHIEVEMENTS: string = 'stickiness_achievements';
  private static readonly KEY_STATS: string = 'stickiness_stats';
  private static readonly KEY_CHALLENGE: string = 'stickiness_challenge';
  private static readonly KEY_PREFS: string = 'stickiness_prefs';

  private static readonly ACHIEVEMENT_DEFS: AchievementDef[] = [
    new AchievementDef('fav_10', '收藏新手', '累计收藏10项', '\u2665', '#e74c3c', 10, 'favTotal'),
    new AchievementDef('fav_50', '收藏达人', '累计收藏50项', '\u2665', '#e74c3c', 50, 'favTotal'),
    new AchievementDef('fav_100', '收藏大师', '累计收藏100项', '\u2665', '#e74c3c', 100, 'favTotal'),
    new AchievementDef('poem_fav_20', '诗词爱好者', '收藏诗词20首', '\uD83C\uDF3C', '#2d7d46', 20, 'favPoems'),
    new AchievementDef('poem_fav_50', '诗词鉴赏家', '收藏诗词50首', '\uD83C\uDF3C', '#2d7d46', 50, 'favPoems'),
    new AchievementDef('idiom_fav_20', '成语收藏家', '收藏成语20个', '\uD83D\uDCD6', '#2980b9', 20, 'favIdioms'),
    new AchievementDef('checkin_7', '坚持一周', '连续签到7天', '\uD83D\uDCC5', '#f39c12', 7, 'checkInStreak'),
    new AchievementDef('checkin_30', '月度学霸', '连续签到30天', '\uD83D\uDCC5', '#f39c12', 30, 'checkInStreak'),
    new AchievementDef('checkin_total_30', '学习习惯', '累计签到30天', '\u2705', '#27ae60', 30, 'checkInTotal'),
    new AchievementDef('challenge_10', '挑战新秀', '完成10次每日挑战', '\uD83C\uDFC6', '#8e44ad', 10, 'challengeTotal'),
    new AchievementDef('challenge_50', '挑战达人', '完成50次每日挑战', '\uD83C\uDFC6', '#8e44ad', 50, 'challengeTotal'),
    new AchievementDef('browse_100', '勤奋读者', '累计浏览100次', '\uD83D\uDC41', '#3498db', 100, 'browseCount'),
    new AchievementDef('browse_500', '博览群书', '累计浏览500次', '\uD83D\uDC41', '#3498db', 500, 'browseCount'),
    new AchievementDef('reading_10', '朗读者', '朗读10篇内容', '\uD83D\uDD0A', '#1abc9c', 10, 'readingItems'),
    new AchievementDef('tool_5', '工具探索者', '使用5种不同工具', '\uD83D\uDD27', '#e67e22', 5, 'toolUseCount'),
  ];

  static todayStr(): string {
    let now: Date = new Date();
    let y: number = now.getFullYear();
    let m: number = now.getMonth() + 1;
    let d: number = now.getDate();
    return y.toString() + '-' + (m < 10 ? '0' : '') + m.toString() + '-' + (d < 10 ? '0' : '') + d.toString();
  }

  static loadCheckIn(context: Context): CheckInData {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: StickinessUtil.PREFS_NAME });
      let json: string = prefs.getSync(StickinessUtil.KEY_CHECK_IN, '') as string;
      if (!json) {
        return new CheckInData();
      }
      let obj: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
      let data: CheckInData = new CheckInData();
      data.lastDate = (obj['lastDate'] as string) || '';
      data.streak = (obj['streak'] as number) || 0;
      data.totalDays = (obj['totalDays'] as number) || 0;
      let rawDates: Object[] = (obj['dates'] as Object[]) || [];
      let arr: string[] = [];
      for (let i = 0; i < rawDates.length; i++) {
        arr.push(rawDates[i] as string);
      }
      data.dates = arr;
      return data;
    } catch (e) {
      return new CheckInData();
    }
  }

  static saveCheckIn(context: Context, data: CheckInData): void {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: StickinessUtil.PREFS_NAME });
      let obj: Record<string, Object> = {
        'lastDate': data.lastDate as Object,
        'streak': data.streak as Object,
        'totalDays': data.totalDays as Object,
        'dates': data.dates as Object
      };
      prefs.putSync(StickinessUtil.KEY_CHECK_IN, JSON.stringify(obj));
      prefs.flush();
    } catch (e) {
      console.error('[Stickiness] saveCheckIn failed: ' + (e as Error).message);
    }
  }

  static doCheckIn(context: Context): boolean {
    let data: CheckInData = StickinessUtil.loadCheckIn(context);
    let today: string = StickinessUtil.todayStr();
    if (data.lastDate === today) {
      return false;
    }
    let yesterday: Date = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    let yStr: string = yesterday.getFullYear().toString() + '-' +
      ((yesterday.getMonth() + 1) < 10 ? '0' : '') + (yesterday.getMonth() + 1).toString() + '-' +
      (yesterday.getDate() < 10 ? '0' : '') + yesterday.getDate().toString();
    if (data.lastDate === yStr) {
      data.streak = data.streak + 1;
    } else {
      data.streak = 1;
    }
    data.lastDate = today;
    data.totalDays = data.totalDays + 1;
    if (data.dates.length >= 90) {
      data.dates = data.dates.slice(data.dates.length - 89);
    }
    data.dates.push(today);
    StickinessUtil.saveCheckIn(context, data);
    StickinessUtil.incrementStat(context, 'checkInStreak', data.streak);
    StickinessUtil.incrementStat(context, 'checkInTotal', data.totalDays);
    return true;
  }

  static isCheckedInToday(context: Context): boolean {
    let data: CheckInData = StickinessUtil.loadCheckIn(context);
    return data.lastDate === StickinessUtil.todayStr();
  }

  static loadStats(context: Context): UserStats {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: StickinessUtil.PREFS_NAME });
      let json: string = prefs.getSync(StickinessUtil.KEY_STATS, '') as string;
      if (!json) {
        return new UserStats();
      }
      let obj: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
      let stats: UserStats = new UserStats();
      stats.favPoems = (obj['favPoems'] as number) || 0;
      stats.favIdioms = (obj['favIdioms'] as number) || 0;
      stats.favXiehouyu = (obj['favXiehouyu'] as number) || 0;
      stats.favTotal = (obj['favTotal'] as number) || 0;
      stats.browseCount = (obj['browseCount'] as number) || 0;
      stats.checkInStreak = (obj['checkInStreak'] as number) || 0;
      stats.checkInTotal = (obj['checkInTotal'] as number) || 0;
      stats.challengeTotal = (obj['challengeTotal'] as number) || 0;
      stats.readingItems = (obj['readingItems'] as number) || 0;
      stats.readingMinutes = (obj['readingMinutes'] as number) || 0;
      stats.toolUseCount = (obj['toolUseCount'] as number) || 0;
      return stats;
    } catch (e) {
      return new UserStats();
    }
  }

  static saveStats(context: Context, stats: UserStats): void {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: StickinessUtil.PREFS_NAME });
      let obj: Record<string, Object> = {
        'favPoems': stats.favPoems as Object,
        'favIdioms': stats.favIdioms as Object,
        'favXiehouyu': stats.favXiehouyu as Object,
        'favTotal': stats.favTotal as Object,
        'browseCount': stats.browseCount as Object,
        'checkInStreak': stats.checkInStreak as Object,
        'checkInTotal': stats.checkInTotal as Object,
        'challengeTotal': stats.challengeTotal as Object,
        'readingItems': stats.readingItems as Object,
        'readingMinutes': stats.readingMinutes as Object,
        'toolUseCount': stats.toolUseCount as Object
      };
      prefs.putSync(StickinessUtil.KEY_STATS, JSON.stringify(obj));
      prefs.flush();
    } catch (e) {
      console.error('[Stickiness] saveStats failed: ' + (e as Error).message);
    }
  }

  static incrementStat(context: Context, key: string, value: number): void {
    let stats: UserStats = StickinessUtil.loadStats(context);
    if (key === 'favPoems') {
      stats.favPoems = value;
    } else if (key === 'favIdioms') {
      stats.favIdioms = value;
    } else if (key === 'favXiehouyu') {
      stats.favXiehouyu = value;
    } else if (key === 'favTotal') {
      stats.favTotal = value;
    } else if (key === 'browseCount') {
      stats.browseCount = value;
    } else if (key === 'checkInStreak') {
      stats.checkInStreak = value;
    } else if (key === 'checkInTotal') {
      stats.checkInTotal = value;
    } else if (key === 'challengeTotal') {
      stats.challengeTotal = value;
    } else if (key === 'readingItems') {
      stats.readingItems = value;
    } else if (key === 'readingMinutes') {
      stats.readingMinutes = value;
    } else if (key === 'toolUseCount') {
      stats.toolUseCount = value;
    }
    StickinessUtil.saveStats(context, stats);
    StickinessUtil.checkAchievements(context, stats);
  }

  static incrementBrowseCount(context: Context): void {
    let stats: UserStats = StickinessUtil.loadStats(context);
    stats.browseCount = stats.browseCount + 1;
    StickinessUtil.saveStats(context, stats);
    StickinessUtil.checkAchievements(context, stats);
  }

  static syncFavStats(context: Context, poemCount: number, idiomCount: number, xiehouyuCount: number): void {
    let stats: UserStats = StickinessUtil.loadStats(context);
    stats.favPoems = poemCount;
    stats.favIdioms = idiomCount;
    stats.favXiehouyu = xiehouyuCount;
    stats.favTotal = poemCount + idiomCount + xiehouyuCount;
    StickinessUtil.saveStats(context, stats);
    StickinessUtil.checkAchievements(context, stats);
  }

  static syncReadingStats(context: Context, readingItemCount: number): void {
    let stats: UserStats = StickinessUtil.loadStats(context);
    stats.readingItems = readingItemCount;
    StickinessUtil.saveStats(context, stats);
    StickinessUtil.checkAchievements(context, stats);
  }

  static loadAchievements(context: Context): AchievementItem[] {
    let stats: UserStats = StickinessUtil.loadStats(context);
    let unlockedMap: Record<string, number> = StickinessUtil.loadUnlockedMap(context);
    let items: AchievementItem[] = [];
    for (let i = 0; i < StickinessUtil.ACHIEVEMENT_DEFS.length; i++) {
      let def: AchievementDef = StickinessUtil.ACHIEVEMENT_DEFS[i];
      let item: AchievementItem = AchievementItem.create(def.id, def.title, def.desc,
        def.icon, def.color, def.target);
      let current: number = StickinessUtil.getStatValue(stats, def.statKey);
      item.current = current;
      item.unlocked = current >= def.target;
      if (unlockedMap[def.id] !== undefined) {
        item.unlocked = true;
        item.unlockedAt = unlockedMap[def.id];
      }
      items.push(item);
    }
    return items;
  }

  private static getStatValue(stats: UserStats, key: string): number {
    if (key === 'favPoems') {
      return stats.favPoems;
    } else if (key === 'favIdioms') {
      return stats.favIdioms;
    } else if (key === 'favXiehouyu') {
      return stats.favXiehouyu;
    } else if (key === 'favTotal') {
      return stats.favTotal;
    } else if (key === 'browseCount') {
      return stats.browseCount;
    } else if (key === 'checkInStreak') {
      return stats.checkInStreak;
    } else if (key === 'checkInTotal') {
      return stats.checkInTotal;
    } else if (key === 'challengeTotal') {
      return stats.challengeTotal;
    } else if (key === 'readingItems') {
      return stats.readingItems;
    } else if (key === 'readingMinutes') {
      return stats.readingMinutes;
    } else if (key === 'toolUseCount') {
      return stats.toolUseCount;
    }
    return 0;
  }

  private static loadUnlockedMap(context: Context): Record<string, number> {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: StickinessUtil.PREFS_NAME });
      let json: string = prefs.getSync(StickinessUtil.KEY_ACHIEVEMENTS, '') as string;
      if (!json) {
        let empty: Record<string, number> = {};
        return empty;
      }
      let obj: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
      let result: Record<string, number> = {};
      let keys: string[] = Object.keys(obj);
      for (let i = 0; i < keys.length; i++) {
        result[keys[i]] = (obj[keys[i]] as number) || 0;
      }
      return result;
    } catch (e) {
      let empty: Record<string, number> = {};
      return empty;
    }
  }

  private static saveUnlockedMap(context: Context, map: Record<string, number>): void {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: StickinessUtil.PREFS_NAME });
      let obj: Record<string, Object> = {};
      let keys: string[] = Object.keys(map);
      for (let i = 0; i < keys.length; i++) {
        obj[keys[i]] = map[keys[i]] as Object;
      }
      prefs.putSync(StickinessUtil.KEY_ACHIEVEMENTS, JSON.stringify(obj));
      prefs.flush();
    } catch (e) {
      console.error('[Stickiness] saveUnlockedMap failed: ' + (e as Error).message);
    }
  }

  static checkAchievements(context: Context, stats: UserStats): string[] {
    let unlockedMap: Record<string, number> = StickinessUtil.loadUnlockedMap(context);
    let newlyUnlocked: string[] = [];
    let now: number = Date.now();
    for (let i = 0; i < StickinessUtil.ACHIEVEMENT_DEFS.length; i++) {
      let def: AchievementDef = StickinessUtil.ACHIEVEMENT_DEFS[i];
      if (unlockedMap[def.id] !== undefined) {
        continue;
      }
      let current: number = StickinessUtil.getStatValue(stats, def.statKey);
      if (current >= def.target) {
        unlockedMap[def.id] = now;
        newlyUnlocked.push(def.id);
      }
    }
    if (newlyUnlocked.length > 0) {
      StickinessUtil.saveUnlockedMap(context, unlockedMap);
    }
    return newlyUnlocked;
  }

  static loadChallengeProgress(context: Context): ChallengeProgress {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: StickinessUtil.PREFS_NAME });
      let json: string = prefs.getSync(StickinessUtil.KEY_CHALLENGE, '') as string;
      if (!json) {
        return new ChallengeProgress();
      }
      let obj: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
      let p: ChallengeProgress = new ChallengeProgress();
      p.date = (obj['date'] as string) || '';
      p.score = (obj['score'] as number) || 0;
      p.completed = (obj['completed'] as boolean) || false;
      p.totalChallenges = (obj['totalChallenges'] as number) || 0;
      return p;
    } catch (e) {
      return new ChallengeProgress();
    }
  }

  static saveChallengeProgress(context: Context, progress: ChallengeProgress): void {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: StickinessUtil.PREFS_NAME });
      let obj: Record<string, Object> = {
        'date': progress.date as Object,
        'score': progress.score as Object,
        'completed': progress.completed as Object,
        'totalChallenges': progress.totalChallenges as Object
      };
      prefs.putSync(StickinessUtil.KEY_CHALLENGE, JSON.stringify(obj));
      prefs.flush();
    } catch (e) {
      console.error('[Stickiness] saveChallengeProgress failed: ' + (e as Error).message);
    }
  }

  static completeChallenge(context: Context, score: number): void {
    let progress: ChallengeProgress = StickinessUtil.loadChallengeProgress(context);
    let today: string = StickinessUtil.todayStr();
    if (progress.date !== today) {
      progress.totalChallenges = progress.totalChallenges + 1;
    }
    progress.date = today;
    progress.score = score;
    progress.completed = true;
    StickinessUtil.saveChallengeProgress(context, progress);
    let stats: UserStats = StickinessUtil.loadStats(context);
    stats.challengeTotal = progress.totalChallenges;
    StickinessUtil.saveStats(context, stats);
    StickinessUtil.checkAchievements(context, stats);
  }

  static loadContentPrefs(context: Context): ContentPrefs {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: StickinessUtil.PREFS_NAME });
      let json: string = prefs.getSync(StickinessUtil.KEY_PREFS, '') as string;
      if (!json) {
        return new ContentPrefs();
      }
      let obj: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
      let p: ContentPrefs = new ContentPrefs();
      let raw: Object[] = (obj['favDynasties'] as Object[]) || [];
      let arr: string[] = [];
      for (let i = 0; i < raw.length; i++) {
        arr.push(raw[i] as string);
      }
      p.favDynasties = arr;
      return p;
    } catch (e) {
      return new ContentPrefs();
    }
  }

  static saveContentPrefs(context: Context, prefs2: ContentPrefs): void {
    try {
      let p: preferences.Preferences = preferences.getPreferencesSync(context, { name: StickinessUtil.PREFS_NAME });
      let obj: Record<string, Object> = {
        'favDynasties': prefs2.favDynasties as Object
      };
      p.putSync(StickinessUtil.KEY_PREFS, JSON.stringify(obj));
      p.flush();
    } catch (e) {
      console.error('[Stickiness] saveContentPrefs failed: ' + (e as Error).message);
    }
  }

  static recordDynastyBrowse(context: Context, dynasty: string): void {
    let prefs2: ContentPrefs = StickinessUtil.loadContentPrefs(context);
    let found: boolean = false;
    for (let i = 0; i < prefs2.favDynasties.length; i++) {
      if (prefs2.favDynasties[i] === dynasty) {
        found = true;
        break;
      }
    }
    if (!found && prefs2.favDynasties.length < 5) {
      prefs2.favDynasties.push(dynasty);
      StickinessUtil.saveContentPrefs(context, prefs2);
    }
  }
}

export class ChallengeProgress {
  date: string = '';
  score: number = 0;
  completed: boolean = false;
  totalChallenges: number = 0;
}

export class ContentPrefs {
  favDynasties: string[] = [];
}
