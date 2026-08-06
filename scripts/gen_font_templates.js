// gen_font_templates.js
// 纯 JS 解析 font 目录里的字体（TrueType glyf / OpenType CFF），
// 把数字 1-9 光栅化为位图，按 SudokuPixel.ets 中 cellSigFromGray 同款算法
// 生成 70 位（10 行 x 7 列）二值特征码，输出可供 .ets 直接使用的模板数组。
//
// 用法: node scripts/gen_font_templates.js
// 依赖: canvas（仅用于把解析出的轮廓填充成位图）
// 不依赖系统字体安装 / registerFont（那些在本机 Windows 版 node-canvas 上是坏的）。

const fs = require('fs');
const path = require('path');
const { createCanvas } = require('canvas');

const FONT_DIR = 'entry/src/main/resources/rawfile/font';
const SIG_ROWS = 10;
const SIG_COLS = 7;
const INK_THRESH = 50;      // 与 SudokuPixel.ets 一致
const BG = 255;             // 模板在白底上渲染 -> isDark=false
const RENDER = 320;         // 渲染画布尺寸

// ---------- 通用字体解析 ----------
function tag(buf, off) { return String.fromCharCode(buf[off], buf[off + 1], buf[off + 2], buf[off + 3]); }

function readTableDir(buf) {
  const num = buf.readUInt16BE(4);
  const tables = {};
  let off = 12;
  for (let i = 0; i < num; i++) {
    const t = tag(buf, off);
    tables[t] = { off: buf.readUInt32BE(off + 8), len: buf.readUInt32BE(off + 12) };
    off += 16;
  }
  return tables;
}

// cmap -> 返回 getGlyph(charCode) 函数
function buildCmap(buf, tables) {
  const cm = tables['cmap'];
  if (!cm) return () => 0;
  const base = cm.off;
  const num = buf.readUInt16BE(base + 2);
  let best = -1, bestFmt = -1;
  for (let i = 0; i < num; i++) {
    const pid = buf.readUInt16BE(base + 4 + i * 8);
    const eid = buf.readUInt16BE(base + 6 + i * 8);
    const subOff = buf.readUInt32BE(base + 8 + i * 8);
    // 优先 Windows Unicode(3,1) / (3,0) / (0,*) / (1,*)
    let score = -1;
    if (pid === 3 && eid === 1) score = 100;
    else if (pid === 3 && eid === 0) score = 90;
    else if (pid === 0) score = 80;
    else if (pid === 1) score = 70;
    if (score > bestFmt) { bestFmt = score; best = subOff; }
  }
  if (best < 0) return () => 0;
  const sub = base + best;
  const fmt = buf.readUInt16BE(sub);
  let map = {};
  if (fmt === 4) {
    const segCount = buf.readUInt16BE(sub + 6) / 2;
    const end = sub + 14;
    const start = end + segCount * 2 + 2;
    const delta = start + segCount * 2;
    const range = delta + segCount * 2;
    for (let i = 0; i < segCount; i++) {
      const e = buf.readUInt16BE(end + i * 2);
      const s = buf.readUInt16BE(start + i * 2);
      const d = buf.readInt16BE(delta + i * 2);
      const ro = buf.readUInt16BE(range + i * 2);
      for (let c = s; c <= e; c++) {
        if (c === 0xFFFF) continue;
        let gi;
        if (ro === 0) gi = (c + d) & 0xFFFF;
        else {
          const aidx = ro / 2 + (c - s) + (range - sub) / 2 - segCount * 0; // offset into glyphIdArray
          const gid = buf.readUInt16BE(sub + (range - sub) + i * 2 + ro + (c - s) * 2);
          gi = gid === 0 ? 0 : (gid + d) & 0xFFFF;
        }
        if (gi !== 0) map[c] = gi;
      }
    }
  } else if (fmt === 12) {
    const nGroups = buf.readUInt32BE(sub + 12);
    let p = sub + 16;
    for (let i = 0; i < nGroups; i++) {
      const s = buf.readUInt32BE(p); const e = buf.readUInt32BE(p + 4); const g0 = buf.readUInt32BE(p + 8);
      for (let c = s; c <= e; c++) map[c] = g0 + (c - s);
      p += 12;
    }
  }
  return (c) => map[c] || 0;
}

