// Flow 4 — /new-workspace: live slug preview, creation, duplicate error.
//
//   node test/browser/auth/04_new_workspace.mjs

import { BASE, Report, launch, newContext, shot, stamp, signupViaUi, watch } from "./lib.mjs"

const r = new Report("04 new workspace")
const browser = await launch()
const ctx = await newContext(browser)
const page = await ctx.newPage()
const errs = watch(page)

const acct = await signupViaUi(page)
console.log(`  (signed up ${acct.username} / ${acct.slug})`)

await page.goto(`${BASE}/new-workspace`, { waitUntil: "networkidle" })
r.ok("form renders for a signed-in user", await page.locator("#ws-name").count() === 1)
r.ok("Create button disabled while empty", await page.locator("button.auth-submit").isDisabled())
await shot(page, "04a-new-workspace-empty")

// --- live slug preview ------------------------------------------------
const cases = [
  ["Acme Rockets", "acme-rockets"],
  ["Acme  --  Rockets!!", "acme-rockets"],
  // Aveline.Slug.derive downcases then maps runs of [^a-z0-9]+ to "-",
  // so non-ASCII letters become separators (Elm's port matches).
  ["Ünïcode Ω 42", "n-code-42"],
]
for (const [input, want] of cases) {
  await page.fill("#ws-name", input)
  await page.waitForTimeout(150)
  const slugPreview = (await page.locator(".auth-hint code").textContent()).trim()
  const hint = (await page.locator(".auth-hint").innerText()).trim()
  r.eq(`slug preview for ${JSON.stringify(input)}`, slugPreview, want)
  r.ok(`preview shows the aveline.ai/w/ prefix for ${JSON.stringify(input)}`, hint.startsWith("aveline.ai/w/"), hint)
}
await shot(page, "04b-slug-preview")

// --- client-side validation ------------------------------------------
await page.fill("#ws-name", "!!!")
await page.click("button.auth-submit")
await page.waitForTimeout(300)
r.eq("punctuation-only name rejected inline",
  (await page.locator(".auth-error").first().textContent()).trim(),
  "Name needs at least one letter or digit.")
await shot(page, "04c-invalid-name")

// --- creation ---------------------------------------------------------
// Deliberately messy name: the previewed slug must be the slug the
// server actually creates (client derive vs Aveline.Slug.derive).
const name = `BT WS ünïcode!! ${stamp()}`
await page.fill("#ws-name", name)
const expectedSlug = (await page.locator(".auth-hint code").textContent()).trim()
await page.click("button.auth-submit")
await page.waitForURL(/\/w\/[^/]+/, { timeout: 20000 })
await page.waitForTimeout(800)
const landedSlug = new URL(page.url()).pathname.split("/")[2]
r.eq("navigated to the newly created workspace", landedSlug, expectedSlug)
const bodyText = (await page.locator("body").innerText()).trim()
r.ok("new workspace page renders (not gated / not blank)",
  bodyText.length > 40 && !/private workspace/i.test(bodyText), `${bodyText.length} chars`)
await shot(page, "04d-created-workspace")

// --- duplicate name shows inline -------------------------------------
await page.goto(`${BASE}/new-workspace`, { waitUntil: "networkidle" })
await page.fill("#ws-name", name)
await page.click("button.auth-submit")
await page.waitForSelector(".auth-error", { timeout: 15000 })
const dupErr = (await page.locator(".auth-error").first().textContent()).trim()
r.eq("duplicate name shows the inline slug_taken message", dupErr,
  "That name is already in use. Pick a different one.")
r.ok("stayed on /new-workspace after the duplicate", new URL(page.url()).pathname === "/new-workspace", page.url())
r.ok("input marked with the error class", await page.locator("#ws-name").evaluate((e) => e.className.includes("auth-input-error")))
await shot(page, "04e-duplicate-name")

// --- signed-out visitors bounce to /login -----------------------------
await page.goto(`${BASE}/logout`, { waitUntil: "networkidle" })
await page.goto(`${BASE}/new-workspace`, { waitUntil: "networkidle" })
await page.waitForTimeout(1000)
r.ok("signed-out /new-workspace bounces to /login", new URL(page.url()).pathname === "/login", page.url())
await shot(page, "04f-new-workspace-logged-out")

r.finish(errs)
await browser.close()
