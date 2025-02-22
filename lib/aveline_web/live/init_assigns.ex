defmodule AvelineWeb.InitAssigns do
  @moduledoc """
  Ensures common `assigns` are applied to all LiveViews attaching this hook.
  """
  alias Aveline.Account

  import Phoenix.Component

  def on_mount(:user, _params, session, socket) do
    user_id = session["user_id"]

    case Account.get_user_by_id(user_id) do
      # TODO(Arie): Redirect to login page if user is not found
      nil ->
        {:halt, socket}

      user ->
        {:cont, socket |> assign(:current_user, user)}
    end
  end
end
