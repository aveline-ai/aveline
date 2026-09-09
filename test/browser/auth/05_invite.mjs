// Flow 5 — /invite/:code.
//
//   node test/browser/auth/05_invite.mjs
//
// Signs up an inviter (UI), mints the workspace invite over the Bearer
// API, then opens the link in a *logged-out* context and completes the
// invite signup form. Also covers the live "Username taken." check, the
// "Sign in instead" toggle, the signed-in Join confirm, and an invalid
// code.

import { BASE, Report, launch, mintInvite, newContext, shot, stamp, signupViaUi, watch } from "./lib.mjs"

const r = new Report("05 invite")
const browser = await launch()

// --- inviter ----------------------------------------------------------
const ownerCtx = await newContext(browser)
const ownerPage = await ownerCtx.newPage()
const errs = watch(ownerPage)
const owner = await signupViaUi(ownerPage)
console.log(`  (inviter ${owner.username} / ${owner.slug})`)

const minted = await mintInvite(owner.token, owner.slug)
r.ok("POST /api/workspaces/:slug/invite mints a code", minted.status === 200 && !!minted.body.code,
  `${minted.status} ${JSON.stringify(minted.body)}`)
const code = minted.body.code
const inviteUrl = `${BASE}/invite/${code}`

// --- invalid code -----------------------------------------------------
const anonCtx = await newContext(browser)
const anon = await anonCtx.newPage()
watch(anon, errs)
await anon.goto(`${BASE}/invite/inv_totally_bogus_code_xyz`, { waitUntil: "networkidle" })
await anon.waitForSelector(".auth-card", { timeout: 10000 })
await anon.waitForTimeout(400)
const invalidText = (await anon.locator(".auth-card").innerText()).replace(/\s+/g, " ")
r.ok("invalid code renders the 'Invite link expired' card", /Invite link expired/i.test(invalidText), invalidText.slice(0, 120))
r.ok("invalid card explains what to do", /no longer valid/i.test(invalidText))
await shot(anon, "05a-invite-invalid")

// --- valid code, logged out -------------------------------------------
await anon.goto(inviteUrl, { waitUntil: "networkidle" })
await anon.waitForSelector("#invite-signup-form", { timeout: 10000 })
const introText = (await anon.locator(".auth-subtitle").innerText()).replace(/\s+/g, " ")
r.ok("invite form names the workspace", introText.includes(owner.workspaceName), introText)
r.ok("invite form invites a username", /Pick a username/i.test(introText))
await anon.waitForFunction(() => {
  const el = document.querySelector("#preview-token-value")
  return el && el.value.startsWith("avl_")
}, null, { timeout: 10000 })
const inviteeToken = await anon.inputValue("#preview-token-value")
r.ok("invite form mints a preview API key", inviteeToken.startsWith("avl_"))
r.ok("Join button labelled with the workspace", (await anon.locator("#invite-signup-form button.auth-submit").textContent())
  .includes(`Join ${owner.workspaceName}`))
await shot(anon, "05b-invite-form")

// --- live username validation (this page DOES validate as you type) ---
await anon.fill("#username", "a")
await anon.waitForTimeout(400)
r.eq("live too-short message", (await anon.locator(".auth-error").first().textContent().catch(() => "")).trim(),
  "Too short (minimum 2 characters).")
await anon.fill("#username", "Bad Name!")
await anon.waitForTimeout(400)
r.eq("live bad-format message", (await anon.locator(".auth-error").first().textContent().catch(() => "")).trim(),
  "Use lowercase letters, digits, and hyphens. Must start with a letter or digit.")
await anon.fill("#username", owner.username)
await anon.waitForTimeout(900) // 250ms debounce + roundtrip
r.eq("live 'Username taken.' via /papi/signup/username-status",
  (await anon.locator(".auth-error").first().textContent().catch(() => "")).trim(), "Username taken.")
await shot(anon, "05c-invite-username-taken")

// --- toggle to the token form and back --------------------------------
await anon.locator(".auth-footer button.auth-link").click()
await anon.waitForTimeout(300)
r.ok("'Sign in instead' toggles to the token form", await anon.locator("#invite-login-form").count() === 1)
await shot(anon, "05d-invite-token-form")
await anon.locator(".auth-footer button.auth-link").click()
await anon.waitForTimeout(300)
r.ok("'Create an account' toggles back", await anon.locator("#invite-signup-form").count() === 1)

// --- copy gate + join -------------------------------------------------
const invitee = `bt-invitee-${stamp()}`
await anon.fill("#username", invitee)
await anon.waitForTimeout(600)
await anon.click("#invite-signup-form button.auth-submit")
await anon.waitForSelector(".auth-error", { timeout: 10000 })
r.eq("copy gate enforced on the invite form",
  (await anon.locator(".auth-error").first().textContent()).trim(),
  "Copy the API key first. You will not be able to see it again.")

await anon.click("#preview-copy-btn")
await anon.waitForTimeout(200)
r.ok("copy button flips to Copied ✓", (await anon.locator("#preview-copy-btn").textContent()).includes("Copied"))
await anon.click("#invite-signup-form button.auth-submit")
await anon.waitForURL(/\/w\/[^/]+\/welcome/, { timeout: 20000 })
const landed = new URL(anon.url()).pathname.split("/")[2]
r.eq("invitee lands in the inviter's workspace", landed, owner.slug)
await anon.waitForTimeout(900)
await shot(anon, "05e-invitee-welcome")

const boot = await anon.evaluate(() => JSON.parse(document.getElementById("spa-bootstrap").textContent))
r.eq("invitee is signed in", boot.user && boot.user.username, invitee)

// membership is real, per the API
const members = await fetch(`${BASE}/api/workspaces/${owner.slug}/members`, {
  headers: { authorization: `Bearer ${inviteeToken}` },
}).then((res) => res.json()).catch(() => ({}))
const names = (members.members || []).map((m) => m.username)
r.ok("invitee is a workspace member per the API", names.includes(invitee), JSON.stringify(names))

// --- signed-in visitor gets the Join confirm --------------------------
const otherCtx = await newContext(browser)
const other = await otherCtx.newPage()
watch(other, errs)
const outsider = await signupViaUi(other)
await other.goto(inviteUrl, { waitUntil: "networkidle" })
await other.waitForSelector(".auth-card button.auth-submit", { timeout: 10000 })
const confirmText = (await other.locator(".auth-card").innerText()).replace(/\s+/g, " ")
r.ok("signed-in visitor sees the Join confirm", confirmText.includes(`Join ${owner.workspaceName}`), confirmText.slice(0, 160))
r.ok("confirm names the signed-in user", confirmText.includes(outsider.username))
await shot(other, "05f-invite-signed-in-confirm")
await other.locator(".auth-card button.auth-submit").click()
await other.waitForURL(new RegExp(`/w/${owner.slug}`), { timeout: 20000 })
await other.waitForTimeout(800)
r.ok("accepting joins the workspace", other.url().includes(`/w/${owner.slug}`), other.url())
await shot(other, "05g-invite-accepted")

r.finish(errs)
await browser.close()