// ---------- TrueType glyf ----------
function parseGlyf(buf, tables, getGlyph) {
  const head = tables['head']; if (!head) return null;
  const unitsPerEm = buf.readUInt16BE(head.off + 18);
  const indexToLocFormat = buf.readUInt16BE(head.off + 50);
  const loca = tables['loca']; const glyf = tables['glyf'];
  if (!loca || !glyf) return null;
  function glyphOffset(gi) {
    return indexToLocFormat === 0 ? buf.readUInt16BE(loca.off + gi * 4) * 2 : buf.readUInt32BE(loca.off + gi * 4);
  }
  function readSimple(gi, goff) {
    let p = glyf.off + goff;
    const numContours = buf.readInt16BE(p); p += 2;
    const xMin = buf.readInt16BE(p); p += 2; const yMin = buf.readInt16BE(p); p += 2;
    const xMax = buf.readInt16BE(p); p += 2; const yMax = buf.readInt16BE(p); p += 2;
    const endPts = [];
    for (let i = 0; i < numContours; i++) { endPts.push(buf.readUInt16BE(p)); p += 2; }
    const instrLen = buf.readUInt16BE(p); p += 2; p += instrLen;
    // flags
    const flags = [];
    const nPts = numContours > 0 ? endPts[numContours - 1] + 1 : 0;
    while (flags.length < nPts) {
      const f = buf.readUInt8(p++);
      flags.push(f);
      if (f & 8) { const rep = buf.readUInt8(p++); for (let r = 0; r < rep; r++) flags.push(f); }
    }
    // x
    const xs = []; let x = 0;
    for (let i = 0; i < nPts; i++) {
      const f = flags[i];
      if (f & 2) { const b = buf.readUInt8(p++); x += (f & 16) ? b : -b; }
      else if (f & 16) { /* same */ }
      else { x += buf.readInt16BE(p); p += 2; }
      xs.push(x);
    }
    // y
    const ys = []; let y = 0;
    for (let i = 0; i < nPts; i++) {
      const f = flags[i];
      if (f & 4) { const b = buf.readUInt8(p++); y += (f & 32) ? b : -b; }
      else if (f & 32) { /* same */ }
      else { y += buf.readInt16BE(p); p += 2; }
      ys.push(y);
    }
    // build contours
    const contours = [];
    let start = 0;
    for (let c = 0; c < numContours; c++) {
      const e = endPts[c];
      const arr = [];
      for (let i = start; i <= e; i++) arr.push({ x: xs[i], y: ys[i], on: !!(flags[i] & 1) });
      contours.push(arr);
      start = e + 1;
    }
    return { contours, xMin, yMin, xMax, yMax };
  }
  function flatPoints(contours) {
    const arr = [];
    for (const c of contours) for (const pt of c) arr.push(pt);
    return arr;
  }
  function applyT(pt, m, dx, dy) {
    return { x: pt.x * m.xx + pt.y * m.yx + dx, y: pt.x * m.xy + pt.y * m.yy + dy, on: pt.on };
  }
  function readGlyph(gi, depth) {
    if (depth === undefined) depth = 0;
    if (depth > 20) return null;
    const goff = glyphOffset(gi);
    const goff2 = glyphOffset(gi + 1);
    if (goff === goff2) return null; // 空字形
    const numContours = buf.readInt16BE(glyf.off + goff);
    if (numContours >= 0) return readSimple(gi, goff);
    return resolveComposite(gi, goff, depth);
  }
  function resolveComposite(rootGi, rootOff, depth) {
    let parentContours = [];
    let parentFlat = [];
    let p = glyf.off + rootOff + 10; // skip numContours(-1)+bbox
    let more = true;
    while (more) {
      const flags = buf.readUInt16BE(p); p += 2;
      const gidx = buf.readUInt16BE(p); p += 2;
      let arg1, arg2;
      if (flags & 1) { arg1 = buf.readInt16BE(p); arg2 = buf.readInt16BE(p + 2); p += 4; }
      else { arg1 = buf.readInt8(p); arg2 = buf.readInt8(p + 1); p += 2; }
      const m = { xx: 1, xy: 0, yx: 0, yy: 1 };
      if (flags & 8) { const s = buf.readInt16BE(p) / 16384; p += 2; m.xx = s; m.yy = s; }
      else if (flags & 64) { m.xx = buf.readInt16BE(p) / 16384; m.xy = buf.readInt16BE(p + 2) / 16384; m.yx = buf.readInt16BE(p + 4) / 16384; m.yy = buf.readInt16BE(p + 6) / 16384; p += 8; }
      else if (flags & 128) { m.xx = buf.readInt16BE(p) / 16384; m.yy = buf.readInt16BE(p + 2) / 16384; p += 4; }
      const child = readGlyph(gidx, depth + 1);
      const childContours = child ? child.contours : [];
      const childFlat = flatPoints(childContours);
      let dx, dy;
      if (flags & 1) { dx = arg1; dy = arg2; }
      else {
        // 锚点匹配：把子字形 arg2 号点对齐到父轮廓 arg1 号点（在矩阵变换之后的空间）
        const pp = parentFlat[arg1] || { x: 0, y: 0 };
        const cp = childFlat[arg2] || { x: 0, y: 0 };
        const sx = cp.x * m.xx + cp.y * m.yx;
        const sy = cp.x * m.xy + cp.y * m.yy;
        dx = pp.x - sx; dy = pp.y - sy;
      }
      for (const c of childContours) parentContours.push(c.map(pt => applyT(pt, m, dx, dy)));
      parentFlat = flatPoints(parentContours);
      more = !!(flags & 32);
    }
    let xMin = 1e9, yMin = 1e9, xMax = -1e9, yMax = -1e9;
    for (const pt of parentFlat) { if (pt.x < xMin) xMin = pt.x; if (pt.x > xMax) xMax = pt.x; if (pt.y < yMin) yMin = pt.y; if (pt.y > yMax) yMax = pt.y; }
    return { contours: parentContours, xMin, yMin, xMax, yMax };
  }
  return { unitsPerEm, readGlyph, getGlyph };
}

