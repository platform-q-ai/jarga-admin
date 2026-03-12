# Storefront Architecture

An agent-programmable, data-driven storefront where the entire customer-facing
frontend is defined by JSON page specs served from the Commerce API. No
templates with baked-in product names, no static category pages, no hand-wired
layouts — every page is a structured document that Phoenix renders at runtime.

---

## How It Works

1. An AI agent (or human) writes a JSON page spec and sends it to the
   Commerce API via `POST /v1/frontend/pages` or `PATCH /v1/frontend/page-drafts/:id`
2. The Phoenix app fetches that spec on each request and renders it into a
   live, interactive storefront page
3. Every page — home, category, PDP — is a different JSON document with the
   same component vocabulary

The storefront is **reproducible**: wipe `frontend_pages` and the theme slot,
then recreate an identical (or completely different) store with three API calls.

---

## Layer-by-Layer

### 1. Commerce API (Rust, port 8080)

The backend exposes these Frontend API endpoints (wrapped by `JargaAdmin.Api`):

| Endpoint | Purpose |
|----------|---------|
| `POST /v1/frontend/bootstrap` | Seed entire site in one call (pages + nav) |
| `POST /v1/frontend/pages` | Create a page draft |
| `PATCH /v1/frontend/page-drafts/:id` | Update draft content, `seo_title`, `meta_description` |
| `POST /v1/frontend/page-drafts/:id/publish` | Publish a draft — makes it live |
| `GET /v1/frontend/pages/:slug` | Fetch published page content |
| `PUT /v1/frontend/navigation` | Set site navigation links |
| `GET /v1/frontend/navigation` | Fetch navigation |
| `GET /v1/frontend/slots/:key` | Fetch named content slots (e.g. theme tokens) |

Each page is stored in the `frontend_pages` table with these columns:

```
id, slug, title, content_json, status, version, seo_title, meta_description,
created_at, updated_at
```

The `content_json` column holds the page spec as a JSON string.

### 2. Page Spec Format

Every page is a JSON object with a `layout` and a list of typed `components`:

```json
{
  "layout": "storefront",
  "components": [
    {"type": "announcement_bar", "data": {"message": "FREE SHIPPING OVER £50"}},
    {"type": "editorial_hero", "data": {
      "image_url": "/images/hero.jpg",
      "title": "WINTER COLLECTION",
      "subtitle": "Warmth meets elegance",
      "cta": {"label": "SHOP NOW", "href": "/store/bedroom"}
    }},
    {"type": "product_grid", "data": {
      "title": "BEST SELLERS",
      "columns": 3,
      "products": [
        {"id": "p1", "name": "Linen Duvet", "price": "£89.00",
         "image_url": "/images/duvet.jpg", "href": "/store/products/duvet",
         "colours": [{"name": "Natural", "hex": "#c4b5a0"}]}
      ]
    }},
    {"type": "text_block", "data": {
      "title": "OUR PHILOSOPHY",
      "content": "We believe the home should be a sanctuary."
    }}
  ]
}
```

#### Supported Component Types

| Component | Purpose | Key Data Fields |
|-----------|---------|-----------------|
| `announcement_bar` | Top banner (shipping, promos) | `message`, `href` |
| `editorial_hero` | Full-width hero image with title/CTA | `image_url`, `title`, `subtitle`, `cta` |
| `editorial_split` | Two-column category cards | `left`, `right` (each: `image_url`, `label`, `href`) |
| `editorial_full` | Full-width editorial band | `image_url`, `label`, `href` |
| `category_nav` | Horizontal filter/category links | `items` (array of `{label, href}`) |
| `product_scroll` | Horizontally scrolling product cards | `title`, `products` |
| `product_grid` | N-column product grid | `title`, `columns`, `products` |
| `product_detail` | PDP: gallery, variants, sizes, accordion | `name`, `price`, `images`, `description`, `colours`, `sizes`, `accordion` |
| `related_products` | "You may also like" product scroll | `title`, `products` |
| `text_block` | Centered title + paragraph | `title`, `content` |
| `nav_bar` | Navigation (rendered automatically, not in component list) | `logo`, `links` |
| `footer` | Footer (rendered automatically, not in component list) | `columns`, `copyright` |

Products in `product_scroll`, `product_grid`, and `related_products` share this shape:

```json
{
  "id": "p1",
  "name": "Linen Duvet Cover",
  "price": "£89.00",
  "image_url": "/images/duvet.jpg",
  "href": "/store/products/linen-duvet",
  "featured": false,
  "colours": [{"name": "Natural", "hex": "#c4b5a0"}]
}
```

### 3. StorefrontRenderer (`lib/jarga_admin/storefront_renderer.ex`)

Converts the raw JSON page spec into a list of `%{type: :atom, assigns: %{...}}`
maps that the LiveView can pattern-match and render.

- Normalises product data (image URLs, colour swatches, price strings)
- Passes `source`, `limit`, `collection_id`, `category_slug` fields through
  for dynamic hydration
- Falls back to `%{type: :unknown, assigns: %{raw: ...}}` for unrecognised
  component types (rendered as empty)

