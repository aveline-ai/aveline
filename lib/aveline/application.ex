defmodule Aveline.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Initialize Sentry logger handler
    Logger.add_handlers(:aveline)

    # Setup Oban job logging to Logflare
    setup_oban_logging()

    children = [
      {Task.Supervisor, name: Aveline.TaskSupervisor},
      AvelineWeb.Telemetry,
      Aveline.Repo,
      {Oban, Application.fetch_env!(:aveline, Oban)},
      {DNSCluster, query: Application.get_env(:aveline, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Aveline.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Aveline.Finch},
      # Start a worker by calling: Aveline.Worker.start_link(arg)
      # {Aveline.Worker, arg},
      # Start to serve requests, typically the last entry
      AvelineWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Aveline.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AvelineWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Setup Oban telemetry for job start, completion, and failure logging
  defp setup_oban_logging do
    :telemetry.attach_many(
      "oban-job-logger",
      [
        [:oban, :job, :start],
        [:oban, :job, :stop],
        [:oban, :job, :exception]
      ],
      &__MODULE__.handle_oban_event/4,
      %{}
    )
  end

  # Handle Oban telemetry events for logging job lifecycle
  def handle_oban_event([:oban, :job, :start], _measurements, %{job: job}, _config) do
    alias Aveline.LittleLogger, as: LL

    LL.info_job_step(
      job.worker,
      "started",
      %{
        job_id: job.id,
        queue: job.queue,
        attempt_number: job.attempt,
        max_attempts: job.max_attempts
      }
    )
  end

  def handle_oban_event([:oban, :job, :stop], measurements, %{job: job}, _config) do
    alias Aveline.LittleLogger, as: LL

    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    LL.info_job_step(
      job.worker,
      "completed",
      %{
        job_id: job.id,
        queue: job.queue,
        attempt_number: job.attempt,
        duration_ms: duration_ms
      }
    )
  end

  def handle_oban_event([:oban, :job, :exception], _measurements, %{job: job} = meta, _config) do
    alias Aveline.LittleLogger, as: LL

    LL.error_job(
      job.worker,
      "failed",
      # Don't send stacktrace to avoid nested lists
      [],
      %{
        job_id: job.id,
        queue: job.queue,
        attempt_number: job.attempt,
        max_attempts: job.max_attempts,
        error_kind: to_string(Map.get(meta, :kind, "unknown")),
        error_reason:
          case Map.get(meta, :reason) do
            %{message: msg} when is_binary(msg) -> msg
            reason when is_binary(reason) -> reason
            # Truncate long errors
            reason -> inspect(reason) |> String.slice(0, 200)
          end
      }
    )
  end

  def handle_oban_event(_event, _measurements, _metadata, _config), do: :ok
end