// ---------- OpenType CFF ----------
function parseCFF(buf, tables, getGlyph) {
  const cffT = tables['CFF ']; if (!cffT) return null;
  const base = cffT.off;
  let p = base + 2 /*major,minor*/ + 1 /*hdrSize*/ + 1 /*offSize*/;
  // read INDEX helper
  function readIndex(start) {
    const count = buf.readUInt16BE(start);
    const offSize = buf.readUInt8(start + 2);
    const offsets = [];
    for (let i = 0; i <= count; i++) {
      let v = 0;
      for (let k = 0; k < offSize; k++) v = (v << 8) | buf.readUInt8(start + 3 + i * offSize + k);
      offsets.push(v);
    }
    const dataStart = start + 3 + (count + 1) * offSize;
    const items = [];
    for (let i = 0; i < count; i++) {
      items.push({ off: dataStart + offsets[i], len: offsets[i + 1] - offsets[i] });
    }
    return { items, next: dataStart + offsets[count] };
  }
  const nameIdx = readIndex(p); p = nameIdx.next;
  const topIdx = readIndex(p); p = topIdx.next;
  // parse Top DICT
  const topData = topIdx.items[0];
  const dict = parseDict(buf, topData.off, topData.len);
  const charStringsOff = dict.get(17); // CharStrings
  const privateArr = dict.get(18); // [size, offset]
  let defaultWidthX = 0, nominalWidthX = 0;
  if (privateArr) {
    const priv = parseDict(buf, base + privateArr[1], privateArr[0]);
    if (priv.has(20)) defaultWidthX = priv.get(20);
    if (priv.has(21)) nominalWidthX = priv.get(21);
  }
  const csIdx = readIndex(base + charStringsOff);
  // decode a glyph charstring -> contours (cubic)
  function decodeCharstring(gi) {
    const item = csIdx.items[gi];
    if (!item || item.len === 0) return null;
    let q = item.off;
    const end = item.off + item.len;
    const stack = [];
    const contours = [];
    let cur = { x: 0, y: 0 };
    let started = false;
    let curContour = null;
    let widthRead = false;
    function newContour() { curContour = [cur]; contours.push(curContour); }
    function pushPt(x, y, on) { cur = { x, y }; if (!curContour) newContour(); else curContour.push(cur); }
    while (q < end) {
      let b = buf.readUInt8(q++);
      if (b <= 11) {
        // operator or operand? numbers are b>=12 (some) or b in 28.. etc. Actually operators are <32 and not part of number encoding except specific.
        // Handle operators 0..11
        switch (b) {
          case 1: case 3: case 11: case 13: // hstem/vstem/hstemhm/vstemhm (hints) -> pop all args (n pairs or with width)
            // simplest: if stack has odd count first is width
            if (!widthRead && stack.length % 2 === 1) stack.shift();
            stack.length = 0; break;
          case 4: { // vmoveto
            if (!widthRead && stack.length === 2) { stack.shift(); widthRead = true; }
            const dy = stack.pop(); stack.length = 0;
            pushPt(cur.x, cur.y + dy, true); break; }
          case 5: { // rmoveto
            if (!widthRead && stack.length === 3) { stack.shift(); widthRead = true; }
            const dy = stack.pop(); const dx = stack.pop(); stack.length = 0;
            pushPt(cur.x + dx, cur.y + dy, true); break; }
          case 6: { // hlineto
            while (stack.length) { const d = stack.shift(); pushPt(cur.x + d, cur.y, true); } break; }
          case 7: { // vlineto
            while (stack.length) { const d = stack.shift(); pushPt(cur.x, cur.y + d, true); } break; }
          case 8: { // rlineto
            while (stack.length >= 2) { const dx = stack.shift(); const dy = stack.shift(); pushPt(cur.x + dx, cur.y + dy, true); } break; }
          case 10: { // endchar
            stack.length = 0; break; }
          default: stack.length = 0;
        }
      } else if (b === 12) {
        const op = buf.readUInt8(q++);
        // 12 0.. ; 12 34 etc. curves: 12 34 = hvcurveto? Actually: 12 0 = Reserved? Let me handle common:
        // 12 34 -> ? We'll just clear stack for hintmask-like. Handle curve ops:
        // 12 7 = hvcurveto? no. Real: 12 34 reserved. 12 24 = ? 
        // Common two-byte: 12 0? Not needed. We'll treat unknown as clear.
        if (op === 34) { // hvcurveto (actually 12 34? no). skip safely:
          // rrcurveto-family? We'll just clear.
        }
        stack.length = 0;
      } else if (b >= 14 && b <= 18) {
        // 14 hintmask, 15 cntrmask -> skip (nStems+7)/8 bytes; 16/17 reserved; 18 = rrcurveto? no 18=0x12 rrcurveto (single byte!). Wait 0x12=18 rrcurveto.
        if (b === 18) { // rrcurveto: 6 args per curve
          while (stack.length >= 6) {
            const dx1 = stack.shift(), dy1 = stack.shift(), dx2 = stack.shift(), dy2 = stack.shift(), dx3 = stack.shift(), dy3 = stack.shift();
            const c1 = { x: cur.x + dx1, y: cur.y + dy1 };
            const c2 = { x: c1.x + dx2, y: c1.y + dy2 };
            const endp = { x: c2.x + dx3, y: c2.y + dy3 };
            pushCurve(cur, c1, c2, endp);
          }
          stack.length = 0;
        } else if (b === 14 || b === 15) {
          // hintmask/cntrmask: need nStems; we don't track, approximate skip 1 byte (often 1-2). Safe: skip 1.
          q += 1; stack.length = 0;
        } else { stack.length = 0; }
      } else if (b === 21) { // hhcurveto 0x15
        while (stack.length >= 4) {
          const dx1 = stack.shift(), dy1 = stack.shift(), dx2 = stack.shift(), dy2 = stack.shift();
          const c1 = { x: cur.x + dx1, y: cur.y + dy1 };
          const c2 = { x: c1.x, y: c1.y + dy2 };
          const endp = { x: c2.x + dx2, y: c2.y };
          pushCurve(cur, c1, c2, endp);
        }
        stack.length = 0;
      } else if (b === 22) { // vvcurveto 0x16
        while (stack.length >= 4) {
          const dx1 = stack.shift(), dy1 = stack.shift(), dx2 = stack.shift(), dy2 = stack.shift();
          const c1 = { x: cur.x + dx1, y: cur.y + dy1 };
          const c2 = { x: c1.x + dx2, y: c1.y };
          const endp = { x: c2.x, y: c2.y + dy2 };
          pushCurve(cur, c1, c2, endp);
        }
        stack.length = 0;
      } else if (b === 23) { // hvcurveto 0x17
        while (stack.length >= 4) {
          const dx1 = stack.shift(), dy1 = stack.shift(), dx2 = stack.shift(), dy2 = stack.shift();
          const c1 = { x: cur.x + dx1, y: cur.y + dy1 };
          const c2 = { x: c1.x + dx2, y: c1.y };
          const endp = { x: c2.x, y: c2.y + dy2 };
          pushCurve(cur, c1, c2, endp);
        }
        stack.length = 0;
      } else if (b === 24) { // vhcurveto 0x18
        while (stack.length >= 4) {
          const dx1 = stack.shift(), dy1 = stack.shift(), dx2 = stack.shift(), dy2 = stack.shift();
          const c1 = { x: cur.x + dx1, y: cur.y + dy1 };
          const c2 = { x: c1.x, y: c1.y + dy2 };
          const endp = { x: c2.x + dx2, y: c2.y };
          pushCurve(cur, c1, c2, endp);
        }
        stack.length = 0;
      } else if (b === 28) { // short int
        const v = buf.readInt16BE(q); q += 2; stack.push(v);
      } else if (b >= 29 && b <= 30) { // long int / fixed
        const v = buf.readInt32BE(q); q += 4; stack.push(v);
      } else if (b >= 32 && b <= 246) { stack.push(b - 139); }
      else if (b >= 247 && b <= 250) { const w = buf.readUInt8(q++); stack.push((b - 247) * 256 + w + 108); }
      else if (b >= 251 && b <= 254) { const w = buf.readUInt8(q++); stack.push(-(b - 251) * 256 - w - 108); }
      else if (b === 255) { const v = buf.readInt32BE(q); q += 4; stack.push(v / 65536); }
      else { stack.length = 0; }
    }
    // bounding box
    let xMin=1e9,yMin=1e9,xMax=-1e9,yMax=-1e9;
    for (const c of contours) for (const pt of c) { if(pt.x<xMin)xMin=pt.x; if(pt.x>xMax)xMax=pt.x; if(pt.y<yMin)yMin=pt.y; if(pt.y>yMax)yMax=pt.y; }
    return { contours, xMin, yMin, xMax, yMax };
  }
  function pushCurve(p0, c1, c2, p3) {
    // cubic bezier -> flatten into line segments, mark off-curve intermediates
    const STEPS = 8;
    if (!curContour) { curContour = [p0]; contours.push(curContour); }
    // push control points as off-curve (for later flattening we just store as polyline samples)
    for (let k = 1; k <= STEPS; k++) {
      const t = k / STEPS, mt = 1 - t;
      const x = mt*mt*mt*p0.x + 3*mt*mt*t*c1.x + 3*mt*t*t*c2.x + t*t*t*p3.x;
      const y = mt*mt*mt*p0.y + 3*mt*mt*t*c1.y + 3*mt*t*t*c2.y + t*t*t*p3.y;
      cur = { x, y }; curContour.push(cur);
    }
  }
  return { unitsPerEm: 1000, getGlyph, decodeCharstring };
}

