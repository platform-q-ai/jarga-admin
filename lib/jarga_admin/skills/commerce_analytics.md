# SKILL: Commerce Analytics — Interpreting Sales Data

## Key metrics to always include
- **Revenue**: total_revenue (GBP), trend vs previous period
- **Orders**: order_count, trend
- **AOV**: average_order_value = revenue / orders
- **Returns**: return_count, return_rate = returns / orders × 100

## Periods
- `period: "today"` — current day so far vs yesterday same time
- `period: "week"` — current 7 days vs previous 7 days  
- `period: "month"` — current month vs same month last year
- Or use `from_date` + `to_date` for custom ranges

## Trend interpretation
- > 10% up → "strong growth"
- 0-10% up → "steady growth"
- 0-10% down → "slight decline"
- > 10% down → "notable decline, consider action"

## Chart guidance
- Use **line charts** for trends over time (daily/weekly revenue)
- Use **bar charts** for comparisons (product revenue, category breakdown)
- Use **doughnut charts** for proportions (revenue by category, order status mix)

## Default analytics dashboard layout
1. metric_grid: revenue, orders, AOV, returns (4 cards)
2. chart (line): daily revenue last 30 days
3. data_table: top 10 products by revenue
