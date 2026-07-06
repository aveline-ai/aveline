defmodule AvelineWeb.Plugs.WorkspaceGate do
  @moduledoc """
  Access gate for all /w/* browser URLs, rendered AT the requested URL
  (no redirect). The rule: an unfurl may only ever show what an
  anonymous visitor could see — so unauthenticated fetchers (humans and
  link-preview bots alike) get a branded "private" page with generic
  OpenGraph tags, never doc metadata and never the signup page.

  Three states:
    * member            → pass through to the LiveView
    * no session        → login gate (with `next` back to this URL)
    * signed in, not a member (or workspace doesn't exist — existence
      is information, the two render identically) → no-access gate

  Full-page loads only; in-app live navigation between workspaces the
  user belongs to never hits this. The LiveViews keep their own
  membership checks as the backstop.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias AvelineWeb.LiveSession

  def init(opts), do: opts

  def call(%Plug.Conn{params: %{"slug" => slug}} = conn, _opts) when is_binary(slug) do
    user = LiveSession.current_user(get_session(conn))

    case LiveSession.fetch_workspace_for_user(slug, user) do
      {:ok, _ws} -> conn
      _ when is_nil(user) -> gate(conn, :login, slug)
      _ -> gate(conn, :no_access, slug)
    end
  end

  def call(conn, _opts), do: conn

  defp gate(conn, mode, slug) do
    doc? = String.contains?(conn.request_path, "/d/")

    conn
    |> assign(:og_title, if(doc?, do: "A private doc on Aveline", else: "A private workspace on Aveline"))
    |> assign(:og_description, "Log in to view it, or ask for an invite to this workspace.")
    |> assign(:noindex, true)
    |> assign(:page_title, "Aveline · Private")
    |> put_layout(html: false)
    |> put_view(html: AvelineWeb.GateHTML)
    |> render(:gate, mode: mode, slug: slug, doc?: doc?, next: conn.request_path)
    |> halt()
  end
end
