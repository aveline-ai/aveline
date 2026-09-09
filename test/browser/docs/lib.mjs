// Shared helpers for the docs browser tests.
//
// Usage: every script under test/browser/docs/ imports these. State
// produced by seed.mjs lives in state.json next to this file.
import { chromium } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

export const BASE = process.env.AVELINE_BASE || 'http://localhost:4000';
export const HERE = path.dirname(fileURLToPath(import.meta.url));
export const STATE_PATH = path.join(HERE, 'state.json');
export const SHOTS = path.resolve(HERE, '..', 'screenshots');

fs.mkdirSync(SHOTS, { recursive: true });

export function loadState() {
  return JSON.parse(fs.readFileSync(STATE_PATH, 'utf8'));
}

export function saveState(s) {
  fs.writeFileSync(STATE_PATH, JSON.stringify(s, null, 2));
}

// ===== Bearer API =====

export async function api(token, method, urlPath, body) {
  const res = await fetch(BASE + urlPath, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    /* non-JSON */
  }
  return { status: res.status, json, text };
}

export async function apiOk(token, method, urlPath, body) {
  const r = await api(token, method, urlPath, body);
  if (r.status >= 300) {
    throw new Error(`${method} ${urlPath} -> ${r.status}: ${r.text.slice(0, 500)}`);
  }
  return r.json;
}

// ===== Browser =====

// The npm playwright build expects a browser revision that may not be
// in the local cache; fall back to whatever chromium IS cached.
function cachedChromium() {
  if (process.env.AVELINE_CHROMIUM) return process.env.AVELINE_CHROMIUM;
  const root = path.join(os.homedir(), 'Library/Caches/ms-playwright');
  if (!fs.existsSync(root)) return undefined;
  const dirs = fs
    .readdirSync(root)
    .filter((d) => /^chromium-\d+$/.test(d))
    .sort((a, b) => Number(b.split('-')[1]) - Number(a.split('-')[1]));
  for (const d of dirs) {
    const exe = path.join(
      root,
      d,
      'chrome-mac-x64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing'
    );
    if (fs.existsSync(exe)) return exe;
  }
  return undefined;
}

export async function launch() {
  return chromium.launch({ headless: true, executablePath: cachedChromium() });
}

// Opens a context, logs the token's user in via /login/:token, and
// wires console/pageerror/failed-response capture.
export async function newPage(browser, token, { next = '/' } = {}) {
  const ctx = await browser.newContext({ viewport: { width: 1400, height: 1000 } });
  const page = await ctx.newPage();
  const logs = [];
  page.on('console', (m) => {
    if (m.type() === 'error' || m.type() === 'warning') {
      logs.push({ kind: m.type(), text: m.text() });
    }
  });
  page.on('pageerror', (e) => logs.push({ kind: 'pageerror', text: String(e) }));
  page.on('requestfailed', (r) =>
    logs.push({ kind: 'requestfailed', text: `${r.method()} ${r.url()}` })
  );
  page.on('response', (r) => {
    if (r.status() >= 400) logs.push({ kind: 'http', text: `${r.status()} ${r.url()}` });
  });
  page.logs = logs;
  await page.goto(`${BASE}/login/${token}?next=${encodeURIComponent(next)}`, {
    waitUntil: 'networkidle',
  });
  return page;
}

export async function shot(page, name) {
  const p = path.join(SHOTS, `${name}.png`);
  await page.screenshot({ path: p, fullPage: true });
  return p;
}

// ===== Reporting =====

const results = [];

export function check(name, pass, detail = '') {
  results.push({ name, pass, detail });
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`);
  return pass;
}

export function report(page) {
  const bad = results.filter((r) => !r.pass);
  console.log(`\n--- ${results.length - bad.length}/${results.length} checks passed ---`);
  if (page && page.logs && page.logs.length) {
    console.log('CONSOLE/NETWORK NOISE:');
    for (const l of page.logs) console.log(`  [${l.kind}] ${l.text}`);
  }
  return bad.length === 0;
}

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
