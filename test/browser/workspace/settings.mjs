// Flow 3 — Settings (/w/:slug/settings): display name, API keys.
import { chromium } from 'playwright';
import { loadState, login, attachConsole, launch, shot, report, BASE } from './lib.mjs';

const st = loadState();
const b = await launch(chromium);
const page = await (await b.newContext({ viewport: { width: 1440, height: 1100 } })).newPage();
const errs = [];
attachConsole(page, errs);
await login(page, st.owner.token);
const url = `${BASE}/w/${st.slug}/settings`;
await page.goto(url, { waitUntil: 'networkidle' });
await page.waitForTimeout(400);

const r = {};
const txt = () => page.locator('body').innerText();
r['title'] = { pass: (await page.title()).includes('Settings'), note: await page.title() };
r['signed-in line'] = { pass: (await txt()).includes(`Signed in as ${st.owner.username}`) };

// --- display name ---
const name = `Testy ${Date.now() % 10000}`;
await page.locator('#display-name').fill(name);
await page.getByRole('button', { name: 'Save' }).click();
await page.waitForTimeout(600);
r['display-name save shows "Saved."'] = { pass: (await txt()).includes('Saved.') };
await page.reload({ waitUntil: 'networkidle' });
await page.waitForTimeout(400);
r['display name persists on reload'] = {
  pass: (await page.locator('#display-name').inputValue()) === name,
  note: await page.locator('#display-name').inputValue(),
};
await shot(page, 'settings-display-name');

// --- api keys ---
let body = await txt();
r['API keys list renders'] = { pass: body.includes('API KEYS') && /avl_…/.test(body) };
r['single key is marked "only key"'] = { pass: body.includes('only key') };

// last-key revoke: the product hides the revoke affordance entirely when
// there is exactly one key and surfaces the message as a tooltip; the API
// refuses too. Assert both.
const onlyKey = page.locator('.auth-hint', { hasText: 'only key' });
r['last-key revoke refused (no revoke button, product tooltip)'] = {
  pass:
    (await page.locator('button', { hasText: /^revoke$/ }).count()) === 0 &&
    (await onlyKey.getAttribute('title')) ===
      'Your only key. Create a new one first, then revoke this one.',
  note: await onlyKey.getAttribute('title'),
};
const keyId = (await (await fetch(`${BASE}/api/keys`, {
  headers: { authorization: `Bearer ${st.owner.token}` },
})).json()).keys[0].id;
const del = await fetch(`${BASE}/api/keys/${keyId}`, {
  method: 'DELETE',
  headers: { authorization: `Bearer ${st.owner.token}` },
});
const delBody = await del.json();
r['API refuses last-key revoke'] = {
  pass: del.status >= 400 && /last_key/.test(JSON.stringify(delBody)),
  note: `${del.status} ${JSON.stringify(delBody)}`,
};
await shot(page, 'settings-last-key');

// --- create a key ---
await page.locator('input[placeholder*="Name the new key"]').fill('browser-test-key');
await page.getByRole('button', { name: 'New key' }).click();
await page.waitForTimeout(700);
const reveal = await page.locator('#new-key-value').innerText().catch(() => '');
r['create key shows one-time reveal'] = { pass: /^avl_\w+/.test(reveal.trim()), note: reveal.trim().slice(0, 12) + '…' };
await shot(page, 'settings-key-created');

// --- revoke the new key ---
// Target the row for the key we just made, never the signup token.
const row = page.locator('.team-row', { hasText: 'browser-test-key' });
r['revoke button appears once >1 key'] = {
  pass: (await page.locator('button', { hasText: /^revoke$/ }).count()) === 2,
  note: `count=${await page.locator('button', { hasText: /^revoke$/ }).count()}`,
};
const before = (await txt()).match(/API KEYS\n(\d+)/)?.[1];
await row.getByRole('button', { name: 'revoke' }).click();
await page.waitForTimeout(150);
await row.getByRole('button', { name: 'confirm?' }).click();
await page.waitForTimeout(800);
const after = (await txt()).match(/API KEYS\n(\d+)/)?.[1];
r['revoking a key removes it'] = { pass: Number(after) === Number(before) - 1, note: `${before} -> ${after}` };
await shot(page, 'settings-after-revoke');

report('SETTINGS', r, errs);
await b.close();
process.exit(Object.values(r).every((x) => x.pass) ? 0 : 1);
