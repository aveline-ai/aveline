defmodule AvelineWeb.Api.BaseController do
  @moduledoc """
  The Aveline base doc, served to anyone. No token: an agent that has not
  logged in yet still needs to read what Aveline is and how to log in,
  and the website shows the same text to a logged-out reader. It is
  product documentation from a public repo, so there is nothing here to
  withhold. The same payload rides along with a workspace's orientation
  for callers that are already authenticated.
  """
  use AvelineWeb, :controller

  alias AvelineWeb.Api.Envelope

  def show(conn, _params), do: Envelope.ok(conn, %{base: Aveline.Primer.payload()})
end
