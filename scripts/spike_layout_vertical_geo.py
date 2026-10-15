# -*- coding: utf-8 -*-
"""
1.4.6 P0-1 Phase 2 准入：竖排内核 layoutVertical 几何精确参数边界用例。
计划：docs/1.4.6开发计划_欠账收口与排版内核.md §2.1.2 / §A.4（算法先 Python 跑通再写 ArkTS）

与 spike_layout_vertical.py 的差异：spike 的 avail 为近似值（raw 偏移），
本脚本按 CopyPosterPreview 实际渲染盒几何重算 avail（1:1 与 spike 完全一致，3:4/9:16 更严）：
  T16 盒：.height(h() - fy(122) - f(209)) → availH = dh*778/900 - 209；宽 900-270-167=463
  T18 盒：.height(h() - fy(238) - fy(174)) → availH = dh*488/900；宽 900-212*2=476
  T20 无硬盒（spike 锁定软预算）：availH = dh - 250；宽 0（硬上限 3/4 列）
验收锚点（计划 §2.1.2 spike 结论）：1:1 视觉与现行分档一致区间 T16 ≤20字→48 / T18 ≤12字→70 / T20 ≤18字→82。

运行：python scripts/spike_layout_vertical_geo.py（全绿输出 ALL PASS，退出码 0）
"""

import sys
sys.path.insert(0, 'scripts')

from spike_layout_vertical import layout_vertical, vert_chars, NO_COL_START, NO_COL_END, MIN_FONT_PX

HAN = '春'
BRACKET_TEXT = '好好生活「慢慢相遇」用力去爱身边的人'
RATIOS = [('1:1', 900), ('3:4', 1200), ('9:16', 1600)]
BOUNDARY = [0, 1, 2, 4, 8, 12, 16, 18, 19, 20, 21, 24, 32, 33, 40, 45, 46, 50, 60, 61, 77, 78, 100, 120, 130]


def make_configs():
    cfgs = []
    for name, dh in RATIOS:
        cfgs.append(dict(
            tag='T16 SolarTerm %s GEO' % name, base_px=48, big=False, lh=1.30, pitch=1.63,
            avail_w=463, avail_h=dh * 778 / 900 - 209, hard_cap=99,
            anchor=(20, 48), anchor_note='1:1 ≤20字→48'))
        cfgs.append(dict(
            tag='T18 RedCouplet %s GEO' % name, base_px=70, big=False, lh=1.36, pitch=1.90,
            avail_w=476, avail_h=dh * 488 / 900, hard_cap=99,
            anchor=(12, 70), anchor_note='1:1 ≤12字→70'))
        base = 82 if dh == 900 else 92
        cap = 3 if dh == 900 else 4
        cfgs.append(dict(
            tag='T20 VerticalQuote %s GEO' % name, base_px=base, big=False, lh=1.32, pitch=1.80,
            avail_w=0, avail_h=dh - 250, hard_cap=cap,
            anchor=(18, base) if dh == 900 else None, anchor_note='1:1 ≤18字→82'))
    return cfgs


def check(cfg, text, res, problems):
    tag = cfg['tag']
    cols = res['cols']
    per_col = res['per_col']
    n = len(vert_chars(text))
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
            problems.append('%s: n=%d 截断但字号 %d 非最小字号' % (tag, n, res['font_px']))
        if res['truncated_chars'] != n - kept:
            problems.append('%s: n=%d truncated_chars 口径不一致' % (tag, n))
    # 列高不超盒：perCol * font * lh <= availH（几何精确核心校验）
    if per_col * res['font_px'] * cfg['lh'] > cfg['avail_h'] + 0.5:
        problems.append('%s: n=%d 列高溢出 %.1f>%.1f' % (
            tag, n, per_col * res['font_px'] * cfg['lh'], cfg['avail_h']))
    # 列宽不超盒：cols * font * pitch <= availW（availW>0 时）
    if cfg['avail_w'] > 0 and len(cols) * res['font_px'] * cfg['pitch'] > cfg['avail_w'] + 0.5:
        problems.append('%s: n=%d 列宽溢出 %.1f>%.1f' % (
            tag, n, len(cols) * res['font_px'] * cfg['pitch'], cfg['avail_w']))
    if per_col >= 2:
        for idx, col in enumerate(cols):
            if len(col) > per_col:
                problems.append('%s: n=%d 第 %d 列超长 %d>%d' % (tag, n, idx, len(col), per_col))
            if idx > 0 and col and col[0] in NO_COL_START:
                problems.append('%s: n=%d 第 %d 列以闭合标点开头 %r' % (tag, n, idx, col[0]))
            if idx < len(cols) - 1 and col and col[-1] in NO_COL_END:
                problems.append('%s: n=%d 第 %d 列以开放标点收尾 %r' % (tag, n, idx, col[-1]))
    if '「' in text and '」' in text:
        joined = ''.join(''.join(c) for c in cols)
        if '「' in joined and '」' in joined and joined.index('」') < joined.index('「'):
            problems.append('%s: 括号次序错乱 %r' % (tag, joined))