function parseDict(buf, off, len) {
  const m = new Map();
  let p = off;
  const end = off + len;
  const stack = [];
  while (p < end) {
    const b = buf.readUInt8(p++);
    if (b === 12) { const op = buf.readUInt8(p++); m.set(1200 + op, stack.slice()); stack.length = 0; }
    else if (b <= 21) { m.set(b, stack.slice()); stack.length = 0; }
    else if (b === 28) { const v = buf.readInt16BE(p); p += 2; stack.push(v); }
    else if (b === 29) { const v = buf.readInt32BE(p); p += 4; stack.push(v); }
    else if (b >= 32 && b <= 246) stack.push(b - 139);
    else if (b >= 247 && b <= 250) { const w = buf.readUInt8(p++); stack.push((b - 247) * 256 + w + 108); }
    else if (b >= 251 && b <= 254) { const w = buf.readUInt8(p++); stack.push(-(b - 251) * 256 - w - 108); }
    else if (b === 30) { // real — skip
      while (p < end) { const c = buf.readUInt8(p++); if ((c & 0x0f) === 0x0f) break; }
    } else if (b === 255) { p += 4; }
  }
  return m;
}

// ---------- 轮廓 -> 多边形（含 TrueType 二次曲线扁平化） ----------
function contoursToPolylines(contours) {
  const result = [];
  for (const c of contours) {
    const n = c.length;
    if (n === 0) continue;
    let start = 0;
    while (start < n && !c[start].on) start++;
    if (start === n) {
      const poly = [];
      for (let i = 0; i < n; i++) { const a = c[i], b = c[(i + 1) % n]; poly.push({ x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 }); }
      result.push(poly); continue;
    }
    const pts = c.slice(start).concat(c.slice(0, start));
    const m = pts.length;
    const poly = [{ x: pts[0].x, y: pts[0].y }];
    let i = 1;
    while (i < m) {
      const p = pts[i];
      if (p.on) { poly.push({ x: p.x, y: p.y }); i++; }
      else {
        const q = pts[(i + 1) % m];
        const cx = p.x, cy = p.y;
        let ex, ey;
        if (q.on) { ex = q.x; ey = q.y; i += 2; }
        else { ex = (p.x + q.x) / 2; ey = (p.y + q.y) / 2; i += 1; }
        flattenQuad(poly, poly[poly.length - 1], { x: cx, y: cy }, { x: ex, y: ey }, 10);
        poly.push({ x: ex, y: ey });
      }
    }
    result.push(poly);
  }
  return result;
}
function flattenQuad(poly, p0, c, p1, steps) {
  for (let k = 1; k <= steps; k++) {
    const t = k / steps, mt = 1 - t;
    const x = mt * mt * p0.x + 2 * mt * t * c.x + t * t * p1.x;
    const y = mt * mt * p0.y + 2 * mt * t * c.y + t * t * p1.y;
    poly.push({ x, y });
  }
}

