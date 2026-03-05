defmodule JargaAdmin.TabStoreTest do
  use ExUnit.Case, async: false

  alias JargaAdmin.TabStore

  setup do
    TabStore.init()
    TabStore.reset_to_defaults()
    :ok
  end

  test "list/0 returns tabs sorted by position" do
    tabs = TabStore.list()
    positions = Enum.map(tabs, & &1.position)
    assert positions == Enum.sort(positions)
  end

  test "list/0 includes default tabs" do
    tabs = TabStore.list()
    ids = Enum.map(tabs, & &1.id)
    assert "dashboard" in ids
    assert "orders" in ids
  end

  test "pin/3 creates a new tab with an auto-generated id" do
    tab = TabStore.pin("Low Stock", "📦", nil)
    assert tab.id != nil
    assert tab.label == "Low Stock"
    assert tab.icon == "📦"
    assert tab.pinnable == true

    # Cleanup
    TabStore.unpin(tab.id)
  end

  test "unpin/1 removes a pinnable tab" do
    tab = TabStore.pin("Temp Tab", "🗑️", nil)
    assert :ok = TabStore.unpin(tab.id)
    assert {:error, :not_found} = TabStore.get(tab.id)
  end

  test "unpin/1 refuses to unpin non-pinnable tabs" do
    # Insert a synthetic non-pinnable tab directly
    :ets.insert(:jarga_tabs, {"fixed", %{id: "fixed", label: "Fixed", pinnable: false}})
    assert {:error, :not_pinnable} = TabStore.unpin("fixed")
  end

  test "rename/2 updates tab label" do
    tab = TabStore.pin("Old Name", "✏️", nil)
    assert {:ok, updated} = TabStore.rename(tab.id, "New Name")
    assert updated.label == "New Name"

    # Cleanup
    TabStore.unpin(tab.id)
  end

  test "duplicate/1 creates a copy with a new id" do
    tab = TabStore.pin("Original", "📋", nil)
    assert {:ok, copy} = TabStore.duplicate(tab.id)
    assert copy.id != tab.id
    assert copy.label == "Original (copy)"

    # Cleanup
    TabStore.unpin(tab.id)
    TabStore.unpin(copy.id)
  end

  test "update_spec/2 stores a ui_spec" do
    spec = %{"layout" => "full", "components" => []}
    tab = TabStore.pin("Spec Tab", "🧪", nil)
    assert {:ok, updated} = TabStore.update_spec(tab.id, spec)
    assert updated.ui_spec == spec

    # Cleanup
    TabStore.unpin(tab.id)
  end

  test "reorder/1 updates positions" do
    tabs = TabStore.list()
    ids = Enum.map(tabs, & &1.id)
    reversed = Enum.reverse(ids)
    assert :ok = TabStore.reorder(reversed)

    reordered = TabStore.list()
    new_ids = Enum.map(reordered, & &1.id)
    assert new_ids == reversed
  end

  test "first_run?/0 returns true when only the five default tabs exist" do
    # After reset_to_defaults only the five built-in tabs are present
    assert TabStore.first_run?()
  end

  test "first_run?/0 returns false after a user pins an extra tab" do
    TabStore.pin("Custom View")
    refute TabStore.first_run?()
  end
end
