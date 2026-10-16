/**
 * 文案海报渲染上下文（1.4.7 P2-1 修复 ctx 冻结回归：类改为接口）。
 * 门面 CopyPosterPreview 实现本接口并作为 ctx 实参传给 21 个模板全局 @Builder：
 * 模板内 c.xxx 的每次读取最终落在门面 @Prop getter 上，随 V1 局部更新逐 observe 作用域刷新，
 * 恢复 1.4.6 单体的全量刷新语义。此前 makeCtx() 每次渲染快照传参不在追踪图内，
 * 导致内容编辑/水印/配色切换后预览不刷新（ctx 冻结）。
 */
import { CopyPosterContent, CopyPosterTemplate } from '../../../model/CopyPosterModels';
import { CoverPalette } from '../../../model/CoverModels';

/** 拼音字号 / 主文案字号比（拼音走系统字体兜底，1.4.1 声调字符教训） */
export const PY_RATIO: number = 0.3;
/** 注音开启时主文案字号收缩系数：拼音行高≈1.17×拼音字号(0.3×字号)，预算取 1.3 系数 -> 1/(1+0.3×1.3)≈0.72 */
export const PY_SHRINK: number = 0.72;

export interface PosterRenderCtx {
  readonly template: CopyPosterTemplate;
  readonly content: CopyPosterContent;
  readonly paletteIndex: number;
  readonly fontIndex: number;
  readonly ratioKind: string;
  readonly previewWidth: number;
  /** 屏幕密度（vp->px） */
  readonly density: number;
  /** 主文案拼音注音开关（固定构图模板不生效） */
  readonly pinyinOn: boolean;
  /** 是否为模板选择器的缩略图渲染（96px 见方） */
  readonly isThumb: boolean;

  /** 设计稿 px -> vp */
  f(px: number): number;
  /** 设计稿高度（vp）：宽 900 基准按比例换算 */
  h(): number;
  /** 定位专用：设计稿 x（宽 900 基准）→ vp，仅作 .position 的 x 实参 */
  posX(px: number): number;
  /** 定位专用：设计稿 y（高 900 基准）→ vp，仅作 .position 的 y 实参 */
  posY(py: number): number;
  pal(): CoverPalette;
  font(): string;
  /** 主文案有效字数（去空白） */
  bodyLen(): number;
  /** 主文案字号：availWidthPx>0 走排版内核连续计算，否则按长度阶梯 */
  bodyFont(basePx: number, big: boolean, availWidthPx?: number, maxLines?: number): number;
  /** 主文案行数上限：竖图更宽容 */
  maxBodyLines(big: boolean): number;
  /** 长文案行数预算预留：主文案与署名/dots/tag 同列的模板满文案防挤出版面 */
  bodyBudget(reserve: number, big?: boolean): number;
  /** 注音是否生效：开关开 + 模板支持 + 主文案非空 */
  pyEnabled(): boolean;
  /** 注音模式字/拼音阴影：neon=霓虹三层 / soft=荧光单层 / none=无（透明零半径兜底保持数组非空） */
  pyShadow(glow: string): ShadowOptions[];
  /** 截断提示字数：需在 bodyFont 之后取值；不截断返回 0（不显示提示） */
  truncatedHint(): number;
  /** 竖排列渲染序：内核返回阅读序（首列在前），渲染需首列在最右，反转并滤空列 */
  vertRenderCols(cols: string[][]): string[][];
  /** 任意色加透明度前缀（如 hexA('#FF4FD8', '#80') -> '#80FF4FD8'；alpha 也接受不带 # 的 '80'） */
  hexA(color: string, alphaHex: string): string;
  /** 设计稿 y（1:1 基准 900 高）按实际画布高换算，3:4 时按比例下沉 */
  fy(py: number): number;
}
