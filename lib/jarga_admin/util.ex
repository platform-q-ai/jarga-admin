defmodule JargaAdmin.Util do
  @moduledoc """
  Pure presentation helpers used across components and LiveViews.
  No data fetching — only formatting and classification.
  """

  @doc "Extract initials from a full name or email."
  def initials(nil), do: "?"
  def initials(""), do: "?"

  def initials(name) do
    name
    |> String.split(~r/[\s@.]+/)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  @doc "Stock percentage against reorder threshold (capped 0..100)."
  def stock_pct(_stock, 0), do: 100

  def stock_pct(stock, reorder_at) when reorder_at > 0 do
    min(100, round(stock / reorder_at * 100))
  end

  def stock_pct(_, _), do: 100

  @doc "CSS modifier for the stock bar — `\"low\"` or `\"ok\"`."
  def stock_class(0, _), do: "low"
  def stock_class(stock, reorder_at) when stock <= reorder_at, do: "low"
  def stock_class(_, _), do: "ok"

  @doc """
  Map a status string to `{label, badge_class}`.
  Badge classes: j-badge-green | j-badge-amber | j-badge-red | j-badge-muted
  """
  def status_badge(status)
  def status_badge("published"), do: {"Published", "j-badge-green"}
  def status_badge("active"), do: {"Active", "j-badge-green"}
  def status_badge("fulfilled"), do: {"Fulfilled", "j-badge-green"}
  def status_badge("paid"), do: {"Paid", "j-badge-green"}
  def status_badge("shipped"), do: {"Shipped", "j-badge-green"}
  def status_badge("delivered"), do: {"Delivered", "j-badge-green"}
  def status_badge("pending"), do: {"Pending", "j-badge-amber"}
  def status_badge("pending_payment"), do: {"Pending", "j-badge-amber"}
  def status_badge("unfulfilled"), do: {"Unfulfilled", "j-badge-amber"}
  def status_badge("partially_fulfilled"), do: {"Partial", "j-badge-amber"}
  def status_badge("partially_refunded"), do: {"Part. Refunded", "j-badge-amber"}
  def status_badge("draft"), do: {"Draft", "j-badge-muted"}
  def status_badge("refunded"), do: {"Refunded", "j-badge-red"}
  def status_badge("cancelled"), do: {"Cancelled", "j-badge-red"}
  def status_badge("expired"), do: {"Expired", "j-badge-muted"}
  def status_badge("out_of_stock"), do: {"Out of stock", "j-badge-red"}
  def status_badge(nil), do: {"—", "j-badge-muted"}
  def status_badge(s), do: {String.capitalize(s), "j-badge-muted"}
end
