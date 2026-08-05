// 本地验证OCR像素分析算法（用Node复刻ArkTS逻辑，先调通再移植）
const { createCanvas, loadImage } = require('canvas');
const fs = require('fs');
const path = require('path');

const OUT_DIR = path.join(__dirname, '..', 'sudoku_test_images');

const expected = [
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

const ROWS = 10, COLS = 7;

function grayAt(px, i) { return 0.299*px[i]+0.587*px[i+1]+0.114*px[i+2]; }

// 直方图众数背景（与 ArkTS bgColor 一致）：稳健应对白纸放深色桌面等真实照片
function bgColor(px, W, H) {
  const hist = new Array(256).fill(0);
  const total = W * H;
  const step = Math.max(1, Math.floor(total / 20000));
  for (let i = 0; i < total; i += step) {
    let g = grayAt(px, i * 4); let gi = g < 0 ? 0 : (g > 255 ? 255 : Math.floor(g));
    hist[gi]++;
  }
  let mode = 0, max = -1;
  for (let i = 0; i < 256; i++) if (hist[i] > max) { max = hist[i]; mode = i; }
  return mode;
}

// 封闭空洞纵向中心（与 ArkTS holeCenterRow 一致）：6 圈在下、9 圈在上
function holeCenterRow(sig) {
  const outside = new Array(ROWS * COLS).fill(false);
  const stack = [];
  const pushIfBg = (i) => { if (!outside[i] && sig[i] === 0) { outside[i] = true; stack.push(i); } };
  for (let c = 0; c < COLS; c++) { pushIfBg(c); pushIfBg((ROWS - 1) * COLS + c); }
  for (let r = 0; r < ROWS; r++) { pushIfBg(r * COLS); pushIfBg(r * COLS + (COLS - 1)); }
  while (stack.length) {
    const i = stack.pop(); const r = Math.floor(i / COLS), c = i % COLS;
    if (r > 0) pushIfBg(i - COLS);
    if (r < ROWS - 1) pushIfBg(i + COLS);
    if (c > 0) pushIfBg(i - 1);
    if (c < COLS - 1) pushIfBg(i + 1);
  }
  const visited = new Array(ROWS * COLS).fill(false);
  const comps = [];
  for (let i = 0; i < ROWS * COLS; i++) {
    if (sig[i] === 0 && !outside[i] && !visited[i]) {
      const comp = []; const cs = [i]; visited[i] = true;
      while (cs.length) {
        const j = cs.pop(); comp.push(j);
        const r = Math.floor(j / COLS), c = j % COLS;
        const p2 = (n) => { if (!visited[n] && sig[n] === 0 && !outside[n]) { visited[n] = true; cs.push(n); } };
        if (r > 0) p2(j - COLS);
        if (r < ROWS - 1) p2(j + COLS);
        if (c > 0) p2(j - 1);
        if (c < COLS - 1) p2(j + 1);
      }
      comps.push(comp);
    }
  }
  if (comps.length === 0) return -1;
  comps.sort((a, b) => b.length - a.length);
  if (comps.length >= 2 && comps[1].length > comps[0].length * 0.4) return -1;
  let s = 0; for (const j of comps[0]) s += Math.floor(j / COLS);
  return s / comps[0].length;
}
const HOLE_W = 22, HOLE_SPAN = 4;

async function loadPixels(imgPath) {
  const img = await loadImage(imgPath);
  const W = img.width, H = img.height;
  const cnv = createCanvas(W, H);
  const ctx = cnv.getContext('2d');
  ctx.drawImage(img, 0, 0);
  return { px: ctx.getImageData(0, 0, W, H).data, W, H };
}

// 复现 ArkTS createPixelMap desiredSize:{450,450}：强制拉伸到 450x450
async function loadPixelsAtSize(imgPath, tw, th) {
  const img = await loadImage(imgPath);
  const cnv = createCanvas(tw, th);
  const ctx = cnv.getContext('2d');
  ctx.drawImage(img, 0, 0, tw, th);
  return { px: ctx.getImageData(0, 0, tw, th).data, W: tw, H: th };
}

function findBoardBBox(px, W, H, bg) {
  const isDark = bg < 128;
  const inkThresh = 45;
  const isInk = (g) => isDark ? (g > bg + inkThresh) : (g < bg - inkThresh);
  const colInk = new Array(W).fill(0), rowInk = new Array(H).fill(0);
  for (let x=0;x<W;x++){ let c=0; for(let y=0;y<H;y+=2) if(isInk(grayAt(px,(y*W+x)*4)))c++; colInk[x]=c; }
  for (let y=0;y<H;y++){ let c=0; for(let x=0;x<W;x+=2) if(isInk(grayAt(px,(y*W+x)*4)))c++; rowInk[y]=c; }
  const colFrac = colInk.map(c=>c/(H/2)), rowFrac = rowInk.map(c=>c/(W/2));
  let minX=W,maxX=0,minY=H,maxY=0,found=false;
  for (let x=0;x<W;x++) if(colFrac[x]>0.3){ if(x<minX)minX=x; if(x>maxX)maxX=x; found=true; }
  for (let y=0;y<H;y++) if(rowFrac[y]>0.3){ if(y<minY)minY=y; if(y>maxY)maxY=y; found=true; }
  if (!found || maxX-minX < W*0.3 || maxY-minY < H*0.3)
    return { left:0, top:0, right:W, bottom:H, isDark };
  return { left:minX, top:minY, right:maxX, bottom:maxY, isDark };
}

// 包围盒归一化采样: 在数字墨迹包围盒上采样 ROWSxCOLS
function cellSig(px, W, left, top, cw, ch, isDark, bg) {
  const mx=cw*0.08, my=ch*0.08;
  const x0=Math.floor(left+mx), y0=Math.floor(top+my);
  const x1=Math.floor(left+cw-mx), y1=Math.floor(top+ch-my);
  const inkThresh=45;
  const isInk=(g)=> isDark ? (g>bg+inkThresh) : (g<bg-inkThresh);
  let ink=0, area=0;
  let bminX=1e9,bmaxX=-1,bminY=1e9,bmaxY=-1;
  for (let y=y0;y<y1;y++) for (let x=x0;x<x1;x++){
    area++; const g=grayAt(px,(y*W+x)*4);
    if (isInk(g)){ ink++; if(x<bminX)bminX=x; if(x>bmaxX)bmaxX=x; if(y<bminY)bminY=y; if(y>bmaxY)bmaxY=y; }
  }
  if (ink < area*0.02 || bmaxX<0) return null;
  const bw=bmaxX-bminX+1, bh=bmaxY-bminY+1;
  const sig = new Array(ROWS*COLS).fill(0);
  for (let r=0;r<ROWS;r++) for (let c=0;c<COLS;c++){
    const sx0=bminX+Math.floor(bw*c/COLS), sx1=bminX+Math.floor(bw*(c+1)/COLS);
    const sy0=bminY+Math.floor(bh*r/ROWS), sy1=bminY+Math.floor(bh*(r+1)/ROWS);
    let s=0,n=0;
    for (let y=sy0;y<sy1;y++) for (let x=sx0;x<sx1;x++){ s+=grayAt(px,(y*W+x)*4); n++; }
    sig[r*COLS+c] = isInk(n>0?s/n:bg) ? 1 : 0;
  }
  const inkCount = sig.reduce((a,v)=>a+v,0);
  if (inkCount < 6 || inkCount > ROWS*COLS-4) return null;
  return sig;
}

function buildTemplates(refPx, refW, refH, refBg, refExpected) {
  const bbox = findBoardBBox(refPx, refW, refH, refBg);
  const cw=(bbox.right-bbox.left)/9, ch=(bbox.bottom-bbox.top)/9;
  const buckets = {};
  for (let i=0;i<81;i++){
    if (refExpected[i]===0) continue;
    const r=Math.floor(i/9), c=i%9;
    const sig = cellSig(refPx, refW, bbox.left+c*cw, bbox.top+r*ch, cw, ch, bbox.isDark, refBg);
    if (!sig) continue;
    (buckets[refExpected[i]] = buckets[refExpected[i]] || []).push(sig);
  }
  const tpls = [];
  for (let d=1; d<=9; d++) {
    const arr = buckets[d] || [];
    if (arr.length === 0) { tpls.push({ d, k: new Array(ROWS*COLS).fill(0), n:0, hole:-1 }); continue; }
    const k = new Array(ROWS*COLS).fill(0);
    for (let p=0;p<ROWS*COLS;p++){ let on=0; for (const s of arr) if (s[p]===1) on++; k[p]=on>=arr.length*0.5?1:0; }
    tpls.push({ d, k, n: arr.length, hole: holeCenterRow(k) });
  }
  return tpls;
}

function recognize(sig, templates) {
  const inkCount = sig.reduce((a,v)=>a+v,0);
  const qHole = holeCenterRow(sig);
  let bestIdx=0, bestScore=-1e9, secondIdx=0, secondScore=-1e9; const scores=[];
  for (let ti=0; ti<templates.length; ti++) {
    const t = templates[ti];
    if (t.n===0) continue;
    let match=0, tplInk=0, tp=0;
    for (let i=0;i<ROWS*COLS;i++){ if(t.k[i]===1){ tplInk++; if(sig[i]===1) tp++; } if(sig[i]===t.k[i]) match++; }
    const recall=tplInk>0?tp/tplInk:0, prec=inkCount>0?tp/inkCount:0;
    const f1=(recall+prec>0)?2*recall*prec/(recall+prec):0;
    const score=match-(ROWS*COLS-match)*0.5+f1*40;
    scores.push({ d:t.d, score:Math.round(score) });
    if (score>bestScore){ secondIdx=bestIdx; secondScore=bestScore; bestIdx=ti; bestScore=score; }
    else if (score>secondScore){ secondIdx=ti; secondScore=score; }
  }
  // 6/9 特征裁决：仅当轮廓竞争在 6 与 9 之间时用圈半区打破对称
  if (qHole>=0 && bestScore>=12) {
    const halfOf=(h)=>(h<0?0:(h<4.5?1:(h>4.5?2:0)));
    const bh=halfOf(templates[bestIdx].hole), sh=halfOf(templates[secondIdx].hole);
    if (bh!==0 && sh!==0 && bh!==sh) {
      const qh=qHole<4.5?1:2;
      if (qh===sh) bestIdx=secondIdx;
    }
  }
  const best = templates[bestIdx] ? templates[bestIdx].d : 0;
  scores.sort((a,b)=>b.score-a.score);
  return { digit: bestScore>=12?best:0, scores };
}

function analyze(px, W, H, templates) {
  const bg = bgColor(px, W, H);
  const bbox = findBoardBBox(px, W, H, bg);
  const cw=(bbox.right-bbox.left)/9, ch=(bbox.bottom-bbox.top)/9;
  const grid=new Array(81).fill(0);
  for (let r=0;r<9;r++) for (let c=0;c<9;c++){
    const sig = cellSig(px, W, bbox.left+c*cw, bbox.top+r*ch, cw, ch, bbox.isDark, bg);
    if (sig) grid[r*9+c] = recognize(sig, templates).digit;
  }
  return grid;
}

(async () => {
  const files = fs.readdirSync(OUT_DIR).filter(f=>f.endsWith('.png')).sort();
  const ref = await loadPixels(path.join(OUT_DIR, '01_standard_544.png'));
  const refBg = bgColor(ref.px, ref.W, ref.H);
  const templates = buildTemplates(ref.px, ref.W, ref.H, refBg, expected);
  const DEBUG = process.env.DEBUG==='1';
  if (DEBUG) {
    for (const t of templates){ console.log(`TPLARR ${t.d}: [${t.k.join(',')}]`); }
  }
  let totalRight=0, totalCells=0;
  let totalRight450=0, totalCells450=0;
  for (const f of files) {
    const { px, W, H } = await loadPixels(path.join(OUT_DIR, f));
    const g = analyze(px, W, H, templates);
    let right=0, filled=0;
    for (let i=0;i<81;i++){ if(expected[i]!==0){ totalCells++; filled++; if(g[i]===expected[i]) right++; } }
    totalRight+=right;
    console.log(`${f.padEnd(28)} ${right}/${filled} (${(right/filled*100).toFixed(0)}%)  grid=[${g.join('')}]`);

    // 复现 ArkTS 450x450 路径
    const s = await loadPixelsAtSize(path.join(OUT_DIR, f), 450, 450);
    const g450 = analyze(s.px, s.W, s.H, templates);
    let r450=0, f450=0;
    for (let i=0;i<81;i++){ if(expected[i]!==0){ totalCells450++; f450++; if(g450[i]===expected[i]) r450++; } }
    totalRight450+=r450;
    console.log(`   @450x450          ${r450}/${f450} (${(r450/f450*100).toFixed(0)}%)  grid=[${g450.join('')}]`);
  }
  console.log(`\nOverall native : ${totalRight}/${totalCells} (${(totalRight/totalCells*100).toFixed(0)}%)`);
  console.log(`Overall 450x450: ${totalRight450}/${totalCells450} (${(totalRight450/totalCells450*100).toFixed(0)}%)`);
})();
