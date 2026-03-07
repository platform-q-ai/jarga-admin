# Jarga Admin — Elixir/Phoenix Docker image
# Multi-stage build: deps → build → release

# ── Stage 1: dependencies ────────────────────────────────────────────────
FROM elixir:1.17-otp-27-alpine AS deps

RUN apk add --no-cache build-base git nodejs npm

WORKDIR /app

COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix local.rebar --force
RUN mix deps.get --only prod

# ── Stage 2: build ──────────────────────────────────────────────────────
FROM deps AS build

ENV MIX_ENV=prod

COPY . .

# Compile assets
RUN npm install --prefix assets
RUN mix assets.deploy

# Compile application
RUN mix compile

# Build release
RUN mix release

# ── Stage 3: runtime ─────────────────────────────────────────────────────
FROM alpine:3.20 AS runtime

RUN apk add --no-cache libstdc++ openssl ncurses bash

WORKDIR /app

COPY --from=build /app/_build/prod/rel/jarga_admin ./

ENV PHX_HOST=localhost
ENV PORT=4000
ENV MIX_ENV=prod

# Health check
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
  CMD wget -qO- http://localhost:${PORT}/health || exit 1

EXPOSE 4000

CMD ["/app/bin/jarga_admin", "start"]
