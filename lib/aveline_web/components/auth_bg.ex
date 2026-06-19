defmodule AvelineWeb.AuthBg do
  @moduledoc """
  Split-screen background frame for auth pages (signup / login / invite).
  Same aesthetic as the landing page: warm parchment left with subtle
  sine-wave drift, deep dark right with matrix-style cascade. The
  canvases get their animations from the `OrganicCanvas` and
  `MatrixCanvas` JS hooks in app.js.
  """
  use Phoenix.Component

  def split(assigns) do
    ~H"""
    <div class="auth-pane auth-pane-human" aria-hidden="true">
      <canvas class="canvas-organic" id="auth-canvas-organic" phx-hook="OrganicCanvas" phx-update="ignore"></canvas>
    </div>
    <div class="auth-pane auth-pane-agent" aria-hidden="true">
      <canvas class="canvas-matrix" id="auth-canvas-matrix" phx-hook="MatrixCanvas" phx-update="ignore"></canvas>
    </div>
    """
  end
end
