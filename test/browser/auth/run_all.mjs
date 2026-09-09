// Runs every auth/onboarding browser check in order, sequentially.
//
//   node test/browser/auth/run_all.mjs
//
// Needs a dev server at $AVELINE_BASE (default http://localhost:4000).
// Each script signs up its own throwaway account(s), so runs are
// independent and repeatable.

import { spawn } from "node:child_process"
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const HERE = path.dirname(fileURLToPath(import.meta.url))
const scripts = fs.readdirSync(HERE).filter((f) => /^\d\d_.*\.mjs$/.test(f)).sort()

const results = []
for (const s of scripts) {
  console.log(`\n${"=".repeat(60)}\n${s}\n${"=".repeat(60)}`)
  const code = await new Promise((resolve) => {
    const p = spawn(process.execPath, [path.join(HERE, s)], { stdio: "inherit" })
    p.on("close", resolve)
  })
  results.push({ script: s, pass: code === 0 })
}

console.log(`\n${"=".repeat(60)}\nSUMMARY`)
for (const r of results) console.log(`  ${r.pass ? "PASS" : "FAIL"}  ${r.script}`)
process.exitCode = results.every((r) => r.pass) ? 0 : 1
