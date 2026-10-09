// B avatar probe — ATTACHES to a running headless Chrome holding the sandbox session.
// Deep links redirect to /home on cold load, so Profile is reached the way a user reaches it:
// by tapping the dock's "You" item. Measures what the SERVER returned for each avatar surface.
// No writes, no upload, no account change. Tokens redacted before printing.
// Usage: node avatar-probe.mjs <cdp-port> <outdir> <dark|light>
import { writeFileSync, mkdirSync } from 'node:fs';
const [port, outdir, scheme] = process.argv.slice(2);
mkdirSync(outdir, { recursive: true });
const t = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find(x => x.type === 'page');
const ws = new WebSocket(t.webSocketDebuggerUrl);
await new Promise(r => ws.onopen = r);
let id = 0; const send = (method, params={}) => new Promise(res => {
  const myId = ++id;
  const h = e => { const m = JSON.parse(e.data); if (m.id === myId) { ws.removeEventListener('message', h); res(m); } };
  ws.addEventListener('message', h); ws.send(JSON.stringify({ id: myId, method, params }));
});
await send('Page.enable'); await send('Runtime.enable');
await send('Emulation.setDeviceMetricsOverride', { width:393, height:852, deviceScaleFactor:3, mobile:true });
await send('Emulation.setEmulatedMedia', { features:[{ name:'prefers-color-scheme', value: scheme }] });

const MEASURE = `(()=>({ path: location.pathname, imgs: [...document.querySelectorAll('img')].map(im=>{
  const r=im.getBoundingClientRect(); const cs=getComputedStyle(im);
  const par=im.parentElement? getComputedStyle(im.parentElement):null;
  return { src: im.currentSrc||im.src, nw: im.naturalWidth, nh: im.naturalHeight,
           w: Math.round(r.width), h: Math.round(r.height), x: Math.round(r.x), y: Math.round(r.y),
           fit: cs.objectFit, pos: cs.objectPosition, parentRadius: par?par.borderRadius:'?' };
}).filter(im=>im.w>0) }))()`;

const report = async (name) => {
  const m = await send('Runtime.evaluate', { expression: MEASURE, returnByValue: true });
  const shot = await send('Page.captureScreenshot', { format:'png' });
  writeFileSync(`${outdir}/${name}.png`, Buffer.from(shot.result.data,'base64'));
  const v = m.result?.result?.value ?? { imgs: [] };
  console.log(`### ${name}.png   path=${v.path}`);
  for (const im of v.imgs) {
    const u = new URL(im.src, 'http://x');
    const q = u.pathname.split('/').slice(-1)[0] + u.search.replace(/token=[^&]*/,'token=<redacted>');
    console.log(`  natural=${im.nw}x${im.nh} [${im.nw===im.nh?'SQUARE':'NOT-SQUARE'}] box=${im.w}x${im.h} at=(${im.x},${im.y}) fit=${im.fit} pos=${im.pos} parentRadius=${im.parentRadius}`);
    console.log(`    ${q}`);
  }
};
const click = async (text) => {
  const expr = `(()=>{const t=${JSON.stringify(text)};
    const els=[...document.querySelectorAll('*')].filter(e=>e.children.length===0&&e.textContent.trim()===t);
    const el=els[els.length-1]; if(!el) return 'not-found';
    let n=el; for(let i=0;i<8&&n;i++){ const r=n.getBoundingClientRect();
      if(r.width>40&&r.height>30){ const x=r.x+r.width/2,y=r.y+r.height/2;
        for(const type of ['pointerdown','mousedown','pointerup','mouseup','click'])
          n.dispatchEvent(new MouseEvent(type,{bubbles:true,clientX:x,clientY:y}));
        return 'clicked '+n.tagName+' @'+Math.round(x)+','+Math.round(y); } n=n.parentElement; }
    return 'no-box';})()`;
  const c = await send('Runtime.evaluate', { expression: expr, returnByValue: true });
  console.log('  click("'+text+'") -> ' + c.result?.result?.value);
};
await send('Page.navigate', { url: 'http://localhost:8083/' });
await new Promise(r => setTimeout(r, 15000));
await report(`avatar_dock_${scheme}`);
await click('You');
await new Promise(r => setTimeout(r, 9000));
await report(`avatar_profile_${scheme}`);
ws.close();
