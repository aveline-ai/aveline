defmodule AvelineWeb.GateHTML do
  @moduledoc """
  The private-page gate rendered at /w/* URLs by `Plugs.WorkspaceGate`.
  Dead HTML on purpose: it must carry OpenGraph tags for unfurlers and
  work with zero JS. Says nothing about what lives at the URL beyond
  the workspace slug the visitor already has.
  """
  use AvelineWeb, :html

  def gate(assigns) do
    ~H"""
    <div class="auth-shell">
      <AvelineWeb.AuthBg.split />
      <div class="auth-card auth-card-spare">
        <div class="auth-brand auth-brand-hero">
          <span class="nav-brand-mark" style="width:36px;height:36px">A</span>
          <span class="auth-brand-name" style="font-size:26px">aveline</span>
        </div>

        <%= if @mode == :login do %>
          <div class="gate-body">
            <div class="gate-title">
              {if @doc?, do: "This doc is private", else: "This workspace is private"}
            </div>
            <p class="gate-copy">Log in to view it.</p>
            <a href={~p"/login?next=#{@next}"} class="auth-submit gate-btn">Log in</a>
            <p class="gate-fine">
              New to Aveline? You'll need an invite to this workspace either way — ask whoever shared the link.
            </p>
          </div>
        <% else %>
          <div class="gate-body">
            <div class="gate-title">You don't have access to this workspace</div>
            <p class="gate-copy">
              <code class="gate-slug">{@slug}</code>
              — ask whoever shared this link for an invite.
            </p>
            <a href={~p"/"} class="auth-submit gate-btn">Go to your workspaces</a>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
