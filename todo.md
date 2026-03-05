# Jarga Admin — Wiring TODO

## Goal
Replace all mock data and mock bridges with real connections to the Jarga Commerce
Rust backend (Postgres-backed), then introduce the Quecto agent harness.

---

## Context

### Infrastructure
- Postgres running at `localhost:5432`, db `jarga_dev`, credentials `jarga/jarga`
- 44/44 migrations now applied (ran 018–044 just now)
- Zero data in any table — needs seeding
- Jarga Commerce Rust backend at `~/Documents/github/jarga-commerce/platform`
  - Builds clean: `cargo build --bin commerce-api`
  - Postgres mode: set `DATABASE_URL` env var
  - Auth: `JARGA_BOOTSTRAP_KEY=dev` bypasses API key enforcement for local dev
  - Runs on port 8080
- Quecto binary installed at `~/.cargo/bin/quecto`
  - RPC mode: `quecto agent --mode rpc` — JSON-lines protocol over stdin/stdout
  - Config at `~/.quecto/config.json` (Telegram token present, no LLM API keys set yet)

### Jarga Admin current state (`~/Documents/github/jarga-admin`)
- `lib/jarga_admin/mock_data.ex` — 679 lines of hardcoded products/orders/customers/promotions — **DELETE**
- `lib/jarga_admin/quecto/mock_bridge.ex` — 503 lines of fake AI responses — **DELETE**
- `lib/jarga_admin/tab_store.ex` — seeds default tabs from MockData — **REWRITE**
- `lib/jarga_admin/api.ex` — HTTP client already written, never called by UI — **USE THIS**
- Tests reference MockData and MockBridge — need updating

### Key API endpoints (all at `http://localhost:8080`)
- `GET  /v1/agent/context?sections=store,products,orders,promotions,metrics,inventory`
- `GET  /v1/pim/products`
- `POST /v1/pim/products` + variants
- `GET  /v1/oms/orders`
- `GET  /v1/crm/customers`
- `GET  /v1/promotions/campaigns`
- `GET  /v1/inventory/levels`
- `GET  /v1/analytics/sales`
- Auth header: `Authorization: Bearer dev` (bootstrap key bypass)

### Quecto RPC protocol (stdin/stdout JSON-lines)
```
# Send:
{"type":"prompt","id":"msg-1","message":"Show me all orders"}

# Receive (stream of events):
{"type":"agent_start"}
{"type":"turn_start"}
{"type":"text_delta","text":"Here are your orders..."}
{"type":"tool_execution_start","tool_call_id":"...","tool_name":"bash","args":{}}
{"type":"tool_execution_end","tool_call_id":"...","tool_name":"bash","result":{}}
{"type":"agent_end","messages":[...]}
```

---

## Steps

### Phase 1 — Backend up with real data

- [ ] **1. Start the Rust backend**
  ```bash
  cd ~/Documents/github/jarga-commerce/platform
  DATABASE_URL="postgres://jarga:jarga@localhost:5432/jarga_dev" \
  JARGA_BOOTSTRAP_KEY="dev" \
  cargo run -p commerce-api
  ```
  Verify: `curl http://localhost:8080/v1/pim/products -H "Authorization: Bearer dev"`

- [ ] **2. Write the seed Mix task** (`lib/mix/tasks/jarga.seed.ex`)
  Call the live API (not direct SQL) so seed exercises the real endpoints:
  - 12 products (artisan goods, matching current MockData theme) each with 2–3 variants
  - Inventory levels for each variant (via `POST /v1/inventory/levels/set` or equivalent)
  - 15 orders across statuses: paid, pending, partially_refunded, fulfilled
  - 8 customers with addresses and tags
  - 3 promotion campaigns (percentage, fixed, free shipping) with coupons
  - 2 shipping zones (UK, EU) with rates
  - Run: `mix jarga.seed`

- [ ] **3. Delete mock files**
  - `lib/jarga_admin/mock_data.ex` — delete entirely
  - `lib/jarga_admin/quecto/mock_bridge.ex` — delete entirely

- [ ] **4. Update `api.ex`**
  - Default `JARGA_API_URL` → `http://localhost:8080` (was `localhost:3000`)
  - Auth: use `Authorization: Bearer <JARGA_API_KEY>` (bearer, not HMAC) — the Rust
    backend expects a plain bearer token, not HMAC signatures
  - Remove HMAC signing (`build_headers/3`) — replace with simple bearer header
  - Add `JARGA_API_KEY` defaulting to `"dev"` for local bootstrap key

