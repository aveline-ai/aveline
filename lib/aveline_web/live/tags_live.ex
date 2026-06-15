defmodule AvelineWeb.TagsLive do
  @moduledoc """
  Tag management — the only place to create, rename, merge, delete a
  workspace tag, or edit its description. Every tag carries a required
  description so an LLM (or a human) browsing the index understands
  what the tag covers.

  Tag *filtering* still happens on the All Docs chip row; this page is
  for housekeeping the taxonomy itself.
  """
  use AvelineWeb, :live_view

  alias Aveline.Tags
  alias Aveline.Tags.Tag
  alias Aveline.Workspaces
  alias AvelineWeb.LiveSession

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    user = LiveSession.current_user(session)

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, ws} ->
        {:ok,
         socket
         |> assign(
           page_title: "Aveline · Tags · #{ws.name}",
           current_user: user,
           workspace: ws,
           sidebar_workspaces: Workspaces.list_for_user(user.id),
           topbar_title: "Tags",
           nav_active: :tags,
           min_description: Tag.min_description(),
           max_description: Tag.max_description(),
           # row-edit state
           editing_slug_of: nil,
           editing_desc_of: nil,
           merging: nil,
           # new-tag form state
           new_slug: "",
           new_description: "",
           form_error: nil
         )
         |> load_tags()}

      :not_found ->
        {:ok, socket |> put_flash(:error, "Workspace not found.") |> push_navigate(to: ~p"/")}

      :forbidden ->
        {:ok, socket |> put_flash(:error, "Forbidden.") |> push_navigate(to: ~p"/")}
    end
  end

  defp load_tags(socket) do
    assign(socket, tags: Tags.list_with_stats(socket.assigns.workspace.id))
  end

  # ===== Create =====

  @impl true
  def handle_event("new_change", params, socket) do
    {:noreply,
     assign(socket,
       new_slug: to_string(params["slug"] || ""),
       new_description: to_string(params["description"] || ""),
       form_error: nil
     )}
  end

  def handle_event("create", params, socket) do
    %{workspace: ws, current_user: user} = socket.assigns

    case Tags.create(
           ws.id,
           params["slug"] |> to_string() |> String.trim(),
           params["description"] |> to_string() |> String.trim(),
           user.id
         ) do
      {:ok, _tag} ->
        {:noreply,
         socket
         |> assign(new_slug: "", new_description: "", form_error: nil)
         |> load_tags()}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, form_error: format_error(cs))}
    end
  end

  # ===== Row edits =====

  def handle_event("edit_slug", %{"slug" => slug}, socket),
    do: {:noreply, assign(socket, editing_slug_of: slug, editing_desc_of: nil, merging: nil)}

  def handle_event("edit_desc", %{"slug" => slug}, socket),
    do: {:noreply, assign(socket, editing_desc_of: slug, editing_slug_of: nil, merging: nil)}

  def handle_event("cancel", _, socket),
    do: {:noreply, assign(socket, editing_slug_of: nil, editing_desc_of: nil, merging: nil)}

  def handle_event("rename", %{"slug" => slug, "new_slug" => new_slug}, socket) do
    %{workspace: ws, current_user: user} = socket.assigns

    with %Tag{} = tag <- Tags.get(ws.id, slug),
         {:ok, _} <- Tags.rename(tag, new_slug, user.id) do
      {:noreply, socket |> assign(editing_slug_of: nil) |> load_tags()}
    else
      {:error, :destination_exists} ->
        {:noreply,
         socket
         |> put_flash(:error, "“#{new_slug}” already exists. Use Merge instead.")
         |> assign(editing_slug_of: nil)}

      _ ->
        {:noreply, put_flash(socket, :error, "Couldn't rename — slug must be lowercase letters / digits / hyphens.")}
    end
  end

  def handle_event("update_desc", %{"slug" => slug, "description" => desc}, socket) do
    %{workspace: ws, current_user: user} = socket.assigns

    with %Tag{} = tag <- Tags.get(ws.id, slug),
         {:ok, _} <- Tags.update_description(tag, desc, user.id) do
      {:noreply, socket |> assign(editing_desc_of: nil) |> load_tags()}
    else
      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, put_flash(socket, :error, format_error(cs))}

      _ ->
        {:noreply, put_flash(socket, :error, "Couldn't update description.")}
    end
  end

  def handle_event("start_merge", %{"slug" => slug}, socket),
    do: {:noreply, assign(socket, merging: slug, editing_slug_of: nil, editing_desc_of: nil)}

  def handle_event("merge", %{"slug" => slug, "target" => target}, socket) do
    %{workspace: ws, current_user: user} = socket.assigns

    if target in ["", slug] do
      {:noreply, socket}
    else
      with %Tag{} = src <- Tags.get(ws.id, slug),
           {:ok, _} <- Tags.merge(src, target, user.id) do
        {:noreply, socket |> assign(merging: nil) |> load_tags()}
      else
        _ -> {:noreply, put_flash(socket, :error, "Couldn't merge.")}
      end
    end
  end

  def handle_event("delete", %{"slug" => slug}, socket) do
    %{workspace: ws, current_user: user} = socket.assigns

    with %Tag{} = tag <- Tags.get(ws.id, slug),
         {:ok, _} <- Tags.delete(tag, user.id) do
      {:noreply, load_tags(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Couldn't delete.")}
    end
  end

  defp format_error(%Ecto.Changeset{} = cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="content">
      <h1 class="page-title">Tags</h1>
      <p class="page-subtitle">
        Workspace taxonomy. Every tag carries a short description so an LLM
        (or a teammate) browsing the index understands what it covers.
        Filtering by tag happens on
        <.link navigate={~p"/w/#{@workspace.slug}"} class="auth-link">Docs</.link>.
      </p>

      <form phx-change="new_change" phx-submit="create" class="tag-new-form">
        <div class="tag-new-fields">
          <input
            type="text"
            name="slug"
            value={@new_slug}
            placeholder="new-tag-slug"
            autocomplete="off"
            class="tag-row-input tag-new-slug"
          />
          <input
            type="text"
            name="description"
            value={@new_description}
            placeholder={"What's this tag for? (#{@min_description}–#{@max_description} chars)"}
            autocomplete="off"
            class="tag-row-input"
          />
          <button type="submit" class="tag-row-primary" disabled={@new_slug == "" or @new_description == ""}>
            Create
          </button>
        </div>
        <%= if @form_error do %>
          <div class="auth-error" style="margin-top:8px">{@form_error}</div>
        <% end %>
      </form>

      <%= if @tags == [] do %>
        <div class="empty">No tags yet. Create the first one above.</div>
      <% else %>
        <ol class="tag-list">
          <li :for={row <- @tags} class="tag-row">
            <%= cond do %>
              <% @editing_slug_of == row.tag.slug -> %>
                <form phx-submit="rename" phx-value-slug={row.tag.slug} class="tag-row-form">
                  <input
                    type="text"
                    name="new_slug"
                    value={row.tag.slug}
                    autocomplete="off"
                    autofocus
                    class="tag-row-input"
                  />
                  <button type="submit" class="tag-row-primary">Save</button>
                  <button type="button" phx-click="cancel" class="tag-row-secondary">Cancel</button>
                </form>

              <% @editing_desc_of == row.tag.slug -> %>
                <form phx-submit="update_desc" phx-value-slug={row.tag.slug} class="tag-row-form">
                  <span class="tag-row-name"><span class="mono">#{row.tag.slug}</span></span>
                  <input
                    type="text"
                    name="description"
                    value={row.tag.description}
                    autocomplete="off"
                    autofocus
                    maxlength={@max_description}
                    class="tag-row-input"
                  />
                  <button type="submit" class="tag-row-primary">Save</button>
                  <button type="button" phx-click="cancel" class="tag-row-secondary">Cancel</button>
                </form>

              <% @merging == row.tag.slug -> %>
                <form phx-submit="merge" phx-value-slug={row.tag.slug} class="tag-row-form">
                  <span class="tag-row-prompt">Merge <strong>#{row.tag.slug}</strong> into:</span>
                  <select name="target" class="tag-row-input">
                    <option value="">— pick a tag —</option>
                    <%= for other <- @tags, other.tag.slug != row.tag.slug do %>
                      <option value={other.tag.slug}>{other.tag.slug}</option>
                    <% end %>
                  </select>
                  <button type="submit" class="tag-row-primary">Merge</button>
                  <button type="button" phx-click="cancel" class="tag-row-secondary">Cancel</button>
                </form>

              <% true -> %>
                <div class="tag-row-body">
                  <div class="tag-row-head">
                    <.link navigate={~p"/w/#{@workspace.slug}?#{[{"tag", [row.tag.slug]}]}"} class="tag-row-link">
                      #{row.tag.slug}
                    </.link>
                    <span class="tag-row-meta">
                      <span>{row.count} {plural("doc", row.count)}</span>
                      <%= if row.last_used_at do %>
                        <span class="card-meta-dot">·</span>
                        <span title={absolute_time(row.last_used_at)}>last used {relative_time(row.last_used_at)}</span>
                      <% end %>
                    </span>
                  </div>
                  <p class="tag-row-desc">{row.tag.description}</p>
                </div>
                <span class="tag-row-actions">
                  <button phx-click="edit_desc" phx-value-slug={row.tag.slug} class="tag-row-action">
                    Edit description
                  </button>
                  <button phx-click="edit_slug" phx-value-slug={row.tag.slug} class="tag-row-action">
                    Rename
                  </button>
                  <button phx-click="start_merge" phx-value-slug={row.tag.slug} class="tag-row-action">
                    Merge
                  </button>
                  <button
                    phx-click="delete"
                    phx-value-slug={row.tag.slug}
                    data-confirm={"Delete tag “#{row.tag.slug}” and remove it from all #{row.count} #{plural("doc", row.count)}?"}
                    class="tag-row-action tag-row-action-danger"
                  >
                    Delete
                  </button>
                </span>
            <% end %>
          </li>
        </ol>
      <% end %>
    </div>
    """
  end

  defp plural(noun, 1), do: noun
  defp plural(noun, _), do: noun <> "s"
end
