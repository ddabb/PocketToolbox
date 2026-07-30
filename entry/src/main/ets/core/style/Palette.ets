import { TemplateInfo, Md2PngTemplates } from '../../model/Md2PngModels';

export class PaletteColor {
  bgColor: string = '#ffffff';
  colors: string[] = [];

  constructor(bgColor: string, colors: string[]) {
    this.bgColor = bgColor;
    this.colors = colors;
  }
}

export class Palette {
  private static readonly WORD_CLOUD_PALETTES: Record<string, string[]> = {
    'default': ['#2563eb', '#1e40af', '#3b82f6', '#60a5fa', '#1d4ed8', '#93c5fd', '#1e3a5f', '#7dd3fc'],
    'wechat': ['#059669', '#047857', '#10b981', '#34d399', '#065f46', '#6ee7b7', '#0d9488', '#a7f3d0'],
    'xiaohongshu': ['#dc2626', '#ef4444', '#f87171', '#b91c1c', '#fb923c', '#f97316', '#fca5a5', '#ea580c'],
    'douyin': ['#fe2c55', '#00f2ea', '#ff0050', '#25f4ee', '#ff6b9d', '#00c4b4', '#e6003a', '#008f87'],
    'ink': ['#1f2937', '#4b5563', '#6b7280', '#374151', '#9ca3af', '#111827', '#78716c', '#57534e'],
    'cyberpunk': ['#ff00ff', '#00ffff', '#ff0080', '#8000ff', '#00ff80', '#ffff00', '#ff4081', '#40c4ff'],
    'minimalist': ['#0070f3', '#333333', '#666666', '#1a1a1a', '#171717', '#525252', '#0a0a0a', '#a3a3a3'],
    'neon': ['#ff00ff', '#00ffff', '#39ff14', '#ff6ec7', '#ffff00', '#7b68ee', '#ff4500', '#00ff7f'],
    'nature': ['#16a34a', '#15803d', '#22c55e', '#4ade80', '#166534', '#86efac', '#a3e635', '#65a30d'],
    'nordic': ['#5B8FA8', '#475569', '#0ea5e9', '#64748b', '#0284c7', '#94a3b8', '#334155', '#7dd3fc'],
  };

  static getAll(): PaletteColor[] {
    let templates: TemplateInfo[] = Md2PngTemplates.getAll();
    let palettes: PaletteColor[] = [];
    for (let i = 0; i < templates.length; i++) {
      let tpl: TemplateInfo = templates[i];
      let colors: string[] = Palette.getWordCloudColors(tpl.id);
      palettes.push(new PaletteColor(tpl.bgColor, colors));
    }
    return palettes;
  }

  static getById(id: string): PaletteColor {
    let tpl: TemplateInfo = Md2PngTemplates.getById(id);
    let colors: string[] = Palette.getWordCloudColors(tpl.id);
    return new PaletteColor(tpl.bgColor, colors);
  }

  static getNames(): string[] {
    let templates: TemplateInfo[] = Md2PngTemplates.getAll();
    let names: string[] = [];
    for (let i = 0; i < templates.length; i++) {
      names.push(templates[i].name);
    }
    return names;
  }

  static getIds(): string[] {
    let templates: TemplateInfo[] = Md2PngTemplates.getAll();
    let ids: string[] = [];
    for (let i = 0; i < templates.length; i++) {
      ids.push(templates[i].id);
    }
    return ids;
  }

  private static getWordCloudColors(templateId: string): string[] {
    let palette: string[] | undefined = Palette.WORD_CLOUD_PALETTES[templateId];
    if (palette !== undefined && palette.length > 0) {
      return palette;
    }
    return ['#333333', '#666666', '#999999', '#1a1a1a', '#4a4a4a', '#7a7a7a'];
  }
}
