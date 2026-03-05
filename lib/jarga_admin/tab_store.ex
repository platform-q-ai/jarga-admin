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
      icon: "💬",
      ui_spec: nil,
      refresh_interval: :off,
      position: 0,
      pinnable: false
    },
    %{
      id: "dashboard",
      label: "Dashboard",
      icon: "📊",
      ui_spec: nil,
      refresh_interval: 60,
      position: 1,
      pinnable: true
    },
    %{
      id: "orders",
      label: "Orders",
      icon: "📦",
      ui_spec: nil,
      refresh_interval: 30,
      position: 2,
      pinnable: true
    },
    %{
      id: "products",
      label: "Products",
      icon: "🏷️",
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
    # table already exists
    ArgumentError -> :ok
  end

  defp seed_defaults do
    if list() == [] do
      Enum.each(@default_tabs, &put/1)
    end
  end

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
  def pin(label, icon \\ "📌", ui_spec \\ nil) do
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

  @doc "True if no user-pinned tabs exist (first-run detection)."
  def first_run? do
    list()
    |> Enum.filter(& &1.pinnable)
    |> Enum.all?(fn t -> t.ui_spec == nil end)
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Private
  # ──────────────────────────────────────────────────────────────────────────

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
