// Flow 1 — /signup (preview-token signup) → /w/:slug/welcome.
//
//   node test/browser/auth/01_signup.mjs
//
// Checks: CSS applied, preview token minted, username input behavior,
// copy gate enforced, submit creates the account + session and lands on
// the welcome vestibule. Writes the resulting credentials to
// test/browser/auth/.state.json for convenience (gitignore-able).

import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { BASE, Report, cssLoaded, launch, newContext, shot, stamp, watch } from "./lib.mjs"

const HERE = path.dirname(fileURLToPath(import.meta.url))
const r = new Report("01 signup")
const browser = await launch()
const ctx = await newContext(browser)
const page = await ctx.newPage()
const errs = watch(page)

const username = `bt-signup-${stamp()}`
const workspaceName = `BT Signup ${stamp()}`

// --- form renders -----------------------------------------------------
await page.goto(`${BASE}/signup`, { waitUntil: "networkidle" })
r.ok("signup form renders", await page.locator("#signup-form").count() === 1)

const css = await cssLoaded(page)
r.ok("app.css loaded", css.appCss, css.sheets.join(", "))
r.ok("auth-card actually styled", css.cardPadding && css.cardPadding !== "0px", `padding=${css.cardPadding}`)
r.ok("Inter webfont applied to body", /Inter/.test(css.bodyFont || ""), css.bodyFont)
r.ok("auth background canvas present", await page.locator("#auth-canvas-organic, #auth-canvas-matrix").count() > 0)

// --- preview token ----------------------------------------------------
await page.waitForFunction(() => {
  const el = document.querySelector("#preview-token-value")
  return el && el.value.startsWith("avl_")
}, null, { timeout: 10000 })
const previewToken = await page.inputValue("#preview-token-value")
r.ok("preview token minted (avl_…)", previewToken.startsWith("avl_"), `${previewToken.slice(0, 8)}… len=${previewToken.length}`)
r.ok("token field is readonly", await page.locator("#preview-token-value").evaluate((e) => e.readOnly))

await shot(page, "01a-signup-form")

// --- submit gated while empty ----------------------------------------
r.ok("Sign up disabled with empty fields", await page.locator("button.auth-submit").isDisabled())

// --- typing behavior (validation-as-you-type probe) -------------------
// The old SignupLive did *pure input capture* on "validate" — no
// messages until submit. We record what the Elm page does so a
// regression either way is visible.
await page.fill("#username", "A")            // 1 char + uppercase
await page.waitForTimeout(500)
const errAfterShort = await page.locator(".auth-error").allTextContents()
const normalized = await page.inputValue("#username")
r.eq("username normalized to lowercase while typing", normalized, "a")
r.ok("no live message for too-short username (matches LiveView: validate is pure capture)",
  errAfterShort.length === 0, JSON.stringify(errAfterShort))

await page.fill("#username", "Not Valid!")
await page.waitForTimeout(400)
const errAfterBad = await page.locator(".auth-error").allTextContents()
r.ok("no live message for bad-format username (matches LiveView)", errAfterBad.length === 0, JSON.stringify(errAfterBad))
await shot(page, "01b-signup-typing")

// --- server-side validation on submit ---------------------------------
await page.fill("#username", "a")
await page.fill("#ws-name", workspaceName)
await page.click("button.auth-submit")
await page.waitForSelector(".auth-error", { timeout: 10000 })
r.eq("too-short username rejected on submit", (await page.locator(".auth-error").first().textContent()).trim(),
  "Username too short (min 2).")

await page.fill("#username", "bad name!")
await page.click("button.auth-submit")
await page.waitForTimeout(600)
r.eq("bad-format username rejected on submit", (await page.locator(".auth-error").first().textContent()).trim(),
  "Lowercase letters, digits, and hyphens only.")
await shot(page, "01c-signup-submit-validation")

// --- copy gate --------------------------------------------------------
await page.fill("#username", username)
await page.fill("#ws-name", workspaceName)
await page.click("button.auth-submit")
await page.waitForSelector(".auth-error", { timeout: 10000 })
r.eq("copy gate enforced before account creation",
  (await page.locator(".auth-error").first().textContent()).trim(),
  "Copy the API key first. You will not be able to see it again.")
await shot(page, "01d-copy-gate")

r.ok("copy button not yet in 'copied' state", !(await page.locator("#preview-copy-btn").evaluate((e) => e.classList.contains("copied"))))
await page.click("#preview-copy-btn")
await page.waitForTimeout(200)
r.ok("copy button flips to Copied ✓", (await page.locator("#preview-copy-btn").textContent()).includes("Copied"))
const clip = await page.evaluate(() => navigator.clipboard.readText())
r.eq("clipboard holds the token", clip, previewToken)
await shot(page, "01e-copied")

// --- create the account ----------------------------------------------
await page.click("button.auth-submit")
await page.waitForURL(/\/w\/[^/]+\/welcome/, { timeout: 20000 })
const slug = new URL(page.url()).pathname.split("/")[2]
r.ok("landed on /w/:slug/welcome", /\/w\/.+\/welcome$/.test(new URL(page.url()).pathname), page.url())

// session cookie present + signed in
const cookies = await ctx.cookies()
r.ok("session cookie set", cookies.some((c) => /_aveline_key|session/i.test(c.name)), cookies.map((c) => c.name).join(","))
const boot = await page.evaluate(() => JSON.parse(document.getElementById("spa-bootstrap").textContent))
r.eq("bootstrap user is the new account", boot.user && boot.user.username, username)

// the token we copied is the token that works
const who = await fetch(`${BASE}/api/me`, { headers: { authorization: `Bearer ${previewToken}` } })
const whoBody = await who.json().catch(() => ({}))
r.ok("copied token authenticates against the API", who.status === 200 && whoBody?.user?.username === username,
  `${who.status} ${JSON.stringify(whoBody).slice(0, 200)}`)

await shot(page, "01f-welcome-after-signup")

fs.writeFileSync(path.join(HERE, ".state.json"), JSON.stringify({ username, workspaceName, slug, token: previewToken }, null, 2))
console.log(`\nstate: username=${username} slug=${slug}`)

r.finish(errs)
await browser.close()
