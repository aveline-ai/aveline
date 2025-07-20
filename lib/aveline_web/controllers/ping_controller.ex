defmodule AvelineWeb.PingController do
  use AvelineWeb, :controller

  def ping(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def error(conn, _params) do
    raise "EXAMPLE ERROR"
  end

  def test_job(conn, _params) do
    job_args = %{
      "message" => "Test job triggered from API endpoint at #{DateTime.utc_now()}",
      "source" => "ping_controller",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case Aveline.TestWorker.new(job_args) |> Oban.insert() do
      {:ok, job} ->
        json(conn, %{
          status: "ok",
          message: "Job enqueued successfully",
          job_id: job.id,
          job_args: job_args
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{status: "error", message: "Failed to enqueue job", reason: inspect(reason)})
    end
  end
end
