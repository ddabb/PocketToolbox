const fs = require('fs');
const path = require('path');
const { createCanvas, loadImage } = require('canvas');
const vm = require('vm');

const code = fs.readFileSync(path.join(__dirname, 'test_ocr_node.js'), 'utf8');

const patchStr = 'grid[r * 9 + c] = digit;';
const replaceStr = `
if (r===7 && c===8) {
  console.log('R7C8: digit='+digit+' sig='+(sig?'arr':'null')+' rawInk='+g_lastRawInkRatio+' conf='+g_lastConfidence);
}
grid[r * 9 + c] = digit;`;
const patchedCode = code.replace(patchStr, replaceStr);

const sandbox = {
  console, require, Float32Array, Array, Map, Set, Math, JSON,
  Int32Array, Uint8Array, Uint8ClampedArray, Date, process,
  Buffer: require('buffer').Buffer,
  path, fs,
  createCanvas, loadImage,
  exports: {}, module: { exports: {} }
};
vm.runInNewContext(patchedCode, sandbox, { filename: 'test_ocr_node.js' });

async function run() {
  const img = await loadImage(path.join(__dirname, '..', 'sudoku_test_images', '09_serif_font.png'));
  const canvas = createCanvas(800, 800);
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = '#FFFFFF';
  ctx.fillRect(0, 0, 800, 800);
  ctx.drawImage(img, 0, 0, 800, 800);
  const imgData = ctx.getImageData(0, 0, 800, 800);
  
  const tmplData = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'digit_templates_extended.json'), 'utf8'));
  const templates = tmplData.templates.map(t => ({ digit: t.digit, key: t.key }));
  const grid = sandbox.processImage(imgData.data, 800, 800, templates);
  console.log('R7C8 in grid:', grid[7 * 9 + 8]);
}
run().catch(e => console.error(e));
