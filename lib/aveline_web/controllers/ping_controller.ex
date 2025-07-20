defmodule AvelineWeb.PingController do
  use AvelineWeb, :controller

  def ping(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def error(conn, _params) do
    raise "EXAMPLE ERROR"
  end
end
