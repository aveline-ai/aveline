// Flow 6 — the workspace access gate (Plugs.WorkspaceGate).
//
//   node test/browser/auth/06_gate.mjs
//
// Logged out (and as a signed-in non-member), a /w/* URL must render the
// branded private page AT the URL — not the SPA shell, not a redirect to
// signup.

import { BASE, Report, launch, newContext, shot, signupViaUi, watch } from "./lib.mjs"

const r = new Report("06 workspace gate")
const browser = await launch()

const ownerCtx = await newContext(browser)
const ownerPage = await ownerCtx.newPage()
const errs = watch(ownerPage)
const owner = await signupViaUi(ownerPage)
console.log(`  (owner ${owner.username} / ${owner.slug})`)

// --- logged out -------------------------------------------------------
const anonCtx = await newContext(browser)
const anon = await anonCtx.newPage()
watch(anon, errs)

for (const [label, url] of [
  ["workspace home", `${BASE}/w/${owner.slug}`],
  ["a doc URL", `${BASE}/w/${owner.slug}/d/how-we-use-aveline-here`],
  ["a nonexistent workspace", `${BASE}/w/definitely-not-a-workspace-xyz`],
]) {
  const res = await anon.goto(url, { waitUntil: "networkidle" })
  const html = await anon.content()
  const text = (await anon.locator("body").innerText()).replace(/\s+/g, " ")
  r.ok(`${label}: served AT the URL (no redirect)`, anon.url() === url, anon.url())
  r.ok(`${label}: not the SPA shell`, !html.includes('id="spa-bootstrap"') && !html.includes('id="elm-root"'))
  r.ok(`${label}: branded private gate rendered`, /private/i.test(text) || /log in/i.test(text), text.slice(0, 160))
  r.ok(`${label}: noindex`, /noindex/.test(html))
  r.ok(`${label}: generic OG title (leaks nothing)`,
    /og:title" content="A private (doc|workspace) on Aveline/.test(html) && !html.includes(owner.workspaceName),
    (html.match(/og:title" content="[^"]*"/) || [])[0])
  r.ok(`${label}: status ok-ish`, res && res.status() < 500, String(res && res.status()))
}
await shot(anon, "06a-gate-logged-out")

// the login link on the gate carries `next` back to the URL
await anon.goto(`${BASE}/w/${owner.slug}`, { waitUntil: "networkidle" })
const links = await anon.locator("a").evaluateAll((as) => as.map((a) => a.getAttribute("href")))
r.ok("gate links to /login", links.some((h) => h && h.includes("/login")), JSON.stringify(links))

// --- signed in, not a member ------------------------------------------
const strangerCtx = await newContext(browser)
const stranger = await strangerCtx.newPage()
watch(stranger, errs)
const other = await signupViaUi(stranger)
await stranger.goto(`${BASE}/w/${owner.slug}`, { waitUntil: "networkidle" })
const strangerHtml = await stranger.content()
const strangerText = (await stranger.locator("body").innerText()).replace(/\s+/g, " ")
r.ok("non-member gets the no-access gate, not the SPA",
  !strangerHtml.includes('id="spa-bootstrap"'), strangerText.slice(0, 160))
r.ok("no-access gate doesn't leak the workspace name", !strangerHtml.includes(owner.workspaceName))
r.ok("no-access gate served at the URL", stranger.url() === `${BASE}/w/${owner.slug}`, stranger.url())
await shot(stranger, "06b-gate-non-member")

// --- and the member still gets the app --------------------------------
await ownerPage.goto(`${BASE}/w/${owner.slug}`, { waitUntil: "networkidle" })
const ownerHtml = await ownerPage.content()
r.ok("member gets the SPA shell", ownerHtml.includes('id="spa-bootstrap"'))
await shot(ownerPage, "06c-member-passes-gate")

r.finish(errs)
await browser.close()
