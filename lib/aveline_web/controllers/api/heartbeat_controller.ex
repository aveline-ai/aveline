defmodule AvelineWeb.Api.HeartbeatController do
  use AvelineWeb, :controller

  alias AvelineWeb.Api.Envelope

  def show(conn, _params) do
    Envelope.ok(conn, %{
      service: "aveline",
      version: Application.spec(:aveline, :vsn) |> to_string()
    })
  end
end
