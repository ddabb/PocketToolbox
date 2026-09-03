const { createCanvas, loadImage } = require('canvas');
const vm = require('vm');
const fs = require('fs');
const path = require('path');

const code = fs.readFileSync(path.join(__dirname, 'test_ocr_node.js'), 'utf8');

// Add detailed logging for R4C0/C8 lowInk path
const patch = code.replace(
  /g_lastConfidence = Math\.min\(1, best1Score \/ \(SIG_LEN \+ 200\)\);\s*\/\/ 1→4 check for low-ink serif fonts/,
  `g_lastConfidence = Math.min(1, best1Score / (SIG_LEN + 200));
   if (g_dbgR4) console.log('LOWINK_14: inkC='+inkCount+' s1='+best1Score+' gconf='+g_lastConfidence);`
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
  
  // Set debug flag for R4 cells
  sb.g_dbgR4 = true;
  sb.processImage(imgData.data, 800, 800, templates);
}
run();
