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
      id: "chat",
      label: "Chat",
      icon: "",
      ui_spec: nil,
      refresh_interval: :off,
      position: 0,
      pinnable: false
    },
    %{
      id: "dashboard",
      label: "Dashboard",
      icon: "",
      ui_spec: nil,
      refresh_interval: 60,
      position: 1,
      pinnable: true
    },
    %{
      id: "orders",
      label: "Orders",
      icon: "",
      ui_spec: nil,
      refresh_interval: 30,
      position: 2,
      pinnable: true
    },
    %{
      id: "products",
      label: "Products",
      icon: "",
      ui_spec: nil,
      refresh_interval: :off,
      position: 3,
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

  # Patch any existing default tab that still has nil spec (e.g. old server run)
  defp reseed_defaults do
    ["dashboard", "orders", "products"]
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
    %{
      "layout" => "full",
      "components" => [
        %{
          "type" => "metric_grid",
          "data" => %{
            "metrics" => [
              %{
                "label" => "Revenue",
                "value" => "£1,247",
                "trend" => 12.4,
                "subtitle" => "Today"
              },
              %{"label" => "Orders", "value" => "14", "trend" => 7.7, "subtitle" => "Today"},
              %{
                "label" => "Avg Order Value",
                "value" => "£89.07",
                "trend" => 4.2,
                "subtitle" => "Today"
              },
              %{"label" => "Returns", "value" => "1", "trend" => -50.0, "subtitle" => "Today"}
            ]
          }
        },
        %{
          "type" => "data_table",
          "title" => "Recent Orders",
          "data" => %{
            "columns" => [
              %{"key" => "id", "label" => "Order"},
              %{"key" => "customer", "label" => "Customer"},
              %{"key" => "total", "label" => "Total"},
              %{"key" => "status", "label" => "Status"},
              %{"key" => "date", "label" => "Date"}
            ],
            "rows" => [
              %{
                "id" => "#1042",
                "customer" => "Sarah Mitchell",
                "total" => "£89.00",
                "status" => "pending",
                "date" => "4 Mar 2026"
              },
              %{
                "id" => "#1041",
                "customer" => "James Cooper",
                "total" => "£234.50",
                "status" => "fulfilled",
                "date" => "3 Mar 2026"
              },
              %{
                "id" => "#1040",
                "customer" => "Emma Walsh",
                "total" => "£45.00",
                "status" => "pending",
                "date" => "3 Mar 2026"
              },
              %{
                "id" => "#1039",
                "customer" => "Oliver Park",
                "total" => "£178.00",
                "status" => "fulfilled",
                "date" => "2 Mar 2026"
              }
            ]
          }
        },
        %{
          "type" => "data_table",
          "title" => "Low Stock Items",
          "data" => %{
            "columns" => [
              %{"key" => "name", "label" => "Product"},
              %{"key" => "stock", "label" => "Stock"},
              %{"key" => "reorder_at", "label" => "Reorder Point"}
            ],
            "rows" => [
              %{"name" => "Beeswax Candle Set", "stock" => "0", "reorder_at" => "10"},
              %{"name" => "Canvas Tote Bag", "stock" => "3", "reorder_at" => "15"},
              %{"name" => "Oak Serving Board", "stock" => "2", "reorder_at" => "5"}
            ]
          }
        }
      ]
    }
  end

  defp default_spec("orders") do
    %{
      "layout" => "full",
      "components" => [
        %{
          "type" => "data_table",
          "title" => "All Orders",
          "data" => %{
            "columns" => [
              %{"key" => "id", "label" => "Order"},
              %{"key" => "customer", "label" => "Customer"},
              %{"key" => "total", "label" => "Total"},
              %{"key" => "status", "label" => "Status"},
              %{"key" => "date", "label" => "Date"}
            ],
            "rows" => [
              %{
                "id" => "#1042",
                "customer" => "Sarah Mitchell",
                "total" => "£89.00",
                "status" => "pending",
                "date" => "4 Mar 2026"
              },
              %{
                "id" => "#1041",
                "customer" => "James Cooper",
                "total" => "£234.50",
                "status" => "fulfilled",
                "date" => "3 Mar 2026"
              },
              %{
                "id" => "#1040",
                "customer" => "Emma Walsh",
                "total" => "£45.00",
                "status" => "pending",
                "date" => "3 Mar 2026"
              },
              %{
                "id" => "#1039",
                "customer" => "Oliver Park",
                "total" => "£178.00",
                "status" => "fulfilled",
                "date" => "2 Mar 2026"
              },
              %{
                "id" => "#1038",
                "customer" => "Lily Chen",
                "total" => "£67.00",
                "status" => "pending",
                "date" => "2 Mar 2026"
              }
            ],
            "actions" => [%{"label" => "View", "event" => "view_order"}]
          }
        }
      ]
    }
  end

  defp default_spec("products") do
    %{
      "layout" => "full",
      "components" => [
        %{
          "type" => "data_table",
          "title" => "Products",
          "data" => %{
            "columns" => [
              %{"key" => "name", "label" => "Product"},
              %{"key" => "sku", "label" => "SKU"},
              %{"key" => "price", "label" => "Price"},
              %{"key" => "stock", "label" => "Stock"},
              %{"key" => "status", "label" => "Status"}
            ],
            "rows" => [
              %{
                "name" => "Leather Journal A5",
                "sku" => "LJ-A5-001",
                "price" => "£34.99",
                "stock" => "40",
                "status" => "published"
              },
              %{
                "name" => "Canvas Tote Bag",
                "sku" => "CTB-NAT-001",
                "price" => "£24.99",
                "stock" => "3",
                "status" => "published"
              },
              %{
                "name" => "Ceramic Mug — Slate",
                "sku" => "MUG-SL-001",
                "price" => "£18.00",
                "stock" => "120",
                "status" => "published"
              },
              %{
                "name" => "Oak Serving Board",
                "sku" => "OSB-001",
                "price" => "£42.00",
                "stock" => "2",
                "status" => "published"
              },
              %{
                "name" => "Beeswax Candle Set",
                "sku" => "BWC-SET-001",
                "price" => "£28.00",
                "stock" => "0",
                "status" => "draft"
              }
            ],
            "actions" => [%{"label" => "Edit", "event" => "edit_product"}]
          }
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
