defmodule AvelineWeb.Api.ContractController do
  @moduledoc """
  GET /api/contract — the doc write contract (block types, ops, edit
  modes, dispositions) with a valid example for every shape. Workspace-
  independent: it describes the API, not any workspace's data.
  """
  use AvelineWeb, :controller

  alias Aveline.Contract
  alias AvelineWeb.Api.Envelope

  action_fallback AvelineWeb.Api.FallbackController

  def show(conn, _params) do
    Envelope.ok(conn, %{contract: Contract.write_contract()})
  end
end
