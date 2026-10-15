# -*- coding: utf-8 -*-
"""
1.4.6 P0-1 Phase 0 spike：竖排排版内核 layoutVertical 算法选型
计划：docs/1.4.6开发计划_欠账收口与排版内核.md §2.1.2 / §7 Phase 0
运行：python scripts/spike_layout_vertical.py（全绿输出 ALL PASS，退出码 0）

待锁定结论：
  1. 字号连续收缩（-1px 步进、容量驱动），不套用横排 startFont 曲线——竖排列数即预算，无需曲线预缩；
  2. 行高比 lh / 列距比 pitch 为参数（现行：T16 1.30/1.63、T18 1.36/1.90、T20 1.32/1.80）；
  3. 列首避让 NO_COL_START（同横排 NO_LINE_START）+ 列尾避让 NO_COL_END（竖排「」不断词验收项）；
  4. 截断仅在 MIN_FONT_PX=20 下发生，报 truncatedChars，提示复用 poster_truncated_hint（替代旧 '…' 截断）。
"""

import sys

MIN_FONT_PX = 20
NO_COL_START = '，。、！？；：…—·）】》」』〉%,.!?;:)]}'
NO_COL_END = '「『（【《〈(['


def vert_chars(text):
    """与 CopyPosterPreview.vertChars 同口径：去空白逐字拆分"""
    return [c for c in text if not c.isspace()]


def simulate_columns(chars, per_col, max_cols):
    """按阅读序切列（首列在前，渲染时反转成右起）；超列预算返回 None。
    列首避让：下一字符是闭合标点时不让它开新列（当前列提前 1 字收列）；
    列尾避让：当前列末字是开放标点时把它带到下一列（「」不断词）。"""
    if per_col < 1:
        per_col = 1
    cols = []
    cur = []
    i = 0
    n = len(chars)
    while i < n:
        cur.append(chars[i])
        i += 1
        if len(cur) >= per_col or i >= n:
            pulled = False
            if per_col >= 2 and i < n and len(cur) >= per_col and chars[i] in NO_COL_START:
                cur.pop()
                i -= 1
                pulled = True
            if not pulled and per_col >= 2 and i < n and cur and cur[-1] in NO_COL_END:
                cur.pop()
                i -= 1
            cols.append(cur)
            cur = []
            if len(cols) > max_cols:
                return None
    return cols


