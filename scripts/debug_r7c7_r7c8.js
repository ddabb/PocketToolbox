const { createCanvas, loadImage } = require('canvas');
const vm = require('vm');
const fs = require('fs');
const path = require('path');

const code = fs.readFileSync(path.join(__dirname, 'test_ocr_node.js'), 'utf8');

let r7c7_sig = null;
let r7c8_sig = null;
let r7c7_digit = -1;
let r7c8_digit = -1;
let r7c7_ink = -1;
let r7c8_ink = -1;

const patchedCode = code.replace(
  'grid[r * 9 + c] = digit;',
  `if (r === 7 && c === 7) { r7c7_sig = sig ? sig.length : 0; r7c7_digit = digit; r7c7_ink = g_lastRawInkRatio; }
   if (r === 7 && c === 8) { r7c8_sig = sig ? sig.length : 0; r7c8_digit = digit; r7c8_ink = g_lastRawInkRatio; }
   grid[r * 9 + c] = digit;`
);

const sb = {
  console, require, Float32Array, Array, Map, Set, Math, JSON,
  Int32Array, Uint8Array, Uint8ClampedArray, Date, process,
  Buffer: require('buffer').Buffer, path, fs,
  createCanvas, loadImage,
  exports: {}, module: { exports: {} },
  r7c7_sig: 0, r7c8_sig: 0, r7c7_digit: -1, r7c8_digit: -1, r7c7_ink: -1, r7c8_ink: -1
};
vm.runInNewContext(patchedCode, sb, { filename: 'test_ocr_node.js' });

const tmplData = JSON.parse(fs.readFileSync(
  path.join(__dirname, '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'digit_templates_extended.json'), 'utf8'));
const templates = tmplData.templates.map(t => ({ digit: t.digit, key: t.key }));

async function run() {
  const img = await loadImage(path.join(__dirname, '..', 'sudoku_test_images', '01_standard_544.png'));
  const canvas = createCanvas(800, 800);
  const ctx = canvas.getContext('2d');
  ctx.drawImage(img, 0, 0, 800, 800);
  const imgData = ctx.getImageData(0, 0, 800, 800);
  sb.processImage(imgData.data, 800, 800, templates);
  console.log('R7C7: digit=' + sb.r7c7_digit + ' sigLen=' + sb.r7c7_sig + ' ink=' + sb.r7c7_ink);
  console.log('R7C8: digit=' + sb.r7c8_digit + ' sigLen=' + sb.r7c8_sig + ' ink=' + sb.r7c8_ink);
}
run();