- [ ] **5. Rewrite `tab_store.ex` `seed_defaults/0`**
  - Call `Api.list_products/0`, `Api.list_orders/0`, `Api.list_customers/0`,
    `Api.get_analytics/0` via the live API
  - Map real response shapes to UI specs (products → product_grid, orders → data_table, etc.)
  - Remove all `MockData` references
  - Keep `reset_to_defaults/0` for tests — but have it call the API or use a
    test-mode flag that inserts minimal fixture data via the API

- [ ] **6. Update tests**
  - Remove all `MockData` module references
  - `chat_live_test` — seed minimal data via API before each test (or use a
    shared `setup` that calls `mix jarga.seed --minimal`)
  - Ensure `mix test` still passes at 51+

### Phase 2 — Quecto agent bridge

- [ ] **7. Set LLM API key in Quecto config**
  ```bash
  quecto auth login --provider anthropic --token sk-ant-...
  # or
  quecto auth login --provider openai --token sk-proj-...
  ```

- [ ] **8. Write a Jarga skill for Quecto** (`~/.quecto/skills/jarga-commerce.md`)
  System prompt that tells the agent:
  - It is a Jarga Commerce admin assistant
  - Available API endpoints (summary of SETUP-APIS.md)
  - How to call `GET /v1/agent/context` first to understand store state
  - How to embed UI specs in ` ```json ``` ` fences in responses
  - Component types available: data_table, stat_bar, product_grid, order_detail, etc.

- [ ] **9. Replace `MockBridge` with real `Bridge`** (`lib/jarga_admin/quecto/bridge.ex`)
  - Spawn `quecto agent --mode rpc --system <skill_content>` as an Elixir `Port`
  - One port per session (supervised under `DynamicSupervisor`)
  - Send: write JSON-line to port stdin
  - Receive: parse JSON-line events from port stdout
  - Map events to PubSub broadcasts:
    - `text_delta` → `broadcast "quecto:<session>:response", {:chunk, text}`
    - `agent_end`  → `broadcast "quecto:<session>:response", :done`
    - Parse ` ```json ``` ` fences from final text → `broadcast "quecto:<session>:ui_spec"`
  - Error handling: port crash → restart, notify user

- [ ] **10. Wire agent context into Quecto prompts**
  - Before each user message, call `Api.agent_context/0`
  - Prepend context snapshot to the prompt so the agent knows current store state
  - Or: give Quecto a `jarga_api` bash tool that can call the API directly

- [ ] **11. Final test pass**
  - `mix test` — all passing
  - `mix format --check-formatted`
  - Manual smoke test: start backend, seed, start admin, chat "show me orders"

---

## File map

| File | Action |
|---|---|
| `lib/jarga_admin/mock_data.ex` | DELETE |
| `lib/jarga_admin/quecto/mock_bridge.ex` | DELETE |
| `lib/jarga_admin/api.ex` | UPDATE (bearer auth, port 8080) |
| `lib/jarga_admin/tab_store.ex` | REWRITE (call Api.*) |
| `lib/jarga_admin/quecto/bridge.ex` | REWRITE (real Port-based bridge) |
| `lib/mix/tasks/jarga.seed.ex` | CREATE |
| `~/.quecto/skills/jarga-commerce.md` | CREATE |
| `test/jarga_admin_web/live/chat_live_test.exs` | UPDATE |
| `test/jarga_admin/tab_store_test.exs` | UPDATE |

## Notes
- Keep `UiSpec`, `Renderer`, and all components untouched — they are mock-agnostic
- The Rust API response shape is `{"data": {...}, "error": null, "meta": {...}}`
  — `api.ex` needs to unwrap `["data"]` from responses
- Migrations 18–44 are now applied; the DB has auth_api_keys, audit_log,
  shipping, tax, markets, channels, subscriptions, flows, metaobjects,
  promotions_v2 tables — seed should populate the ones the admin UI shows
- `JARGA_BOOTSTRAP_KEY=dev` means any `Authorization: Bearer dev` request is
  accepted without a real key record in the DB

---

## Chores (found during Phase 1 seed work)

These are bugs/gaps in `jarga-commerce` platform discovered while wiring up the seed.
File issues and fix in the platform repo.

