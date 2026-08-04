const { createCanvas } = require('canvas');
const fs = require('fs');
const path = require('path');

const puzzle = [
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

const SIZE = 9;
const CELL = 56;
const PAD = 20;
const BOARD = SIZE * CELL;
const TOTAL = BOARD + 2 * PAD;

const canvas = createCanvas(TOTAL, TOTAL);
const ctx = canvas.getContext('2d');

// white background
ctx.fillStyle = '#ffffff';
ctx.fillRect(0, 0, TOTAL, TOTAL);

// --- thin cell lines ---
ctx.strokeStyle = '#bfbfbf';
ctx.lineWidth = 1;
for (let i = 0; i <= SIZE; i++) {
  ctx.beginPath();
  ctx.moveTo(PAD + i * CELL, PAD);
  ctx.lineTo(PAD + i * CELL, PAD + BOARD);
  ctx.stroke();
  ctx.beginPath();
  ctx.moveTo(PAD, PAD + i * CELL);
  ctx.lineTo(PAD + BOARD, PAD + i * CELL);
  ctx.stroke();
}

// --- thick 3x3 block lines ---
ctx.strokeStyle = '#333333';
ctx.lineWidth = 3;
for (let i = 0; i <= SIZE; i += 3) {
  ctx.beginPath();
  ctx.moveTo(PAD + i * CELL, PAD);
  ctx.lineTo(PAD + i * CELL, PAD + BOARD);
  ctx.stroke();
  ctx.beginPath();
  ctx.moveTo(PAD, PAD + i * CELL);
  ctx.lineTo(PAD + BOARD, PAD + i * CELL);
  ctx.stroke();
}

// --- outer border (thickest) ---
ctx.strokeStyle = '#000000';
ctx.lineWidth = 4;
ctx.beginPath();
ctx.rect(PAD, PAD, BOARD, BOARD);
ctx.stroke();

// --- numbers ---
ctx.textAlign = 'center';
ctx.textBaseline = 'middle';
ctx.font = 'bold 26px "Segoe UI", Arial, sans-serif';
ctx.fillStyle = '#1a1a1a';

for (let r = 0; r < SIZE; r++) {
  for (let c = 0; c < SIZE; c++) {
    const val = puzzle[r * SIZE + c];
    if (val !== 0) {
      const x = PAD + c * CELL + CELL / 2;
      const y = PAD + r * CELL + CELL / 2;
      ctx.fillText(val.toString(), x, y);
    }
  }
}

const outPath = path.join(__dirname, '..', 'sudoku_puzzle.png');
const buffer = canvas.toBuffer('image/png');
fs.writeFileSync(outPath, buffer);
console.log(`Saved: ${outPath} (${TOTAL}x${TOTAL}px)`);
