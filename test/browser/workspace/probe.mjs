// Exploratory: dump innerText + testids for each workspace page.
import { chromium } from 'playwright';
import { loadState, login, attachConsole, launch, BASE } from './lib.mjs';

const st = loadState();
const pages = process.argv[2]
  ? [process.argv[2]]
  : ['', '/team', '/settings', '/activity', '/data-sources'];

const b = await launch(chromium);
const ctx = await b.newContext({ viewport: { width: 1440, height: 1000 } });
const page = await ctx.newPage();
const errs = [];
attachConsole(page, errs);
await login(page, st.owner.token);

for (const p of pages) {
  const url = `${BASE}/w/${st.slug}${p}`;
  await page.goto(url, { waitUntil: 'networkidle' });
  await page.waitForTimeout(600);
  console.log(`\n########## ${url}`);
  console.log('TITLE:', await page.title());
  console.log('TESTIDS:', JSON.stringify(await page.$$eval('[data-test],[data-testid]', (ns) =>
    ns.map((n) => n.getAttribute('data-test') || n.getAttribute('data-testid')))));
  console.log('TEXT:\n' + (await page.locator('body').innerText()).slice(0, 4000));
}
console.log('\nCONSOLE:', JSON.stringify(errs, null, 1));
await b.close();
