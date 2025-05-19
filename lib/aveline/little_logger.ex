defmodule Aveline.LittleLogger do
  @moduledoc """
  The wrapper around the elixir `Logger` with some logging helpers. We currently pipe our logs to Logflare.

  This should be aliased everywhere as such (for easy ctrl-f):
    alias Aveline.LittleLogger, as: LL
  """
  require Logger

  ## Metadata

  @doc """
  Add the current user ID to the logger metadata.
  """
  def metadata_add_current_user_id(user_id) do
    Logger.metadata(current_user_id: user_id)
  end

  ## Logging

  # Some simple symmetrical info/warning/error wrappers below. Use `*_event` if you want to have an event_name logged
  # in the metadata and if the event name makes sense as the top level message (what we see in logflare).

  ### Info

  def info(message), do: Logger.info("[INFO] #{message}")
  def info(message, metadata), do: Logger.info("[INFO] #{message}", metadata)

  def info_event(event_name), do: Logger.info("[INFO][EVENT] #{event_name}", %{event_name: event_name})

  def info_event(event_name, metadata) do
    Logger.info("[INFO][EVENT] #{event_name}", Map.put(metadata, :event_name, event_name))
  end

  def info_job_step(job_name, step_name) do
    Logger.info("[INFO][JOB] #{job_name}_#{step_name}", %{job: job_name, step: step_name})
  end

  def info_job_step(job_name, step_name, metadata) do
    total_metadata =
      metadata
      |> Map.put(:job, job_name)
      |> Map.put(:step, step_name)

    Logger.info("[INFO][JOB] #{job_name}_#{step_name}", total_metadata)
  end

  ### Warning

  def warning(message), do: Logger.warning("[WARNING] #{message}")
  def warning(message, metadata), do: Logger.warning("[WARNING] #{message}", metadata)

  def warning_event(event_name), do: Logger.warning("[WARNING][EVENT] #{event_name}", %{event_name: event_name})

  def warning_event(event_name, metadata) do
    Logger.warning("[WARNING][EVENT] #{event_name}", Map.put(metadata, :event_name, event_name))
  end

  ### Error

  def error(message), do: Logger.error("[ERROR] #{message}")
  def error(message, metadata), do: Logger.error("[ERROR] #{message}", metadata)

  def error_event(event_name), do: Logger.error("[ERROR][EVENT] #{event_name}", %{event_name: event_name})

  def error_event(event_name, metadata) do
    Logger.error("[ERROR][EVENT] #{event_name}", Map.put(metadata, :event_name, event_name))
  end

  def error_job(job_name, error_kind, stacktrace, metadata \\ %{}) do
    total_metadata =
      metadata
      |> Map.put(:job, job_name)
      |> Map.put(:error_kind, error_kind)
      |> Map.put(:stacktrace, stacktrace)

    Logger.error("[ERROR][JOB] #{job_name}_#{error_kind}", total_metadata)
  end
end
