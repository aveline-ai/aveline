defmodule Aveline.Vault do
  @moduledoc """
  Symmetric encryption for secrets we must be able to use (not just
  verify), i.e. data source connection URLs. AES-256-GCM; the key lives
  in the CLOAK_KEY runtime secret (base64, 32 bytes decoded) — never in
  the repo or the database, so a DB dump alone yields ciphertext only.

  The cipher tag ("AES.GCM.V1") is stored with each ciphertext, which
  is what makes key rotation an "add V2, re-encrypt lazily" operation
  instead of a migration crisis.

  Dev/test fall back to a fixed key: nothing real is encrypted there.
  """
  use Cloak.Vault, otp_app: :aveline

  @impl GenServer
  def init(config) do
    config =
      Keyword.put(config, :ciphers,
        default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: key!(), iv_length: 12}
      )

    {:ok, config}
  end

  defp key! do
    case System.get_env("CLOAK_KEY") do
      nil ->
        if Application.get_env(:aveline, :env, :dev) in [:dev, :test] do
          # Fixed, public dev key. Real deployments set CLOAK_KEY.
          :crypto.hash(:sha256, "aveline-dev-only-cloak-key")
        else
          raise "CLOAK_KEY is not set — required outside dev/test"
        end

      b64 ->
        case Base.decode64(b64) do
          {:ok, key} when byte_size(key) == 32 -> key
          _ -> raise "CLOAK_KEY must be base64 of exactly 32 bytes"
        end
    end
  end
end

defmodule Aveline.Encrypted.Binary do
  @moduledoc "Ecto type: transparent encrypt-on-write / decrypt-on-read via Aveline.Vault."
  use Cloak.Ecto.Binary, vault: Aveline.Vault
end
