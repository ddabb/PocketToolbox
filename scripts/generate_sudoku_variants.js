const { createCanvas } = require('canvas');
const fs = require('fs');
const path = require('path');

// 标准数独题目
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
const OUT_DIR = path.join(__dirname, '..', 'sudoku_test_images');

// 配置数组: 各种变体
const variants = [
  // --- 标准变体 ---
  {
    name: '01_standard_544',
    cell: 56, pad: 20,
    thinColor: '#bfbfbf', thinWidth: 1,
    thickColor: '#333333', thickWidth: 3,
    outerColor: '#000000', outerWidth: 4,
    bgColor: '#ffffff',
    font: 'bold 26px "Segoe UI", Arial, sans-serif',
    numberColor: '#1a1a1a',
  },
  {
    name: '02_small_300',
    cell: 30, pad: 15,
    thinColor: '#c0c0c0', thinWidth: 1,
    thickColor: '#444444', thickWidth: 2,
    outerColor: '#000000', outerWidth: 3,
    bgColor: '#ffffff',
    font: 'bold 14px "Segoe UI", Arial, sans-serif',
    numberColor: '#000000',
  },
  {
    name: '03_large_800',
    cell: 80, pad: 30,
    thinColor: '#cccccc', thinWidth: 1,
    thickColor: '#222222', thickWidth: 4,
    outerColor: '#000000', outerWidth: 5,
    bgColor: '#ffffff',
    font: 'bold 38px "Segoe UI", Arial, sans-serif',
    numberColor: '#1a1a1a',
  },

  // --- 颜色变体 ---
  {
    name: '04_blue_numbers',
    cell: 56, pad: 20,
    thinColor: '#e0e7ff', thinWidth: 1,
    thickColor: '#4338ca', thickWidth: 3,
    outerColor: '#1e3a5f', outerWidth: 4,
    bgColor: '#ffffff',
    font: 'bold 26px "Segoe UI", Arial, sans-serif',
    numberColor: '#2563eb',
  },
  {
    name: '05_red_theme',
    cell: 56, pad: 20,
    thinColor: '#fecaca', thinWidth: 1,
    thickColor: '#dc2626', thickWidth: 3,
    outerColor: '#7f1d1d', outerWidth: 4,
    bgColor: '#ffffff',
    font: 'bold 26px "Segoe UI", Arial, sans-serif',
    numberColor: '#b91c1c',
  },
  {
    name: '06_green_theme',
    cell: 56, pad: 20,
    thinColor: '#bbf7d0', thinWidth: 1,
    thickColor: '#16a34a', thickWidth: 3,
    outerColor: '#14532d', outerWidth: 4,
    bgColor: '#ffffff',
    font: 'bold 26px "Segoe UI", Arial, sans-serif',
    numberColor: '#15803d',
  },

  // --- 低对比度变体 ---
  {
    name: '07_light_gray_numbers',
    cell: 56, pad: 20,
    thinColor: '#e5e5e5', thinWidth: 1,
    thickColor: '#a3a3a3', thickWidth: 3,
    outerColor: '#737373', outerWidth: 4,
    bgColor: '#ffffff',
    font: 'bold 26px "Segoe UI", Arial, sans-serif',
    numberColor: '#9ca3af',
  },
  {
    name: '08_gray_bg_dark_numbers',
    cell: 56, pad: 20,
    thinColor: '#d1d5db', thinWidth: 1,
    thickColor: '#6b7280', thickWidth: 3,
    outerColor: '#374151', outerWidth: 4,
    bgColor: '#f3f4f6',
    font: 'bold 26px "Segoe UI", Arial, sans-serif',
    numberColor: '#111827',
  },

  // --- 字体变体 ---
  {
    name: '09_serif_font',
    cell: 56, pad: 20,
    thinColor: '#bfbfbf', thinWidth: 1,
    thickColor: '#333333', thickWidth: 3,
    outerColor: '#000000', outerWidth: 4,
    bgColor: '#ffffff',
    font: 'bold 26px "Times New Roman", Georgia, serif',
    numberColor: '#1a1a1a',
  },
  {
    name: '10_italic_font',
    cell: 56, pad: 20,
    thinColor: '#bfbfbf', thinWidth: 1,
    thickColor: '#333333', thickWidth: 3,
    outerColor: '#000000', outerWidth: 4,
    bgColor: '#ffffff',
    font: 'italic 26px "Segoe UI", Arial, sans-serif',
    numberColor: '#1a1a1a',
  },
  {
    name: '11_thin_font',
    cell: 56, pad: 20,
    thinColor: '#bfbfbf', thinWidth: 1,
    thickColor: '#333333', thickWidth: 3,
    outerColor: '#000000', outerWidth: 4,
    bgColor: '#ffffff',
    font: '26px "Segoe UI Light", "Segoe UI", Arial, sans-serif',
    numberColor: '#1a1a1a',
  },

  // --- 边框变体 ---
  {
    name: '12_all_thin_lines',
    cell: 56, pad: 20,
    thinColor: '#cccccc', thinWidth: 1,
    thickColor: '#cccccc', thickWidth: 1,   // 粗线=细线
    outerColor: '#cccccc', outerWidth: 1,    // 外框同上
    bgColor: '#ffffff',
    font: 'bold 26px "Segoe UI", Arial, sans-serif',
    numberColor: '#1a1a1a',
  },
  {
    name: '13_no_outer_border',
    cell: 56, pad: 20,
    thinColor: '#bfbfbf', thinWidth: 1,
    thickColor: '#333333', thickWidth: 3,
    outerColor: '#ffffff', outerWidth: 0,    // 无外框
    bgColor: '#ffffff',
    font: 'bold 26px "Segoe UI", Arial, sans-serif',
    numberColor: '#1a1a1a',
  },

  // --- 极端变体 ---
  {
    name: '14_tiny_200',
    cell: 20, pad: 10,
    thinColor: '#cccccc', thinWidth: 1,
    thickColor: '#555555', thickWidth: 2,
    outerColor: '#000000', outerWidth: 2,
    bgColor: '#ffffff',
    font: 'bold 10px "Segoe UI", Arial, sans-serif',
    numberColor: '#000000',
  },
  {
    name: '15_huge_1000',
    cell: 100, pad: 40,
    thinColor: '#dddddd', thinWidth: 2,
    thickColor: '#111111', thickWidth: 5,
    outerColor: '#000000', outerWidth: 6,
    bgColor: '#ffffff',
    font: 'bold 48px "Segoe UI", Arial, sans-serif',
    numberColor: '#111111',
  },

  // --- 深色主题 ---
  {
    name: '16_dark_bg_light_numbers',
    cell: 56, pad: 20,
    thinColor: '#4a4a4a', thinWidth: 1,
    thickColor: '#888888', thickWidth: 3,
    outerColor: '#aaaaaa', outerWidth: 4,
    bgColor: '#1a1a2e',
    font: 'bold 26px "Segoe UI", Arial, sans-serif',
    numberColor: '#e0e0e0',
  },
  {
    name: '17_pure_black_white',
    cell: 56, pad: 20,
    thinColor: '#444444', thinWidth: 1,
    thickColor: '#888888', thickWidth: 3,
    outerColor: '#ffffff', outerWidth: 4,
    bgColor: '#000000',
    font: 'bold 26px "Segoe UI", Arial, sans-serif',
    numberColor: '#ffffff',
  },

  // --- 字体大小/粗细变体 ---
  {
    name: '18_small_font_in_cell',
    cell: 56, pad: 20,
    thinColor: '#bfbfbf', thinWidth: 1,
    thickColor: '#333333', thickWidth: 3,
    outerColor: '#000000', outerWidth: 4,
    bgColor: '#ffffff',
    font: 'bold 18px "Segoe UI", Arial, sans-serif',
    numberColor: '#1a1a1a',
  },
  {
    name: '19_large_font_in_cell',
    cell: 56, pad: 20,
    thinColor: '#bfbfbf', thinWidth: 1,
    thickColor: '#333333', thickWidth: 3,
    outerColor: '#000000', outerWidth: 4,
    bgColor: '#ffffff',
    font: 'bold 36px "Segoe UI", Arial, sans-serif',
    numberColor: '#1a1a1a',
  },

  // --- 单元格边框变体 ---
  {
    name: '20_dashed_lines',
    cell: 56, pad: 20,
    thinColor: '#bfbfbf', thinWidth: 1,
    thickColor: '#333333', thickWidth: 3,
    outerColor: '#000000', outerWidth: 4,
    bgColor: '#ffffff',
    font: 'bold 26px "Segoe UI", Arial, sans-serif',
    numberColor: '#1a1a1a',
    dashed: true,
  },
  {
    name: '21_thick_all_lines',
    cell: 56, pad: 20,
    thinColor: '#333333', thinWidth: 3,
    thickColor: '#000000', thickWidth: 5,
    outerColor: '#000000', outerWidth: 6,
    bgColor: '#ffffff',
    font: 'bold 26px "Segoe UI", Arial, sans-serif',
    numberColor: '#1a1a1a',
  },

  // --- 彩色场景 ---
  {
    name: '22_yellow_highlight',
    cell: 56, pad: 20,
    thinColor: '#d4a017', thinWidth: 1,
    thickColor: '#8b6914', thickWidth: 3,
    outerColor: '#5c4609', outerWidth: 4,
    bgColor: '#fffde7',
    font: 'bold 26px "Segoe UI", Arial, sans-serif',
    numberColor: '#4e342e',
  },
  {
    name: '23_orange_numbers',
    cell: 56, pad: 20,
    thinColor: '#bfbfbf', thinWidth: 1,
    thickColor: '#333333', thickWidth: 3,
    outerColor: '#000000', outerWidth: 4,
    bgColor: '#ffffff',
    font: 'bold 26px "Segoe UI", Arial, sans-serif',
    numberColor: '#e65100',
  },

  // --- 对比度变体 ---
  {
    name: '24_medium_gray_numbers',
    cell: 56, pad: 20,
    thinColor: '#cccccc', thinWidth: 1,
    thickColor: '#555555', thickWidth: 3,
    outerColor: '#333333', outerWidth: 4,
    bgColor: '#ffffff',
    font: 'bold 26px "Segoe UI", Arial, sans-serif',
    numberColor: '#666666',
  },
  {
    name: '25_very_faint_numbers',
    cell: 56, pad: 20,
    thinColor: '#e0e0e0', thinWidth: 1,
    thickColor: '#999999', thickWidth: 3,
    outerColor: '#666666', outerWidth: 4,
    bgColor: '#ffffff',
    font: 'bold 26px "Segoe UI", Arial, sans-serif',
    numberColor: '#aaaaaa',
  },

  // --- 字体变体 ---
  {
    name: '26_mono_font',
    cell: 56, pad: 20,
    thinColor: '#bfbfbf', thinWidth: 1,
    thickColor: '#333333', thickWidth: 3,
    outerColor: '#000000', outerWidth: 4,
    bgColor: '#ffffff',
    font: 'bold 26px "Courier New", Courier, monospace',
    numberColor: '#1a1a1a',
  },
  {
    name: '27_cursive_font',
    cell: 56, pad: 20,
    thinColor: '#bfbfbf', thinWidth: 1,
    thickColor: '#333333', thickWidth: 3,
    outerColor: '#000000', outerWidth: 4,
    bgColor: '#ffffff',
    font: '26px "Brush Script MT", "Segoe Script", cursive',
    numberColor: '#1a1a1a',
  },

  // --- 尺寸极端 ---
  {
    name: '28_medium_400',
    cell: 40, pad: 16,
    thinColor: '#cccccc', thinWidth: 1,
    thickColor: '#333333', thickWidth: 2,
    outerColor: '#000000', outerWidth: 3,
    bgColor: '#ffffff',
    font: 'bold 20px "Segoe UI", Arial, sans-serif',
    numberColor: '#1a1a1a',
  },
  {
    name: '29_wide_padding',
    cell: 56, pad: 60,
    thinColor: '#bfbfbf', thinWidth: 1,
    thickColor: '#333333', thickWidth: 3,
    outerColor: '#000000', outerWidth: 4,
    bgColor: '#ffffff',
    font: 'bold 26px "Segoe UI", Arial, sans-serif',
    numberColor: '#1a1a1a',
  },
  {
    name: '30_no_padding',
    cell: 56, pad: 0,
    thinColor: '#bfbfbf', thinWidth: 1,
    thickColor: '#333333', thickWidth: 3,
    outerColor: '#000000', outerWidth: 4,
    bgColor: '#ffffff',
    font: 'bold 26px "Segoe UI", Arial, sans-serif',
    numberColor: '#1a1a1a',
  },

  // --- 不同谜题 ---
  {
    name: '31_puzzle2_standard',
    cell: 56, pad: 20,
    thinColor: '#bfbfbf', thinWidth: 1,
    thickColor: '#333333', thickWidth: 3,
    outerColor: '#000000', outerWidth: 4,
    bgColor: '#ffffff',
    font: 'bold 26px "Segoe UI", Arial, sans-serif',
    numberColor: '#1a1a1a',
  },
  {
    name: '32_puzzle2_tiny',
    cell: 20, pad: 10,
    thinColor: '#cccccc', thinWidth: 1,
    thickColor: '#555555', thickWidth: 2,
    outerColor: '#000000', outerWidth: 2,
    bgColor: '#ffffff',
    font: 'bold 10px "Segoe UI", Arial, sans-serif',
    numberColor: '#000000',
  },
  {
    name: '33_puzzle3_hard',
    cell: 56, pad: 20,
    thinColor: '#bfbfbf', thinWidth: 1,
    thickColor: '#333333', thickWidth: 3,
    outerColor: '#000000', outerWidth: 4,
    bgColor: '#ffffff',
    font: 'bold 26px "Segoe UI", Arial, sans-serif',
    numberColor: '#1a1a1a',
  },
];

