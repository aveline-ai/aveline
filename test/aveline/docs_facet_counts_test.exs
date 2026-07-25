defmodule Aveline.DocsFacetCountsTest do
  use Aveline.DataCase, async: false

  alias Aveline.{Docs, Fixtures, Workspaces}

  setup do
    owner = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(owner)
    %{owner: owner, ws: ws}
  end

  test "counts the full filtered corpus, not just one page", %{owner: owner, ws: ws} do
    for i <- 1..5 do
      Fixtures.doc_fixture(ws, owner, slug: "prod-#{i}", tags: ["product"])
    end

    page = Docs.list_current(ws.id, viewer: owner.id, limit: 2)
    assert length(page) == 2

    assert Docs.facet_counts(ws.id, viewer: owner.id).tags["product"] == 5
    # Scoped to the tag filter so workspace-seeded docs stay out of the way.
    assert Docs.facet_counts(ws.id, viewer: owner.id, tags: ["product"]).owners ==
             %{owner.id => 5}
  end

  test "respects viewer scoping: private docs never counted for non-shared members", %{
    owner: owner,
    ws: ws
  } do
    member = Fixtures.user_fixture()
    {:ok, _} = Workspaces.ensure_member(ws.id, member.id)

    Fixtures.doc_fixture(ws, owner, slug: "open", tags: ["product"])
    Fixtures.doc_fixture(ws, owner, slug: "secret", tags: ["product"], visibility: "private")

    assert Docs.facet_counts(ws.id, viewer: owner.id).tags["product"] == 2
    assert Docs.facet_counts(ws.id, viewer: member.id).tags["product"] == 1
    # Omitted viewer fails closed, same as list_current.
    assert Docs.facet_counts(ws.id).tags["product"] == 1
  end

  test "respects the active tag and search filters", %{owner: owner, ws: ws} do
    other = Fixtures.user_fixture()
    {:ok, _} = Workspaces.ensure_member(ws.id, other.id)
    {:ok, _} = Aveline.Tags.create(ws.id, "planning", "Planning docs.", owner.id)
    {:ok, _} = Aveline.Tags.create(ws.id, "ops", "Ops docs.", owner.id)

    Fixtures.doc_fixture(ws, owner,
      slug: "roadmap",
      title: "Roadmap",
      tags: ["product", "planning"]
    )

    Fixtures.doc_fixture(ws, owner, slug: "spec", title: "Widget spec", tags: ["product"])
    Fixtures.doc_fixture(ws, other, slug: "runbook", title: "Runbook", tags: ["ops"])

    # Tag filter: only docs carrying "product" contribute.
    facets = Docs.facet_counts(ws.id, viewer: owner.id, tags: ["product"])
    assert facets.tags == %{"product" => 2, "planning" => 1}
    assert facets.owners == %{owner.id => 2}

    # Search filter narrows the corpus the same way list_current does.
    facets = Docs.facet_counts(ws.id, viewer: owner.id, search: "widget")
    assert facets.tags == %{"product" => 1}
    assert facets.owners == %{owner.id => 1}
  end

  test "two selected tags AND together; remaining counts reflect the intersection", %{
    owner: owner,
    ws: ws
  } do
    {:ok, _} = Aveline.Tags.create(ws.id, "planning", "Planning docs.", owner.id)
    {:ok, _} = Aveline.Tags.create(ws.id, "ops", "Ops docs.", owner.id)

    Fixtures.doc_fixture(ws, owner, slug: "both", tags: ["product", "planning"])
    Fixtures.doc_fixture(ws, owner, slug: "both-plus", tags: ["product", "planning", "ops"])
    Fixtures.doc_fixture(ws, owner, slug: "prod-only", tags: ["product"])
    Fixtures.doc_fixture(ws, owner, slug: "plan-only", tags: ["planning"])

    # One tag selected: the other chips count docs that ALSO carry it.
    facets = Docs.facet_counts(ws.id, viewer: owner.id, tags: ["product"])
    assert facets.tags == %{"product" => 3, "planning" => 2, "ops" => 1}

    # Two selected: intersection only. Selected chips read the corpus
    # size; "ops" reads 1 (the doc carrying all three); absent keys
    # (count 0) are what the UI renders disabled.
    facets = Docs.facet_counts(ws.id, viewer: owner.id, tags: ["product", "planning"])
    assert facets.tags == %{"product" => 2, "planning" => 2, "ops" => 1}
    assert facets.owners == %{owner.id => 2}
  end

  test "facets narrow each other across categories", %{owner: owner, ws: ws} do
    other = Fixtures.user_fixture()
    {:ok, _} = Workspaces.ensure_member(ws.id, other.id)
    {:ok, _} = Aveline.Tags.create(ws.id, "ops", "Ops docs.", owner.id)

    Fixtures.doc_fixture(ws, owner, slug: "mine-prod", tags: ["product"])
    Fixtures.doc_fixture(ws, other, slug: "theirs-prod", tags: ["product"])
    Fixtures.doc_fixture(ws, other, slug: "theirs-ops", tags: ["ops"])

    # Author filter scopes the tag counts.
    facets = Docs.facet_counts(ws.id, viewer: owner.id, owner_ids: [other.id])
    assert facets.tags == %{"product" => 1, "ops" => 1}
    assert facets.owners == %{other.id => 2}

    # Tag filter scopes the author counts.
    facets = Docs.facet_counts(ws.id, viewer: owner.id, tags: ["ops"])
    assert facets.owners == %{other.id => 1}

    # Both at once, and every doc-list opt combines the same way.
    facets =
      Docs.facet_counts(ws.id,
        viewer: owner.id,
        tags: ["product"],
        owner_ids: [other.id],
        updated: "7d"
      )

    assert facets.tags == %{"product" => 1}
    assert facets.owners == %{other.id => 1}
  end
end
