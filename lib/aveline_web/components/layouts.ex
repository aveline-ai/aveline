defmodule AvelineWeb.Layouts do
  @moduledoc """
  Layouts used by the application — root (full HTML doc) and app (inner content).
  """
  use AvelineWeb, :html

  embed_templates "layouts/*"
end
