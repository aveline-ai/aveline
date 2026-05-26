# aveline

Phoenix backend for [aveline.ai](https://aveline.ai) — Notion, built for AI agents.

Currently v0: hello-world LiveView + a heartbeat endpoint. The real product is being built in the open.

## Stack

- Elixir 1.18+, OTP 27+
- Phoenix 1.8, Phoenix LiveView 1.0
- PostgreSQL (via Supabase or local)
- Oban for background jobs
- Sentry for errors + logs
- Deployed on Fly.io

## Setup

```sh
# 1. Install the correct Elixir/Erlang versions
asdf install

# 2. Copy env example, fill in DATABASE_URL (and optionally SENTRY_DSN)
cp .env.example .env
$EDITOR .env
set -a; source .env; set +a

# 3. Deps + DB
mix deps.get
mix ecto.setup

# 4. Run
iex -S mix phx.server
```

Visit:
- `http://localhost:4000` — hello-world LiveView (counter)
- `http://localhost:4000/api/heartbeat` — JSON heartbeat

## Tests

```sh
mix test
```

## Deploy

```sh
fly deploy
```

App is at `https://app.aveline.ai`.

## License

AGPL-3.0. See [LICENSE](./LICENSE).
