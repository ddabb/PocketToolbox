// gen_digit_templates.js
// 基于 gen_font_templates.js 的算法（与 SudokuPixel.ets cellSigFromGray 一致），
// 解析 font/ 目录字体，将数字 1-9 光栅化为 12x8 二值特征码，
// 输出 digit_templates.json 供 SudokuPixel.ets 使用。
//
// 用法: node scripts/gen_digit_templates.js
// 依赖: canvas

const fs = require('fs');
const path = require('path');
const { createCanvas } = require('canvas');

const FONT_DIR = 'entry/src/main/resources/rawfile/font';
const OUTPUT_JSON = 'entry/src/main/resources/rawfile/digit_templates.json';
const SIG_ROWS = 28;
const SIG_COLS = 20;
const INK_THRESH = 50;
const BG = 255;
const RENDER = 320;

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
          const aidx = ro / 2 + (c - s) + (range - sub) / 2 - segCount * 0;
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
    return indexToLocFormat === 0 ? buf.readUInt16BE(loca.off + gi * 2) * 2 : buf.readUInt32BE(loca.off + gi * 4);
  }
  function readSimple(gi, goff) {
    let p = glyf.off + goff;
    const numContours = buf.readInt16BE(p); p += 2;
    const xMin = buf.readInt16BE(p); p += 2; const yMin = buf.readInt16BE(p); p += 2;
    const xMax = buf.readInt16BE(p); p += 2; const yMax = buf.readInt16BE(p); p += 2;
    const endPts = [];
    for (let i = 0; i < numContours; i++) { endPts.push(buf.readUInt16BE(p)); p += 2; }
    const instrLen = buf.readUInt16BE(p); p += 2; p += instrLen;
    const flags = [];
    const nPts = numContours > 0 ? endPts[numContours - 1] + 1 : 0;
    while (flags.length < nPts) {
      const f = buf.readUInt8(p++);
      flags.push(f);
      if (f & 8) { const rep = buf.readUInt8(p++); for (let r = 0; r < rep; r++) flags.push(f); }
    }
    const xs = []; let x = 0;
    for (let i = 0; i < nPts; i++) {
      const f = flags[i];
      if (f & 2) { const b = buf.readUInt8(p++); x += (f & 16) ? b : -b; }
      else if (f & 16) { /* same */ }
      else { x += buf.readInt16BE(p); p += 2; }
      xs.push(x);
    }
    const ys = []; let y = 0;
    for (let i = 0; i < nPts; i++) {
      const f = flags[i];
      if (f & 4) { const b = buf.readUInt8(p++); y += (f & 32) ? b : -b; }
      else if (f & 32) { /* same */ }
      else { y += buf.readInt16BE(p); p += 2; }
      ys.push(y);
    }
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
    if (goff === goff2) return null;
    const numContours = buf.readInt16BE(glyf.off + goff);
    if (numContours >= 0) return readSimple(gi, goff);
    return resolveComposite(gi, goff, depth);
  }
  function resolveComposite(rootGi, rootOff, depth) {
    let parentContours = [];
    let parentFlat = [];
    let p = glyf.off + rootOff + 10;
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

// ---------- OpenType CFF (Type 2 Charstring) ----------
function parseCFF(buf, tables, getGlyph) {
  const cffT = tables['CFF ']; if (!cffT) return null;
  const base = cffT.off;
  let p = base + 2 + 1 + 1; // major, minor, hdrSize, offSize

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
      items.push({ off: dataStart + offsets[i] - 1, len: offsets[i + 1] - offsets[i] });
    }
    return { items, next: dataStart + offsets[count] - 1, count };
  }

  const nameIdx = readIndex(p); p = nameIdx.next;
  const topIdx = readIndex(p); p = topIdx.next;
  if (topIdx.count === 0 || !topIdx.items[0]) return null;
  const topData = topIdx.items[0];
  if (topData.len <= 0) return null;
  const dict = parseDict(buf, topData.off, topData.len);

  // CharStrings offset (Top DICT op 17)
  const charStringsOffArr = dict.get(17);
  const charStringsOff = charStringsOffArr ? charStringsOffArr[0] : 0;

  // Read String INDEX then Global Subr INDEX
  const stringIdx = readIndex(p); p = stringIdx.next;
  const globalSubrIdx = readIndex(p);
  const globalSubrs = globalSubrIdx.items;
  const globalSubrCount = globalSubrIdx.count;

  // Private DICT (Top DICT op 18 -> [size, offset])
  const privateArr = dict.get(18);
  let localSubrs = null;
  let localSubrCount = 0;
  if (privateArr && privateArr.length >= 2 && privateArr[0] > 0) {
    const privOff = base + privateArr[1];
    const priv = parseDict(buf, privOff, privateArr[0]);
    // Local Subr INDEX (Private DICT op 19)
    const subrArr = priv.get(19);
    if (subrArr) {
      const localSubrIdx = readIndex(privOff + subrArr[0]);
      localSubrs = localSubrIdx.items;
      localSubrCount = localSubrIdx.count;
    }
  }

  if (!charStringsOff) return null;
  const csIdx = readIndex(base + charStringsOff);

  // Subroutine bias (CFF spec)
  function subrBias(n) {
    if (n < 1240) return 107;
    if (n < 33900) return 1131;
    return 32768;
  }
  const localBias = subrBias(localSubrCount);
  const globalBias = subrBias(globalSubrCount);

  function decodeCharstring(gi) {
    const item = csIdx.items[gi];
    if (!item || item.len === 0) return null;

    const stack = [];
    const contours = [];
    let cur = { x: 0, y: 0 };
    let curContour = null;
    let widthRead = false;
    let stemCount = 0;

    function newContour() { curContour = [cur]; contours.push(curContour); }
    function moveTo(x, y) { cur = { x, y }; curContour = null; }
    function lineTo(x, y) {
      cur = { x, y };
      if (!curContour) newContour();
      else curContour.push(cur);
    }
    function pushCurve(p0, c1, c2, p3) {
      const STEPS = 8;
      if (!curContour) { curContour = [p0]; contours.push(curContour); }
      for (let k = 1; k <= STEPS; k++) {
        const t = k / STEPS, mt = 1 - t;
        const x = mt*mt*mt*p0.x + 3*mt*mt*t*c1.x + 3*mt*t*t*c2.x + t*t*t*p3.x;
        const y = mt*mt*mt*p0.y + 3*mt*mt*t*c1.y + 3*mt*t*t*c2.y + t*t*t*p3.y;
        cur = { x, y }; curContour.push(cur);
      }
    }

    function exec(off, len, depth) {
      if (depth > 10) return;
      let q = off;
      const end = off + len;
      while (q < end) {
        let b = buf.readUInt8(q++);

        // --- Number operands ---
        if (b === 28) { stack.push(buf.readInt16BE(q)); q += 2; continue; }
        if (b >= 32 && b <= 246) { stack.push(b - 139); continue; }
        if (b >= 247 && b <= 250) { const w = buf.readUInt8(q++); stack.push((b - 247) * 256 + w + 108); continue; }
        if (b >= 251 && b <= 254) { const w = buf.readUInt8(q++); stack.push(-(b - 251) * 256 - w - 108); continue; }
        if (b === 255) { stack.push(buf.readInt32BE(q) / 65536); q += 4; continue; }

        // --- Two-byte operators (escape) ---
        if (b === 12) {
          const op = buf.readUInt8(q++);
          // Flex operators (12 34..37): render as two cubic Bézier curves
          if (op === 34 && stack.length >= 7) { // hflex: dx1 dx2 dy2 dx3 dx4 dx5 dx6
            const dx1=stack[0], dx2=stack[1], dy2=stack[2], dx3=stack[3], dx4=stack[4], dx5=stack[5], dx6=stack[6];
            const c1={x:cur.x+dx1,y:cur.y}, c2={x:c1.x+dx2,y:c1.y+dy2}, mid={x:c2.x+dx3,y:c2.y};
            const c3={x:mid.x+dx4,y:mid.y}, c4={x:c3.x+dx5,y:c3.y-dy2}, endp={x:c4.x+dx6,y:c4.y};
            pushCurve(cur,c1,c2,mid); pushCurve(mid,c3,c4,endp);
          } else if (op === 35 && stack.length >= 13) { // flex: 12 coords + 1 depth
            const dx1=stack[0],dy1=stack[1],dx2=stack[2],dy2=stack[3],dx3=stack[4],dy3=stack[5];
            const dx4=stack[6],dy4=stack[7],dx5=stack[8],dy5=stack[9],dx6=stack[10],dy6=stack[11];
            const c1={x:cur.x+dx1,y:cur.y+dy1}, c2={x:c1.x+dx2,y:c1.y+dy2}, mid={x:c2.x+dx3,y:c2.y+dy3};
            const c3={x:mid.x+dx4,y:mid.y+dy4}, c4={x:c3.x+dx5,y:c3.y+dy5}, endp={x:c4.x+dx6,y:c4.y+dy6};
            pushCurve(cur,c1,c2,mid); pushCurve(mid,c3,c4,endp);
          } else if (op === 36 && stack.length >= 9) { // hflex1: dx1 dy1 dx2 dy2 dx3 dx4 dx5 dy5 dx6
            const dx1=stack[0],dy1=stack[1],dx2=stack[2],dy2=stack[3],dx3=stack[4],dx4=stack[5],dx5=stack[6],dy5=stack[7],dx6=stack[8];
            const c1={x:cur.x+dx1,y:cur.y+dy1}, c2={x:c1.x+dx2,y:c1.y+dy2}, mid={x:c2.x+dx3,y:c2.y};
            const c3={x:mid.x+dx4,y:mid.y}, c4={x:c3.x+dx5,y:c3.y+dy5}, endp={x:c4.x+dx6,y:c4.y};
            pushCurve(cur,c1,c2,mid); pushCurve(mid,c3,c4,endp);
          } else if (op === 37 && stack.length >= 11) { // flex1
            const dx1=stack[0],dy1=stack[1],dx2=stack[2],dy2=stack[3],dx3=stack[4],dy3=stack[5];
            const dx4=stack[6],dy4=stack[7],dx5=stack[8],dy5=stack[9],d6=stack[10];
            const c1={x:cur.x+dx1,y:cur.y+dy1}, c2={x:c1.x+dx2,y:c1.y+dy2}, mid={x:c2.x+dx3,y:c2.y+dy3};
            const c3={x:mid.x+dx4,y:mid.y+dy4}, c4={x:c3.x+dx5,y:c3.y+dy5};
            // d6 applies to whichever axis has less total movement
            const totalDx = dx1+dx2+dx3+dx4+dx5;
            const totalDy = dy1+dy2+dy3+dy4+dy5;
            let endp;
            if (Math.abs(totalDx) > Math.abs(totalDy)) endp = {x:c4.x+d6, y:c4.y};
            else endp = {x:c4.x, y:c4.y+d6};
            pushCurve(cur,c1,c2,mid); pushCurve(mid,c3,c4,endp);
          }
          stack.length = 0;
          continue;
        }

        // --- One-byte operators (correct Type 2 numbering) ---
        switch (b) {
          case 1: case 3:      // hstem, vstem
          case 18: case 23: {  // hstemhm, vstemhm
            if (!widthRead && stack.length % 2 === 1) { stack.shift(); widthRead = true; }
            stemCount += Math.floor(stack.length / 2);
            stack.length = 0;
            break;
          }
          case 4: { // vmoveto
            if (!widthRead && stack.length === 2) { stack.shift(); widthRead = true; }
            const dy = stack.pop();
            moveTo(cur.x, cur.y + dy);
            stack.length = 0;
            break;
          }
          case 5: { // rlineto
            while (stack.length >= 2) {
              const dx = stack.shift(), dy = stack.shift();
              lineTo(cur.x + dx, cur.y + dy);
            }
            stack.length = 0;
            break;
          }
          case 6: { // hlineto (alternating h/v, starts with h)
            let h = true;
            while (stack.length) {
              const d = stack.shift();
              if (h) lineTo(cur.x + d, cur.y);
              else lineTo(cur.x, cur.y + d);
              h = !h;
            }
            break;
          }
          case 7: { // vlineto (alternating v/h, starts with v)
            let v = true;
            while (stack.length) {
              const d = stack.shift();
              if (v) lineTo(cur.x, cur.y + d);
              else lineTo(cur.x + d, cur.y);
              v = !v;
            }
            break;
          }
          case 8: { // rrcurveto: {dx1 dy1 dx2 dy2 dx3 dy3}+
            while (stack.length >= 6) {
              const dx1=stack.shift(), dy1=stack.shift(), dx2=stack.shift(), dy2=stack.shift(), dx3=stack.shift(), dy3=stack.shift();
              const c1={x:cur.x+dx1, y:cur.y+dy1}, c2={x:c1.x+dx2, y:c1.y+dy2}, endp={x:c2.x+dx3, y:c2.y+dy3};
              pushCurve(cur, c1, c2, endp);
            }
            stack.length = 0;
            break;
          }
          case 10: { // callsubr
            if (stack.length > 0 && localSubrs) {
              const idx = stack.pop() + localBias;
              const sub = localSubrs[idx];
              if (sub) exec(sub.off, sub.len, depth + 1);
            }
            break;
          }
          case 11: return; // return from subroutine
          case 14: { stack.length = 0; return; } // endchar
          case 19: case 20: { // hintmask, cntrmask
            if (!widthRead && stack.length % 2 === 1) { stack.shift(); widthRead = true; }
            stemCount += Math.floor(stack.length / 2);
            stack.length = 0;
            const maskBytes = Math.ceil(stemCount / 8);
            q += maskBytes;
            break;
          }
          case 21: { // rmoveto
            if (!widthRead && stack.length === 3) { stack.shift(); widthRead = true; }
            const dy = stack.pop(), dx = stack.pop();
            moveTo(cur.x + dx, cur.y + dy);
            stack.length = 0;
            break;
          }
          case 22: { // hmoveto
            if (!widthRead && stack.length === 2) { stack.shift(); widthRead = true; }
            const dx = stack.pop();
            moveTo(cur.x + dx, cur.y);
            stack.length = 0;
            break;
          }
          case 24: { // rcurveline: {curve6}+ dx dy
            while (stack.length >= 8) {
              const dx1=stack.shift(), dy1=stack.shift(), dx2=stack.shift(), dy2=stack.shift(), dx3=stack.shift(), dy3=stack.shift();
              const c1={x:cur.x+dx1,y:cur.y+dy1}, c2={x:c1.x+dx2,y:c1.y+dy2}, endp={x:c2.x+dx3,y:c2.y+dy3};
              pushCurve(cur, c1, c2, endp);
            }
            if (stack.length >= 2) {
              const dx = stack.shift(), dy = stack.shift();
              lineTo(cur.x + dx, cur.y + dy);
            }
            stack.length = 0;
            break;
          }
          case 25: { // rlinecurve: {dx dy}+ curve6
            while (stack.length > 6) {
              const dx = stack.shift(), dy = stack.shift();
              lineTo(cur.x + dx, cur.y + dy);
            }
            if (stack.length >= 6) {
              const dx1=stack.shift(), dy1=stack.shift(), dx2=stack.shift(), dy2=stack.shift(), dx3=stack.shift(), dy3=stack.shift();
              const c1={x:cur.x+dx1,y:cur.y+dy1}, c2={x:c1.x+dx2,y:c1.y+dy2}, endp={x:c2.x+dx3,y:c2.y+dy3};
              pushCurve(cur, c1, c2, endp);
            }
            stack.length = 0;
            break;
          }
          case 26: { // vvcurveto: [dx1?] {dy1 dx2 dy2 dy3}+
            let firstDx = 0;
            if (stack.length % 4 === 1) firstDx = stack.shift();
            while (stack.length >= 4) {
              const dya=stack.shift(), dxb=stack.shift(), dyb=stack.shift(), dyc=stack.shift();
              const c1={x:cur.x+firstDx, y:cur.y+dya}, c2={x:c1.x+dxb, y:c1.y+dyb}, endp={x:c2.x, y:c2.y+dyc};
              pushCurve(cur, c1, c2, endp);
              firstDx = 0;
            }
            stack.length = 0;
            break;
          }
          case 27: { // hhcurveto: [dy1?] {dx1 dx2 dy2 dx3}+
            let firstDy = 0;
            if (stack.length % 4 === 1) firstDy = stack.shift();
            while (stack.length >= 4) {
              const dxa=stack.shift(), dxb=stack.shift(), dyb=stack.shift(), dxc=stack.shift();
              const c1={x:cur.x+dxa, y:cur.y+firstDy}, c2={x:c1.x+dxb, y:c1.y+dyb}, endp={x:c2.x+dxc, y:c2.y};
              pushCurve(cur, c1, c2, endp);
              firstDy = 0;
            }
            stack.length = 0;
            break;
          }
          case 29: { // callgsubr
            if (stack.length > 0 && globalSubrs) {
              const idx = stack.pop() + globalBias;
              const sub = globalSubrs[idx];
              if (sub) exec(sub.off, sub.len, depth + 1);
            }
            break;
          }
          case 30: { // vhcurveto: alternating v-start / h-start curves
            while (stack.length >= 4) {
              const dya=stack.shift(), dxb=stack.shift(), dyb=stack.shift(), dxc=stack.shift();
              const c1={x:cur.x, y:cur.y+dya}, c2={x:c1.x+dxb, y:c1.y+dyb};
              let endp={x:c2.x+dxc, y:c2.y};
              if (stack.length === 1) endp.y += stack.shift();
              pushCurve(cur, c1, c2, endp);
              if (stack.length >= 4) {
                const dxa=stack.shift(), dxb2=stack.shift(), dyb2=stack.shift(), dyc=stack.shift();
                const c1b={x:cur.x+dxa, y:cur.y}, c2b={x:c1b.x+dxb2, y:c1b.y+dyb2};
                let endpb={x:c2b.x, y:c2b.y+dyc};
                if (stack.length === 1) endpb.x += stack.shift();
                pushCurve(cur, c1b, c2b, endpb);
              }
            }
            stack.length = 0;
            break;
          }
          case 31: { // hvcurveto: alternating h-start / v-start curves
            while (stack.length >= 4) {
              const dxa=stack.shift(), dxb=stack.shift(), dyb=stack.shift(), dyc=stack.shift();
              const c1={x:cur.x+dxa, y:cur.y}, c2={x:c1.x+dxb, y:c1.y+dyb};
              let endp={x:c2.x, y:c2.y+dyc};
              if (stack.length === 1) endp.x += stack.shift();
              pushCurve(cur, c1, c2, endp);
              if (stack.length >= 4) {
                const dya=stack.shift(), dxb2=stack.shift(), dyb2=stack.shift(), dxc=stack.shift();
                const c1b={x:cur.x, y:cur.y+dya}, c2b={x:c1b.x+dxb2, y:c1b.y+dyb2};
                let endpb={x:c2b.x+dxc, y:c2b.y};
                if (stack.length === 1) endpb.y += stack.shift();
                pushCurve(cur, c1b, c2b, endpb);
              }
            }
            stack.length = 0;
            break;
          }
          default:
            stack.length = 0;
        }
      }
    }

    exec(item.off, item.len, 0);

    let xMin = 1e9, yMin = 1e9, xMax = -1e9, yMax = -1e9;
    for (const c of contours) for (const pt of c) { if(pt.x<xMin)xMin=pt.x; if(pt.x>xMax)xMax=pt.x; if(pt.y<yMin)yMin=pt.y; if(pt.y>yMax)yMax=pt.y; }
    return { contours, xMin, yMin, xMax, yMax };
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
    else if (b === 30) {
      while (p < end) { const c = buf.readUInt8(p++); if ((c & 0x0f) === 0x0f) break; }
    } else if (b === 255) { p += 4; }
  }
  return m;
}

