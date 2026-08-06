// Full pipeline replica: findBoardBBox(long-run) -> cellSigFromGray -> recognizeDigit.
// Validates photos.jpg accuracy with the strategy we'll port to .ets.
const { createCanvas, loadImage } = require('canvas');
const path = require('path');
const TEMPLATES = [
  { digit: 1, key: [0,0,0,0,0,1,1,0,0,0,1,1,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1] },
  { digit: 2, key: [0,0,0,1,1,0,0,0,1,1,1,1,1,1,0,1,1,1,1,1,1,0,0,0,0,0,1,1,0,0,0,0,1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1] },
  { digit: 3, key: [0,1,1,1,1,1,0,0,1,1,1,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,0,1,1,1,1,1,0,0,0,1,1,1,1,1,0,0,0,0,0,1,1,0,0,0,0,0,1,1,1,1,1,1,1,1,1,0,1,1,1,1,0,0] },
  { digit: 4, key: [0,0,0,0,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,0,0,0,1,1,1,1,0,0,1,1,0,1,1,0,0,1,1,0,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,0,0,0,0,0,1,1,0] },
  { digit: 5, key: [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,1,1,1,0,1,1,1,1,1,1,1,0,0,0,0,0,1,1,1,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0] },
  { digit: 6, key: [0,0,0,1,1,1,0,0,0,1,1,1,1,1,0,1,1,1,0,0,0,0,1,1,0,1,0,0,1,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,0,0,1,1,0,1,1,0,0,1,1,0,1,1,1,1,1,1,0,0,1,1,1,0,0] },
  { digit: 7, key: [1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,0,0,0,0,0,1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,0,0,0,0,0,1,1,0,0,0] },
  { digit: 8, key: [0,0,0,1,1,0,0,0,1,1,1,1,1,0,0,1,1,0,1,1,1,0,1,1,0,0,1,1,0,1,1,1,1,1,0,0,1,1,1,1,1,0,1,1,1,0,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,0] },
  { digit: 9, key: [0,0,1,1,1,0,0,0,1,1,1,1,1,0,1,1,1,0,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,0,0,0,0,0,1,1,0,0,0,0,1,1,1,0,1,1,1,1,1,0,0,1,1,1,1,0,0] },
];
const SIG_ROWS=10,SIG_COLS=7,INK_THRESH=50;
function holeCenterRow(sig){const R=SIG_ROWS,C=SIG_COLS,o=new Array(R*C).fill(false),st=[],p=i=>{if(!o[i]&&sig[i]===0){o[i]=true;st.push(i);}};
  for(let c=0;c<C;c++){p(c);p((R-1)*C+c);}for(let r=0;r<R;r++){p(r*C);p(r*C+(C-1));}
  while(st.length){const i=st.pop(),r=Math.floor(i/C),c=i%C;if(r>0)p(i-C);if(r<R-1)p(i+C);if(c>0)p(i-1);if(c<C-1)p(i+1);}
  const v=new Array(R*C).fill(false),cm=[];for(let i=0;i<R*C;i++)if(sig[i]===0&&!o[i]&&!v[i]){const a=[i];v[i]=true;while(a.length){const j=a.pop(),r=Math.floor(j/C),c=j%C;const q=n=>{if(!v[n]&&sig[n]===0&&!o[n]){v[n]=true;a.push(n);}};if(r>0)q(j-C);if(r<R-1)q(j+C);if(c>0)q(j-1);if(c<C-1)q(j+1);}cm.push(a);}
  if(!cm.length)return -1;cm.sort((a,b)=>b.length-a.length);if(cm.length>=2&&cm[1].length>cm[0].length*0.4)return -1;let s=0;for(const j of cm[0])s+=Math.floor(j/C);return s/cm[0].length;}
