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
      refresh_interval: 10,
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
      refresh_interval: 30,
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
    },
    %{
      id: "audit",
      label: "Audit log",
      icon: "",
      ui_spec: nil,
      refresh_interval: :off,
      position: 9,
      pinnable: true
    },
    %{
      id: "events",
      label: "Event log",
      icon: "",
      ui_spec: nil,
      refresh_interval: :off,
      position: 10,
      pinnable: true
    },
    %{
      id: "flows",
      label: "Flows",
      icon: "",
      ui_spec: nil,
      refresh_interval: 60,
      position: 11,
      pinnable: true
    },
    %{
      id: "collections",
      label: "Collections",
      icon: "",
      ui_spec: nil,
      refresh_interval: :off,
      position: 12,
      pinnable: true
    },
    %{
      id: "categories",
      label: "Categories",
      icon: "",
      ui_spec: nil,
      refresh_interval: :off,
      position: 13,
      pinnable: true
    },
    %{
      id: "metaobjects",
      label: "Metaobjects",
      icon: "",
      ui_spec: nil,
      refresh_interval: :off,
      position: 14,
      pinnable: true
    },
    %{
      id: "files",
      label: "Files",
      icon: "",
      ui_spec: nil,
      refresh_interval: :off,
      position: 15,
      pinnable: true
    }
  ]

  # ── Initialization ────────────────────────────────────────────────────────

  @doc """
  Create the ETS table (call from Application supervisor).

  Tabs are inserted with `nil` ui_spec intentionally — specs are built lazily
  on first access via `get_or_build_spec/1`. This keeps Application.start/2
  fast regardless of backend availability.
  """
  def init do
    :ets.new(@table, [:set, :public, :named_table, {:read_concurrency, true}])
    seed_tab_metadata()
    :ok
  rescue
    # Table already exists — ensure any newly-added default tabs are present
    ArgumentError ->
      ensure_default_tabs()
      :ok
  end

  @doc """
  Return the ui_spec for a tab, building it from the live API if not yet cached.

  This is the primary entry point for the LiveView — call this instead of
  reading `tab.ui_spec` directly when displaying a tab.
  """
  def get_or_build_spec(tab_id) do
    case get(tab_id) do
      {:ok, %{ui_spec: nil}} ->
        spec = default_spec(tab_id)
        update(tab_id, %{ui_spec: spec})
        spec

      {:ok, %{ui_spec: spec}} ->
        spec

      _ ->
        nil
    end
  end

  @doc """
  Clears the cached spec for a tab so the next `get_or_build_spec/1` call
  will rebuild it from the API. Use this after a successful write operation
  to force a fresh data load.
  """
  def invalidate_spec(tab_id) do
    case get(tab_id) do
      {:ok, _tab} -> update(tab_id, %{ui_spec: nil})
      _ -> :ok
    end

    :ok
  end

  @doc """
  Invalidate all cached specs. Used in tests to prevent stale Bypass state leaking.
  Sets all specs to an empty placeholder so get_or_build_spec returns immediately
  without making API calls.
  """
  def invalidate_all_specs do
    empty_spec = %{"components" => [], "layout" => "full"}

    case :ets.info(@table) do
      :undefined ->
        :ok

      _ ->
        @table
        |> :ets.tab2list()
        |> Enum.each(fn {tab_id, _} -> update(tab_id, %{ui_spec: empty_spec}) end)

        :ok
    end
  end

  @doc """
  Wipe and re-seed to defaults. Used in tests.
  Builds all specs synchronously — acceptable in test context.
  """
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

  defp ensure_default_tabs do
    Enum.each(@default_tabs, fn tab ->
      case get(tab.id) do
        {:error, :not_found} ->
          # New default tab added since last boot — insert with nil spec (built lazily)
          put(%{tab | ui_spec: nil})

        _ ->
          :ok
      end
    end)
  end

  defp seed_tab_metadata do
    if list() == [] do
      Enum.each(@default_tabs, fn tab ->
        put(%{tab | ui_spec: nil})
      end)
    end
  end

  # ── Default specs — delegated to TabSpecBuilder ───────────────────────────

  defp default_spec(tab_id), do: JargaAdmin.TabSpecBuilder.build_spec(tab_id)

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
        "draft_orders",
        "audit",
        "events",
        "flows",
        "collections",
        "categories",
        "metaobjects",
        "files"
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
