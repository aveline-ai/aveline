defmodule Aveline.Gleam.Caps.Views do
  @moduledoc "Real IO for src/aveline/caps/views.gleam. Keep field order in lockstep."

  import Ecto.Query
  import Aveline.Gleam.Interop

  alias Aveline.Repo
  alias Aveline.Views
  alias Aveline.Views.Bucket
  alias Aveline.Views.BucketMember
  alias Aveline.Views.View

  def build do
    {:views_caps,
     # list_views
     fn workspace_id ->
       from(v in live_views(),
         where: v.workspace_id == ^workspace_id,
         order_by: [desc: v.pinned, asc: v.name],
         preload: [:bucket]
       )
       |> Repo.all()
       |> Enum.map(&view(&1, live_bucket_opt(&1.bucket)))
     end,
     # get_current_by_name
     fn workspace_id, name ->
       Views.get_current_by_name(workspace_id, name)
       |> opt(&view(&1, opt(&1.bucket, fn b -> bucket(b) end)))
     end,
     # find_restorable
     fn workspace_id, name ->
       from(v in View,
         where:
           v.workspace_id == ^workspace_id and v.name == ^name and not v.superseded and
             not is_nil(v.deleted_at)
       )
       |> Repo.one()
       |> opt(&view(&1, :none))
     end,
     # insert_view
     fn write ->
       case %View{} |> View.insert_changeset(write_attrs(write)) |> Repo.insert() do
         {:ok, v} ->
           v = Repo.preload(v, :bucket)
           {:ok, view(v, opt(v.bucket, fn b -> bucket(b) end))}

         {:error, _cs} ->
           {:error, nil}
       end
     end,
     # replace_version
     fn view_id, write ->
       result =
         Repo.transaction(fn ->
           {1, _} =
             from(v in View, where: v.id == ^view_id)
             |> Repo.update_all(set: [superseded: true])

           case %View{} |> View.insert_changeset(write_attrs(write)) |> Repo.insert() do
             {:ok, v} -> v
             {:error, cs} -> Repo.rollback(cs)
           end
         end)

       case result do
         {:ok, v} -> {:ok, view(v, :none)}
         {:error, _} -> {:error, nil}
       end
     end,
     # restore_view
     fn view_id ->
       Repo.get!(View, view_id)
       |> Ecto.Changeset.change(deleted_at: nil, deleted_by_id: nil)
       |> Repo.update!()
       |> view(:none)
     end,
     # soft_delete_view
     fn view_id, user_id ->
       Repo.get!(View, view_id)
       |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(), deleted_by_id: user_id)
       |> Repo.update!()

       nil
     end,
     # set_view_pinned
     fn view_id, pinned? ->
       v =
         Repo.get!(View, view_id)
         |> Ecto.Changeset.change(pinned: pinned?)
         |> Repo.update!()
         |> Repo.preload(:bucket)

       view(v, opt(v.bucket, fn b -> bucket(b) end))
     end,
     # move_view
     fn view_id, bucket_id ->
       v =
         Repo.get!(View, view_id)
         |> Ecto.Changeset.change(bucket_id: bucket_id)
         |> Repo.update!()
         |> Repo.preload(:bucket, force: true)

       view(v, opt(v.bucket, fn b -> bucket(b) end))
     end,
     # list_buckets
     fn workspace_id ->
       from(b in live_buckets(),
         where: b.workspace_id == ^workspace_id,
         order_by: [asc: b.kind, asc: b.name]
       )
       |> Repo.all()
       |> Enum.map(&bucket/1)
     end,
     # get_bucket
     fn workspace_id, name -> Views.get_bucket(workspace_id, name) |> opt(&bucket/1) end,
     # ensure_team_bucket
     fn workspace_id -> workspace_id |> Views.ensure_team_bucket() |> bucket() end,
     # ensure_personal_bucket
     fn workspace_id, user_id ->
       workspace_id |> Views.ensure_personal_bucket(user_id) |> bucket()
     end,
     # insert_bucket
     fn workspace_id, name, owner_id, visibility ->
       attrs = %{
         workspace_id: workspace_id,
         name: name,
         kind: "project",
         owner_id: owner_id,
         visibility: visibility_string(visibility)
       }

       case %Bucket{} |> Bucket.changeset(attrs) |> Repo.insert() do
         {:ok, b} -> {:ok, bucket(b)}
         {:error, _cs} -> {:error, nil}
       end
     end,
     # set_bucket_visibility
     fn bucket_id, visibility ->
       Repo.get!(Bucket, bucket_id)
       |> Ecto.Changeset.change(visibility: visibility_string(visibility))
       |> Repo.update!()
       |> bucket()
     end,
     # soft_delete_bucket
     fn bucket_id ->
       Repo.get!(Bucket, bucket_id)
       |> Ecto.Changeset.change(deleted_at: DateTime.utc_now())
       |> Repo.update!()

       nil
     end,
     # bucket_has_live_views
     fn bucket_id -> Repo.exists?(from v in live_views(), where: v.bucket_id == ^bucket_id) end,
     # list_bucket_member_usernames
     fn bucket_id ->
       from(m in BucketMember,
         where: m.bucket_id == ^bucket_id and is_nil(m.deleted_at),
         order_by: [asc: m.inserted_at],
         preload: [:user]
       )
       |> Repo.all()
       |> Enum.map(fn m -> opt(m.user && m.user.username) end)
     end,
     # insert_bucket_member
     fn bucket_id, user_id, added_by_id ->
       %BucketMember{}
       |> BucketMember.changeset(%{bucket_id: bucket_id, user_id: user_id, added_by_id: added_by_id})
       |> Repo.insert!()

       nil
     end,
     # find_live_membership
     fn bucket_id, user_id ->
       from(m in BucketMember,
         where: m.bucket_id == ^bucket_id and m.user_id == ^user_id and is_nil(m.deleted_at),
         select: m.id
       )
       |> Repo.one()
       |> opt()
     end,
     # soft_delete_membership
     fn membership_id ->
       Repo.get!(BucketMember, membership_id)
       |> Ecto.Changeset.change(deleted_at: DateTime.utc_now())
       |> Repo.update!()

       nil
     end,
     # member_bucket_ids
     fn user_id ->
       from(m in BucketMember,
         where: m.user_id == ^user_id and is_nil(m.deleted_at),
         select: m.bucket_id
       )
       |> Repo.all()
     end,
     # get_username
     fn user_id -> Repo.get(Aveline.Accounts.User, user_id) |> opt(& &1.username) end,
     # find_user_id_by_username
     fn username -> Aveline.Accounts.get_user_by_username(username) |> opt(& &1.id) end,
     # is_workspace_member
     fn workspace_id, user_id -> Aveline.Workspaces.member?(workspace_id, user_id) end,
     # unknown_tags
     fn workspace_id, slugs ->
       case Aveline.Tags.ensure_all_exist(workspace_id, slugs) do
         :ok -> []
         {:error, {:unknown_tags, missing}} -> missing
       end
     end,
     # scope_has_tags
     fn workspace_id, scope -> Aveline.Tags.list_scope_members(workspace_id, scope) != [] end}
  end

  # ===== Row -> Gleam domain conversions =====

  defp live_views, do: from(v in View, where: not v.superseded and is_nil(v.deleted_at))
  defp live_buckets, do: from(b in Bucket, where: is_nil(b.deleted_at))

  defp view(v, bucket_opt) do
    {:view, v.id, v.workspace_id, v.base_view_id, v.version_number, v.name, v.description,
     config(v.config), v.pinned, v.owner_id, bucket_opt, DateTime.to_iso8601(v.inserted_at)}
  end

  # Index-style reads treat a soft-deleted bucket as absent (the old SQL
  # joined live buckets only); by-name reads keep the raw preload.
  defp live_bucket_opt(%Bucket{deleted_at: nil} = b), do: {:some, bucket(b)}
  defp live_bucket_opt(_), do: :none

  defp bucket(b) do
    {:bucket, b.id, b.workspace_id, b.name, kind(b.kind), visibility(b.visibility),
     opt(b.owner_id)}
  end

  defp kind("team"), do: :team
  defp kind("personal"), do: :personal
  defp kind("project"), do: :project

  defp visibility("workspace"), do: :workspace_visible
  defp visibility(_), do: :private

  defp visibility_string(:workspace_visible), do: "workspace"
  defp visibility_string(:private), do: "private"

  defp config(c) do
    c = c || %{}

    {:view_config, Map.get(c, "tags", []) |> List.wrap() |> Enum.filter(&is_binary/1),
     opt(Map.get(c, "group_by")), opt(Map.get(c, "sub_group_by")), opt(Map.get(c, "edited")),
     opt(Map.get(c, "sort")), opt(Map.get(c, "icon"))}
  end

  defp write_attrs(
         {:view_write, workspace_id, base_view_id, version_number, name, description, config,
          pinned, bucket_id, owner_id, created_by_id}
       ) do
    %{
      workspace_id: workspace_id,
      base_view_id: unopt(base_view_id) || Ecto.UUID.generate(),
      version_number: version_number,
      name: name,
      description: description,
      config: config_map(config),
      pinned: pinned,
      bucket_id: bucket_id,
      owner_id: owner_id,
      created_by_id: created_by_id
    }
  end

  defp config_map({:view_config, tags, group_by, sub_group_by, edited, sort, icon}) do
    %{"tags" => tags}
    |> put_some("group_by", group_by)
    |> put_some("sub_group_by", sub_group_by)
    |> put_some("edited", edited)
    |> put_some("sort", sort)
    |> put_some("icon", icon)
  end

  defp put_some(map, _key, :none), do: map
  defp put_some(map, key, {:some, v}), do: Map.put(map, key, v)
end
