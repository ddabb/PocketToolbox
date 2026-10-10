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

/** 导出比例：1:1（1080x1080）/ 3:4（1080x1440） */
export class CopyPosterRatio {
  static readonly SQUARE: string = 'square';
  static readonly PORTRAIT: string = 'portrait';

  static label(kind: string): ResourceStr {
    if (kind === CopyPosterRatio.PORTRAIT) {
      return $r('app.string.poster_ratio_portrait');
    }
    return $r('app.string.poster_ratio_square');
  }

  static all(): string[] {
    return [CopyPosterRatio.SQUARE, CopyPosterRatio.PORTRAIT];
  }

  /** 设计稿高度（宽恒 900）：1:1 -> 900，3:4 -> 1200 */
  static designHeight(kind: string): number {
    return kind === CopyPosterRatio.PORTRAIT ? 1200 : 900;
  }

  /** 导出像素高度（宽恒 1080）：1:1 -> 1080，3:4 -> 1440 */
  static exportHeight(kind: string): number {
    return kind === CopyPosterRatio.PORTRAIT ? 1440 : 1080;
  }
}

/** 槽位内容 */
export class CopyPosterContent {
  body: string = '';
  sign: string = '';
  tag: string = '';

  copy(): CopyPosterContent {
    let c: CopyPosterContent = new CopyPosterContent();
    c.body = this.body;
    c.sign = this.sign;
    c.tag = this.tag;
    return c;
  }

  toJson(): string {
    let r: Record<string, Object> = {
      'body': this.body,
      'sign': this.sign,
      'tag': this.tag,
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

  static of(id: string, name: ResourceStr, layout: string, slots: string[], palettes: CoverPalette[],
    fonts: string[], defaults: Record<string, string>): CopyPosterTemplate {
    let t: CopyPosterTemplate = new CopyPosterTemplate();
    t.id = id;
    t.name = name;
    t.layout = layout;
    t.slots = slots;
    t.palettes = palettes;
    t.fonts = fonts;
    t.defaults = defaults;
    return t;
  }
}
