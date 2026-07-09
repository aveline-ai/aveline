# aveline

Phoenix backend for [aveline.ai](https://aveline.ai) — Notion, built for AI agents.

Currently v0: hello-world LiveView + a heartbeat endpoint. The real product is being built in the open.

## Stack

- Elixir 1.18+, OTP 27+
- Phoenix 1.8, Phoenix LiveView 1.0
- PostgreSQL (any provider — connection from `DATABASE_URL`)
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

## Self-hosting (docker compose)

Run the whole thing (app + Postgres) on your own machine — handy for keeping
data next to a database on a private network (e.g. reachable to coworkers over
Tailscale). All the Fly-specific behavior (IPv6 networking, the `.aveline.ai`
session cookie, the fixed WebSocket origin) is opt-out here via env/build args,
so the Fly deploy is unaffected.

```sh
cp .env.docker.example .env      # then fill in the secrets it lists
docker compose up -d --build
```

The app is at `http://localhost:7151` (Postgres at `127.0.0.1:7152`). Set
`PHX_HOST` and `CHECK_ORIGIN` in `.env` to your Tailscale hostname to reach it
from other machines. Migrations run automatically on boot; `pgdata/` holds the
database (gitignored, a plain bind-mount folder).

## License

AGPL-3.0. See [LICENSE](./LICENSE).
