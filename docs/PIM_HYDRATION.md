# PIM Hydration Pipeline

> **Single source of truth**: All product data lives in the PIM (Product Information Manager).
> The storefront fetches it at render time. Page specs define **layout only** — never product data.
>
> For the full agent API workflow (creating products, pages, and themes via HTTP),
> see **[AGENT_API_GUIDE.md](./AGENT_API_GUIDE.md)**.

## Architecture

```
┌─────────────┐    ┌──────────────────┐    ┌──────────────────────┐
│  PIM API     │    │  Frontend Pages  │    │  Storefront LiveView │
│  (Products)  │    │  (Page Specs)    │    │                      │
│              │    │                  │    │  1. Load page spec   │
│  • title     │    │  • layout config │    │  2. Render spec      │
│  • price     │──▶ │  • source ref   │──▶ │  3. Hydrate from PIM │
│  • variants  │    │  • display opts  │    │  4. Render HTML      │
│  • category  │    │  • filters/sort  │    │                      │
│  • tags      │    │  • NO products!  │    └──────────────────────┘
│  • material  │    └──────────────────┘
│  • media     │
└─────────────┘
```

### Data Flow

1. **Page spec** declares a `product_grid` with `source: "category"` and `category_id`
2. **StorefrontRenderer** parses the spec into component assigns
3. **StorefrontHydrator** detects components with a `source` field and fetches live data from PIM
4. **StorefrontLive** renders the hydrated components

### Key Rule

> **Page specs MUST NOT contain inline product data.**
>
> Products are ALWAYS fetched from the PIM at render time.
> The page spec defines how to fetch them (source, category, limit, sort)
> and how to display them (columns, filters, sort options, featured overrides).

## Page Spec Format

### Product Grid (PLP)

```json
{
  "type": "product_grid",
  "data": {
    "columns": 4,
    "source": "category",
    "category_id": "cat_0000000000000001",
    "limit": 200,
    "sort_options": [
      {"value": "featured", "label": "Featured"},
      {"value": "price:asc", "label": "Price: Low to High"},
      {"value": "price:desc", "label": "Price: High to Low"},
      {"value": "name:asc", "label": "Name: A-Z"}
    ],
    "filters": [
      {
        "type": "checkbox",
        "key": "collection",
        "label": "Collection",
        "options": [
          {"value": "SLOW COFFEE STYLE", "label": "Slow Coffee Style"},
          {"value": "OCT", "label": "OCT"}
        ]
      }
    ]
  }
}
```

### Source Types

| Source | Description | Required fields |
|--------|-------------|-----------------|
| `"category"` | Products in a PIM category | `category_id` |
| `"collection"` | Products in a PIM collection | `collection_id` |
| `"newest"` | Most recently created products | — |
| `"featured"` | Products tagged as featured | — |

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `limit` | int | Max products to fetch (default 12) |
| `offset` | int | Pagination offset |
| `sort` | string | Initial sort (e.g. `"price:asc"`) |
| `columns` | int 1-6 | Grid column count |
| `sort_options` | array | Sort dropdown options |
| `filters` | array | Filter drawer config |

## PIM API Reference

### Products

```
GET    /v1/pim/products                    # List (paginated)
GET    /v1/pim/products/:id                # Single product
POST   /v1/pim/products                    # Create
PATCH  /v1/pim/products/:id                # Update
DELETE /v1/pim/products/:id                # Delete
POST   /v1/pim/products/:id/publish        # Publish
POST   /v1/pim/products/:id/archive        # Archive
```

#### Create Product

```json
POST /v1/pim/products
{
  "title": "OCT brewer 2cups",
  "slug": "oct-brewer-2cups",
  "vendor": "KINTO",
  "product_type": "Drinkware",
  "description_html": "<p>Pour-over brewer with stainless steel filter.</p>",
  "tags": ["SLOW COFFEE STYLE", "Glass"],
  "material": "Borosilicate glass",
  "origin": "Japan",
  "category_id": "cat_0000000000000001"
}
```

#### List Products (Query Params)

| Param | Type | Description |
|-------|------|-------------|
| `limit` | int | Max results (default 50, max 200) |
| `offset` | int | Pagination offset |
| `category_id` | string | Filter by category |
| `vendor` | string | Filter by vendor |
| `product_type` | string | Filter by product type |
| `tag` | string | Filter by tag |
| `q` | string | Full-text search |
| `status` | string | Filter by status |

### Variants (Pricing & Inventory)

```
GET    /v1/pim/products/:id/variants       # List variants
POST   /v1/pim/products/:id/variants       # Create variant
PATCH  /v1/pim/variants/:id                # Update variant
DELETE /v1/pim/variants/:id                # Delete variant
```

```json
POST /v1/pim/products/:id/variants
{
  "title": "Default",
  "sku": "KINTO-OCT-2CUP",
  "currency": "GBP",
  "unit_amount": 2550,
  "inventory_qty": 100,
  "available": true
}
```

**unit_amount is in the smallest currency unit** (pence for GBP, cents for USD).

### Categories

```
GET    /v1/pim/categories                  # List all
POST   /v1/pim/categories                  # Create
PATCH  /v1/pim/categories/:id              # Update
DELETE /v1/pim/categories/:id              # Delete
```

### Collections

```
GET    /v1/pim/collections                 # List all
POST   /v1/pim/collections                 # Create
GET    /v1/pim/collections/:id             # Get with products
PATCH  /v1/pim/collections/:id             # Update
DELETE /v1/pim/collections/:id             # Delete
POST   /v1/pim/collections/:id/products    # Add product
DELETE /v1/pim/collections/:id/products/:pid  # Remove product
```

