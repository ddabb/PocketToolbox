/**
 * 文案海报 - 数据模型
 * 槽位(slot)系统 + 导出比例 + 内容 + 模板（复用 CoverPalette 配色与 CoverHistoryRecord 历史）
 */
import { CoverPalette } from './CoverModels';

/** 槽位 id 常量 */
export class CopyPosterSlot {
  static readonly BODY: string = 'body';
  static readonly SIGN: string = 'sign';
  static readonly TAG: string = 'tag';
  /** 1.4.8 T18 对联定制槽位（id 与 CopyPosterContent 字段名一致） */
  static readonly COUPLET_UP: string = 'coupletUp';
  static readonly COUPLET_DOWN: string = 'coupletDown';
}

/** 定制槽位定义（1.4.8：模板声明的额外输入控件，如 T18 对联的上联/下联） */
export class CopyPosterSlotDef {
  id: string = '';
  label: ResourceStr = '';
  maxLen: number = 20;

  static of(id: string, label: ResourceStr, maxLen: number): CopyPosterSlotDef {
    let d: CopyPosterSlotDef = new CopyPosterSlotDef();
    d.id = id;
    d.label = label;
    d.maxLen = maxLen;
    return d;
  }
}

/** 导出比例：1:1（1080x1080）/ 3:4（1080x1440）/ 9:16 长图（1080x1920） */
export class CopyPosterRatio {
  static readonly SQUARE: string = 'square';
  static readonly PORTRAIT: string = 'portrait';
  static readonly LONG: string = 'long';

  static label(kind: string): ResourceStr {
    if (kind === CopyPosterRatio.PORTRAIT) {
      return $r('app.string.poster_ratio_portrait');
    }
    if (kind === CopyPosterRatio.LONG) {
      return $r('app.string.poster_ratio_long');
    }
    return $r('app.string.poster_ratio_square');
  }

  static all(): string[] {
    return [CopyPosterRatio.SQUARE, CopyPosterRatio.PORTRAIT, CopyPosterRatio.LONG];
  }

  /** 设计稿高度（宽恒 900）：1:1 -> 900，3:4 -> 1200，9:16 -> 1600 */
  static designHeight(kind: string): number {
    if (kind === CopyPosterRatio.PORTRAIT) {
      return 1200;
    }
    if (kind === CopyPosterRatio.LONG) {
      return 1600;
    }
    return 900;
  }

  /** 导出像素高度（宽恒 1080）：1:1 -> 1080，3:4 -> 1440，9:16 -> 1920 */
  static exportHeight(kind: string): number {
    if (kind === CopyPosterRatio.PORTRAIT) {
      return 1440;
    }
    if (kind === CopyPosterRatio.LONG) {
      return 1920;
    }
    return 1080;
  }
}

/** 槽位内容 */
export class CopyPosterContent {
  body: string = '';
  sign: string = '';
  tag: string = '';
  /** T18 对联上联（1.4.8 定制槽位，旧记录缺省 '' 兼容） */
  coupletUp: string = '';
  /** T18 对联下联 */
  coupletDown: string = '';
  /** 水印开关（随历史存储，旧记录缺省 false 兼容） */
  watermarkOn: boolean = false;
  /** 水印文字（清空则不渲染） */
  watermarkText: string = '';

  copy(): CopyPosterContent {
    let c: CopyPosterContent = new CopyPosterContent();
    c.body = this.body;
    c.sign = this.sign;
    c.tag = this.tag;
    c.coupletUp = this.coupletUp;
    c.coupletDown = this.coupletDown;
    c.watermarkOn = this.watermarkOn;
    c.watermarkText = this.watermarkText;
    return c;
  }

  toJson(): string {
    let r: Record<string, Object> = {
      'body': this.body,
      'sign': this.sign,
      'tag': this.tag,
      'coupletUp': this.coupletUp,
      'coupletDown': this.coupletDown,
      'watermarkOn': this.watermarkOn,
      'watermarkText': this.watermarkText,
    };
    return JSON.stringify(r);
  }

  static fromJson(json: string): CopyPosterContent {
    let c: CopyPosterContent = new CopyPosterContent();
    try {
      let r: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
      c.body = String(r['body'] ?? '');
      c.sign = String(r['sign'] ?? '');
      c.tag = String(r['tag'] ?? '');
      c.coupletUp = String(r['coupletUp'] ?? '');
      c.coupletDown = String(r['coupletDown'] ?? '');
      c.watermarkOn = r['watermarkOn'] === true;
      c.watermarkText = String(r['watermarkText'] ?? '');
    } catch (e) {
      console.error('[CopyPoster] parse content json failed: ' + (e as Error).message);
    }
    return c;
  }
}

/**
 * 模板分类（1.4.5 文案海报优化 · 分类导航）
 *
 * 背景：缩略图 96vp、间距 10vp，手机屏宽约 360-400vp，一屏只能显示 3-4 个；
 * 18 个模板需要横滑 5 次才到末尾，且滑过后用户已记不清前面有什么。
 * 改为「顶部分类 chips + 下方只显示该类模板」。
 *
 * 分类依据「视觉风格」而非「题材」——用户选模板时先想的是要什么调性，
 * 而不是内容属于节日还是日常。
 */