### 4. StorefrontHydrator (`lib/jarga_admin/storefront_hydrator.ex`)

Page specs can reference **live data sources** instead of inline product lists:

```json
{"type": "product_grid", "data": {"source": "newest", "limit": 8}}
```

The hydrator detects components with `source` fields and fetches current
product data from the PIM API (`GET /v1/pim/products`) at render time.

| Source | API Params | Description |
|--------|-----------|-------------|
| `newest` | `sort=created_at:desc` | Latest products |
| `featured` | `featured=true` | Featured/promoted products |
| `collection` | `collection_id=...` | Products in a specific collection |
| `category` | `category=...` | Products filtered by category slug |

The hydrator normalises PIM API product format (nested `images`, `price.amount`,
`price.currency`) into the storefront product shape expected by components.

On API errors, the hydrator logs a warning and falls back to any inline
`products` array in the spec (graceful degradation).

**Note:** Hydration is currently sequential — one API call per hydratable
component. A `TODO` exists to parallelise via `Task.async_stream`.

### 5. StorefrontTheme (`lib/jarga_admin/storefront_theme.ex`)

The visual design is data-driven via a `storefront_theme` Frontend API slot
containing design tokens:

```json
{
  "fonts": {
    "heading": "Cormorant Garamond",
    "body": "Inter",
    "display": "Helvetica Neue",
    "google_fonts_url": "https://fonts.googleapis.com/css2?family=..."
  },
  "colors": {
    "primary": "#1a1a1a",
    "accent": "#000000",
    "background": "#ffffff",
    "text_primary": "#1a1a1a",
    "text_muted": "#999999",
    "border": "rgba(0,0,0,0.08)"
  },
  "layout": {
    "border_radius": "0",
    "max_width": "1440px",
    "nav_style": "light"
  },
  "branding": {
    "store_name": "JARGA",
    "logo_url": null,
    "favicon_url": null
  }
}
```

Tokens are converted to CSS custom properties (`--sf-font-heading`,
`--sf-color-primary`, etc.) and injected as an inline `style` attribute
on the `#storefront-page` wrapper. All storefront CSS references these
variables, so changing the slot changes the entire site's look.

**Caching:** Themes are cached in an ETS table (`:storefront_theme_cache`)
with a 60-second TTL and a stale-while-revalidate strategy:

- Fresh cache → return immediately
- Stale cache → return stale data, spawn background refresh (one per channel)
- Cache miss → fetch from API synchronously

**Validation:** All token values are validated before use:

- Colours must match `#hex`, `rgb()`, `rgba()`, `hsl()`, or `hsla()` patterns
- Font names are restricted to `[a-zA-Z0-9 -]` (no injection)
- URLs must start with `/` or `https://` (blocks `javascript:` / `data:`)
- Google Fonts URLs must match `https://fonts.googleapis.com/`

Invalid values fall back to defaults (Helvetica Neue, black-on-white minimal).

### 6. StorefrontLive (`lib/jarga_admin_web/live/storefront_live.ex`)

A single LiveView that renders every storefront page.

**Routing:** `/store` and `/store/*slug` (catch-all). The slug maps to a
Frontend API page. `/store` → slug `home`, `/store/bedroom` → slug `bedroom`,
`/store/products/linen-duvet` → slug `products/linen-duvet`.

**Mount sequence:**

1. Resolve slug from URL params
2. Read channel handle from session (set by `ChannelResolver` plug)
3. **Parallel fetch** page content, navigation, and theme via `Task.async`
4. Parse `content_json` into component list via `StorefrontRenderer`
5. Apply theme CSS vars, Google Fonts URL, store name
6. Set SEO assigns (`meta_description`, `og_title`, `og_description`) from
   the page's `seo_title` / `meta_description` API fields, with
   `content_json.seo` as an override layer

**Interactive features** (all handled via LiveView events, no inline scripts):

| Feature | Events | Description |
|---------|--------|-------------|
| Search overlay | `toggle_search`, `close_search`, `search` | Full-screen search, async PIM API query via `Task.async`, 300ms `phx-debounce` |
| Cart drawer | `toggle_cart`, `add_to_cart`, `remove_from_cart` | Slide-out basket, client-side state, count badge |
| Filter drawer | `toggle_filters`, `close_filters`, `clear_filters` | Slide-out category filter panel |
| Gallery zoom | `open_gallery_zoom`, `close_gallery_zoom`, `gallery_prev`, `gallery_next` | Full-screen PDP image viewer |
| Mobile menu | `toggle_mobile_menu` | Hamburger menu for mobile viewports |
| Preview mode | `?preview=true` query param | Amber banner, `noindex` meta tag |
| Newsletter | `newsletter_subscribe` | Placeholder for future implementation |

**JS hooks** (`assets/js/storefront_hooks.js`): Only two hooks are used:

- `StorefrontNav` — hides/shows nav bar on scroll direction
- `ImageHoverSwap` — product card image swap on hover

All other interactivity is pure LiveView server-side events.

**What is not data-driven (hardcoded in the module):**