## Image Convention

Product images are served as static files at:

```
/images/kinto/{product-slug}_angle.jpg        # Primary product shot
/images/kinto/{product-slug}_coffee_shop.jpg   # Lifestyle/hover image
```

The `StorefrontHydrator` derives image URLs from the product slug:
- `image_url` → `/images/kinto/{slug}_angle.jpg`
- `hover_image_url` → `/images/kinto/{slug}_coffee_shop.jpg`

If PIM media records exist, those take priority over the slug convention.

## Elixir Module Reference

### `JargaAdmin.StorefrontHydrator`

```elixir
# Check if a component needs hydration
StorefrontHydrator.needs_hydration?(component)
# => true if component has type in [:product_grid, :product_scroll, :related_products]
#    AND has a non-empty source field

# Build PIM API query params from component assigns
StorefrontHydrator.build_api_params(assigns)
# => %{"category_id" => "cat_...", "limit" => "12"}

# Hydrate a single component
StorefrontHydrator.hydrate(component)
# => component with products replaced by PIM data

# Hydrate all components (parallel fetch, max 4 concurrent)
StorefrontHydrator.hydrate_all(components)
# => list of components with all hydratable ones hydrated

# Normalize a PIM product into storefront card format
StorefrontHydrator.normalize_product(pim_product)
# => %{id, name, price, price_cents, image_url, hover_image_url, href, ...}
```

### PIM → Storefront Field Mapping

| PIM field | Storefront card field |
|-----------|-----------------------|
| `title` | `name` |
| `slug` | `href` (as `/store/products/{slug}`) |
| `variants[0].unit_amount` | `price_cents`, `price` (formatted) |
| `variants[0].compare_at_amount` | `compare_at_price` |
| `media[0].url` | `image_url` |
| `media[1].url` | `hover_image_url` |
| `description_html` | `description` (HTML stripped) |
| `tags` | `tags`, `collection` (first tag) |
| `material` | `material` |

## Display Overrides (Spanning Cards)

Layout-specific display settings live in the page spec, NOT in the PIM.
These control **how** a card renders, not **what** product it shows.

The `display_overrides` map is keyed by product slug and merged onto
hydrated products after PIM fetch:

```json
{
  "type": "product_grid",
  "data": {
    "source": "category",
    "category_id": "cat_0000000000000001",
    "columns": 4,
    "display_overrides": {
      "scs-coffee-carafe-set-4cups": {
        "span": 3,
        "card_height": "flush",
        "position": 5,
        "images": [
          {"url": "/images/kinto/scs-coffee-carafe-set-4cups_coffee_shop.jpg", "span": 2},
          {"url": "/images/kinto/scs-coffee-carafe-set-4cups_angle.jpg", "span": 1}
        ]
      },
      "scs-s04-brewer-stand-set-4cups": {
        "span": 2,
        "card_height": "flush",
        "position": 9,
        "images": [
          {"url": "/images/kinto/scs-s04-brewer-stand-set-4cups_coffee_shop.jpg", "span": 1},
          {"url": "/images/kinto/scs-s04-brewer-stand-set-4cups_angle.jpg", "span": 1}
        ]
      }
    }
  }
}
```

### Override Fields

| Field | Values | Description |
|-------|--------|-------------|
| `span` | 1-4 | Grid columns the card occupies |
| `card_height` | `"flush"` / `"hero"` / `"auto"` | Image height mode |
| `images` | `[{url, alt, span}]` | Multi-image layout with ratios |
| `position` | int (1-indexed) | Force product to this position in the grid |
| `badge` | string | Badge text (e.g. "NEW", "SALE") |
| `featured` | boolean | Mark as featured |

### How It Works

1. Hydrator fetches all products from PIM for the category
2. For each product, checks if its slug has an entry in `display_overrides`
3. If yes, merges the override fields onto the product (span, images, etc.)
4. If any overrides have `position`, reorders products accordingly
5. Products without overrides render as standard 1-column cards

### Common Patterns

**3+1 editorial row** (hero product spanning 3 cols + 1 standard):
```json
"scs-coffee-carafe-set-4cups": {
  "span": 3, "card_height": "flush", "position": 5,
  "images": [
    {"url": "/images/lifestyle.jpg", "span": 2},
    {"url": "/images/product.jpg", "span": 1}
  ]
}
```

**2+2 feature pair** (two products each spanning 2 cols):
```json
"product-a": {"span": 2, "card_height": "flush", "position": 9, "images": [...]},
"product-b": {"span": 2, "card_height": "flush", "position": 10, "images": [...]}
```

**Hero card** (taller cinematic card):
```json
"hero-product": {"span": 3, "card_height": "hero", "position": 13, "images": [...]}
```

## NEVER Do This

❌ **Inline product data in page specs**
```json
{
  "type": "product_grid",
  "data": {
    "products": [
      {"name": "OCT Brewer", "price": "£25.50", ...}
    ]
  }
}
```

✅ **Reference PIM via source**
```json
{
  "type": "product_grid",
  "data": {
    "source": "category",
    "category_id": "cat_0000000000000001"
  }
}
```

## Current PIM Categories

| ID | Slug | Name | KINTO Products |
|----|------|------|---------------|
| `cat_0000000000000001` | coffee | Coffee | 56 |
| `cat_0000000000000003` | tea | Tea | 47 |
| `cat_0000000000000004` | mugs-cups | Mugs & Cups | 23 |
| `cat_0000000000000005` | tableware | Tableware | 117 |
| `cat_0000000000000006` | tumblers-bottles | Tumblers & Bottles | 42 |
| `cat_0000000000000009` | home-living | Home & Living | 28 |
