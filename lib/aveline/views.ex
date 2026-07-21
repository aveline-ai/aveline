defmodule Aveline.Views do
  @moduledoc """
  Views — named, versioned snapshots of the Docs page's display knobs
  (see `Aveline.Views.View`). Ordinary config-tier lifecycle: create,
  versioned edit with intent trail, soft delete, restore. Pin/unpin is
  placement, updated in place on the current row (like doc pin slots),
  never a version.
  """

  import Ecto.Query, warn: false

  alias Aveline.Repo
  alias Aveline.Tags
  alias Aveline.Views.Bucket
  alias Aveline.Views.BucketMember
  alias Aveline.Views.View

  defp base_query do
    from v in View, where: not v.superseded and is_nil(v.deleted_at)
  end

  # Pinned first, then name — the one ordering every surface uses
  # (title switcher, list-views, sidebar).
  def list_for_workspace(workspace_id, opts \\ []) do
    from(v in base_query(),
      where: v.workspace_id == ^workspace_id,
      order_by: [desc: v.pinned, asc: v.name],
      preload: [:bucket]
    )
    |> where_usable(Keyword.get(opts, :viewer))
    |> Repo.all()
  end

  # ===== Buckets =====
  #
  # The space a view lives in and the unit views are shared at (see the
  # view-buckets TIP). Audience by kind: team = every workspace member,
  # personal = the owner, project = owner + live binary members.

  @reserved_bucket_prefix "personal-"

  def ensure_team_bucket(workspace_id) do
    get_bucket_by_kind(workspace_id, "team") ||
      Repo.insert!(
        Bucket.changeset(%Bucket{}, %{workspace_id: workspace_id, name: "team", kind: "team"})
      )
  end

  def ensure_personal_bucket(workspace_id, user_id) do
    existing =
      Repo.one(
        from b in live_buckets(),
          where:
            b.workspace_id == ^workspace_id and b.kind == "personal" and b.owner_id == ^user_id
      )

    existing ||
      Repo.insert!(
        Bucket.changeset(%Bucket{}, %{
          workspace_id: workspace_id,
          name: @reserved_bucket_prefix <> personal_slug(user_id),
          kind: "personal",
          owner_id: user_id
        })
      )
  end

  defp personal_slug(user_id) do
    case Repo.get(Aveline.Accounts.User, user_id) do
      %{username: u} when is_binary(u) -> u
      _ -> String.slice(user_id, 0, 8)
    end
  end

  defp live_buckets, do: from(b in Bucket, where: is_nil(b.deleted_at))

  defp get_bucket_by_kind(workspace_id, kind) do
    Repo.one(from b in live_buckets(), where: b.workspace_id == ^workspace_id and b.kind == ^kind)
  end

  def get_bucket(workspace_id, name) when is_binary(name) do
    Repo.one(from b in live_buckets(), where: b.workspace_id == ^workspace_id and b.name == ^name)
  end

  @doc "Buckets `user_id` can use: team, their personal one (if it exists), projects they own or belong to."
  def list_buckets_for(workspace_id, user_id) do
    member_ids =
      from m in BucketMember, where: m.user_id == ^user_id and is_nil(m.deleted_at), select: m.bucket_id

    from(b in live_buckets(),
      where:
        b.workspace_id == ^workspace_id and
          (b.kind == "team" or b.owner_id == ^user_id or b.id in subquery(member_ids)),
      order_by: [asc: b.kind, asc: b.name]
    )
    |> Repo.all()
  end

  @doc "Create a project bucket. Reserved names (team, personal-*) rejected."
  def create_bucket(workspace_id, name, owner_id) do
    name = name |> to_string() |> String.trim() |> String.downcase()

    if name == "team" or String.starts_with?(name, @reserved_bucket_prefix) do
      {:error, "that bucket name is reserved"}
    else
      %Bucket{}
      |> Bucket.changeset(%{
        workspace_id: workspace_id,
        name: name,
        kind: "project",
        owner_id: owner_id
      })
      |> Repo.insert()
    end
  end

  @doc "Delete a project bucket. Owner only; must hold no live views."
  def delete_bucket(%Bucket{} = bucket, actor_user_id) do
    cond do
      bucket.kind != "project" ->
        {:error, "only project buckets can be deleted"}

      bucket.owner_id != actor_user_id ->
        {:error, "only the bucket's owner can delete it"}

      Repo.exists?(from v in base_query(), where: v.bucket_id == ^bucket.id) ->
        {:error, "move or delete this bucket's views first"}

      true ->
        bucket |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now()}) |> Repo.update()
    end
  end

  @doc "Live members of a project bucket (the owner is implicit and not listed)."
  def list_bucket_members(%Bucket{} = bucket) do
    from(m in BucketMember,
      where: m.bucket_id == ^bucket.id and is_nil(m.deleted_at),
      order_by: [asc: m.inserted_at],
      preload: [:user, :added_by]
    )
    |> Repo.all()
  end

  @doc "Add a workspace member to a project bucket. Owner only; binary membership."
  def add_bucket_member(%Bucket{} = bucket, user_id, actor_user_id) do
    cond do
      bucket.kind != "project" ->
        {:error, "only project buckets take members; team is everyone and personal is just you"}

      bucket.owner_id != actor_user_id ->
        {:error, "only the bucket's owner can add members"}

      user_id == bucket.owner_id ->
        {:error, "the owner is already in the bucket"}

      not Aveline.Workspaces.member?(bucket.workspace_id, user_id) ->
        {:error, "that user is not a member of this workspace"}

      Repo.exists?(
        from m in BucketMember,
          where: m.bucket_id == ^bucket.id and m.user_id == ^user_id and is_nil(m.deleted_at)
      ) ->
        {:error, "that user is already in the bucket"}

      true ->
        %BucketMember{}
        |> BucketMember.changeset(%{
          bucket_id: bucket.id,
          user_id: user_id,
          added_by_id: actor_user_id
        })
        |> Repo.insert()
    end
  end

  @doc "Remove a member from a project bucket. Owner only; soft delete."
  def remove_bucket_member(%Bucket{} = bucket, user_id, actor_user_id) do
    with :owner <- if(bucket.owner_id == actor_user_id, do: :owner, else: :not_owner),
         %BucketMember{} = m <-
           Repo.one(
             from m in BucketMember,
               where: m.bucket_id == ^bucket.id and m.user_id == ^user_id and is_nil(m.deleted_at)
           ) do
      m |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now()}) |> Repo.update()
    else
      :not_owner -> {:error, "only the bucket's owner can remove members"}
      nil -> {:error, "that user is not in the bucket"}
    end
  end

  @doc "Is `user_id` in this bucket's audience? (Workspace membership already checked.)"
  def bucket_audience?(%Bucket{kind: "team"}, _user_id), do: true
  def bucket_audience?(%Bucket{kind: "personal"} = b, user_id), do: b.owner_id == user_id

  def bucket_audience?(%Bucket{kind: "project"} = b, user_id) do
    b.owner_id == user_id or
      Repo.exists?(
        from m in BucketMember,
          where: m.bucket_id == ^b.id and m.user_id == ^user_id and is_nil(m.deleted_at)
      )
  end

  # ===== Access =====

  @doc """
  Narrows a views query to what `user_id` may use: views whose bucket
  audience includes them. `nil` fails closed (team bucket only).
  """
  def where_usable(query, nil) do
    team = from b in live_buckets(), where: b.kind == "team", select: b.id
    from v in query, where: v.bucket_id in subquery(team)
  end

  def where_usable(query, user_id) do
    member_ids =
      from m in BucketMember, where: m.user_id == ^user_id and is_nil(m.deleted_at), select: m.bucket_id

    usable =
      from b in live_buckets(),
        where: b.kind == "team" or b.owner_id == ^user_id or b.id in subquery(member_ids),
        select: b.id

    from v in query, where: v.bucket_id in subquery(usable)
  end

  @doc """
  May this workspace member use (and, binary membership, edit) the
  view? Resolves the bucket if not preloaded.
  """
  def member_can_use?(%View{} = view, user_id) do
    case bucket_of(view) do
      nil -> false
      bucket -> bucket_audience?(bucket, user_id)
    end
  end

  defp bucket_of(%View{bucket: %Bucket{} = b}), do: b
  defp bucket_of(%View{bucket_id: nil}), do: nil
  defp bucket_of(%View{bucket_id: id}), do: Repo.get(Bucket, id)

  @doc """
  Move a view to another bucket, in place (like pins — placement, not
  meaning). The view's owner only, and only into a bucket they can use.
  """
  def move_view(%View{} = view, %Bucket{} = bucket, actor_user_id) do
    cond do
      view.owner_id != actor_user_id ->
        {:error, "only the view's owner can move it"}

      bucket.workspace_id != view.workspace_id ->
        {:error, "that bucket belongs to another workspace"}

      not bucket_audience?(bucket, actor_user_id) ->
        {:error, "you aren't in that bucket"}

      true ->
        view |> Ecto.Changeset.change(%{bucket_id: bucket.id}) |> Repo.update()
    end
  end

  @doc """
  The sidebar's sections, one query. Pin = in the sidebar, universally;
  the section is the view's bucket: Team, Yours (your personal bucket),
  then one section per project bucket you're in, pinned views under
  each.
  """
  def sidebar_sections(workspace_id, user_id) do
    pinned =
      workspace_id
      |> list_for_workspace(viewer: user_id)
      |> Enum.filter(& &1.pinned)

    {team, rest} = Enum.split_with(pinned, &(bucket_of(&1) && bucket_of(&1).kind == "team"))
    {yours, project} = Enum.split_with(rest, &(bucket_of(&1) && bucket_of(&1).kind == "personal"))

    buckets =
      project
      |> Enum.group_by(&bucket_of/1)
      |> Enum.reject(fn {b, _} -> is_nil(b) end)
      |> Enum.map(fn {b, views} -> %{bucket: b, views: Enum.sort_by(views, & &1.name)} end)
      |> Enum.sort_by(& &1.bucket.name)

    %{team: team, yours: yours, buckets: buckets}
  end

  def list_pinned(workspace_id) do
    from(v in base_query(), where: v.workspace_id == ^workspace_id and v.pinned, order_by: v.name)
    |> Repo.all()
  end

  def get_current_by_name(workspace_id, name) when is_binary(name) do
    from(v in base_query(),
      where: v.workspace_id == ^workspace_id and v.name == ^name,
      preload: [:bucket]
    )
    |> Repo.one()
  end

  def create(workspace_id, name, description, config, created_by_id, opts \\ []) do
    bucket =
      case Keyword.get(opts, :bucket) do
        %Bucket{} = b -> b
        nil -> ensure_team_bucket(workspace_id)
      end

    with :ok <- validate_config_against_workspace(workspace_id, config) do
      %View{}
      |> View.insert_changeset(%{
        workspace_id: workspace_id,
        base_view_id: Ecto.UUID.generate(),
        name: name,
        description: description,
        config: config || %{},
        created_by_id: created_by_id,
        bucket_id: bucket.id,
        # The creator owns the view; ownership never moves with edits.
        owner_id: created_by_id
      })
      |> Repo.insert()
    end
  end

  @doc """
  Versioned edit: `changes` may carry `:name`, `:description`,
  `:config`. Mints v+1 on the same base id; supersede-then-insert.
  Pinned carries over (placement survives edits).
  """
  def edit(%View{} = current, changes, user_id) when is_map(changes) do
    # Config edits MERGE onto the current config so a partial update
    # (e.g. just --sub-group-by) doesn't drop the other keys. Callers
    # clear a key by sending it explicitly as nil.
    config =
      case Map.get(changes, :config) do
        nil -> current.config
        incoming -> Map.merge(current.config || %{}, incoming)
      end

    with :ok <- validate_config_against_workspace(current.workspace_id, config) do
      Repo.transaction(fn ->
        {1, _} =
          from(v in View, where: v.id == ^current.id)
          |> Repo.update_all(set: [superseded: true])

        insert =
          %View{}
          |> View.insert_changeset(%{
            workspace_id: current.workspace_id,
            base_view_id: current.base_view_id,
            version_number: current.version_number + 1,
            name: Map.get(changes, :name, current.name),
            description: Map.get(changes, :description, current.description),
            config: config,
            pinned: current.pinned,
            bucket_id: current.bucket_id,
            owner_id: current.owner_id,
            created_by_id: user_id
          })
          |> Repo.insert()

        case insert do
          {:ok, view} -> view
          {:error, cs} -> Repo.rollback(cs)
        end
      end)
    end
  end

  def delete(%View{} = view, user_id) do
    view
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(), deleted_by_id: user_id)
    |> Repo.update()
  end

  def restore(workspace_id, name) do
    deleted =
      from(v in View,
        where:
          v.workspace_id == ^workspace_id and v.name == ^name and not v.superseded and
            not is_nil(v.deleted_at)
      )
      |> Repo.one()

    case deleted do
      nil -> {:error, :not_user_deleted}
      view -> view |> Ecto.Changeset.change(deleted_at: nil, deleted_by_id: nil) |> Repo.update()
    end
  end

  @doc """
  Placement, not meaning: in-place update, no version minted. Pin = in
  the sidebar; a pinned view renders only in the sidebars of its
  bucket's audience.
  """
  def set_pinned(%View{} = view, pinned?) when is_boolean(pinned?) do
    view |> Ecto.Changeset.change(pinned: pinned?) |> Repo.update()
  end

  def safe_map(%View{} = view) do
    %{
      "name" => view.name,
      "description" => view.description,
      "config" => view.config,
      "pinned" => view.pinned,
      "bucket" => (case view.bucket do
        %Bucket{} = b -> %{"name" => b.name, "kind" => b.kind}
        _ -> nil
      end),
      "version_number" => view.version_number,
      "created_at" => DateTime.to_iso8601(view.inserted_at)
    }
  end

  # Filter tags must exist; group_by must be a scope with members. A
  # view over unknown tags is a typo, not an empty view (same spirit as
  # the old board-block validation).
  defp validate_config_against_workspace(workspace_id, config) when is_map(config) do
    tags = Map.get(config, "tags", [])
    group_by = Map.get(config, "group_by")

    with :ok <- Tags.ensure_all_exist(workspace_id, Enum.filter(tags, &is_binary/1)) do
      cond do
        is_nil(group_by) ->
          :ok

        not is_binary(group_by) or not Regex.match?(~r/^[a-z0-9][a-z0-9-]*$/, group_by) ->
          {:error, :view_invalid, "group_by must be a tag scope (a plain slug like \"status\")"}

        Tags.list_scope_members(workspace_id, group_by) == [] ->
          {:error, :view_invalid, "group_by scope has no tags in this workspace: #{group_by}"}

        true ->
          :ok
      end
    end
  end

  defp validate_config_against_workspace(_ws, nil), do: :ok
  defp validate_config_against_workspace(_ws, _), do: {:error, :view_invalid, "config must be an object"}
end
