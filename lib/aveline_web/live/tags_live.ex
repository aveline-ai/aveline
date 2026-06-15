defmodule AvelineWeb.TagsLive do
  @moduledoc """
  Tag management — the only place to rename, merge, or delete a workspace
  tag. Tag *filtering* still happens on the All Docs page (chip row);
  this page is for housekeeping the taxonomy itself.
  """
  use AvelineWeb, :live_view

  alias Aveline.Docs
  alias Aveline.Workspaces
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        {:ok,
         assign(socket,
           page_title: "Aveline · Tags · #{ws.name}",
           current_user: user,
           workspace: ws,
           sidebar_workspaces: Workspaces.list_for_user(user.id),
           topbar_title: "Tags",
           nav_active: :tags,
           tags: Docs.list_tags_with_stats(ws.id),
           editing: nil,
           merging: nil,
           error: nil
         )}

      :not_found ->
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("edit", %{"tag" => tag}, socket) do
    {:noreply, assign(socket, editing: tag, merging: nil, error: nil)}
  end

  def handle_event("cancel", _, socket) do
    {:noreply, assign(socket, editing: nil, merging: nil, error: nil)}
  end

  def handle_event("rename", %{"tag" => tag, "name" => new_name}, socket) do
    %{workspace: ws, current_user: user} = socket.assigns
    new_name = new_name |> to_string() |> String.trim() |> String.downcase()

    cond do
      new_name == "" or new_name == tag ->
        {:noreply, assign(socket, editing: nil, error: nil)}

      new_name in Enum.map(socket.assigns.tags, & &1.tag) ->
        {:noreply,
         assign(socket,
           error: "“#{new_name}” already exists. Use Merge instead to combine them."
         )}

      true ->
        case Docs.rename_tag(ws.id, tag, new_name, user.id) do
          {:ok, _affected} ->
            {:noreply,
             assign(socket,
               tags: Docs.list_tags_with_stats(ws.id),
               editing: nil,
               error: nil
             )}

          {:error, _} ->
            {:noreply, assign(socket, error: "Use lowercase letters, digits, and hyphens.")}
        end
    end
  end

  def handle_event("start_merge", %{"tag" => tag}, socket) do
    {:noreply, assign(socket, merging: tag, editing: nil, error: nil)}
  end

  def handle_event("merge", %{"tag" => source, "target" => target}, socket) do
    %{workspace: ws, current_user: user} = socket.assigns

    if target == "" or target == source do
      {:noreply, socket}
    else
      {:ok, _} = Docs.merge_tags(ws.id, source, target, user.id)

      {:noreply,
       assign(socket,
         tags: Docs.list_tags_with_stats(ws.id),
         merging: nil,
         error: nil
       )}
    end
  end

  def handle_event("delete", %{"tag" => tag}, socket) do
    %{workspace: ws, current_user: user} = socket.assigns
    {:ok, _} = Docs.delete_tag(ws.id, tag, user.id)

    {:noreply, assign(socket, tags: Docs.list_tags_with_stats(ws.id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="content">
      <h1 class="page-title">Tags</h1>
      <p class="page-subtitle">
        Rename, merge, or delete tags across the whole workspace. Filtering by tag happens on
        <.link navigate={~p"/w/#{@workspace.slug}"} class="auth-link">Docs</.link>.
      </p>

      <%= if @tags == [] do %>
        <div class="empty">
          No tags yet. Tags are added on each doc — once you tag something, it shows up here.
        </div>
      <% else %>
        <ol class="tag-list">
          <li :for={row <- @tags} class="tag-row">
            <%= cond do %>
              <% @editing == row.tag -> %>
                <form phx-submit="rename" phx-value-tag={row.tag} class="tag-row-form">
                  <input
                    type="text"
                    name="name"
                    value={row.tag}
                    autocomplete="off"
                    autofocus
                    class="tag-row-input"
                  />
                  <button type="submit" class="tag-row-primary">Save</button>
                  <button type="button" phx-click="cancel" class="tag-row-secondary">Cancel</button>
                </form>

              <% @merging == row.tag -> %>
                <form phx-submit="merge" phx-value-tag={row.tag} class="tag-row-form">
                  <span class="tag-row-prompt">Merge <strong>#{row.tag}</strong> into:</span>
                  <select name="target" class="tag-row-input">
                    <option value="">— pick a tag —</option>
                    <%= for other <- @tags, other.tag != row.tag do %>
                      <option value={other.tag}>{other.tag}</option>
                    <% end %>
                  </select>
                  <button type="submit" class="tag-row-primary">Merge</button>
                  <button type="button" phx-click="cancel" class="tag-row-secondary">Cancel</button>
                </form>

              <% true -> %>
                <span class="tag-row-name">
                  <.link navigate={~p"/w/#{@workspace.slug}?#{[{"tag", [row.tag]}]}"} class="tag-row-link">
                    #{row.tag}
                  </.link>
                </span>
                <span class="tag-row-meta">
                  <span>{row.count} <span class="card-meta-key">{plural("doc", row.count)}</span></span>
                  <span class="card-meta-dot">·</span>
                  <span title={absolute_time(row.last_used_at)}>last used {relative_time(row.last_used_at)}</span>
                </span>
                <span class="tag-row-actions">
                  <button phx-click="edit" phx-value-tag={row.tag} class="tag-row-action">
                    Rename
                  </button>
                  <button phx-click="start_merge" phx-value-tag={row.tag} class="tag-row-action">
                    Merge
                  </button>
                  <button
                    phx-click="delete"
                    phx-value-tag={row.tag}
                    data-confirm={"Delete tag “#{row.tag}” from all #{row.count} #{plural("doc", row.count)}?"}
                    class="tag-row-action tag-row-action-danger"
                  >
                    Delete
                  </button>
                </span>
            <% end %>
          </li>
        </ol>

        <%= if @error do %>
          <div class="auth-error" style="margin-top:14px">{@error}</div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp plural(noun, 1), do: noun
  defp plural(noun, _), do: noun <> "s"
end
