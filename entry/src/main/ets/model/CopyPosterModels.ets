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
  /** 水印开关（随历史存储，旧记录缺省 false 兼容） */
  watermarkOn: boolean = false;
  /** 水印文字（清空则不渲染） */
  watermarkText: string = '';

  copy(): CopyPosterContent {
    let c: CopyPosterContent = new CopyPosterContent();
    c.body = this.body;
    c.sign = this.sign;
    c.tag = this.tag;
    c.watermarkOn = this.watermarkOn;
    c.watermarkText = this.watermarkText;
    return c;
  }

  toJson(): string {
    let r: Record<string, Object> = {
      'body': this.body,
      'sign': this.sign,
      'tag': this.tag,
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
      c.watermarkOn = r['watermarkOn'] === true;
      c.watermarkText = String(r['watermarkText'] ?? '');
    } catch (e) {
      console.error('[CopyPoster] parse content json failed: ' + (e as Error).message);
    }
    return c;
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

  static of(id: string, name: ResourceStr, layout: string, slots: string[], palettes: CoverPalette[],
    fonts: string[], defaults: Record<string, string>, supportsPinyin: boolean = true): CopyPosterTemplate {
    let t: CopyPosterTemplate = new CopyPosterTemplate();
    t.id = id;
    t.name = name;
    t.layout = layout;
    t.slots = slots;
    t.palettes = palettes;
    t.fonts = fonts;
    t.defaults = defaults;
    t.supportsPinyin = supportsPinyin;
    return t;
  }
}
