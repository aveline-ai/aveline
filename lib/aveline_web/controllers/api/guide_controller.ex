defmodule AvelineWeb.Api.GuideController do
  @moduledoc """
  Aveline's own guide to using Aveline (`Aveline.Guide`): what the product
  is and how to work it, versioned, with no opinion about how a team
  should run. Served under `/api` (`aveline guide`) and `/papi` (the web
  app's help page).
  """
  use AvelineWeb, :controller

  alias AvelineWeb.Api.Envelope

  def show(conn, _params) do
    Envelope.ok(conn, %{guide: Aveline.Guide.payload()})
  end
end
