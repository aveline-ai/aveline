defmodule AvelineWeb.Setup do
  @moduledoc """
  The one setup surface, rendered everywhere an unconnected user lands
  (signup screen, home card, settings section). One component + one
  prompt builder so every path teaches the agent the same things and
  the copy never drifts between doors.
  """
  use AvelineWeb, :html

  @doc """
  The copy-paste prompt a user hands their Claude.

    * `:new_user` — fresh account holding a fresh API key: the login
      step is unconditional.
    * `:existing_user` — someone already keyed (invitees, second
      machines, skipped setups): login only if `whoami` fails.
  """
  def prompt(ws, variant \\ :existing_user)

  def prompt(ws, :new_user) do
    """
    Set up Aveline, the wiki our team uses for shared knowledge (built for AI agents like you):

    1. Install the `aveline` CLI from https://github.com/aveline-ai/cli/releases/latest (pick the binary for this machine and put it on PATH).
    2. Ask me to run `aveline login` myself in this terminal and wait for me to confirm. It prompts for my API key interactively. Don't ask me for the key: it's a secret and must never enter your context or any file.
    3. Then run `aveline use-workspace #{ws.slug}`, verify with `aveline whoami`, and read `aveline get-orientation` to learn how this workspace organizes its knowledge.
    4. Add a short note to this project's CLAUDE.md: we keep shared knowledge in Aveline; interact via the `aveline` CLI (`aveline --help` shows every operation); start sessions with `aveline get-orientation`; run `aveline contract` before your first doc write (it shows every block type and edit op with a valid example); new docs are born private and new views land in your personal bucket, so publish deliberately with --visibility workspace / --bucket team when the team should see them.
    """
  end

  def prompt(ws, :existing_user) do
    """
    Set up Aveline, the wiki our team uses for shared knowledge (built for AI agents like you):

    1. Install the `aveline` CLI from https://github.com/aveline-ai/cli/releases/latest if `aveline --version` fails (pick the binary for this machine and put it on PATH).
    2. Run `aveline whoami`. If it errors, ask me to run `aveline login` myself in this terminal and wait for me to confirm. It prompts for my API key interactively. Don't ask me for the key: it's a secret and must never enter your context or any file.
    3. Then run `aveline use-workspace #{ws.slug}` and read `aveline get-orientation` to learn how this workspace organizes its knowledge.
    4. Add a short note to this project's CLAUDE.md: we keep shared knowledge in Aveline; interact via the `aveline` CLI (`aveline --help` shows every operation); start sessions with `aveline get-orientation`; run `aveline contract` before your first doc write (it shows every block type and edit op with a valid example); new docs are born private and new views land in your personal bucket, so publish deliberately with --visibility workspace / --bucket team when the team should see them.
    """
  end

  attr :id, :string, required: true
  attr :workspace, :map, required: true
  attr :prompt, :string, required: true
  attr :setup_done, :boolean, default: false
  attr :show_pitch, :boolean, default: true

  def setup_card(assigns) do
    ~H"""
    <div class="setup-card" id={@id}>
      <div class="setup-card-row">
        <div class="setup-card-text">
          <div class="setup-card-title">Connect your agent</div>
          <p :if={@show_pitch} class="setup-card-pitch">
            Your AI agents read and write this workspace's knowledge; you review
            and comment. Copy the prompt into Claude Code once and your agent
            learns how <span class="mono">{@workspace.slug}</span> works.
          </p>
        </div>
        <button
          type="button"
          id={@id <> "-copy"}
          class="setup-card-cta"
          phx-hook="CopyToken"
          data-target={"##{@id}-snippet"}
          title="Copy the setup prompt"
        >
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
            <rect x="9" y="9" width="12" height="12" rx="2" />
            <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
          </svg>
          <span class="token-field-copy-label">Copy setup prompt</span>
        </button>
      </div>
      <div class="setup-card-foot">
        <%= if @setup_done do %>
          <p class="setup-status setup-status-done">
            ✓ Your agent just read the orientation doc. You're connected.
          </p>
        <% else %>
          <p class="setup-status">
            <span class="setup-pulse" aria-hidden="true"></span>
            Waiting for your agent to read the orientation doc…
          </p>
        <% end %>
        <details class="setup-prompt-details">
          <summary>view the prompt</summary>
          <div class="snippet">
            <pre><code id={@id <> "-snippet"}>{@prompt}</code></pre>
          </div>
        </details>
      </div>
    </div>
    """
  end

  @doc """
  The vestibule: while a member is unconnected and hasn't skipped,
  home IS this page. Nearly empty on purpose: a welcome in the
  product's own quiet voice, one action, a pulse of proof-of-life,
  and the orientation doc as the single pointer (the same doc their
  agent is about to read). "Look around first" is the skip. The
  confidence of an almost-empty page is the design.
  """
  attr :id, :string, required: true
  attr :workspace, :map, required: true
  attr :prompt, :string, required: true
  attr :setup_done, :boolean, default: false
  attr :doc_count, :integer, required: true
  attr :view_count, :integer, required: true
  attr :member_names, :list, required: true
  attr :orientation, :any, required: true

  def welcome(assigns) do
    ~H"""
    <div class="welcome-vestibule" id={@id}>
      <h1 class="welcome-title">Welcome to {@workspace.name}.</h1>
      <p class="welcome-body">
        This is your team's shared knowledge base: docs, tickets, and views
        kept together by the people here and their AI agents. Connect your
        agent and it learns how <span class="mono">{@workspace.slug}</span>
        works, then does the reading and filing for you.
      </p>
      <p class="welcome-life">
        {@doc_count} docs · {@view_count} views · {names_sentence(@member_names)}
      </p>

      <div class="welcome-action">
        <%= if @setup_done do %>
          <p class="setup-status setup-status-done">✓ Your agent is in.</p>
          <button type="button" class="welcome-enter" phx-click="enter_home">
            Take me in →
          </button>
        <% else %>
          <button
            type="button"
            id={@id <> "-copy"}
            class="setup-card-cta welcome-cta"
            phx-hook="CopyToken"
            data-target={"##{@id}-snippet"}
            title="Copy the setup prompt"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
              <rect x="9" y="9" width="12" height="12" rx="2" />
              <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
            </svg>
            <span class="token-field-copy-label">Copy setup prompt</span>
          </button>
          <p class="welcome-hint">then paste it into Claude Code</p>
          <p class="setup-status">
            <span class="setup-pulse" aria-hidden="true"></span>
            Waiting for your agent to read the orientation doc…
          </p>
        <% end %>
      </div>

      <div class="welcome-links">
        <details class="setup-prompt-details">
          <summary>view the prompt</summary>
          <div class="snippet">
            <pre><code id={@id <> "-snippet"}>{@prompt}</code></pre>
          </div>
        </details>
        <button
          :if={not @setup_done}
          type="button"
          class="setup-skip"
          phx-click="skip_setup"
        >
          or look around first
        </button>
      </div>

      <.link
        :if={@orientation}
        navigate={~p"/w/#{@workspace.slug}/d/#{@orientation.slug}"}
        class="welcome-orientation"
      >
        <span class="welcome-orientation-label">Start with</span>
        <span class="welcome-orientation-title">{@orientation.title}</span>
        <span aria-hidden="true">→</span>
      </.link>
    </div>
    """
  end

  # "alice", "alice and bob", "alice, bob, and carol are here"
  defp names_sentence([]), do: "your team is on the way"
  defp names_sentence([a]), do: "#{a} is here"
  defp names_sentence([a, b]), do: "#{a} and #{b} are here"

  defp names_sentence(names) do
    {rest, [last]} = Enum.split(names, -1)
    Enum.join(rest, ", ") <> ", and " <> last <> " are here"
  end
end
