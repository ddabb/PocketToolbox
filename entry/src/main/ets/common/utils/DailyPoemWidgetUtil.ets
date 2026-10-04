import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PoetryViewModel } from '../../viewmodel/PoetryViewModel';
import { PoetItem, PoetDetail, PoemItem } from '../../model/PoetryModels';
import { CheckInWidgetUtil } from './CheckInWidgetUtil';

interface WidgetFormEntry {
  id: string;
  type: string;
  dimension: string;
}

export class DailyPoemWidgetUtil {
  private static readonly PREFS_NAME: string = 'app_cache';
  private static readonly KEY_FORMS: string = 'widget_forms';
  private static readonly KEY_LEGACY_IDS: string = 'daily_poem_form_ids';
  private static readonly SEPARATOR: string = '|';
  private static readonly MAX_LINE_LEN: number = 18;

  static buildCardData(context: Context, dimension: string = ''): Record<string, string> {
    let title: string = context.resourceManager.getStringByNameSync('daily_poem_title');
    let author: string = '';
    let lines: string = context.resourceManager.getStringByNameSync('daily_poem_loading');
    let poemJson: string = '';
    try {
      let vm: PoetryViewModel = PoetryViewModel.getInstance();
      if (!vm.isDataLoaded()) {
        vm.loadIndex(context);
      }
      let poets: PoetItem[] = vm.getFilteredPoets('全部');
      if (poets.length > 0) {
        let now: Date = new Date();
        let seed: number = now.getFullYear() * 10000 + (now.getMonth() + 1) * 100 + now.getDate();
        let poetIdx: number = Math.floor(DailyPoemWidgetUtil.seededRandom(seed) * poets.length);
        let poet: PoetItem = poets[poetIdx];
        let detail: PoetDetail = vm.loadPoetDetail(context, poet.n, poet.i, poet.d);
        if (detail.poems.length > 0) {
          let poemIdx: number = Math.floor(DailyPoemWidgetUtil.seededRandom(seed + 1) * detail.poems.length);
          let poem: PoemItem = detail.poems[poemIdx];
          title = poem.n;
          author = detail.name + ' \u00B7 ' + detail.dynasty;
          lines = DailyPoemWidgetUtil.extractLines(poem.c);
          let poemParam: Record<string, string> = {
            'n': poem.n,
            'c': poem.c,
            'f': poem.f,
            'a': poem.a,
            'd': poem.d
          };
          poemJson = JSON.stringify(poemParam);
        }
      }
    } catch (e) {
      console.error('[DailyPoemWidget] buildCardData failed: ' + (e as Error).message);
    }
    let now: Date = new Date();
    let date: string = context.resourceManager.getStringByNameSync('widget_date_format',
      (now.getMonth() + 1).toString(), now.getDate().toString());
    let data: Record<string, string> = {
      'title': title,
      'author': author,
      'lines': lines,
      'date': date,
      'poemJson': poemJson,
      'dimension': dimension
    };
    return data;
  }

  // 遍历所有已添加卡片，按类型用对应数据刷新（诗词卡/签到卡）
  static updateAllForms(context: Context): void {
    let forms: WidgetFormEntry[] = DailyPoemWidgetUtil.loadForms(context);
    if (forms.length === 0) {
      return;
    }
    for (let i = 0; i < forms.length; i++) {
      let form: WidgetFormEntry = forms[i];
      let data: formBindingData.FormBindingData;
      if (form.type === 'checkin') {
        data = formBindingData.createFormBindingData(CheckInWidgetUtil.buildCardData(context, form.dimension));
      } else {
        data = formBindingData.createFormBindingData(DailyPoemWidgetUtil.buildCardData(context, form.dimension));
      }
      formProvider.updateForm(form.id, data).catch((error: BusinessError) => {
        console.error('[DailyPoemWidget] updateForm failed: ' + JSON.stringify(error));
      });
    }
  }

  // 注册一张卡片，记录其类型与尺寸（默认 poem；签到卡传 'checkin'）；重复 id 自动去重
  static saveFormId(context: Context, formId: string, type: string = 'poem', dimension: string = ''): void {
    let forms: WidgetFormEntry[] = DailyPoemWidgetUtil.loadForms(context);
    let next: WidgetFormEntry[] = [];
    for (let i = 0; i < forms.length; i++) {
      if (forms[i].id !== formId) {
        next.push(forms[i]);
      }
    }
    let entry: WidgetFormEntry = { id: formId, type: type, dimension: dimension };
    next.push(entry);
    DailyPoemWidgetUtil.saveForms(context, next);
  }

