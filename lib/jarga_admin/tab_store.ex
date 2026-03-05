defmodule JargaAdmin.TabStore do
  @moduledoc """
  ETS-backed persistent tab store for pinned views.

  Each tab has:
  - id (unique string)
  - label (display name)
  - icon (emoji)
  - ui_spec (the rendered UI spec map)
  - refresh_interval (:off | 30 | 60 | 300 seconds)
  - position (integer, for ordering)
  - pinnable (boolean — Chat tab is not unpinnable)

  Tabs survive process restarts (ETS table is public and named).
  For true persistence across server restarts, see the :dets backend option.
  """

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
    }
  ]

  # ──────────────────────────────────────────────────────────────────────────
  # Initialization
  # ──────────────────────────────────────────────────────────────────────────

  @doc "Create the ETS table (call from Application supervisor)."
  def init do
    :ets.new(@table, [:set, :public, :named_table, {:read_concurrency, true}])
    seed_defaults()
    :ok
  rescue
    # table already exists — re-seed any default tabs that are missing a spec
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

  # Patch any existing default tab that still has nil spec (e.g. old server run)
  defp reseed_defaults do
    ["dashboard", "orders", "products", "customers", "promotions"]
    |> Enum.each(fn id ->
      case get(id) do
        {:ok, %{ui_spec: nil} = tab} -> put(%{tab | ui_spec: default_spec(id)})
        _ -> :ok
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

  # Pre-baked UI specs so default tabs show data immediately (no agent call needed)
  defp default_spec("dashboard") do
    orders = JargaAdmin.MockData.orders()
    recent = Enum.take(orders, 5)

    %{
      "layout" => "full",
      "components" => [
        %{
          "type" => "stat_bar",
          "data" => %{
            "stats" => [
              %{
                "label" => "Revenue today",
                "value" => "£1,247",
                "delta" => "↑ 12% vs yesterday",
                "delta_up" => true
              },
              %{
                "label" => "Orders today",
                "value" => "14",
                "delta" => "↑ 8% vs yesterday",
                "delta_up" => true
              },
              %{
                "label" => "Avg order value",
                "value" => "£89.07",
                "delta" => "↑ 4% vs yesterday",
                "delta_up" => true
              },
              %{"label" => "Pending fulfilment", "value" => "3", "delta" => nil}
            ]
          }
        },
        %{
          "type" => "chart",
          "title" => "Revenue — last 7 days",
          "data" => %{
            "type" => "line",
            "labels" => ["26 Feb", "27 Feb", "28 Feb", "1 Mar", "2 Mar", "3 Mar", "4 Mar"],
            "datasets" => [
              %{
                "label" => "Revenue",
                "data" => [890, 1240, 760, 1100, 980, 1380, 1247],
                "borderColor" => "#181512",
                "backgroundColor" => "rgba(24,21,18,0.06)",
                "tension" => 0.4,
                "fill" => true
              }
            ]
          }
        },
        %{
          "type" => "data_table",
          "title" => "Recent orders",
          "data" => %{
            "columns" => [
              %{"key" => "id", "label" => "Order"},
              %{"key" => "customer", "label" => "Customer"},
              %{"key" => "total", "label" => "Total"},
              %{"key" => "status", "label" => "Status"},
              %{"key" => "date", "label" => "Date"}
            ],
            "rows" =>
              Enum.map(recent, &Map.take(&1, ["id", "customer", "total", "status", "date"])),
            "on_row_click" => "view_order"
          }
        },
        %{
          "type" => "inventory_table",
          "title" => "Low stock",
          "data" => %{
            "rows" => [
              %{
                "id" => "prod_002",
                "name" => "Canvas Tote Bag",
                "sku" => "CTB-NAT-001",
                "stock" => 3,
                "reorder_at" => 20
              },
              %{
                "id" => "prod_004",
                "name" => "Oak Serving Board",
                "sku" => "OSB-LRG-001",
                "stock" => 2,
                "reorder_at" => 8
              },
              %{
                "id" => "prod_005",
                "name" => "Beeswax Candle Set",
                "sku" => "BWC-SET-3",
                "stock" => 0,
                "reorder_at" => 15
              },
              %{
                "id" => "prod_008",
                "name" => "Linen Notebook Cover",
                "sku" => "LNC-A5-001",
                "stock" => 8,
                "reorder_at" => 12
              }
            ],
            "on_restock" => "restock_item"
          }
        }
      ]
    }
  end

  defp default_spec("orders") do
    orders = JargaAdmin.MockData.orders()

    %{
      "layout" => "full",
      "components" => [
        %{
          "type" => "stat_bar",
          "data" => %{
            "stats" => [
              %{"label" => "Total orders", "value" => "#{length(orders)}"},
              %{
                "label" => "Pending",
                "value" => "#{Enum.count(orders, &(&1["status"] == "pending"))}",
                "delta" => nil
              },
              %{
                "label" => "Fulfilled",
                "value" => "#{Enum.count(orders, &(&1["status"] == "fulfilled"))}",
                "delta" => nil
              },
              %{
                "label" => "Refunded",
                "value" => "#{Enum.count(orders, &(&1["status"] == "refunded"))}",
                "delta" => nil
              }
            ]
          }
        },
        %{
          "type" => "data_table",
          "title" => "All orders",
          "data" => %{
            "columns" => [
              %{"key" => "id", "label" => "Order"},
              %{"key" => "customer", "label" => "Customer"},
              %{"key" => "total", "label" => "Total"},
              %{"key" => "fulfillment", "label" => "Fulfilment"},
              %{"key" => "payment", "label" => "Payment"},
              %{"key" => "date", "label" => "Date"}
            ],
            "rows" =>
              Enum.map(
                orders,
                &Map.take(&1, ["id", "customer", "total", "fulfillment", "payment", "date"])
              ),
            "on_row_click" => "view_order"
          }
        }
      ]
    }
  end

  defp default_spec("products") do
    products = JargaAdmin.MockData.products()
    low_stock = Enum.filter(products, &(&1["stock"] <= &1["reorder_at"]))

    %{
      "layout" => "full",
      "components" => [
        %{
          "type" => "stat_bar",
          "data" => %{
            "stats" => [
              %{"label" => "Total products", "value" => "#{length(products)}"},
              %{
                "label" => "Published",
                "value" => "#{Enum.count(products, &(&1["status"] == "published"))}"
              },
              %{
                "label" => "Draft",
                "value" => "#{Enum.count(products, &(&1["status"] == "draft"))}"
              },
              %{"label" => "Low / out of stock", "value" => "#{length(low_stock)}"}
            ]
          }
        },
        %{
          "type" => "product_grid",
          "title" => "All products",
          "data" => %{
            "products" => products,
            "on_click" => "view_product"
          }
        }
      ]
    }
  end

  defp default_spec("customers") do
    customers = JargaAdmin.MockData.customers()

    %{
      "layout" => "full",
      "components" => [
        %{
          "type" => "stat_bar",
          "data" => %{
            "stats" => [
              %{"label" => "Total customers", "value" => "#{length(customers)}"},
              %{
                "label" => "VIP",
                "value" => "#{Enum.count(customers, &(&1["segment"] == "VIP"))}"
              },
              %{
                "label" => "Loyal",
                "value" => "#{Enum.count(customers, &(&1["segment"] == "Loyal"))}"
              },
              %{
                "label" => "New (30d)",
                "value" => "#{Enum.count(customers, &(&1["segment"] == "New"))}"
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
              %{"key" => "ltv", "label" => "Lifetime value"},
              %{"key" => "order_count", "label" => "Orders"},
              %{"key" => "segment", "label" => "Segment"},
              %{"key" => "joined", "label" => "Joined"}
            ],
            "rows" =>
              Enum.map(
                customers,
                &Map.take(&1, ["id", "name", "email", "ltv", "order_count", "segment", "joined"])
              ),
            "on_row_click" => "view_customer"
          }
        }
      ]
    }
  end

  defp default_spec("promotions") do
    promotions = JargaAdmin.MockData.promotions()

    %{
      "layout" => "full",
      "components" => [
        %{
          "type" => "stat_bar",
          "data" => %{
            "stats" => [
              %{
                "label" => "Active promotions",
                "value" => "#{Enum.count(promotions, &(&1["status"] == "active"))}"
              },
              %{
                "label" => "Total uses",
                "value" => "#{Enum.sum(Enum.map(promotions, &(&1["uses"] || 0)))}"
              },
              %{"label" => "Discount issued", "value" => "£10,124"},
              %{
                "label" => "Expired",
                "value" => "#{Enum.count(promotions, &(&1["status"] == "expired"))}"
              }
            ]
          }
        },
        %{
          "type" => "promotion_list",
          "title" => "All promotions",
          "data" => %{"promotions" => promotions}
        }
      ]
    }
  end

  defp default_spec(_), do: nil

  # ──────────────────────────────────────────────────────────────────────────
  # CRUD
  # ──────────────────────────────────────────────────────────────────────────

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
  def rename(id, new_label) do
    update(id, %{label: new_label})
  end

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
    |> Enum.each(fn {id, idx} ->
      update(id, %{position: idx})
    end)

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
  def update_spec(id, ui_spec) do
    update(id, %{ui_spec: ui_spec})
  end

  @doc "True if only the default tabs exist (no user-pinned tabs yet)."
  def first_run? do
    default_ids = MapSet.new(["chat", "dashboard", "orders", "products"])

    list()
    |> Enum.map(& &1.id)
    |> MapSet.new()
    |> MapSet.equal?(default_ids)
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Private
  # ──────────────────────────────────────────────────────────────────────────

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
