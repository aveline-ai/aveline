// Seeds a throwaway workspace for the docs browser tests.
//
//   node test/browser/docs/seed.mjs
//
// Creates two users (owner + reader) through the real signup API, then
// fills the owner's workspace with tags, richly-blocked docs, comments,
// kudos, a saved view, and 30 filler docs so the docs list paginates.
// Writes test/browser/docs/state.json for the other scripts.
import { BASE, apiOk, api, launch, saveState } from './lib.mjs';

const stamp = Date.now().toString(36);

async function signup(browser, username, workspaceName) {
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  await page.goto(`${BASE}/signup`, { waitUntil: 'domcontentloaded' });
  // The SPA ships its CSRF token in the #spa-bootstrap JSON blob.
  const csrf = await page.evaluate(
    () => JSON.parse(document.getElementById('spa-bootstrap').textContent).csrf
  );
  const out = await page.evaluate(
    async ({ csrf, username, workspaceName }) => {
      const h = { 'Content-Type': 'application/json', 'x-csrf-token': csrf };
      const pt = await (await fetch('/papi/signup/preview-token', { headers: h })).json();
      const token = pt.data ? pt.data.token : pt.token;
      const res = await fetch('/papi/signup', {
        method: 'POST',
        headers: h,
        body: JSON.stringify({ username, workspace_name: workspaceName, copied: true, token }),
      });
      return { status: res.status, body: await res.json() };
    },
    { csrf, username, workspaceName }
  );
  await ctx.close();
  if (out.status >= 300) throw new Error(`signup ${username}: ${JSON.stringify(out)}`);
  const d = out.body.data || out.body;
  return { username, token: d.token, workspace: d.workspace };
}

const spans = (...texts) => texts.map((t) => (typeof t === 'string' ? { text: t } : t));

