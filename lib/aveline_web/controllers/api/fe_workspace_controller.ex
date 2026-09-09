defmodule AvelineWeb.Api.FeWorkspaceController do
  @moduledoc """
  Thin JSON endpoints backing the Elm workspace pages (Home, Welcome,
  Team, Settings) for LiveView features that had no /papi equivalent.
  Each action mirrors the corresponding LiveView's mount/handle_event
  logic exactly — same context functions, same shapes on screen.

  Routed only in the /papi workspace scope (see `# fe-workspace routes`
  in the router).
  """
  use AvelineWeb, :controller

  alias Aveline.Comments
  alias Aveline.Docs
  alias Aveline.DocViews
  alias Aveline.Stats
  alias Aveline.Workspaces
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.Views

  action_fallback AvelineWeb.Api.FallbackController

  @doc """
  Everything HomeLive assembles at mount, minus tags (GET /tags already
  serves the glossary). Reading the orientation card here does NOT
  record an agent doc-view — unlike GET /orientation — because a page
  render is not an agent read (agent views power setup detection).
  """
  def home(conn, _params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    Envelope.ok(conn, %{
      viewer: %{
        username: user.username,
        display_name: user.display_name
      },
      orientation: doc_card(Docs.get_orientation(ws.id)),
      pinned_docs: ws.id |> Docs.list_pinned() |> Enum.map(&doc_card/1),
      needs_you:
        ws.id
        |> Comments.list_open_threads_for_owner(user.id, 5)
        |> Enum.map(&thread_map/1),
      recently_viewed:
        ws.id
        |> DocViews.recent_for_user(user.id, 3)
        |> Enum.map(fn {d, viewed_at} ->
          %{slug: d.slug, title: d.title, viewed_at: iso(viewed_at)}
        end),
      recent_changes:
        ws.id
        |> Docs.list_current(sort: :recent, limit: 5, viewer: user.id)
        |> Enum.map(fn d ->
          %{
            slug: d.slug,
            title: d.title,
            version_number: d.version_number,
            intent: d.intent,
            updated_at: iso(d.updated_at)
          }
        end)
    })
  end

  @doc """
  Everything WelcomeLive assembles at mount, including the server-built
  setup prompt (it depends on the instance's canonical-host check).
  """
  def welcome(conn, _params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    docs = Docs.list_current(ws.id, viewer: user.id, sort: :recent)
    backdrop = Enum.reject(docs, &("template" in (&1.tags || [])))

    Envelope.ok(conn, %{
      prompt: AvelineWeb.Setup.prompt(ws),
      api_base_override: AvelineWeb.Setup.api_base_override(),
      doc_count: length(docs),
      view_count: length(Aveline.Views.list_for_workspace(ws.id, viewer: user.id)),
      member_names:
        ws.id
        |> Workspaces.list_members()
        |> Enum.map(& &1.user.username)
        |> Enum.reject(&(&1 == user.username))
        |> Enum.sort(),
      orientation: doc_card(Docs.get_orientation(ws.id)),
      backdrop_docs:
        backdrop
        |> Enum.take(10)
        |> Enum.map(fn d ->
          %{
            title: d.title,
            tags: d.tags || [],
            actor_username: d.actor_user && d.actor_user.username,
            updated_at: iso(d.updated_at)
          }
        end)
    })
  end

  @doc """
  The Team page's extras on top of GET /members: usage stats (folded in
  from the old Usage page) and the current invite link — read-only, so
  loading the page never mints an invite (POST /invite does that).
  """
  def team(conn, _params) do
    ws = conn.assigns.current_workspace

    totals = Stats.workspace_totals(ws.id)

    Envelope.ok(conn, %{
      invite: invite_map(Workspaces.get_active_invite_for_workspace(ws.id)),
      totals: %{
        active_docs: totals.active_docs,
        total_edits: totals.total_edits,
        reads: totals.reads,
        kudos: totals.kudos,
        comments: totals.comments
      },
      contributors:
        ws.id
        |> Stats.contributors()
        |> Enum.map(fn s ->
          %{
            user_id: s.user.id,
            docs_owned: s.docs_owned,
            edits_made: s.edits_made,
            reads_earned: s.reads_earned,
            kudos_earned: s.kudos_earned
          }
        end)
    })
  end

  @doc """
  Rotate the invite link: revoke the current one (if any) and mint a
  fresh one, atomically — mirrors TeamLive's `rotate_invite` event.
  """
  def rotate_invite(conn, _params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, invite} <- Workspaces.rotate_invite(ws.id, user.id) do
      Envelope.ok(conn, %{invite: invite_map(invite)})
    end
  end

  @doc """
  Update the caller's display name — mirrors SettingsLive's `save`
  event. Settings are per-user; the workspace in the path only scopes
  access (same as the Settings page URL). Blank clears the name.
  """
  def update_profile(conn, params) do
    user = conn.assigns.current_user
    raw = params["display_name"] |> to_string() |> String.trim()
    next_name = if raw == "", do: nil, else: raw

    changeset = Aveline.Accounts.User.changeset(user, %{"display_name" => next_name})

    with {:ok, updated} <- Aveline.Repo.update(changeset) do
      Envelope.ok(conn, %{user: Views.user(updated)})
    end
  end

  # ===== Helpers =====

  defp doc_card(nil), do: nil

  defp doc_card(d) do
    %{slug: d.slug, title: d.title, summary: d.summary, tags: d.tags || []}
  end

  defp thread_map({c, d}) do
    %{
      body: c.body,
      block_id: c.block_id,
      actor_type: c.actor_type,
      actor_username: c.actor_user && c.actor_user.username,
      inserted_at: iso(c.inserted_at),
      doc_slug: d.slug,
      doc_title: d.title
    }
  end

  defp invite_map(nil), do: nil

  defp invite_map(invite) do
    %{code: invite.code, url: AvelineWeb.Endpoint.url() <> "/invite/" <> invite.code}
  end

  defp iso(nil), do: nil
  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
end
