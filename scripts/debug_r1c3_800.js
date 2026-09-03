const fs = require('fs');
const path = require('path');
const { createCanvas, loadImage } = require('canvas');
const vm = require('vm');

const code = fs.readFileSync(path.join(__dirname, 'test_ocr_node.js'), 'utf8');

const patchStr1 = 'grid[r * 9 + c] = digit;';
const replaceStr1 = `
if (r===1 && c===3) {
  const retSig = cellSigFromGray(gray, width, cellL, cellT, cellW, cellH, isDark, bg, r, c);
  console.log('R1C3: retSig type='+(retSig===null?'null':typeof retSig)+' len='+(retSig?retSig.length:'N/A'));
  if (retSig) {
    const ic = retSig.reduce((a,b)=>a+b,0);
    console.log('R1C3: retSig ink='+ic+' first35=['+retSig.slice(0,35).join(',')+']');
  }
  const lowSig = cellSigFromGrayLowThresh(gray, width, cellL, cellT, cellW, cellH, isDark, bg, r, c);
  console.log('R1C3: lowSig type='+(lowSig===null?'null':typeof lowSig)+' len='+(lowSig?lowSig.length:'N/A'));
  if (lowSig) {
    const ic = lowSig.reduce((a,b)=>a+b,0);
    console.log('R1C3: lowSig ink='+ic);
    const rec = recognizeDigit(lowSig, templates);
    console.log('R1C3: lowSig recognized as digit='+rec+' conf='+g_lastConfidence);
  }
  console.log('R1C3: main digit='+digit+' sig='+(sig===null?'null':'arr')+' rawInk='+g_lastRawInkRatio);
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
  
  // Scale to 800x800 like ArkTS does
  const canvas = createCanvas(800, 800);
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = '#FFFFFF';
  ctx.fillRect(0, 0, 800, 800);
  ctx.drawImage(img, 0, 0, 800, 800);
  const imgData = ctx.getImageData(0, 0, 800, 800);
  
  const tmplData = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'digit_templates_extended.json'), 'utf8'));
  const templates = tmplData.templates.map(t => ({ digit: t.digit, key: t.key }));
  const grid = sandbox.processImage(imgData.data, 800, 800, templates);
  console.log('R1C3 in grid:', grid[1 * 9 + 3]);
  console.log('Full grid:');
  for (let r=0;r<9;r++) {
    let s='';
    for (let c=0;c<9;c++) s+=grid[r*9+c]+' ';
    console.log(s);
  }
}
run().catch(e => console.error(e));
