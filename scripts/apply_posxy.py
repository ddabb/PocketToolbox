# -*- coding: utf-8 -*-
"""P0-1 Phase 1: .position 71 处收敛 posX/posY（1.4.6 计划 §2.1.1）。

规则（posX==f、posY==fy，数值恒等）：
- x 实参 this.f(...)  -> this.posX(...)   纯改名（含 previewWidth - f(...)、f(800)-f(22) 等）
- y 实参 this.fy(...) -> this.posY(...)   纯改名
- 主画布 y 用 f 的站点（Y_BASIS_FIX）: this.f(...) -> this.posY(...)  3:4/9:16 基准修正
- 宽度缩放子盒内部 y 保留 f()（T9 票根 1572-1579、霓虹灯箱 1101-1107 父盒为宽基准）
- y 实参中的元素尺寸补偿项（-f(14)/f(13.5)/f(54) 等）保留 f()
- T16 底部节气歌 2870（h()-f(102)）与竖排列底部预留 f(209) 耦合，Phase 2 重排一并修，本期保持 f
- T18 金框 3163/3170：y 基准修正需与 .height(h()-f(N)*2) 同步（HEIGHT_FIX），否则 3:4 上下边距不对称

用法：py -3 scripts/apply_posxy.py [--apply]  （默认 dry-run 只打印 diff）
"""
import re
import sys

PATH = r'entry/src/main/ets/components/cover/CopyPosterPreview.ets'
APPLY = '--apply' in sys.argv

# 行号 = 原行号 + 10（posX/posY 方法定义已先行插入 :52-62，编辑工具写入覆盖了首次 apply）
Y_BASIS_FIX = {378, 450, 457, 502, 1098, 1943, 1954, 2326, 2646, 2753, 2760,
               3076, 3173, 3180, 3296}

# T13 山丘：f(119) 是底部设计边距（→posY），f(177)/f(154) 是 Path 自身高度（尺寸，保持 f）
SPECIAL_FIX = {
    2990: ('.position({ x: -this.f(48), y: this.h() - this.f(119) - this.f(177) })',
           '.position({ x: -this.posX(48), y: this.h() - this.posY(119) - this.f(177) })'),
    2997: ('.position({ x: this.previewWidth - this.f(466), y: this.h() - this.f(119) - this.f(154) })',
           '.position({ x: this.previewWidth - this.posX(466), y: this.h() - this.posY(119) - this.f(154) })'),
}

HEIGHT_FIX = {
    3171: ('.height(this.h() - this.f(32) * 2)', '.height(this.h() - this.posY(32) * 2)'),
    3178: ('.height(this.h() - this.f(43) * 2)', '.height(this.h() - this.posY(43) * 2)'),
}

CORNER_WRAP_FIX = {
    3188: ('this.CoupletCorner(this.previewWidth - this.f(55) - this.f(54), this.h() - this.fy(55) - this.f(54),',
           'this.CoupletCorner(this.previewWidth - this.posX(55) - this.posX(54), this.h() - this.posY(55) - this.f(54),'),
}

POS_RE = re.compile(r'^(.*?\.position\(\{ x: )(.*?)(, y: )(.*?)( \}\)\s*)$')
COIN_RE = re.compile(r'^(.*?this\.CoupletCoin\()(.*?)(, )(.*?)(\)\s*)$')
CORNER_RE = re.compile(r'^(.*?this\.CoupletCorner\()(.*?)(, )(.*?)(, Alignment\.[A-Za-z]+\))(\s*)$')


def fix_x(x):
    return x.replace('this.f(', 'this.posX(')


def fix_y(y, basis):
    y = y.replace('this.fy(', 'this.posY(')
    if basis:
        y = y.replace('this.f(', 'this.posY(')
    return y


def main():
    with open(PATH, encoding='utf-8', newline='') as fp:
        text = fp.read()
    lines = text.split('\n')

    changed = []
    pos_count = 0
    coin_count = 0
    corner_count = 0

    for i, line in enumerate(lines, start=1):
        orig = line

        if i in SPECIAL_FIX:
            old, new = SPECIAL_FIX[i]
            assert old in line, 'L%d special anchor missing: %s' % (i, line)
            line = line.replace(old, new)

        if i in HEIGHT_FIX:
            old, new = HEIGHT_FIX[i]
            assert old in line, 'L%d height anchor missing: %s' % (i, line)
            line = line.replace(old, new)

        if i in CORNER_WRAP_FIX:
            old, new = CORNER_WRAP_FIX[i]
            assert old in line, 'L%d corner-wrap anchor missing: %s' % (i, line)
            line = line.replace(old, new)
            corner_count += 1

        m = POS_RE.match(line)
        if m:
            pos_count += 1
            basis = i in Y_BASIS_FIX
            line = (m.group(1) + fix_x(m.group(2)) + m.group(3)
                    + fix_y(m.group(4), basis) + m.group(5))

        m = COIN_RE.match(line)
        if m:
            coin_count += 1
            line = (m.group(1) + fix_x(m.group(2)) + m.group(3)
                    + fix_y(m.group(4), False) + m.group(5))

        m = CORNER_RE.match(line)
        if m:
            corner_count += 1
            line = (m.group(1) + fix_x(m.group(2)) + m.group(3)
                    + fix_y(m.group(4), False) + m.group(5) + m.group(6))

        if line != orig:
            changed.append((i, orig.strip(), line.strip()))
            lines[i - 1] = line  # 关键：转换结果写回列表，否则 join(lines) 写回的是原内容

    assert pos_count == 71, 'expected 71 .position lines, saw %d' % pos_count
    assert coin_count == 7, 'expected 7 CoupletCoin callers, saw %d' % coin_count
    assert corner_count == 4, 'expected 4 CoupletCorner callers, saw %d' % corner_count

    print('.position lines: %d | CoupletCoin: %d | CoupletCorner: %d | changed: %d'
          % (pos_count, coin_count, corner_count, len(changed)))
    for i, old, new in changed:
        print('\nL%d\n  - %s\n  + %s' % (i, old, new))

    if APPLY:
        with open(PATH, 'w', encoding='utf-8', newline='') as fp:
            fp.write('\n'.join(lines))
        print('\nAPPLIED')
    else:
        print('\nDRY RUN (pass --apply to write)')


if __name__ == '__main__':
    main()
