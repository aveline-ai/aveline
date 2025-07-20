defmodule Aveline.TestWorker do
  use Oban.Worker, queue: :default

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"message" => message}}) do
    IO.puts("🎉 Oban Test Job executed with message: #{message}")
    IO.puts("Job processed at: #{DateTime.utc_now()}")
    :ok
  end

  def perform(%Oban.Job{args: args}) do
    IO.puts("🎉 Oban Test Job executed with args: #{inspect(args)}")
    IO.puts("Job processed at: #{DateTime.utc_now()}")
    :ok
  end
end
