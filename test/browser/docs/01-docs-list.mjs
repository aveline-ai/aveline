// Flow 1 — the docs list (/w/:slug/docs).
//
//   node test/browser/docs/01-docs-list.mjs   (run seed.mjs first)
//
// Cards + tags + authors, search, tag-filter dropdown counts, sort
// switch, saved-view switcher, and load-more past 25 docs.
import { launch, newPage, loadState, check, report, shot, sleep } from './lib.mjs';

const S = loadState();
const DOCS = `/w/${S.workspace}/docs`;

const cardCount = (page) => page.locator('.card-list .card').count();

async function main() {
  const browser = await launch();
  const page = await newPage(browser, S.owner.token, { next: DOCS });
  await page.waitForSelector('.card-list .card', { timeout: 15000 });

  // ===== Cards render with tags + authors =====
  const n = await cardCount(page);
  check('docs list renders cards', n >= 25, `${n} cards on first page`);
  check(
    'cards carry tag chips',
    (await page.locator('.card .chip-tag').count()) > 0,
    `${await page.locator('.card .chip-tag').count()} tag chips`
  );
  check(
    'cards carry author chips',
    (await page.locator('.card .chip-author').count()) > 0,
    `${await page.locator('.card .chip-author').count()} author chips`
  );
  await shot(page, 'docs-list-initial');

  // ===== Load more (37 docs seeded, page size 25) =====
  const hasLoadMore = await page.locator('.load-more-btn').count();
  check('load-more button shown with >25 docs', hasLoadMore === 1, `${n} cards, button=${hasLoadMore}`);
  if (hasLoadMore) {
    await page.click('.load-more-btn');
    await page.waitForFunction((prev) => document.querySelectorAll('.card-list .card').length > prev, n, {
      timeout: 10000,
    });
    const n2 = await cardCount(page);
    check('load more appends docs', n2 > n, `${n} -> ${n2}`);
    const titles = await page.locator('.card .card-title').allInnerTexts();
    check(
      'seeded rich doc appears in the full list',
      titles.some((t) => t.includes('Block Gallery')),
      `${titles.length} titles`
    );
    await shot(page, 'docs-list-loaded-more');
  }

  // ===== Search =====
  await page.fill('.search-input', 'zarquon');
  await page.keyboard.press('Enter');
  await page.waitForFunction(
    () => document.querySelectorAll('.card-list .card').length <= 3,
    null,
    { timeout: 10000 }
  );
  const searchTitles = await page.locator('.card .card-title').allInnerTexts();
  check(
    'search filters to the matching doc',
    searchTitles.length >= 1 && searchTitles.every((t) => /zarquon/i.test(t)),
    JSON.stringify(searchTitles)
  );
  await shot(page, 'docs-list-search');

  await page.fill('.search-input', '');
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => document.querySelectorAll('.card-list .card').length > 5, null, {
    timeout: 10000,
  });

  // ===== Tag filter dropdown =====
  await page.click('#fdd-tag .fdd-btn');
  let menuVisible = true;
  try {
    await page.locator('#fdd-tag-menu').waitFor({ state: 'visible', timeout: 5000 });
  } catch {
    menuVisible = false;
  }
  check('tag dropdown opens', menuVisible);
  const items = await page.locator('#fdd-tag-menu .fdd-item').count();
  const counts = await page.locator('#fdd-tag-menu .fdd-item-count').allInnerTexts();
  const nonZero = counts.filter((c) => c.trim() !== '0' && c.trim() !== '');
  check('tag dropdown lists tags', items > 0, `${items} items`);
  check(
    'tag dropdown shows non-zero facet counts',
    nonZero.length > 0,
    `counts: ${counts.slice(0, 8).join(',')}`
  );
  await shot(page, 'docs-list-tag-dropdown');

  // Pick the "design" tag (2 seeded docs).
  const designItem = page
    .locator('#fdd-tag-menu .fdd-item')
    .filter({ has: page.locator('.fdd-item-label', { hasText: /^design$/ }) })
    .first();
  const designExists = (await designItem.count()) > 0;
  if (designExists) {
    const label = await designItem.innerText();
    await designItem.click();
    await page.waitForFunction(() => document.querySelectorAll('.card-list .card').length <= 5, null, {
      timeout: 10000,
    });
    const filtered = await page.locator('.card .card-title').allInnerTexts();
    check(
      'tag filter narrows the list',
      filtered.length > 0 && filtered.length <= 5,
      `${filtered.length} docs for tag design (menu said "${label.replace(/\n/g, ' ')}")`
    );
    const chips = await page.locator('.card').first().locator('.chip-tag').allInnerTexts();
    check('filtered cards carry the tag', chips.includes('design'), chips.join(','));
    await shot(page, 'docs-list-tag-filtered');
    // Clear it again.
    await designItem.click();
    await sleep(600);
    await page.keyboard.press('Escape');
  } else {
    check('tag filter narrows the list', false, 'no "design" item in the tag dropdown');
  }

  // ===== Sort switch =====
  await page.click('body', { position: { x: 5, y: 5 } });
  await page.click('#fdd-sort .fdd-btn');
  await page.locator('#fdd-sort-menu').waitFor({ state: 'visible', timeout: 5000 });
  check('sort dropdown opens', await page.locator('#fdd-sort-menu').isVisible());
  const firstBefore = (await page.locator('.card .card-title').first().innerText()).trim();
  await page.locator('#fdd-sort-menu .fdd-item', { hasText: 'Kudos' }).first().click();
  await sleep(1200);
  const sortLabel = await page.locator('#fdd-sort .fdd-btn').innerText();
  const firstAfter = (await page.locator('.card .card-title').first().innerText()).trim();
  check('sort switch updates the button label', /Kudos/.test(sortLabel), sortLabel.trim());
  check(
    'sort switch reorders (Block Gallery has the only kudos)',
    firstAfter !== firstBefore || /Block Gallery/.test(firstAfter),
    `${firstBefore} -> ${firstAfter}`
  );
  await shot(page, 'docs-list-sorted-kudos');

  // ===== Saved view switcher =====
  await page.click('#fdd-view .title-fdd-btn');
  const viewMenu = page.locator('#fdd-view-menu');
  await viewMenu.waitFor({ state: 'visible', timeout: 5000 });
  check('view switcher opens', await viewMenu.isVisible());
  const viewNames = await viewMenu.locator('.vmenu-name').allInnerTexts();
  check(
    'saved view listed in the switcher',
    viewNames.some((v) => v.includes(S.view)),
    viewNames.join(' | ')
  );
  await shot(page, 'docs-list-view-menu');
  await viewMenu.locator('.vmenu-item', { hasText: S.view }).first().click();
  await page.waitForFunction(() => location.pathname.includes('/v/'), null, { timeout: 10000 });
  await sleep(1200);
  const viewTitles = await page.locator('.card .card-title').allInnerTexts();
  check(
    'applying the saved view filters the list',
    viewTitles.length > 0 && viewTitles.length <= 5,
    `${viewTitles.length} docs: ${viewTitles.join(', ')}`
  );
  check(
    'view page title shows the view name',
    (await page.locator('.page-title').innerText()).includes(S.view),
    await page.locator('.page-title').innerText()
  );
  await shot(page, 'docs-list-view-applied');

  const ok = report(page);
  await browser.close();
  process.exit(ok ? 0 : 1);
}

main().catch(async (e) => {
  console.error('SCRIPT ERROR', e);
  process.exit(2);
});
