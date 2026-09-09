// Flow 3 — visibility + shares driven from the doc page.
//
//   node test/browser/docs/03-visibility-shares.mjs   (seed.mjs first)
//
// Flip a workspace doc private from the UI and prove the second user
// loses API access; share it back to them from the UI and prove access
// returns. Every assertion about access is made with the OTHER user's
// bearer token, never with the owner's.
import { launch, newPage, loadState, api, apiOk, check, report, shot, sleep } from './lib.mjs';

const S = loadState();
const W = (p) => `/api/workspaces/${S.workspace}${p}`;
const DOC_PATH = `/w/${S.workspace}/d/${S.docs.shared}`;
const readerGet = () => api(S.reader.token, 'GET', W(`/docs/${S.docs.shared}`));

async function main() {
  // Reset to a known state: workspace-visible, no shares.
  await apiOk(S.owner.token, 'PUT', W(`/docs/${S.docs.shared}/visibility`), { visibility: 'workspace' });
  for (const sh of (await apiOk(S.owner.token, 'GET', W(`/docs/${S.docs.shared}/shares`))).shares || []) {
    if (sh.username) await apiOk(S.owner.token, 'DELETE', W(`/docs/${S.docs.shared}/shares/${sh.username}`));
  }

  const browser = await launch();
  const page = await newPage(browser, S.owner.token, { next: DOC_PATH });
  await page.waitForSelector('.blocks', { timeout: 15000 });

  const start = await readerGet();
  check('second user can read the workspace-visible doc', start.status === 200, `status ${start.status}`);

  // ===== Flip private from the UI =====
  const switcher = page.locator('#visibility-switcher');
  check('owner sees the visibility switcher', (await switcher.count()) === 1);
  check(
    'switcher starts on "Team"',
    (await switcher.locator('.article-meta-val').innerText()).trim() === 'Team'
  );
  await switcher.locator('summary').click();
  await page.locator('.visibility-menu').waitFor({ state: 'visible', timeout: 5000 });
  await shot(page, 'visibility-menu-open');
  await page.locator('.visibility-menu .comment-view-item', { hasText: 'private' }).first().click();
  await sleep(1500);
  const labelAfter = (await switcher.locator('.article-meta-val').innerText()).trim();
  check('switcher label flips to Private', /^Private/.test(labelAfter), labelAfter);
  check(
    'title row shows the private lock icon',
    (await page.locator('.article-title .doc-lock, .article-title svg.doc-lock').count()) > 0
  );

  const blocked = await readerGet();
  check(
    'second user now 404s on the private doc',
    blocked.status === 404,
    `status ${blocked.status}`
  );
  await shot(page, 'visibility-private');

  // ===== Share it back from the UI =====
  const menu = page.locator('.visibility-menu');
  // The switcher is a <details>; Elm owns the open state, so nudge the
  // summary until the menu is actually visible.
  for (let i = 0; i < 4 && !(await menu.isVisible()); i++) {
    await switcher.locator('summary').click();
    await sleep(400);
  }
  await menu.waitFor({ state: 'visible', timeout: 5000 });
  check(
    'private menu shows the "Shared with" empty state',
    (await page.locator('.share-empty').count()) === 1
  );
  const form = page.locator('.share-form');
  check('share form renders for a private doc', (await form.count()) === 1);
  const options = await form.locator('.share-select').first().locator('option').allInnerTexts();
  check(
    'share picker lists the second user',
    options.includes(S.reader.username),
    options.join(', ')
  );
  await shot(page, 'visibility-share-form');
  // Deliberately do NOT touch the <select> first — an onInput-only
  // binding would leave the username empty. Elm falls back to the
  // first candidate, so this must still work.
  await form.locator('.share-add-btn').click();
  await sleep(1500);
  const shares = (await apiOk(S.owner.token, 'GET', W(`/docs/${S.docs.shared}/shares`))).shares || [];
  check(
    'share created without touching the select',
    shares.some((s) => s.username === S.reader.username),
    JSON.stringify(shares)
  );
  const shareRowText = await page.locator('.share-row').first().innerText().catch(() => '');
  check('share row renders in the menu', shareRowText.includes(S.reader.username), shareRowText.replace(/\n/g, ' '));
  const labelWithShare = (await switcher.locator('.article-meta-val').innerText()).trim();
  check('switcher label counts the share', /Private · 1/.test(labelWithShare), labelWithShare);

  const restored = await readerGet();
  check(
    'second user can read the doc again once shared',
    restored.status === 200,
    `status ${restored.status}`
  );
  await shot(page, 'visibility-shared');

  // ===== Revoke from the UI =====
  await page.locator('.share-remove').first().click();
  await sleep(1500);
  const revoked = await readerGet();
  check('revoking the share 404s the second user again', revoked.status === 404, `status ${revoked.status}`);

  // Leave the doc as seeded.
  await apiOk(S.owner.token, 'PUT', W(`/docs/${S.docs.shared}/visibility`), { visibility: 'workspace' });

  const ok = report(page);
  await browser.close();
  process.exit(ok ? 0 : 1);
}

main().catch((e) => {
  console.error('SCRIPT ERROR', e);
  process.exit(2);
});
