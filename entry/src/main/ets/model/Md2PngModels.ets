export class TemplateInfo {
  id: string = '';
  name: string = '';
  icon: string = '';
  bgColor: string = '';
  textColor: string = '';
  accentColor: string = '';
  headerColor: string = '';
  codeBgColor: string = '';
  quoteBgColor: string = '';
  quoteBorderColor: string = '';
  cardBgColor: string = '';
  decorPattern: string = '';
  highlightBgColor: string = '';
  titleFont: string = '';
  textFont: string = '';
  highlightFont: string = '';

  constructor(
    id: string, name: string, icon: string, bgColor: string, textColor: string,
    accentColor: string, headerColor: string, codeBgColor: string,
    quoteBgColor: string, quoteBorderColor: string, cardBgColor: string, decorPattern: string,
    highlightBgColor: string,
    titleFont: string = '', textFont: string = '', highlightFont: string = ''
  ) {
    this.id = id;
    this.name = name;
    this.icon = icon;
    this.bgColor = bgColor;
    this.textColor = textColor;
    this.accentColor = accentColor;
    this.headerColor = headerColor;
    this.codeBgColor = codeBgColor;
    this.quoteBgColor = quoteBgColor;
    this.quoteBorderColor = quoteBorderColor;
    this.cardBgColor = cardBgColor;
    this.decorPattern = decorPattern;
    this.highlightBgColor = highlightBgColor;
    this.titleFont = titleFont;
    this.textFont = textFont;
    this.highlightFont = highlightFont;
  }
}

export class ShareTemplateInfo {
  accentColor: string = '';
  bgColor: string = '';
  textColor: string = '';
  headerColor: string = '';
  codeBgColor: string = '';
  quoteBgColor: string = '';
  quoteBorderColor: string = '';
  watermarkColor: string = '';
  decorPattern: string = '';

  constructor(
    accentColor: string, bgColor: string, textColor: string, headerColor: string,
    codeBgColor: string, quoteBgColor: string, quoteBorderColor: string, watermarkColor: string,
    decorPattern: string
  ) {
    this.accentColor = accentColor;
    this.bgColor = bgColor;
    this.textColor = textColor;
    this.headerColor = headerColor;
    this.codeBgColor = codeBgColor;
    this.quoteBgColor = quoteBgColor;
    this.quoteBorderColor = quoteBorderColor;
    this.watermarkColor = watermarkColor;
    this.decorPattern = decorPattern;
  }
}

export class Md2PngTemplates {
  static readonly FONT_SMILEY: string = 'SmileySans-Oblique';
  static readonly FONT_WENKAI: string = 'LXGWWenKai';
  static readonly FONT_MASHAN: string = 'MaShanZheng';
  static readonly FONT_KUAILE: string = 'ZCOOLKuaiLe';
  static readonly FONT_HUANGYOU: string = 'ZCOOLQingKeHuangYou';
  static readonly FONT_LONGCANG: string = 'LongCang';
  static readonly FONT_MAOMAO: string = 'LiuJianMaoCao';
  static readonly FONT_XIAOWEI: string = 'ZCOOLXiaoWei';
  static readonly FONT_ZHIMANG: string = 'ZhiMangXing';

