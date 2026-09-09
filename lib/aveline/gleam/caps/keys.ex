defmodule Aveline.Gleam.Caps.Keys do
  @moduledoc "Real IO for src/aveline/caps/keys.gleam. Keep field order in lockstep."

  import Ecto.Query
  import Aveline.Gleam.Interop

  alias Aveline.Accounts.User
  alias Aveline.Repo
  alias Aveline.Tokens
  alias Aveline.Tokens.ApiToken

  def build do
    {:keys_caps,
     fn user_id ->
       user = Repo.get!(User, user_id)
       {:user_info, user.id, user.username, opt(user.display_name), opt(user.email)}
     end,
     fn user_id ->
       user_id |> Tokens.list_active_for_user() |> Enum.map(&api_key/1)
     end,
     fn user_id, name ->
       {:ok, token, plaintext} = Tokens.mint(user_id, name)
       {:minted_key, api_key(token), plaintext}
     end,
     fn user_id, token_id ->
       from(t in Tokens.base_query(),
         where: t.id == ^token_id and t.user_id == ^user_id,
         select: t.id
       )
       |> Repo.one()
       |> opt()
     end,
     fn user_id, token_id ->
       from(t in Tokens.base_query(), where: t.user_id == ^user_id and t.id != ^token_id)
       |> Repo.aggregate(:count, :id)
     end,
     fn token_id ->
       {:ok, _} = Tokens.revoke(Repo.get!(ApiToken, token_id))
       nil
     end}
  end

  defp api_key(t) do
    {:api_key, t.id, t.name, Tokens.masked(t), DateTime.to_iso8601(t.inserted_at),
     opt(t.last_used_at, &DateTime.to_iso8601/1)}
  end
end
