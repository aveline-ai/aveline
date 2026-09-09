import { chromium } from "playwright";
import fs from "fs";
const exe = process.env.HOME + "/Library/Caches/ms-playwright/chromium-1194/chrome-mac/Chromium.app/Contents/MacOS/Chromium";
const browser = await chromium.launch({ executablePath: fs.existsSync(exe) ? exe : undefined });
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true });
const page = await ctx.newPage();
await page.goto("http://localhost:4000/login/avl_locseed_alice_aaaaaaaaaaaaaaaaaa");
await page.waitForSelector(".sidebar", { timeout: 15000 });
const check = async (label) => {
  const collapsed = await page.evaluate(() => document.documentElement.classList.contains("sidebar-collapsed"));
  const toggleVisible = await page.locator(".sidebar-edge-toggle").isVisible().catch(() => false);
  const rail = await page.locator(".sidebar").boundingBox();
  console.log(`${label}: collapsed=${collapsed} toggleVisible=${toggleVisible} railWidth=${rail && Math.round(rail.width)}`);
  return collapsed && !toggleVisible;
};
const a = await check("fresh phone");
// Simulate a desktop "expanded" pref then reload on phone.
await page.evaluate(() => localStorage.setItem("aveline:sidebarCollapsed", "0"));
await page.reload();
await page.waitForSelector(".sidebar");
const b = await check("phone with expanded pref");
// Desktop width still honors the pref and shows the toggle region.
const dctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const dpage = await dctx.newPage();
await dpage.goto("http://localhost:4000/login/avl_locseed_alice_aaaaaaaaaaaaaaaaaa");
await dpage.waitForSelector(".sidebar");
const dcollapsed = await dpage.evaluate(() => document.documentElement.classList.contains("sidebar-collapsed"));
const dtoggle = await dpage.evaluate(() => getComputedStyle(document.querySelector(".sidebar-edge-toggle")).display !== "none");
console.log(`desktop: collapsed=${dcollapsed} toggleInDom=${dtoggle}`);
await page.screenshot({ path: "test/browser/screenshots/mobile-rail.png" });
console.log(a && b && !dcollapsed && dtoggle ? "PASS" : "FAIL");
await browser.close();
process.exit(a && b && !dcollapsed && dtoggle ? 0 : 1);
