defmodule AvelineWeb.Setup do
  @moduledoc """
  The one setup surface, rendered everywhere an unconnected user lands
  (signup screen, home card, settings section). One component + one
  prompt builder so every path teaches the agent the same things and
  the copy never drifts between doors.
  """
  use AvelineWeb, :html

  @canonical_base "https://app.aveline.ai"

  @doc """
  Non-nil when this instance is served somewhere other than the
  canonical host (staging, self-hosted): the CLI must be pointed at it
  explicitly, so the prompt and the manual steps carry --api-url.
  """
  def api_base_override do
    base = AvelineWeb.Endpoint.url()
    if base == @canonical_base, do: nil, else: base
  end

  @doc """
  The copy-paste prompt a user hands their coding agent (Claude Code,
  Cursor, Codex: the steps are tool-agnostic). One prompt for
  everyone; the login step is conditional so it works for fresh
  signups and already-keyed members alike.
  """
  def prompt(ws) do
    login_cmd =
      case api_base_override() do
        nil -> "`aveline login`"
        base -> "`aveline login --api-url #{base}`"
      end

    """
    Set up Aveline, the wiki our team uses for shared knowledge (built for AI agents like you). Ask me before you install anything or write any file.

    1. Install the `aveline` CLI from https://github.com/aveline-ai/cli/releases/latest if `aveline --version` fails (pick the binary for this machine and put it on PATH).
    2. Run `aveline whoami`. If it errors, ask me to run #{login_cmd} myself in this terminal and wait for me to confirm. It prompts for my API key interactively (I saved it at signup; if it's lost I can mint a new one in Aveline under Settings, API keys). Don't ask me for the key: it's a secret and must never enter your context or any file.
    3. Then run `aveline use-workspace #{ws.slug}` and read `aveline get-orientation` to learn how this workspace organizes its knowledge.
    4. Add a short note to this project's agent instructions file (CLAUDE.md, AGENTS.md, or your tool's equivalent): we keep shared knowledge in Aveline; interact via the `aveline` CLI (`aveline --help` shows every operation); start sessions with `aveline get-orientation`; run `aveline contract` before your first doc write. New docs are born private and new views land in your personal bucket, so publish deliberately with --visibility workspace / --bucket team when the team should see them.
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
            and comment. Copy the prompt into your coding agent once and it
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
            Listening for your agent…
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
  The vestibule, living-workspace edition (design mock B): while a
  member is unconnected and hasn't skipped, home IS this page. The
  workspace's real docs drift dimly behind a glass panel: proof the
  place is already humming. One action in front. "Look around first"
  is the skip.
  """
  attr :id, :string, required: true
  attr :workspace, :map, required: true
  attr :prompt, :string, required: true
  attr :setup_done, :boolean, default: false
  attr :doc_count, :integer, required: true
  attr :view_count, :integer, required: true
  attr :member_names, :list, required: true
  attr :orientation, :any, required: true
  attr :backdrop_docs, :list, required: true

  @backdrop_slots [
    {"wb-p1", "wb-tier-1", ""},
    {"wb-p4", "wb-tier-1", "wb-drift-b"},
    {"wb-p3", "wb-tier-1", "wb-drift-c"},
    {"wb-p6", "wb-tier-1", "wb-drift-c"},
    {"wb-p2", "wb-tier-2", "wb-drift-b"},
    {"wb-p5", "wb-tier-2", ""},
    {"wb-p7", "wb-tier-3", "wb-drift-b"},
    {"wb-p8", "wb-tier-3", "wb-drift-c"},
    {"wb-p9", "wb-tier-3", ""},
    {"wb-p10", "wb-tier-3", "wb-drift-b"}
  ]

  def welcome(assigns) do
    # Two seductions: an inhabited workspace sells its inheritance (the
    # real docs drifting behind the panel); a fresh one has nothing to
    # show, so it sells what compounds, on an aurora instead of a void.
    # Inhabited means PEOPLE: seed docs alone must never trigger the
    # inheritance pitch over template filler.
    inhabited? = assigns.member_names != []

    assigns =
      assign(assigns,
        placed_docs: Enum.zip(Enum.take(assigns.backdrop_docs, 10), @backdrop_slots),
        others: assigns.member_names,
        inhabited?: inhabited?
      )

    ~H"""
    <div class={"welcome-stage " <> if @inhabited?, do: "", else: "welcome-stage-fresh"} id={@id}>
      <div :if={@inhabited?} class="wb-backdrop" aria-hidden="true">
        <div
          :for={{doc, {pos, tier, drift}} <- @placed_docs}
          class={"wb-card #{pos} #{tier} #{drift}"}
        >
          <div class="wb-title">
            <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round">
              <path d="M4 2h5.5L13 5.5V13a1 1 0 01-1 1H4a1 1 0 01-1-1V3a1 1 0 011-1z" />
            </svg>
            {doc.title}
          </div>
          <div class="wb-line" style={"width: #{skeleton_width(doc.title, 0)}%"}></div>
          <div class="wb-line" style={"width: #{skeleton_width(doc.title, 1)}%"}></div>
          <div class="wb-line" style={"width: #{skeleton_width(doc.title, 2)}%"}></div>
          <div :if={doc.tags != []} class="wb-chips">
            <span :for={tag <- Enum.take(doc.tags, 2)} class="wb-chip">{tag}</span>
          </div>
          <div :if={doc.actor_user} class="wb-meta">
            <span class={"wb-face #{hue_class(doc.actor_user.username)}"}>
              {String.first(doc.actor_user.username)}
            </span>
            {doc.actor_user.username} edited {AvelineWeb.UIHelpers.relative_time(doc.updated_at)}
          </div>
        </div>
      </div>

      <div class="wb-veil" aria-hidden="true"></div>

      <div class="welcome-center">
        <section class="welcome-panel welcome-vestibule">
          <div class="welcome-eyebrow"><span class="welcome-spark">●</span> {@workspace.slug} · aveline</div>

          <h1 class="welcome-h1">
            Welcome to <em>{@workspace.name}</em>.<br />
            <%= if @others == [] do %>
              Your team's shared brain starts here.
            <% else %>
              The team saved you a seat.
            <% end %>
          </h1>

          <%= if @inhabited? do %>
            <p class="welcome-lede">
              This workspace already knows things: decisions, runbooks,
              tickets. Connect your agent and it inherits all of it, plus
              everything written next. You review, comment, and steer. About
              two minutes.
            </p>
          <% else %>
            <p class="welcome-lede">
              Every decision, runbook, and ticket your agents file here
              compounds. In a month, a new teammate's agent can learn the
              whole system in one read. It starts with yours. About two
              minutes.
            </p>
          <% end %>

          <div :if={@inhabited?} class="welcome-proof">
            <span :if={@others != []} class="welcome-facepile">
              <span :for={name <- Enum.take(@others, 5)} class={"wb-face welcome-face #{hue_class(name)}"}>
                {String.first(name)}
              </span>
            </span>
            <span><b>{names_sentence(@others)}</b></span>
            <span class="welcome-sep">·</span>
            <span><b>{@doc_count}</b> docs</span>
            <span class="welcome-sep">·</span>
            <span><b>{@view_count}</b> saved views</span>
          </div>

          <div class="welcome-setup">
            <%= if @setup_done do %>
              <p class="setup-status setup-status-done welcome-done">✓ Your agent is in.</p>
              <button type="button" class="welcome-enter" phx-click="enter_home">
                Take me in →
              </button>
            <% else %>
              <p class="welcome-setup-lead">
                One prompt sets everything up. Paste it into your coding
                agent: Claude Code, Cursor, and Codex all work.
              </p>
              <button
                type="button"
                id={@id <> "-copy"}
                class="welcome-cta"
                phx-hook="CopyToken"
                data-target={"##{@id}-snippet"}
                title="Copy the setup prompt"
              >
                <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round">
                  <rect x="5.5" y="5.5" width="8" height="8" rx="1.5" />
                  <path d="M10.5 3.5v-.75A1.25 1.25 0 009.25 1.5h-6A1.25 1.25 0 002 2.75v6A1.25 1.25 0 003.25 10H4" />
                </svg>
                <span class="token-field-copy-label">Copy setup prompt</span>
              </button>
              <div class="welcome-status">
                <span class="welcome-ping" aria-hidden="true"></span>
                Listening for your agent…
              </div>
              <div class="welcome-or" aria-hidden="true">
                <span></span>or do it yourself<span></span>
              </div>
              <div class="welcome-steps-box">
                <details class="welcome-step" name="welcome-steps" open>
                  <summary class="welcome-step-title">Install the CLI</summary>
                  <div class="welcome-step-body">
                    <a
                      href="https://github.com/aveline-ai/cli/releases/latest"
                      target="_blank"
                      rel="noopener"
                      class="welcome-step-line welcome-step-line-link"
                    >github.com/aveline-ai/cli/releases/latest ↗</a>
                    <div class="welcome-step-note">put it on your PATH</div>
                  </div>
                </details>
                <details class="welcome-step" name="welcome-steps">
                  <summary class="welcome-step-title">Log in</summary>
                  <div class="welcome-step-body">
                    <div class="welcome-step-line">aveline login<%= if base = api_base_override() do %> --api-url {base}<% end %></div>
                    <div class="welcome-step-note">
                      asks for your API key. Lost it? Mint a new one in
                      <.link navigate={~p"/w/#{@workspace.slug}/settings"} class="welcome-step-link">Settings</.link>.
                    </div>
                  </div>
                </details>
                <details class="welcome-step" name="welcome-steps">
                  <summary class="welcome-step-title">Set your workspace</summary>
                  <div class="welcome-step-body">
                    <div class="welcome-step-line">aveline use-workspace {@workspace.slug}</div>
                  </div>
                </details>
                <details class="welcome-step" name="welcome-steps">
                  <summary class="welcome-step-title">Get oriented</summary>
                  <div class="welcome-step-body">
                    <div class="welcome-step-line">aveline get-orientation</div>
                    <div class="welcome-step-note">how the team organizes its knowledge</div>
                  </div>
                </details>
              </div>

              <pre class="welcome-snippet-source" aria-hidden="true"><code id={@id <> "-snippet"}>{@prompt}</code></pre>
            <% end %>
          </div>

          <div :if={@orientation} class="welcome-start">
            Start with
            <span aria-hidden="true">→</span>
            <.link navigate={~p"/w/#{@workspace.slug}/d/#{@orientation.slug}"} class="welcome-start-doc">
              <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round">
                <path d="M4 2h5.5L13 5.5V13a1 1 0 01-1 1H4a1 1 0 01-1-1V3a1 1 0 011-1z" />
                <path d="M9.5 2v3.5H13" />
              </svg>
              {@orientation.title}
            </.link>
          </div>
        </section>
      </div>
    </div>
    """
  end

  # Deterministic skeleton line widths, so the backdrop is stable
  # across renders without storing anything.
  defp skeleton_width(title, line) do
    55 + :erlang.phash2({title, line}, 40)
  end

  # A muted hue per person, stable by name.
  defp hue_class(name), do: "wb-hue-#{:erlang.phash2(name, 5)}"

  # "alice is here", "alice and bob are here", "you're the first one here"
  defp names_sentence([]), do: "you're the first one here"
  defp names_sentence([a]), do: "#{a} is here"
  defp names_sentence([a, b]), do: "#{a} and #{b} are here"

  defp names_sentence(names) do
    {rest, [last]} = Enum.split(names, -1)
    Enum.join(rest, ", ") <> ", and " <> last <> " are here"
  end
end
