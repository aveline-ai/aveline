// Creates two accounts + a workspace and seeds docs/pins/tags/comments/
// kudos/events, then writes .state.json for the per-page test scripts.
import { signup, api, saveState, BASE } from './lib.mjs';

const stamp = Date.now().toString(36);
const owner = `bt-owner-${stamp}`;
const mate = `bt-mate-${stamp}`;

const para = (t) => [{ type: 'paragraph', content: [{ text: t }] }];

const main = async () => {
  const o = await signup({ username: owner, workspaceName: `Browser Test ${stamp}` });
  const slug = o.workspace.slug;
  console.log('owner', owner, 'ws', slug, 'token', o.token);
  const A = api(o.token, slug);

  // second user, own workspace, then added as a member of ours
  const m = await signup({ username: mate, workspaceName: `Mate WS ${stamp}` });
  await A.post('/members', { username: mate });
  const M = api(m.token, slug);

  // tags
  for (const t of [
    { name: 'metrics', description: 'Numbers we watch' },
    { name: 'runbook', description: 'How to operate things' },
    { name: 'decisions', description: 'Why we chose things' },
  ]) {
    await A.post('/tags', t).catch((e) => console.log('tag skip', e.message));
  }

  // docs
  const docs = [];
  for (let i = 1; i <= 6; i++) {
    const d = await A.post('/docs', {
      title: `Seeded doc ${i}`,
      summary: `Summary for seeded doc ${i}`,
      tags: [['metrics', 'runbook', 'decisions'][i % 3]],
      blocks: para(`Body of seeded doc ${i}.`),
      intent: 'seed',
      actor: 'human',
      visibility: 'workspace',
    });
    docs.push(d.slug || d.doc?.slug || `seeded-doc-${i}`);
  }
  console.log('docs', docs);

  // pins
  await A.post(`/docs/${docs[0]}/pin`);
  await A.post(`/docs/${docs[1]}/pin`);

  // comment from the second user on the owner's doc
  const c = await M.post(`/docs/${docs[0]}/comments`, {
    body: 'Is this number still right after the migration?',
  });
  const c2 = await A.post(`/docs/${docs[2]}/comments`, {
    body: 'Adding context for the team here.',
  });
  console.log('comments', JSON.stringify(c).slice(0, 200));

  // kudos + edits, enough to push the activity feed past 25 events
  for (const d of docs) {
    await M.post(`/docs/${d}/kudos`).catch((e) => console.log('kudos', e.message));
  }
  for (let round = 1; round <= 4; round++) {
    for (const d of docs) {
      const full = await A.get(`/docs/${d}`);
      const blocks = full.doc.blocks;
      blocks[0].content = [{ text: `Body of ${d}, revision ${round}.` }];
      await A.raw('PATCH', `/docs/${d}`, { blocks, intent: `edit round ${round}` });
    }
  }

  const events = await A.get('/events?limit=100');
  const count = (events.events || events).length;
  console.log('event count', count);

  const invite = await A.post('/invite');
  console.log('invite', invite.url);

  saveState({
    base: BASE,
    slug,
    owner: { username: owner, token: o.token, id: o.user.id },
    mate: { username: mate, token: m.token, id: m.user.id },
    docs,
    commentBody: 'Is this number still right after the migration?',
    eventCount: count,
  });
  console.log('state saved');
};

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