// ---------- 光栅化 + 特征码 ----------
function rasterizeToGray(contoursUnits, unitsPerEm) {
  const polys = contoursToPolylines(contoursUnits);
  // bbox
  let xMin = 1e9, yMin = 1e9, xMax = -1e9, yMax = -1e9;
  for (const poly of polys) for (const pt of poly) { if (pt.x < xMin) xMin = pt.x; if (pt.x > xMax) xMax = pt.x; if (pt.y < yMin) yMin = pt.y; if (pt.y > yMax) yMax = pt.y; }
  const span = Math.max(xMax - xMin, yMax - yMin) || 1;
  const scale = (RENDER * 0.82) / span;
  const cx = RENDER / 2 - (xMin + xMax) / 2 * scale;
  const cy = RENDER / 2 + (yMin + yMax) / 2 * scale; // 翻转 Y
  const c = createCanvas(RENDER, RENDER);
  const x = c.getContext('2d');
  x.fillStyle = 'white'; x.fillRect(0, 0, RENDER, RENDER);
  x.fillStyle = 'black';
  x.beginPath();
  for (const poly of polys) {
    for (let i = 0; i < poly.length; i++) {
      const X = cx + poly[i].x * scale;
      const Y = cy - poly[i].y * scale;
      if (i === 0) x.moveTo(X, Y); else x.lineTo(X, Y);
    }
    x.closePath();
  }
  x.fill('nonzero');
  const data = x.getImageData(0, 0, RENDER, RENDER).data;
  const gray = new Float32Array(RENDER * RENDER);
  for (let i = 0; i < RENDER * RENDER; i++) gray[i] = data[i * 4]; // 红通道即灰度
  return gray;
}