def cols_width_cap(font, avail_w, pitch, hard_cap):
    """列数上限 = min(硬上限, 可用宽/列距)；avail_w<=0 时只用硬上限"""
    cap = hard_cap
    if avail_w and avail_w > 0:
        cap = min(cap, max(1, int(avail_w // (font * pitch))))
    return max(1, cap)


def layout_vertical(text, avail_h, max_cols, base_px, big=False, lh=1.32, avail_w=0, pitch=1.7):
    """竖排内核（设计稿 px）：字号自 basePx 连续收缩至文本恰入 <=max_cols 列；
    最小字号仍放不下则截断并报 truncatedChars。"""
    res = {
        'font_px': base_px, 'cols': [], 'per_col': 0, 'n_cols': 0,
        'truncated': False, 'truncated_chars': 0, 'capacity': 0,
    }
    chars = vert_chars(text)
    n = len(chars)
    if n == 0:
        return res
    font = int(base_px * (1.15 if big else 1.0))
    while font >= MIN_FONT_PX:
        per_col = max(1, int(avail_h // (font * lh)))
        cap = cols_width_cap(font, avail_w, pitch, max_cols)
        cols = simulate_columns(chars, per_col, cap)
        if cols is not None:
            res.update(font_px=font, cols=cols, per_col=per_col,
                       n_cols=len(cols), capacity=per_col * cap)
            return res
        font -= 1
    font = MIN_FONT_PX
    per_col = max(1, int(avail_h // (font * lh)))
    cap = cols_width_cap(font, avail_w, pitch, max_cols)
    total = per_col * cap
    while total > 0:
        cols = simulate_columns(chars[:total], per_col, cap)
        if cols is not None:
            kept = sum(len(c) for c in cols)
            res.update(font_px=font, cols=cols, per_col=per_col, n_cols=len(cols),
                       truncated=True, truncated_chars=n - kept, capacity=total)
            return res
        total -= 1
    res.update(font_px=font, truncated=True, truncated_chars=n)
    return res


RATIOS = [('1:1', 900), ('3:4', 1200), ('9:16', 1600)]
BOUNDARY = [0, 1, 2, 4, 8, 12, 16, 20, 21, 24, 32, 33, 40, 45, 46, 50, 60, 61, 77, 78, 100, 120]
HAN = '春'
BRACKET_TEXT = '好好生活「慢慢相遇」用力去爱身边的人'
LATIN = 'A2'


def make_configs():
    cfgs = []
    for name, h_px in RATIOS:
        cfgs.append(dict(
            tag='T16 SolarTerm %s' % name, base_px=48, big=False, lh=1.30, pitch=1.63,
            avail_w=900 - 270 - 167, avail_h=h_px - 122 - 209, hard_cap=99,
            old=lambda n: 48 if n <= 20 else (38 if n <= 45 else 30),
            old_note='旧分档 <=20→48 / <=45→38 / else→30（与比例无关）'))
        cfgs.append(dict(
            tag='T18 RedCouplet %s' % name, base_px=70, big=False, lh=1.36, pitch=1.90,
            avail_w=900 - 212 * 2, avail_h=h_px - 238 - 174, hard_cap=99,
            old=lambda n: 70 if n <= 12 else (56 if n <= 24 else 44),
            old_note='旧分档 <=12→70 / <=24→56 / else→44（与比例无关）'))
        base = 82 if h_px == 900 else 92
        cap = 3 if h_px == 900 else 4
        cfgs.append(dict(
            tag='T20 VerticalQuote %s' % name, base_px=base, big=False, lh=1.32, pitch=1.80,
            avail_w=0, avail_h=h_px - 250, hard_cap=cap,
            old=lambda n, b=base: b,
            old_note='旧实现字号固定 %d（与字数无关），超 perCol×maxCols 直接截为 …' % base))
    return cfgs


def check_result(cfg, text, n, res, problems):
    tag = cfg['tag']
    cols = res['cols']
    per_col = res['per_col']
    if n == 0:
        if cols:
            problems.append('%s: n=0 应无列' % tag)
        return
    if not cols:
        problems.append('%s: n=%d 无列输出' % (tag, n))
        return
    kept = sum(len(c) for c in cols)
    if not res['truncated'] and kept != n:
        problems.append('%s: n=%d 未截断却丢字 kept=%d' % (tag, n, kept))
    if res['truncated']:
        if res['font_px'] != MIN_FONT_PX:
            problems.append('%s: n=%d 截断但字号 %d 不是最小字号' % (tag, n, res['font_px']))
        if res['truncated_chars'] != n - kept:
            problems.append('%s: n=%d truncated_chars 口径不一致' % (tag, n))
    if res['font_px'] < MIN_FONT_PX or res['font_px'] > int(cfg['base_px'] * 1.15):
        problems.append('%s: n=%d 字号越界 %d' % (tag, n, res['font_px']))
    if per_col >= 2:
        for idx, col in enumerate(cols):
            if len(col) > per_col:
                problems.append('%s: n=%d 第 %d 列超长 %d>%d' % (tag, n, idx, len(col), per_col))
            if idx > 0 and col and col[0] in NO_COL_START:
                problems.append('%s: n=%d 第 %d 列以闭合标点开头 %r' % (tag, n, idx, col[0]))
            if idx < len(cols) - 1 and col and col[-1] in NO_COL_END:
                problems.append('%s: n=%d 第 %d 列以开放标点收尾 %r' % (tag, n, idx, col[-1]))
    if '「' in text:
        joined = ''.join(cols[0]) if False else None


def run():
    problems = []
    all_max_drop = 0
    all_max_drop_at = ''
    for cfg in make_configs():
        prev_font = None
        print('=' * 100)
        print('%s | base=%d availH=%d availW=%s cap=%s' % (
            cfg['tag'], cfg['base_px'], cfg['avail_h'],
            cfg['avail_w'] if cfg['avail_w'] > 0 else '-', cfg['hard_cap']))
        print('  %s' % cfg['old_note'])
        print('  %4s %8s %8s %7s %9s %6s' % ('n', '旧字号', '新字号', '每列字', '列数/上限', '截断'))
        for n in BOUNDARY:
            text = HAN * n
            res = layout_vertical(text, cfg['avail_h'], cfg['hard_cap'], cfg['base_px'],
                                  cfg['big'], cfg['lh'], cfg['avail_w'], cfg['pitch'])
            check_result(cfg, text, n, res, problems)
            print('  %4d %8d %8d %7d %5d/%-4d %6s' % (
                n, cfg['old'](n), res['font_px'], res['per_col'],
                res['n_cols'], cols_width_cap(res['font_px'], cfg['avail_w'], cfg['pitch'], cfg['hard_cap']),
                '省%d字' % res['truncated_chars'] if res['truncated'] else '-'))
        for n in range(1, 131):
            text = HAN * n
            res = layout_vertical(text, cfg['avail_h'], cfg['hard_cap'], cfg['base_px'],
                                  cfg['big'], cfg['lh'], cfg['avail_w'], cfg['pitch'])
            check_result(cfg, text, n, res, problems)
            if prev_font is not None:
                if res['font_px'] > prev_font:
                    problems.append('%s: n=%d 字号回升 %d→%d' % (cfg['tag'], n, prev_font, res['font_px']))
                drop = prev_font - res['font_px']
                if drop > all_max_drop:
                    all_max_drop = drop
                    all_max_drop_at = '%s n=%d' % (cfg['tag'], n)
                if drop > max(8, int(prev_font * 0.2)):
                    problems.append('%s: n=%d 字号骤降 %d→%d' % (cfg['tag'], n, prev_font, res['font_px']))
            prev_font = res['font_px']
        # 括号/拉丁/混合文本专项（含截断区间）
        for n in (6, 13, 25, 41, 62, 90):
            text = (BRACKET_TEXT * 12)[:n]
            res = layout_vertical(text, cfg['avail_h'], cfg['hard_cap'], cfg['base_px'],
                                  cfg['big'], cfg['lh'], cfg['avail_w'], cfg['pitch'])
            check_result(cfg, text, len(vert_chars(text)), res, problems)
            joined = ''.join(''.join(c) for c in res['cols'])
            if '「' in joined and '」' in joined and joined.index('」') < joined.index('「'):
                problems.append('%s: 括号次序错乱 %r' % (cfg['tag'], joined))
        for n in (5, 20, 60):
            text = (LATIN * 40)[:n]
            res = layout_vertical(text, cfg['avail_h'], cfg['hard_cap'], cfg['base_px'],
                                  cfg['big'], cfg['lh'], cfg['avail_w'], cfg['pitch'])
            check_result(cfg, text, len(vert_chars(text)), res, problems)
        prev_font = None
    print('=' * 100)
    print('相邻字数字号最大跌落：%dpx（%s）' % (all_max_drop, all_max_drop_at))
    if problems:
        print('FAIL %d 项：' % len(problems))
        for p in problems[:40]:
            print('  - %s' % p)
        sys.exit(1)
    print('ALL PASS')


if __name__ == '__main__':
    run()
