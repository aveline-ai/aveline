defmodule Aveline.AccountsSignupTest do
  use Aveline.DataCase, async: true

  alias Aveline.Accounts
  alias Aveline.Tokens
  alias Aveline.Workspaces

  test "creates a user, workspace, membership, and token in one shot" do
    assert {:ok, %{user: user, workspace: ws, token: plaintext}} =
             Accounts.signup(%{"username" => "Dragon", "workspace_name" => "Dragon Inc"})

    # username is downcased
    assert user.username == "dragon"

    # workspace named per the workspace_name field
    assert ws.name == "Dragon Inc"
    assert ws.slug == "dragon-inc"
    assert ws.created_by_id == user.id

    # they're a member
    assert Workspaces.member?(ws.id, user.id)

    # the token verifies
    assert plaintext =~ ~r/^avl_[A-Za-z0-9_-]{32}$/
    assert %{user_id: uid} = Tokens.verify(plaintext)
    assert uid == user.id
  end

  test "rejects duplicate username" do
    {:ok, _} = Accounts.signup(%{"username" => "arie", "workspace_name" => "Arie's Lab"})

    assert {:error, %Ecto.Changeset{} = cs} =
             Accounts.signup(%{"username" => "arie", "workspace_name" => "Other"})

    assert "has already been taken" in (cs |> errors_on() |> Map.get(:username, []))
  end

  test "rejects bad username format" do
    assert {:error, %Ecto.Changeset{}} =
             Accounts.signup(%{"username" => "Bad Name!", "workspace_name" => "Anything"})
  end

  test "allows nil email" do
    {:ok, %{user: user}} =
      Accounts.signup(%{"username" => "noemail", "workspace_name" => "No Email Co"})

    assert is_nil(user.email)
  end

  test "without workspace_name (and no invite_code) fails with :workspace_name_required" do
    assert {:error, :workspace_name_required} =
             Accounts.signup(%{"username" => "nameless"})
  end
end
