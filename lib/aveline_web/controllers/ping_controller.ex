defmodule AvelineWeb.PingController do
  use AvelineWeb, :controller

  def ping(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