async function main() {
  const browser = await launch();
  const owner = await signup(browser, `bt-owner-${stamp}`, `Browser Test ${stamp}`);
  const reader = await signup(browser, `bt-reader-${stamp}`, `Reader Space ${stamp}`);
  await browser.close();

  const ws = owner.workspace.slug;
  const W = (p) => `/api/workspaces/${ws}${p}`;
  console.log(`owner=${owner.username} reader=${reader.username} ws=${ws}`);

  // Reader joins the owner's workspace.
  await apiOk(owner.token, 'POST', W('/members'), { username: reader.username });

  // ===== Tags (a fresh workspace ships with some already) =====
  const existing = new Set(
    (await apiOk(owner.token, 'GET', W('/tags'))).tags.map((t) => t.slug)
  );
  console.log('tags already present:', [...existing].join(', ') || '(none)');
  for (const [name, desc] of [
    ['runbook', 'Operational runbooks for the browser test'],
    ['design', 'Design notes for the browser test'],
    ['archive', 'Older material kept for the browser test'],
  ]) {
    if (existing.has(name)) continue;
    await apiOk(owner.token, 'POST', W('/tags'), { name, description: desc });
  }

  // ===== Docs =====
  // A target doc for the doc_link block.
  const target = await apiOk(owner.token, 'POST', W('/docs'), {
    title: 'Deploy Runbook',
    summary: 'How we ship.',
    tags: ['runbook'],
    visibility: 'workspace',
    blocks: [
      { type: 'heading', level: 2, text: 'Steps' },
      { type: 'paragraph', content: spans('Push, then watch the dashboard.') },
    ],
  });

  // The kitchen-sink doc every block-type check runs against.
  const rich = await apiOk(owner.token, 'POST', W('/docs'), {
    title: 'Block Gallery',
    summary: 'One of every block type.',
    tags: ['design', 'runbook'],
    visibility: 'workspace',
    blocks: [
      { type: 'heading', level: 1, text: 'Gallery H1' },
      { type: 'heading', level: 2, text: 'Gallery H2' },
      {
        type: 'paragraph',
        content: spans(
          'Plain, then ',
          { text: 'bold', marks: ['bold'] },
          ', then ',
          { text: 'code span', marks: ['code'] },
          ', and a ',
          { text: 'link', link: { href: 'https://example.com' } },
          '.'
        ),
      },
      {
        type: 'list',
        ordered: false,
        items: [{ content: spans('bullet one') }, { content: spans('bullet two') }],
      },
      {
        type: 'list',
        ordered: true,
        items: [{ content: spans('step one') }, { content: spans('step two') }],
      },
      { type: 'code', language: 'elixir', content: 'defmodule Hi do\n  def go, do: IO.puts("hi")\nend' },
      { type: 'code', language: null, content: 'no language here' },
      {
        type: 'table',
        headers: ['Name', 'Role'],
        rows: [
          [spans('Ada'), spans('Engineer')],
          [spans('Grace'), spans('Admiral')],
        ],
      },
      { type: 'doc_link', doc: 'deploy-runbook', note: spans('See the deploy runbook.') },
      // NOTE: `quote` and `divider` are NOT block types in
      // Aveline.Contract — POST /docs rejects them with 422
      // validation_failed, so they cannot be seeded at all.
    ],
  });

  // A doc that starts workspace-visible; flow 3 flips it private via UI.
  const shared = await apiOk(owner.token, 'POST', W('/docs'), {
    title: 'Visibility Lab',
    summary: 'Flipped private and re-shared by the UI test.',
    tags: ['design'],
    visibility: 'workspace',
    blocks: [{ type: 'paragraph', content: spans('Visible to the whole workspace, for now.') }],
  });

  // A doc for the search test with a distinctive term.
  await apiOk(owner.token, 'POST', W('/docs'), {
    title: 'Zarquon Migration Plan',
    summary: 'Contains the unique search term zarquon.',
    tags: ['archive'],
    visibility: 'workspace',
    blocks: [{ type: 'paragraph', content: spans('zarquon zarquon zarquon') }],
  });

  // ===== Comments anchored to blocks =====
  const richDoc = (await apiOk(owner.token, 'GET', W(`/docs/${rich.slug}`))).doc;
  const blocks = richDoc.blocks;
  const byType = (t) => blocks.find((b) => b.type === t);
  const anchors = [byType('paragraph'), byType('code')].filter(Boolean);
  const commentIds = [];
  for (const [i, b] of anchors.entries()) {
    const c = await apiOk(owner.token, 'POST', W(`/docs/${rich.slug}/comments`), {
      body: `Seeded comment ${i + 1} on a ${b.type} block.`,
      block_id: b.id,
      actor: 'human',
    });
    commentIds.push({ id: c.id, block_id: b.id, type: b.type });
  }
  // A doc-level comment too.
  await apiOk(owner.token, 'POST', W(`/docs/${rich.slug}/comments`), {
    body: 'Seeded doc-level comment.',
    actor: 'human',
  });

  // ===== Kudos from the second user =====
  await apiOk(reader.token, 'POST', W(`/docs/${rich.slug}/kudos`), {});

  // ===== Saved view =====
  await apiOk(owner.token, 'POST', W('/views'), {
    name: 'design-only',
    description: 'Only design-tagged docs',
    config: { tags: ['design'], sort: 'recent' },
    bucket: 'yours',
  });
  // Only pinned views appear in the sidebar (Chrome.sectionsFromViews).
  await apiOk(owner.token, 'POST', W(`/views/design-only/pin`), {});

  // ===== 30 filler docs so the list paginates =====
  for (let i = 1; i <= 30; i++) {
    await apiOk(owner.token, 'POST', W('/docs'), {
      title: `Filler Doc ${String(i).padStart(2, '0')}`,
      summary: `Filler ${i}`,
      tags: i % 2 === 0 ? ['archive'] : ['runbook'],
      visibility: 'workspace',
      blocks: [{ type: 'paragraph', content: spans(`Body of filler ${i}.`) }],
    });
  }

  const counts = await api(owner.token, 'GET', W('/docs?limit=100'));
  const state = {
    base: BASE,
    workspace: ws,
    owner,
    reader,
    docs: {
      rich: rich.slug,
      target: target.slug,
      shared: shared.slug,
      search: 'zarquon-migration-plan',
    },
    comments: commentIds,
    view: 'design-only',
    totalDocs: (counts.json.docs || []).length,
  };
  saveState(state);
  console.log(`seeded. docs in workspace: ${state.totalDocs}`);
  console.log(`owner login: ${BASE}/login/${owner.token}?next=/w/${ws}/docs`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