const TPL_HOLE_ROW=TEMPLATES.map(t=>holeCenterRow(t.key));
function countInk(s){let c=0;for(let i=0;i<s.length;i++)if(s[i]===1)c++;return c;}
function grayInk(g,bg,isDark,thr){return isDark?g>bg+thr:g<bg-thr;}
function loopVC(s){let su=0,c=0;for(let r=2;r<8;r++)for(let cc=0;cc<SIG_COLS;cc++)if(s[r*SIG_COLS+cc]===1){su+=r;c++;}return c?su/c:5;}
function recog(s,ik){if(ik<6)return 0;const q=holeCenterRow(s);let bi=0,bs=-1e9,si=0,ss=-1e9;
  for(let t=0;t<TEMPLATES.length;t++){const k=TEMPLATES[t].key;let m=0,ti=0,tp=0;for(let i=0;i<70;i++){if(k[i]===1){ti++;if(s[i]===1)tp++;}if(s[i]===k[i])m++;}
    const rc=ti?tp/ti:0,pc=ik?tp/ik:0,f1=(rc+pc)?2*rc*pc/(rc+pc):0,sc=m-(70-m)*0.5+f1*40;
    if(sc>bs){si=bi;ss=bs;bi=t;bs=sc;}else if(sc>ss){si=t;ss=sc;}}
  const bd=TEMPLATES[bi].digit;if(bd===6||bd===9){if(q>=0)return q>4.5?6:9;return loopVC(s)>4.4?6:9;}
  if(q>=0&&bs>=12){const hf=h=>h<0?0:(h<=4.5?1:2);const bh=hf(TPL_HOLE_ROW[bi]),sh=hf(TPL_HOLE_ROW[si]);if(bh&&sh&&bh!==sh){const qh=hf(q);if(qh&&qh===sh)bi=si;}}
  return bs>=12?TEMPLATES[bi].digit:0;}
function otsu(h,tot){let sa=0;for(let i=0;i<256;i++)sa+=i*h[i];let sb=0,wb=0,mv=-1,th=128;
  for(let t=0;t<256;t++){wb+=h[t];if(!wb)continue;const wf=tot-wb;if(!wf)break;sb+=t*h[t];const mb=sb/wb,mf=(sa-sb)/wf,d=mb-mf,v=wb*wf*d*d;if(v>mv){mv=v;th=t;}}return th;}
function cellSig(gray,W,cl,ct,cw,ch,isDark,bg){const mx=cw*0.08,my=ch*0.08,x0=Math.floor(cl+mx),y0=Math.floor(ct+my),x1=Math.floor(cl+cw-mx),y1=Math.floor(ct+ch-my);
  const H=Math.floor(gray.length/W);let ink=0,area=0,bx0=1e9,bx1=-1,by0=1e9,by1=-1;
  for(let y=y0;y<y1;y++)for(let x=x0;x<x1;x++){area++;const g=gray[y*W+x];if(grayInk(g,bg,isDark,INK_THRESH)){ink++;if(x<bx0)bx0=x;if(x>bx1)bx1=x;if(y<by0)by0=y;if(y>by1)by1=y;}}
  if(ink<area*0.02||bx1<0)return null;const bw=bx1-bx0+1,bh=by1-by0+1;
  const sig=new Array(70).fill(0);
  for(let r=0;r<10;r++)for(let c=0;c<7;c++){const sx0=bx0+Math.floor(bw*c/7),sx1=bx0+Math.floor(bw*(c+1)/7),sy0=by0+Math.floor(bh*r/10),sy1=by0+Math.floor(bh*(r+1)/10);
    let s=0,n=0;for(let y=sy0;y<sy1;y++)for(let x=sx0;x<sx1;x++){if(y>=0&&y<H&&x>=0&&x<W){s+=gray[y*W+x];n++;}}const a=n?s/n:bg;sig[r*7+c]=grayInk(a,bg,isDark,INK_THRESH)?1:0;}
  const ik=countInk(sig);if(ik<6||ik>66){const hist=new Array(256).fill(0);let tot=0;
    for(let y=by0;y<by0+bh;y++)for(let x=bx0;x<bx0+bw;x++){if(y>=0&&y<H&&x>=0&&x<W){const gi=Math.floor(gray[y*W+x]);if(gi>=0&&gi<=255){hist[gi]++;tot++;}}}
    if(tot>=30){const ot=otsu(hist,tot);if(Math.abs(ot-bg)>=12){const fs=new Array(70).fill(0);
      for(let r=0;r<10;r++)for(let c=0;c<7;c++){const sx0=bx0+Math.floor(bw*c/7),sx1=bx0+Math.floor(bw*(c+1)/7),sy0=by0+Math.floor(bh*r/10),sy1=by0+Math.floor(bh*(r+1)/10);let s=0,n=0;
        for(let y=sy0;y<sy1;y++)for(let x=sx0;x<sx1;x++){if(y>=0&&y<H&&x>=0&&x<W){s+=gray[y*W+x];n++;}}const a=n?s/n:bg;fs[r*7+c]=isDark?(a>ot?1:0):(a<ot?1:0);}
      const fbc=countInk(fs);if(fbc>=6&&fbc<=66)return fs;}}return null;}
  return sig;}
