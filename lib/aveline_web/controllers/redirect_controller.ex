defmodule AvelineWeb.RedirectController do
  @moduledoc """
  Permanent homes for retired URLs. `/w/:slug/usage` folded into the Team
  page, so old links keep working.
  """
  use AvelineWeb, :controller

  def team(conn, %{"slug" => slug}) do
    redirect(conn, to: ~p"/w/#{slug}/team")
  end
end
