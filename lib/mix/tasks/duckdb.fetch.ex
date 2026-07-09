defmodule Mix.Tasks.Duckdb.Fetch do
  @shortdoc "Fetch the pinned DuckDB CLI binary into priv/duckdb/"

  @moduledoc """
  Downloads the pinned DuckDB CLI (the workspace-source analytics
  engine) into `priv/duckdb/duckdb`. One static binary, no toolchain:
  the Dockerfile runs the same pin for the image, this task covers
  local dev. The app boots fine without it — workspace-source runs
  fail with a clear "engine not installed" error until it's fetched.

      mix duckdb.fetch

  The download is checksum-pinned per platform; bumping the version
  means updating both the version and the checksums here and in the
  Dockerfile.
  """
  use Mix.Task

  @version "1.4.4"

  # sha256 per release asset. A nil pin means trust-on-first-use: the
  # task prints the digest so it can be pinned after verification.
  @checksums %{
    "duckdb_cli-osx-universal.zip" => "3261e52ea423a97bb766172b584ceae20bb90b2d40552ab24c1b740ace79c972",
    "duckdb_cli-linux-amd64.zip" => "ea79eae4233f1aba9a020c8a61877de38a789bc62cdd37485d3589cd77dc0d3e",
    "duckdb_cli-linux-arm64.zip" => "97995363217ddef691fe53b26df3b55ff368d356613d9daaea5999bb7a637e60"
  }

  @impl true
  def run(_argv) do
    Mix.Task.run("app.config")

    asset = asset_for(:os.type(), :erlang.system_info(:system_architecture))
    url = "https://github.com/duckdb/duckdb/releases/download/v#{@version}/#{asset}"
    dest_dir = Path.join(:code.priv_dir(:aveline) |> to_string(), "duckdb")
    dest = Path.join(dest_dir, "duckdb")

    Mix.shell().info("Fetching DuckDB v#{@version} (#{asset})…")

    zip_bytes = download!(url)

    digest = :crypto.hash(:sha256, zip_bytes) |> Base.encode16(case: :lower)

    case Map.get(@checksums, asset) do
      nil ->
        Mix.shell().info("sha256 #{digest} (unpinned — verify and pin in duckdb.fetch + Dockerfile)")

      ^digest ->
        Mix.shell().info("sha256 verified")

      other ->
        Mix.raise("checksum mismatch for #{asset}: got #{digest}, pinned #{other}")
    end

    {:ok, files} = :zip.extract(zip_bytes, [:memory])

    {_name, binary} =
      Enum.find(files, fn {name, _} -> Path.basename(to_string(name)) == "duckdb" end) ||
        Mix.raise("no duckdb binary inside #{asset}")

    File.mkdir_p!(dest_dir)
    File.write!(dest, binary)
    File.chmod!(dest, 0o755)

    Mix.shell().info("Installed #{dest}")
  end

  # curl does the fetch (ships on macOS and in the Docker build stage;
  # OTP's httpc trips on GitHub's CDN cert chain). -f fails on HTTP
  # errors, -L follows the release 302.
  defp download!(url) do
    case System.cmd("curl", ["-fsSL", url], stderr_to_stdout: true) do
      {body, 0} -> body
      {out, code} -> Mix.raise("download failed (curl exit #{code}): #{String.slice(out, 0, 200)}")
    end
  end

  defp asset_for({:unix, :darwin}, _arch), do: "duckdb_cli-osx-universal.zip"

  defp asset_for({:unix, :linux}, arch) do
    if to_string(arch) =~ "aarch64",
      do: "duckdb_cli-linux-arm64.zip",
      else: "duckdb_cli-linux-amd64.zip"
  end

  defp asset_for(os, arch), do: Mix.raise("unsupported platform: #{inspect(os)} #{arch}")
end
