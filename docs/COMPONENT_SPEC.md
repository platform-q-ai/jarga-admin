# Storefront Component Spec

A formal contract for adding components to the storefront rendering system.
Follow this spec exactly and every new component will "just work" — rendered
from JSON, styled via theme tokens, validated against injection, tested, and
available to any agent that can call the API.

---

## Architecture Overview

A component flows through **5 layers**, each with a single responsibility:

```
  API JSON                     ┌──────────────────┐
  {"type": "faq",    ────────► │ StorefrontRenderer│ normalize JSON → Elixir struct
   "data": {...}}              └────────┬─────────┘
                                        │
                               %{type: :faq, assigns: %{...}}
                                        │
                               ┌────────▼─────────┐
                               │ StorefrontLive    │ pattern-match type, call component
                               └────────┬─────────┘
                                        │
                               ┌────────▼─────────┐
                               │ Storefront        │ HEEx function component → HTML
                               │ Components        │
                               └────────┬─────────┘
                                        │
                               ┌────────▼─────────┐
                               │ storefront.css    │ .sf-{name} classes
                               └──────────────────┘
```

Each component touches **exactly 5 files** (+ 1 test file):

| # | File | What to add |
|---|------|-------------|
| 1 | `lib/jarga_admin/storefront_renderer.ex` | `normalize_component/1` clause |
| 2 | `lib/jarga_admin_web/live/storefront_live.ex` | `render_component/1` clause |
| 3 | `lib/jarga_admin_web/components/storefront_components.ex` | Function component |
| 4 | `assets/css/storefront.css` | `.sf-{name}` styles |
| 5 | `test/jarga_admin/storefront_renderer_test.exs` | Normalisation test |
| 6 | `test/jarga_admin_web/live/storefront_live_test.exs` | Rendering test |

---

## Step-by-Step: Adding a New Component

We'll use a concrete example: an `faq` component that renders an accordion
of question/answer pairs.

### Step 1 — Define the JSON Contract

Design the JSON shape an agent or human will send via the API:

```json
{
  "type": "faq",
  "data": {
    "title": "Frequently Asked Questions",
    "items": [
      {"question": "What is your return policy?", "answer": "30-day returns on all items."},
      {"question": "Do you ship internationally?", "answer": "Yes, to 40+ countries."}
    ],
    "style": {
      "background": "#fafafa",
      "padding": "48px 24px",
      "max_width": "800px"
    }
  },
  "conditions": {
    "after": "2026-01-01T00:00:00Z"
  }
}
```

**Rules for the JSON contract:**

