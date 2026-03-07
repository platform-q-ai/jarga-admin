defmodule JargaAdmin.TabSpecBuilder do
  @moduledoc """
  Builds UI spec maps for each default admin tab by calling the live API.

  Extracted from TabStore to keep file sizes under the 750-line architecture limit.
  All functions are called lazily on first tab access (never on startup).
  """

  require Logger

  # ── Default specs (built from live API) ───────────────────────────────────

  def build_spec("dashboard") do
    orders = unwrap_or_empty(fetch_orders())
    products = unwrap_or_empty(fetch_products())
    recent = Enum.take(orders, 5)

    paid_total =
      orders
      |> Enum.filter(&(&1["financial_status"] == "paid"))
      |> Enum.map(&(&1["amount_total"] || 0))
      |> Enum.sum()

    low_stock =
      products
      |> Enum.flat_map(fn p ->
        (p["variants"] || [])
        |> Enum.filter(&((&1["inventory_qty"] || 0) < 20))
        |> Enum.map(fn v ->
          %{
            "id" => v["id"],
            "name" => p["title"],
            "sku" => v["sku"] || "",
            "stock" => v["inventory_qty"] || 0,
            "reorder_at" => 20
          }
        end)
      end)
      |> Enum.sort_by(& &1["stock"])
      |> Enum.take(8)

    pending_count = Enum.count(orders, &(&1["fulfillment_status"] == "unfulfilled"))

    %{
      "layout" => "full",
      "components" => [
        %{
          "type" => "stat_bar",
          "data" => %{
            "stats" => [
              %{
                "label" => "Revenue (all paid)",
                "value" => format_pence(paid_total),
                "delta" => nil
              },
              %{"label" => "Total orders", "value" => "#{length(orders)}", "delta" => nil},
              %{"label" => "Pending fulfilment", "value" => "#{pending_count}", "delta" => nil},
              %{"label" => "Products", "value" => "#{length(products)}", "delta" => nil}
            ]
          }
        },
        %{
          "type" => "data_table",
          "title" => "Recent orders",
          "data" => %{
            "columns" => [
              %{"key" => "order_number", "label" => "Order"},
              %{"key" => "email", "label" => "Customer"},
              %{"key" => "amount_total", "label" => "Total"},
              %{"key" => "financial_status", "label" => "Payment"},
              %{"key" => "fulfillment_status", "label" => "Fulfilment"}
            ],
            "rows" => Enum.map(recent, &order_row/1),
            "on_row_click" => "view_order"
          }
        },
        %{
          "type" => "inventory_table",
          "title" => "Low stock",
          "data" => %{"rows" => low_stock, "on_restock" => "restock_item"}
        }
      ]
    }
  end

  def build_spec("orders") do
    with {:ok, orders} <- fetch_orders() do
      build_orders_spec(orders)
    else
      {:error, reason} -> error_spec(reason)
    end
  end

  def build_spec("products") do
    with {:ok, products} <- fetch_products() do
      build_products_spec(products)
    else
      {:error, reason} -> error_spec(reason)
    end
  end

  def build_spec("customers") do
    with {:ok, customers} <- fetch_customers() do
      build_customers_spec(customers)
    else
      {:error, reason} -> error_spec(reason)
    end
  end

  def build_spec("promotions") do
    with {:ok, promotions} <- fetch_promotions() do
      build_promotions_spec(promotions)
    else
      {:error, reason} -> error_spec(reason)
    end
  end

  def build_spec("inventory") do
    with {:ok, products} <- fetch_products() do
      build_inventory_spec(products)
    else
      {:error, reason} -> error_spec(reason)
    end
  end

  def build_spec("analytics") do
    with {:ok, orders} <- fetch_orders() do
      build_analytics_spec(orders)
    else
      {:error, reason} -> error_spec(reason)
    end
  end

  def build_spec("shipping") do
    zones_result =
      case JargaAdmin.Api.list_shipping_zones() do
        {:ok, list} when is_list(list) -> {:ok, list}
        {:ok, %{"items" => items}} -> {:ok, items}
        {:error, %Req.TransportError{reason: :timeout}} -> {:error, :timeout}
        {:error, _} -> {:error, :unavailable}
      end

    with {:ok, zones} <- zones_result do
      build_shipping_spec(zones)
    else
      {:error, reason} -> error_spec(reason)
    end
  end

  def build_spec("draft_orders") do
    # fetch_draft_orders always succeeds (falls back to empty on 404/405)
    {:ok, draft_orders} = fetch_draft_orders()
    build_draft_orders_spec(draft_orders)
  end

  def build_spec(_), do: nil

  # ── Per-resource spec builders ──────────────────────────────────────────────

  defp build_orders_spec(orders) do
    _paid = Enum.count(orders, &(&1["financial_status"] == "paid"))
    pending = Enum.count(orders, &(&1["financial_status"] == "pending_payment"))
    refunded = Enum.count(orders, &(&1["financial_status"] in ["refunded", "partially_refunded"]))
    cancelled = Enum.count(orders, &(&1["financial_status"] == "cancelled"))
    unfulfilled = Enum.count(orders, &(&1["fulfillment_status"] == "unfulfilled"))

    paid_revenue =
      orders
      |> Enum.filter(&(&1["financial_status"] in ["paid", "partially_refunded"]))
      |> Enum.map(&(&1["amount_total"] || 0))
      |> Enum.sum()

    %{
      "layout" => "full",
      "components" => [
        %{
          "type" => "stat_bar",
          "data" => %{
            "stats" => [
              %{"label" => "Total orders", "value" => "#{length(orders)}"},
              %{"label" => "Revenue", "value" => format_pence(paid_revenue)},
              %{"label" => "Unfulfilled", "value" => "#{unfulfilled}"},
              %{"label" => "Pending / Cancelled", "value" => "#{pending + cancelled}"},
              %{"label" => "Refunded", "value" => "#{refunded}"}
            ]
          }
        },
        %{
          "type" => "data_table",
          "title" => "All orders",
          "data" => %{
            "columns" => [
              %{"key" => "order_number", "label" => "Order"},
              %{"key" => "created_at", "label" => "Date"},
              %{"key" => "email", "label" => "Customer"},
              %{"key" => "items", "label" => "Items"},
              %{"key" => "amount_total", "label" => "Total"},
              %{"key" => "financial_status", "label" => "Payment"},
              %{"key" => "fulfillment_status", "label" => "Fulfilment"}
            ],
            "rows" => Enum.map(orders, &order_row/1),
            "on_row_click" => "view_order"
          }
        }
      ]
    }
  end

  defp build_products_spec(products) do
    published = Enum.count(products, &(&1["status"] == "active"))
    draft = Enum.count(products, &(&1["status"] == "draft"))

    low_stock_count =
      products
      |> Enum.flat_map(&(&1["variants"] || []))
      |> Enum.count(&((&1["inventory_qty"] || 0) < 20))

    %{
      "layout" => "full",
      "components" => [
        %{
          "type" => "stat_bar",
          "data" => %{
            "stats" => [
              %{"label" => "Total products", "value" => "#{length(products)}"},
              %{"label" => "Published", "value" => "#{published}"},
              %{"label" => "Draft", "value" => "#{draft}"},
              %{"label" => "Low / out of stock", "value" => "#{low_stock_count}"}
            ]
          }
        },
        action_bar_component("product"),
        %{
          "type" => "product_grid",
          "title" => "All products",
          "data" => %{
            "products" => Enum.map(products, &product_card/1),
            "on_click" => "view_product"
          }
        }
      ]
    }
  end

  defp build_customers_spec(customers) do
    subscribed =
      Enum.count(customers, fn c ->
        get_in(c, ["email_marketing_consent", "status"]) == "subscribed"
      end)

    %{
      "layout" => "full",
      "components" => [
        %{
          "type" => "stat_bar",
          "data" => %{
            "stats" => [
              %{"label" => "Total customers", "value" => "#{length(customers)}"},
              %{
                "label" => "With email",
                "value" => "#{Enum.count(customers, &(&1["email"] != nil))}"
              },
              %{"label" => "Subscribed to email", "value" => "#{subscribed}"},
              %{
                "label" => "Countries",
                "value" =>
                  "#{customers |> Enum.map(&get_in(&1, ["default_address", "country_code"])) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> length()}"
              }
            ]
          }
        },
        action_bar_component("customer"),
        %{
          "type" => "data_table",
          "title" => "All customers",
          "data" => %{
            "columns" => [
              %{"key" => "name", "label" => "Customer"},
              %{"key" => "email", "label" => "Email"},
              %{"key" => "marketing", "label" => "Marketing"},
              %{"key" => "location", "label" => "Location"},
              %{"key" => "avg_order_value", "label" => "Avg order"},
              %{"key" => "created_at", "label" => "Joined"}
            ],
            "rows" => Enum.map(customers, &customer_row/1),
            "on_row_click" => "view_customer"
          }
        }
      ]
    }
  end

  defp build_promotions_spec(promotions) do
    active = Enum.count(promotions, &(&1["status"] == "active"))
    inactive = Enum.count(promotions, &(&1["status"] != "active"))

    %{
      "layout" => "full",
      "components" => [
        %{
          "type" => "stat_bar",
          "data" => %{
            "stats" => [
              %{"label" => "Total campaigns", "value" => "#{length(promotions)}"},
              %{"label" => "Active", "value" => "#{active}"},
              %{"label" => "Inactive", "value" => "#{inactive}"},
              %{
                "label" => "Total uses",
                "value" => "#{promotions |> Enum.map(&(&1["use_count"] || 0)) |> Enum.sum()}"
              }
            ]
          }
        },
        action_bar_component("promotion"),
        %{
          "type" => "promotion_list",
          "title" => "All promotions",
          "data" => %{"promotions" => Enum.map(promotions, &promotion_row/1)}
        }
      ]
    }
  end

  defp build_inventory_spec(products) do
    variant_rows =
      products
      |> Enum.flat_map(fn p ->
        (p["variants"] || [])
        |> Enum.map(fn v ->
          qty = v["inventory_qty"] || 0

          %{
            "id" => v["id"],
            "product" => p["title"],
            "variant" => v["title"],
            "sku" => v["sku"] || "",
            "available" => qty,
            "status" =>
              cond do
                qty == 0 -> "out_of_stock"
                qty < 10 -> "low_stock"
                true -> "in_stock"
              end
          }
        end)
      end)
      |> Enum.sort_by(& &1["available"])

    total = length(variant_rows)
    out_of_stock = Enum.count(variant_rows, &(&1["status"] == "out_of_stock"))
    low_stock = Enum.count(variant_rows, &(&1["status"] == "low_stock"))
    in_stock = total - out_of_stock - low_stock

    %{
      "layout" => "full",
      "components" => [
        %{
          "type" => "stat_bar",
          "data" => %{
            "stats" => [
              %{"label" => "Total SKUs", "value" => "#{total}"},
              %{"label" => "In stock", "value" => "#{in_stock}"},
              %{"label" => "Low stock (<10)", "value" => "#{low_stock}"},
              %{"label" => "Out of stock", "value" => "#{out_of_stock}"}
            ]
          }
        },
        %{
          "type" => "inventory_detail_table",
          "title" => "All inventory",
          "data" => %{
            "rows" => variant_rows
          }
        }
      ]
    }
  end

  defp build_analytics_spec(orders) do
    total_revenue =
      orders
      |> Enum.filter(&(&1["financial_status"] in ["paid", "partially_refunded"]))
      |> Enum.map(&(&1["amount_total"] || 0))
      |> Enum.sum()

    avg_order_value =
      case Enum.count(orders, &(&1["financial_status"] == "paid")) do
        0 -> 0
        n -> div(total_revenue, n)
      end

    # Group orders by financial_status for breakdown
    status_breakdown =
      orders
      |> Enum.group_by(&(&1["financial_status"] || "unknown"))
      |> Enum.map(fn {status, list} ->
        %{
          "status" => humanise(status),
          "count" => length(list),
          "revenue" => Enum.sum(Enum.map(list, &(&1["amount_total"] || 0)))
        }
      end)
      |> Enum.sort_by(& &1["count"], :desc)

    # Revenue by month (last 6 months from order data)
    monthly_revenue =
      orders
      |> Enum.filter(&(&1["financial_status"] in ["paid", "partially_refunded"]))
      |> Enum.group_by(fn o ->
        case o["created_at"] do
          nil -> "Unknown"
          ts -> String.slice(ts, 0, 7)
        end
      end)
      |> Enum.map(fn {month, list} ->
        %{
          "month" => month,
          "revenue" => Enum.sum(Enum.map(list, &(&1["amount_total"] || 0))),
          "count" => length(list)
        }
      end)
      |> Enum.sort_by(& &1["month"])
      |> Enum.take(-6)

    %{
      "layout" => "full",
      "components" => [
        %{
          "type" => "stat_bar",
          "data" => %{
            "stats" => [
              %{"label" => "Total revenue", "value" => format_pence(total_revenue)},
              %{"label" => "Total orders", "value" => "#{length(orders)}"},
              %{"label" => "Avg order value", "value" => format_pence(avg_order_value)},
              %{
                "label" => "Paid orders",
                "value" => "#{Enum.count(orders, &(&1["financial_status"] == "paid"))}"
              }
            ]
          }
        },
        %{
          "type" => "analytics_revenue",
          "title" => "Revenue by month",
          "data" => %{"rows" => monthly_revenue}
        },
        %{
          "type" => "analytics_breakdown",
          "title" => "Orders by status",
          "data" => %{"rows" => status_breakdown}
        }
      ]
    }
  end

  defp build_shipping_spec(zones) do
    %{
      "layout" => "full",
      "components" => [
        %{
          "type" => "stat_bar",
          "data" => %{
            "stats" => [
              %{"label" => "Shipping zones", "value" => "#{length(zones)}"},
              %{
                "label" => "Active",
                "value" => "#{Enum.count(zones, &(&1["active"] == true))}"
              },
              %{
                "label" => "Total countries",
                "value" =>
                  "#{zones |> Enum.flat_map(&(&1["countries"] || [])) |> Enum.uniq() |> length()}"
              },
              %{"label" => "Carriers", "value" => "3"}
            ]
          }
        },
        action_bar_component("shipping_zone"),
        %{
          "type" => "shipping_zones_table",
          "title" => "Shipping zones",
          "data" => %{"zones" => Enum.map(zones, &shipping_zone_row/1)}
        }
      ]
    }
  end

  defp build_draft_orders_spec(draft_orders) do
    total_value =
      draft_orders
      |> Enum.map(&(get_in(&1, ["total"]) || 0))
      |> Enum.sum()

    %{
      "layout" => "full",
      "components" => [
        %{
          "type" => "stat_bar",
          "data" => %{
            "stats" => [
              %{"label" => "Draft orders", "value" => "#{length(draft_orders)}"},
              %{"label" => "Total value", "value" => format_pence(total_value)},
              %{
                "label" => "Open",
                "value" => "#{Enum.count(draft_orders, &((&1["status"] || "open") == "open"))}"
              },
              %{
                "label" => "Completed",
                "value" => "#{Enum.count(draft_orders, &(&1["status"] == "completed"))}"
              }
            ]
          }
        },
        %{
          "type" => "data_table",
          "title" => "All draft orders",
          "data" => %{
            "columns" => [
              %{"key" => "id", "label" => "Draft ID"},
              %{"key" => "customer_id", "label" => "Customer"},
              %{"key" => "items", "label" => "Items"},
              %{"key" => "total", "label" => "Total"},
              %{"key" => "status", "label" => "Status"},
              %{"key" => "created_at", "label" => "Created"}
            ],
            "rows" => Enum.map(draft_orders, &draft_order_row/1)
          }
        }
      ]
    }
  end

  # ── API fetchers — return {:ok, items} or {:error, reason} ───────────────

  defp fetch_orders do
    case JargaAdmin.Api.list_orders() do
      {:ok, %{"items" => items}} -> {:ok, items}
      {:ok, items} when is_list(items) -> {:ok, items}
      {:error, %{status: s}} -> {:error, "API error (HTTP #{s})"}
      {:error, %Req.TransportError{reason: :timeout}} -> {:error, :timeout}
      {:error, _} -> {:error, :unavailable}
    end
  end

  defp fetch_products do
    case JargaAdmin.Api.list_products() do
      {:ok, %{"items" => items}} -> {:ok, items}
      {:ok, items} when is_list(items) -> {:ok, items}
      {:error, %{status: s}} -> {:error, "API error (HTTP #{s})"}
      {:error, %Req.TransportError{reason: :timeout}} -> {:error, :timeout}
      {:error, _} -> {:error, :unavailable}
    end
  end

  defp fetch_customers do
    case JargaAdmin.Api.list_customers() do
      {:ok, %{"items" => items}} -> {:ok, items}
      {:ok, %{"data" => items}} when is_list(items) -> {:ok, items}
      {:ok, items} when is_list(items) -> {:ok, items}
      {:error, %{status: s}} -> {:error, "API error (HTTP #{s})"}
      {:error, %Req.TransportError{reason: :timeout}} -> {:error, :timeout}
      {:error, _} -> {:error, :unavailable}
    end
  end

  defp fetch_promotions do
    case JargaAdmin.Api.list_promotions() do
      {:ok, %{"items" => items}} -> {:ok, items}
      {:ok, items} when is_list(items) -> {:ok, items}
      {:error, %{status: s}} -> {:error, "API error (HTTP #{s})"}
      {:error, %Req.TransportError{reason: :timeout}} -> {:error, :timeout}
      {:error, _} -> {:error, :unavailable}
    end
  end

  defp fetch_draft_orders do
    # The platform only has POST /v1/oms/draft-orders (create) and GET /:id.
    # A list endpoint does not yet exist — return empty gracefully.
    case JargaAdmin.Api.list_draft_orders() do
      {:ok, %{"items" => items}} -> {:ok, items}
      {:ok, items} when is_list(items) -> {:ok, items}
      {:error, %{status: s}} when s in [404, 405] -> {:ok, []}
      {:error, _} -> {:ok, []}
    end
  end

  # Unwrap a fetch result — falls back to empty list on error (for secondary data)
  defp unwrap_or_empty({:ok, items}), do: items
  defp unwrap_or_empty({:error, _}), do: []

  # Build an error spec with alert_banner and retry button
  defp error_spec(reason) do
    message =
      case reason do
        :timeout -> "Commerce API is not responding. Check your connection and try again."
        :unavailable -> "Commerce API is unavailable. Please retry in a moment."
        msg when is_binary(msg) -> "#{msg}. Please retry in a moment."
        _ -> "Commerce API is unavailable. Please retry in a moment."
      end

    %{
      "layout" => "full",
      "components" => [
        %{
          "type" => "alert_banner",
          "data" => %{
            "kind" => "error",
            "title" => "Data unavailable",
            "message" => message,
            "retry_event" => "retry_tab"
          }
        }
      ]
    }
  end

  # ── Row mappers ───────────────────────────────────────────────────────────

  defp order_row(o) do
    line_count = length(o["line_items"] || [])

    %{
      "id" => o["id"],
      "order_number" => "##{o["order_number"] || o["id"]}",
      "created_at" => format_date(o["created_at"]),
      "email" => o["email"] || "—",
      "items" => "#{line_count} item#{if line_count == 1, do: "", else: "s"}",
      "amount_total" => format_pence(o["amount_total"] || 0),
      "financial_status" => humanise(o["financial_status"]),
      "fulfillment_status" => humanise(o["fulfillment_status"])
    }
  end

  defp product_card(p) do
    variant_count = length(p["variants"] || [])

    min_price =
      (p["variants"] || [])
      |> Enum.map(&(&1["unit_amount"] || 0))
      |> Enum.min(fn -> 0 end)

    %{
      "id" => p["id"],
      "name" => p["title"],
      "vendor" => p["vendor"] || "",
      "type" => p["product_type"] || "",
      "price" => format_pence(min_price),
      "variants" => variant_count,
      "status" => p["status"] || "draft",
      "stock" => (p["variants"] || []) |> Enum.map(&(&1["inventory_qty"] || 0)) |> Enum.sum()
    }
  end

  defp customer_row(c) do
    name =
      [c["first_name"], c["last_name"]]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.trim()
      |> then(fn n -> if n == "", do: c["email"] || "—", else: n end)

    marketing_status = get_in(c, ["email_marketing_consent", "status"]) || "not_subscribed"

    location =
      cond do
        c["city"] && c["country_code"] -> "#{c["city"]}, #{c["country_code"]}"
        c["country_code"] -> c["country_code"]
        true -> "—"
      end

    avg =
      case c["average_order_value"] do
        nil -> "—"
        "0.00" -> "—"
        v when is_binary(v) -> "£#{v}"
        v when is_number(v) -> format_pence(round(v * 100))
        _ -> "—"
      end

    %{
      "id" => c["id"],
      "name" => name,
      "email" => c["email"] || "—",
      "marketing" => humanise(marketing_status),
      "location" => location,
      "avg_order_value" => avg,
      "created_at" => format_date(c["created_at"])
    }
  end

  defp promotion_row(p) do
    %{
      "id" => p["id"],
      "name" => p["name"] || p["title"] || "—",
      "discount_type" => humanise(p["discount_type"]),
      "status" => humanise(p["status"]),
      "use_count" => p["use_count"] || 0,
      "starts_at" => format_date(p["starts_at"]),
      "ends_at" => format_date(p["ends_at"])
    }
  end

  defp shipping_zone_row(z) do
    countries = z["countries"] || []

    %{
      "id" => z["id"],
      "name" => z["name"] || "—",
      "countries" => Enum.take(countries, 5) |> Enum.join(", "),
      "total_countries" => length(countries),
      "active" => if(z["active"], do: "Active", else: "Inactive")
    }
  end

  defp draft_order_row(d) do
    line_count = length(d["line_items"] || [])

    %{
      "id" => String.slice(d["id"] || "—", 0, 16) <> "…",
      "customer_id" => d["customer_id"] || "Guest",
      "items" => "#{line_count} item#{if line_count == 1, do: "", else: "s"}",
      "total" => format_pence(d["total"] || 0),
      "status" => humanise(d["status"] || "open"),
      "created_at" => format_date(d["created_at"])
    }
  end

  # ── Action bar component builder ──────────────────────────────────────────

  defp action_bar_component(resource) do
    label =
      case resource do
        "product" -> "Add product"
        "customer" -> "Add customer"
        "promotion" -> "Create discount"
        "shipping_zone" -> "Add zone"
        "order" -> "Create draft order"
        _ -> "Create #{resource}"
      end

    %{
      "type" => "action_bar",
      "data" => %{
        "actions" => [
          %{"label" => label, "event" => "show_create_form", "resource" => resource}
        ]
      }
    }
  end

  # ── Formatters ────────────────────────────────────────────────────────────

  defp format_pence(nil), do: "—"
  defp format_pence(0), do: "£0.00"

  defp format_pence(pence) when is_integer(pence) do
    pounds = div(pence, 100)
    cents = rem(pence, 100)
    "£#{pounds}.#{String.pad_leading("#{cents}", 2, "0")}"
  end

  defp format_pence(_), do: "—"

  defp format_date(nil), do: "—"

  defp format_date(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%d %b %Y")
      _ -> iso
    end
  end

  defp format_date(_), do: "—"

  defp humanise(nil), do: "—"

  defp humanise(s) when is_binary(s) do
    s |> String.replace("_", " ") |> String.split(" ") |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp humanise(other), do: inspect(other)
end
