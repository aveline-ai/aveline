defmodule AvelineWeb.Api.WorkspaceJSON do
  @moduledoc false

  def index(%{workspaces: workspaces}) do
    %{workspaces: Enum.map(workspaces, &one/1)}
  end

  def show(%{workspace: workspace}), do: one(workspace)

  def one(w) do
    %{
      id: w.id,
      slug: w.slug,
      name: w.name,
      inserted_at: w.inserted_at,
      updated_at: w.updated_at,
      deleted_at: w.deleted_at
    }
  end
end
