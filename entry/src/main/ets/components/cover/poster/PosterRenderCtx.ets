/**
 * 文案海报渲染上下文（1.4.7 P2-1 拆分自 CopyPosterPreview，行为零变化）：
 * 每次 build() 新建实例，承载模板/内容/调色板/字号/画布等只读渲染快照与 layoutCache 排版缓存；
 * 原结构体的换算与排版私有方法（f/h/posX/posY/fy/pal/font/bodyLen/bodyFont 等）整体迁入本类。
 */
import { CopyPosterContent, CopyPosterRatio, CopyPosterTemplate } from '../../../model/CopyPosterModels';
import { CoverPalette } from '../../../model/CoverModels';
import { PosterLayout, PosterTypeset } from '../../../core/cover/PosterTypeset';

/** 拼音字号 / 主文案字号比（拼音走系统字体兜底，1.4.1 声调字符教训） */
export const PY_RATIO: number = 0.3;
/** 注音开启时主文案字号收缩系数：拼音行高≈1.17×拼音字号(0.3×字号)，预算取 1.3 系数 -> 1/(1+0.3×1.3)≈0.72 */
export const PY_SHRINK: number = 0.72;

export class PosterRenderCtx {
  readonly template: CopyPosterTemplate;
  readonly content: CopyPosterContent;
  readonly paletteIndex: number;
  readonly fontIndex: number;
  readonly ratioKind: string;
  readonly previewWidth: number;
  readonly density: number;
  readonly pinyinOn: boolean;
  readonly isThumb: boolean;

  /**
   * 最近一次 bodyFont 调用（走内核时）的排版结果，供 BodyBlock 显示「已省略 N 字」提示。
   * 未启用内核（availWidthPx <= 0）时为 null，此时不显示提示，保持优化前行为。
   */
  layoutCache: PosterLayout | null = null;

  constructor(template: CopyPosterTemplate, content: CopyPosterContent, paletteIndex: number, fontIndex: number,
    ratioKind: string, previewWidth: number, density: number, pinyinOn: boolean, isThumb: boolean) {
    this.template = template;
    this.content = content;
    this.paletteIndex = paletteIndex;
    this.fontIndex = fontIndex;
    this.ratioKind = ratioKind;
    this.previewWidth = previewWidth;
    this.density = density;
    this.pinyinOn = pinyinOn;
    this.isThumb = isThumb;
  }

  /** 设计稿 px -> vp */
  f(px: number): number {
    return this.previewWidth * px / 900;
  }

  h(): number {
    return this.previewWidth * CopyPosterRatio.designHeight(this.ratioKind) / 900;
  }

  /** 定位专用：设计稿 x（宽 900 基准）→ vp，仅作 .position 的 x 实参 */
  posX(px: number): number {
    return this.previewWidth * px / 900;
  }

  /** 定位专用：设计稿 y（高 900 基准）→ vp，仅作 .position 的 y 实参 */
  posY(py: number): number {
    return this.h() * py / 900;
  }

  pal(): CoverPalette {
    let list: CoverPalette[] = this.template.palettes;
    if (this.paletteIndex >= 0 && this.paletteIndex < list.length) {
      return list[this.paletteIndex];
    }
    return list[0];
  }

  font(): string {
    let list: string[] = this.template.fonts;
    if (this.fontIndex >= 0 && this.fontIndex < list.length) {
      return list[this.fontIndex];
    }
    return list.length > 0 ? list[0] : '';
  }

  /** 主文案有效字数（去空白） */
  bodyLen(): number {
    return this.content.body.replace(new RegExp('\\s', 'g'), '').length;
  }

