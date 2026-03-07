# Jarga Admin

Generative backend UI for [Jarga Commerce](https://jargacommerce.com) — built with Elixir Phoenix LiveView.

Chat with your store. Ask questions. Get AI-generated data tables, charts, and forms — all styled in the Jarga cinematic design system.

---

## Features

- **Chat interface** — real-time streaming chat with the Quecto AI agent
- **Generative UI** — agent responses auto-render as data tables, metric cards, charts, and forms
- **Pinned tabs** — save any generated view as a persistent tab with auto-refresh
- **Commerce context** — full Jarga Commerce API integration (products, orders, customers, analytics)
- **Cinematic design** — matches [jargacommerce.com/platform](https://jargacommerce.com/platform.html)

---

## Setup

### Prerequisites

- Elixir 1.19+ / Erlang/OTP 28+
- Node.js 18+ (for asset building)
- [Jarga Commerce](https://github.com/platform-q-ai/jargacommerce) running locally (optional — mock mode available)
- [Quecto](https://github.com/platform-q-ai/quecto) agent binary (optional — mock mode available)

### Install

```bash
git clone https://github.com/platform-q-ai/jarga-admin
cd jarga-admin
mix setup
```

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `JARGA_API_URL` | `http://localhost:3000` | Jarga Commerce API base URL |
| `JARGA_API_KEY` | _(empty)_ | API key for HMAC request signing |
| `QUECTO_BIN` | `quecto` | Path to quecto binary |
| `QUECTO_BASE_DIR` | _(cwd)_ | Working directory for quecto |
| `SECRET_KEY_BASE` | _(required in prod)_ | Phoenix secret key base |
| `PHX_HOST` | `localhost` | Production hostname |

### Run in development

```bash
mix phx.server
```

Visit [localhost:4000](http://localhost:4000) — you'll be redirected to the chat interface.

> **No Quecto binary?** The mock bridge kicks in automatically and simulates realistic commerce-aware responses.

### Run tests

```bash
mix test
```

### Format check

```bash
mix format --check-formatted
```

---

## Architecture

```
lib/
├── jarga_admin/
│   ├── api.ex              # Jarga Commerce HTTP client (bearer auth)
│   ├── ui_spec.ex          # UI spec parser (agent JSON → component assigns)
│   ├── renderer.ex         # UI spec → renderable component list
│   ├── tab_store.ex        # ETS-backed pinned tabs (lazy spec loading)
│   ├── tab_spec_builder.ex # Builds UI specs per tab from live API (called on first access)
│   ├── quecto/
│   │   ├── bridge.ex       # GenServer managing quecto OS process
│   │   └── mock_bridge.ex  # Dev/test mock with realistic responses
│   └── skills/             # Quecto SKILL.md files for commerce domain
│       ├── commerce_overview.md
│       ├── commerce_analytics.md
│       ├── commerce_inventory.md
│       ├── commerce_orders.md
│       ├── commerce_pricing.md
│       └── commerce_promotions.md
└── jarga_admin_web/
    ├── live/
    │   └── chat_live.ex    # Main LiveView (chat + tab bar + generated UI)
    ├── components/
    │   ├── jarga_components.ex  # DataTable, MetricCard, DetailCard, Chart…
    │   └── layouts/
    │       ├── root.html.heex
    │       └── app.html.heex
    └── router.ex
```

Tab specs are loaded lazily — `tab_store.ex` inserts tabs with `nil` specs on startup (no API calls), and `TabSpecBuilder.build_spec/1` is invoked on first access via `TabStore.get_or_build_spec/1`. This keeps application startup non-blocking even when the backend is unavailable.

---

## Design tokens

| Token | Value |
|---|---|
| Font: headings | Montserrat 700, `letter-spacing: 0.2em`, uppercase |
| Font: body | Manrope 400/500/600 |
| Font: display | Noto Serif Display 600 |
| Background: dark | `#090b0c` |
| Background: light | `#f3efea` |
| Card bg | `#f6f3ee` |
| Text: primary | `#181512` |
| Button solid | `#181512` bg → `#3a3028` hover |
| Nav | `rgba(9,11,12,0.85)` + blur(12px) |

---

## Docker

### Single container (admin only)

```bash
docker build -t jarga-admin .
docker run -p 4000:4000 \
  -e SECRET_KEY_BASE=$(mix phx.gen.secret) \
  -e JARGA_API_URL=http://your-jarga-api \
  -e JARGA_API_KEY=your-api-key \
  jarga-admin
```

### Full local stack (Postgres + Commerce API + Admin)

```bash
# 1. Point to your commerce API image
export JARGA_COMMERCE_IMAGE=jarga-commerce:latest

# 2. (Optional) pre-build from local source
#    docker build -t jarga-commerce:latest ../jarga-commerce

# 3. Start everything
docker compose up

# 4. Start with seed data
SEED=true docker compose up

# 5. Start only the admin (assumes API is already running)
JARGA_API_URL=http://localhost:8080 docker compose up admin
```

The admin panel will be available at http://localhost:4000.
The commerce API will be available at http://localhost:8080.
PostgreSQL will be available at localhost:5432 (user: jarga, password: jarga_dev_password).

### Hot reload (development)

Source code is volume-mounted into the container so Phoenix hot reload works
automatically — edit files and the browser refreshes.

### Health checks

All services expose `/health` endpoints and Docker Compose waits for them
before starting dependent services. The startup order is:
`postgres` → `api` → `admin`

---

## Issue roadmap

| Issue | Title | Status |
|---|---|---|
| #16 | Phoenix scaffold + design system | ✅ |
| #17 | Jarga API client | ✅ |
| #18 | Quecto process bridge | ✅ |
| #19 | Chat LiveView | ✅ |
| #20 | UI spec protocol + renderer | ✅ |
| #21 | DataTable component | ✅ |
| #22 | MetricCard + DetailCard components | ✅ |
| #23 | Pinned tabs | ✅ |
| #24 | Dashboard view + smart defaults | ✅ |
| #25 | Form component + write operations | ✅ |
| #26 | Quecto commerce tools (auto-gen) | 🔜 |
| #27 | Commerce skills + system prompt | ✅ |
| #28 | Activity feed + approval UI | ✅ |
| #29 | Chart component | ✅ |

---

## Licence

Same licence as Jarga Commerce — see [LICENSE](../jargacommerce/LICENSE).
