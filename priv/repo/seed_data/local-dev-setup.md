---
title: Local dev setup
slug: local-dev-setup
owner: alice
pinned: true
tags: [onboarding, dev]
summary: Get the backend, API, and CLI talking on your laptop.
---

# Local dev setup

## Prereqs

- Erlang/OTP 27+
- Elixir 1.18+
- Postgres 15+
- Go 1.22+ (for the CLI)

`asdf` or `mise` both work for the BEAM toolchain.

## Backend

```sh
git clone git@github.com:aveline-ai/aveline.git
cd aveline
mix deps.get
mix ecto.setup       # creates DB, migrates, runs priv/repo/seeds.exs
mix phx.server
```

The seed task prints three local tokens (alice / bob / carol). Copy any one.

## CLI

```sh
cd ../cli
make build           # produces ./bin/aveline
mkdir -p ~/.config/aveline
cat > ~/.config/aveline/config.toml <<EOF
api_url = "http://localhost:4000"
token = "avl_locseed_alice_aaaaaaaaaaaaaaaaaa"
workspace = "local-pod"
EOF
chmod 600 ~/.config/aveline/config.toml
./bin/aveline whoami
```

You should see Alice and the `local-pod` workspace.

## Try it

```sh
aveline list --pinned
aveline get stack-overview
aveline view list
aveline view get onboarding
```
