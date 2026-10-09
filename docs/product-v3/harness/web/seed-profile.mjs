// B harness: seed a dedicated headless-Chrome profile with the sandbox test session.
// Credentials are read from the local sandbox.env and never printed, never served,
// never written to a file. The session is injected over CDP (a loopback socket).
import { readFileSync } from 'node:fs';
import { spawn } from 'node:child_process';
const envFile = '/Users/josetascon/snatchit-batch1/scripts/sandbox/sandbox.env';
const env = Object.fromEntries(readFileSync(envFile,'utf8').split('\n')
  .filter(l => l.trim() && !l.startsWith('#') && l.includes('='))
  .map(l => { const i = l.indexOf('='); return [l.slice(0,i).trim(), l.slice(i+1).trim().replace(/^['"]|['"]$/g,'')]; }));
const url = readFileSync('/Users/josetascon/snatchit-v3render/.env.local','utf8')
  .split('\n').find(l => l.startsWith('EXPO_PUBLIC_SUPABASE_URL=')).split('=')[1].trim();
const ref = url.match(/https:\/\/([a-z0-9]+)\.supabase\.co/)[1];
const anon = env.TEST_ANON_KEY;
const res = await fetch(`${url}/auth/v1/token?grant_type=password`, { method:'POST',
  headers:{apikey:anon, Authorization:`Bearer ${anon}`,'Content-Type':'application/json'},
  body: JSON.stringify({ email: env.BUYER_EMAIL, password: env.BUYER_PASSWORD }) });
if (!res.ok) { console.error('AUTH FAILED', res.status); process.exit(1); }
const sess = await res.json();
const PROFILE = process.argv[2];
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ['--headless','--disable-gpu','--no-sandbox',`--user-data-dir=${PROFILE}`,
   '--remote-debugging-port=9222','about:blank'], { stdio:'ignore', detached:false });
await new Promise(r => setTimeout(r, 3500));
const targets = await (await fetch('http://127.0.0.1:9222/json')).json();
const page = targets.find(t => t.type === 'page');
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise(r => ws.onopen = r);
let id = 0; const send = (method, params) => new Promise(resolve => {
  const myId = ++id;
  const h = e => { const m = JSON.parse(e.data); if (m.id === myId) { ws.removeEventListener('message', h); resolve(m); } };
  ws.addEventListener('message', h); ws.send(JSON.stringify({ id: myId, method, params }));
});
await send('Page.enable', {});
await send('Page.navigate', { url: 'http://localhost:8083' });
await new Promise(r => setTimeout(r, 6000));
const expr = `localStorage.setItem(${JSON.stringify(`sb-${ref}-auth-token`)}, ${JSON.stringify(JSON.stringify(sess))}); 'ok'`;
const out = await send('Runtime.evaluate', { expression: expr, returnByValue: true });
console.log('seed result:', out.result?.result?.value ?? 'unknown');
console.log('user id:', sess.user.id);
ws.close(); chrome.kill();
await new Promise(r => setTimeout(r, 1500));
