defmodule Aveline.SidebarFavorites do
  @moduledoc """
  Per-user "stars" on tags in the sidebar. Stars bubble that tag to the
  top of the user's own sidebar. Private to the user — they don't affect
  anyone else's view.

  Different from doc pinning (`docs.pinned`), which is a global flag
  everyone sees.
  """

  import Ecto.Query

  alias Aveline.Repo
  alias Aveline.SidebarFavorites.Favorite

  @doc """
  All starred tags for a user in a workspace, as a `MapSet`. Cheap to
  test membership with `MapSet.member?/2`.
  """
  def list_for_user(workspace_id, user_id)
      when is_binary(workspace_id) and is_binary(user_id) do
    from(f in Favorite,
      where: f.workspace_id == ^workspace_id and f.user_id == ^user_id,
      select: f.tag
    )
    |> Repo.all()
    |> MapSet.new()
  end

  def list_for_user(_, _), do: MapSet.new()

  @doc """
  Toggle a tag favorite. Returns `{:ok, :starred}` or `{:ok, :unstarred}`.
  """
  def toggle(workspace_id, user_id, tag)
      when is_binary(workspace_id) and is_binary(user_id) and is_binary(tag) do
    case Repo.get_by(Favorite,
           workspace_id: workspace_id,
           user_id: user_id,
           tag: tag
         ) do
      nil ->
        %Favorite{}
        |> Ecto.Changeset.change(%{
          workspace_id: workspace_id,
          user_id: user_id,
          tag: tag,
          inserted_at: DateTime.utc_now()
        })
        |> Repo.insert!()

        {:ok, :starred}

      %Favorite{} = existing ->
        Repo.delete!(existing)
        {:ok, :unstarred}
    end
  end

  def toggle(_, _, _), do: {:error, :invalid}

  @doc """
  Reorder `tags` so favorites bubble to the top while preserving the
  input order otherwise.
  """
  def sort_by_favorites(tags, %MapSet{} = favorites) do
    {starred, rest} = Enum.split_with(tags, &MapSet.member?(favorites, &1))
    starred ++ rest
  end

  @doc """
  Drop-in `handle_event` body. LV needs:

      def handle_event("toggle_sidebar_favorite", params, socket),
        do: {:noreply, Aveline.SidebarFavorites.handle_toggle(socket, params)}
  """
  def handle_toggle(socket, %{"tag" => tag}) do
    %{workspace: ws, current_user: user} = socket.assigns

    if user do
      {:ok, _} = toggle(ws.id, user.id, tag)
      Phoenix.Component.assign(socket, :favorites, list_for_user(ws.id, user.id))
    else
      socket
    end
  end

  def handle_toggle(socket, _), do: socket
end
