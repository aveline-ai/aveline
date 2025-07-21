defmodule AvelineWeb.PingController do
  use AvelineWeb, :controller

  def ping(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def error(_conn, _params) do
    raise "EXAMPLE ERROR"
  end

  def test_job(conn, _params) do
    job_args = %{
      "message" => "Success test job triggered from API endpoint at #{DateTime.utc_now()}",
      "source" => "ping_controller",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case Aveline.TestSuccessWorker.new(job_args) |> Oban.insert() do
      {:ok, job} ->
        json(conn, %{
          status: "ok",
          message: "Success job enqueued successfully",
          job_id: job.id,
          queue: "test_success",
          job_args: job_args
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{status: "error", message: "Failed to enqueue job", reason: inspect(reason)})
    end
  end

  def test_error_job(conn, _params) do
    job_args = %{
      "message" => "Error test job triggered from API endpoint at #{DateTime.utc_now()}",
      "source" => "ping_controller",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case Aveline.TestErrorWorker.new(job_args) |> Oban.insert() do
      {:ok, job} ->
        json(conn, %{
          status: "ok",
          message: "Error job enqueued successfully (will fail when processed)",
          job_id: job.id,
          queue: "test_error",
          job_args: job_args
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{status: "error", message: "Failed to enqueue job", reason: inspect(reason)})
    end
  end
end
