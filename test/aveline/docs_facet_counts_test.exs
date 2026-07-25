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
end
