const { createCanvas, loadImage } = require('canvas');
const vm = require('vm');
const fs = require('fs');
const path = require('path');

const code = fs.readFileSync(path.join(__dirname, 'test_ocr_node.js'), 'utf8');
const sb = {
  console, require, Float32Array, Array, Map, Set, Math, JSON,
  Int32Array, Uint8Array, Uint8ClampedArray, Date, process,
  Buffer: require('buffer').Buffer, path, fs,
  createCanvas, loadImage,
  exports: {}, module: { exports: {} }
};
vm.runInNewContext(code, sb, { filename: 'test_ocr_node.js' });

const tmplData = JSON.parse(fs.readFileSync(
  path.join(__dirname, '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'digit_templates_extended.json'), 'utf8'));
const templates = tmplData.templates.map(t => ({ digit: t.digit, key: t.key }));

const EXPECTED = [
  5, 3, 0, 0, 7, 0, 0, 0, 0,
  6, 0, 0, 1, 9, 5, 0, 0, 0,
  0, 9, 8, 0, 0, 0, 0, 6, 0,
  8, 0, 0, 0, 6, 0, 0, 0, 3,
  4, 0, 0, 8, 0, 3, 0, 0, 1,
  7, 0, 0, 0, 2, 0, 0, 0, 6,
  0, 6, 0, 0, 0, 0, 2, 8, 0,
  0, 0, 0, 4, 1, 9, 0, 0, 5,
  0, 0, 0, 0, 8, 0, 0, 7, 9,
];

const IMAGES = [
  '01_standard_544', '02_small_300', '03_large_800', '04_blue_numbers',
  '05_red_theme', '06_green_theme', '07_light_gray_numbers',
  '08_gray_bg_dark_numbers', '09_serif_font',
];

async function run() {
  for (const name of IMAGES) {
    try {
      const img = await loadImage(path.join(__dirname, '..', 'sudoku_test_images', name + '.png'));
      const canvas = createCanvas(800, 800);
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = '#FFFFFF';
      ctx.fillRect(0, 0, 800, 800);
      ctx.drawImage(img, 0, 0, 800, 800);
      const imgData = ctx.getImageData(0, 0, 800, 800);
      const grid = sb.processImage(imgData.data, 800, 800, templates);

      let errs = 0;
      const details = [];
      for (let i = 0; i < 81; i++) {
        if (EXPECTED[i] !== 0 && grid[i] !== EXPECTED[i]) {
          errs++;
          const r = Math.floor(i / 9);
          const c = i % 9;
          details.push(`R${r}C${c}:g=${grid[i]}w=${EXPECTED[i]}`);
        }
      }
      const status = errs === 0 ? 'PASS' : `FAIL(${errs})`;
      console.log(`${name}: ${status} ${details.join(', ')}`);
    } catch (e) {
      console.log(`${name}: ERROR ${e.message}`);
    }
  }
}
run();
