defmodule Aveline.Fixtures do
  @moduledoc """
  Test fixtures.
  """

  alias Aveline.Accounts
  alias Aveline.Docs
  alias Aveline.Tokens
  alias Aveline.Workspaces

  def unique_int, do: System.unique_integer([:positive])

  def user_fixture(attrs \\ %{}) do
    i = unique_int()

    {:ok, u} =
      Accounts.create_user(
        Map.merge(
          %{
            "username" => "user-#{i}",
            "email" => "user-#{i}@example.com",
            "display_name" => "User #{i}"
          },
          stringify(attrs)
        )
      )

    u
  end

  def workspace_fixture(creator, attrs \\ %{}) do
    i = unique_int()

    {:ok, w} =
      Workspaces.create_workspace(
        Map.merge(
          %{
            "slug" => "ws-#{i}",
            "name" => "Workspace #{i}",
            "created_by_id" => creator.id
          },
          stringify(attrs)
        )
      )

    {:ok, _} = Workspaces.ensure_member(w.id, creator.id)
    w
  end

  def doc_fixture(workspace, user, attrs \\ %{}) do
    i = unique_int()
    attrs = Enum.into(attrs, %{})

    {:ok, item} =
      Docs.create_doc(
        %{
          workspace_id: workspace.id,
          owner_id: user.id,
          actor_user_id: user.id,
          actor_type: Map.get(attrs, :actor_type, "agent"),
          title: Map.get(attrs, :title, "Item #{i}"),
          slug: Map.get(attrs, :slug),
          summary: Map.get(attrs, :summary),
          tags: Map.get(attrs, :tags, []),
          blocks: Map.get(attrs, :blocks, [
            %{"type" => "paragraph", "content" => [%{"text" => "Body #{i}"}]}
          ]),
          intent: Map.get(attrs, :intent, "seed item-fixture")
        }
      )

    item
  end

  def token_fixture(user, name \\ "test") do
    {:ok, token, plaintext} = Tokens.mint(user.id, name)
    {token, plaintext}
  end

  @doc "Create a catalog query. Pass `source:` for a raw query; omit for derived."
  def query_fixture(workspace, user, name, sql, opts \\ []) do
    attrs =
      %{name: name, sql: sql}
      |> then(fn a -> if opts[:source], do: Map.put(a, :source, opts[:source]), else: a end)

    {:ok, q} = Aveline.DataSources.Queries.create(workspace.id, attrs, user.id)
    q
  end

  @doc "A chart block referencing a named query (the current chart shape)."
  def chart_block(query_ref, viz \\ %{"type" => "table"}),
    do: %{"type" => "chart", "query_ref" => query_ref, "viz" => viz}

  defp stringify(attrs) when is_map(attrs) do
    Enum.into(attrs, %{}, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
