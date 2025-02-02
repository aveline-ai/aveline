defmodule Aveline.Repo do
  use Ecto.Repo,
    otp_app: :aveline,
    adapter: Ecto.Adapters.Postgres
end
