defmodule JargaAdmin.TabStore do
  @moduledoc """
  ETS-backed persistent tab store for pinned views.

  Each tab has:
  - id (unique string)
  - label (display name)
  - icon (text marker)
  - ui_spec (the rendered UI spec map)
  - refresh_interval (:off | 30 | 60 | 300 seconds)
  - position (integer, for ordering)
  - pinnable (boolean)

  Default tabs are populated from the live Jarga Commerce API on startup.
  Tabs survive process restarts (ETS table is public and named).
  """

  require Logger

  @table :jarga_tabs

  @default_tabs [
    %{
      id: "dashboard",
      label: "Dashboard",
      icon: "",
      ui_spec: nil,
      refresh_interval: 60,
      position: 0,
      pinnable: true
    },
    %{
      id: "orders",
      label: "Orders",
      icon: "",
      ui_spec: nil,
      refresh_interval: 30,
      position: 1,
      pinnable: true
    },
    %{
      id: "products",
      label: "Products",
      icon: "",
      ui_spec: nil,
      refresh_interval: :off,
      position: 2,
      pinnable: true
    },
    %{
      id: "customers",
      label: "Customers",
      icon: "",
      ui_spec: nil,
      refresh_interval: :off,
      position: 3,
      pinnable: true
    },
    %{
      id: "promotions",
      label: "Promotions",
      icon: "",
      ui_spec: nil,
      refresh_interval: :off,
      position: 4,
      pinnable: true
    },
    %{
      id: "inventory",
      label: "Inventory",
      icon: "",
      ui_spec: nil,
      refresh_interval: 60,
      position: 5,
      pinnable: true
    },
    %{
      id: "analytics",
      label: "Analytics",
      icon: "",
      ui_spec: nil,
      refresh_interval: 300,
      position: 6,
      pinnable: true
    },
    %{
      id: "shipping",
      label: "Shipping",
      icon: "",
      ui_spec: nil,
      refresh_interval: :off,
      position: 7,
      pinnable: true
    },
    %{
      id: "draft_orders",
      label: "Draft Orders",
      icon: "",
      ui_spec: nil,
      refresh_interval: 60,
      position: 8,
      pinnable: true
    }
  ]

  # ── Initialization ────────────────────────────────────────────────────────

  @doc "Create the ETS table (call from Application supervisor)."
  def init do
    :ets.new(@table, [:set, :public, :named_table, {:read_concurrency, true}])
    seed_defaults()
    :ok
  rescue
    # Table already exists — patch any tabs that lost their spec
    ArgumentError ->
      reseed_defaults()
      :ok
  end

  @doc "Wipe and re-seed to defaults. Used in tests."
  def reset_to_defaults do
    :ets.delete_all_objects(@table)

    Enum.each(@default_tabs, fn tab ->
      put(%{tab | ui_spec: default_spec(tab.id)})
    end)

    :ok
  end

  @doc "List the IDs of all default tabs (for nav filtering etc)."
  def default_tab_ids do
    Enum.map(@default_tabs, & &1.id)
  end

  defp reseed_defaults do
    Enum.each(@default_tabs, fn tab ->
      case get(tab.id) do
        {:ok, %{ui_spec: nil} = existing} ->
          put(%{existing | ui_spec: default_spec(tab.id)})

        {:error, :not_found} ->
          # New default tab added since last boot — insert it
          put(%{tab | ui_spec: default_spec(tab.id)})

        _ ->
          :ok
      end
    end)
  end

  defp seed_defaults do
    if list() == [] do
      Enum.each(@default_tabs, fn tab ->
        put(%{tab | ui_spec: default_spec(tab.id)})
      end)
    end
  end

  # ── Default specs (built from live API) ───────────────────────────────────

  defp default_spec("dashboard") do
    orders = fetch_orders()
    products = fetch_products()
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

  defp default_spec("orders") do
    orders = fetch_orders()

    paid = Enum.count(orders, &(&1["financial_status"] == "paid"))
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

  defp default_spec("products") do
    products = fetch_products()

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

  defp default_spec("customers") do
    customers = fetch_customers()

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

  defp default_spec("promotions") do
    promotions = fetch_promotions()

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
        %{
          "type" => "promotion_list",
          "title" => "All promotions",
          "data" => %{"promotions" => Enum.map(promotions, &promotion_row/1)}
        }
      ]
    }
  end

  defp default_spec("inventory") do
    products = fetch_products()

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

  defp default_spec("analytics") do
    orders = fetch_orders()

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

  defp default_spec("shipping") do
    zones =
      case JargaAdmin.Api.list_shipping_zones() do
        {:ok, list} when is_list(list) -> list
        {:ok, %{"items" => items}} -> items
        _ -> []
      end

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
        %{
          "type" => "shipping_zones_table",
          "title" => "Shipping zones",
          "data" => %{"zones" => Enum.map(zones, &shipping_zone_row/1)}
        }
      ]
    }
  end

  defp default_spec("draft_orders") do
    draft_orders = fetch_draft_orders()

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

  defp default_spec(_), do: nil

  # ── API fetchers (graceful fallback to empty list on error) ───────────────

  defp fetch_orders do
    case JargaAdmin.Api.list_orders() do
      {:ok, %{"items" => items}} -> items
      {:ok, items} when is_list(items) -> items
      _ -> []
    end
  end

  defp fetch_products do
    case JargaAdmin.Api.list_products() do
      {:ok, %{"items" => items}} -> items
      {:ok, items} when is_list(items) -> items
      _ -> []
    end
  end

  defp fetch_customers do
    case JargaAdmin.Api.list_customers() do
      {:ok, %{"items" => items}} -> items
      {:ok, %{"data" => items}} when is_list(items) -> items
      {:ok, items} when is_list(items) -> items
      _ -> []
    end
  end

  defp fetch_promotions do
    case JargaAdmin.Api.list_promotions() do
      {:ok, %{"items" => items}} -> items
      {:ok, items} when is_list(items) -> items
      _ -> []
    end
  end

  defp fetch_draft_orders do
    # The platform only has POST /v1/oms/draft-orders (create) and GET /:id.
    # A list endpoint does not yet exist — return empty gracefully.
    case JargaAdmin.Api.list_draft_orders() do
      {:ok, %{"items" => items}} -> items
      {:ok, items} when is_list(items) -> items
      {:error, %{status: s}} when s in [404, 405] -> []
      _ -> []
    end
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

  # ── CRUD ──────────────────────────────────────────────────────────────────

  @doc "List all tabs sorted by position."
  def list do
    @table
    |> :ets.tab2list()
    |> Enum.map(fn {_id, tab} -> tab end)
    |> Enum.sort_by(& &1.position)
  end

  @doc "Get a tab by id."
  def get(id) do
    case :ets.lookup(@table, id) do
      [{^id, tab}] -> {:ok, tab}
      [] -> {:error, :not_found}
    end
  end

  @doc "Insert or replace a tab."
  def put(tab) do
    tab = Map.put_new(tab, :id, generate_id())
    :ets.insert(@table, {tab.id, tab})
    tab
  end

  @doc "Pin a new view as a tab."
  def pin(label, icon \\ "", ui_spec \\ nil) do
    max_pos = list() |> Enum.map(& &1.position) |> Enum.max(fn -> 0 end)

    tab = %{
      id: generate_id(),
      label: label,
      icon: icon,
      ui_spec: ui_spec,
      refresh_interval: :off,
      position: max_pos + 1,
      pinnable: true
    }

    put(tab)
    tab
  end

  @doc "Update a tab's fields."
  def update(id, changes) do
    case get(id) do
      {:ok, tab} ->
        updated = Map.merge(tab, changes)
        :ets.insert(@table, {id, updated})
        {:ok, updated}

      error ->
        error
    end
  end

  @doc "Rename a tab."
  def rename(id, new_label), do: update(id, %{label: new_label})

  @doc "Unpin (delete) a tab — only if pinnable."
  def unpin(id) do
    case get(id) do
      {:ok, %{pinnable: false}} ->
        {:error, :not_pinnable}

      {:ok, _tab} ->
        :ets.delete(@table, id)
        :ok

      error ->
        error
    end
  end

  @doc "Reorder tabs by supplying new list of ids."
  def reorder(ids) do
    ids
    |> Enum.with_index()
    |> Enum.each(fn {id, idx} -> update(id, %{position: idx}) end)

    :ok
  end

  @doc "Duplicate a tab."
  def duplicate(id) do
    case get(id) do
      {:ok, tab} ->
        max_pos = list() |> Enum.map(& &1.position) |> Enum.max(fn -> 0 end)
        new_tab = %{tab | id: generate_id(), label: tab.label <> " (copy)", position: max_pos + 1}
        put(new_tab)
        {:ok, new_tab}

      error ->
        error
    end
  end

  @doc "Update a tab's ui_spec (refresh)."
  def update_spec(id, ui_spec), do: update(id, %{ui_spec: ui_spec})

  @doc "True if only the default tabs exist (no user-pinned tabs yet)."
  def first_run? do
    default_ids =
      MapSet.new([
        "dashboard",
        "orders",
        "products",
        "customers",
        "promotions",
        "inventory",
        "analytics",
        "shipping",
        "draft_orders"
      ])

    list()
    |> Enum.map(& &1.id)
    |> MapSet.new()
    |> MapSet.subset?(default_ids)
  end

  # ── Private ───────────────────────────────────────────────────────────────

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
