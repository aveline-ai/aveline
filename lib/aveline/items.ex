defmodule Aveline.Items do
  @moduledoc """
  Items context — CRUD, list with filters, soft delete/restore.
  """

  import Ecto.Query

  alias Aveline.Items.Item
  alias Aveline.Repo
  alias Aveline.Views

  @doc """
  Base query excludes soft-deleted items.
  """
  def base_query do
    from i in Item, where: is_nil(i.deleted_at)
  end

  @doc """
  List items in a workspace with optional filters.

  Filters:
    * `pinned: true` — only pinned items
    * `tags: ["a", "b"]` — items whose tags ⊇ all of these
    * `view: %View{}` — apply the view's tag_filter
  """
  def list_items(workspace_id, opts \\ []) do
    pinned = Keyword.get(opts, :pinned, nil)
    tags = Keyword.get(opts, :tags, []) || []
    view = Keyword.get(opts, :view, nil)

    extra_tags =
      case view do
        %Views.View{tag_filter: tf} when is_list(tf) -> tf
        _ -> []
      end

    all_tags = Enum.uniq(tags ++ extra_tags)

    query =
      from i in base_query(),
        where: i.workspace_id == ^workspace_id,
        order_by: [desc: i.pinned, desc: i.updated_at],
        preload: [:owner, :created_by]

    query
    |> maybe_filter_pinned(pinned)
    |> maybe_filter_tags(all_tags)
    |> Repo.all()
  end

  defp maybe_filter_pinned(query, true), do: from(i in query, where: i.pinned == true)
  defp maybe_filter_pinned(query, false), do: from(i in query, where: i.pinned == false)
  defp maybe_filter_pinned(query, _), do: query

  defp maybe_filter_tags(query, []), do: query

  defp maybe_filter_tags(query, tags) when is_list(tags) do
    from(i in query, where: fragment("? @> ?", i.tags, ^tags))
  end

  @doc """
  Direct slug lookup — does NOT exclude soft-deleted (caller decides).
  Returns the most-recently-inserted match (soft-deleted items can collide
  with new ones if same slug was re-used after delete).
  """
  def get_by_slug(workspace_id, slug) when is_binary(slug) do
    from(i in Item,
      where: i.workspace_id == ^workspace_id and i.slug == ^slug,
      order_by: [desc: i.inserted_at],
      limit: 1,
      preload: [:owner, :created_by]
    )
    |> Repo.one()
  end

  def get_by_slug(_, _), do: nil

  @doc """
  Lookup excluding soft-deleted.
  """
  def get_active_by_slug(workspace_id, slug) when is_binary(slug) do
    from(i in base_query(),
      where: i.workspace_id == ^workspace_id and i.slug == ^slug,
      limit: 1,
      preload: [:owner, :created_by]
    )
    |> Repo.one()
  end

  def get_active_by_slug(_, _), do: nil

  def get_item(id), do: Repo.get(Item, id) |> Repo.preload([:owner, :created_by])

  def create_item(attrs) do
    %Item{}
    |> Item.create_changeset(attrs)
    |> Repo.insert()
    |> preload_if_ok()
  end

  def update_item(%Item{} = item, attrs) do
    item
    |> Item.update_changeset(attrs)
    |> Repo.update()
    |> preload_if_ok()
  end

  def soft_delete_item(%Item{} = item, deleted_by_id) do
    item
    |> Ecto.Changeset.change(%{
      deleted_at: DateTime.utc_now(),
      deleted_by_id: deleted_by_id
    })
    |> Repo.update()
    |> preload_if_ok()
  end

  def restore_item(%Item{} = item) do
    item
    |> Ecto.Changeset.change(%{deleted_at: nil, deleted_by_id: nil})
    |> Repo.update()
    |> preload_if_ok()
  end

  defp preload_if_ok({:ok, item}), do: {:ok, Repo.preload(item, [:owner, :created_by])}
  defp preload_if_ok(other), do: other

  @doc """
  Items in the same workspace that share at least one tag with the given
  item. Ordered by tag overlap (most shared first), then most-recently
  updated. Excludes the source item itself and any soft-deleted rows.
  """
  def related_items(%Item{id: id, workspace_id: ws_id, tags: tags}, limit \\ 5)
      when is_list(tags) do
    if tags == [] do
      []
    else
      tag_array = tags

      from(i in base_query(),
        where: i.workspace_id == ^ws_id and i.id != ^id,
        where: fragment("? && ?::varchar[]", i.tags, ^tag_array),
        order_by: [
          desc:
            fragment(
              "cardinality(ARRAY(SELECT unnest(?) INTERSECT SELECT unnest(?::varchar[])))",
              i.tags,
              ^tag_array
            ),
          desc: i.pinned,
          desc: i.updated_at
        ],
        limit: ^limit,
        preload: [:owner]
      )
      |> Repo.all()
    end
  end
end
