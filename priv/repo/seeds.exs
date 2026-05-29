# Local development seed data.
#
#   mix run priv/repo/seeds.exs
#   (also runs via `mix ecto.setup` and `mix ecto.reset`)
#
# Deterministic: three users, one workspace, three hardcoded API tokens,
# and a fixed set of markdown notes loaded from priv/repo/seed_data/.
# Idempotent: safe to re-run; existing rows are left in place.

import Ecto.Query

alias Aveline.Accounts
alias Aveline.Items
alias Aveline.Repo
alias Aveline.Tokens.ApiToken
alias Aveline.Views
alias Aveline.Workspaces

# ===== Users =====

user_specs = [
  %{
    email: "alice@local.test",
    username: "alice",
    display_name: "Alice",
    token: "avl_locseed_alice_aaaaaaaaaaaaaaaaaa"
  },
  %{
    email: "bob@local.test",
    username: "bob",
    display_name: "Bob",
    token: "avl_locseed_bob_bbbbbbbbbbbbbbbbbbbb"
  },
  %{
    email: "carol@local.test",
    username: "carol",
    display_name: "Carol",
    token: "avl_locseed_carol_cccccccccccccccccc"
  }
]

upsert_user = fn spec ->
  case Accounts.get_user_by_email(spec.email) do
    nil ->
      {:ok, u} =
        Accounts.create_user(%{
          "email" => spec.email,
          "username" => spec.username,
          "display_name" => spec.display_name
        })

      u

    u ->
      u
  end
end

users = Enum.map(user_specs, fn spec -> {spec, upsert_user.(spec)} end)
[{_, first_user} | _] = users
users_by_username = Map.new(users, fn {spec, u} -> {spec.username, u} end)

# ===== Workspace + memberships =====

workspace_slug = "local-pod"
workspace_name = "Local Pod"

workspace =
  case Workspaces.get_active_by_slug(workspace_slug) do
    nil ->
      {:ok, w} =
        Workspaces.create_workspace(%{
          "slug" => workspace_slug,
          "name" => workspace_name,
          "created_by_id" => first_user.id
        })

      w

    w ->
      w
  end

Enum.each(users, fn {_, user} ->
  {:ok, _} = Workspaces.ensure_member(workspace.id, user.id)
end)

# ===== Tokens =====

hash = fn plaintext ->
  :crypto.hash(:sha256, plaintext) |> Base.encode16(case: :lower)
end

upsert_token = fn user, plaintext ->
  h = hash.(plaintext)

  case Repo.one(from t in ApiToken, where: t.token_hash == ^h) do
    nil ->
      %ApiToken{}
      |> ApiToken.changeset(%{
        user_id: user.id,
        name: "local seed",
        token_hash: h,
        token_prefix: String.slice(plaintext, 0, 8)
      })
      |> Repo.insert!()

    existing ->
      existing
  end
end

Enum.each(users, fn {spec, user} -> upsert_token.(user, spec.token) end)

# ===== Markdown notes (from priv/repo/seed_data/*.md) =====

