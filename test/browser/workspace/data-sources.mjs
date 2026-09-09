// Flow 5 — Data sources (/w/:slug/data-sources): smoke render only.
import { chromium } from 'playwright';
import { loadState, login, attachConsole, launch, shot, report, BASE } from './lib.mjs';

const st = loadState();
const b = await launch(chromium);
const page = await (await b.newContext({ viewport: { width: 1440, height: 1100 } })).newPage();
const errs = [];
attachConsole(page, errs);
await login(page, st.owner.token);
await page.goto(`${BASE}/w/${st.slug}/data-sources`, { waitUntil: 'networkidle' });
// Wait for the async bootstrap (data-sources-overview) rather than a
// fixed sleep — a cold server can take seconds on the first request.
const loaded = await page
  .getByText('QUERY CATALOG', { exact: false })
  .first()
  .waitFor({ timeout: 20000 })
  .then(() => true)
  .catch(() => false);

const body = await page.locator('body').innerText();
const r = {};
r['async bootstrap resolves'] = { pass: loaded };
r['title'] = { pass: (await page.title()).includes('Data sources'), note: await page.title() };
r['page header + blurb'] = {
  pass: body.includes('Data sources') && body.includes('External databases this workspace can chart from'),
};
r['built-in workspace source card'] = {
  pass: body.includes('derived') && body.includes('DUCKDB') && body.includes('BUILT-IN'),
};
r['source card shows query/chart counts'] = { pass: /\d+ queries/.test(body) && /\d+ charts/.test(body) };
r['query catalog area renders'] = { pass: body.includes('QUERY CATALOG') && body.includes('No queries yet') };
r['timeline/milestones area renders'] = { pass: body.includes('TIMELINE') && body.includes('No milestones yet') };
r['no console errors'] = { pass: errs.length === 0, note: JSON.stringify(errs) };

await shot(page, 'data-sources');
report('DATA SOURCES', r, errs);
await b.close();
process.exit(Object.values(r).every((x) => x.pass) ? 0 : 1);
