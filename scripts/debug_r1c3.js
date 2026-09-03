const fs = require('fs');
const path = require('path');
const { createCanvas, loadImage } = require('canvas');
const vm = require('vm');

const code = fs.readFileSync(path.join(__dirname, 'test_ocr_node.js'), 'utf8');

// Patch to add debug for R1C3 - show signature and intermediate results
const patchStr1 = 'grid[r * 9 + c] = digit;';
const replaceStr1 = `
if (r===1 && c===3) {
  console.log('R1C3: sig=' + (sig?'non-null':'null') + ' digit=' + digit + ' rawInk=' + g_lastRawInkRatio.toFixed(4));
  if (sig) {
    console.log('R1C3 sig:');
    for (let rr=0;rr<7;rr++) { let row=''; for (let cc=0;cc<5;cc++) row+=sig[rr*5+cc]+' '; console.log('  '+row); }
  }
}
grid[r * 9 + c] = digit;`;
const patchedCode = code.replace(patchStr1, replaceStr1);

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
  const img = await loadImage(path.join(__dirname, '..', 'sudoku_test_images', '07_light_gray_numbers.png'));
  const canvas = createCanvas(img.width, img.height);
  const ctx = canvas.getContext('2d');
  ctx.drawImage(img, 0, 0);
  const imgData = ctx.getImageData(0, 0, img.width, img.height);
  const tmplData = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'digit_templates_extended.json'), 'utf8'));
  const templates = tmplData.templates.map(t => ({ digit: t.digit, key: t.key }));
  const grid = sandbox.processImage(imgData.data, img.width, img.height, templates);
  console.log('R1C3 in grid:', grid[1 * 9 + 3]);
}
run().catch(e => console.error(e));
