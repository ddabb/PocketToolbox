const { createCanvas, loadImage } = require('canvas');
const vm = require('vm');
const fs = require('fs');
const path = require('path');

const code = fs.readFileSync(path.join(__dirname, 'test_ocr_node.js'), 'utf8');

const patch = code.replace(
  'grid[r * 9 + c] = digit;',
  `if (r === 4 && (c === 0 || c === 8)) {
     const midTop14b = Math.floor(SIG_ROWS * 0.15), midBot14b = Math.floor(SIG_ROWS * 0.45);
     let topRightInk14 = 0, topLeftInk14 = 0;
     for (let rr = midTop14b; rr < midBot14b; rr++) for (let cc = 0; cc < SIG_COLS; cc++) if (sig[rr * SIG_COLS + cc] === 1) { if (cc >= SIG_COLS / 2) topRightInk14++; else topLeftInk14++; }
     const crossTop14 = Math.floor(SIG_ROWS * 0.55), crossBot14 = Math.floor(SIG_ROWS * 0.75);
     let crossCols14 = 0, crossInk14 = 0;
     for (let rr = crossTop14; rr < crossBot14; rr++) { let minC2 = SIG_COLS, maxC2 = -1; for (let cc = 0; cc < SIG_COLS; cc++) if (sig[rr * SIG_COLS + cc] === 1) { if (cc < minC2) minC2 = cc; if (cc > maxC2) maxC2 = cc; } if (maxC2 >= minC2) crossCols14 += maxC2 - minC2 + 1; for (let cc = 0; cc < SIG_COLS; cc++) if (sig[rr * SIG_COLS + cc] === 1) crossInk14++; }
     const midTop14c = Math.floor(SIG_ROWS * 0.25), midBot14c = Math.floor(SIG_ROWS * 0.75);
     let totalRowWidth14 = 0, rowCount14 = 0;
     for (let rr = midTop14c; rr < midBot14c; rr++) { let minC3 = SIG_COLS, maxC3 = -1; for (let cc = 0; cc < SIG_COLS; cc++) if (sig[rr * SIG_COLS + cc] === 1) { if (cc < minC3) minC3 = cc; if (cc > maxC3) maxC3 = cc; } if (maxC3 >= minC3) { totalRowWidth14 += maxC3 - minC3 + 1; rowCount14++; } }
     const avgRowW = rowCount14 > 0 ? totalRowWidth14 / rowCount14 : 0;
     console.log('R4_CELL r=' + r + ' c=' + c + ' d=' + digit + ' ink=' + g_lastRawInkRatio +
       ' topR=' + topRightInk14 + ' topL=' + topLeftInk14 +
       ' crossCols=' + crossCols14 + ' crossInk=' + crossInk14 +
       ' avgRowW=' + avgRowW.toFixed(1) +
       ' s1=' + digitBestScore[1] + ' s4=' + digitBestScore[4] +
       ' s1/s4=' + (digitBestScore[4] > 0 ? (digitBestScore[1] / digitBestScore[4]).toFixed(2) : 'inf'));
   }
   grid[r * 9 + c] = digit;`
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