export class CopyPosterCategory {
  /** 分类 id，写入 preferences 用于记忆上次选择 */
  id: string = '';
  /** 分类显示名（ResourceStr，跟随三语） */
  name: ResourceStr = '';
  /** 该分类下的模板 id */
  templateIds: string[] = [];

  static of(id: string, name: ResourceStr, templateIds: string[]): CopyPosterCategory {
    let c: CopyPosterCategory = new CopyPosterCategory();
    c.id = id;
    c.name = name;
    c.templateIds = templateIds;
    return c;
  }
}

export class CopyPosterCategories {
  static readonly SIMPLE: string = 'simple';
  static readonly BOLD: string = 'bold';
  static readonly TECH: string = 'tech';
  static readonly LIFE: string = 'life';
  static readonly FESTIVAL: string = 'festival';

  /**
   * 分类定义。T7 霓虹灯归入 tech（与 LCD/CRT/掌机同为发光设备风格）；
   * 若后续要把霓虹单列一个「赛博」类，只需在此加一项并把 T7 移过去，页面代码零改动。
   */
  static all(): CopyPosterCategory[] {
    return [
      // 简约清新：低饱和、纸感、留白多
      CopyPosterCategory.of(CopyPosterCategories.SIMPLE, $r('app.string.poster_cat_simple'),
        ['T1', 'T2', 'T3']),
      // 大字金句：冲击力强，主文案占比高
      CopyPosterCategory.of(CopyPosterCategories.BOLD, $r('app.string.poster_cat_bold'),
        ['T4', 'T19', 'T20', 'T21']),
      // 科技复古：发光设备与旧时代质感
      CopyPosterCategory.of(CopyPosterCategories.TECH, $r('app.string.poster_cat_tech'),
        ['T5', 'T6', 'T7', 'T8', 'T10', 'T13']),
      // 生活质感：印刷品、日用品、影视感
      CopyPosterCategory.of(CopyPosterCategories.LIFE, $r('app.string.poster_cat_life'),
        ['T9', 'T11', 'T12', 'T14', 'T15']),
      // 节日节气：时令限定
      CopyPosterCategory.of(CopyPosterCategories.FESTIVAL, $r('app.string.poster_cat_festival'),
        ['T16', 'T17', 'T18']),
    ];
  }

  static getById(id: string): CopyPosterCategory {
    let list: CopyPosterCategory[] = CopyPosterCategories.all();
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === id) {
        return list[i];
      }
    }
    return list[0];
  }

  /**
   * 取某分类下的模板对象列表（保持传入注册表中的顺序）。
   * 注册表由调用方传入（core/cover/CopyPosterTemplates.all()），
   * 避免 model 层反向依赖 core 注册表造成循环导入。
   */
  static templatesOf(cat: CopyPosterCategory, registry: CopyPosterTemplate[]): CopyPosterTemplate[] {
    let out: CopyPosterTemplate[] = [];
    for (let i = 0; i < cat.templateIds.length; i++) {
      for (let j = 0; j < registry.length; j++) {
        if (registry[j].id === cat.templateIds[i]) {
          out.push(registry[j]);
          break;
        }
      }
    }
    return out;
  }

  /** 模板 id 所属分类；未登记的模板归入 simple（兜底，避免模板不可达） */
  static categoryOfTemplate(templateId: string): string {
    let list: CopyPosterCategory[] = CopyPosterCategories.all();
    for (let i = 0; i < list.length; i++) {
      if (list[i].templateIds.indexOf(templateId) >= 0) {
        return list[i].id;
      }
    }
    return CopyPosterCategories.SIMPLE;
  }
}

/** 模板定义 */
export class CopyPosterTemplate {
  id: string = '';
  name: ResourceStr = '';
  layout: string = '';
  slots: string[] = [];
  palettes: CoverPalette[] = [];
  fonts: string[] = [];
  defaults: Record<string, string> = {};
  /** 是否支持主文案拼音注音（固定构图模板传 false 隐藏注音开关） */
  supportsPinyin: boolean = true;
  /** 定制输入槽位（非空时页面隐藏主文案输入与换一句，渲染定制输入） */
  customSlots: CopyPosterSlotDef[] = [];

  static of(id: string, name: ResourceStr, layout: string, slots: string[], palettes: CoverPalette[],
    fonts: string[], defaults: Record<string, string>, supportsPinyin: boolean = true,
    customSlots: CopyPosterSlotDef[] = []): CopyPosterTemplate {
    let t: CopyPosterTemplate = new CopyPosterTemplate();
    t.id = id;
    t.name = name;
    t.layout = layout;
    t.slots = slots;
    t.palettes = palettes;
    t.fonts = fonts;
    t.defaults = defaults;
    t.supportsPinyin = supportsPinyin;
    t.customSlots = customSlots;
    return t;
  }
}
