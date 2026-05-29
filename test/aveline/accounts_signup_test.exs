defmodule Aveline.AccountsSignupTest do
  use Aveline.DataCase, async: true

  alias Aveline.Accounts
  alias Aveline.Tokens
  alias Aveline.Workspaces

  test "creates a user, personal workspace, membership, and token in one shot" do
    assert {:ok, %{user: user, workspace: ws, token: plaintext}} =
             Accounts.signup(%{"username" => "Dragon"})

    # username is downcased
    assert user.username == "dragon"

    # personal workspace named after them
    assert ws.slug == "dragon"
    assert ws.name == "Personal"
    assert ws.created_by_id == user.id

    # they're a member
    assert Workspaces.member?(ws.id, user.id)

    # the token verifies
    assert plaintext =~ ~r/^avl_[A-Za-z0-9_-]{32}$/
    assert %{user_id: uid} = Tokens.verify(plaintext)
    assert uid == user.id
  end

  test "rejects duplicate username" do
    {:ok, _} = Accounts.signup(%{"username" => "arie"})
    assert {:error, %Ecto.Changeset{} = cs} = Accounts.signup(%{"username" => "arie"})
    assert "has already been taken" in (cs |> errors_on() |> Map.get(:username, []))
  end

  test "rejects bad username format" do
    assert {:error, %Ecto.Changeset{}} = Accounts.signup(%{"username" => "Bad Name!"})
  end

  test "allows nil email" do
    {:ok, %{user: user}} = Accounts.signup(%{"username" => "noemail"})
    assert is_nil(user.email)
  end
end
