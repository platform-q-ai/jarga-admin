# Agent API Guide

> **Everything is API-driven.** An agent builds and manages the entire storefront
> through HTTP calls alone — no code changes, no deploys, no templates.

## Quick Start: Build a Store in 4 Steps

### Step 1: Create categories

```
POST /v1/pim/categories
{"name": "Coffee", "slug": "coffee"}

POST /v1/pim/categories
{"name": "Tea", "slug": "tea"}
```

### Step 2: Create products with pricing

```
POST /v1/pim/products
{
  "title": "OCT Brewer 2cups",
  "slug": "oct-brewer-2cups",
  "vendor": "KINTO",
  "product_type": "Drinkware",
  "description_html": "<p>Pour-over brewer with stainless steel filter.</p>",
  "tags": ["SLOW COFFEE STYLE", "Glass"],
  "material": "Borosilicate glass",
  "origin": "Japan",
  "category_id": "cat_0000000000000001"
}
→ returns {"data": {"id": "prod_oct_brewer_2cups", ...}}

POST /v1/pim/products/prod_oct_brewer_2cups/variants
{
  "title": "Default",
  "sku": "KINTO-OCT-2C",
  "currency": "GBP",
  "unit_amount": 2550,
  "inventory_qty": 100,
  "available": true
}

POST /v1/pim/products/prod_oct_brewer_2cups/publish
{}
```

### Step 3: Create storefront pages

```
POST /v1/frontend/bootstrap
{
  "publish": true,
  "pages": [
    {
      "slug": "home",
      "title": "Home",
      "status": "published",
      "content_json": "{\"layout\":\"storefront\",\"components\":[{\"type\":\"editorial_hero\",\"data\":{\"image_url\":\"/images/hero.jpg\",\"title\":\"KINTO\",\"subtitle\":\"Thoughtful design for everyday life\",\"cta\":{\"label\":\"SHOP COFFEE\",\"href\":\"/store/coffee\"}}}]}"
    },
    {
      "slug": "coffee",
      "title": "Coffee",
      "status": "published",
      "content_json": "{\"layout\":\"storefront\",\"components\":[{\"type\":\"text_block\",\"data\":{\"title\":\"Coffee\",\"body\":\"Pour-over brewers and everything for the perfect cup.\"}},{\"type\":\"product_grid\",\"data\":{\"source\":\"category\",\"category_id\":\"cat_0000000000000001\",\"columns\":4,\"limit\":200}}]}"
    }
  ]
}
```

### Step 4: Set theme

```
PUT /v1/frontend/slots/storefront_theme
{
  "fonts": {"heading": "Cormorant Garamond", "body": "Inter"},
  "colors": {"primary": "#1a1a1a", "background": "#ffffff"},
  "branding": {"store_name": "KINTO"}
}
```

**Done.** The store is live at `/store`.

---

## Common Agent Tasks

### Add a product and feature it on a PLP

```
# 1. Create in PIM
POST /v1/pim/products
{"title": "SCS-S04 Brewer — Matte Black", "slug": "scs-s04-matte-black", "vendor": "KINTO", "product_type": "Drinkware", "category_id": "cat_0000000000000001"}

# 2. Add pricing
POST /v1/pim/products/prod_scs_s04_matte_black/variants
{"title": "Default", "sku": "S04-MB", "currency": "GBP", "unit_amount": 14500, "inventory_qty": 25, "available": true}

# 3. Publish
POST /v1/pim/products/prod_scs_s04_matte_black/publish
{}

# 4. Feature on PLP (update page spec with display override)
GET /v1/frontend/pages/coffee
→ get current content_json

# Add to display_overrides in the product_grid component:
"display_overrides": {
  "scs-s04-matte-black": {
    "span": 3,
    "card_height": "flush",
    "position": 1,
    "badge": "NEW",
    "images": [
      {"url": "/images/kinto/scs-s04-matte-black_coffee_shop.jpg", "span": 2},
      {"url": "/images/kinto/scs-s04-matte-black_angle.jpg", "span": 1}
    ]
  }
}

POST /v1/frontend/bootstrap
{"publish": true, "pages": [{"slug": "coffee", "title": "Coffee", "content_json": "...", "status": "published"}]}
```

### Change product price

```
PATCH /v1/pim/variants/var_xxx
{"unit_amount": 12900}
```

The storefront automatically shows the new price — no page spec update needed.

### Change product layout on a PLP

```
# Get current page
GET /v1/frontend/pages/coffee

# Modify display_overrides in content_json, then:
POST /v1/frontend/bootstrap
{"publish": true, "pages": [{"slug": "coffee", ...}]}
```

### Create a new category page