function toGray(px,W,H){const g=new Float32Array(W*H);for(let i=0;i<W*H;i++)g[i]=0.299*px[i*4]+0.587*px[i*4+1]+0.114*px[i*4+2];return g;}
function bgColor(px,W,H){const h=new Array(256).fill(0),s=Math.max(1,Math.floor(W*H/5000));for(let i=0;i<W*H;i+=s){const v=Math.floor(0.299*px[i*4]+0.587*px[i*4+1]+0.114*px[i*4+2]);if(v>=0&&v<=255)h[v]++;}let m=-1,mi=128;for(let i=0;i<256;i++)if(h[i]>m){m=h[i];mi=i;}return mi;}
function resize(px,W,H,m){let tw=W,th=H;if(W>m||H>m){const sc=m/Math.max(W,H);tw=Math.round(W*sc);th=Math.round(H*sc);}const c=createCanvas(th,th),x=c.getContext('2d'),t=createCanvas(W,H),y=t.getContext('2d');const d=new Uint8ClampedArray(W*H*4);for(let i=0;i<W*H*4;i++)d[i]=px[i];y.putImageData(new(require('canvas').ImageData)(d,W,H),0,0);x.drawImage(t,0,0,tw,th);return{px:x.getImageData(0,0,tw,th).data,W:tw,H:th};}
const EXP=[5,3,0,0,7,0,0,0,0,6,0,0,1,9,5,0,0,0,0,9,8,0,0,0,0,6,0,8,0,0,0,6,0,0,0,3,4,0,0,8,0,3,0,0,1,7,0,0,0,2,0,0,0,6,0,6,0,0,0,0,2,8,0,0,0,0,4,1,9,0,0,5,0,0,0,0,8,0,0,7,9];

// ---- long-run board locator (the strategy to port) ----
function findBoxLongRun(gray,W,H,isDark){
  const thrLo=isDark?9999:(bg=>Math.min(80,bg-60)); // placeholder, use absolute below
  const abs=80; // absolute: black lines on white paper
  const ink=new Uint8Array(W*H);
  for(let i=0;i<W*H;i++)ink[i]= isDark ? (gray[i]>150?1:0) : (gray[i]<abs?1:0);
  const keep=new Uint8Array(W*H);
  const MINRUN=Math.max(20,Math.floor(Math.min(W,H)*0.10));
  for(let y=0;y<H;y++){let run=0,start=0;for(let x=0;x<=W;x++){if(x<W&&ink[y*W+x]){if(run===0)start=x;run++;}else{if(run>=MINRUN&&start>0&&x<W){for(let xx=start;xx<x;xx++)keep[y*W+xx]=1;}run=0;}}}
  for(let x=0;x<W;x++){let run=0,start=0;for(let y=0;y<H;y++){if(ink[y*W+x]){if(run===0)start=y;run++;}else{if(run>=MINRUN&&start>0&&y<H){for(let yy=start;yy<y;yy++)keep[yy*W+x]=1;}run=0;}}}
  let minX=W,maxX=0,minY=H,maxY=0,n=0;for(let y=0;y<H;y++)for(let x=0;x<W;x++)if(keep[y*W+x]){n++;if(x<minX)minX=x;if(x>maxX)maxX=x;if(y<minY)minY=y;if(y>maxY)maxY=y;}
  if(n<50)return null;
  const bw=maxX-minX+1,bh=maxY-minY+1;
  if(bw<20||bh<20)return null;
  const aspect=bw/bh;
  if(aspect<0.5||aspect>2.0)return null;
  return {left:minX,top:minY,right:maxX,bottom:maxY,isDark};
}

