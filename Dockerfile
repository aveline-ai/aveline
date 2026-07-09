# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?page=1&name=ubuntu
# https://hub.docker.com/_/ubuntu?tab=tags
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian?tab=tags&page=1&name=bullseye-20250113-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: hexpm/elixir:1.18.2-erlang-27.2.1-debian-bullseye-20250113-slim
#
ARG ELIXIR_VERSION=1.18.2
ARG OTP_VERSION=27.2.1
ARG DEBIAN_VERSION=bullseye-20250113-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} as builder

# install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git curl \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# prepare build dir
WORKDIR /app

# Install Hex + Rebar.
#
# Both `mix local.hex` and `mix local.rebar` download from
# builds.hex.pm, whose TLS certificate trips Erlang's strict validation
# as of mid-2026 (the cert claims both keyCertSign and serverAuth EKUs
# which Erlang considers a key_usage_mismatch).
#
# Hex: Mix's own error message suggests `mix archive.install github`
# which clones via git (no TLS to builds.hex.pm) and compiles locally.
#
# Rebar3: download the prebuilt escript from S3 (rebar3's official
# redirect-to-latest-stable URL) and point `mix local.rebar` at it.
#
# Once Erlang 27.3+ ships in our base image (more lenient cert
# validation), both workarounds can come out.
RUN mix archive.install github hexpm/hex branch latest --force && \
  curl -fsSL -o /tmp/rebar3 https://s3.amazonaws.com/rebar3/rebar3 && \
  chmod +x /tmp/rebar3 && \
  mix local.rebar rebar3 /tmp/rebar3 --force && \
  rm /tmp/rebar3

# set build ENV
ENV MIX_ENV="prod"

# Session cookie overrides for self-hosted builds (see config/prod.exs).
# Defaults preserve the Fly/app.aveline.ai behavior.
ARG SESSION_COOKIE_DOMAIN=".aveline.ai"
ARG SESSION_COOKIE_SECURE="true"
ENV SESSION_COOKIE_DOMAIN=$SESSION_COOKIE_DOMAIN
ENV SESSION_COOKIE_SECURE=$SESSION_COOKIE_SECURE

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv

COPY lib lib

COPY assets assets

# Build & digest static assets (esbuild → priv/static/assets/js/app.js, etc.)
RUN mix assets.deploy

# Compile the release
RUN mix compile

# Package source code for Sentry
RUN mix sentry.package_source_code

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
  apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/aveline ./

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

CMD ["/app/bin/server"]
