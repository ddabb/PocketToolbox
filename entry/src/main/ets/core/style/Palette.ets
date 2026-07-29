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
  static getAll(): PaletteColor[] {
    let templates: TemplateInfo[] = Md2PngTemplates.getAll();
    let palettes: PaletteColor[] = [];
    for (let i = 0; i < templates.length; i++) {
      let tpl: TemplateInfo = templates[i];
      let colors: string[] = Palette.derivePalette(tpl);
      palettes.push(new PaletteColor(tpl.bgColor, colors));
    }
    return palettes;
  }

  static getById(id: string): PaletteColor {
    let tpl: TemplateInfo = Md2PngTemplates.getById(id);
    let colors: string[] = Palette.derivePalette(tpl);
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

  private static derivePalette(tpl: TemplateInfo): string[] {
    let colors: string[] = [];
    if (tpl.accentColor && tpl.accentColor.length > 0) {
      colors.push(tpl.accentColor);
    }
    if (tpl.textColor && tpl.textColor.length > 0) {
      colors.push(tpl.textColor);
    }
    if (tpl.headerColor && tpl.headerColor.length > 0) {
      colors.push(tpl.headerColor);
    }
    colors.push(Palette.lighten(tpl.accentColor, 40));
    colors.push(Palette.darken(tpl.accentColor, 30));
    let extras: string[] = Palette.generateVariants(tpl.accentColor);
    for (let i = 0; i < extras.length; i++) {
      colors.push(extras[i]);
    }
    return colors;
  }

  private static lighten(hex: string, percent: number): string {
    let rgb: number[] = Palette.hexToRgb(hex);
    if (rgb.length < 3) {
      return '#888888';
    }
    let r: number = Math.min(255, rgb[0] + Math.floor((255 - rgb[0]) * percent / 100));
    let g: number = Math.min(255, rgb[1] + Math.floor((255 - rgb[1]) * percent / 100));
    let b: number = Math.min(255, rgb[2] + Math.floor((255 - rgb[2]) * percent / 100));
    return Palette.rgbToHex(r, g, b);
  }

  private static darken(hex: string, percent: number): string {
    let rgb: number[] = Palette.hexToRgb(hex);
    if (rgb.length < 3) {
      return '#222222';
    }
    let r: number = Math.max(0, Math.floor(rgb[0] * (100 - percent) / 100));
    let g: number = Math.max(0, Math.floor(rgb[1] * (100 - percent) / 100));
    let b: number = Math.max(0, Math.floor(rgb[2] * (100 - percent) / 100));
    return Palette.rgbToHex(r, g, b);
  }

  private static generateVariants(baseHex: string): string[] {
    let rgb: number[] = Palette.hexToRgb(baseHex);
    if (rgb.length < 3) {
      return [];
    }
    let results: string[] = [];
    results.push(Palette.rgbToHex(Math.min(255, rgb[1]), Math.min(255, rgb[2]), rgb[0]));
    results.push(Palette.rgbToHex(Math.min(255, rgb[2]), rgb[0], Math.min(255, rgb[1])));
    results.push(Palette.rgbToHex(
      Math.min(255, Math.floor((rgb[0] + rgb[1]) / 2)),
      Math.min(255, Math.floor((rgb[1] + rgb[2]) / 2)),
      Math.min(255, Math.floor((rgb[2] + rgb[0]) / 2))
    ));
    return results;
  }

  private static hexToRgb(hex: string): number[] {
    if (!hex || hex.length < 7) {
      return [];
    }
    let h: string = hex.startsWith('#') ? hex.substring(1) : hex;
    if (h.length < 6) {
      return [];
    }
    let r: number = parseInt(h.substring(0, 2), 16);
    let g: number = parseInt(h.substring(2, 4), 16);
    let b: number = parseInt(h.substring(4, 6), 16);
    if (isNaN(r) || isNaN(g) || isNaN(b)) {
      return [];
    }
    return [r, g, b];
  }

  private static rgbToHex(r: number, g: number, b: number): string {
    let rs: string = r.toString(16).padStart(2, '0');
    let gs: string = g.toString(16).padStart(2, '0');
    let bs: string = b.toString(16).padStart(2, '0');
    return '#' + rs + gs + bs;
  }
}