- `type` — lowercase, snake_case string. Must be unique across all components.
- `data` — a flat-ish map. Nested arrays are fine (like `items`), but avoid deep nesting.
- `data.style` — optional. Uses the shared `StyleValidator` allowlist (see below).
- `conditions` — optional. Handled automatically by the renderer (you don't need to implement this).

### Step 2 — Normalise (StorefrontRenderer)

**File:** `lib/jarga_admin/storefront_renderer.ex`

Add a `normalize_component/1` clause that converts the raw JSON map into a
typed Elixir struct. This is the **single source of truth** for what fields
the component accepts and their defaults.

```elixir
defp normalize_component(%{"type" => "faq", "data" => data}) do
  items =
    (data["items"] || [])
    |> Enum.map(fn item ->
      %{
        question: item["question"] || "",
        answer: item["answer"] || ""
      }
    end)

  %{
    type: :faq,
    assigns: %{
      title: data["title"],
      items: items,
      style: extract_style(data)
    }
  }
end
```

**Rules:**

- Pattern match `%{"type" => "your_type", "data" => data}`.
- Return `%{type: :atom, assigns: %{...}}`.
- **Always** include `style: extract_style(data)` — this runs the style map
  through `StyleValidator` automatically.
- Use sensible defaults for every field (`|| ""`, `|| []`, `|| "default"`).
- String keys in → atom keys out. This is the JSON→Elixir boundary.
- Never trust input: no raw passthrough of user strings into atoms or code.
- If a field has a fixed set of valid values, validate with an allowlist:
  ```elixir
  layout = if data["layout"] in ~w(horizontal vertical), do: data["layout"], else: "vertical"
  ```

**Placement:** Add your clause **before** the catch-all `normalize_component(unknown)` at the bottom.

### Step 3 — Wire Up (StorefrontLive)

**File:** `lib/jarga_admin_web/live/storefront_live.ex`

Add a `render_component/1` clause that pattern-matches on the type atom and
calls the function component:

```elixir
defp render_component(%{component: %{type: :faq, assigns: a}} = assigns) do
  assigns = assign(assigns, :a, a)

  ~H"""
  <StorefrontComponents.faq title={@a.title} items={@a.items} style={@a.style} />
  """
end
```

**Rules:**

- Pattern match `%{component: %{type: :your_atom, assigns: a}}`.
- Assign `a` into the assigns map (required for HEEx access).
- Pass **every field** from `assigns` explicitly to the component — no
  spreading, no passthrough maps.
- **Placement:** Add before the catch-all `render_component(assigns)` clause.
- **Group with other `render_component` clauses** — Elixir requires all clauses
  of the same function to be together. Place it adjacent to the existing
  `render_component` clauses (around lines 529–750).

### Step 4 — Build the HTML (StorefrontComponents)

**File:** `lib/jarga_admin_web/components/storefront_components.ex`

Write a Phoenix function component:

```elixir
# ── FAQ ────────────────────────────────────────────────────────────────────

attr :title, :string, default: nil
attr :items, :list, default: []
attr :style, :map, default: %{}

def faq(assigns) do
  inline_style = StyleValidator.to_inline_style(assigns.style)
  assigns = assign(assigns, :inline_style, inline_style)

  ~H"""
  <section class="sf-faq" style={@inline_style}>
    <h2 :if={@title} class="sf-faq-title">{@title}</h2>
    <div class="sf-faq-items">
      <details :for={item <- @items} class="sf-faq-item">
        <summary class="sf-faq-question">{item.question}</summary>
        <div class="sf-faq-answer">{item.answer}</div>
      </details>
    </div>
  </section>
  """
end
```

**Rules:**

- **Always** declare `attr` for every prop. Include `:style` with `default: %{}`.
- **Always** use `StyleValidator.to_inline_style/1` to convert the style map
  to a safe inline CSS string. Never build `style=` attributes by hand from
  user data.
- **Always** prefix CSS classes with `sf-` followed by the component name:
  `sf-faq`, `sf-faq-title`, `sf-faq-item`.
- Use semantic HTML: `<section>` for containers, `<h2>` for titles, `<details>`
  for accordions, etc.
- Use `:for` comprehensions (not `Enum.each`) for lists.
- Use `:if` guards for optional content (not `<%= if ... %>`).
- **Never** use `raw/1` or `Phoenix.HTML.raw/1` — all content is escaped by
  HEEx automatically.
- For user-supplied colours, use `sanitize_hex/1`:
  ```elixir
  color_style = if assigns.color, do: "color: #{sanitize_hex(assigns.color)};", else: ""
  ```
- For user-supplied dimensions (widths, heights, padding), use
  `StyleValidator.sanitize_css_dimension/1`:
  ```elixir
  height_style = "height: #{StyleValidator.sanitize_css_dimension(assigns.height)}"
  ```

### Step 5 — Style It (storefront.css)

**File:** `assets/css/storefront.css`

```css
/* FAQ */
.sf-faq {
  padding: var(--sf-space-xl) var(--sf-space-md);
  max-width: var(--sf-max-width);
  margin: 0 auto;
}

.sf-faq-title {
  font-family: var(--sf-font-heading);
  font-size: 1.5rem;
  font-weight: var(--sf-font-weight-light);
  letter-spacing: var(--sf-letter-spacing-heading);
  text-transform: uppercase;
  text-align: center;
  margin-bottom: var(--sf-space-lg);
  color: var(--sf-color-text-primary);
}

.sf-faq-item {
  border-bottom: 1px solid var(--sf-color-border);
  padding: var(--sf-space-md) 0;
}

.sf-faq-question {
  font-family: var(--sf-font-body);
  font-size: 0.95rem;
  font-weight: var(--sf-font-weight-medium);
  letter-spacing: var(--sf-letter-spacing-body);
  cursor: pointer;
  color: var(--sf-color-text-primary);
  list-style: none;
}

.sf-faq-question::-webkit-details-marker {
  display: none;
}

.sf-faq-answer {
  font-family: var(--sf-font-body);
  font-size: 0.9rem;
  line-height: 1.7;
  color: var(--sf-color-text-secondary);
  padding-top: var(--sf-space-sm);
  max-width: 65ch;
}
```

**Rules:**

- **Always** use `var(--sf-*)` custom properties for colours, fonts, spacing,
  border radius, etc. Never hardcode `color: #333` — use `var(--sf-color-text-primary)`.
  This ensures the component respects theme changes.
- **Never** use `@apply`. Write raw CSS.
- Prefix every class with `sf-{component-name}`.
- Design for the **Zara Home aesthetic**: clean typography, generous whitespace,
  refined details, light borders, subtle transitions.
- Add responsive breakpoints at `768px` (tablet) and `480px` (mobile) where
  needed:
  ```css
  @media (max-width: 768px) {
    .sf-faq { padding: var(--sf-space-lg) var(--sf-space-sm); }
  }
  ```
- Add transitions for interactive elements:
  ```css
  .sf-faq-item summary {
    transition: color var(--sf-transition-speed) ease;
  }
  ```

### Step 6 — Test It

**Two test files, two test types.**

#### 6a. Normalisation test

**File:** `test/jarga_admin/storefront_renderer_test.exs`

```elixir
test "normalizes faq component" do
  spec = %{
    "components" => [
      %{
        "type" => "faq",
        "data" => %{
          "title" => "Help",
          "items" => [
            %{"question" => "Returns?", "answer" => "30 days."},
            %{"question" => "Shipping?", "answer" => "Free over £50."}
          ]
        }
      }
    ]
  }

  [comp] = StorefrontRenderer.render_spec(spec)
  assert comp.type == :faq
  assert comp.assigns.title == "Help"
  assert length(comp.assigns.items) == 2
  assert hd(comp.assigns.items).question == "Returns?"
  assert comp.assigns.style == %{}
end

test "normalizes faq with defaults" do
  spec = %{"components" => [%{"type" => "faq", "data" => %{}}]}
  [comp] = StorefrontRenderer.render_spec(spec)
  assert comp.type == :faq
  assert comp.assigns.title == nil
  assert comp.assigns.items == []
end
```

**Test rules:**
- Test the happy path with all fields populated.
- Test defaults with an empty `data` map.
- Assert on every field in `assigns`.
- If the component has an allowlist (layout variants, etc.), test invalid values
  fall back to the default.

#### 6b. Rendering test

**File:** `test/jarga_admin_web/live/storefront_live_test.exs`

```elixir
test "renders faq component", %{conn: conn} do
  page_spec = %{
    "components" => [
      %{
        "type" => "faq",
        "data" => %{
          "title" => "Common Questions",
          "items" => [
            %{"question" => "How do returns work?", "answer" => "Easy 30-day returns."}
          ]
        }
      }
    ]
  }

  conn = setup_storefront_page(conn, "test-faq", page_spec)
  {:ok, view, _html} = live(conn, "/store/test-faq")

  assert has_element?(view, ".sf-faq")
  assert has_element?(view, ".sf-faq-title", "Common Questions")
  assert has_element?(view, ".sf-faq-question", "How do returns work?")
end
```

**Test rules:**
- Use `has_element?/2` and `has_element?/3` — never assert on raw HTML strings.
- Test that the component's wrapper class (`.sf-faq`) is present.
- Test that key content renders (titles, text).
- For components with interactions (clicks, toggles), test the event cycle:
  ```elixir
  view |> element(".sf-faq-question") |> render_click()
  assert has_element?(view, ".sf-faq-answer", "Easy 30-day returns.")
  ```

---

## Cross-Cutting Concerns (Automatic)

These features work for **every** component automatically — you don't implement
them per-component:

### Inline Styling

Any component with `style: extract_style(data)` in its normaliser and
`StyleValidator.to_inline_style(assigns.style)` in its template gets per-instance
styling for free. The agent sends:

```json
{"type": "faq", "data": {"style": {"background": "#f5f0e8", "padding": "64px 24px"}}}
```

Allowed style properties (validated, injection-safe):

| Category | Properties |
|----------|-----------|
| **Layout** | `background`, `padding`, `margin`, `max_width`, `gap`, `text_align`, `min_height`, `border_top`, `border_bottom`, `border_radius` |
| **Typography** | `text_color`, `text_size`, `title_size`, `title_weight`, `title_color`, `title_spacing` |
| **Card-level** | `card_background`, `card_padding`, `card_aspect_ratio`, `card_border` |

Values are validated against patterns:
- Dimensions: `^[\d.]+(px|rem|em|%|vh|vw)$`
- Colours: `^#[0-9a-fA-F]{3,8}$` or `^(rgb|rgba|hsl|hsla)\(` patterns
- `text_align`: `left|center|right|justify` only
- Everything else is rejected (no `url()`, no `expression()`, no `javascript:`)

### Conditional Rendering

Any component can include a `conditions` map in the JSON. The renderer
evaluates conditions **before** normalisation — your component code never sees
them:

```json
{
  "type": "faq",
  "data": {"title": "Holiday FAQ"},
  "conditions": {
    "after": "2026-12-01T00:00:00Z",
    "before": "2026-12-31T23:59:59Z"
  }
}
```

| Condition | Effect |
|-----------|--------|
| `before` | Component hidden after the ISO 8601 timestamp |
| `after` | Component hidden before the ISO 8601 timestamp |
| `preview_only` | Component only visible with `?preview=true` |
| `min_width` | CSS responsive — hidden below this viewport width (px integer) |
| `max_width` | CSS responsive — hidden above this viewport width (px integer) |

### Responsive Classes

Viewport conditions (`min_width`, `max_width`) inject a `responsive_class`
into the component's assigns. The CSS media queries are generated automatically.
The component template should include the class if present:

```elixir
<section class={["sf-faq", assigns[:responsive_class]]} style={@inline_style}>
```

This is **optional** — only needed if you want viewport conditions to work on
your component. Most components don't need it because the CSS handles
responsiveness directly.

### Data Hydration

For product-bearing components (`product_grid`, `product_scroll`,
`related_products`), the hydrator replaces `source` references with live PIM
data. If your component lists products, add it to `@hydratable_types` in
`StorefrontHydrator`:

```elixir
@hydratable_types [:product_grid, :product_scroll, :related_products, :your_new_type]
```

And include `|> maybe_add_source(data)` in your normaliser to pass through
source fields.

Non-product components skip hydration entirely — no action needed.

---

## Security Checklist

Every component must satisfy these rules. Violating any of them will be caught
in code review:

- [ ] **No `raw/1`** — never render unescaped HTML from user data
- [ ] **Style via `StyleValidator`** — never build `style=` strings from raw
      user input. Always use `to_inline_style/1`, `sanitize_hex/1`, or
      `sanitize_css_dimension/1`
- [ ] **No atoms from user input** — the component type is mapped to an atom
      in the normaliser's pattern match, not via `String.to_atom/1`
- [ ] **Allowlist enums** — any field with a fixed set of values (layout,
      variant, direction) must be validated against an explicit list with a
      safe fallback
- [ ] **URL validation** — URLs from user data must start with `/` or `https://`.
      Block `javascript:`, `data:`, `vbscript:`
- [ ] **No inline `<script>` tags** — all JS goes in `assets/js/`
- [ ] **Image URLs sanitised** — use the existing `sanitize_image_url/1` helper
      if displaying user-provided image URLs

---

## Naming Conventions

| Layer | Convention | Example |
|-------|-----------|---------|
| JSON type | `snake_case` string | `"feature_list"` |
| Elixir type atom | `:snake_case` | `:feature_list` |
| Function component | `snake_case` function | `def feature_list(assigns)` |
| CSS classes | `sf-kebab-case` | `.sf-feature-list`, `.sf-feature-list-item` |
| HTML wrapper | `<section class="sf-{name}">` | `<section class="sf-feature-list">` |
| Test describe | `"normalizes {name} component"` | `"normalizes feature_list component"` |

---

## Component Catalogue (Current)

For reference, here are all 17 existing components with their normalised assign
shapes. Use these as patterns for new components:

### Layout Components (no product data)

| Component | Assigns |
|-----------|---------|
| `announcement_bar` | `message`, `href`, `style` |
| `editorial_hero` | `image_url`, `title`, `subtitle`, `cta`, `style` |
| `editorial_full` | `image_url`, `label`, `href`, `style` |
| `editorial_split` | `left`, `right` (each: `image_url`, `label`, `href`), `style` |
| `category_nav` | `links[]`, `style` |
| `text_block` | `title`, `content`, `style` |
| `video_hero` | `video_url`, `poster_url`, `title`, `subtitle`, `cta`, `autoplay`, `loop`, `muted`, `style` |
| `banner` | `message`, `background_color`, `text_color`, `cta`, `countdown_to`, `style` |
| `spacer` | `height`, `style` |
| `divider` | `thickness`, `color`, `max_width`, `style` |
| `image_grid` | `columns`, `gap`, `images[]` (`url`, `alt`, `href`), `style` |
| `testimonials` | `title`, `items[]` (`quote`, `author`, `role`, `avatar_url`, `rating`), `style` |
| `feature_list` | `features[]` (`icon`, `title`, `description`), `layout`, `style` |

### Product Components (support `source` hydration)

| Component | Assigns |
|-----------|---------|
| `product_grid` | `title`, `columns`, `products[]`, `style` (+ source fields) |
| `product_scroll` | `title`, `products[]`, `style` (+ source fields) |
| `related_products` | `title`, `products[]`, `style` (+ source fields) |
| `product_detail` | `id`, `name`, `price`, `compare_at_price`, `layout`, `images[]`, `description`, `colours[]`, `sizes[]`, `variants[]`, `breadcrumbs[]`, `in_stock`, `stock_count`, `quantity_max`, `accordion[]`, `style` |

### Product shape (shared by grid/scroll/related)

```elixir
%{
  id: "p1",
  name: "Linen Duvet",
  price: "£89.00",
  compare_at_price: "£120.00",  # optional, shows strikethrough
  image_url: "/images/duvet.jpg",
  hover_image_url: "/images/duvet-2.jpg",  # optional, swaps on hover
  href: "/store/products/linen-duvet",
  featured: false,
  variant: "default",  # "default" | "editorial" | "minimal" | "detailed"
  badge: "NEW",  # optional, overlay text
  description: "...",  # only shown in "detailed" variant
  colours: [%{"name" => "Natural", "hex" => "#c4b5a0"}]
}
```

---

## Adding a New Style Property

If your component needs a CSS property not in the allowlist (e.g. `opacity`,
`box_shadow`), add it to `StyleValidator`:

1. Add the property name to the appropriate list in `style_validator.ex`:
   ```elixir
   @layout_properties ~w(background padding margin max_width gap text_align
     min_height border_top border_bottom border_radius opacity)
   ```

2. If the property needs special validation (not just the default
   dimension/colour regex), add a validation clause.

3. Add a test in `test/jarga_admin/style_validator_test.exs`.

---

## TDD Workflow

When adding a component, follow this order:

1. **Write the normalisation test** (renderer test) — run it, see it fail (RED)
2. **Write the rendering test** (live test) — run it, see it fail (RED)
3. **Add `normalize_component/1`** — renderer test passes (GREEN)
4. **Add `render_component/1`** + function component + CSS — live test passes (GREEN)
5. **Refactor** — clean up, verify tests still pass
6. **Run `mix precommit`** — 0 new failures

---

## Quick Checklist for New Components

```
□ JSON contract designed (type + data fields + defaults)
□ normalize_component/1 added to StorefrontRenderer
□ render_component/1 added to StorefrontLive
□ Function component added to StorefrontComponents
□ CSS added to storefront.css (sf-{name} prefix, var(--sf-*) tokens)
□ extract_style(data) included in normaliser
□ StyleValidator.to_inline_style/1 used in template
□ Normalisation test written (happy path + defaults)
□ Rendering test written (element presence)
□ Security checklist passed
□ mix precommit passes with 0 new failures
```
