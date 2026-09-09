// Shared helpers for the workspace browser tests.
// No app code is touched; everything goes through the public HTTP API.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const BASE = process.env.AVELINE_BASE || 'http://localhost:4000';
export const HERE = path.dirname(fileURLToPath(import.meta.url));
export const SHOTS = path.join(HERE, '..', 'screenshots');
export const STATE = path.join(HERE, '.state.json');

export function loadState() {
  return JSON.parse(fs.readFileSync(STATE, 'utf8'));
}
export function saveState(s) {
  fs.writeFileSync(STATE, JSON.stringify(s, null, 2));
}

// --- tiny cookie-jar fetch (for the CSRF-protected /papi signup flow) ---
export function makeJar() {
  const jar = new Map();
  return {
    cookieHeader: () => [...jar].map(([k, v]) => `${k}=${v}`).join('; '),
    absorb: (res) => {
      for (const c of res.headers.getSetCookie?.() || []) {
        const [kv] = c.split(';');
        const i = kv.indexOf('=');
        jar.set(kv.slice(0, i).trim(), kv.slice(i + 1).trim());
      }
    },
  };
}

export async function signup({ username, workspaceName, inviteCode }) {
  const jar = makeJar();
  const page = await fetch(`${BASE}/signup`);
  jar.absorb(page);
  const html = await page.text();
  const boot = JSON.parse(
    /<script id="spa-bootstrap" type="application\/json">([^<]+)<\/script>/.exec(html)[1]
  );
  const csrf = boot.csrf;
  const h = () => ({
    'content-type': 'application/json',
    'x-csrf-token': csrf,
    cookie: jar.cookieHeader(),
  });
  const pt = await fetch(`${BASE}/papi/signup/preview-token`, { headers: h() });
  jar.absorb(pt);
  const token = (await pt.json()).token;
  const body = { username, copied: true, token };
  if (inviteCode) body.invite_code = inviteCode;
  else body.workspace_name = workspaceName;
  const res = await fetch(`${BASE}/papi/signup`, {
    method: 'POST',
    headers: h(),
    body: JSON.stringify(body),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`signup failed ${res.status}: ${JSON.stringify(json)}`);
  return { ...json, token };
}

// --- bearer API client ---
export function api(token, wsSlug) {
  const call = async (method, p, body) => {
    const url = p.startsWith('/api') ? BASE + p : `${BASE}/api/workspaces/${wsSlug}${p}`;
    const res = await fetch(url, {
      method,
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/json',
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    let json;
    try { json = JSON.parse(text); } catch { json = text; }
    if (!res.ok) throw new Error(`${method} ${url} -> ${res.status} ${text.slice(0, 400)}`);
    return json;
  };
  return {
    get: (p) => call('GET', p),
    post: (p, b) => call('POST', p, b ?? {}),
    patch: (p, b) => call('PATCH', p, b),
    del: (p) => call('DELETE', p),
    raw: call,
  };
}

// --- playwright helpers ---
// The installed playwright wants a newer chromium build than what's in the
// local cache; point it at the newest cached Chrome-for-Testing instead.
export const CHROME =
  process.env.AVELINE_CHROME ||
  `${process.env.HOME}/Library/Caches/ms-playwright/chromium-1200/chrome-mac-x64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing`;

export async function launch(chromium) {
  return chromium.launch({ executablePath: CHROME, headless: true });
}

// Benign dev-server noise, not app bugs.
const BENIGN = [/Compiled in DEV mode/, /phoenix\/live_reload/];
const benign = (t) => BENIGN.some((re) => re.test(t));

export function attachConsole(page, sink) {
  page.on('console', (m) => {
    if (m.type() === 'error' || m.type() === 'warning') {
      if (!benign(m.text())) sink.push({ type: m.type(), text: m.text(), url: page.url() });
    }
  });
  page.on('pageerror', (e) => sink.push({ type: 'pageerror', text: String(e), url: page.url() }));
  page.on('requestfailed', (r) =>
    benign(r.url()) || sink.push({ type: 'requestfailed', text: `${r.method()} ${r.url()} ${r.failure()?.errorText}`, url: page.url() }));
  page.on('response', (r) => {
    if (r.status() >= 400) sink.push({ type: 'http', text: `${r.status()} ${r.request().method()} ${r.url()}`, url: page.url() });
  });
}

export async function login(page, token) {
  await page.goto(`${BASE}/login`, { waitUntil: 'networkidle' });
  const ok = await page.evaluate(async (tok) => {
    const csrf = JSON.parse(document.getElementById('spa-bootstrap').textContent).csrf;
    const r = await fetch('/papi/session', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-csrf-token': csrf },
      body: JSON.stringify({ token: tok }),
    });
    return r.status;
  }, token);
  if (ok !== 200) throw new Error(`login failed: ${ok}`);
}

export async function shot(page, name) {
  await page.screenshot({ path: path.join(SHOTS, `${name}.png`), fullPage: true });
}

export function report(title, results, consoleErrors) {
  console.log(`\n===== ${title} =====`);
  for (const [k, v] of Object.entries(results)) {
    console.log(`${v.pass ? 'PASS' : 'FAIL'}  ${k}${v.note ? '  -- ' + v.note : ''}`);
  }
  if (consoleErrors.length) {
    console.log('--- console/network problems ---');
    for (const e of consoleErrors) console.log(`[${e.type}] ${e.text}  @${e.url}`);
  } else {
    console.log('--- console clean ---');
  }
}
