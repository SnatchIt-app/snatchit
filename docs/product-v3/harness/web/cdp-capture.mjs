// B harness capture: real app, pinned commit, iPhone 15 Pro logical viewport, both appearances.
// Usage: node cdp-capture.mjs <profile> <outdir> <scheme:dark|light> <route> <name>
import { spawn } from 'node:child_process';
import { writeFileSync, mkdirSync } from 'node:fs';
const [profile, outdir, scheme, route, name] = process.argv.slice(2);
mkdirSync(outdir, { recursive: true });
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ['--headless','--disable-gpu','--no-sandbox','--hide-scrollbars',
   `--user-data-dir=${profile}`,'--remote-debugging-port=9223','about:blank'], { stdio:'ignore' });
await new Promise(r => setTimeout(r, 3500));
const t = (await (await fetch('http://127.0.0.1:9223/json')).json()).find(x => x.type === 'page');
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
await send('Page.navigate', { url: `http://localhost:8083${route}` });
await new Promise(r => setTimeout(r, 12000));
// Deep links are redirected to /home on cold load, so an optional click-through
// reaches the screen the way a user does. CLICK="visible text" node cdp-capture.mjs ...
if (process.env.CLICK) {
  const clickExpr = `(()=>{const t=${JSON.stringify(process.env.CLICK)};
    const els=[...document.querySelectorAll('*')].filter(e=>e.textContent.trim().includes(t));
    const el=els[els.length-1]; if(!el) return 'not-found';
    let n=el; for(let i=0;i<8&&n;i++){ const r=n.getBoundingClientRect();
      if(r.width>60&&r.height>30){ const x=r.x+r.width/2,y=r.y+r.height/2;
        for(const type of ['pointerdown','mousedown','pointerup','mouseup','click'])
          n.dispatchEvent(new MouseEvent(type,{bubbles:true,clientX:x,clientY:y}));
        return 'clicked:'+n.tagName; } n=n.parentElement; }
    return 'no-box';})()`;
  const c = await send('Runtime.evaluate', { expression: clickExpr, returnByValue: true });
  process.stderr.write('click -> ' + (c.result?.result?.value ?? '?') + '\n');
  await new Promise(r => setTimeout(r, 9000));
}
const probe = await send('Runtime.evaluate', { returnByValue:true, awaitPromise:true, expression:
  `(async()=>{await document.fonts.ready; const used=new Set();
    for(const el of document.querySelectorAll('*')){ if(el.children.length===0&&el.textContent.trim()) used.add(getComputedStyle(el).fontFamily); }
    return { path: location.pathname, faces:[...document.fonts].map(f=>f.family+':'+f.status),
             families:[...used].filter(f=>/Oswald|Inter/.test(f)), bg:getComputedStyle(document.body).backgroundColor };})()` });
const shot = await send('Page.captureScreenshot', { format:'png', captureBeyondViewport:false });
writeFileSync(`${outdir}/${name}.png`, Buffer.from(shot.result.data, 'base64'));
console.log(JSON.stringify({ file:`${name}.png`, scheme, ...probe.result?.result?.value }));
ws.close(); chrome.kill(); await new Promise(r => setTimeout(r, 800));