- Footer columns and copyright text (`@footer_columns` module attribute)
- The list of supported component types in `render_component/1`
- Cart state management (client-side, session-scoped)
- The storefront layout template (`layouts/storefront.html.heex`)

### 7. ChannelResolver (`lib/jarga_admin_web/plugs/channel_resolver.ex`)

A Plug that resolves the current sales channel from the request, enabling
multiple branded storefronts from a single Phoenix deployment.

Three strategies:

| Strategy | Resolution | Example |
|----------|-----------|---------|
| `:single` (default) | Always uses the configured default channel | All requests → `online-store` |
| `:hostname` | Maps request hostname to a channel via config map | `wholesale.example.com` → `b2b-portal` |
| `:path_prefix` | Uses the first path segment as the channel handle | `/store/uk/...` → `uk` |

Configuration:

```elixir
config :jarga_admin,
  channel_strategy: :hostname,
  channel_hostnames: %{
    "shop.example.com" => "online-store",
    "wholesale.example.com" => "b2b-portal"
  },
  default_channel: "online-store"
```

The resolved channel handle is sanitised (`[a-zA-Z0-9-]`, max 64 chars) and
stored in `conn.assigns.channel_handle`. It flows through to the LiveView
session and is used by `StorefrontTheme.load/1` to load channel-scoped themes
(slot key: `storefront_theme--{channel}`).

### 8. SEO

Page-level SEO fields are stored in the database and returned by the API:

- `seo_title` → used for `og:title` (and page title if no `content_json.seo.title`)
- `meta_description` → used for `<meta name="description">` and `og:description`

An additional `seo` object inside `content_json` can override these:

```json
{
  "seo": {
    "title": "Custom OG Title",
    "description": "Custom meta description",
    "og_image": "https://...",
    "canonical": "https://..."
  }
}
```

Priority: `content_json.seo` fields → page-level `seo_title` / `meta_description` → page `title`.

All URL values (`og_image`, `canonical`) are validated to start with `/` or
`https://` to prevent injection.

---

## Reproducibility

The entire demo store can be recreated from scratch with:

1. **One `POST /v1/frontend/bootstrap` call** — creates all pages (home,
   bedroom, kitchen, bathroom, fragrances, PDPs) and navigation in a single
   request
2. **One `PUT /v1/frontend/slots/storefront_theme` call** — sets design
   tokens (fonts, colours, layout, branding)
3. **Copy product images** to `priv/static/images/products/` (or reference
   external URLs in the page specs)
4. **Per-page `PATCH` calls** for `seo_title` / `meta_description` (these
   fields are not part of the bootstrap payload — they require individual
   page-draft updates)

Swap the JSON for a fashion brand, a bookshop, a wine merchant — the rendering
engine doesn't care. It reads the spec and renders components.

---

## File Map

```
lib/
  jarga_admin/
    api.ex                          # HTTP client — wraps all Commerce API endpoints
    storefront_renderer.ex          # JSON page spec → component assigns
    storefront_hydrator.ex          # Live data source resolution (PIM API)
    storefront_theme.ex             # Theme tokens: parse, validate, cache, CSS vars
  jarga_admin_web/
    plugs/channel_resolver.ex       # Multi-channel resolution plug
    live/storefront_live.ex         # Single LiveView for all storefront pages
    components/
      storefront_components.ex      # All storefront HEEx component functions
      layouts/storefront.html.heex  # Minimal storefront layout (just @inner_content)
assets/
  js/storefront_hooks.js            # Two JS hooks: nav scroll, image hover
  css/storefront.css                # All storefront CSS (uses --sf-* custom properties)

test/
  jarga_admin/
    storefront_renderer_test.exs    # 17 tests — component normalisation
    storefront_hydrator_test.exs    # 7 tests — source detection, API params, hydration
    storefront_theme_test.exs       # 33 tests — parse, validate, CSS vars, cache
  jarga_admin_web/
    live/storefront_live_test.exs   # 29 tests — page load, search, cart, preview, SEO
    plugs/channel_resolver_test.exs # 13 tests — all 3 strategies, sanitisation
```

**99 storefront-specific tests** across these files.

---

## Adding Components

See **[COMPONENT_SPEC.md](./COMPONENT_SPEC.md)** for the full specification:
how to add new component types, the 5-file touchpoint pattern, security
checklist, naming conventions, and the complete catalogue of existing components.

---

## Limitations and Known TODOs

- **Footer is hardcoded** — `@footer_columns` is a module attribute, not loaded
  from the API. Could be moved to a Frontend API slot or included in the
  bootstrap payload.
- **Hydration is sequential** — each hydratable component makes one API call.
  Should be parallelised with `Task.async_stream` for pages with multiple
  dynamic grids.
- **Cart is client-side only** — items are stored in LiveView assigns (lost on
  page reload). Not wired to the Basket API for persistence.
- **No per-channel page scoping** — the `ChannelResolver` sets the channel
  handle, but the page fetch doesn't yet filter by channel. Theme scoping works.
- **SEO fields require separate PATCH** — `seo_title` and `meta_description`
  are not included in the bootstrap payload; they need per-page draft updates
  after creation.
