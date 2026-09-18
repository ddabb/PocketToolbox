/**
 * 公众号首图制作 - 数据模型
 * 槽位(slot)系统 + 模板 + 配色 + 内容 + 历史记录
 */

/** 槽位 id 常量 */
export class CoverSlot {
  static readonly TITLE: string = 'title';
  static readonly SUBTITLE: string = 'subtitle';
  static readonly AUTHOR: string = 'author';
  static readonly ISSUE: string = 'issue';
  static readonly QUOTE: string = 'quote';
  static readonly QUOTE_SOURCE: string = 'quoteSource';
  static readonly PINYIN: string = 'pinyin';
  static readonly SEAL: string = 'seal';
}

/** 配色方案 */
export class CoverPalette {
  name: string = '';
  bg: string = '#FFFFFF';
  bg2: string = '';
  accent: string = '#2E6FD6';
  title: string = '#1F1F1F';
  sub: string = '#666666';
  block: string = '#F5F5F5';
  grid: string = '#D8231A';

  static of(name: string, bg: string, accent: string, title: string, sub: string,
    bg2: string = '', block: string = '', grid: string = ''): CoverPalette {
    let p: CoverPalette = new CoverPalette();
    p.name = name;
    p.bg = bg;
    p.accent = accent;
    p.title = title;
    p.sub = sub;
    p.bg2 = bg2;
    p.block = block === '' ? bg : block;
    p.grid = grid === '' ? accent : grid;
    return p;
  }
}

/** 模板定义 */
export class CoverTemplate {
  id: string = '';
  name: string = '';
  series: string = '';
  layout: string = '';
  slots: string[] = [];
  titleLabel: string = '主标题';
  palettes: CoverPalette[] = [];
  fonts: string[] = [];
  contentKind: string = '';
  seed: Record<string, string> = {};

  static of(id: string, name: string, series: string, layout: string, slots: string[],
    titleLabel: string, palettes: CoverPalette[], fonts: string[], contentKind: string,
    seed: Record<string, string>): CoverTemplate {
    let t: CoverTemplate = new CoverTemplate();
    t.id = id;
    t.name = name;
    t.series = series;
    t.layout = layout;
    t.slots = slots;
    t.titleLabel = titleLabel;
    t.palettes = palettes;
    t.fonts = fonts;
    t.contentKind = contentKind;
    t.seed = seed;
    return t;
  }
}

/** 槽位内容 */
export class CoverContent {
  title: string = '';
  subtitle: string = '';
  author: string = '';
  issue: string = '';
  quote: string = '';
  quoteSource: string = '';
  pinyin: string = '';
  pinyinLocked: boolean = false;
  seal: string = '';

  copy(): CoverContent {
    let c: CoverContent = new CoverContent();
    c.title = this.title;
    c.subtitle = this.subtitle;
    c.author = this.author;
    c.issue = this.issue;
    c.quote = this.quote;
    c.quoteSource = this.quoteSource;
    c.pinyin = this.pinyin;
    c.pinyinLocked = this.pinyinLocked;
    c.seal = this.seal;
    return c;
  }

  toJson(): string {
    let r: Record<string, Object> = {
      'title': this.title,
      'subtitle': this.subtitle,
      'author': this.author,
      'issue': this.issue,
      'quote': this.quote,
      'quoteSource': this.quoteSource,
      'pinyin': this.pinyin,
      'seal': this.seal,
    };
    return JSON.stringify(r);
  }

  static fromJson(json: string): CoverContent {
    let c: CoverContent = new CoverContent();
    try {
      let r: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
      c.title = String(r['title'] ?? '');
      c.subtitle = String(r['subtitle'] ?? '');
      c.author = String(r['author'] ?? '');
      c.issue = String(r['issue'] ?? '');
      c.quote = String(r['quote'] ?? '');
      c.quoteSource = String(r['quoteSource'] ?? '');
      c.pinyin = String(r['pinyin'] ?? '');
      c.seal = String(r['seal'] ?? '');
      c.pinyinLocked = true;
    } catch (e) {
      console.error('[Cover] parse content json failed: ' + (e as Error).message);
    }
    return c;
  }
}

/** 历史记录 */
export class CoverHistoryRecord {
  id: string = '';
  fileName: string = '';
  templateId: string = '';
  paletteIndex: number = 0;
  fontIndex: number = 0;
  textsJson: string = '';
  exportedAt: number = 0;

  static of(id: string, fileName: string, templateId: string, paletteIndex: number,
    fontIndex: number, textsJson: string, exportedAt: number): CoverHistoryRecord {
    let r: CoverHistoryRecord = new CoverHistoryRecord();
    r.id = id;
    r.fileName = fileName;
    r.templateId = templateId;
    r.paletteIndex = paletteIndex;
    r.fontIndex = fontIndex;
    r.textsJson = textsJson;
    r.exportedAt = exportedAt;
    return r;
  }
}

/** 内容推荐结果（换一句） */
export class CoverQuotePick {
  quote: string = '';
  source: string = '';
  extra: string = '';

  static of(quote: string, source: string, extra: string): CoverQuotePick {
    let p: CoverQuotePick = new CoverQuotePick();
    p.quote = quote;
    p.source = source;
    p.extra = extra;
    return p;
  }
}
