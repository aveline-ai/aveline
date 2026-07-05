defmodule Aveline.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Sentry 12 auto-attaches its LoggerHandler on startup when SENTRY_DSN +
    # enable_logs are set (see config/runtime.exs). No manual handler attach
    # needed here. With no DSN, Sentry is a clean no-op.

    children = [
      {Task.Supervisor, name: Aveline.TaskSupervisor},
      AvelineWeb.Telemetry,
      Aveline.Vault,
      Aveline.Repo,
      Aveline.DataSources.Cache,
      {Oban, Application.fetch_env!(:aveline, Oban)},
      {DNSCluster, query: Application.get_env(:aveline, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Aveline.PubSub},
      {Finch, name: Aveline.Finch},
      AvelineWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Aveline.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    AvelineWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