  static getFormType(context: Context, formId: string): string {
    let forms: WidgetFormEntry[] = DailyPoemWidgetUtil.loadForms(context);
    for (let i = 0; i < forms.length; i++) {
      if (forms[i].id === formId) {
        return forms[i].type;
      }
    }
    return 'poem';
  }

  static getFormDimension(context: Context, formId: string): string {
    let forms: WidgetFormEntry[] = DailyPoemWidgetUtil.loadForms(context);
    for (let i = 0; i < forms.length; i++) {
      if (forms[i].id === formId) {
        return forms[i].dimension;
      }
    }
    return '';
  }

  static removeFormId(context: Context, formId: string): void {
    let forms: WidgetFormEntry[] = DailyPoemWidgetUtil.loadForms(context);
    let next: WidgetFormEntry[] = [];
    for (let i = 0; i < forms.length; i++) {
      if (forms[i].id !== formId) {
        next.push(forms[i]);
      }
    }
    DailyPoemWidgetUtil.saveForms(context, next);
  }

  // 读取卡片注册表；首次调用时把旧版扁平 id 列表（全部视为 poem）迁移为新结构
  private static loadForms(context: Context): WidgetFormEntry[] {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: DailyPoemWidgetUtil.PREFS_NAME });
      let legacy: string = prefs.getSync(DailyPoemWidgetUtil.KEY_LEGACY_IDS, '') as string;
      if (legacy) {
        let ids: string[] = legacy.split(DailyPoemWidgetUtil.SEPARATOR).filter((s) => s.length > 0);
        let migrated: WidgetFormEntry[] = [];
        for (let i = 0; i < ids.length; i++) {
          migrated.push({ id: ids[i], type: 'poem', dimension: '' });
        }
        DailyPoemWidgetUtil.saveForms(context, migrated);
        try {
          prefs.deleteSync(DailyPoemWidgetUtil.KEY_LEGACY_IDS);
        } catch (e) {
          // ignore
        }
        return migrated;
      }
      let raw: string = prefs.getSync(DailyPoemWidgetUtil.KEY_FORMS, '') as string;
      if (!raw) {
        return [];
      }
      let arr: Object[] = JSON.parse(raw) as Object[];
      let result: WidgetFormEntry[] = [];
      for (let i = 0; i < arr.length; i++) {
        let o: Record<string, Object> = arr[i] as Record<string, Object>;
        result.push({
          id: (o['id'] as string) || '',
          type: (o['type'] as string) || 'poem',
          dimension: (o['dimension'] as string) || ''
        });
      }
      return result;
    } catch (e) {
      return [];
    }
  }

  private static saveForms(context: Context, forms: WidgetFormEntry[]): void {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: DailyPoemWidgetUtil.PREFS_NAME });
      prefs.putSync(DailyPoemWidgetUtil.KEY_FORMS, JSON.stringify(forms));
      prefs.flushSync();
    } catch (e) {
      console.error('[DailyPoemWidget] saveForms failed: ' + (e as Error).message);
    }
  }

  private static extractLines(content: string): string {
    let parts: string[] = content.split('\n');
    let lines: string[] = [];
    for (let i = 0; i < parts.length && lines.length < 2; i++) {
      let line: string = parts[i].trim();
      if (!line) {
        continue;
      }
      if (line.length > DailyPoemWidgetUtil.MAX_LINE_LEN) {
        line = line.substring(0, DailyPoemWidgetUtil.MAX_LINE_LEN) + '…';
      }
      lines.push(line);
    }
    if (lines.length === 0) {
      return content.length > DailyPoemWidgetUtil.MAX_LINE_LEN ?
        content.substring(0, DailyPoemWidgetUtil.MAX_LINE_LEN) + '…' : content;
    }
    return lines.join('\n');
  }

  private static seededRandom(seed: number): number {
    let x: number = Math.sin(seed) * 10000;
    return x - Math.floor(x);
  }
}
