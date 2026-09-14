// Minimal Chrome DevTools Protocol client (Node >= 22 built-in WebSocket; no dependencies).
// One headless browser, isolated browser contexts (separate cookie jars) for multi-user checks.
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function launchBrowser(chromePath) {
  const profile = mkdtempSync(join(tmpdir(), "venue-accept-chrome-"));
  const port = 9400 + Math.floor(Math.random() * 400);
  const proc = spawn(chromePath, ["--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run", `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, "about:blank"], { stdio: "ignore" });
  let wsUrl;
  for (let i = 0; i < 75 && !wsUrl; i++) {
    await sleep(200);
    try {
      wsUrl = (await (await fetch(`http://127.0.0.1:${port}/json/version`)).json()).webSocketDebuggerUrl;
    } catch {}
  }
  if (!wsUrl) {
    proc.kill();
    throw new Error(`Chrome did not start (${chromePath})`);
  }
  const ws = new WebSocket(wsUrl);
  await new Promise((res, rej) => {
    ws.onopen = res;
    ws.onerror = rej;
  });
  let id = 0;
  const pending = new Map();
  const listeners = [];
  ws.onmessage = (m) => {
    const msg = JSON.parse(m.data);
    if (msg.id && pending.has(msg.id)) {
      const { res, rej, method } = pending.get(msg.id);
      pending.delete(msg.id);
      msg.error ? rej(new Error(`${method}: ${msg.error.message}`)) : res(msg.result);
    } else if (msg.method) listeners.forEach((l) => l(msg));
  };
  const send = (method, params = {}, sessionId) =>
    new Promise((res, rej) => {
      const i = ++id;
      pending.set(i, { res, rej, method });
      ws.send(JSON.stringify({ id: i, method, params, ...(sessionId ? { sessionId } : {}) }));
    });

  async function newPage({ width = 1280, height = 900 } = {}) {
    const { browserContextId } = await send("Target.createBrowserContext", { disposeOnDetach: true });
    const { targetId } = await send("Target.createTarget", { url: "about:blank", browserContextId });
    const { sessionId } = await send("Target.attachToTarget", { targetId, flatten: true });
    const s = (method, params) => send(method, params, sessionId);
    await s("Page.enable");
    await s("Runtime.enable");
    await s("Network.enable");
    await s("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 1, mobile: false });
    const evaluate = async (expression) => {
      const r = await s("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
      if (r.exceptionDetails) throw new Error(`evaluate: ${r.exceptionDetails.text}`);
      return r.result.value;
    };
    const waitReady = async (min = 400) => {
      await sleep(min);
      for (let i = 0; i < 100; i++) {
        try {
          if ((await evaluate("document.readyState")) === "complete") return;
        } catch {}
        await sleep(100);
      }
    };
    const page = {
      async goto(url) {
        await s("Page.navigate", { url });
        await waitReady();
      },
      async reload() {
        await s("Page.reload", { ignoreCache: true });
        await waitReady();
      },
      url: () => evaluate("location.href"),
      text: () => evaluate("document.body ? document.body.innerText : ''"),
      evaluate,
      async waitFor(predicateJs, timeoutMs = 15000) {
        const end = Date.now() + timeoutMs;
        while (Date.now() < end) {
          try {
            if (await evaluate(predicateJs)) return true;
          } catch {}
          await sleep(200);
        }
        return false;
      },
      async fill(selector, value) {
        const ok = await evaluate(`(() => { const e = document.querySelector(${JSON.stringify(selector)}); if (!e) return false;
          const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set; set.call(e, ${JSON.stringify(value)});
          e.dispatchEvent(new Event('input', { bubbles: true })); e.dispatchEvent(new Event('change', { bubbles: true })); return true; })()`);
        if (!ok) throw new Error(`fill: ${selector} not found`);
      },
      async click(selector) {
        const ok = await evaluate(`(() => { const e = document.querySelector(${JSON.stringify(selector)}); if (!e) return false; e.click(); return true; })()`);
        if (!ok) throw new Error(`click: ${selector} not found`);
      },
      cookies: async (url) => (await s("Network.getCookies", { urls: [url] })).cookies,
      setCookie: (cookie) => s("Network.setCookie", cookie),
      deleteCookie: (name, url) => s("Network.deleteCookies", { name, url }),
      async screenshot(file) {
        const h = await evaluate("Math.min(document.documentElement.scrollHeight, 3000)");
        const { data } = await s("Page.captureScreenshot", { format: "png", captureBeyondViewport: true, clip: { x: 0, y: 0, width, height: h, scale: 1 } });
        writeFileSync(file, Buffer.from(data, "base64"));
      },
      close: () => send("Target.disposeBrowserContext", { browserContextId }),
    };
    return page;
  }

  return {
    newPage,
    async close() {
      try {
        ws.close();
      } catch {}
      const exited = new Promise((r) => (proc.exitCode !== null ? r() : proc.once("exit", r)));
      proc.kill();
      await Promise.race([exited, sleep(3000)]);
      try {
        rmSync(profile, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
      } catch {
        // A lingering Chrome helper can hold the temp profile briefly; it lives under the OS temp dir.
      }
    },
  };
}
