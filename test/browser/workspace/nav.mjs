// Flow 6 — chrome/navigation: sidebar active highlight, client-side
// routing (window marker must survive), workspace switcher, per-page
// document.title.
import { chromium } from 'playwright';
import { loadState, login, attachConsole, launch, shot, report, BASE } from './lib.mjs';

const st = loadState();
const b = await launch(chromium);
const page = await (await b.newContext({ viewport: { width: 1440, height: 1100 } })).newPage();
const errs = [];
attachConsole(page, errs);
await login(page, st.owner.token);
await page.goto(`${BASE}/w/${st.slug}`, { waitUntil: 'networkidle' });
await page.waitForTimeout(400);

const r = {};
// marker that only survives if no full page load happens
await page.evaluate(() => { window.__spaMarker = 'alive'; });

const steps = [
  // Docs deliberately has no route segment in the title (Chrome.elm
  // documentTitle: Route.Docs -> withWs []), mirroring the old LiveView.
  { label: 'Docs', path: `/w/${st.slug}/docs`, title: /^Aveline · .+/ },
  { label: 'Data sources', path: `/w/${st.slug}/data-sources`, title: /Data sources/ },
  { label: 'Activity', path: `/w/${st.slug}/activity`, title: /Activity/ },
  { label: 'Team', path: `/w/${st.slug}/team`, title: /Team/ },
  // Settings is hardcoded "Aveline · Settings" (no workspace suffix).
  { label: 'Settings', path: `/w/${st.slug}/settings`, title: /^Aveline · Settings$/ },
  { label: 'Home', path: `/w/${st.slug}`, title: /Aveline/ },
];

const activeLabel = () =>
  page.$$eval('.sidebar-item.active', (ns) => ns.map((n) => n.innerText.trim()).join('|'));

r['home starts with Home active'] = { pass: (await activeLabel()) === 'Home', note: await activeLabel() };

for (const s of steps) {
  await page.locator('.sidebar-item', { hasText: new RegExp(`^${s.label}$`) }).first().click();
  await page.waitForURL(`**${s.path}`, { timeout: 5000 }).catch(() => {});
  await page.waitForTimeout(450);
  const marker = await page.evaluate(() => window.__spaMarker);
  const act = await activeLabel();
  const title = await page.title();
  r[`nav -> ${s.label}: url`] = { pass: new URL(page.url()).pathname === s.path, note: page.url() };
  r[`nav -> ${s.label}: client-side (no reload)`] = { pass: marker === 'alive' };
  r[`nav -> ${s.label}: sidebar active`] = { pass: act === s.label, note: `active=${act}` };
  r[`nav -> ${s.label}: document.title`] = { pass: s.title.test(title), note: title };
}
await shot(page, 'nav-final');

// workspace switcher
const switcher = page.locator('.workspace-switcher');
r['workspace switcher present'] = { pass: (await switcher.count()) === 1 };
await switcher.first().click().catch(() => {});
await page.waitForTimeout(300);
const items = await page.$$eval('.switcher-item', (ns) => ns.map((n) => n.innerText.trim()));
r['switcher lists this workspace'] = {
  pass: items.some((t) => t.toLowerCase().includes('browser test')),
  note: JSON.stringify(items),
};
r['switcher marks current workspace'] = {
  pass: (await page.locator('.switcher-item.current').count()) === 1,
};
await shot(page, 'nav-switcher');

report('NAV / CHROME', r, errs);
await b.close();
process.exit(Object.values(r).every((x) => x.pass) ? 0 : 1);
