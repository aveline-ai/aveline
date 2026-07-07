defmodule Aveline.DataSources.TLS do
  @moduledoc """
  Interprets a dial URL's query string into driver TLS options, and
  strips it (Ecto's URL parser would otherwise atom-ize unknown params
  and leak them into the driver).

  Recognized, per convention:

    * postgres: `?sslmode=disable | prefer | allow | require |
      verify-ca | verify-full` (libpq's vocabulary)
    * mysql: `?ssl-mode=DISABLED | PREFERRED | REQUIRED | VERIFY_CA |
      VERIFY_IDENTITY`
    * either: `?ssl=true | false`

  Mapping:
    * disable(d) / false → no TLS
    * prefer / allow / required / true → encrypt, no cert validation
      (stops passive snooping; use verify for hostile networks)
    * verify-ca / verify-full / VERIFY_* → verify_peer against the
      system CA roots with hostname checking

  Everything else in the query is dropped — the query string is a TLS
  channel, not a general driver-tuning surface.
  """

  @doc "Returns {url_without_query, ssl_opts | nil}."
  def split(url) when is_binary(url) do
    uri = URI.parse(url)
    params = URI.decode_query(uri.query || "")
    base = uri |> Map.put(:query, nil) |> URI.to_string()
    {base, ssl_opts(params, uri.host)}
  end

  defp ssl_opts(params, host) do
    mode =
      cond do
        m = params["sslmode"] -> String.downcase(m)
        m = params["ssl-mode"] -> String.downcase(m)
        params["ssl"] in ["true", "1"] -> "require"
        params["ssl"] in ["false", "0"] -> "disable"
        true -> nil
      end

    case mode do
      nil -> nil
      "disable" -> nil
      "disabled" -> nil
      m when m in ["prefer", "allow", "require", "required", "preferred"] -> [verify: :verify_none]
      m when m in ["verify-ca", "verify-full", "verify_ca", "verify_identity"] -> verify_opts(host)
      _other -> [verify: :verify_none]
    end
  end

  defp verify_opts(host) do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(host || ""),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)],
      depth: 3
    ]
  end
end
