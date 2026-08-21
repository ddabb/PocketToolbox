const sharp = require('sharp');
const path = require('path');
const fs = require('fs');

const INK_THRESH = 50;
const BG_DARK_THRESHOLD = 128;
const TARGET_CELL_PX = 100;

const TEST_IMAGES = {
  '01_standard_544': { file: '01_standard_544.png' },
  '02_small_300': { file: '02_small_300.png' },
  '03_large_800': { file: '03_large_800.png' },
  '04_blue_numbers': { file: '04_blue_numbers.png' },
  '05_red_theme': { file: '05_red_theme.png' },
  '06_green_theme': { file: '06_green_theme.png' },
  '07_light_gray_numbers': { file: '07_light_gray_numbers.png' },
  '08_gray_bg_dark_numbers': { file: '08_gray_bg_dark_numbers.png' },
  '09_serif_font': { file: '09_serif_font.png' },
  '10_italic_font': { file: '10_italic_font.png' },
  '11_thin_font': { file: '11_thin_font.png' },
  '12_all_thin_lines': { file: '12_all_thin_lines.png' },
  '13_no_outer_border': { file: '13_no_outer_border.png' },
  '14_tiny_200': { file: '14_tiny_200.png' },
  '15_huge_1000': { file: '15_huge_1000.png' },
};

const IMG_DIR = path.join(__dirname, '..', 'sudoku_test_images');

function grayInkPixel(g, bg, isDark, thresh) {
  return isDark ? (g > bg + thresh) : (g < bg - thresh);
}

function bgColor(pixels, w, h) {
  const step = Math.max(1, Math.floor(w * h / 5000));
  const hist = new Array(256).fill(0);
  for (let i = 0; i < w * h; i += step) {
    const r = pixels[i * 4], g = pixels[i * 4 + 1], b = pixels[i * 4 + 2];
    const gray = Math.round(0.299 * r + 0.587 * g + 0.114 * b);
    if (gray >= 0 && gray <= 255) hist[gray]++;
  }
  let maxCount = 0, maxGray = 255;
  for (let i = 0; i < 256; i++) {
    if (hist[i] > maxCount) { maxCount = hist[i]; maxGray = i; }
  }
  return maxGray;
}

function toGrayArray(pixels, w, h) {
  const gray = new Float32Array(w * h);
  for (let i = 0; i < w * h; i++) {
    gray[i] = 0.299 * pixels[i * 4] + 0.587 * pixels[i * 4 + 1] + 0.114 * pixels[i * 4 + 2];
  }
  return gray;
}

