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
  def prompt(ws) do
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
    assigns =
      assign(assigns,
        placed_docs: Enum.zip(Enum.take(assigns.backdrop_docs, 10), @backdrop_slots),
        others: assigns.member_names
      )

    ~H"""
    <div class="welcome-stage" id={@id}>
      <div class="wb-backdrop" aria-hidden="true">
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

          <p class="welcome-lede">
            This is the team's shared knowledge base. Your AI agents read and
            write it, you review, comment, and steer. Connecting your agent
            teaches it how <span class="mono">{@workspace.slug}</span> works.
          </p>

          <div class="welcome-proof">
            <span :if={@others != []} class="welcome-facepile">
              <span :for={name <- Enum.take(@others, 5)} class={"wb-face welcome-face #{hue_class(name)}"}>
                {String.first(name)}
              </span>
            </span>
            <span><b>{names_sentence(@others)}</b></span>
            <span class="welcome-sep">·</span>
            <span><b>{@doc_count}</b> docs</span>
            <span class="welcome-sep">·</span>
            <span><b>{@view_count}</b> views</span>
          </div>

          <%= if @setup_done do %>
            <p class="setup-status setup-status-done welcome-done">✓ Your agent is in.</p>
            <button type="button" class="welcome-enter" phx-click="enter_home">
              Take me in →
            </button>
          <% else %>
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
            <div class="welcome-cta-micro">then paste it into <span class="mono">Claude Code</span></div>

            <div class="welcome-status">
              <span class="welcome-ping" aria-hidden="true"></span>
              Waiting for your agent to read the orientation doc…
            </div>
          <% end %>

          <div class="welcome-quiet-links">
            <details class="setup-prompt-details">
              <summary>view the prompt</summary>
              <div class="snippet">
                <pre><code id={@id <> "-snippet"}>{@prompt}</code></pre>
              </div>
            </details>
            <span :if={not @setup_done} class="welcome-sep">·</span>
            <button
              :if={not @setup_done}
              type="button"
              class="setup-skip"
              phx-click="skip_setup"
            >
              or look around first
            </button>
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
