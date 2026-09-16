/**
 * GIF 叠加层(贴纸/文字)数据模型与纯函数。
 * 坐标 x/y 为画布中心点的归一化值(0~1)，fontPx 为相对 480px 基准画布高度的字号，
 * 导出与预览时按实际画布高度等比换算，保证所见即所得。
 */

/** 叠加层基准参考高度(px) */
export const OVERLAY_REF_HEIGHT: number = 480;

export const TEXT_FONT_MIN: number = 12;
export const TEXT_FONT_MAX: number = 72;
export const STICKER_FONT_MIN: number = 12;
export const STICKER_FONT_MAX: number = 160;

/** 叠加层类型：文字 */
export const OVERLAY_KIND_TEXT: string = 'text';
/** 叠加层类型：贴纸(emoji) */
export const OVERLAY_KIND_STICKER: string = 'sticker';

export class OverlayItem {
  id: string;
  kind: string;
  text: string;
  color: string;
  fontPx: number;
  x: number;
  y: number;
  rotation: number;

  constructor(kind: string, text: string, color: string, fontPx: number, x: number, y: number, rotation: number,
    id: string = '') {
    this.kind = kind;
    this.text = text;
    this.color = color;
    this.fontPx = fontPx;
    this.x = x;
    this.y = y;
    this.rotation = rotation;
    this.id = id;
  }
}

function clampNumber(v: number, min: number, max: number): number {
  if (v < min) {
    return min;
  }
  if (v > max) {
    return max;
  }
  return v;
}

function hexNibble(c: number): number {
  if (c >= 48 && c <= 57) {
    return c - 48;
  }
  if (c >= 97 && c <= 102) {
    return c - 87;
  }
  if (c >= 65 && c <= 70) {
    return c - 55;
  }
  return -1;
}

/**
 * 将 '#RGB' 或 '#RRGGBB' 颜色字符串解析为 0xAARRGGBB(不透明)。
 * 非法输入返回不透明白色。
 */
export function overlayColorToArgb(color: string): number {
  const WHITE: number = 0xFFFFFFFF;
  if (typeof color !== 'string' || color.length < 2 || color.charCodeAt(0) !== 35) {
    return WHITE;
  }
  let body: string = color.substring(1);
  if (body.length === 3) {
    let r: number = hexNibble(body.charCodeAt(0));
    let g: number = hexNibble(body.charCodeAt(1));
    let b: number = hexNibble(body.charCodeAt(2));
    if (r < 0 || g < 0 || b < 0) {
      return WHITE;
    }
    return ((0xFF000000 | (r << 20) | (r << 16) | (g << 12) | (g << 8) | (b << 4) | b) >>> 0);
  }
  if (body.length === 6) {
    let r1: number = hexNibble(body.charCodeAt(0));
    let r2: number = hexNibble(body.charCodeAt(1));
    let g1: number = hexNibble(body.charCodeAt(2));
    let g2: number = hexNibble(body.charCodeAt(3));
    let b1: number = hexNibble(body.charCodeAt(4));
    let b2: number = hexNibble(body.charCodeAt(5));
    if (r1 < 0 || r2 < 0 || g1 < 0 || g2 < 0 || b1 < 0 || b2 < 0) {
      return WHITE;
    }
    return ((0xFF000000 | (r1 << 20) | (r2 << 16) | (g1 << 12) | (g2 << 8) | (b1 << 4) | b2) >>> 0);
  }
  return WHITE;
}

/** 叠加层字号范围：文字 12~72，贴纸 12~160 */
export function clampOverlayFont(kind: string, px: number): number {
  if (kind === OVERLAY_KIND_STICKER) {
    return clampNumber(Math.round(px), STICKER_FONT_MIN, STICKER_FONT_MAX);
  }
  return clampNumber(Math.round(px), TEXT_FONT_MIN, TEXT_FONT_MAX);
}

/** 归一化坐标限制到 0~1 */
export function clampOverlayPos(v: number): number {
  return clampNumber(v, 0, 1);
}

/** 旋转角归一化到 [0, 360) */
export function normalizeOverlayRotation(deg: number): number {
  let d: number = deg % 360;
  if (d < 0) {
    d += 360;
  }
  return d;
}

/** 按(预览盒/导出画布)实际高度换算字号 px，四舍五入且至少 1px */
export function overlayFontPx(fontPx: number, refHeight: number): number {
  let px: number = Math.round(fontPx * refHeight / OVERLAY_REF_HEIGHT);
  if (px < 1) {
    px = 1;
  }
  return px;
}
