/**
 * 模板体系统一 - 协议模型
 * 设计文档：docs/模板体系统一设计文档.md §3
 * 统一 4 个生成类工具（首图/生字卡/文字转图片/词云）的模板协议：
 * UnifiedTemplate = 槽位 + 配色 + 字体 + 导出规格，各工具模板 extends 本基类
 */

import { CoverPalette } from '../../model/CoverModels';

/** 工具类别常量（注册表主键） */
export class UnifiedToolKind {
  static readonly COVER: string = 'cover';
  static readonly CHAR_CARD: string = 'charcard';
  static readonly MD2PNG: string = 'md2png';
  static readonly WORD_CLOUD: string = 'wordcloud';
}

/** 槽位类型常量 */
export class TemplateSlotKind {
  static readonly TEXT: string = 'text';
  static readonly MULTILINE: string = 'multiline';
  static readonly PINYIN: string = 'pinyin';
  static readonly NUMBER: string = 'number';
  static readonly CHOICE: string = 'choice';
}

/** 选项 chips 单项（CHOICE 槽位与 ChipRow 组件共用） */
export class ChipOption {
  value: string = '';
  label: string = '';

  static of(value: string, label: string): ChipOption {
    let o: ChipOption = new ChipOption();
    o.value = value;
    o.label = label;
    return o;
  }
}

/** 槽位定义：模板的一个内容输入位 */
export class TemplateSlot {
  id: string = '';
  label: string = '';
  kind: string = TemplateSlotKind.TEXT;
  maxLength: number = 0;
  placeholder: string = '';
  /** 自动填充能力标记：'' | 'quote' | 'pinyin' | ...，由页面实现具体推荐逻辑 */
  autoFill: string = '';
  /** CHOICE 槽位的候选项 */
  options: ChipOption[] = [];

  static of(id: string, label: string, kind: string, maxLength: number = 0,
    placeholder: string = '', autoFill: string = '', options: ChipOption[] = []): TemplateSlot {
    let s: TemplateSlot = new TemplateSlot();
    s.id = id;
    s.label = label;
    s.kind = kind;
    s.maxLength = maxLength;
    s.placeholder = placeholder;
    s.autoFill = autoFill;
    s.options = options;
    return s;
  }
}

/** 字体选项 */
export class TemplateFontOption {
  family: string = '';
  label: string = '';

  static of(family: string, label: string): TemplateFontOption {
    let f: TemplateFontOption = new TemplateFontOption();
    f.family = family;
    f.label = label;
    return f;
  }
}

/** 导出规格：设计稿基准 + 实际导出像素 */
export class ExportSpec {
  label: string = '';
  designWidth: number = 0;
  designHeight: number = 0;
  exportWidth: number = 0;
  exportHeight: number = 0;

  static of(label: string, designWidth: number, designHeight: number,
    exportWidth: number, exportHeight: number): ExportSpec {
    let s: ExportSpec = new ExportSpec();
    s.label = label;
    s.designWidth = designWidth;
    s.designHeight = designHeight;
    s.exportWidth = exportWidth;
    s.exportHeight = exportHeight;
    return s;
  }
}

/**
 * 统一模板基类：各工具的模板类 extends 本类后向注册表注册。
 * 配色直接沿用 CoverPalette（已是首图/生字卡的事实标准色板）。
 */
export class UnifiedTemplate {
  id: string = '';
  name: string = '';
  kind: string = '';
  series: string = '';
  slots: TemplateSlot[] = [];
  palettes: CoverPalette[] = [];
  fonts: TemplateFontOption[] = [];
  exportSpecs: ExportSpec[] = [];
  /** 槽位默认值（key = slot.id） */
  defaults: Record<string, string> = {};

  static of(id: string, name: string, kind: string, series: string,
    slots: TemplateSlot[], palettes: CoverPalette[], fonts: TemplateFontOption[],
    exportSpecs: ExportSpec[], defaults: Record<string, string>): UnifiedTemplate {
    let t: UnifiedTemplate = new UnifiedTemplate();
    t.id = id;
    t.name = name;
    t.kind = kind;
    t.series = series;
    t.slots = slots;
    t.palettes = palettes;
    t.fonts = fonts;
    t.exportSpecs = exportSpecs;
    t.defaults = defaults;
    return t;
  }
}

/** 工具描述符：注册表的工具级元数据 */
export class UnifiedToolDescriptor {
  kind: string = '';
  title: string = '';
  subtitle: string = '';
  page: string = '';
  icon: string = '';
  color: string = '';

  static of(kind: string, title: string, subtitle: string,
    page: string, icon: string, color: string): UnifiedToolDescriptor {
    let d: UnifiedToolDescriptor = new UnifiedToolDescriptor();
    d.kind = kind;
    d.title = title;
    d.subtitle = subtitle;
    d.page = page;
    d.icon = icon;
    d.color = color;
    return d;
  }
}
