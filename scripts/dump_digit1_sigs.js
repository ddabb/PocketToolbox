'use strict';
const fs = require('fs');
const path = require('path');
const { createCanvas, loadImage } = require('canvas');
const { processImage, cellSigFromGray, cellSigFromGrayLowThresh, cellSigFromGrayThin, recognizeDigit, countInk, getConstants, bgColor, toGrayArray, findBoardBBox, grayInkPixel } = require('./test_ocr_node.js');

const EXPECTED_GRID = [
  5,3,0,0,7,0,0,0,0,
  6,0,0,1,9,5,0,0,0,
  0,9,8,0,0,0,0,6,0,
  8,0,0,0,6,0,0,0,3,
  4,0,0,8,0,3,0,0,1,
  7,0,0,0,2,0,0,0,6,
  0,6,0,0,0,0,2,8,0,
  0,0,0,4,1,9,0,0,5,
  0,0,0,0,8,0,0,7,9
];

const SIG_ROWS = 28, SIG_COLS = 20, SIG_LEN = 560;

function sigToVisual(sig) {
  let s = '';
  for (let r = 0; r < SIG_ROWS; r++) {
    for (let c = 0; c < SIG_COLS; c++) {
      s += sig[r * SIG_COLS + c] ? '#' : '.';
    }
    s += '\n';
  }
  return s;
}

function sigToCompact(sig) {
  let s = '';
  for (let r = 0; r < SIG_ROWS; r++) {
    let row = '';
    for (let c = 0; c < SIG_COLS; c++) row += sig[r * SIG_COLS + c];
    s += row;
  }
  return s;
}

async function main() {
  const templatePath = path.join(__dirname, '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'digit_templates_extended.json');
  const tmplData = JSON.parse(fs.readFileSync(templatePath, 'utf8'));
  const templates = tmplData.templates.map(t => ({ digit: t.digit, key: t.key }));

  const imgFile = process.argv[2] || '14_tiny_200.png';
  const filePath = path.join(__dirname, '..', 'sudoku_test_images', imgFile);
  console.log('Processing:', imgFile);

  const img = await loadImage(filePath);
  const canvas = createCanvas(img.width, img.height);
  const ctx = canvas.getContext('2d');
  ctx.drawImage(img, 0, 0);
  const imgData = ctx.getImageData(0, 0, img.width, img.height);
  const pixels = imgData.data;

  const grid = processImage(pixels, img.width, img.height, templates);
  const sigArray = require('./test_ocr_node.js').getSigArray();

  console.log('\n=== Digit-1 cells (want=1) ===');
  for (let i = 0; i < 81; i++) {
    if (EXPECTED_GRID[i] !== 1) continue;
    const r = Math.floor(i / 9), c = i % 9;
    const sig = sigArray[i];
    const got = grid[i];
    if (sig === null) {
      console.log(`R${r+1}C${c+1}: got=${got} want=1 sig=null`);
      continue;
    }
    const ink = countInk(sig);
    console.log(`R${r+1}C${c+1}: got=${got} want=1 ink=${ink}`);
    console.log(sigToVisual(sig));
    console.log('---');
  }

  console.log('\n=== All non-zero digit cells with errors ===');
  for (let i = 0; i < 81; i++) {
    if (EXPECTED_GRID[i] === 0) continue;
    if (grid[i] === EXPECTED_GRID[i]) continue;
    const r = Math.floor(i / 9), c = i % 9;
    const sig = sigArray[i];
    if (sig === null) {
      console.log(`R${r+1}C${c+1}: got=${grid[i]} want=${EXPECTED_GRID[i]} sig=null`);
      continue;
    }
    const ink = countInk(sig);
    console.log(`R${r+1}C${c+1}: got=${grid[i]} want=${EXPECTED_GRID[i]} ink=${ink}`);
    console.log(sigToVisual(sig));
    console.log('---');
  }
}

main().catch(e => console.error(e));
