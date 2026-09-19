import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PoetryViewModel } from '../../viewmodel/PoetryViewModel';
import { PoetItem, PoetDetail, PoemItem } from '../../model/PoetryModels';

export class DailyPoemWidgetUtil {
  private static readonly PREFS_NAME: string = 'app_cache';
  private static readonly KEY_FORM_IDS: string = 'daily_poem_form_ids';
  private static readonly SEPARATOR: string = '|';
  private static readonly MAX_LINE_LEN: number = 18;

  static buildCardData(context: Context): Record<string, string> {
    let title: string = '每日一诗';
    let author: string = '';
    let lines: string = '今日诗句加载中…';
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
    let date: string = (now.getMonth() + 1).toString() + '\u6708' + now.getDate().toString() + '\u65E5';
    let data: Record<string, string> = {
      'title': title,
      'author': author,
      'lines': lines,
      'date': date,
      'poemJson': poemJson
    };
    return data;
  }

  static updateAllForms(context: Context): void {
    let formIds: string[] = DailyPoemWidgetUtil.loadFormIds(context);
    if (formIds.length === 0) {
      return;
    }
    let data: formBindingData.FormBindingData =
      formBindingData.createFormBindingData(DailyPoemWidgetUtil.buildCardData(context));
    for (let i = 0; i < formIds.length; i++) {
      formProvider.updateForm(formIds[i], data).catch((error: BusinessError) => {
        console.error('[DailyPoemWidget] updateForm failed: ' + JSON.stringify(error));
      });
    }
  }

  static saveFormId(context: Context, formId: string): void {
    let ids: string[] = DailyPoemWidgetUtil.loadFormIds(context);
    if (ids.indexOf(formId) >= 0) {
      return;
    }
    ids.push(formId);
    DailyPoemWidgetUtil.saveFormIds(context, ids);
  }

  static removeFormId(context: Context, formId: string): void {
    let ids: string[] = DailyPoemWidgetUtil.loadFormIds(context);
    let next: string[] = [];
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] !== formId) {
        next.push(ids[i]);
      }
    }
    DailyPoemWidgetUtil.saveFormIds(context, next);
  }

  private static loadFormIds(context: Context): string[] {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: DailyPoemWidgetUtil.PREFS_NAME });
      let raw: string = prefs.getSync(DailyPoemWidgetUtil.KEY_FORM_IDS, '') as string;
      if (!raw) {
        return [];
      }
      let ids: string[] = [];
      let parts: string[] = raw.split(DailyPoemWidgetUtil.SEPARATOR);
      for (let i = 0; i < parts.length; i++) {
        if (parts[i]) {
          ids.push(parts[i]);
        }
      }
      return ids;
    } catch (e) {
      return [];
    }
  }

  private static saveFormIds(context: Context, ids: string[]): void {
    try {
      let prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: DailyPoemWidgetUtil.PREFS_NAME });
      prefs.putSync(DailyPoemWidgetUtil.KEY_FORM_IDS, ids.join(DailyPoemWidgetUtil.SEPARATOR));
      prefs.flushSync();
    } catch (e) {
      console.error('[DailyPoemWidget] saveFormIds failed: ' + (e as Error).message);
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
