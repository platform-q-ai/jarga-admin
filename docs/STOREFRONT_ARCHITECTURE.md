# Storefront Architecture

An agent-programmable, data-driven storefront where the entire customer-facing
frontend is defined by JSON page specs served from the Commerce API. No
templates with baked-in product names, no static category pages, no hand-wired
layouts — every page is a structured document that Phoenix renders at runtime.

> **For agents**: See **[AGENT_API_GUIDE.md](./AGENT_API_GUIDE.md)** for the
> complete HTTP API reference — how to create products, build pages, set themes,
> and configure display overrides, all via API calls.

---

## How It Works

1. Products are created in the **PIM** (`POST /v1/pim/products`) — titles,
   prices, categories, stock. This is the single source of truth.
2. Page layouts are defined as **JSON page specs** (`POST /v1/frontend/bootstrap`)
   — hero images, grids, text blocks, display overrides. No product data here.
3. At render time, the **StorefrontHydrator** fetches live product data from
   the PIM and merges it with display overrides from the page spec.
4. The Phoenix LiveView renders the result into an interactive storefront page.

The storefront is **reproducible**: wipe `frontend_pages` and the theme slot,
then recreate an identical (or completely different) store with API calls.

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
      "title": "KINTO",
      "subtitle": "Thoughtful design for everyday life",
      "cta": {"label": "SHOP COFFEE", "href": "/store/coffee"}
    }},
    {"type": "product_grid", "data": {
      "title": "BEST SELLERS",
      "columns": 4,
      "source": "category",
      "category_id": "cat_0000000000000001",
      "limit": 200,
      "display_overrides": {
        "scs-coffee-carafe-set-4cups": {
          "span": 3, "card_height": "flush", "position": 5,
          "images": [
            {"url": "/images/kinto/scs-coffee-carafe-set-4cups_coffee_shop.jpg", "span": 2},
            {"url": "/images/kinto/scs-coffee-carafe-set-4cups_angle.jpg", "span": 1}
          ]
        }
      }
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

Product cards in `product_scroll`, `product_grid`, and `related_products` are
hydrated from the PIM at render time. The card shape after hydration:

```json
{
  "id": "prod_oct_brewer_2cups",
  "name": "OCT Brewer 2cups",
  "price": "£25.50",
  "price_cents": 2550,
  "image_url": "/images/kinto/oct-brewer-2cups_angle.jpg",
  "hover_image_url": "/images/kinto/oct-brewer-2cups_coffee_shop.jpg",
  "href": "/store/products/oct-brewer-2cups",
  "collection": "SLOW COFFEE STYLE",
  "material": "Borosilicate glass",
  "tags": ["SLOW COFFEE STYLE", "Glass"]
}
```

> **Never put product data in page specs.** Product grids declare `source` +
> `category_id` and the hydrator fetches from PIM. See [PIM_HYDRATION.md](./PIM_HYDRATION.md).

### 3. StorefrontRenderer (`lib/jarga_admin/storefront_renderer.ex`)

Converts the raw JSON page spec into a list of `%{type: :atom, assigns: %{...}}`
maps that the LiveView can pattern-match and render.

- Normalises product data (image URLs, colour swatches, price strings)
- Passes `source`, `limit`, `collection_id`, `category_slug` fields through
  for dynamic hydration
- Falls back to `%{type: :unknown, assigns: %{raw: ...}}` for unrecognised
  component types (rendered as empty)

### 4. StorefrontHydrator (`lib/jarga_admin/storefront_hydrator.ex`)

All product grids use **PIM hydration** — no inline product data in page specs.

```json
{"type": "product_grid", "data": {"source": "category", "category_id": "cat_...", "columns": 4}}
```

The hydrator detects components with `source` fields and fetches current
product data from the PIM API (`GET /v1/pim/products`) at render time.

| Source | API Params | Description |
|--------|-----------|-------------|
| `category` | `category_id=cat_...` | Products in a PIM category |
| `collection` | `collection_id=...` | Products in a PIM collection |
| `newest` | `sort=created_at:desc` | Latest products |
| `featured` | `featured=true` | Featured/promoted products |

After fetching, the hydrator applies **display overrides** from the page spec —
span, card_height, images, position — to control how specific products render.

PIM product fields are mapped to storefront card format:
- `title` → `name`
- `variants[0].unit_amount` → `price`, `price_cents`
- `slug` → `href` (as `/store/products/{slug}`)
- `media` → `image_url`, `hover_image_url` (falls back to slug-based convention)

On API errors, the hydrator logs a warning and falls back to empty products.

See **[PIM_HYDRATION.md](./PIM_HYDRATION.md)** for the full technical reference
and **[AGENT_API_GUIDE.md](./AGENT_API_GUIDE.md)** for agent workflow examples.

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

**JS hooks** (`assets/js/storefront_hooks.js`):

- `StorefrontNav` — hides/shows nav bar on scroll direction
- `ImageHoverSwap` — product card image swap on hover
- `FlushCardHeight` — measures standard card height and sets `--sf-card-img-h`
  CSS variable on spanning cards so their images are flush with row neighbours

All other interactivity is pure LiveView server-side events.

**What is not data-driven (hardcoded in the module):**

- The list of supported component types in `render_component/1`
- Cart state management (client-side, session-scoped)
- The storefront layout template (`layouts/storefront.html.heex`)

**What IS data-driven (controlled via API):**

- All product data (PIM API)
- Page layouts and components (Frontend API page specs)
- Navigation links (Frontend API navigation / nav slot)
- Footer content (Frontend API footer slot)
- Theme: fonts, colours, layout, branding (Frontend API theme slot)
- Display overrides: span, card_height, images, position (page spec)
- Sort/filter options (page spec)
- SEO meta tags (page spec + page-level fields)

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

The entire store can be recreated from scratch by an agent:

1. **Seed PIM** — create categories and products with variants via
   `POST /v1/pim/categories`, `POST /v1/pim/products`,
   `POST /v1/pim/products/:id/variants`, `POST /v1/pim/products/:id/publish`
2. **Bootstrap pages** — `POST /v1/frontend/bootstrap` creates all pages
   (home, PLPs, PDPs) in a single call. Page specs reference PIM categories
   via `source: "category"` + `category_id` — no product data in the spec.
3. **Set theme** — `PUT /v1/frontend/slots/storefront_theme` sets design
   tokens (fonts, colours, layout, branding)
4. **Set navigation** — `PUT /v1/frontend/navigation` or via the
   `storefront_nav` slot

The entire store — products, categories, pages, theme, navigation — can be
built by an agent making HTTP calls. Swap the API calls for a fashion brand,
a bookshop, a wine merchant — the rendering engine doesn't care.

---

## File Map

```
lib/
  jarga_admin/
    api.ex                          # HTTP client — wraps all Commerce API endpoints
    storefront_renderer.ex          # JSON page spec → component assigns + display override normalization
    storefront_hydrator.ex          # PIM data fetch + display override application
    storefront_theme.ex             # Theme tokens: parse, validate, cache, CSS vars
    storefront_search.ex            # Full-text PIM search
    storefront_nav.ex               # Navigation menu builder
    storefront_analytics.ex         # Event tracking
    media_upload.ex                 # Staged upload pipeline
    page_registry.ex                # Page ordering & sitemap
    style_validator.ex              # Inline style sanitisation
  jarga_admin_web/
    plugs/channel_resolver.ex       # Multi-channel resolution plug
    live/storefront_live.ex         # Single LiveView for all storefront pages
    components/
      storefront_components.ex      # All storefront HEEx component functions (17+ types)
      layouts/storefront.html.heex  # Minimal storefront layout (just @inner_content)
    controllers/
      sitemap_controller.ex         # XML sitemap generation
assets/
  js/storefront_hooks.js            # JS hooks: nav scroll, image hover, flush card height
  css/storefront.css                # All storefront CSS (uses --sf-* custom properties)

docs/
  AGENT_API_GUIDE.md                # ★ Complete agent HTTP API reference
  PIM_HYDRATION.md                  # Technical hydration pipeline details
  STOREFRONT_ARCHITECTURE.md        # System architecture overview
  COMPONENT_SPEC.md                 # How to add new component types
```

---

## Adding Components

See **[COMPONENT_SPEC.md](./COMPONENT_SPEC.md)** for the developer specification:
how to add new component types, the 5-file touchpoint pattern, security
checklist, naming conventions, and the complete catalogue of existing components.

Once a component type is implemented, agents use it by including it in
page specs via the API — see **[AGENT_API_GUIDE.md](./AGENT_API_GUIDE.md)**.

---

## Limitations and Known TODOs

- **Cart is client-side only** — items are stored in LiveView assigns (lost on
  page reload). Not wired to the Basket API for persistence.
- **No per-channel page scoping** — the `ChannelResolver` sets the channel
  handle, but the page fetch doesn't yet filter by channel. Theme scoping works.
- **PIM media not wired** — product images use slug-based convention
  (`/images/kinto/{slug}_angle.jpg`) rather than PIM media records. The
  `StorefrontHydrator` supports PIM media but no products have media attached yet.

---

## PIM Integration

The storefront uses the PIM as the **single source of truth** for all product
data. Page specs never contain product data — they reference PIM categories,
and the `StorefrontHydrator` fetches live data at render time.

```
Page Spec (JSON) → StorefrontRenderer → StorefrontHydrator → StorefrontLive
                   (parse layout)       (fetch PIM data      (render HTML)
                                         + apply overrides)
```

| Concern | Where it lives | API |
|---------|---------------|-----|
| Product data (title, price, stock) | PIM | `POST /v1/pim/products` |
| Page layout (grid, hero, text) | Page spec | `POST /v1/frontend/bootstrap` |
| Display config (span, position) | Page spec `display_overrides` | `POST /v1/frontend/bootstrap` |
| Theme (fonts, colours) | Theme slot | `PUT /v1/frontend/slots/storefront_theme` |

See **[AGENT_API_GUIDE.md](./AGENT_API_GUIDE.md)** for the complete API reference.
See **[PIM_HYDRATION.md](./PIM_HYDRATION.md)** for the technical hydration details.