def run():
    problems = []
    all_max_drop = 0
    all_max_drop_at = ''
    for cfg in make_configs():
        prev_font = None
        print('=' * 96)
        print('%s | base=%d availH=%.1f availW=%s cap=%d' % (
            cfg['tag'], cfg['base_px'], cfg['avail_h'],
            cfg['avail_w'] if cfg['avail_w'] > 0 else '-', cfg['hard_cap']))
        print('  %4s %8s %7s %9s %6s' % ('n', '字号', '每列字', '列数/上限', '截断'))
        for n in BOUNDARY:
            res = layout_vertical(HAN * n, cfg['avail_h'], cfg['hard_cap'], cfg['base_px'],
                                  cfg['big'], cfg['lh'], cfg['avail_w'], cfg['pitch'])
            check(cfg, HAN * n, res, problems)
            print('  %4d %8d %7d %5d/%-4d %6s' % (
                n, res['font_px'], res['per_col'], res['n_cols'], cfg['hard_cap'],
                '省%d字' % res['truncated_chars'] if res['truncated'] else '-'))
        for n in range(1, 131):
            res = layout_vertical(HAN * n, cfg['avail_h'], cfg['hard_cap'], cfg['base_px'],
                                  cfg['big'], cfg['lh'], cfg['avail_w'], cfg['pitch'])
            check(cfg, HAN * n, res, problems)
            if prev_font is not None:
                if res['font_px'] > prev_font:
                    problems.append('%s: n=%d 字号回升 %d→%d' % (cfg['tag'], n, prev_font, res['font_px']))
                drop = prev_font - res['font_px']
                if drop > all_max_drop:
                    all_max_drop = drop
                    all_max_drop_at = '%s n=%d' % (cfg['tag'], n)
            prev_font = res['font_px']
        # 锚点：1:1 视觉一致区间
        if cfg['anchor'] is not None:
            n_anchor, font_anchor = cfg['anchor']
            for n in range(1, n_anchor + 1):
                res = layout_vertical(HAN * n, cfg['avail_h'], cfg['hard_cap'], cfg['base_px'],
                                      cfg['big'], cfg['lh'], cfg['avail_w'], cfg['pitch'])
                if res['font_px'] != font_anchor:
                    problems.append('%s: 锚点破坏 n=%d 字号 %d 应为 %d（%s）' % (
                        cfg['tag'], n, res['font_px'], font_anchor, cfg['anchor_note']))
        # 括号/混合文本专项
        for n in (6, 13, 25, 41, 62, 90):
            text = (BRACKET_TEXT * 12)[:n]
            res = layout_vertical(text, cfg['avail_h'], cfg['hard_cap'], cfg['base_px'],
                                  cfg['big'], cfg['lh'], cfg['avail_w'], cfg['pitch'])
            check(cfg, text, res, problems)
        prev_font = None
    print('=' * 96)
    print('相邻字数字号最大跌落：%dpx（%s）' % (all_max_drop, all_max_drop_at))
    if problems:
        print('FAIL %d 项：' % len(problems))
        for p in problems[:40]:
            print('  - %s' % p)
        sys.exit(1)
    print('ALL PASS')


if __name__ == '__main__':
    run()