if (!fs.existsSync(OUT_DIR)) {
  fs.mkdirSync(OUT_DIR, { recursive: true });
}

function generateVariant(v) {
  const p = v.puzzle || puzzle;
  const board = SIZE * v.cell;
  const total = board + 2 * v.pad;

  const canvas = createCanvas(total, total);
  const ctx = canvas.getContext('2d');

  // 背景
  ctx.fillStyle = v.bgColor;
  ctx.fillRect(0, 0, total, total);

  // --- 细线 ---
  if (v.thinWidth > 0) {
    ctx.strokeStyle = v.thinColor;
    ctx.lineWidth = v.thinWidth;
    if (v.dashed) { ctx.setLineDash([4, 3]); } else { ctx.setLineDash([]); }
    for (let i = 0; i <= SIZE; i++) {
      ctx.beginPath();
      ctx.moveTo(v.pad + i * v.cell, v.pad);
      ctx.lineTo(v.pad + i * v.cell, v.pad + board);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(v.pad, v.pad + i * v.cell);
      ctx.lineTo(v.pad + board, v.pad + i * v.cell);
      ctx.stroke();
    }
    ctx.setLineDash([]);
  }

  // --- 3x3 粗线 ---
  if (v.thickWidth > 0) {
    ctx.strokeStyle = v.thickColor;
    ctx.lineWidth = v.thickWidth;
    if (v.dashed) { ctx.setLineDash([8, 4]); } else { ctx.setLineDash([]); }
    for (let i = 0; i <= SIZE; i += 3) {
      ctx.beginPath();
      ctx.moveTo(v.pad + i * v.cell, v.pad);
      ctx.lineTo(v.pad + i * v.cell, v.pad + board);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(v.pad, v.pad + i * v.cell);
      ctx.lineTo(v.pad + board, v.pad + i * v.cell);
      ctx.stroke();
    }
    ctx.setLineDash([]);
  }

  // --- 外框 ---
  if (v.outerWidth > 0) {
    ctx.strokeStyle = v.outerColor;
    ctx.lineWidth = v.outerWidth;
    ctx.beginPath();
    ctx.rect(v.pad, v.pad, board, board);
    ctx.stroke();
  }

  // --- 数字 ---
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.font = v.font;
  ctx.fillStyle = v.numberColor;

  for (let r = 0; r < SIZE; r++) {
    for (let c = 0; c < SIZE; c++) {
      const val = p[r * SIZE + c];
      if (val !== 0) {
        const x = v.pad + c * v.cell + v.cell / 2;
        const y = v.pad + r * v.cell + v.cell / 2;
        ctx.fillText(val.toString(), x, y);
      }
    }
  }

  const outPath = path.join(OUT_DIR, `${v.name}.png`);
  fs.writeFileSync(outPath, canvas.toBuffer('image/png'));
  const p2 = v.puzzle || puzzle;
  console.log(`  [OK] ${v.name}.png  (${total}x${total}px) puzzle=[${p2.join(',')}]`);
}

console.log('Generating Sudoku test images...\n');
for (let i = 0; i < variants.length; i++) {
  generateVariant(variants[i]);
}

// 生成索引文件
const indexLines = ['# Sudoku OCR Test Images', '', '| # | File | Size | Style |'];
indexLines.push('|---|------|------|-------|');
for (let i = 0; i < variants.length; i++) {
  const v = variants[i];
  const board = SIZE * v.cell;
  const total = board + 2 * v.pad;
  indexLines.push(`| ${i + 1} | \`${v.name}.png\` | ${total}x${total} | ${v.name.split('_').slice(1).join(' ')} |`);
}
const indexPath = path.join(OUT_DIR, '_README.md');
fs.writeFileSync(indexPath, indexLines.join('\n'));
console.log(`\nDone! ${variants.length} images saved to: ${OUT_DIR}`);
console.log(`Expected answer grid: [${puzzle.join(',')}]`);
