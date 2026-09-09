// Flow 2 — Team (/w/:slug/team): roster, invite generate/rotate/revoke,
// member removal (re-added over the API afterwards).
import { chromium } from 'playwright';
import { loadState, login, attachConsole, launch, shot, report, api, BASE } from './lib.mjs';

const st = loadState();
const A = api(st.owner.token, st.slug);
const b = await launch(chromium);
const page = await (await b.newContext({ viewport: { width: 1440, height: 1100 } })).newPage();
const errs = [];
attachConsole(page, errs);
await login(page, st.owner.token);

const url = `${BASE}/w/${st.slug}/team`;
await page.goto(url, { waitUntil: 'networkidle' });
await page.waitForTimeout(400);
const r = {};
const txt = () => page.locator('body').innerText();

let body = await txt();
r['title'] = { pass: (await page.title()).includes('Team'), note: await page.title() };
r['roster lists both members'] = {
  pass: body.includes(st.owner.username) && body.includes(st.mate.username),
};
r['roster shows joined times'] = { pass: /joined /.test(body) };
r['roster shows per-member stats'] = { pass: body.includes('BUILT') && body.includes('IMPACT') };
r['avatars render'] = {
  pass: (await page.locator('.member-row .avatar, .avatar, [class*=avatar]').count()) >= 2,
  note: `count=${await page.locator('[class*=avatar]').count()}`,
};
r['workspace totals line'] = { pass: /Together:/.test(body) };
await shot(page, 'team-initial');

// --- invite: revoke existing (seeded via API), then generate via UI ---
await page.getByRole('button', { name: 'Revoke' }).click();
await page.getByRole('button', { name: /Confirm revoke|Revoke/ }).click();
await page.waitForTimeout(500);
body = await txt();
r['revoke invite clears the link'] = {
  pass: body.includes('No active invite link') && body.includes('Generate one'),
  note: body.includes('No active invite link') ? '' : body.slice(body.indexOf('INVITE'), body.indexOf('INVITE') + 200),
};

await page.getByRole('button', { name: 'Generate one' }).click();
await page.waitForTimeout(500);
const url1 = (await page.locator('#invite-url-value').innerText()).trim();
r['generate shows invite URL'] = { pass: /\/invite\/inv_/.test(url1), note: url1 };
await shot(page, 'team-invite-generated');

// --- rotate is two-step ---
await page.getByRole('button', { name: 'Rotate' }).click();
await page.waitForTimeout(200);
const armed = await page.locator('button', { hasText: 'Confirm rotate' }).count();
r['rotate arms before firing (two-step)'] = {
  pass: armed === 1 && (await page.locator('#invite-url-value').innerText()).trim() === url1,
};
await page.getByRole('button', { name: 'Confirm rotate' }).click();
await page.waitForTimeout(600);
const url2 = (await page.locator('#invite-url-value').innerText()).trim();
r['rotate changes the invite URL'] = { pass: url2 !== url1 && /\/invite\/inv_/.test(url2), note: `${url1} -> ${url2}` };
r['rotate notice shown'] = { pass: (await txt()).includes('Rotated.') };
await shot(page, 'team-invite-rotated');

// --- remove the second member, then re-add via API ---
await page.getByRole('button', { name: 'remove' }).click();
await page.waitForTimeout(200);
r['remove arms before firing (two-step)'] = {
  pass: (await page.locator('button', { hasText: 'confirm?' }).count()) === 1,
};
await page.getByRole('button', { name: 'confirm?' }).click();
await page.waitForTimeout(700);
body = await txt();
r['removal updates roster'] = {
  pass: !body.includes(st.mate.username) && /MEMBERS\n1/.test(body),
  note: /MEMBERS\n(\d+)/.exec(body)?.[1],
};
await shot(page, 'team-after-remove');

// restore state for the other flows
await A.post('/members', { username: st.mate.username });
await page.reload({ waitUntil: 'networkidle' });
await page.waitForTimeout(400);
r['re-added member reappears on reload'] = {
  pass: (await txt()).includes(st.mate.username),
};

report('TEAM', r, errs);
await b.close();
process.exit(Object.values(r).every((x) => x.pass) ? 0 : 1);
