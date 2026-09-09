// Regression check: carets on grouped docs sections hide the group body.
import { chromium } from "playwright";
import fs from "fs";

const state = JSON.parse(fs.readFileSync(new URL("./state.json", import.meta.url), "utf8"));
const token = JSON.stringify(state).match(/avl_[A-Za-z0-9_-]+/)[0];
const ws = JSON.stringify(state).match(/browser-test-[a-z0-9]+/)[0];
const api = async (method, path, body) =>
  fetch(`http://localhost:4000/api/workspaces/${ws}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: body && JSON.stringify(body),
  }).then((r) => r.json());

// Seed a scoped tag pair + tag two docs so "Group by status" exists.
for (const v of ["todo", "done"]) {
  await api("POST", "/tags", { slug: `status:${v}`, description: `Status ${v} for collapse check.` });
}
const docs = (await api("GET", "/docs?limit=2")).docs || [];
for (const [i, d] of docs.entries()) {
  await api("PATCH", `/docs/${d.slug}`, {
    operations: [],
    tags: [`status:${i === 0 ? "todo" : "done"}`],
    intent: "collapse check",
  });
}

const exe =
  process.env.HOME +
  "/Library/Caches/ms-playwright/chromium-1194/chrome-mac/Chromium.app/Contents/MacOS/Chromium";
const browser = await chromium.launch({ executablePath: fs.existsSync(exe) ? exe : undefined });
const page = await browser.newPage();
await page.goto(`http://localhost:4000/login/${token}`);
await page.goto(`http://localhost:4000/w/${ws}/docs`);
await page.waitForSelector(".docs-controls");

await page.locator("#fdd-group .fdd-btn").click();
await page.waitForTimeout(150);
await page.evaluate(() => {
  const item = [...document.querySelectorAll("#fdd-group .fdd-item")].find((b) =>
    b.textContent.includes("status")
  );
  item.click();
});
await page.waitForSelector(".group-block");
// Dismiss the dropdown's click-away overlay before touching the carets.
await page.mouse.click(5, 5);
await page.waitForTimeout(100);

const head = page.locator(".group-head").first();
const body = page.locator(".group-body").first();
const before = await body.isVisible();
await head.click();
await page.waitForTimeout(200);
const after = await body.isVisible();
await head.click();
await page.waitForTimeout(200);
const reopened = await body.isVisible();
console.log(
  `visible before=${before} collapsed=${!after} reopened=${reopened} -> ` +
    (before && !after && reopened ? "PASS" : "FAIL")
);
await browser.close();
process.exit(before && !after && reopened ? 0 : 1);
