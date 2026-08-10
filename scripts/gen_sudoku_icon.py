"""
gen_sudoku_icon.py
用 Python 标准库生成数独求解器 PNG 图标（无第三方依赖）
风格：白色圆角卡片背景 + 深墨蓝网格（粗细对比强烈）+ 3个主色数字点缀
输出: entry/src/main/resources/base/media/creative_sudoku.png (144x144 @3x)
用法: py scripts/gen_sudoku_icon.py
"""
import struct
import zlib
import os
import math

OUTPUT = os.path.join('entry', 'src', 'main', 'resources', 'base', 'media', 'creative_sudoku.png')
W = 144
H = 144

# ---------- PNG 工具 ----------
def _chunk(ctype, data):
    c = zlib.crc32(ctype + data) & 0xffffffff
    return struct.pack('>I', len(data)) + ctype + data + struct.pack('>I', c)

def write_png(rgba, w, h, path):
    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)
    stride = w * 4
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw.extend(rgba[y * stride:(y + 1) * stride])
    idat = zlib.compress(bytes(raw), 9)
    with open(path, 'wb') as f:
        f.write(sig)
        f.write(_chunk(b'IHDR', ihdr))
        f.write(_chunk(b'IDAT', idat))
        f.write(_chunk(b'IEND', b''))

# ---------- 像素绘制 ----------
def _mix(dst_rgba, dst_i, r, g, b, a):
    sa = a / 255.0
    da = dst_rgba[dst_i + 3] / 255.0
    oa = sa + da * (1 - sa)
    if oa == 0:
        return
    dst_rgba[dst_i]     = round((r * sa + dst_rgba[dst_i]     * da * (1 - sa)) / oa)
    dst_rgba[dst_i + 1] = round((g * sa + dst_rgba[dst_i + 1] * da * (1 - sa)) / oa)
    dst_rgba[dst_i + 2] = round((b * sa + dst_rgba[dst_i + 2] * da * (1 - sa)) / oa)
    dst_rgba[dst_i + 3] = round(oa * 255)

def set_px(buf, x, y, r, g, b, a):
    if x < 0 or y < 0 or x >= W or y >= H:
        return
    _mix(buf, (y * W + x) * 4, r, g, b, a)

def line_h(buf, x0, x1, y, thickness, r, g, b, a):
    t2 = thickness / 2.0
    for yi in range(int(y - t2 - 0.5), int(y + t2 + 0.5) + 1):
        dy = abs(yi - y)
        if dy > t2:
            continue
        aa = 1.0 if dy < t2 - 0.5 else max(0.0, t2 + 0.5 - dy)
        aa_a = round(a * aa)
        for xi in range(int(x0 - 0.5), int(x1 + 0.5) + 1):
            set_px(buf, xi, yi, r, g, b, aa_a)

def line_v(buf, x, y0, y1, thickness, r, g, b, a):
    t2 = thickness / 2.0
    for xi in range(int(x - t2 - 0.5), int(x + t2 + 0.5) + 1):
        dx = abs(xi - x)
        if dx > t2:
            continue
        aa = 1.0 if dx < t2 - 0.5 else max(0.0, t2 + 0.5 - dx)
        aa_a = round(a * aa)
        for yi in range(int(y0 - 0.5), int(y1 + 0.5) + 1):
            set_px(buf, xi, yi, r, g, b, aa_a)

def corner_arc(buf, cx, cy, radius, a0, a1, thickness, r, g, b, a):
    steps = 40
    pts = []
    for i in range(steps + 1):
        ang = a0 + (a1 - a0) * (i / steps)
        pts.append((cx + math.cos(ang) * radius, cy + math.sin(ang) * radius))
    for i in range(len(pts) - 1):
        ax, ay = pts[i]
        bx, by = pts[i + 1]
        if abs(ax - bx) > abs(ay - by):
            line_h(buf, min(ax, bx), max(ax, bx), (ay + by) / 2, thickness, r, g, b, a)
        else:
            line_v(buf, (ax + bx) / 2, min(ay, by), max(ay, by), thickness, r, g, b, a)

