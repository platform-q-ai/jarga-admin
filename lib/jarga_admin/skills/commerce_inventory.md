# SKILL: Commerce Inventory Management

## Restock decision framework

1. **Check levels**: `get_inventory_levels()` — note items with stock < reorder_point
2. **Prioritise**:
   - Stock = 0 → urgent (show red badge)
   - Stock ≤ reorder_point → warn (show amber badge)
   - Stock > reorder_point → healthy (green)
3. **Recommend restock quantities** based on:
   - Average daily sales (from analytics)
   - Lead time (typically 5-14 days)
   - Safety stock = avg_daily_sales × lead_time × 1.5

## Presenting inventory
Render a data_table with columns: Product, SKU, Stock, Reorder Point, Status.
Include an alert_banner when items are at zero stock.

## Auto-restock guidance
Suggest reorder quantities but do NOT place purchase orders automatically.
Always confirm with the merchant first.