- [ ] **Schema type mismatch — `pim_variants.position` and `weight`** (jargacommerce#170)
  Migration `0011_pim_variant_inventory_policy_position.sql` adds `position` as
  `integer` (INT4) but the Rust code maps it as `i64` (INT8). Same for `weight`.
  Also affects `inventory_qty`. Workaround applied manually in dev DB:
  `ALTER TABLE pim_variants ALTER COLUMN position TYPE bigint` etc.
  Fix: change the migration to use `bigint` for these columns, or add an
  `ALTER COLUMN … TYPE bigint` in a new migration (e.g. `0045_fix_variant_column_types.sql`).

- [ ] **Schema type mismatch — `shipping_rates` integer columns** (jargacommerce#171)
  `estimated_days_min`, `estimated_days_max`, `min_weight_g`, `max_weight_g`,
  `position` are all `integer` (INT4) but the Rust shipping repo maps them as
  `i64`. Same pattern as variants. Fix with a migration.

- [ ] **Schema type mismatch — `inventory_reservations.quantity` and `inventory_transfer_line_items` columns** (jargacommerce#172)
  Same INT4 vs INT8 issue. Fix with a migration.

- [ ] **Draft orders not implemented in Postgres backend** (jargacommerce#175)
  `pg_oms_crm_frontend.rs` `create_draft()` returns `Err(OmsRepoError::Internal)` —
  it's a stub. The entire draft-order API (`POST /v1/oms/draft-orders`,
  `POST /v1/oms/draft-orders/:id/complete` etc.) is therefore broken against
  Postgres. The seed task works around this by inserting orders directly via SQL.
  Fix: implement `create_draft` / `complete_draft` / `get_draft` / `update_draft`
  in `pg_oms_crm_frontend.rs` using proper SQL (similar to how `create_checkout_order`
  is implemented).

- [ ] **Promotion `discount_type` — no `free_shipping` variant** (jargacommerce#176)
  `parse_discount_type()` in `types_promotions.rs` only accepts `"percentage"`,
  `"fixed_amount"`, and `"buy_x_get_y"`. There is no free-shipping discount type.
  A free-shipping promotion is best modelled as a shipping-rate override or a
  campaign flag. Either add `FreeShipping` to `DiscountType` enum, or document
  that free shipping is handled separately via shipping zone rules.

- [ ] **Shipping `rate_type` enum value mismatch with API usage guide** (jargacommerce#177)
  The API guide examples use `"flat"` but the actual accepted value is `"flat_rate"`.
  `SETUP-APIS.md` and `API-USAGE-GUIDE.md` should be corrected to use `"flat_rate"`,
  `"weight_based"`, `"price_based"`, `"free"`.

- [ ] **Backend crashes / returns empty response on first request after idle** (jargacommerce#178)
  The Rust backend (axum/hyper) closes keep-alive connections after a timeout and
  returns an empty response (`reason: :closed`) to the next client that tries to
  reuse a stale connection. The Elixir `Req` client needs `retry: :transient` or
  the seed task needs to send a warm-up request first. The backend itself should
  return a proper `Connection: close` header or configure idle timeout appropriately.
  Workaround: seed task retries on `:closed` up to 3 times with 300ms delay.

- [x] **Bug: `oms_refunds` query missing `order_id` in SELECT** (`pg_oms_crm_frontend.rs` line ~93) (jargacommerce#173)
  Query selects `id, amount, reason` but mapping code calls `r.get("order_id")` → `ColumnNotFound` panic.
  Fixed locally. Needs PR to platform repo.

- [x] **Bug: `get_order` hardcodes `financial_status`, `fulfillment_status`, `order_number`, `email`** (`pg_oms_crm_frontend.rs`) (jargacommerce#174)
  The SELECT only fetched `id, basket_id, amount_total, currency, status` — all other fields were set to
  stub values (`Pending`, `Unfulfilled`, `1001`, `None`). Fixed locally to read all columns and parse
  enums via `parse_financial_status` / `parse_fulfillment_status` / `parse_cancel_reason`. Needs PR.

- [x] **Bug: `cancel_reason` column is a text enum in DB but `CancelReason` has no sqlx `Decode` impl**
  Fixed by reading as `Option<String>` and mapping through `parse_cancel_reason`. Needs PR.

- [ ] **`oms_order_number_seq` not reset between seed runs via API**
  The sequence auto-increments and is only reset in the seed's SQL reset step.
  If the reset step is skipped (`--no-reset`), order numbers continue from where
  they left off rather than restarting at 1001. This is acceptable for now but
  could cause confusion in demo mode. Consider a dedicated reset endpoint or
  document the behaviour.
