'use strict';
const fs = require('fs');
const path = require('path');
const { createCanvas, loadImage } = require('canvas');
const ocr = require(path.join(__dirname, 'test_ocr_node.js'));

const WARP_SIZE_MULTIPLIER = 1.1;
const BG_DARK_THRESHOLD = 128;

function warpPerspectiveGray(gray, W, H, corners, outSize, bgVal) {
  const out = new Float32Array(outSize * outSize);
  const srcX = [corners.topLeftX, corners.topRightX, corners.bottomRightX, corners.bottomLeftX];
  const srcY = [corners.topLeftY, corners.topRightY, corners.bottomRightY, corners.bottomLeftY];
  const dstX = [0, outSize-1, outSize-1, 0], dstY = [0, 0, outSize-1, outSize-1];
  const A=[], bVec=[];
  for (let i=0;i<4;i++) {
    A.push([dstX[i],dstY[i],1,0,0,0,-srcX[i]*dstX[i],-srcX[i]*dstY[i]]); bVec.push(srcX[i]);
    A.push([0,0,0,dstX[i],dstY[i],1,-srcY[i]*dstX[i],-srcY[i]*dstY[i]]); bVec.push(srcY[i]);
  }
  for (let col=0;col<8;col++) {
    let maxRow=col; for(let row=col+1;row<8;row++) if(Math.abs(A[row][col])>Math.abs(A[maxRow][col]))maxRow=row;
    [A[col],A[maxRow]]=[A[maxRow],A[col]]; [bVec[col],bVec[maxRow]]=[bVec[maxRow],bVec[col]];
    const p=A[col][col]; if(Math.abs(p)<1e-12)break; for(let j=col;j<8;j++)A[col][j]/=p; bVec[col]/=p;
    for(let row=0;row<8;row++){if(row===col)continue;const f=A[row][col];for(let j=col;j<8;j++)A[row][j]-=f*A[col][j];bVec[row]-=f*bVec[col];}
  }
  const h=bVec;
  for(let oy=0;oy<outSize;oy++) for(let ox=0;ox<outSize;ox++){
    const d=h[6]*ox+h[7]*oy+1; if(Math.abs(d)<1e-8){out[oy*outSize+ox]=128;continue;}
    const sx=(h[0]*ox+h[1]*oy+h[2])/d, sy=(h[3]*ox+h[4]*oy+h[5])/d;
    const ix=Math.floor(sx),iy=Math.floor(sy),fx=sx-ix,fy=sy-iy;
    if(ix>=0&&ix+1<W&&iy>=0&&iy+1<H) out[oy*outSize+ox]=gray[iy*W+ix]*(1-fx)*(1-fy)+gray[iy*W+ix+1]*fx*(1-fy)+gray[(iy+1)*W+ix]*(1-fx)*fy+gray[(iy+1)*W+ix+1]*fx*fy;
    else { const cx=Math.round(sx),cy=Math.round(sy); out[oy*outSize+ox]=(cx>=0&&cx<W&&cy>=0&&cy<H)?gray[cy*W+cx]:bgVal; }
  }
  return out;
}