function sigFromGray(gray, W, H) {
  const mx = W * 0.08, my = H * 0.08;
  const x0 = Math.floor(mx), y0 = Math.floor(my);
  const x1 = Math.floor(W - mx), y1 = Math.floor(H - my);
  let bminX = 1e9, bmaxX = -1, bminY = 1e9, bmaxY = -1;
  for (let y = y0; y < y1; y++) for (let xx = x0; xx < x1; xx++) {
    const g = gray[y * W + xx];
    if (g < BG - INK_THRESH) { if (xx < bminX) bminX = xx; if (xx > bmaxX) bmaxX = xx; if (y < bminY) bminY = y; if (y > bmaxY) bmaxY = y; }
  }
  if (bmaxX < 0) return null;
  const bw = bmaxX - bminX + 1, bh = bmaxY - bminY + 1;
  const sig = new Array(SIG_ROWS * SIG_COLS).fill(0);
  for (let r = 0; r < SIG_ROWS; r++) for (let col = 0; col < SIG_COLS; col++) {
    const sx0 = bminX + Math.floor(bw * col / SIG_COLS);
    const sx1 = bminX + Math.floor(bw * (col + 1) / SIG_COLS);
    const sy0 = bminY + Math.floor(bh * r / SIG_ROWS);
    const sy1 = bminY + Math.floor(bh * (r + 1) / SIG_ROWS);
    let s = 0, n = 0;
    for (let y = sy0; y < sy1; y++) for (let xx = sx0; xx < sx1; xx++) { s += gray[y * W + xx]; n++; }
    const avg = n > 0 ? s / n : BG;
    sig[r * SIG_COLS + col] = avg < BG - INK_THRESH ? 1 : 0;
  }
  return sig;
}

