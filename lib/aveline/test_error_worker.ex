defmodule Aveline.TestErrorWorker do
  use Oban.Worker, queue: :test_error, max_attempts: 2

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"message" => message}}) do
    IO.puts("💥 Oban Test Error Job started with message: #{message}")
    IO.puts("Job started at: #{DateTime.utc_now()}")

    # Simulate some work before failing
    Process.sleep(100)

    raise "Intentional test error: #{message}"
  end

  def perform(%Oban.Job{args: args}) do
    IO.puts("💥 Oban Test Error Job started with args: #{inspect(args)}")
    IO.puts("Job started at: #{DateTime.utc_now()}")

    # Simulate some work before failing
    Process.sleep(100)

    raise "Intentional test error with args: #{inspect(args)}"
  end
end
