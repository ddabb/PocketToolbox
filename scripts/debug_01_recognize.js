const {createCanvas,loadImage}=require('canvas');
const vm=require('vm');
const fs=require('fs');
const path=require('path');
const code=fs.readFileSync(path.join(__dirname,'test_ocr_node.js'),'utf8');
const sb={console,require,Float32Array,Array,Map,Set,Math,JSON,Int32Array,Uint8Array,Uint8ClampedArray,Date,process,Buffer:require('buffer').Buffer,path,fs,createCanvas,loadImage,exports:{},module:{exports:{}}};
vm.runInNewContext(code,sb,{filename:'test_ocr_node.js'});
const tmplData=JSON.parse(fs.readFileSync(path.join(__dirname,'..','entry','src','main','resources','rawfile','digit_templates_extended.json'),'utf8'));
const templates=tmplData.templates.map(t=>({digit:t.digit,key:t.key}));
async function run(){
  const img=await loadImage(path.join(__dirname,'..','sudoku_test_images','01_standard_544.png'));
  const canvas=createCanvas(800,800);
  const ctx=canvas.getContext('2d');
  ctx.fillStyle='#FFFFFF';
  ctx.fillRect(0,0,800,800);
  ctx.drawImage(img,0,0,800,800);
  const imgData=ctx.getImageData(0,0,800,800);
  
  // Monkey-patch recognizeDigit to capture debug info
  const origRecognize = sb.recognizeDigit;
  const debugCells = {};
  sb.recognizeDigit = function(sig, tmpl) {
    const result = origRecognize(sig, tmpl);
    return result;
  };
  
  const grid = sb.processImage(imgData.data, 800, 800, templates);
  const sigArr = sb.getSigArray();
  const SIG_ROWS=28, SIG_COLS=20, SIG_LEN=560, TEMPLATE_MISMATCH_PENALTY=0.3;
  
  for(const [r,c] of [[1,3],[4,0],[4,8],[7,3],[7,4]]){
    const idx=r*9+c;
    const sig=sigArr[idx];
    if(!sig){ console.log('R'+r+'C'+c+': no sig'); continue; }
    const ink=sb.countInk(sig);
    const rd=origRecognize(sig,templates);
    console.log('R'+r+'C'+c+': grid='+grid[idx]+' recognize='+rd+' ink='+ink);
    
    const scores={};
    for(const t of templates){
      let m=0;
      for(let i=0;i<SIG_LEN;i++) if(sig[i]===t.key[i]) m++;
      const s=m-(SIG_LEN-m)*TEMPLATE_MISMATCH_PENALTY;
      if(!scores[t.digit]||s>scores[t.digit]) scores[t.digit]=s;
    }
    console.log('  scores: '+Object.entries(scores).sort((a,b)=>b[1]-a[1]).slice(0,5).map(([d,s])=>d+'='+Math.round(s)).join(', '));
    
    // Check isLikelyNot4 manually
    const midTop=Math.floor(SIG_ROWS*0.25), midBot=Math.floor(SIG_ROWS*0.60);
    let maxSpan=0;
    for(let row=midTop;row<midBot;row++){
      let minC=SIG_COLS, maxC=-1;
      for(let c=0;c<SIG_COLS;c++) if(sig[row*SIG_COLS+c]===1){if(c<minC)minC=c;if(c>maxC)maxC=c;}
      if(maxC>=minC){const span=maxC-minC+1;if(span>maxSpan)maxSpan=span;}
    }
    const hSpanOk=maxSpan>=SIG_COLS*0.30;
    const topRow2=Math.floor(SIG_ROWS*0.15), midRow2=Math.floor(SIG_ROWS*0.45);
    let topLeftInk=0, topRightInk=0;
    for(let rr=topRow2;rr<midRow2;rr++) for(let cc=0;cc<SIG_COLS;cc++) if(sig[rr*SIG_COLS+cc]===1){if(cc<SIG_COLS/2)topLeftInk++;else topRightInk++;}
    console.log('  hSpan='+maxSpan+' threshold='+Math.floor(SIG_COLS*0.30)+' ok='+hSpanOk+' topLeft='+topLeftInk+' topRight='+topRightInk+' isLikelyNot4='+(!hSpanOk||(topLeftInk===0&&topRightInk>0)));
    
    // Print sig visual
    for(let rr=0;rr<7;rr++){
      let line='';
      for(let cc=0;cc<SIG_COLS;cc++) line+=sig[rr*SIG_COLS+cc]?'#':'.';
      console.log('  '+line);
    }
    console.log('  ...');
  }
}
run().catch(e=>console.error(e));