# Tiny frontmatter parser. Supports:
#   key: scalar       -> "scalar"
#   key: true/false   -> true / false
#   key: [a, b, c]    -> ["a", "b", "c"]
parse_frontmatter = fn raw ->
  case String.split(raw, ~r/^---\s*$/m, parts: 3) do
    ["", front, body] ->
      meta =
        front
        |> String.split("\n", trim: true)
        |> Enum.reduce(%{}, fn line, acc ->
          case String.split(line, ":", parts: 2) do
            [k, v] ->
              key = k |> String.trim() |> String.to_atom()
              val = String.trim(v)

              parsed =
                cond do
                  val == "true" -> true
                  val == "false" -> false
                  String.starts_with?(val, "[") and String.ends_with?(val, "]") ->
                    val
                    |> String.slice(1..-2//1)
                    |> String.split(",")
                    |> Enum.map(&String.trim/1)
                    |> Enum.reject(&(&1 == ""))

                  true ->
                    val
                end

              Map.put(acc, key, parsed)

            _ ->
              acc
          end
        end)

      {meta, String.trim_leading(body, "\n")}

    _ ->
      raise "Bad frontmatter in seed file"
  end
end

seed_dir = Path.join([:code.priv_dir(:aveline), "repo", "seed_data"])

note_files =
  seed_dir
  |> File.ls!()
  |> Enum.filter(&String.ends_with?(&1, ".md"))
  |> Enum.sort()

upsert_item = fn meta, body ->
  owner = Map.fetch!(users_by_username, meta.owner)

  case Items.get_by_slug(workspace.id, meta.slug) do
    nil ->
      attrs = %{
        "workspace_id" => workspace.id,
        "owner_id" => owner.id,
        "created_by_id" => owner.id,
        "created_via" => "seed",
        "slug" => meta.slug,
        "title" => meta.title,
        "body" => body,
        "summary" => Map.get(meta, :summary),
        "tags" => Map.get(meta, :tags, []),
        "pinned" => Map.get(meta, :pinned, false)
      }

      {:ok, item} = Items.create_item(attrs)
      item

    existing ->
      existing
  end
end

Enum.each(note_files, fn name ->
  path = Path.join(seed_dir, name)
  {meta, body} = path |> File.read!() |> parse_frontmatter.()
  upsert_item.(meta, body)
end)

# ===== Views =====

# Views are owned by different users so logging in as bob/alice shows
# attribution variety. carol is left empty on purpose — she's our "new
# account" for testing the freshly-joined-member experience.
# Team views are canonical — visible to every workspace member.
# Personal views belong only to their creator — invisible to others.
# carol is deliberately empty so we can see the freshly-joined-member UI.
view_specs = [
  %{slug: "onboarding", name: "Onboarding", tag_filter: ["onboarding"],
    description: "Everything a new teammate should read first.",
    created_by: "alice", scope: "team"},
  %{slug: "runbook", name: "Runbooks", tag_filter: ["runbook"],
    description: "Operational playbooks — read when something is on fire.",
    created_by: "bob", scope: "team"},
  %{slug: "architecture", name: "Architecture", tag_filter: ["architecture"],
    description: "How the system is shaped and why.",
    created_by: "alice", scope: "team"},

  # alice's personal scratch
  %{slug: "alice-stack-deep-dive", name: "Stack deep dive",
    tag_filter: ["stack"],
    description: "What I'm rereading while planning the v0.1 schema.",
    created_by: "alice", scope: "personal"},

  # bob's personal scratch
  %{slug: "bob-ops-followups", name: "Ops follow-ups",
    tag_filter: ["runbook", "deploys"],
    description: "Bob's runbook bookmarks — not yet team-canonical.",
    created_by: "bob", scope: "personal"}
]

Enum.each(view_specs, fn spec ->
  case Views.get_active_by_slug(workspace.id, spec.slug) do
    nil ->
      creator = Map.fetch!(users_by_username, spec.created_by)

      {:ok, _} =
        Views.create_view(%{
          "workspace_id" => workspace.id,
          "created_by_id" => creator.id,
          "slug" => spec.slug,
          "name" => spec.name,
          "tag_filter" => spec.tag_filter,
          "description" => spec.description,
          "scope" => spec.scope
        })

    _ ->
      :ok
  end
end)

# ===== Summary =====

IO.puts("")
IO.puts("=== Local seed complete ===")
IO.puts("Workspace: #{workspace.slug} (#{workspace.name})")
IO.puts("")
IO.puts("Users + tokens:")

Enum.each(users, fn {spec, _} ->
  IO.puts("  #{String.pad_trailing(spec.username, 6)} #{spec.token}")
end)

IO.puts("")
IO.puts("Seeded #{length(note_files)} notes and #{length(view_specs)} views.")
IO.puts("")