```
# 1. Create category in PIM
POST /v1/pim/categories
{"name": "Gifts", "slug": "gifts"}
→ returns {"data": {"id": "cat_0000000000000002"}}

# 2. Create PLP page
POST /v1/frontend/bootstrap
{"publish": true, "pages": [{
  "slug": "gifts",
  "title": "Gifts",
  "status": "published",
  "content_json": "{\"layout\":\"storefront\",\"components\":[{\"type\":\"text_block\",\"data\":{\"title\":\"Gifts\",\"body\":\"Curated gift sets.\"}},{\"type\":\"product_grid\",\"data\":{\"source\":\"category\",\"category_id\":\"cat_0000000000000002\",\"columns\":4,\"limit\":200}}]}"
}]}
```

### Update inventory

```
PATCH /v1/pim/variants/var_xxx
{"inventory_qty": 50, "available": true}
```

### Archive a product

```
POST /v1/pim/products/prod_xxx/archive
{}
```

Archived products won't appear in storefront hydration results.

---

## Two Separate Concerns

| Concern | API | What it controls |
|---------|-----|-----------------|
| **Product data** | PIM (`/v1/pim/...`) | Title, price, stock, category, tags, material |
| **Page layout** | Frontend (`/v1/frontend/...`) | Grid columns, sort/filter options, display overrides, hero images, text blocks |

**Product data** changes (price, stock, title) take effect immediately — no page spec update needed. The storefront hydrates from PIM on every request.

**Layout** changes (featuring a product, changing grid columns, adding a hero banner) require updating the page spec via the Frontend API.

---

## PIM API Reference

### Products

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/v1/pim/products` | List products (paginated) |
| `GET` | `/v1/pim/products/:id` | Get single product |
| `POST` | `/v1/pim/products` | Create product |
| `PATCH` | `/v1/pim/products/:id` | Update product |
| `DELETE` | `/v1/pim/products/:id` | Delete product |
| `POST` | `/v1/pim/products/:id/publish` | Publish product |
| `POST` | `/v1/pim/products/:id/archive` | Archive product |

#### Create Product (required fields)

```json
{
  "title": "string",
  "slug": "string",
  "vendor": "string",
  "product_type": "string"
}
```

#### Create Product (all fields)

```json
{
  "title": "OCT Brewer 2cups",
  "slug": "oct-brewer-2cups",
  "vendor": "KINTO",
  "product_type": "Drinkware",
  "description_html": "<p>Description here.</p>",
  "tags": ["SLOW COFFEE STYLE", "Glass"],
  "material": "Borosilicate glass",
  "origin": "Japan",
  "category_id": "cat_0000000000000001",
  "seo_title": "OCT Brewer | KINTO",
  "seo_description": "Pour-over brewer by KINTO"
}
```

#### List Products (query params)

| Param | Type | Description |
|-------|------|-------------|
| `limit` | int | Max results (default 50, max 200) |
| `offset` | int | Pagination offset |
| `category_id` | string | Filter by category ID |
| `vendor` | string | Filter by vendor |
| `product_type` | string | Filter by product type |
| `tag` | string | Filter by tag |
| `q` | string | Full-text search |
| `status` | string | Filter by status (published/draft/archived) |

### Variants (Pricing & Stock)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/v1/pim/products/:id/variants` | List variants |
| `POST` | `/v1/pim/products/:id/variants` | Create variant |
| `PATCH` | `/v1/pim/variants/:id` | Update variant |
| `DELETE` | `/v1/pim/variants/:id` | Delete variant |

#### Create Variant (required fields)

```json
{
  "title": "Default",
  "sku": "KINTO-OCT-2C",
  "currency": "GBP",
  "unit_amount": 2550,
  "inventory_qty": 100,
  "available": true
}
```

> **unit_amount** is in the smallest currency unit: pence (GBP), cents (USD/EUR).

### Categories

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/v1/pim/categories` | List all |
| `POST` | `/v1/pim/categories` | Create |
| `PATCH` | `/v1/pim/categories/:id` | Update |
| `DELETE` | `/v1/pim/categories/:id` | Delete |

```json
POST /v1/pim/categories
{"name": "Coffee", "slug": "coffee"}
```

### Collections

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/v1/pim/collections` | List all |
| `POST` | `/v1/pim/collections` | Create |
| `GET` | `/v1/pim/collections/:id` | Get with products |
| `PATCH` | `/v1/pim/collections/:id` | Update |
| `DELETE` | `/v1/pim/collections/:id` | Delete |
| `POST` | `/v1/pim/collections/:id/products` | Add product |
| `DELETE` | `/v1/pim/collections/:id/products/:pid` | Remove product |

---

## Frontend API Reference

