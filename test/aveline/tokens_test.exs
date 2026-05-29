defmodule Aveline.TokensTest do
  use Aveline.DataCase, async: true

  alias Aveline.Tokens

  import Aveline.Fixtures

  test "mint returns plaintext exactly once and verify works" do
    u = user_fixture()
    {:ok, token, plaintext} = Tokens.mint(u.id, "laptop")

    assert String.starts_with?(plaintext, "avl_")
    assert token.token_prefix == String.slice(plaintext, 0, 8)

    found = Tokens.verify(plaintext)
    assert found.id == token.id
    assert found.user.id == u.id
  end

  test "verify returns nil for bogus tokens" do
    assert Tokens.verify("nope") == nil
    assert Tokens.verify("avl_wronghash") == nil
    assert Tokens.verify(nil) == nil
  end

  test "revoke disables verification" do
    u = user_fixture()
    {:ok, token, plaintext} = Tokens.mint(u.id, "laptop")
    {:ok, _} = Tokens.revoke(token)
    assert Tokens.verify(plaintext) == nil
  end

  test "touch_last_used updates the timestamp" do
    u = user_fixture()
    {:ok, token, _} = Tokens.mint(u.id, "laptop")
    assert is_nil(token.last_used_at)
    :ok = Tokens.touch_last_used(token)

    reloaded = Aveline.Repo.get!(Aveline.Tokens.ApiToken, token.id)
    assert reloaded.last_used_at
  end
end
