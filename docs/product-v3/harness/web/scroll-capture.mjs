// B scroll capture: a long gallery in successive viewports. Scrolls the app's own scroll
// container (react-native-web ScrollView), not the window. Usage:
//   node scroll-capture.mjs <port> <outdir> <route> <name> <steps> [scheme]
import { writeFileSync, mkdirSync } from 'node:fs';
const [port,outdir,route,name,steps,scheme] = process.argv.slice(2);
mkdirSync(outdir,{recursive:true});
const t=(await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find(x=>x.type==='page');
const ws=new WebSocket(t.webSocketDebuggerUrl); await new Promise(r=>ws.onopen=r);
let id=0; const send=(m,p={})=>new Promise(res=>{const i=++id;
 const h=e=>{const j=JSON.parse(e.data); if(j.id===i){ws.removeEventListener('message',h);res(j);}};
 ws.addEventListener('message',h); ws.send(JSON.stringify({id:i,method:m,params:p}));});
await send('Page.enable'); await send('Runtime.enable');
await send('Emulation.setDeviceMetricsOverride',{width:393,height:852,deviceScaleFactor:3,mobile:true});
await send('Page.navigate',{url:`http://localhost:8083${route}`});
await new Promise(r=>setTimeout(r,15000));
const SCROLLER=`(()=>{const c=[...document.querySelectorAll('div')].filter(e=>e.scrollHeight>e.clientHeight+40&&e.clientHeight>300);
  window.__s=c.sort((a,b)=>b.scrollHeight-a.scrollHeight)[0]||document.scrollingElement;
  return window.__s? window.__s.scrollHeight+'/'+window.__s.clientHeight : 'none';})()`;
console.log('scroller', (await send('Runtime.evaluate',{expression:SCROLLER,returnByValue:true})).result?.result?.value);
for(let i=0;i<Number(steps);i++){
  if(i) { await send('Runtime.evaluate',{expression:`window.__s.scrollTop = ${i} * (window.__s.clientHeight - 40)`}); await new Promise(r=>setTimeout(r,1400)); }
  const shot=await send('Page.captureScreenshot',{format:'png'});
  writeFileSync(`${outdir}/${name}_${String(i+1).padStart(2,'0')}.png`, Buffer.from(shot.result.data,'base64'));
  const top=await send('Runtime.evaluate',{expression:'Math.round(window.__s.scrollTop)+" of "+window.__s.scrollHeight',returnByValue:true});
  console.log(`  ${name}_${String(i+1).padStart(2,'0')}.png  scrollTop=${top.result?.result?.value}`);
}
ws.close();
