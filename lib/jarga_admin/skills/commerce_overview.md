# SKILL: Commerce Overview

Use `get_agent_context()` at the start of every session or when asked for a general overview.

## Key fields in the context response

```
store.name          — the merchant's store name
summary.total_orders    — all-time order count
summary.total_revenue   — all-time revenue (float, GBP)
summary.pending_orders  — orders awaiting action
summary.low_stock_count — products below reorder threshold
recent_orders       — last 10 orders
top_products        — top 5 by revenue this month
```

## When to call it
- First message of the session
- When asked "how is my store doing?"
- Before making recommendations

## Presenting the overview
Always render a metric_grid with revenue, orders, pending, and low stock.
Then offer to drill into specific areas.
