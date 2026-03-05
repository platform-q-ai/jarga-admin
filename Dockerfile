# ── Build stage ──────────────────────────────────────────────────────────────
FROM hexpm/elixir:1.19.1-erlang-28.1.1-alpine-3.21.0 AS build

RUN apk add --no-cache build-base git curl nodejs npm

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build env
ENV MIX_ENV=prod

# Fetch dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

# Copy config (needed for compile)
COPY config config

# Compile dependencies
RUN mix deps.compile

# Build assets
COPY assets assets
COPY priv priv
RUN mix assets.deploy

# Copy source and compile
COPY lib lib
RUN mix compile

# Build release
RUN mix phx.digest
RUN mix release

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM alpine:3.21.0 AS app

RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app

# Copy release from build stage
COPY --from=build /app/_build/prod/rel/jarga_admin ./

ENV HOME=/app

EXPOSE 4000

CMD ["/app/bin/jarga_admin", "start"]