function accOf(gray,W,bg,box){
  const isDark=bg<128;const cw=(box.right-box.left)/9,ch=(box.bottom-box.top)/9;const grid=new Array(81).fill(0);
  for(let r=0;r<9;r++)for(let c=0;c<9;c++){const s=cellSig(gray,W,box.left+c*cw,box.top+r*ch,cw,ch,isDark,bg);if(s)grid[r*9+c]=recog(s,countInk(s));}
  let e=0,t=0;for(let i=0;i<81;i++)if(EXP[i]!==0){t++;if(grid[i]!==EXP[i])e++;}
  return{t,corr:t-e,acc:100*(t-e)/t,grid};
}

(async()=>{
  const img=await loadImage(path.join(__dirname,'..','entry/src/main/resources/rawfile/sudoku_test_images/photos.jpg'));
  const c=createCanvas(img.width,img.height),x=c.getContext('2d');x.drawImage(img,0,0);
  const orig=x.getImageData(0,0,img.width,img.height).data;const rs=resize(orig,img.width,img.height,450);
  const{px,W,H}=rs,bg=bgColor(px,W,H),gray=toGray(px,W,H);
  const isDark=bg<128;
  console.log(`scaled ${W}x${H}, bg=${bg}, isDark=${isDark}`);
  const box=findBoxLongRun(gray,W,H,isDark);
  if(!box){console.log('long-run locator failed');return;}
  console.log(`long-run bbox=[${box.left},${box.top},${box.right},${box.bottom}]`);
  const r=accOf(gray,W,bg,box);
  console.log(`RAW accuracy: acc=${r.acc.toFixed(0)}% (${r.corr}/${r.t}) ${r.corr>=9?'*** PASS ***':''}`);
  for(let rr=0;rr<9;rr++){let row='';for(let cc=0;cc<9;cc++){const v=r.grid[rr*9+cc],ex=EXP[rr*9+cc];const mk=ex!==0?(v===ex?String(v):'!'+v):(v===0?'.':'?'+v);row+=mk.padStart(3);}console.log(row);}
  // also try a local +-8 refinement
  let best=box,br=r;
  for(const dl of[-8,-4,0,4,8])for(const dt of[-8,-4,0,4,8])for(const dr of[-8,-4,0,4,8])for(const db of[-8,-4,0,4,8]){
    const cand={left:box.left+dl,top:box.top+dt,right:box.right+dr,bottom:box.bottom+db};
    if(cand.left<0||cand.top<0||cand.right>=W||cand.bottom>=H)continue;
    if(cand.right-cand.left<40||cand.bottom-cand.top<40)continue;
    const rr=accOf(gray,W,bg,cand);if(rr.corr>br.corr){br=rr;best=cand;}
  }
  console.log(`REFINED bbox=[${best.left},${best.top},${best.right},${best.bottom}] acc=${br.acc.toFixed(0)}% (${br.corr}/${br.t}) ${br.corr>=9?'*** PASS ***':''}`);
})();
