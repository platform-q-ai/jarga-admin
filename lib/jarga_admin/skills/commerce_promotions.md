# SKILL: Commerce Promotions — Campaign Creation

## Campaign types
- `percentage` — e.g. 20% off
- `fixed_amount` — e.g. £10 off
- `free_shipping` — waive delivery charge
- `bxgy` — buy X get Y (future)

## Creation checklist
1. Name (descriptive, e.g. "Spring 20% Off — Jackets")
2. Type + value
3. Scope: all products, specific collections, or individual products
4. Date range: starts_at, ends_at (ISO 8601)
5. Conditions: min_order_value?, customer_segments?
6. Coupon code (optional): single-use or multi-use

## Validation rules
- Percentage discount must be 1–100
- Fixed amount must be ≤ avg product price
- End date must be after start date
- Cannot create overlapping promotions on same products without confirmation

## Pre-filling forms
When the merchant says "20% off jackets from Friday to Sunday", pre-fill:
- discount_type: percentage
- discount_value: 20
- starts_at: next Friday 00:00
- ends_at: next Sunday 23:59
- scope: collection (search for "Jackets")

Always show the dynamic_form for confirmation before creating.