def fill_rect(buf, x0, y0, x1, y1, r, g, b, a):
    for yi in range(int(y0), int(y1 + 1)):
        for xi in range(int(x0), int(x1 + 1)):
            set_px(buf, xi, yi, r, g, b, a)

# ---------- 圆角矩形实心填充 ----------
def fill_rounded_rect(buf, x0, y0, x1, y1, radius, r, g, b, a):
    # 主体矩形
    fill_rect(buf, x0, y0 + radius, x1, y1 - radius, r, g, b, a)
    fill_rect(buf, x0 + radius, y0, x1 - radius, y0 + radius, r, g, b, a)
    fill_rect(buf, x0 + radius, y1 - radius, x1 - radius, y1, r, g, b, a)
    # 四个圆角（逐像素画圆内区域）
    corners = [
        (x0 + radius, y0 + radius),        # 左上
        (x1 - radius, y0 + radius),        # 右上
        (x0 + radius, y1 - radius),        # 左下
        (x1 - radius, y1 - radius),        # 右下
    ]
    r2 = radius * radius
    for cx, cy in corners:
        y_min = int(cy - radius - 0.5)
        y_max = int(cy + radius + 0.5)
        x_min = int(cx - radius - 0.5)
        x_max = int(cx + radius + 0.5)
        for yi in range(y_min, y_max + 1):
            for xi in range(x_min, x_max + 1):
                dx = xi - cx
                dy = yi - cy
                # 判断是否在圆角矩形象限内
                in_quad = False
                if cx == x0 + radius and cy == y0 + radius:
                    in_quad = (dx <= 0 and dy <= 0)
                elif cx == x1 - radius and cy == y0 + radius:
                    in_quad = (dx >= 0 and dy <= 0)
                elif cx == x0 + radius and cy == y1 - radius:
                    in_quad = (dx <= 0 and dy >= 0)
                elif cx == x1 - radius and cy == y1 - radius:
                    in_quad = (dx >= 0 and dy >= 0)
                if not in_quad:
                    continue
                dist2 = dx * dx + dy * dy
                if dist2 <= r2:
                    # 抗锯齿：r2 边界 ±1 像素
                    edge = radius + 0.5
                    dist = math.sqrt(dist2)
                    if dist < radius - 0.5:
                        aa = 1.0
                    elif dist > edge:
                        aa = 0.0
                    else:
                        aa = edge - dist
                    set_px(buf, xi, yi, r, g, b, round(a * aa))

# ---------- 绘制数字（用简单像素点阵，5x7 字形缩放） ----------
# 0-9 十个数字的 5x7 字形（0=空,1=填）
GLYPHS = {
    '1': [
        [0,1,1,0,0],
        [1,1,1,0,0],
        [0,1,1,0,0],
        [0,1,1,0,0],
        [0,1,1,0,0],
        [0,1,1,0,0],
        [1,1,1,1,1],
    ],
    '2': [
        [0,1,1,1,0],
        [1,0,0,0,1],
        [0,0,0,0,1],
        [0,0,0,1,0],
        [0,0,1,0,0],
        [0,1,0,0,0],
        [1,1,1,1,1],
    ],
    '3': [
        [1,1,1,1,0],
        [0,0,0,0,1],
        [0,0,0,0,1],
        [0,0,1,1,0],
        [0,0,0,0,1],
        [0,0,0,0,1],
        [1,1,1,1,0],
    ],
    '4': [
        [0,0,0,1,0],
        [0,0,1,1,0],
        [0,1,0,1,0],
        [1,0,0,1,0],
        [1,1,1,1,1],
        [0,0,0,1,0],
        [0,0,0,1,0],
    ],
    '5': [
        [1,1,1,1,1],
        [1,0,0,0,0],
        [1,0,0,0,0],
        [1,1,1,1,0],
        [0,0,0,0,1],
        [0,0,0,0,1],
        [1,1,1,1,0],
    ],
    '6': [
        [0,1,1,1,0],
        [1,0,0,0,0],
        [1,0,0,0,0],
        [1,1,1,1,0],
        [1,0,0,0,1],
        [1,0,0,0,1],
        [0,1,1,1,0],
    ],
    '7': [
        [1,1,1,1,1],
        [0,0,0,0,1],
        [0,0,0,1,0],
        [0,0,1,0,0],
        [0,1,0,0,0],
        [0,1,0,0,0],
        [0,1,0,0,0],
    ],
    '8': [
        [0,1,1,1,0],
        [1,0,0,0,1],
        [1,0,0,0,1],
        [0,1,1,1,0],
        [1,0,0,0,1],
        [1,0,0,0,1],
        [0,1,1,1,0],
    ],
    '9': [
        [0,1,1,1,0],
        [1,0,0,0,1],
        [1,0,0,0,1],
        [0,1,1,1,1],
        [0,0,0,0,1],
        [0,0,0,0,1],
        [0,1,1,1,0],
    ],
}

