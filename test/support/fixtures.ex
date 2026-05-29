defmodule Aveline.Fixtures do
  @moduledoc """
  Test fixtures.
  """

  alias Aveline.Accounts
  alias Aveline.Items
  alias Aveline.Tokens
  alias Aveline.Views
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

  def item_fixture(workspace, user, attrs \\ %{}) do
    i = unique_int()

    {:ok, item} =
      Items.create_item(
        Map.merge(
          %{
            "workspace_id" => workspace.id,
            "owner_id" => user.id,
            "created_by_id" => user.id,
            "created_via" => "seed",
            "title" => "Item #{i}",
            "body" => "Body #{i}"
          },
          stringify(attrs)
        )
      )

    item
  end

  def view_fixture(workspace, user, attrs \\ %{}) do
    i = unique_int()

    {:ok, view} =
      Views.create_view(
        Map.merge(
          %{
            "workspace_id" => workspace.id,
            "created_by_id" => user.id,
            "slug" => "view-#{i}",
            "name" => "View #{i}",
            "tag_filter" => []
          },
          stringify(attrs)
        )
      )

    view
  end

  def token_fixture(user, name \\ "test") do
    {:ok, token, plaintext} = Tokens.mint(user.id, name)
    {token, plaintext}
  end

  defp stringify(attrs) when is_map(attrs) do
    Enum.into(attrs, %{}, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
