# -*- coding: utf-8 -*-
"""Print raw subtree of nodes whose bounds intersect a y-band (default chip row)."""
import json
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

def main():
    path = sys.argv[1]
    y0 = int(sys.argv[2]) if len(sys.argv) > 2 else 1380
    y1 = int(sys.argv[3]) if len(sys.argv) > 3 else 1520
    with open(path, encoding='utf-8-sig') as f:
        txt = f.read()
    start = txt.find('[')
    end = txt.rfind(']')
    data = json.loads(txt[start:end + 1])

    def walk(n, depth):
        b = n.get('bounds')
        hit = b and not (b[3] < y0 or b[1] > y1)
        if hit:
            print('  ' * depth + '%s id=%s text=%r bounds=%s clickable=%s' % (
                n.get('type'), n.get('id'), n.get('text') or '', b, n.get('clickable')))
        for c in n.get('children') or []:
            walk(c, depth + 1)

    for r in data:
        walk(r, 0)

if __name__ == '__main__':
    main()
