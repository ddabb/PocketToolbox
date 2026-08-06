const fs = require('fs');
const path = require('path');
const fontDir = 'entry/src/main/resources/rawfile/font';
const fonts = fs.readdirSync(fontDir).filter(f => /\.(ttf|otf)$/i.test(f));
function tag(buf, off) { return String.fromCharCode(buf[off], buf[off+1], buf[off+2], buf[off+3]); }
for (const f of fonts) {
  const buf = fs.readFileSync(path.join(fontDir, f));
  const sfnt = buf.readUInt32BE(0);
  let kind = sfnt === 0x4F54544F ? 'OTTO(CFF)' : (sfnt === 0x00010000 || tag(buf,0)==='true') ? 'TTF(glyf)' : ('0x'+sfnt.toString(16));
  // read table directory
  const numTables = buf.readUInt16BE(4);
  const tables = {};
  let off = 12;
  for (let i = 0; i < numTables; i++) {
    const t = tag(buf, off);
    const to = buf.readUInt32BE(off+8);
    tables[t] = to;
    off += 16;
  }
  const hasGlyf = tables['glyf'] !== undefined;
  const hasCFF = tables['CFF '] !== undefined;
  console.log(f.padEnd(34), kind.padEnd(12), 'glyf=' + hasGlyf, 'CFF=' + hasCFF);
}
