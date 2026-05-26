defmodule AvelineWeb.HelloLive do
  use AvelineWeb, :live_view

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Aveline",
       count: 0,
       last_action: nil
     )}
  end

  @impl true
  def handle_event("inc", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  @impl true
  def handle_event("dec", _params, socket) do
    {:noreply, update(socket, :count, &(&1 - 1))}
  end

  @impl true
  def handle_event("test_log", _params, socket) do
    Logger.info("Test log from Aveline hello page", event_name: "test_log_button")
    {:noreply, assign(socket, :last_action, "Log sent → check Sentry Logs.")}
  end

  @impl true
  def handle_event("test_error", _params, socket) do
    try do
      raise RuntimeError, "Test error from Aveline hello page (intentional)"
    rescue
      e ->
        Sentry.capture_exception(e, stacktrace: __STACKTRACE__)
    end

    {:noreply, assign(socket, :last_action, "Error captured → check Sentry Issues.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="text-align:center">
      <h1 style="font-size:2.5rem;font-weight:600;letter-spacing:-0.03em;margin-bottom:0.5rem">
        Hello, world.
      </h1>
      <p style="color:rgba(232,232,232,0.55);margin-bottom:2.5rem">
        Aveline is alive.
      </p>

      <div style="
        display:inline-flex;align-items:center;gap:1rem;
        padding:1rem 1.5rem;
        background:rgba(232,232,232,0.04);
        border:1px solid rgba(232,232,232,0.1);
        border-radius:999px;
      ">
        <button
          phx-click="dec"
          style="
            width:2.5rem;height:2.5rem;border-radius:50%;border:none;
            background:rgba(232,232,232,0.08);color:#f5f5f5;font-size:1.25rem;
            cursor:pointer;font-family:inherit;
          "
        >
          −
        </button>
        <span style="font-size:1.5rem;font-weight:500;min-width:3rem;text-align:center">
          {@count}
        </span>
        <button
          phx-click="inc"
          style="
            width:2.5rem;height:2.5rem;border-radius:50%;border:none;
            background:#f5f5f5;color:#0a0a0a;font-size:1.25rem;
            cursor:pointer;font-family:inherit;
          "
        >
          +
        </button>
      </div>

      <p style="color:rgba(232,232,232,0.3);font-size:0.8rem;margin-top:1.5rem">
        If the counter updates without a page reload, LiveView is wired correctly.
      </p>

      <div style="margin-top:2.5rem;display:flex;gap:0.75rem;justify-content:center;flex-wrap:wrap">
        <button
          phx-click="test_log"
          style="
            padding:0.65rem 1.1rem;border-radius:999px;
            border:1px solid rgba(232,232,232,0.15);
            background:rgba(232,232,232,0.04);color:#e8e8e8;
            font-family:inherit;font-size:0.85rem;cursor:pointer;
          "
        >
          Send test log
        </button>
        <button
          phx-click="test_error"
          style="
            padding:0.65rem 1.1rem;border-radius:999px;
            border:1px solid rgba(255,130,130,0.25);
            background:rgba(255,130,130,0.06);color:rgba(255,180,180,0.95);
            font-family:inherit;font-size:0.85rem;cursor:pointer;
          "
        >
          Send test error
        </button>
      </div>

      <div style="min-height:1.5rem;margin-top:1rem;font-size:0.85rem;color:rgba(110,231,183,0.85)">
        <%= if @last_action do %>
          {@last_action}
        <% end %>
      </div>
    </div>
    """
  end
end
