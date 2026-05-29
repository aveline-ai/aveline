defmodule AvelineWeb.Api.MeJSON do
  @moduledoc false

  alias AvelineWeb.Api.UserJSON
  alias AvelineWeb.Api.WorkspaceJSON

  def show(%{user: user, workspaces: workspaces}) do
    %{
      user: UserJSON.full(user),
      workspaces: Enum.map(workspaces, &WorkspaceJSON.one/1)
    }
  end
end
