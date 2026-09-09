// Flow 2 — the doc reader (/w/:slug/d/:doc-slug).
//
//   node test/browser/docs/02-doc-show.mjs   (run seed.mjs first)
//
// Block rendering per type, aveline-code highlighting, block-anchored
// comments, posting a reply from the UI (verified back through the
// API), the kudos toggle, and the version switcher / historical banner
// after an API edit.
import { launch, newPage, loadState, apiOk, check, report, shot, sleep } from './lib.mjs';

const S = loadState();
const W = (p) => `/api/workspaces/${S.workspace}${p}`;
const DOC = `/w/${S.workspace}/d/${S.docs.rich}`;

async function main() {
  // Re-runs leave threads resolved (the composer's "Reply & resolve"
  // button); unresolve everything first so the default "open" comment
  // view shows the seeded threads again.
  const seeded = (await apiOk(S.owner.token, 'GET', W(`/docs/${S.docs.rich}/comments`))).comments;
  for (const c of seeded.filter((c) => c.resolved_at)) {
    await apiOk(S.owner.token, 'POST', W(`/comments/${c.id}/unresolve`), {});
  }

  const browser = await launch();
  const page = await newPage(browser, S.owner.token, { next: DOC });
  await page.waitForSelector('.blocks', { timeout: 15000 });

  // ===== Block types =====
  const counts = {
    h1: await page.locator('.blocks .blk-h1').count(),
    h2: await page.locator('.blocks .blk-h2').count(),
    p: await page.locator('.blocks .blk-p').count(),
    list: await page.locator('.blocks .blk-list').count(),
    code: await page.locator('.blocks .blk-code-wrap').count(),
    table: await page.locator('.blocks .blk-table').count(),
    unknown: await page.locator('.blocks .blk-unknown').count(),
  };
  check('heading blocks render (h1 + h2)', counts.h1 === 1 && counts.h2 >= 1, JSON.stringify(counts));
  check('paragraph block renders', counts.p >= 1);
  check('both list blocks render', counts.list === 2, `${counts.list} lists`);
  check(
    'ordered list is <ol>, bulleted is <ul>',
    (await page.locator('ol.blk-list').count()) === 1 && (await page.locator('ul.blk-list').count()) === 1
  );
  check('both code blocks render', counts.code === 2, `${counts.code} code wraps`);
  check('table block renders with header + rows', counts.table === 1);
  check(
    'table has 2 headers and 2 body rows',
    (await page.locator('.blk-table thead th').count()) === 2 &&
      (await page.locator('.blk-table tbody tr').count()) === 2
  );
  check('no unknown blocks in the seeded doc', counts.unknown === 0, `${counts.unknown} unknown`);

  // Inline spans
  const paraHtml = await page.locator('.blocks .blk-p').first().innerHTML();
  check('paragraph renders bold mark', /<strong|<b[ >]/.test(paraHtml), paraHtml.slice(0, 200));
  check('paragraph renders a link', /<a [^>]*href="https:\/\/example.com"/.test(paraHtml));

  // doc_link card
  const docLinkHref = await page
    .locator(`.blocks a[href*="/d/${S.docs.target}"]`)
    .count();
  check('doc_link block renders a card linking the target doc', docLinkHref > 0, `${docLinkHref} links`);

  // ===== Code highlighting via the aveline-code custom element =====
  const codeEl = page.locator('aveline-code').first();
  check('aveline-code custom element present', (await codeEl.count()) > 0);
  const upgraded = await page.evaluate(() => {
    const el = document.querySelector('aveline-code');
    return {
      defined: !!customElements.get('aveline-code'),
      childHtml: el ? el.innerHTML.slice(0, 400) : null,
      tokenSpans: el ? el.querySelectorAll('span').length : 0,
      hasPre: !!(el && el.querySelector('pre')),
    };
  });
  check('aveline-code is a defined custom element', upgraded.defined);
  check('aveline-code renders a <pre>', upgraded.hasPre, JSON.stringify(upgraded).slice(0, 300));
  check(
    'aveline-code highlights (token spans present)',
    upgraded.tokenSpans > 0,
    `${upgraded.tokenSpans} spans`
  );
  await shot(page, 'doc-show-blocks');

  // ===== Comments anchored to blocks =====
  const zones = await page.locator('.block-comments').count();
  check('block comment zones render', zones >= 2, `${zones} zones`);
  for (const c of S.comments) {
    const anchored = await page.evaluate((blockId) => {
      // The comment zone is a sibling that follows the block element.
      const block =
        document.getElementById(blockId) ||
        document.querySelector(`[id="${blockId}"]`);
      if (!block) return { found: false, reason: 'block element missing' };
      let node = block.closest('.blk-anchored') || block;
      // Walk forward to the next .block-comments sibling.
      let next = node.nextElementSibling;
      while (next && !next.classList.contains('block-comments')) {
        if (next.classList.contains('blk-anchored')) return { found: false, reason: 'next block first' };
        next = next.nextElementSibling;
      }
      return { found: !!next, text: next ? next.innerText.slice(0, 120) : null };
    }, c.block_id);
    check(
      `comment anchored under the ${c.type} block`,
      anchored.found && /Seeded comment/.test(anchored.text || ''),
      JSON.stringify(anchored).slice(0, 200)
    );
  }
  const docLevel = await page.locator('#discussion').innerText().catch(() => '');
  check('doc-level comment shown in the discussion section', /doc-level comment/.test(docLevel), docLevel.slice(0, 120));

  // ===== Post a reply from the UI =====
  const before = (await apiOk(S.owner.token, 'GET', W(`/docs/${S.docs.rich}/comments`))).comments.length;
  await page.locator('.comment-card-reply-btn').first().click();
  const input = page.locator('.comment-composer-input').first();
  await input.waitFor({ state: 'visible', timeout: 5000 });
  const replyBody = `UI reply ${Date.now()}`;
  await input.fill(replyBody);
  // NOT .first() — that is "Reply & resolve", which would hide the
  // thread under the default "open" comment view.
  await page.locator('button.comment-composer-submit:not(.comment-composer-submit-resolve)').first().click();
  await sleep(1500);
  const after = (await apiOk(S.owner.token, 'GET', W(`/docs/${S.docs.rich}/comments`))).comments;
  check(
    'reply posted from the UI persists (API sees it)',
    after.length === before + 1 && after.some((c) => (c.body || '').includes(replyBody)),
    `${before} -> ${after.length}`
  );
  const liveText = await page.locator('.blocks').innerText();
  const bodyText = await page.evaluate(() => document.body.innerText);
  check('reply appears in the DOM without a reload', bodyText.includes(replyBody),
    bodyText.includes(replyBody) ? '' : 'reply body absent from the live DOM after the post round-trip');
  await page.reload({ waitUntil: 'networkidle' });
  await page.waitForSelector('.blocks', { timeout: 15000 });
  const afterReload = await page.evaluate(() => document.body.innerText);
  check('reply appears after a reload', afterReload.includes(replyBody));
  void liveText;
  await shot(page, 'doc-show-comments');

  // ===== Kudos toggle =====
  // The owner never sees a kudos button on their own doc (product
  // rule in DocShow.viewHeader), so kudos runs as the second user.
  check(
    'owner sees no kudos button on their own doc',
    (await page.locator('.article-kudos-btn').count()) === 0
  );
  const readerPage = await newPage(browser, S.reader.token, { next: DOC });
  await readerPage.waitForSelector('.blocks', { timeout: 15000 });
  const kudosBtn = readerPage.locator('.article-kudos-btn').first();
  check('kudos button present for a non-owner', (await kudosBtn.count()) > 0);
  // The doc page shows no kudos number by design ("icon-only, no
  // count", app.css) — the count lives on the docs-list card, so that
  // is where the count is verified.
  // fe/docs-list is a browser-session route (/papi), so fetch it from
  // inside the logged-in page.
  const cardKudos = async () => {
    const list = await readerPage.evaluate(
      async (u) => (await fetch(u, { headers: { accept: 'application/json' } })).json(),
      `/papi/workspaces/${S.workspace}/fe/docs-list?limit=100`
    );
    const docs = list.docs || list.items || [];
    const d = docs.find((x) => x.slug === S.docs.rich);
    return d ? (d.kudos_count ?? d.kudos ?? null) : null;
  };
  const beforeLabel = await kudosBtn.getAttribute('title');
  const beforeClass = await kudosBtn.getAttribute('class');
  const beforeCount = await cardKudos();
  await kudosBtn.click();
  await sleep(1200);
  const afterLabel = await kudosBtn.getAttribute('title');
  const afterPressed = await kudosBtn.getAttribute('aria-pressed');
  const afterClass = await kudosBtn.getAttribute('class');
  const afterCount = await cardKudos();
  check('kudos button toggles state', beforeLabel !== afterLabel, `${beforeLabel} -> ${afterLabel}`);
  check('kudos aria-pressed reflects the new state', afterPressed === 'false', `aria-pressed=${afterPressed}`);
  check(
    'kudos is-given class drops on untoggle',
    /is-given/.test(beforeClass || '') && !/is-given/.test(afterClass || ''),
    `"${beforeClass}" -> "${afterClass}"`
  );
  check('kudos count changes', beforeCount !== afterCount, `${beforeCount} -> ${afterCount}`);
  await shot(readerPage, 'doc-show-kudos');
  // Toggle back on so the seeded kudos survives for re-runs.
  await kudosBtn.click();
  await sleep(1000);
  const revertedLabel = await kudosBtn.getAttribute('title');
  const revertedCount = await cardKudos();
  check('kudos toggles back', revertedLabel === beforeLabel, `${afterLabel} -> ${revertedLabel}`);
  check('kudos count returns to its original value', revertedCount === beforeCount, `${afterCount} -> ${revertedCount}`);
  for (const l of readerPage.logs) page.logs.push({ ...l, text: `[reader] ${l.text}` });

  // ===== Version history =====
  await apiOk(S.owner.token, 'PATCH', W(`/docs/${S.docs.rich}`), {
    intent: 'Browser test edit — adds a second version.',
    actor: 'human',
    operations: [
      {
        op: 'append_block',
        block: { type: 'paragraph', content: [{ text: 'Appended by the version-history test.' }] },
      },
    ],
  });
  await page.reload({ waitUntil: 'networkidle' });
  await page.waitForSelector('.blocks', { timeout: 15000 });
  const switcher = page.locator('.version-switcher-trigger').first();
  check('version switcher appears after a second version', (await page.locator('.version-switcher').count()) > 0);
  await switcher.click();
  await sleep(500);
  const versionItems = await page.locator('.version-switcher-menu .version-switcher-num').allInnerTexts();
  check(
    'version switcher lists both versions',
    versionItems.length >= 2,
    versionItems.join(', ')
  );
  await shot(page, 'doc-show-version-menu');
  const v1 = page.locator(`.version-switcher-menu a[href*="/v/1"]`).first();
  const v1Count = await v1.count();
  check('version menu links to v1', v1Count > 0);
  if (v1Count) {
    await v1.click();
    await page.waitForFunction(() => location.pathname.includes('/v/1'), null, { timeout: 10000 });
    await page.waitForSelector('.blocks', { timeout: 15000 });
    const banner = await page.locator('.doc-banner-historical').count();
    check('historical version renders the banner', banner === 1);
    const bannerText = banner ? await page.locator('.doc-banner-historical').innerText() : '';
    check('banner names the version', /v1/.test(bannerText), bannerText.replace(/\n/g, ' ').slice(0, 160));
    const hasAppended = (await page.locator('.blocks').innerText()).includes(
      'Appended by the version-history test'
    );
    check('v1 body excludes the v2-only block', !hasAppended);
    await shot(page, 'doc-show-historical');

    // Historical pages are read-only: .doc-readonly hides the composer
    // (app.css) and DocShow.guardWrite drops any write. The per-thread
    // "Reply" prompt is NOT hidden though, so it is a live button that
    // opens an invisible composer — a dead affordance.
    const readonlyClass = await page.locator('.doc-layout, .prose, [class*="doc-readonly"]').first().getAttribute('class');
    const replyBtn = page.locator('.comment-card-reply-btn').first();
    const replyVisible = (await replyBtn.count()) > 0 && (await replyBtn.isVisible());
    let composerVisible = null;
    if (replyVisible) {
      await replyBtn.click();
      await sleep(600);
      composerVisible = await page.locator('.comment-composer-input').first().isVisible().catch(() => false);
    }
    check(
      'historical page hides the reply affordance (read-only)',
      !replyVisible,
      `reply button visible=${replyVisible}; composer visible after click=${composerVisible}; wrapper class="${readonlyClass}"`
    );
  }

  const ok = report(page);
  await browser.close();
  process.exit(ok ? 0 : 1);
}

main().catch((e) => {
  console.error('SCRIPT ERROR', e);
  process.exit(2);
});
