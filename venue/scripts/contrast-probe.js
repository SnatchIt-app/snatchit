(()=>{const cv=document.createElement('canvas');cv.width=cv.height=1;const cx=cv.getContext('2d',{willReadFrequently:true});
const rs=(c)=>{cx.clearRect(0,0,1,1);cx.fillStyle=c;cx.fillRect(0,0,1,1);const d=cx.getImageData(0,0,1,1).data;return{rgb:[d[0],d[1],d[2]],a:d[3]/255}};
const li=(c)=>{const s=c/255;return s<=0.03928?s/12.92:((s+0.055)/1.055)**2.4};
const lu=([r,g,b])=>0.2126*li(r)+0.7152*li(g)+0.0722*li(b);
const ov=(f,a,b)=>[0,1,2].map(i=>f[i]*a+b[i]*(1-a));
const bgOf=(el)=>{const st=[];let n=el;while(n&&n.nodeType===1){const c=rs(getComputedStyle(n).backgroundColor);if(c.a>0)st.push(c);n=n.parentElement}let acc=[255,255,255];for(let i=st.length-1;i>=0;i--)acc=ov(st[i].rgb,st[i].a,acc);return acc};
const ra=(f,b)=>{const[h,l]=[lu(f),lu(b)].sort((x,y)=>y-x);return(h+0.05)/(l+0.05)};
const run=()=>{const fails=[];let checked=0;
for(const el of document.querySelectorAll('body *')){if(el.children.length)continue;const t=(el.textContent||'').trim();if(!t)continue;
const cs=getComputedStyle(el);if(cs.visibility==='hidden'||cs.display==='none'||parseFloat(cs.opacity)===0)continue;
const r=el.getBoundingClientRect();if(r.width===0||r.height===0)continue;
const f=rs(cs.color),bg=bgOf(el),p=ov(f.rgb,f.a,bg);const px=parseFloat(cs.fontSize),bo=parseInt(cs.fontWeight,10)>=700;
const need=(px>=24||(bo&&px>=18.66))?3:4.5;const got=ra(p,bg);checked++;
if(got<need)fails.push({txt:t.slice(0,34),px:Math.round(px*10)/10,need,got:Math.round(got*100)/100,cls:(el.className||'').toString().slice(0,36)})}
return{checked,fails}};
const bad=document.createElement('p');bad.textContent='CTRL_BAD';bad.style.cssText='color:#ccc;background:#fff;font-size:14px';
const good=document.createElement('p');good.textContent='CTRL_GOOD';good.style.cssText='color:#0b0b0b;background:#fff;font-size:14px';
document.body.append(bad,good);const w=run();const cb=w.fails.some(f=>f.txt==='CTRL_BAD'),fg=w.fails.some(f=>f.txt==='CTRL_GOOD');bad.remove();good.remove();
const c=run();return{page:location.pathname+location.search,controlsOk:cb&&!fg,checked:c.checked,failureCount:c.fails.length,fails:c.fails.slice(0,8)}})()
