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

  constructor(
    id: string, name: string, icon: string, bgColor: string, textColor: string,
    accentColor: string, headerColor: string, codeBgColor: string,
    quoteBgColor: string, quoteBorderColor: string, cardBgColor: string, decorPattern: string,
    highlightBgColor: string
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
  static getAll(): TemplateInfo[] {
    return [
      new TemplateInfo('default', '简约蓝', '#4A90D9', '#ffffff', '#2c3e50',
        '#3182ce', '#1a365d', '#edf2f7', '#f7fafc', '#3182ce', '#f7fafc', 'wave',
        'rgba(49,130,206,0.15)'),
      new TemplateInfo('wechat', '清新绿', '#07c160', '#ffffff', '#3f3f3f',
        '#07c160', '#07c160', '#f7f7f7', '#f8f8f8', '#07c160', '#fafafa', 'leaf',
        'rgba(7,193,96,0.15)'),
      new TemplateInfo('xiaohongshu', '樱桃红', '#ff2e4d', '#faf5f5', '#333333',
        '#ff2e4d', '#ff2e4d', '#f9f9f9', '#fff9f9', '#ff2e4d', '#fff9f9', 'heart',
        'rgba(255,46,77,0.15)'),
      new TemplateInfo('douyin', '暗夜红', '#fe2c55', '#121212', '#ffffff',
        '#fe2c55', '#fe2c55', '#1a1a1a', 'rgba(254,44,85,0.1)', '#fe2c55', '#121212', 'glitch',
        'rgba(254,44,85,0.25)'),
      new TemplateInfo('ink', '水墨风', '#333333', '#f8f8f8', '#333333',
        '#000000', '#000000', 'rgba(0,0,0,0.05)', 'rgba(0,0,0,0.03)', '#000000', '#f8f8f8', 'mountain',
        'rgba(0,0,0,0.08)'),
      new TemplateInfo('cyberpunk', '赛博朋克', '#ff00ff', '#0a0a12', '#00ffff',
        '#ff00ff', '#ff00ff', '#1a1a2e', 'rgba(10,10,18,0.6)', '#ff00ff', '#0a0a12', 'grid',
        'rgba(255,0,255,0.25)'),
      new TemplateInfo('minimalist', '极简白', '#0070f3', '#ffffff', '#333333',
        '#000000', '#000000', '#f5f5f5', '#ffffff', '#eeeeee', '#ffffff', 'dot',
        'rgba(0,112,243,0.12)'),
      new TemplateInfo('neon', '霓虹灯', '#ff00ff', '#121212', '#ffffff',
        '#ff00ff', '#0ff', '#222222', 'rgba(255,0,255,0.1)', '#ff00ff', '#121212', 'line',
        'rgba(255,0,255,0.25)'),
      new TemplateInfo('nature', '自然绿', '#27ae60', '#f0f7f0', '#2c3e50',
        '#27ae60', '#1a5632', '#edf7ed', '#f0f7f0', '#27ae60', '#e8f5e9', 'vine',
        'rgba(39,174,96,0.15)'),
      new TemplateInfo('nordic', '北欧风', '#5B8FA8', '#f5f5f0', '#4a5568',
        '#5B8FA8', '#2d3748', '#f0f0eb', '#f5f5f0', '#5B8FA8', '#e8e8e3', 'snow',
        'rgba(91,143,168,0.15)'),
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
