defmodule AvelineWeb.Api.StarterController do
  @moduledoc """
  What `create-workspace --setup standard` would write, without writing
  it: the tags, the boards and the orientation doc a new workspace
  starts with.

  It exists so the Standard-or-Custom question can be answered by
  someone who has seen the answer. Nothing here touches a workspace, and
  calling it changes nothing.
  """
  use AvelineWeb, :controller

  alias Aveline.Workspaces.Template
  alias AvelineWeb.Api.Envelope

  def show(conn, params) do
    mode = if params["setup"] == "custom", do: :custom, else: :standard

    Envelope.ok(conn, %{
      starter: %{
        "setup" => to_string(mode),
        "tags" =>
          Enum.map(Template.tags(mode), fn {slug, description, _color, _sort} ->
            %{"slug" => slug, "description" => description}
          end),
        "views" =>
          Enum.map(Template.views(mode), fn {name, description, config} ->
            %{"name" => name, "description" => description, "config" => config}
          end),
        "orientation_blocks" => Template.orientation_blocks(mode),
        "docs" =>
          Enum.map(Template.docs(mode), fn {slug, title, _summary, tags, _blocks} ->
            %{"slug" => slug, "title" => title, "tags" => tags}
          end)
      }
    })
  end
end
