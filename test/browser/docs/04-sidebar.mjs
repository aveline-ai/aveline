// Flow 4 — sidebar chrome on the docs pages.
//
//   node test/browser/docs/04-sidebar.mjs   (seed.mjs first)
//
// Nav items, the pinned saved view in the sidebar, active-item
// highlighting, and the collapse toggle (html.sidebar-collapsed) with
// localStorage persistence across a reload.
import { launch, newPage, loadState, apiOk, check, report, shot, sleep } from './lib.mjs';

const S = loadState();
const W = (p) => `/api/workspaces/${S.workspace}${p}`;

const NAV = ['Home', 'Docs', 'Data sources', 'Activity', 'Team', 'Settings'];

async function main() {
  // Only PINNED views show in the sidebar (Chrome.sectionsFromViews).
  await apiOk(S.owner.token, 'POST', W(`/views/${S.view}/pin`), {});

  const browser = await launch();
  const pages = [
    ['docs list', `/w/${S.workspace}/docs`],
    ['doc show', `/w/${S.workspace}/d/${S.docs.rich}`],
    ['saved view', `/w/${S.workspace}/v/${S.view}`],
  ];

  let page;
  for (const [label, path] of pages) {
    page = await newPage(browser, S.owner.token, { next: path });
    await page.waitForSelector('.sidebar', { timeout: 15000 });
    const navLabels = await page.locator('.sidebar .sidebar-item').allInnerTexts();
    const flat = navLabels.map((t) => t.trim());
    check(
      `[${label}] sidebar renders every nav item`,
      NAV.every((n) => flat.some((t) => t === n)),
      flat.join(' | ')
    );
    check(
      `[${label}] pinned saved view listed in the sidebar`,
      flat.some((t) => t === S.view),
      `views section: ${(await page.locator('.sidebar-views').allInnerTexts()).join(' / ').replace(/\n/g, ' ')}`
    );
    check(
      `[${label}] workspace name in the sidebar header`,
      (await page.locator('.sidebar-workspace').innerText()).trim().length > 0,
      (await page.locator('.sidebar-workspace').innerText()).trim()
    );
    check(
      `[${label}] user footer renders`,
      (await page.locator('.sidebar').innerText()).includes(S.owner.username)
    );
    const active = (await page.locator('.sidebar .sidebar-item.active').allInnerTexts())
      .map((t) => t.trim())
      .join(',');
    // Chrome.navActiveFor: the doc-show route deliberately highlights
    // nothing ("DocShow sets none"), mirroring the LiveView.
    const expected = label === 'doc show' ? '' : label === 'saved view' ? S.view : 'Docs';
    check(`[${label}] correct nav item highlighted`, active === expected, `active="${active}" expected="${expected}"`);
    await shot(page, `sidebar-${label.replace(/\s+/g, '-')}`);
    if (label !== 'saved view') await page.context().close();
  }

  // ===== Collapse toggle (on the saved-view page still open) =====
  const htmlClass = () => page.evaluate(() => document.documentElement.className);
  const stored = () => page.evaluate(() => localStorage.getItem('aveline:sidebarCollapsed'));
  const startClass = await htmlClass();
  check('sidebar starts expanded', !/sidebar-collapsed/.test(startClass), `html class="${startClass}"`);
  const toggle = page.locator('[data-sidebar-toggle]').first();
  check('collapse toggle button present', (await toggle.count()) > 0);
  await toggle.click();
  await sleep(400);
  const collapsedClass = await htmlClass();
  check(
    'clicking the toggle adds html.sidebar-collapsed',
    /sidebar-collapsed/.test(collapsedClass),
    `html class="${collapsedClass}"`
  );
  check('collapse state persisted to localStorage', (await stored()) === '1', `stored=${await stored()}`);
  await shot(page, 'sidebar-collapsed');

  await page.reload({ waitUntil: 'networkidle' });
  await page.waitForSelector('.sidebar', { timeout: 15000 });
  check(
    'collapsed state survives a reload',
    /sidebar-collapsed/.test(await htmlClass()),
    `html class="${await htmlClass()}"`
  );
  const widthCollapsed = await page.evaluate(
    () => document.querySelector('.sidebar').getBoundingClientRect().width
  );

  // Expand again.
  await page.locator('[data-sidebar-toggle]').first().click();
  await sleep(500);
  check(
    'toggling back removes the collapsed class',
    !/sidebar-collapsed/.test(await htmlClass()),
    `html class="${await htmlClass()}"`
  );
  check('expanded preference persisted', (await stored()) === '0', `stored=${await stored()}`);
  const widthExpanded = await page.evaluate(
    () => document.querySelector('.sidebar').getBoundingClientRect().width
  );
  check(
    'collapsed sidebar is visually narrower',
    widthCollapsed < widthExpanded,
    `${widthCollapsed}px collapsed vs ${widthExpanded}px expanded`
  );
  await page.reload({ waitUntil: 'networkidle' });
  await page.waitForSelector('.sidebar', { timeout: 15000 });
  check('expanded state survives a reload', !/sidebar-collapsed/.test(await htmlClass()));

  const ok = report(page);
  await browser.close();
  process.exit(ok ? 0 : 1);
}

main().catch((e) => {
  console.error('SCRIPT ERROR', e);
  process.exit(2);
});
