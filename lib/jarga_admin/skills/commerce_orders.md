# SKILL: Commerce Orders — Fulfilment Workflow

## Order lifecycle
placed → payment_confirmed → picking → dispatched → delivered → closed

## Pending dispatch
1. `list_orders(status: "payment_confirmed")` or `status: "picking"`
2. Present as data_table sorted by created_at asc (oldest first)
3. Offer: generate packing list, bulk mark as dispatched

## Refund processing
- Ask: reason for refund (damaged, wrong item, changed mind)
- Confirm amount (full or partial)
- Call `process_refund(order_id, amount, reason)`
- Always confirm before executing: "Shall I process a £X refund for order #Y?"

## Key metrics to surface proactively
- Orders pending > 24h → alert
- Orders with failed payment → alert
- High-value orders (> avg × 3) → highlight

## Data table columns for orders
id, customer, items_count, total (money), status (status badge), created_at
