// Flow 2 — /w/:slug/welcome, the setup vestibule.
//
//   node test/browser/auth/02_welcome.mjs
//
// Signs up a fresh account (UI), then inspects the welcome page: setup
// steps, copy-prompt CTA, orientation link, and the /papi/welcome
// payload actually rendering (decoder failures would blank the page).

import { BASE, Report, launch, newContext, shot, signupViaUi, watch } from "./lib.mjs"

const r = new Report("02 welcome")
const browser = await launch()
const ctx = await newContext(browser)
const page = await ctx.newPage()
const errs = watch(page)

const acct = await signupViaUi(page)
await page.waitForSelector("#welcome", { timeout: 15000 })
await page.waitForTimeout(800)
await shot(page, "02a-welcome")

// --- not a blank page -------------------------------------------------
const stageClass = await page.locator("#welcome").getAttribute("class")
r.ok("welcome stage rendered", !!stageClass, stageClass)
r.ok("welcome is not the error/fresh-only stub",
  await page.locator(".welcome-panel").count() > 0, `panels=${await page.locator(".welcome-panel").count()}`)

const h1 = await page.locator("h1.welcome-h1").first().textContent().catch(() => null)
r.ok("welcome headline names the workspace", h1 && h1.includes(acct.workspaceName), JSON.stringify(h1))

// --- setup steps ------------------------------------------------------
const steps = await page.locator(".welcome-step").count()
r.ok("setup steps rendered (4 expected)", steps === 4, `count=${steps}`)
// textContent, not innerText: the steps are <details>, collapsed by default.
const stepText = (await page.locator(".welcome-steps-box").evaluate((e) => e.textContent)).replace(/\s+/g, " ")
r.ok("step 1 links the CLI release", stepText.includes("github.com/aveline-ai/cli/releases/latest"))
r.ok("step 3 mentions this workspace slug", stepText.includes(acct.slug), acct.slug)
r.ok("step 4 mentions get-orientation", stepText.includes("get-orientation"))

// --- copy-prompt CTA --------------------------------------------------
const cta = page.locator("#welcome-copy")
r.ok("copy setup prompt CTA present", await cta.count() === 1)
r.ok("CTA labelled 'Copy setup prompt'", (await cta.textContent()).includes("Copy setup prompt"))
const snippet = (await page.locator("#welcome-snippet").textContent().catch(() => "")) || ""
r.ok("setup prompt snippet is non-empty", snippet.trim().length > 20, `${snippet.trim().length} chars`)
r.ok("prompt embeds the workspace slug", snippet.includes(acct.slug))

// Seed the clipboard so a no-op click is distinguishable from a copy.
await page.evaluate(() => navigator.clipboard.writeText("SENTINEL-NOT-COPIED"))
await cta.click()
await page.waitForTimeout(400)
const clip = await page.evaluate(() => navigator.clipboard.readText())
// KNOWN PORT BUG: the button kept the LiveView's `data-target` attribute,
// but the SPA's delegated handler (assets/js/fe-auth.js) only matches
// `[data-copy-target]`, and no Elm port replaces the CopyToken hook.
r.ok("CTA copies the prompt to the clipboard", clip.trim() === snippet.trim(),
  `clipboard=${JSON.stringify(clip.slice(0, 40))}`)
r.ok("CTA shows copied state", (await cta.textContent()).includes("Copied") ||
  (await cta.evaluate((e) => e.classList.contains("copied"))), await cta.textContent())
await shot(page, "02b-welcome-copied")

// --- orientation link -------------------------------------------------
const start = page.locator(".welcome-start a.welcome-start-doc")
if (r.ok("orientation start link present", await start.count() === 1)) {
  const href = await start.getAttribute("href")
  r.ok("orientation link points at a doc in this workspace", href && href.startsWith(`/w/${acct.slug}/d/`), href)
  await start.click()
  await page.waitForURL(new RegExp(`/w/${acct.slug}/d/`), { timeout: 15000 })
  r.ok("orientation link navigates", page.url().includes(`/w/${acct.slug}/d/`), page.url())
  await page.waitForTimeout(1200)
  await shot(page, "02c-orientation-doc")
  const bodyText = (await page.locator("body").innerText()).trim()
  r.ok("orientation doc page is not blank", bodyText.length > 40, `${bodyText.length} chars`)
}

r.finish(errs)
await browser.close()