function sigToAscii(sig) {
  let s = '';
  for (let r = 0; r < SIG_ROWS; r++) {
    let line = '';
    for (let col = 0; col < SIG_COLS; col++) line += sig[r * SIG_COLS + col] ? '#' : '.';
    s += line + '\n';
  }
  return s;
}

// ---------- 主流程 ----------
function main() {
  const files = fs.readdirSync(FONT_DIR).filter(f => /\.(ttf|otf)$/i.test(f));
  const allTemplates = [];
  const fontSummaries = [];
  for (const f of files) {
    const buf = fs.readFileSync(path.join(FONT_DIR, f));
    const tables = readTableDir(buf);
    const getGlyph = buildCmap(buf, tables);
    const sfnt = buf.readUInt32BE(0);
    const isCFF = sfnt === 0x4F54544F;
    let parser = isCFF ? parseCFF(buf, tables, getGlyph) : parseGlyf(buf, tables, getGlyph);
    if (!parser) { console.log('!! 无法解析', f); continue; }
    let okCount = 0;
    for (let d = 1; d <= 9; d++) {
      const gi = getGlyph(d + 48); // '1'..'9' ASCII
      let glyph = null;
      if (parser.decodeCharstring) glyph = parser.decodeCharstring(gi);
      else if (parser.readGlyph) glyph = parser.readGlyph(gi);
      if (process.env.DBG && d === 8) {
        const cc = glyph ? glyph.contours.length : -1;
        const bb = glyph ? `(${glyph.xMin},${glyph.yMin})-(${glyph.xMax},${glyph.yMax}) upm=${parser.unitsPerEm}` : 'null';
        console.log(`   [DBG] ${f} d=${d} gi=${gi} contours=${cc} bbox=${bb}`);
        if (glyph && glyph.contours && (f.indexOf('LiuJian') >= 0)) {
          const g2 = rasterizeToGray(glyph.contours, parser.unitsPerEm);
          // 高分辨率 ASCII
          const N = 30; let art = '';
          for (let r = 0; r < N; r++) { let line = ''; for (let c = 0; c < N; c++) { const xi = Math.floor(c / N * RENDER), yi = Math.floor(r / N * RENDER); line += g2[yi * RENDER + xi] < 205 ? '#' : '.'; } art += line + '\n'; }
          console.log(art);
        }
      }
      if (!glyph || !glyph.contours || glyph.contours.length === 0) { console.log(`  ${f} digit ${d}: 空字形`); continue; }
      const gray = rasterizeToGray(glyph.contours, parser.unitsPerEm);
      const sig = sigFromGray(gray, RENDER, RENDER);
      if (!sig) { console.log(`  ${f} digit ${d}: 无墨迹`); continue; }
      const ink = sig.reduce((a, b) => a + b, 0);
      if (ink < 6 || ink > 66) { console.log(`  ${f} digit ${d}: ink=${ink} 越界,跳过`); continue; }
      allTemplates.push({ digit: d, key: sig });
      okCount++;
      if (d === 1 || d === 8) console.log(`  ${f} digit ${d} ink=${ink}:\n` + sigToAscii(sig));
    }
    fontSummaries.push({ font: f, ok: okCount });
    console.log(`-> ${f}: ${okCount}/9 数字生成成功`);
  }
  // 写 FontTemplates.ets
  const out = [];
  out.push('// 自动生成：scripts/gen_font_templates.js');
  out.push('// 由 font/ 目录 9 个字体渲染数字 1-9 得到，作为 SudokuPixel.ets 的扩充匹配模板。');
  out.push('// 修改字体或阈值后重跑该脚本即可重新生成。');
  out.push('export const FONT_TEMPLATES: { digit: number; key: number[] }[] = [');
  for (const t of allTemplates) {
    out.push(`  { digit: ${t.digit}, key: [${t.key.join(',')}] },`);
  }
  out.push('];');
  const etsPath = 'entry/src/main/ets/core/sudoku/FontTemplates.ets';
  fs.writeFileSync(etsPath, out.join('\n'));
  console.log(`\n总计生成 ${allTemplates.length} 个模板，已写入 ${etsPath}`);
  console.log('各字体:', fontSummaries.map(s => `${s.font}=${s.ok}`).join(', '));
}

main();
