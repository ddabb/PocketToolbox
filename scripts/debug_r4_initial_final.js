const { createCanvas, loadImage } = require('canvas');
const vm = require('vm');
const fs = require('fs');
const path = require('path');

const code = fs.readFileSync(path.join(__dirname, 'test_ocr_node.js'), 'utf8');

const patch = code.replace(
  'grid[r * 9 + c] = digit;',
  `if (r === 4 && (c === 0 || c === 8)) {
     console.log('INITIAL R4C' + c + ': digit=' + digit + ' conf=' + g_lastConfidence);
   }
   grid[r * 9 + c] = digit;`
).replace(
  'return finalGrid;',
  `console.log('FINAL R4C0=' + finalGrid[4*9+0] + ' R4C8=' + finalGrid[4*9+8]);
   return finalGrid;`
);

const sb = {
  console, require, Float32Array, Array, Map, Set, Math, JSON,
  Int32Array, Uint8Array, Uint8ClampedArray, Date, process,
  Buffer: require('buffer').Buffer, path, fs,
  createCanvas, loadImage,
  exports: {}, module: { exports: {} }
};
vm.runInNewContext(patch, sb, { filename: 'test_ocr_node.js' });

const tmplData = JSON.parse(fs.readFileSync(
  path.join(__dirname, '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'digit_templates_extended.json'), 'utf8'));
const templates = tmplData.templates.map(t => ({ digit: t.digit, key: t.key }));

async function run() {
  const img = await loadImage(path.join(__dirname, '..', 'sudoku_test_images', '09_serif_font.png'));
  const canvas = createCanvas(800, 800);
  const ctx = canvas.getContext('2d');
  ctx.drawImage(img, 0, 0, 800, 800);
  const imgData = ctx.getImageData(0, 0, 800, 800);
  sb.processImage(imgData.data, 800, 800, templates);
}
run();
