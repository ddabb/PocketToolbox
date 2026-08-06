import { createCanvas, registerFont, loadImage, Image } from 'canvas';
import { writeFileSync, readdirSync } from 'fs';
import { join } from 'path';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const fontkit = require('fontkit');

const FONT_DIR = 'F:\\PocketToolbox\\entry\\src\\main\\resources\\rawfile\\font';
const OUTPUT_JSON = 'F:\\PocketToolbox\\entry\\src\\main\\resources\\rawfile\\digit_templates.json';
const SIG_ROWS = 12;
const SIG_COLS = 8;
const RENDER_SIZE = 256;

function pathToSVG(font, digit) {
  const glyphs = font.layout(String(digit)).glyphs;
  if (!glyphs || glyphs.length === 0) return null;

  let xCursor = 0;
  const rawPaths = [];

  for (const glyph of glyphs) {
    const path = glyph.path;
    if (!path || !path.commands || path.commands.length === 0) return null;
    const metrics = glyph._getMetrics();
    const xOff = xCursor + metrics.leftBearing;
    rawPaths.push({ commands: path.commands, xOff });
    xCursor += metrics.advanceWidth || 0;
  }

  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const { commands, xOff } of rawPaths) {
    for (const cmd of commands) {
      for (let i = 0; i < (cmd.args?.length || 0); i += 2) {
        const x = cmd.args[i] + xOff;
        const y = -cmd.args[i + 1];
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (maxX <= minX || maxY <= minY) return null;

  const pad = 10;
  const svgW = RENDER_SIZE;
  const svgH = RENDER_SIZE;
  const vbX = minX - pad;
  const vbY = minY - pad;
  const vbW = (maxX - minX) + pad * 2;
  const vbH = (maxY - minY) + pad * 2;

  let d = '';
  for (const { commands, xOff } of rawPaths) {
    for (const cmd of commands) {
      const fy = (args, i) => -args[i];
      if (cmd.command === 'moveTo') {
        d += `M${(cmd.args[0] + xOff).toFixed(2)} ${fy(cmd.args, 1).toFixed(2)} `;
      } else if (cmd.command === 'lineTo') {
        d += `L${(cmd.args[0] + xOff).toFixed(2)} ${fy(cmd.args, 1).toFixed(2)} `;
      } else if (cmd.command === 'quadraticCurveTo') {
        d += `Q${(cmd.args[0] + xOff).toFixed(2)} ${fy(cmd.args, 1).toFixed(2)} ${(cmd.args[2] + xOff).toFixed(2)} ${fy(cmd.args, 3).toFixed(2)} `;
      } else if (cmd.command === 'bezierCurveTo') {
        d += `C${(cmd.args[0] + xOff).toFixed(2)} ${fy(cmd.args, 1).toFixed(2)} ${(cmd.args[2] + xOff).toFixed(2)} ${fy(cmd.args, 3).toFixed(2)} ${(cmd.args[4] + xOff).toFixed(2)} ${fy(cmd.args, 5).toFixed(2)} `;
      } else if (cmd.command === 'closePath') {
        d += 'Z ';
      }
    }
  }

  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${svgW}" height="${svgH}" viewBox="${vbX.toFixed(2)} ${vbY.toFixed(2)} ${vbW.toFixed(2)} ${vbH.toFixed(2)}">
  <rect x="${vbX.toFixed(2)}" y="${vbY.toFixed(2)}" width="${vbW.toFixed(2)}" height="${vbH.toFixed(2)}" fill="white"/>
  <path d="${d}" fill="black"/>
</svg>`;

  return svg;
}

function computeSignature(ctx, rows, cols) {
  const W = RENDER_SIZE;
  const H = RENDER_SIZE;
  const imageData = ctx.getImageData(0, 0, W, H);
  const data = imageData.data;

  let bminX = W, bmaxX = 0, bminY = H, bmaxY = 0;
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const idx = (y * W + x) * 4;
      const gray = 0.299 * data[idx] + 0.587 * data[idx + 1] + 0.114 * data[idx + 2];
      if (gray < 128) {
        if (x < bminX) bminX = x;
        if (x > bmaxX) bmaxX = x;
        if (y < bminY) bminY = y;
        if (y > bmaxY) bmaxY = y;
      }
    }
  }

  if (bmaxX <= bminX) return null;

  const bw = bmaxX - bminX + 1;
  const bh = bmaxY - bminY + 1;
  const sig = new Array(rows * cols).fill(0);

  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const sx0 = bminX + Math.floor(bw * c / cols);
      const sx1 = bminX + Math.floor(bw * (c + 1) / cols);
      const sy0 = bminY + Math.floor(bh * r / rows);
      const sy1 = bminY + Math.floor(bh * (r + 1) / rows);
      let ink = 0, total = 0;
      for (let y = sy0; y < sy1; y++) {
        for (let x = sx0; x < sx1; x++) {
          total++;
          const idx = (y * W + x) * 4;
          const gray = 0.299 * data[idx] + 0.587 * data[idx + 1] + 0.114 * data[idx + 2];
          if (gray < 128) ink++;
        }
      }
      sig[r * cols + c] = (total > 0 && ink / total > 0.3) ? 1 : 0;
    }
  }
  return sig;
}

function countInk(sig) {
  return sig.reduce((s, v) => s + v, 0);
}

async function main() {
  const files = readdirSync(FONT_DIR);
  const fonts = [];
  for (const f of files) {
    if (f.endsWith('.ttf') || f.endsWith('.otf')) {
      const fp = join(FONT_DIR, f);
      try {
        const font = fontkit.openSync(fp);
        fonts.push({ file: f, font, family: font.familyName || f });
        console.log(`Loaded: ${f} -> ${font.familyName}`);
      } catch (e) {
        console.warn(`SKIP ${f}: ${e.message}`);
      }
    }
  }
  console.log(`Total: ${fonts.length} fonts\n`);

  const templates = [];
  for (const { file, font, family } of fonts) {
    console.log(`--- ${file} (${family}) ---`);
    for (let d = 1; d <= 9; d++) {
      const svg = pathToSVG(font, d);
      if (!svg) {
        console.warn(`  digit=${d}: SVG generation failed`);
        continue;
      }

      try {
        const buf = Buffer.from(svg);
        const img = await loadImage(buf);
        const canvas = createCanvas(RENDER_SIZE, RENDER_SIZE);
        const ctx = canvas.getContext('2d');
        ctx.drawImage(img, 0, 0, RENDER_SIZE, RENDER_SIZE);

        const sig = computeSignature(ctx, SIG_ROWS, SIG_COLS);
        if (!sig || countInk(sig) < 3) {
          console.warn(`  digit=${d}: signature too small`);
          continue;
        }

        templates.push({ digit: d, font: file, key: sig });
        const ink = countInk(sig);
        console.log(`  digit=${d} ink=${ink}`);
        for (let r = 0; r < SIG_ROWS; r++) {
          const line = sig.slice(r * SIG_COLS, (r + 1) * SIG_COLS).map(v => v ? '█' : '·').join('');
          console.log(`    ${line}`);
        }
      } catch (e) {
        console.warn(`  digit=${d}: render error: ${e.message}`);
      }
    }
  }

  const json = { rows: SIG_ROWS, cols: SIG_COLS, templates };
  writeFileSync(OUTPUT_JSON, JSON.stringify(json, null, 2), 'utf-8');
  console.log(`\nWritten ${templates.length} templates to ${OUTPUT_JSON}`);

  const uniqueSigs = new Set(templates.map(t => t.key.join(',')));
  console.log(`Unique signatures: ${uniqueSigs.size}`);
}

main().catch(console.error);
