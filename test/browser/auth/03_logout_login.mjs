// Flow 3 — logout, then log back in by pasting the API key at /login.
//
//   node test/browser/auth/03_logout_login.mjs

import { BASE, Report, cssLoaded, launch, newContext, shot, signupViaUi, watch } from "./lib.mjs"

const r = new Report("03 logout → login")
const browser = await launch()
const ctx = await newContext(browser)
const page = await ctx.newPage()
const errs = watch(page)

const acct = await signupViaUi(page)
console.log(`  (signed up ${acct.username} / ${acct.slug})`)

// --- logout -----------------------------------------------------------
await page.goto(`${BASE}/logout`, { waitUntil: "networkidle" })
await shot(page, "03a-after-logout")
const bootAfterLogout = await page.evaluate(() =>
  JSON.parse(document.getElementById("spa-bootstrap")?.textContent || "{}"))
r.ok("logged out (bootstrap user is null)", bootAfterLogout.user === null || bootAfterLogout.user === undefined,
  JSON.stringify(bootAfterLogout.user))

// A workspace URL now gates instead of rendering the app.
await page.goto(`${BASE}/w/${acct.slug}`, { waitUntil: "domcontentloaded" })
r.ok("workspace no longer reachable after logout", !(await page.locator("#spa-bootstrap").count()) ||
  (await page.evaluate(() => JSON.parse(document.getElementById("spa-bootstrap")?.textContent || "{}").user)) === null)

// --- login form -------------------------------------------------------
await page.goto(`${BASE}/login`, { waitUntil: "networkidle" })
r.ok("login form renders", await page.locator("#token").count() === 1)
const css = await cssLoaded(page)
r.ok("app.css loaded on /login", css.appCss)
r.ok("login card styled", css.cardPadding && css.cardPadding !== "0px", css.cardPadding)
r.ok("link to signup present", await page.locator("a.auth-link").count() >= 1)
await shot(page, "03b-login-form")

// --- bad token shows inline error ------------------------------------
await page.fill("#token", "avl_definitely_not_a_real_token_000000")
await page.click("button.auth-submit")
await page.waitForSelector(".auth-error", { timeout: 10000 })
const badErr = (await page.locator(".auth-error").first().textContent()).trim()
r.ok("invalid token shows an inline error", badErr.length > 0, JSON.stringify(badErr))
r.ok("stayed on /login after a bad token", new URL(page.url()).pathname === "/login", page.url())
await shot(page, "03c-login-bad-token")

// --- real token -------------------------------------------------------
await page.fill("#token", acct.token)
await page.click("button.auth-submit")
await page.waitForURL((u) => !u.pathname.startsWith("/login"), { timeout: 20000 })
await page.waitForTimeout(800)
r.ok("login lands back inside the app", page.url().includes(`/w/${acct.slug}`) || new URL(page.url()).pathname === "/",
  page.url())

const cookies = await ctx.cookies()
r.ok("session cookie set after login", cookies.some((c) => c.name === "_aveline_key"), cookies.map((c) => c.name).join(","))
const boot = await page.evaluate(() =>
  JSON.parse(document.getElementById("spa-bootstrap")?.textContent || "{}"))
r.eq("bootstrap user is the signed-in account", boot.user && boot.user.username, acct.username)
await shot(page, "03d-after-login")

// --- deep link → gate → login → back where you were -------------------
// LoginLive carried `?next=` into the POST /login form so SessionController
// landed you back on the requested URL (it sanitizes to relative paths).
const deepLink = `/w/${acct.slug}/d/how-we-use-aveline-here`
await page.goto(`${BASE}/logout`, { waitUntil: "networkidle" })
await page.goto(`${BASE}${deepLink}`, { waitUntil: "networkidle" })
const gateLogin = await page.locator('a[href*="/login"]').first().getAttribute("href")
r.ok("gate's login link carries ?next= back to the deep link",
  gateLogin && decodeURIComponent(gateLogin).includes(`next=${deepLink}`), gateLogin)
await page.goto(`${BASE}${gateLogin}`, { waitUntil: "networkidle" })
await shot(page, "03f-login-with-next")
await page.fill("#token", acct.token)
await page.click("button.auth-submit")
await page.waitForURL((u) => !u.pathname.startsWith("/login"), { timeout: 20000 })
await page.waitForTimeout(900)
// KNOWN PORT BUG: Page/Login.elm ignores the `next` query param and always
// does Nav.load "/" after POST /papi/session.
r.ok("login honors ?next= and returns to the deep link",
  new URL(page.url()).pathname === deepLink, page.url())
await shot(page, "03g-after-login-with-next")

// --- and the workspace renders again ---------------------------------
await page.goto(`${BASE}/w/${acct.slug}`, { waitUntil: "networkidle" })
await page.waitForTimeout(900)
const bodyText = (await page.locator("body").innerText()).trim()
r.ok("workspace home renders for the signed-in user", bodyText.length > 40 && !/private workspace/i.test(bodyText),
  `${bodyText.length} chars`)
await shot(page, "03e-workspace-home")

r.finish(errs)
await browser.close()
