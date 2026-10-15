# -*- coding: utf-8 -*-
"""Walk devecocli ui layout JSON: find nodes by text, print id/bounds/clickable path."""
import json
import sys

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

def load(path):
    with open(path, 'r', encoding='utf-8-sig') as f:
        txt = f.read()
    # CLI may append non-JSON banners; trim to outermost JSON array
    start = txt.find('[')
    end = txt.rfind(']')
    if start < 0 or end < 0:
        raise SystemExit('no JSON array found')
    return json.loads(txt[start:end + 1])

def walk(node, out, parents):
    n = dict(node)
    n['_parents'] = list(parents)
    out.append(n)
    for c in node.get('children', []) or []:
        walk(c, out, n['_parents'] + [n])

def main():
    path = sys.argv[1]
    want = sys.argv[2] if len(sys.argv) > 2 else None
    roots = load(path)
    nodes = []
    for r in roots:
        walk(r, nodes, [])
    for n in nodes:
        t = n.get('text') or ''
        if want is None or want in t:
            clickable = None
            for p in reversed(n['_parents']):
                if p.get('clickable'):
                    clickable = p
                    break
            print(json.dumps({
                'text': t, 'id': n.get('id'), 'type': n.get('type'),
                'bounds': n.get('bounds'), 'clickable': n.get('clickable'),
                'clickable_ancestor': ({
                    'id': clickable.get('id'), 'type': clickable.get('type'),
                    'bounds': clickable.get('bounds')} if clickable else None)},
                ensure_ascii=False))

if __name__ == '__main__':
    main()