async function main() {
  const imgPath = process.argv[2] || 'F:\\PocketToolbox\\sudoku_test_images\\01_standard_544.png';
  const img = await loadImage(imgPath);
  const canvas = createCanvas(img.width, img.height);
  const ctx = canvas.getContext('2d');
  ctx.drawImage(img, 0, 0);
  const imgData = ctx.getImageData(0, 0, img.width, img.height);
  const pixels = imgData.data;
  console.log(`Image: ${img.width}x${img.height}`);

  // Use test_ocr_node's bgColor and toGrayArray
  const bg = ocr.bgColor(pixels, img.width, img.height);
  const isDark = bg < BG_DARK_THRESHOLD;
  const gray = ocr.toGrayArray(pixels, img.width, img.height);
  console.log(`bg=${bg.toFixed(1)} isDark=${isDark}`);

  // Find bbox
  const bbox = ocr.findBoardBBox(pixels, img.width, img.height, bg);
  console.log(`bbox: left=${bbox.left} top=${bbox.top} right=${bbox.right} bottom=${bbox.bottom} isDark=${bbox.isDark}`);

  // Use bbox as corners (simplified - same as what ArkTS does for rectangular boards)
  const corners = {
    topLeftX: bbox.left, topLeftY: bbox.top,
    topRightX: bbox.right, topRightY: bbox.top,
    bottomRightX: bbox.right, bottomRightY: bbox.bottom,
    bottomLeftX: bbox.left, bottomLeftY: bbox.bottom,
    confidence: 0.5
  };

  const boardSize = Math.max(bbox.right - bbox.left, bbox.bottom - bbox.top);
  const outSize = Math.round(boardSize * WARP_SIZE_MULTIPLIER);
  console.log(`boardSize=${boardSize} outSize=${outSize}`);

  const warpedGray = warpPerspectiveGray(gray, img.width, img.height, corners, outSize, bg);

  // Estimate warp bg
  let warpBgSum=0,warpBgCnt=0;
  for(let i=0;i<outSize*outSize;i+=Math.max(1,Math.floor(outSize*outSize/20000))){warpBgSum+=warpedGray[i];warpBgCnt++;}
  const warpBg=warpBgCnt>0?warpBgSum/warpBgCnt:BG_DARK_THRESHOLD;
  const warpIsDark=warpBg<BG_DARK_THRESHOLD;
  console.log(`warpBg=${warpBg.toFixed(1)} warpIsDark=${warpIsDark}`);

  // Run detectGridLineWidths on warped image
  // ocr.resetGridLineCrop(); // not exported, skip
  // Need to import detectGridLineWidths... it's not exported. Let me check.
  // Actually, the ocr module exports are: processImage, bgColor, toGrayArray, findBoardBBox, cellSigFromGray, cellSigFromGrayLowThresh, cellSigFromGrayThin, recognizeDigit, countInk, getSigArray, getConstants, grayInkPixel
  // detectGridLineWidths is not exported. I'll need to call it directly.

  // For now, let's just analyze cells WITHOUT detectGridLineWidths first,
  // since the warp path does call it but the main issue may be visible even without it.

  const warpCellW = outSize / 9;
  const warpCellH = outSize / 9;
  console.log(`warpCellW=${warpCellW.toFixed(2)} warpCellH=${warpCellH.toFixed(2)}`);

  // Analyze key cells using cellSigFromGray
  const SIG_ROWS = 28, SIG_COLS = 20, SIG_LEN = SIG_ROWS * SIG_COLS;

  const problemCells = [
    [0,0,'5'],[1,0,'6'],[3,0,'8'],[3,6,'empty(phantom1)'],
    [6,0,'7'],[6,6,'empty(phantom1)'],[7,1,'6'],[7,7,'2'],[7,8,'8'],
    [8,2,'empty'],[8,3,'empty(phantom1)'],[8,4,'empty(phantom1)'],
    [8,8,'empty'],
  ];

  console.log('\n=== Cell analysis on WARPED image ===\n');
  for (const [row, col, note] of problemCells) {
    const cLeft = col * warpCellW;
    const cTop = row * warpCellH;
    // Make a copy since cellSigFromGray modifies gray
    const grayCopy = new Float32Array(warpedGray);
    const sig = ocr.cellSigFromGray(grayCopy, outSize, cLeft, cTop, warpCellW, warpCellH, warpIsDark, warpBg, row, col);
    const inkRatio = ocr.getLastRawInkRatio ? ocr.getLastRawInkRatio() : -1;
    
    if (sig === null) {
      console.log(`R${row}C${col} (${note}): NULL  rawInkRatio=${inkRatio.toFixed(4)}`);
    } else {
      const ink = ocr.countInk(sig);
      console.log(`R${row}C${col} (${note}): sig ink=${ink} rawInkRatio=${inkRatio.toFixed(4)}`);
      // Print signature
      for (let r = 0; r < SIG_ROWS; r++) {
        let l = '  ';
        for (let c = 0; c < SIG_COLS; c++) l += sig[r * SIG_COLS + c] ? '#' : '.';
        console.log(l);
      }
    }
    console.log('');
  }

  // Save warped image for visual inspection
  const outCanvas = createCanvas(outSize, outSize);
  const outCtx = outCanvas.getContext('2d');
  const outImgData = outCtx.createImageData(outSize, outSize);
  for (let i = 0; i < outSize * outSize; i++) {
    const v = Math.max(0, Math.min(255, Math.round(warpedGray[i])));
    outImgData.data[i*4] = v; outImgData.data[i*4+1] = v; outImgData.data[i*4+2] = v; outImgData.data[i*4+3] = 255;
  }
  outCtx.putImageData(outImgData, 0, 0);
  const outPath = path.join('C:', 'Users', '60138546', 'AppData', 'Local', 'Temp', 'deveco', 'warped_01.png');
  fs.writeFileSync(outPath, outCanvas.toBuffer('image/png'));
  console.log(`Warped image saved: ${outPath}`);

  // Also check gray values along grid boundaries
  console.log('\n=== Grid boundary gray values in warped image ===');
  for (let i = 0; i < 10; i++) {
    const lineY = Math.round(i * warpCellH);
    if (lineY >= outSize) continue;
    let sum = 0, cnt = 0;
    for (let x = 0; x < outSize; x++) { sum += warpedGray[lineY * outSize + x]; cnt++; }
    const avg = sum / cnt;
    console.log(`  H-line ${i}: y=${lineY} avg_gray=${avg.toFixed(1)} diff_from_bg=${(warpBg-avg).toFixed(1)}`);
  }
}

main().catch(console.error);
