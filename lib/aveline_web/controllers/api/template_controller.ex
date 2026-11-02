defmodule AvelineWeb.Api.TemplateController do
  @moduledoc """
  The templates a new workspace can start from, readable before choosing
  one. `index` is the picker's list; `show` is everything a template
  would create, without creating it. Nothing here touches a workspace.

  Served under both `/api` (CLI, `aveline templates`) and `/papi` (the
  signup and new-workspace pickers, which run before any login).
  """
  use AvelineWeb, :controller

  action_fallback AvelineWeb.Api.FallbackController

  alias Aveline.Workspaces.Template
  alias AvelineWeb.Api.Envelope

  def index(conn, _params) do
    Envelope.ok(conn, %{templates: Template.list()})
  end

  def show(conn, %{"name" => name}) do
    case Template.preview(name) do
      nil -> {:error, :not_found}
      preview -> Envelope.ok(conn, %{template: preview})
    end
  end
end