function findBoardBBox(gray, w, h, bg, isDark) {
  const thresh = isDark ? bg + INK_THRESH : bg - INK_THRESH;
  let minX = w, maxX = 0, minY = h, maxY = 0;
  const step = 2;
  for (let y = 0; y < h; y += step) {
    for (let x = 0; x < w; x += step) {
      const g = gray[y * w + x];
      const isInk = isDark ? (g > thresh) : (g < thresh);
      if (isInk) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  return { left: minX, top: minY, right: maxX + 1, bottom: maxY + 1 };
}

function profileHLineAtY(gray, imgW, y, x0, x1, bg, isDark) {
  const span = x1 - x0 + 1;
  if (span < 5) return { inkPct: 0 };
  let inkCount = 0;
  for (let x = x0; x <= x1; x++) {
    if (grayInkPixel(gray[y * imgW + x], bg, isDark, INK_THRESH)) inkCount++;
  }
  return { inkPct: inkCount / span, inkCount, span };
}

function profileVLineAtX(gray, imgW, x, y0, y1, bg, isDark) {
  const span = y1 - y0 + 1;
  if (span < 5) return { inkPct: 0 };
  let inkCount = 0;
  for (let y = y0; y <= y1; y++) {
    if (grayInkPixel(gray[y * imgW + x], bg, isDark, INK_THRESH)) inkCount++;
  }
  return { inkPct: inkCount / span, inkCount, span };
}

function detectGridLineWidths(gray, imgW, boardL, boardT, boardR, boardB, isDark, bg) {
  const cellW = (boardR - boardL) / 9;
  const cellH = (boardB - boardT) / 9;
  const imgH = Math.floor(gray.length / imgW);

  const hLineInfo = [];
  const vLineInfo = [];

  for (let i = 0; i < 10; i++) {
    const lineY = Math.round(boardT + i * cellH);
    const bandCenter = lineY;
    const bandHalf = Math.max(3, Math.floor(cellH * 0.15));
    const yStart = Math.max(0, bandCenter - bandHalf);
    const yEnd = Math.min(imgH - 1, bandCenter + bandHalf);

    const innerX0 = Math.floor(boardL + cellW * 0.15);
    const innerX1 = Math.floor(boardR - cellW * 0.15);

    const rowProfiles = [];
    for (let y = yStart; y <= yEnd; y++) {
      const prof = profileHLineAtY(gray, imgW, y, innerX0, innerX1, bg, isDark);
      rowProfiles.push({ y, inkPct: prof.inkPct });
    }

    let maxInkPct = 0;
    let bestY = lineY;
    for (const rp of rowProfiles) {
      if (rp.inkPct > maxInkPct) { maxInkPct = rp.inkPct; bestY = rp.y; }
    }

    if (maxInkPct < 0.15) {
      hLineInfo.push({ found: false, maxInkPct, lineY, bestY });
      continue;
    }

    const inkRows = rowProfiles.filter(rp => rp.inkPct >= maxInkPct * 0.5);
    const inkYs = inkRows.map(rp => rp.y);
    const topInkY = Math.min(...inkYs);
    const botInkY = Math.max(...inkYs);
    const inkBandH = botInkY - topInkY + 1;

    const aboveCell = lineY > boardT ? lineY - 1 : lineY;
    const belowCell = lineY < boardB ? lineY + 1 : lineY;
    const marginAbove = Math.max(0, topInkY - (aboveCell - Math.floor(cellH * 0.1)));
    const marginBelow = Math.max(0, (belowCell + Math.floor(cellH * 0.1)) - botInkY);

    hLineInfo.push({
      found: true, lineY, bestY, maxInkPct,
      topInkY, botInkY, inkBandH,
      marginAbove: topInkY - lineY,
      marginBelow: botInkY - lineY,
      inkUp: lineY - topInkY,
      inkDown: botInkY - lineY,
    });
  }

  for (let j = 0; j < 10; j++) {
    const lineX = Math.round(boardL + j * cellW);
    const bandHalf = Math.max(3, Math.floor(cellW * 0.15));
    const xStart = Math.max(0, lineX - bandHalf);
    const xEnd = Math.min(imgW - 1, lineX + bandHalf);

    const innerY0 = Math.floor(boardT + cellH * 0.15);
    const innerY1 = Math.floor(boardB - cellH * 0.15);

    const colProfiles = [];
    for (let x = xStart; x <= xEnd; x++) {
      const prof = profileVLineAtX(gray, imgW, x, innerY0, innerY1, bg, isDark);
      colProfiles.push({ x, inkPct: prof.inkPct });
    }

    let maxInkPct = 0;
    let bestX = lineX;
    for (const cp of colProfiles) {
      if (cp.inkPct > maxInkPct) { maxInkPct = cp.inkPct; bestX = cp.x; }
    }

    if (maxInkPct < 0.15) {
      vLineInfo.push({ found: false, maxInkPct, lineX, bestX });
      continue;
    }

    const inkCols = colProfiles.filter(cp => cp.inkPct >= maxInkPct * 0.5);
    const inkXs = inkCols.map(cp => cp.x);
    const leftInkX = Math.min(...inkXs);
    const rightInkX = Math.max(...inkXs);
    const inkBandW = rightInkX - leftInkX + 1;

    vLineInfo.push({
      found: true, lineX, bestX, maxInkPct,
      leftInkX, rightInkX, inkBandW,
      inkLeft: lineX - leftInkX,
      inkRight: rightInkX - lineX,
    });
  }

  return { hLineInfo, vLineInfo, cellW, cellH };
}

function computeCropMargins(hLineInfo, vLineInfo, cellW, cellH) {
  const margins = [];
  for (let row = 0; row < 9; row++) {
    for (let col = 0; col < 9; col++) {
      const topI = hLineInfo[row];
      const botI = hLineInfo[row + 1];
      const leftI = vLineInfo[col];
      const rightI = vLineInfo[col + 1];

      const marginT = topI.found ? (topI.inkDown + 1) : 0;
      const marginB = botI.found ? (botI.inkUp + 1) : 0;
      const marginL = leftI.found ? (leftI.inkRight + 1) : 0;
      const marginR = rightI.found ? (rightI.inkLeft + 1) : 0;

      const maxM = Math.floor(Math.min(cellW, cellH) * 0.45);
      const minM = Math.max(1, Math.floor(Math.min(cellW, cellH) * 0.05));

      const cropTop = Math.min(marginT, maxM);
      const cropBot = Math.min(marginB, maxM);
      const cropLeft = Math.min(marginL, maxM);
      const cropRight = Math.min(marginR, maxM);

      const mx = Math.max(cropLeft, cropRight, minM);
      const my = Math.max(cropTop, cropBot, minM);

      margins.push({ row, col, marginT, marginB, marginL, marginR, mx, my,
        innerW: Math.floor(cellW - 2 * mx),
        innerH: Math.floor(cellH - 2 * my)
      });
    }
  }
  return margins;
}

async function testImage(name, config) {
  const imgPath = path.join(IMG_DIR, config.file);
  if (!fs.existsSync(imgPath)) {
    console.log(`  SKIP: ${imgPath} not found`);
    return;
  }

  const meta = await sharp(imgPath).metadata();
  const origW = meta.width;
  const origH = meta.height;
  const scale = TARGET_CELL_PX / (Math.min(origW, origH) / 9);
  const targetW = Math.round(origW * scale);
  const targetH = Math.round(origH * scale);

  const imgData = await sharp(imgPath)
    .resize(targetW, targetH)
    .raw()
    .toBuffer();

  const w = targetW, h = targetH;
  const bg = bgColor(imgData, w, h);
  const isDark = bg < BG_DARK_THRESHOLD;
  const gray = toGrayArray(imgData, w, h);
  const bbox = findBoardBBox(gray, w, h, bg, isDark);

  console.log(`\n=== ${name} (${origW}x${origH} → ${w}x${h}) ===`);
  console.log(`  bg=${bg.toFixed(1)} isDark=${isDark}`);
  console.log(`  bbox: [${bbox.left},${bbox.top},${bbox.right},${bbox.bottom}] = ${bbox.right-bbox.left}x${bbox.bottom-bbox.top}`);

  const cellW = (bbox.right - bbox.left) / 9;
  const cellH = (bbox.bottom - bbox.top) / 9;
  console.log(`  cellSize: ${cellW.toFixed(1)}x${cellH.toFixed(1)}`);

  const result = detectGridLineWidths(gray, w, bbox.left, bbox.top, bbox.right, bbox.bottom, isDark, bg);

  console.log(`\n  Horizontal grid lines:`);
  for (let i = 0; i < 10; i++) {
    const info = result.hLineInfo[i];
    const isBoxBorder = (i === 0 || i === 3 || i === 6 || i === 9);
    if (info.found) {
      console.log(`    H[${i}] y=${info.lineY} band=[${info.topInkY}..${info.botInkY}] h=${info.inkBandH}px inkUp=${info.inkUp} inkDown=${info.inkDown} maxPct=${(info.maxInkPct*100).toFixed(0)}% ${isBoxBorder ? '★BOX' : '  cell'}`);
    } else {
      console.log(`    H[${i}] y=${info.lineY} NOT FOUND (maxPct=${(info.maxInkPct*100).toFixed(0)}%) ${isBoxBorder ? '★BOX' : '  cell'}`);
    }
  }

  console.log(`\n  Vertical grid lines:`);
  for (let j = 0; j < 10; j++) {
    const info = result.vLineInfo[j];
    const isBoxBorder = (j === 0 || j === 3 || j === 6 || j === 9);
    if (info.found) {
      console.log(`    V[${j}] x=${info.lineX} band=[${info.leftInkX}..${info.rightInkX}] w=${info.inkBandW}px inkLeft=${info.inkLeft} inkRight=${info.inkRight} maxPct=${(info.maxInkPct*100).toFixed(0)}% ${isBoxBorder ? '★BOX' : '  cell'}`);
    } else {
      console.log(`    V[${j}] x=${info.lineX} NOT FOUND (maxPct=${(info.maxInkPct*100).toFixed(0)}%) ${isBoxBorder ? '★BOX' : '  cell'}`);
    }
  }

  const margins = computeCropMargins(result.hLineInfo, result.vLineInfo, cellW, cellH);
  console.log(`\n  Cell crop margins (sample):`);
  const sampleCells = [[0,0],[0,4],[0,8],[3,3],[4,4],[8,8]];
  for (const [r, c] of sampleCells) {
    const m = margins[r * 9 + c];
    console.log(`    [${r},${c}] T=${m.marginT} B=${m.marginB} L=${m.marginL} R=${m.marginR} → mx=${m.mx} my=${m.my} inner=${m.innerW}x${m.innerH}`);
  }

  let innerMin = 9999, innerMax = 0;
  for (const m of margins) {
    const inner = Math.min(m.innerW, m.innerH);
    if (inner < innerMin) innerMin = inner;
    if (inner > innerMax) innerMax = inner;
  }
  console.log(`  Inner region range: ${innerMin}..${innerMax}px`);
}

async function main() {
  const args = process.argv.slice(2);
  let imageNames = null;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--image' && args[i + 1]) {
      imageNames = [args[i + 1]];
      i++;
    } else if (args[i] === '--all') {
      imageNames = Object.keys(TEST_IMAGES);
    }
  }

  if (!imageNames) {
    imageNames = ['01_standard_544', '02_small_300', '04_blue_numbers', '12_all_thin_lines', '14_tiny_200'];
  }

  for (const name of imageNames) {
    const config = TEST_IMAGES[name];
    if (!config) { console.log(`Unknown image: ${name}`); continue; }
    try {
      await testImage(name, config);
    } catch (e) {
      console.log(`  ERROR: ${name}: ${e.message}`);
    }
  }
}

main();
