# Aveline

This is the API that powers Aveline.

## Development

The project is developed with [Postgres](https://www.postgresql.org/), [Elixir](https://elixir-lang.org/), and
[Phoenix](https://www.phoenixframework.org/).

### Setup

  * Install correct Elixir/Erlang versions in `.tool_versions` with `asdf install`.
  * Copy `.env.example` to `.env` and fill in environment variables. Then, `source .env` to set in shell.
  * Install dependencies with `mix deps.get`
  * Assuming you already have Postgres installed, create and migrate your database with `mix ecto.setup`.
    * Check our `config/dev.exs` to see the expected username/password for your postgres user.
  * Start Phoenix endpoint with `mix phx.server` or inside a REPL with `iex -S mix phx.server`

Now you can visit [`localhost:4000/ping`](http://localhost:4000/ping) from your browser.

### Tests

 * Run all tests with `mix test`
 * Run a specific test with `mix test test/...exs`
 * This project takes advantage of
   [elixir doctests](https://elixir-lang.org/getting-started/mix-otp/docs-tests-and-with.html#doctests) which are an
   easy way to write tests in documentation. Refer to [todo: example](https://github.com/amilner42/aveline) to see an
   example.

### Production

#### Deployment

I deploy on [fly.io](fly.io). I mostly followed the simple instructions on the
[Phoenix fly deploy guide](https://hexdocs.pm/phoenix/fly.html).

Some helpful commands:

 - `fly deploy`
 - `fly status`
 - `fly logs` (tail)

 - `fly ssh console`
   - Will require `fly ssh issue` first to get ssh certs
   - Once you have a console, `app/bin/aveline remote` to open up IEX connected to the prod instance.
   - As always `use Aveline.IexHelpers` is a helpful macro for getting all common imports.
   - From there, you have a console to prod, eg: `Repo.all User`...

#### Database

You can access the prod DB by using a fly proxy:

```bash
fly proxy 5433:5432 -a aveline-db
```

And then you can open a connection to:

* Host: 127.0.0.1
* post: 5433
* username: aveline
* database: aveline
* password: fetch by using `fly ssh console` & `echo $DATABASE_URL`.

#### Logging

TODO

#### Analytics

##### Events

TODO

##### Client

TODO

#### Email

TODO
