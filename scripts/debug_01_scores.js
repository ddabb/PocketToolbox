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
  
  const grid=sb.processImage(imgData.data,800,800,templates);
  const sigArr=sb.getSigArray();
  const SIG_ROWS=28, SIG_COLS=20, SIG_LEN=560, PENALTY=0.5;
  
  for(const [r,c] of [[1,3],[4,0],[4,8],[7,3],[7,4]]){
    const idx=r*9+c;
    const sig=sigArr[idx];
    if(!sig){console.log('R'+r+'C'+c+': no sig');continue;}
    
    const scores={};
    for(const t of templates){
      let m=0;
      for(let i=0;i<SIG_LEN;i++) if(sig[i]===t.key[i]) m++;
      const s=m-(SIG_LEN-m)*PENALTY;
      if(!scores[t.digit]||s>scores[t.digit]) scores[t.digit]=s;
    }
    console.log('R'+r+'C'+c+': grid='+grid[idx]+' top5: '+Object.entries(scores).sort((a,b)=>b[1]-a[1]).slice(0,5).map(([d,s])=>d+'='+Math.round(s)).join(', '));
  }
}
run().catch(e=>console.error(e));