### Pages

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/v1/frontend/bootstrap` | Create/update multiple pages |
| `GET` | `/v1/frontend/pages/:slug` | Get published page |

#### Bootstrap (create/update pages)

```json
POST /v1/frontend/bootstrap
{
  "publish": true,
  "pages": [
    {
      "slug": "coffee",
      "title": "Coffee",
      "status": "published",
      "content_json": "{ JSON string of page spec }"
    }
  ]
}
```

### Slots (Theme, Footer, Nav)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/v1/frontend/slots/:key` | Get slot content |
| `PUT` | `/v1/frontend/slots/:key` | Set slot content |

Key slots: `storefront_theme`, `storefront_footer`, `storefront_nav`

---

## Page Spec: Product Grid with Display Overrides

This is the core pattern. A product grid declares **where** to get products
(PIM source) and **how** to display specific ones (overrides):

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
    ],
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

### Display Override Fields

| Field | Type | Description |
|-------|------|-------------|
| `span` | int 1-4 | Grid columns the card occupies |
| `card_height` | `"flush"` / `"hero"` / `"auto"` | `flush` = same height as 1-col cards, `hero` = taller cinematic, `auto` = natural |
| `images` | array of `{url, alt, span}` | Multi-image layout; each image's `span` controls its width ratio |
| `position` | int (1-indexed) | Force this product to a specific position in the grid |
| `badge` | string | Badge text overlay (e.g. `"NEW"`, `"SALE"`) |
| `featured` | boolean | Mark as featured |

### Layout Recipes

**Standard 4-column grid** (no overrides needed):
```json
{"source": "category", "category_id": "cat_...", "columns": 4}
```

**3+1 editorial row** (hero product spanning 3 cols, 1 standard):
```json
"slug-of-hero-product": {
  "span": 3, "card_height": "flush", "position": 5,
  "images": [
    {"url": "/images/lifestyle.jpg", "span": 2},
    {"url": "/images/product.jpg", "span": 1}
  ]
}
```

**2+2 feature pair** (two products side by side, each 2 cols):
```json
"product-a": {"span": 2, "card_height": "flush", "position": 9, "images": [...]},
"product-b": {"span": 2, "card_height": "flush", "position": 10, "images": [...]}
```

**Tall hero card** (cinematic, taller than neighbours):
```json
"hero-slug": {"span": 3, "card_height": "hero", "position": 1, "images": [...]}
```

**Badge a product** (no layout change, just add a badge):
```json
"sale-product": {"badge": "30% OFF"}
```

### Source Types

| Source | Required | Description |
|--------|----------|-------------|
| `"category"` | `category_id` | All products in a PIM category |
| `"collection"` | `collection_id` | All products in a PIM collection |
| `"newest"` | — | Most recently created products |
| `"featured"` | — | Products tagged as "featured" |

---

## Image Convention

Product images are resolved in order:

1. **PIM media** — if the product has media records attached, those URLs are used
2. **Slug convention** — otherwise, images are derived from the product slug:
   - Primary: `/images/kinto/{slug}_angle.jpg`
   - Hover: `/images/kinto/{slug}_coffee_shop.jpg`
3. **Display override images** — if `display_overrides` specifies `images`, those replace the default for that card's multi-image layout

---

## What NOT to Do

❌ **Never put product data in page specs**
```json
{"type": "product_grid", "data": {"products": [{"name": "OCT", "price": "£25"}]}}
```
This duplicates data, drifts from PIM, and won't show in the admin panel.

✅ **Always use source + category_id**
```json
{"type": "product_grid", "data": {"source": "category", "category_id": "cat_..."}}
```

❌ **Never hardcode prices in display_overrides**
Display overrides control **layout** (span, position, images) — never product data.

✅ **Change prices via PIM**
```
PATCH /v1/pim/variants/var_xxx
{"unit_amount": 2900}
```

---

## Current PIM Categories

| ID | Slug | Name | Products |
|----|------|------|----------|
| `cat_0000000000000001` | coffee | Coffee | 56 |
| `cat_0000000000000003` | tea | Tea | 47 |
| `cat_0000000000000004` | mugs-cups | Mugs & Cups | 23 |
| `cat_0000000000000005` | tableware | Tableware | 117 |
| `cat_0000000000000006` | tumblers-bottles | Tumblers & Bottles | 42 |
| `cat_0000000000000009` | home-living | Home & Living | 36 |

---

## Authentication

All API calls require:
```
Authorization: Bearer sk_c863e21f12d54ab5aed7ff09064fc0b6
Content-Type: application/json
```

## Base URL

```
http://localhost:8080
```

## Storefront URL

```
http://localhost:4000/store
http://localhost:4000/store/{page-slug}
http://localhost:4000/store/products/{product-slug}
```
