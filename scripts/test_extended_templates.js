const { createCanvas, loadImage } = require('canvas');
const fs = require('fs');
const path = require('path');
const mod = require('./test_ocr_node.js');

const tmplData = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'digit_templates_extended.json'), 'utf8'));
const templates = tmplData.templates.map(t => ({ digit: t.digit, key: t.key }));
console.log('Total templates:', templates.length);
const byD = {};
templates.forEach(t => { byD[t.digit] = (byD[t.digit] || 0) + 1; });
console.log('By digit:', JSON.stringify(byD));

const EXPECTED = [5,3,0,0,7,0,0,0,0,6,0,0,1,9,5,0,0,0,0,9,8,0,0,0,0,6,0,8,0,0,0,6,0,0,0,3,4,0,0,8,0,3,0,0,1,7,0,0,0,2,0,0,0,6,0,6,0,0,0,0,2,8,0,0,0,0,4,1,9,0,0,5,0,0,0,0,8,0,0,7,9];

async function run() {
  const imgDir = path.join(__dirname, '..', 'sudoku_test_images');
  const files = fs.readdirSync(imgDir).filter(f => f.endsWith('.png')).sort();
  let totalCorrect = 0, grandTotal = 0, totalDigitCorrect = 0, grandDigitTotal = 0;
  for (const file of files) {
    const img = await loadImage(path.join(imgDir, file));
    const canvas = createCanvas(img.width, img.height);
    const ctx = canvas.getContext('2d');
    ctx.drawImage(img, 0, 0);
    const imgData = ctx.getImageData(0, 0, img.width, img.height);
    const grid = mod.processImage(imgData.data, img.width, img.height, templates);
    let correct = 0, total = 0, digitCorrect = 0, digitTotal = 0;
    for (let i = 0; i < 81; i++) {
      if (EXPECTED[i] !== 0) { digitTotal++; if (grid[i] === EXPECTED[i]) digitCorrect++; }
      total++; if (grid[i] === EXPECTED[i]) correct++;
    }
    totalCorrect += correct; grandTotal += total;
    totalDigitCorrect += digitCorrect; grandDigitTotal += digitTotal;
    const pct = (digitTotal > 0 ? digitCorrect / digitTotal * 100 : 0).toFixed(1);
    console.log(file.padEnd(35), digitCorrect + '/' + digitTotal + ' (' + pct + '%)');
  }
  console.log('\nOVERALL digits: ' + totalDigitCorrect + '/' + grandDigitTotal + ' (' + (totalDigitCorrect / grandDigitTotal * 100).toFixed(1) + '%)');
}

run().catch(e => console.error(e));
