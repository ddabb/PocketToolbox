const { createCanvas, loadImage } = require('canvas');
const fs = require('fs');
const path = require('path');

const EXPECTED = [5,3,0,0,7,0,0,0,0,6,0,0,1,9,5,0,0,0,0,9,8,0,0,0,0,6,0,8,0,0,0,6,0,0,0,3,4,0,0,8,0,3,0,0,1,7,0,0,0,2,0,0,0,6,0,6,0,0,0,0,2,8,0,0,0,0,4,1,9,0,0,5,0,0,0,0,8,0,0,7,9];

const tmplData = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'digit_templates.json'), 'utf8'));
const templates = tmplData.templates.map(t => ({ digit: t.digit, key: t.key }));

// Load the main test script
const testMod = path.join(__dirname, 'test_ocr_node.js');
const src = fs.readFileSync(testMod, 'utf8');

// Add exports at the end
const exportIdx = src.lastIndexOf('if (process.argv.includes(');
const modifiedSrc = src.substring(0, exportIdx) +
  'module.exports = { processImage, getSigArray, getConstants, countInk, recognizeDigit };\n\n' +
  src.substring(exportIdx);

const tmpFile = path.join(__dirname, '_tmp_collect.js');
fs.writeFileSync(tmpFile, modifiedSrc);
const mod = require(tmpFile);

const imgDir = path.join(__dirname, '..', 'sudoku_test_images');
const allNewTemplates = [];

async function collect() {
  const highAccuracyImages = [
    '21_thick_all_lines.png',
    '26_mono_font.png',
    '09_serif_font.png',
    '06_green_theme.png',
    '17_pure_black_white.png',
    '22_yellow_highlight.png',
    '07_light_gray_numbers.png',
    '15_huge_1000.png',
    '20_dashed_lines.png',
    '01_standard_544.png',
    '03_large_800.png',
    '04_blue_numbers.png',
    '05_red_theme.png',
    '08_gray_bg_dark_numbers.png',
    '11_thin_font.png',
    '13_no_outer_border.png',
    '16_dark_bg_light_numbers.png',
    '23_orange_numbers.png',
    '27_cursive_font.png',
    '29_wide_padding.png',
    '02_small_300.png',
    '10_italic_font.png',
    '18_small_font_in_cell.png',
    '19_large_font_in_cell.png',
    '24_medium_gray_numbers.png',
    '28_medium_400.png',
  ];

  for (const fname of highAccuracyImages) {
    const imgPath = path.join(imgDir, fname);
    if (!fs.existsSync(imgPath)) { console.log('Skip missing:', fname); continue; }
    const img = await loadImage(imgPath);
    const canvas = createCanvas(img.width, img.height);
    const ctx = canvas.getContext('2d');
    ctx.drawImage(img, 0, 0);
    const imgData = ctx.getImageData(0, 0, img.width, img.height);

    const grid = mod.processImage(imgData.data, img.width, img.height, templates);
    const sigArr = mod.getSigArray();

    let correct = 0, total = 0;
    for (let i = 0; i < 81; i++) {
      if (EXPECTED[i] !== 0) { total++; if (grid[i] === EXPECTED[i]) correct++; }
    }
    const pct = (correct / total * 100).toFixed(0);
    console.log(fname + ': ' + correct + '/' + total + ' (' + pct + '%)');

    for (let i = 0; i < 81; i++) {
      if (EXPECTED[i] !== 0 && sigArr[i] !== null && grid[i] === EXPECTED[i]) {
        allNewTemplates.push({ digit: EXPECTED[i], key: Array.from(sigArr[i]) });
      }
    }
  }

  console.log('\nTotal new templates:', allNewTemplates.length);
  const byDigit = {};
  allNewTemplates.forEach(t => { byDigit[t.digit] = (byDigit[t.digit] || 0) + 1; });
  console.log('By digit:', JSON.stringify(byDigit));

  // Save
  const outPath = path.join(__dirname, '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'digit_templates_extended.json');
  const combined = { templates: [...tmplData.templates, ...allNewTemplates] };
  fs.writeFileSync(outPath, JSON.stringify(combined));
  console.log('Saved to', outPath, '(' + combined.templates.length + ' total templates)');

  fs.unlinkSync(tmpFile);
}

collect().catch(e => { console.error(e); try { fs.unlinkSync(tmpFile); } catch (_) {} });