def draw_glyph(buf, ch, cx, cy, cell_w, cell_h, r, g, b, a):
    """在 (cx, cy) 为中心画字形；每点 1 像素，总尺寸 < cell，绝不超出格子"""
    pat = GLYPHS[ch]
    rows = len(pat)
    cols = len(pat[0])
    # 每点 1 像素 → 字形 5×7 px，远小于 CELL (~12px)，居中留足边距
    px_per_dot = 1
    gw = px_per_dot * cols
    gh = px_per_dot * rows
    # 严格整数居中
    px = int(round(cx - gw / 2))
    py = int(round(cy - gh / 2))
    for ri in range(rows):
        for ci in range(cols):
            if not pat[ri][ci]:
                continue
            xi = px + ci * px_per_dot
            yi = py + ri * px_per_dot
            if xi < 0 or xi >= W or yi < 0 or yi >= H:
                continue
            i = (yi * W + xi) * 4
            buf[i]     = r
            buf[i + 1] = g
            buf[i + 2] = b
            buf[i + 3] = a

# ---------- 主绘制 ----------
def main():
    buf = bytearray(W * H * 4)  # 默认全透明背景

    # === 1. 外层白色圆角卡片（整张图标作为卡片，留约 5% 透明边） ===
    CARD_PAD = round(W * 0.05)
    CARD_R = W * 0.15
    CARD_RGB = (255, 255, 255, 255)
    fill_rounded_rect(buf, CARD_PAD, CARD_PAD, W - CARD_PAD - 1, H - CARD_PAD - 1, CARD_R, *CARD_RGB)

    # 卡片底部淡淡的投影（下沿半透明深灰叠一层，增加立体感）
    shadow_rgb = (148, 163, 184, 35)  # ~14% alpha 灰色
    for i in range(3):
        shadow_pad = CARD_PAD + i + 2
        shadow_h = 3 + i
        fill_rounded_rect(
            buf,
            shadow_pad, H - CARD_PAD - shadow_h - i,
            W - shadow_pad - 1, H - CARD_PAD - i,
            CARD_R * 0.5,
            *shadow_rgb
        )

    # === 2. 数独网格：卡片内部再缩进 ===
    PAD = round(W * 0.08)   # ~12px，网格放大让 CELL 更宽敞，数字不拥挤
    x0 = PAD
    y0 = PAD
    grid_w = W - PAD * 2
    CELL = grid_w / 9       # ~13.3 px（之前 ~12.4）

    # 颜色：深墨蓝网格 + 中灰细线；线宽再细一档
    thin_w  = max(0.7, W * 0.011)  # ~1.6 细线（再 -21%）
    thick_w = max(1.3, W * 0.022)  # ~3.2 粗线（再 -21%）
    outer_w = max(1.7, W * 0.028)  # ~4.0 外框（再 -18%）
    LINE_DARK = (30, 41, 59, 255)   # slate-800
    LINE_MID  = (148, 163, 184, 220) # slate-400 稍浅，让粗细对比更明显

    # === 3. 细线（1x1 网格） ===
    for i in range(1, 9):
        if i in (3, 6):
            continue
        line_h(buf, x0, x0 + grid_w, y0 + i * CELL, thin_w, *LINE_MID)
        line_v(buf, x0 + i * CELL, y0, y0 + grid_w, thin_w, *LINE_MID)

    # === 4. 粗线（3x3 宫格分隔） ===
    for i in (3, 6):
        line_h(buf, x0, x0 + grid_w, y0 + i * CELL, thick_w, *LINE_DARK)
        line_v(buf, x0 + i * CELL, y0, y0 + grid_w, thick_w, *LINE_DARK)

    # === 5. 外框（最深、最粗、带圆角） ===
    CORNER = W * 0.06
    line_h(buf, x0 + CORNER, x0 + grid_w - CORNER, y0, outer_w, *LINE_DARK)
    line_h(buf, x0 + CORNER, x0 + grid_w - CORNER, y0 + grid_w, outer_w, *LINE_DARK)
    line_v(buf, x0, y0 + CORNER, y0 + grid_w - CORNER, outer_w, *LINE_DARK)
    line_v(buf, x0 + grid_w, y0 + CORNER, y0 + grid_w - CORNER, outer_w, *LINE_DARK)

    corner_arc(buf, x0 + CORNER, y0 + CORNER, CORNER, math.pi, math.pi * 1.5, outer_w, *LINE_DARK)
    corner_arc(buf, x0 + grid_w - CORNER, y0 + CORNER, CORNER, math.pi * 1.5, math.pi * 2, outer_w, *LINE_DARK)
    corner_arc(buf, x0 + CORNER, y0 + grid_w - CORNER, CORNER, math.pi * 0.5, math.pi, outer_w, *LINE_DARK)
    corner_arc(buf, x0 + grid_w - CORNER, y0 + grid_w - CORNER, CORNER, 0, math.pi * 0.5, outer_w, *LINE_DARK)

    # === 6. 真正的数独题目：经典入门级（30 个已知数字） ===
    #   5 3 . | . 7 . | . . .
    #   6 . . | 1 9 5 | . . .
    #   . 9 8 | . . . | . 6 .
    #   ------+-------+------
    #   8 . . | . 6 . | . . 3
    #   4 . . | 8 . 3 | . . 1
    #   7 . . | . 2 . | . . 6
    #   ------+-------+------
    #   . 6 . | . . . | 2 8 .
    #   . . . | 4 1 9 | . . 5
    #   . . . | . 8 . | . 7 9
    NUM_RGB = (15, 23, 42, 255)   # pure black-ish slate-900，更锐利清晰
    clues = [
        (0,0,'5'),(0,1,'3'),(0,4,'7'),
        (1,0,'6'),(1,3,'1'),(1,4,'9'),(1,5,'5'),
        (2,1,'9'),(2,2,'8'),(2,7,'6'),
        (3,0,'8'),(3,4,'6'),(3,8,'3'),
        (4,0,'4'),(4,3,'8'),(4,5,'3'),(4,8,'1'),
        (5,0,'7'),(5,4,'2'),(5,8,'6'),
        (6,1,'6'),(6,6,'2'),(6,7,'8'),
        (7,3,'4'),(7,4,'1'),(7,5,'9'),(7,8,'5'),
        (8,4,'8'),(8,7,'7'),(8,8,'9'),
    ]
    for r, c, ch in clues:
        cx = x0 + (c + 0.5) * CELL
        cy = y0 + (r + 0.5) * CELL
        draw_glyph(buf, ch, cx, cy, CELL, CELL, *NUM_RGB)

    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    write_png(bytes(buf), W, H, OUTPUT)
    sz = os.path.getsize(OUTPUT)
    print(f"✅ 已生成: {os.path.abspath(OUTPUT)} ({sz} bytes, {W}x{H})")

if __name__ == '__main__':
    main()
