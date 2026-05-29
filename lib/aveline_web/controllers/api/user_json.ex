defmodule AvelineWeb.Api.UserJSON do
  @moduledoc false

  def show(%{user: user}), do: %{user: full(user)}

  def full(user) do
    %{
      id: user.id,
      username: user.username,
      email: user.email,
      display_name: user.display_name
    }
  end

  def summary(nil), do: nil

  def summary(user) do
    %{
      id: user.id,
      username: user.username,
      display_name: user.display_name
    }
  end
end
