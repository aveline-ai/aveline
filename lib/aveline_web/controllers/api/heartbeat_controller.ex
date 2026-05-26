defmodule AvelineWeb.Api.HeartbeatController do
  use AvelineWeb, :controller

  def show(conn, _params) do
    json(conn, %{
      status: "ok",
      service: "aveline",
      version: Application.spec(:aveline, :vsn) |> to_string()
    })
  end
end