  /**
   * 主文案字号。
   *
   * 兼容说明（1.4.5 文案海报优化 P0-2）：
   *   - availWidthPx 为可选参数。未传（<=0）时**行为与优化前完全一致**，走原 5 档阶梯；
   *     这样 18 个 Builder 调用点可分批迁移，任一中途状态工程都可编译可运行。
   *   - 传入容器可用宽度（设计稿 px）后，改由 PosterTypeset 内核按「宽度 + 行数预算」连续计算，
   *     消除 32→33 字的字号骤变，并让窄容器（T1 pad70）不再顶格、宽容器（T10 pad24）不再显小。
   *
   * @param basePx        该模板的基准字号（设计稿 px）
   * @param big           是否大字模板
   * @param availWidthPx  容器可用宽度（设计稿 px）。<=0 表示不启用内核
   * @param maxLines      行数预算覆盖（>0 生效）。用于两类场景：
   *                      1) 渲染 maxLines 与内核预算错配的模板（T7 渲染 3 行但内核按 8/12 行算字）；
   *                      2) 主文案与署名/dots 同列纵向排布的模板预留行数，避免满文案把署名挤出画布。
   */
  bodyFont(basePx: number, big: boolean, availWidthPx: number = 0, maxLines: number = 0): number {
    if (availWidthPx > 0) {
      let budget: number = maxLines > 0 ? maxLines : this.maxBodyLines(big);
      let layout: PosterLayout = PosterTypeset.layout(
        this.content.body, availWidthPx, budget, basePx, big);
      // 内核 fontPx 是设计稿 px（相对 900 宽），渲染前必须经 f() 缩放到实际预览尺寸；
      // 漏掉这步会把字号直接当 fp 用（放大 ~900/previewWidth 倍），行数膨胀把署名挤出画布。
      let px: number = this.f(layout.fontPx);
      this.layoutCache = layout;
      return this.pyEnabled() ? px * PY_SHRINK : px;
    }
    let n: number = this.bodyLen();
    let s: number;
    if (big) {
      if (n <= 4) {
        s = this.f(150);
      } else if (n <= 8) {
        s = this.f(112);
      } else if (n <= 16) {
        s = this.f(80);
      } else {
        s = this.f(52);
      }
    } else if (n <= 8) {
      s = this.f(basePx);
    } else if (n <= 16) {
      s = this.f(basePx * 0.8);
    } else if (n <= 32) {
      s = this.f(basePx * 0.62);
    } else if (n <= 60) {
      s = this.f(basePx * 0.48);
    } else {
      s = this.f(basePx * 0.38);
    }
    this.layoutCache = null;
    return this.pyEnabled() ? s * PY_SHRINK : s;
  }

  /** 主文案行数上限：竖图更宽容 */
  maxBodyLines(big: boolean): number {
    if (big && this.bodyLen() <= 16) {
      return 4;
    }
    return this.ratioKind === CopyPosterRatio.SQUARE ? 8 : 12;
  }

  /**
   * 长文案行数预算预留（1.4.5 真机走查 P1）：主文案与署名/dots/tag 同列纵向排布的模板，
   * 满文案（8/12 行）会把署名挤出画布（T1 走查：120 字时署名从 dump 消失）。
   * 从预算里预留 reserve 行给兄弟元素；紧凑块（大字短文案 ≤4 行）本就克制，不压缩。
   */
  bodyBudget(reserve: number, big: boolean = false): number {
    let max: number = this.maxBodyLines(big);
    if (max <= 4) {
      return max;
    }
    return Math.max(3, max - reserve);
  }

  /** 注音是否生效：开关开 + 模板支持 + 主文案非空 */
  pyEnabled(): boolean {
    return this.pinyinOn && this.template.supportsPinyin && this.content.body.trim() !== '';
  }

  /** 注音模式字/拼音阴影：neon=霓虹三层 / soft=荧光单层 / none=无（透明零半径兜底保持数组非空） */
  pyShadow(glow: string): ShadowOptions[] {
    if (glow === 'neon') {
      return [
        { radius: this.f(4), color: '#FFFFFFFF', offsetX: 0, offsetY: 0 },
        { radius: this.f(10), color: this.hexA(this.pal().accent, '#E6'), offsetX: 0, offsetY: 0 },
        { radius: this.f(26), color: this.hexA(this.pal().accent, '#8C'), offsetX: 0, offsetY: 0 },
      ];
    }
    if (glow === 'soft') {
      return [{ radius: this.f(3), color: this.hexA(this.pal().accent, '#B3'), offsetX: 0, offsetY: 0 }];
    }
    return [{ radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 }];
  }

  /**
   * 截断提示字数：仅在启用内核（availWidthPx > 0）且判定为截断时返回，其余返回 0（不显示提示）。
   * 需在 bodyFont 调用之后取值（layoutCache 由 bodyFont 写入）。
   */
  truncatedHint(): number {
    let cache: PosterLayout | null = this.layoutCache;
    if (cache !== null && cache.truncated && cache.truncatedChars > 0) {
      return cache.truncatedChars;
    }
    return 0;
  }

  /** 竖排列渲染序：内核返回阅读序（首列在前），渲染需首列在最右，反转并滤空列 */
  vertRenderCols(cols: string[][]): string[][] {
    let out: string[][] = [];
    for (let i = cols.length - 1; i >= 0; i--) {
      if (cols[i].length > 0) {
        out.push(cols[i]);
      }
    }
    return out;
  }

  /** 任意色加透明度前缀（如 hexA('#FF4FD8', '#80') -> '#80FF4FD8'；alpha 也接受不带 # 的 '80'） */
  hexA(color: string, alphaHex: string): string {
    let a: string = alphaHex.startsWith('#') ? alphaHex.substring(1) : alphaHex;
    return '#' + a + color.substring(1);
  }

  /** 设计稿 y（1:1 基准 900 高）按实际画布高换算，3:4 时按比例下沉 */
  fy(py: number): number {
    return this.h() * py / 900;
  }
}
