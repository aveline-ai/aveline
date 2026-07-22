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

  attr :id, :string, required: true
  attr :workspace, :map, required: true
  attr :prompt, :string, required: true
  attr :setup_done, :boolean, default: false

  @doc """
  The first-run hero: home leads with this until the user connects an
  agent or skips. Left column sells and directs (headline, pitch,
  three steps where the third IS the live status); right column shows
  the product doing its thing in a small terminal vignette. Skip
  collapses to the compact card via the parent's "skip_setup" event.
  """
  def setup_hero(assigns) do
    ~H"""
    <div class="setup-card setup-hero" id={@id}>
      <div class="hero-grid">
        <div class="hero-main">
          <h2 class="hero-title">Your team's knowledge, written by your agents</h2>
          <p class="hero-sub">
            Aveline is the shared knowledge base you and your AI agents keep
            together. Agents do the reading, writing, and filing; you review,
            comment, and steer.
          </p>
          <ol class="hero-steps">
            <li>
              <span class="hero-step-num">1</span>
              <span>Copy the setup prompt</span>
            </li>
            <li>
              <span class="hero-step-num">2</span>
              <span>Paste it into Claude Code and follow along</span>
            </li>
            <%= if @setup_done do %>
              <li class="hero-step-done">
                <span class="hero-step-num">✓</span>
                <span>
                  Connected. Your agent read how
                  <span class="mono">{@workspace.slug}</span> works.
                </span>
              </li>
            <% else %>
              <li class="hero-step-waiting">
                <span class="hero-step-num">3</span>
                <span>
                  <span class="setup-pulse" aria-hidden="true"></span>
                  Watch this flip the moment your agent reads the orientation doc
                </span>
              </li>
            <% end %>
          </ol>
          <div class="hero-cta-row">
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
              skip for now
            </button>
          </div>
        </div>
        <div class="hero-side" aria-hidden="true">
          <div class="hero-term">
            <div class="hero-term-bar">
              <span></span><span></span><span></span>
              <span class="hero-term-title">claude · your project</span>
            </div>
            <div class="hero-term-body">
              <div class="ht-line ht-you">you: file yesterday's decisions in aveline</div>
              <div class="ht-line ht-cmd">$ aveline get-orientation</div>
              <div class="ht-line ht-ok">✓ learned how {@workspace.slug} works</div>
              <div class="ht-line ht-cmd">$ aveline create-doc --title "why-we-picked-postgres"</div>
              <div class="ht-line ht-ok">✓ doc created</div>
              <div class="ht-line ht-cmd">$ aveline set-doc-visibility why-we-picked-postgres workspace</div>
              <div class="ht-line ht-ok">✓ published to the team</div>
              <div class="ht-line ht-cursor">▊</div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
