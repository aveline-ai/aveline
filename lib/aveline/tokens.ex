defmodule Aveline.Tokens do
  @moduledoc """
  API tokens.

  Plaintext is `avl_<32 url-safe chars>`. We store the sha256 hex of the
  full plaintext token and the first 8 plaintext chars for display.
  Plaintext is returned to the caller on `mint/2` ONCE and never persisted.
  """

  import Ecto.Query

  alias Aveline.Repo
  alias Aveline.Tokens.ApiToken

  @prefix "avl_"
  @random_bytes 24

  @doc """
  Always returns an Ecto query — kept for shape consistency. Tokens have no
  soft-delete; we filter on `revoked_at` here so callers can compose.
  """
  def base_query do
    from t in ApiToken, where: is_nil(t.revoked_at)
  end

  @doc """
  Mint a new token for the given user. Returns
  `{:ok, %ApiToken{}, plaintext}` on success.
  """
  def mint(user_id, name) when is_binary(user_id) and is_binary(name) do
    mint_with(generate_plaintext(), user_id, name)
  end

  @doc """
  Like `mint/2` but takes a pre-generated plaintext (e.g. the signup form
  shows the token to the user *before* they submit, so the same plaintext
  needs to land in the DB on submit).
  """
  def mint_with(plaintext, user_id, name)
      when is_binary(plaintext) and is_binary(user_id) and is_binary(name) do
    if valid_plaintext_shape?(plaintext) do
      attrs = %{
        user_id: user_id,
        name: name,
        token_hash: hash(plaintext),
        token_prefix: String.slice(plaintext, 0, 8)
      }

      case %ApiToken{} |> ApiToken.changeset(attrs) |> Repo.insert() do
        {:ok, token} -> {:ok, token, plaintext}
        {:error, _} = err -> err
      end
    else
      {:error, :invalid_plaintext}
    end
  end

  @doc "Generate a fresh plaintext token without persisting it."
  def generate_plaintext do
    rand = :crypto.strong_rand_bytes(@random_bytes) |> Base.url_encode64(padding: false)
    @prefix <> String.slice(rand, 0, 32)
  end

  defp valid_plaintext_shape?(p) when is_binary(p) do
    String.starts_with?(p, @prefix) and byte_size(p) == byte_size(@prefix) + 32
  end

  @doc """
  Verify a plaintext bearer token. Returns `%ApiToken{}` preloaded with user,
  or `nil`.
  """
  def verify(plaintext) when is_binary(plaintext) do
    if String.starts_with?(plaintext, @prefix) do
      h = hash(plaintext)

      from(t in base_query(),
        where: t.token_hash == ^h,
        preload: [:user]
      )
      |> Repo.one()
    else
      nil
    end
  end

  def verify(_), do: nil

  @doc """
  Mark token as recently used. Best-effort — failures are silently ignored.
  """
  def touch_last_used(%ApiToken{} = token) do
    from(t in ApiToken, where: t.id == ^token.id)
    |> Repo.update_all(set: [last_used_at: DateTime.utc_now()])

    :ok
  end

  def touch_last_used(_), do: :ok

  def revoke(%ApiToken{} = token) do
    token
    |> Ecto.Changeset.change(%{revoked_at: DateTime.utc_now()})
    |> Repo.update()
  end

  def list_for_user(user_id) do
    from(t in ApiToken,
      where: t.user_id == ^user_id,
      order_by: [desc: t.inserted_at]
    )
    |> Repo.all()
  end

  # ===== Internals =====

  defp hash(plaintext) do
    :crypto.hash(:sha256, plaintext) |> Base.encode16(case: :lower)
  end
end
