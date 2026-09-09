// Flow 1 — Home (/w/:slug)
import { chromium } from 'playwright';
import { loadState, login, attachConsole, launch, shot, report, BASE } from './lib.mjs';

const st = loadState();
const b = await launch(chromium);
const page = await (await b.newContext({ viewport: { width: 1440, height: 1100 } })).newPage();
const errs = [];
attachConsole(page, errs);
await login(page, st.owner.token);
await page.goto(`${BASE}/w/${st.slug}`, { waitUntil: 'networkidle' });
await page.waitForTimeout(500);

const body = await page.locator('body').innerText();
const has = (s) => body.includes(s);
const r = {};

r['title is workspace-scoped'] = {
  pass: (await page.title()).includes(st.slug.replace(/-/g, ' ')) || (await page.title()).startsWith('Aveline'),
  note: await page.title(),
};
// The header greets the display name when one is set (Settings flow sets
// one), otherwise the username.
const me = await (await fetch(`${BASE}/api/workspaces/${st.slug}/members`, {
  headers: { authorization: `Bearer ${st.owner.token}` },
})).json();
const meRow = me.members.find((m) => m.username === st.owner.username);
const greeted = meRow.display_name || st.owner.username;
r['welcome-back header'] = {
  pass: has(`Welcome back, ${greeted}`),
  note: /Welcome back, [^\n]*/.exec(body)?.[0],
};
r['pinned shelf has orientation card'] = {
  pass: has('PINNED DOCS') && has('How we use Aveline here') && has('Get oriented'),
};
r['pinned shelf shows both pins'] = { pass: has('Seeded doc 1') && has('Seeded doc 2') };
r['recently changed reflects edits'] = {
  pass: has('RECENTLY CHANGED') && has('edit round 4') && has('v5'),
};
r['open comments section lists comment'] = {
  pass: has('OPEN COMMENTS') && has(st.commentBody) && has(st.mate.username),
};
r['tag glossary chips render'] = {
  pass: has('TAGS') && has('metrics') && has('runbook') && has('decisions'),
  note: `chips=${await page.locator('.tag-chip, .glossary-chip, [class*=tag]').count()}`,
};
r['view all activity link'] = { pass: has('View all activity') };

await shot(page, 'home');
report('HOME', r, errs);
await b.close();
process.exit(Object.values(r).every((x) => x.pass) ? 0 : 1);
