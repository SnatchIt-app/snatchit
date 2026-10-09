// B batch capture — ONE attached Chrome, many routes. Appearance comes from the app's own
// preference (?appearance=), never a browser emulation flag. Reports the font faces actually
// used on each screen, so a fallback-font render can never be mistaken for a real comparison.
// Usage: node batch-capture.mjs <cdp-port> <outdir> <<< "route<TAB>name" lines on stdin
import { writeFileSync, mkdirSync, readFileSync } from 'node:fs';
const [port, outdir] = process.argv.slice(2);
mkdirSync(outdir, { recursive: true });
const jobs = readFileSync(0,'utf8').split('\n').map(l=>l.trim()).filter(Boolean).map(l=>l.split(/\s+\|\s+/));
const t = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find(x => x.type === 'page');
const ws = new WebSocket(t.webSocketDebuggerUrl);
await new Promise(r => ws.onopen = r);
let id=0; const send=(method,params={})=>new Promise(res=>{const myId=++id;
  const h=e=>{const m=JSON.parse(e.data); if(m.id===myId){ws.removeEventListener('message',h);res(m);}};
  ws.addEventListener('message',h); ws.send(JSON.stringify({id:myId,method,params}));});
await send('Page.enable'); await send('Runtime.enable');
await send('Emulation.setDeviceMetricsOverride',{width:393,height:852,deviceScaleFactor:3,mobile:true});
const PROBE=`(async()=>{await document.fonts.ready; const used=new Set();
  for(const el of document.querySelectorAll('*')) if(el.children.length===0&&el.textContent.trim()) used.add(getComputedStyle(el).fontFamily);
  const c=document.elementFromPoint(196,400);
  return { path: location.pathname+location.search, fams:[...used].join(' / '),
           bg: getComputedStyle(document.documentElement).backgroundColor,
           mid: c?getComputedStyle(c).backgroundColor:'?' };})()`;
for (const [route,name,wait] of jobs) {
  await send('Page.navigate',{url:`http://localhost:8083${route}`});
  await new Promise(r=>setTimeout(r, Number(wait ?? process.env.WAIT ?? 11000)));
  const p = await send('Runtime.evaluate',{expression:PROBE,returnByValue:true,awaitPromise:true});
  const shot = await send('Page.captureScreenshot',{format:'png'});
  writeFileSync(`${outdir}/${name}.png`, Buffer.from(shot.result.data,'base64'));
  const v=p.result?.result?.value??{};
  console.log(`${name.padEnd(28)} ${String(v.path).padEnd(52)} fonts=${v.fams}`);
}
ws.close();