// ---------- 轮廓 -> 多边形 ----------
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
  let xMin = 1e9, yMin = 1e9, xMax = -1e9, yMax = -1e9;
  for (const poly of polys) for (const pt of poly) { if (pt.x < xMin) xMin = pt.x; if (pt.x > xMax) xMax = pt.x; if (pt.y < yMin) yMin = pt.y; if (pt.y > yMax) yMax = pt.y; }
  const span = Math.max(xMax - xMin, yMax - yMin) || 1;
  const scale = (RENDER * 0.82) / span;
  const cx = RENDER / 2 - (xMin + xMax) / 2 * scale;
  const cy = RENDER / 2 + (yMin + yMax) / 2 * scale;
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
  for (let i = 0; i < RENDER * RENDER; i++) {
    const val = data[i * 4];
    gray[i] = val < 128 ? 0 : 255; // 二值化，消除抗锯齿
  }
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
    for (let col = 0; col < SIG_COLS; col++) line += sig[r * SIG_COLS + col] ? '█' : '·';
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
    try {
      const buf = fs.readFileSync(path.join(FONT_DIR, f));
      const tables = readTableDir(buf);
      const getGlyph = buildCmap(buf, tables);
      const sfnt = buf.readUInt32BE(0);
      const isCFF = sfnt === 0x4F54544F;
      let parser = isCFF ? parseCFF(buf, tables, getGlyph) : parseGlyf(buf, tables, getGlyph);
      if (!parser) { console.log(`!! 无法解析 ${f}`); continue; }

      let okCount = 0;
      for (let d = 1; d <= 9; d++) {
        const gi = getGlyph(d + 48);
        let glyph = null;
        if (parser.decodeCharstring) glyph = parser.decodeCharstring(gi);
        else if (parser.readGlyph) glyph = parser.readGlyph(gi);

        if (!glyph || !glyph.contours || glyph.contours.length === 0) {
          console.log(`  ${f} digit ${d}: 空字形 (gi=${gi})`);
          continue;
        }

        const gray = rasterizeToGray(glyph.contours, parser.unitsPerEm);
        const sig = sigFromGray(gray, RENDER, RENDER);

        if (!sig) { console.log(`  ${f} digit ${d}: 无墨迹`); continue; }

        const ink = sig.reduce((a, b) => a + b, 0);
        if (ink < 25 || ink > 420) { console.log(`  ${f} digit ${d}: ink=${ink} 越界,跳过`); continue; }

        allTemplates.push({ digit: d, font: f, key: sig });
        okCount++;
        console.log(`  ${f} digit ${d} ink=${ink}:`);
        console.log(sigToAscii(sig));
      }
      fontSummaries.push({ font: f, ok: okCount });
      console.log(`-> ${f}: ${okCount}/9 数字生成成功\n`);
    } catch (err) {
      console.log(`!! 处理 ${f} 时出错: ${err.message}`);
      fontSummaries.push({ font: f, ok: 0 });
    }
  }

  // 输出 JSON
  const json = {
    rows: SIG_ROWS,
    cols: SIG_COLS,
    templates: allTemplates
  };

  fs.writeFileSync(OUTPUT_JSON, JSON.stringify(json, null, 2), 'utf-8');
  console.log(`\n总计生成 ${allTemplates.length} 个模板，已写入 ${OUTPUT_JSON}`);
  console.log('各字体:', fontSummaries.map(s => `${s.font}=${s.ok}`).join(', '));

  // 统计唯一性
  const uniqueSigs = new Set(allTemplates.map(t => t.key.join(',')));
  console.log(`唯一特征码数: ${uniqueSigs.size} / ${allTemplates.length}`);
}

main();