  static getAll(): TemplateInfo[] {
    let smiley: string = Md2PngTemplates.FONT_SMILEY;
    let wenkai: string = Md2PngTemplates.FONT_WENKAI;
    let mashan: string = Md2PngTemplates.FONT_MASHAN;
    let kuaile: string = Md2PngTemplates.FONT_KUAILE;
    let huangyou: string = Md2PngTemplates.FONT_HUANGYOU;
    let longcang: string = Md2PngTemplates.FONT_LONGCANG;
    let maomao: string = Md2PngTemplates.FONT_MAOMAO;
    let xiaowei: string = Md2PngTemplates.FONT_XIAOWEI;
    let zhimang: string = Md2PngTemplates.FONT_ZHIMANG;
    return [
      new TemplateInfo('default', '简约蓝', '#4A90D9', '#ffffff', '#2c3e50',
        '#2563eb', '#1e40af', '#dbeafe', '#eff6ff', '#3b82f6', '#eff6ff', 'wave',
        'rgba(37,99,235,0.25)', smiley, '', smiley),
      new TemplateInfo('wechat', '清新绿', '#07c160', '#ffffff', '#3f3f3f',
        '#059669', '#047857', '#d1fae5', '#ecfdf5', '#047857', '#ecfdf5', 'leaf',
        'rgba(5,150,105,0.25)', xiaowei, '', kuaile),
      new TemplateInfo('xiaohongshu', '樱桃红', '#ff2e4d', '#fef2f2', '#333333',
        '#dc2626', '#b91c1c', '#fee2e2', '#fff1f2', '#ef4444', '#fff5f5', 'heart',
        'rgba(220,38,38,0.25)', kuaile, '', kuaile),
      new TemplateInfo('douyin', '暗夜红', '#fe2c55', '#121212', '#ffffff',
        '#ef4444', '#dc2626', '#1f1f1f', 'rgba(239,68,68,0.15)', '#ef4444', '#1a1a1a', 'glitch',
        'rgba(239,68,68,0.5)', huangyou, '', huangyou),
      new TemplateInfo('ink', '水墨风', '#333333', '#f8f8f8', '#333333',
        '#1f2937', '#111827', '#f3f4f6', 'rgba(0,0,0,0.02)', '#4b5563', '#f5f5f5', 'mountain',
        'rgba(31,41,55,0.2)', mashan, wenkai, maomao),
      new TemplateInfo('cyberpunk', '赛博朋克', '#ff00ff', '#0a0a12', '#00ffff',
        '#ff00ff', '#ff00ff', '#1a0a2e', 'rgba(255,0,255,0.15)', '#00ffff', '#0f0f1a', 'grid',
        'rgba(255,0,255,0.35)', smiley, '', smiley),
      new TemplateInfo('minimalist', '极简白', '#0070f3', '#ffffff', '#333333',
        '#333333', '#1a1a1a', '#f5f5f5', '#ffffff', '#e5e5e5', '#ffffff', 'dot',
        'rgba(51,51,51,0.15)', xiaowei, '', smiley),
      new TemplateInfo('neon', '霓虹灯', '#ff00ff', '#121212', '#ffffff',
        '#ff00ff', '#00ffff', '#1a1a1a', 'rgba(0,255,255,0.1)', '#00ffff', '#1a1a1a', 'line',
        'rgba(255,0,255,0.35)', huangyou, '', zhimang),
      new TemplateInfo('nature', '自然绿', '#27ae60', '#f0f7f0', '#2c3e50',
        '#16a34a', '#15803d', '#dcfce7', '#f0fdf4', '#15803d', '#ecfdf5', 'vine',
        'rgba(22,163,74,0.2)', longcang, wenkai, longcang),
      new TemplateInfo('nordic', '北欧风', '#5B8FA8', '#f5f5f0', '#4a5568',
        '#475569', '#334155', '#e2e8f0', '#f8fafc', '#0ea5e9', '#f1f5f9', 'snow',
        'rgba(71,85,105,0.18)', xiaowei, '', zhimang),
    ];
  }

  static getById(id: string): TemplateInfo {
    let templates: TemplateInfo[] = Md2PngTemplates.getAll();
    for (let i = 0; i < templates.length; i++) {
      if (templates[i].id === id) {
        return templates[i];
      }
    }
    return templates[0];
  }

  static getPoetryTemplate(): ShareTemplateInfo {
    return new ShareTemplateInfo(
      '#6b8e6b', '#fdf8f0', '#4a3c2a', '#2d5a27',
      '#e8f0e8', '#f0f5ec', '#6b8e6b', '#9bb59b',
      'bamboo'
    );
  }

  static getIdiomTemplate(): ShareTemplateInfo {
    return new ShareTemplateInfo(
      '#9e2b25', '#f6efe1', '#4a3b2c', '#7a1f1f',
      '#efe6d2', '#f3ead7', '#c9a35b', '#9e2b25',
      'seal'
    );
  }

  static getXiehouyuTemplate(): ShareTemplateInfo {
    return new ShareTemplateInfo(
      '#e67e22', '#fffbf0', '#5a3e2b', '#c45100',
      '#fef0e0', '#fff5eb', '#e67e22', '#d4a574',
      'lantern'
    );
  }
}
