// Shared helpers for the auth/onboarding browser checks.
//
// These scripts drive the real Elm SPA at BASE (default
// http://localhost:4000) with Playwright. Each `NN_*.mjs` script is
// standalone: `node test/browser/auth/01_signup.mjs`.
//
// Screenshots land in test/browser/screenshots/.

import { chromium } from "playwright"
import { fileURLToPath } from "node:url"
import path from "node:path"
import fs from "node:fs"

export const BASE = process.env.AVELINE_BASE || "http://localhost:4000"

const HERE = path.dirname(fileURLToPath(import.meta.url))
export const SHOTS = path.resolve(HERE, "../screenshots")
fs.mkdirSync(SHOTS, { recursive: true })

// ---------------------------------------------------------------- misc

export const stamp = () => Date.now().toString(36)

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

// ------------------------------------------------------- browser setup

/**
 * The pinned playwright build may be newer than what's in the local
 * ms-playwright cache (no network installs here), so fall back to the
 * newest cached chrome-headless-shell we can find.
 */
function cachedHeadlessShell() {
  const root = process.env.PLAYWRIGHT_BROWSERS_PATH ||
    path.join(process.env.HOME || "", "Library/Caches/ms-playwright")
  if (!fs.existsSync(root)) return undefined
  const builds = fs
    .readdirSync(root)
    .filter((d) => d.startsWith("chromium_headless_shell-"))
    .sort((a, b) => Number(b.split("-")[1]) - Number(a.split("-")[1]))
  for (const b of builds) {
    for (const arch of ["mac-x64", "mac-arm64", "linux", "win"]) {
      const p = path.join(root, b, `chrome-headless-shell-${arch}`, "chrome-headless-shell")
      if (fs.existsSync(p)) return p
    }
  }
  return undefined
}

export async function launch() {
  try {
    return await chromium.launch()
  } catch (err) {
    const exe = cachedHeadlessShell()
    if (!exe) throw err
    return await chromium.launch({ executablePath: exe })
  }
}

/** A fresh, logged-out context with clipboard permissions granted. */
export async function newContext(browser) {
  const ctx = await browser.newContext({
    viewport: { width: 1280, height: 900 },
    permissions: ["clipboard-read", "clipboard-write"],
  })
  return ctx
}

/**
 * Attach console / pageerror / failed-request capture to a page.
 * Returns the array it appends to (shared, live).
 */
export function watch(page, sink = []) {
  page.on("console", (m) => {
    if (m.type() === "error" || m.type() === "warning") {
      sink.push({ kind: `console.${m.type()}`, text: m.text(), url: page.url() })
    }
  })
  page.on("pageerror", (e) => {
    sink.push({ kind: "pageerror", text: e.message, url: page.url() })
  })
  page.on("requestfailed", (r) => {
    sink.push({ kind: "requestfailed", text: `${r.method()} ${r.url()} — ${r.failure()?.errorText}`, url: page.url() })
  })
  page.on("response", (r) => {
    if (r.status() >= 500) sink.push({ kind: "http5xx", text: `${r.status()} ${r.url()}`, url: page.url() })
  })
  return sink
}

export async function shot(page, name) {
  const file = path.join(SHOTS, `${name}.png`)
  await page.screenshot({ path: file, fullPage: true })
  return path.basename(file)
}

// -------------------------------------------------------- assertions

export class Report {
  constructor(title) {
    this.title = title
    this.checks = []
  }
  ok(name, cond, detail = "") {
    this.checks.push({ name, pass: !!cond, detail })
    console.log(`${cond ? "  PASS" : "  FAIL"}  ${name}${detail ? ` — ${detail}` : ""}`)
    return !!cond
  }
  eq(name, actual, expected) {
    return this.ok(name, actual === expected, `got ${JSON.stringify(actual)}, want ${JSON.stringify(expected)}`)
  }
  finish(consoleErrors = []) {
    const failed = this.checks.filter((c) => !c.pass)
    console.log(`\n${this.title}: ${this.checks.length - failed.length}/${this.checks.length} checks passed`)
    if (consoleErrors.length) {
      console.log(`console/network noise (${consoleErrors.length}):`)
      for (const e of consoleErrors) console.log(`  [${e.kind}] ${e.text}`)
    } else {
      console.log("console: clean")
    }
    if (failed.length) {
      process.exitCode = 1
      console.log(`\nRESULT: FAIL (${failed.map((f) => f.name).join("; ")})`)
    } else {
      console.log(`\nRESULT: PASS`)
    }
  }
}

// ------------------------------------------------------------- helpers

/** True when app.css actually applied (not just requested). */
export async function cssLoaded(page) {
  return page.evaluate(() => {
    const sheets = [...document.styleSheets].map((s) => s.href || "inline")
    const card = document.querySelector(".auth-card")
    const cs = card ? getComputedStyle(card) : null
    return {
      sheets,
      appCss: sheets.some((h) => h && h.includes("/assets/css/app.css")),
      cardPadding: cs ? cs.padding : null,
      cardBg: cs ? cs.backgroundColor : null,
      bodyBg: getComputedStyle(document.body).backgroundColor,
      bodyFont: getComputedStyle(document.body).fontFamily,
    }
  })
}

/**
 * Full signup through the real UI. Leaves `page` on /w/:slug/welcome.
 * Returns { username, workspaceName, slug, token }.
 */
export async function signupViaUi(page, opts = {}) {
  const username = opts.username || `bt-${stamp()}`
  const workspaceName = opts.workspaceName || `BT ${stamp()} ${Math.floor(Math.random() * 1e4)}`

  await page.goto(`${BASE}/signup`, { waitUntil: "networkidle" })
  await page.waitForSelector("#signup-form")
  await page.waitForFunction(() => {
    const el = document.querySelector("#preview-token-value")
    return el && el.value.startsWith("avl_")
  })
  const token = await page.inputValue("#preview-token-value")

  await page.fill("#username", username)
  await page.fill("#ws-name", workspaceName)
  await page.click("#preview-copy-btn")
  await page.click("button.auth-submit")
  await page.waitForURL(/\/w\/[^/]+\/welcome/, { timeout: 15000 })

  const slug = new URL(page.url()).pathname.split("/")[2]
  return { username, workspaceName, slug, token }
}

/** Mint (or fetch) the workspace invite code via the Bearer API. */
export async function mintInvite(token, slug) {
  const res = await fetch(`${BASE}/api/workspaces/${slug}/invite`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: "{}",
  })
  const body = await res.json()
  return { status: res.status, body }
}
