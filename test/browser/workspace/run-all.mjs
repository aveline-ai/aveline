// Runs every workspace flow in order. Assumes seed.mjs has been run
// (node test/browser/workspace/seed.mjs) and a dev server on :4000.
import { spawnSync } from 'node:child_process';
import { HERE } from './lib.mjs';
import path from 'node:path';

const flows = ['home.mjs', 'team.mjs', 'settings.mjs', 'activity.mjs', 'data-sources.mjs', 'nav.mjs'];
let bad = 0;
for (const f of flows) {
  const res = spawnSync(process.execPath, [path.join(HERE, f)], { stdio: 'inherit' });
  if (res.status !== 0) bad++;
}
console.log(bad ? `\n${bad} flow(s) had failures` : '\nall flows green');
process.exit(bad ? 1 : 0);
