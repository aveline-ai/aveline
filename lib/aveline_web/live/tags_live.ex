defmodule AvelineWeb.TagsLive do
  @moduledoc """
  Tag management — the only place to create, rename, delete a workspace
  tag, or edit its description. Every tag carries a required description
  so an LLM (or a human) browsing the index understands what the tag
  covers.

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
           # row-edit state — one slug is "in edit mode" at a time.
           editing: nil,
           # creating? toggles the new-tag form on/off (collapsed by default).
           creating?: false,
           # delete-confirm modal state.
           # %{slug, count, blocking_count} when open, nil when closed.
           deleting: nil,
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
         |> assign(new_slug: "", new_description: "", form_error: nil, creating?: false)
         |> load_tags()}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, form_error: format_error(cs))}
    end
  end

  def handle_event("start_create", _, socket) do
    {:noreply, assign(socket, creating?: true, editing: nil, form_error: nil)}
  end

  def handle_event("cancel_create", _, socket) do
    {:noreply, assign(socket, creating?: false, new_slug: "", new_description: "", form_error: nil)}
  end

  # ===== Row edits =====

  def handle_event("edit", %{"slug" => slug}, socket),
    do: {:noreply, assign(socket, editing: slug, creating?: false)}

  def handle_event("cancel", _, socket),
    do: {:noreply, assign(socket, editing: nil)}

  # Single save handler — handles slug rename and/or description edit in
  # one go. Rename cascades through every doc carrying the old slug.
  def handle_event("save", %{"slug" => slug, "new_slug" => new_slug, "description" => desc}, socket) do
    %{workspace: ws, current_user: user} = socket.assigns
    new_slug = new_slug |> to_string() |> String.trim() |> String.downcase()
    desc = to_string(desc) |> String.trim()

    with %Tag{} = tag <- Tags.get(ws.id, slug),
         {:ok, _} <- Tags.edit(tag, %{slug: new_slug, description: desc}, user.id) do
      {:noreply, socket |> assign(editing: nil) |> load_tags()}
    else
      {:error, :destination_exists} ->
        {:noreply,
         put_flash(socket, :error, "“#{new_slug}” already exists. Delete one of the two first.")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, put_flash(socket, :error, format_error(cs))}

      _ ->
        {:noreply, put_flash(socket, :error, "Couldn't save changes.")}
    end
  end

  def handle_event("start_delete", %{"slug" => slug}, socket) do
    %{workspace: ws} = socket.assigns
    row = Enum.find(socket.assigns.tags, fn r -> r.tag.slug == slug end)
    count = (row && row.count) || 0
    blocking_count = Tags.docs_with_only_this_tag_count(ws.id, slug)

    {:noreply,
     assign(socket,
       deleting: %{slug: slug, count: count, blocking_count: blocking_count}
     )}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, deleting: nil)}
  end

  def handle_event("confirm_delete", %{"slug" => slug}, socket) do
    %{workspace: ws, current_user: user} = socket.assigns

    with %Tag{} = tag <- Tags.get(ws.id, slug),
         {:ok, _} <- Tags.delete(tag, user.id) do
      {:noreply, socket |> assign(deleting: nil) |> load_tags()}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Couldn't delete.")}
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
      <div class="tags-header">
        <div>
          <h1 class="page-title">Tags</h1>
          <p class="page-subtitle">
            Workspace taxonomy. Every tag carries a short description so an LLM
            (or a teammate) browsing the index understands what it covers.
          </p>
        </div>
        <%= if not @creating? do %>
          <button type="button" phx-click="start_create" class="tags-new-btn">
            + New tag
          </button>
        <% end %>
      </div>

      <%= if @creating? do %>
        <form phx-change="new_change" phx-submit="create" class="tag-create-card">
          <div class="tag-create-row">
            <label class="tag-field-label" for="new-tag-slug">Slug</label>
            <input
              id="new-tag-slug"
              type="text"
              name="slug"
              value={@new_slug}
              placeholder="lowercase-with-dashes"
              autocomplete="off"
              autofocus
              class="tag-field-input tag-field-mono"
            />
          </div>
          <div class="tag-create-row">
            <label class="tag-field-label" for="new-tag-desc">Description</label>
            <input
              id="new-tag-desc"
              type="text"
              name="description"
              value={@new_description}
              placeholder={"What's this tag for? (#{@min_description}–#{@max_description} chars)"}
              autocomplete="off"
              class="tag-field-input"
            />
          </div>
          <%= if @form_error do %>
            <div class="tag-create-error">{@form_error}</div>
          <% end %>
          <div class="tag-create-actions">
            <button type="button" phx-click="cancel_create" class="tag-btn-ghost">Cancel</button>
            <button
              type="submit"
              class="tag-btn-primary"
              disabled={@new_slug == "" or @new_description == ""}
            >
              Create tag
            </button>
          </div>
        </form>
      <% end %>

      <%= if @tags == [] do %>
        <div class="empty">No tags yet — click <strong>+ New tag</strong> above to add your first one.</div>
      <% else %>
        <ol class="tag-list">
          <li :for={row <- @tags} class="tag-row">
            <%= cond do %>
              <% @editing == row.tag.slug -> %>
                <form phx-submit="save" phx-value-slug={row.tag.slug} class="tag-edit-form">
                  <div class="tag-create-row">
                    <label class="tag-field-label">Slug</label>
                    <input
                      type="text"
                      name="new_slug"
                      value={row.tag.slug}
                      autocomplete="off"
                      autofocus
                      class="tag-field-input tag-field-mono"
                    />
                  </div>
                  <div class="tag-create-row">
                    <label class="tag-field-label">Description</label>
                    <input
                      type="text"
                      name="description"
                      value={row.tag.description}
                      autocomplete="off"
                      maxlength={@max_description}
                      class="tag-field-input"
                      placeholder="What's this tag for?"
                    />
                  </div>
                  <div class="tag-create-actions">
                    <button type="button" phx-click="cancel" class="tag-btn-ghost">Cancel</button>
                    <button type="submit" class="tag-btn-primary">Save</button>
                  </div>
                </form>

              <% true -> %>
                <div class="tag-row-body">
                  <div class="tag-row-head">
                    <.link
                      navigate={~p"/w/#{@workspace.slug}/docs?#{[{"tag", [row.tag.slug]}]}"}
                      class="chip chip-tag tag-row-chip"
                      style={
                        if c = row.tag.color do
                          "--tag: #{c}; --tag-dim: #{c}14; --tag-border: #{c}40"
                        end
                      }
                    >
                      {row.tag.slug}
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
                  <button phx-click="edit" phx-value-slug={row.tag.slug} class="tag-row-action">
                    Edit
                  </button>
                  <button
                    phx-click="start_delete"
                    phx-value-slug={row.tag.slug}
                    class="tag-row-action tag-row-action-danger"
                  >
                    Delete
                  </button>
                </span>
            <% end %>
          </li>
        </ol>
      <% end %>

      <%= if @deleting do %>
        <div class="modal-backdrop">
          <div class="modal-card" phx-click-away="cancel_delete">
            <h2 class="modal-title">Delete tag “{@deleting.slug}”?</h2>
            <p class="modal-body">
              <strong>“{@deleting.slug}”</strong>
              will disappear from
              <strong>{@deleting.count}</strong>
              {plural("doc", @deleting.count)}
              and from every filter and board. Docs keep the tag under the
              hood — restoring it brings everything back
              (<code>aveline restore-tag {@deleting.slug}</code>).
            </p>
            <div class="modal-actions">
              <button type="button" phx-click="cancel_delete" class="tag-btn-ghost">
                Cancel
              </button>
              <button
                type="button"
                phx-click="confirm_delete"
                phx-value-slug={@deleting.slug}
                class="modal-btn-danger"
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp plural(noun, 1), do: noun
  defp plural(noun, _), do: noun <> "s"
end
