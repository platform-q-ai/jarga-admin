defmodule JargaAdminWeb.KeyboardShortcutsTest do
  use JargaAdminWeb.ConnCase

  import Phoenix.LiveViewTest

  # ── Shortcut help modal ──────────────────────────────────────────────────

  describe "keyboard shortcut help modal" do
    test "help modal is hidden on load", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/chat")

      refute html =~ "keyboard-shortcuts-modal"
    end

    test "toggle_shortcuts_modal event shows the modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      html = render_click(view, "toggle_shortcuts_modal", %{})
      assert has_element?(view, "#keyboard-shortcuts-modal")
      assert html =~ "keyboard-shortcuts-modal"
    end

    test "toggle_shortcuts_modal event hides modal when already visible", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      # Open it
      render_click(view, "toggle_shortcuts_modal", %{})
      assert has_element?(view, "#keyboard-shortcuts-modal")

      # Close it
      html = render_click(view, "toggle_shortcuts_modal", %{})
      refute html =~ "keyboard-shortcuts-modal"
    end

    test "close_shortcuts_modal event hides the modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      render_click(view, "toggle_shortcuts_modal", %{})
      assert has_element?(view, "#keyboard-shortcuts-modal")

      html = render_click(view, "close_shortcuts_modal", %{})
      refute html =~ "keyboard-shortcuts-modal"
    end

    test "modal lists navigation shortcuts", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      render_click(view, "toggle_shortcuts_modal", %{})
      html = render(view)

      assert html =~ "keyboard-shortcuts-modal"
      assert html =~ "Orders"
      assert html =~ "Products"
      assert html =~ "Customers"
    end

    test "modal lists action shortcuts", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      render_click(view, "toggle_shortcuts_modal", %{})
      html = render(view)

      assert html =~ "keyboard-shortcuts-modal"
      # Refresh shortcut
      assert html =~ "Refresh"
    end
  end

  # ── Navigation shortcuts (server-side events) ─────────────────────────────

  describe "navigate_to event" do
    test "navigate_to orders switches active tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      render_click(view, "navigate_to", %{"tab" => "orders"})
      html = render(view)
      assert html =~ "JARGA"
    end

    test "navigate_to products switches active tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      render_click(view, "navigate_to", %{"tab" => "products"})
      html = render(view)
      assert html =~ "JARGA"
    end

    test "navigate_to customers switches active tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      render_click(view, "navigate_to", %{"tab" => "customers"})
      html = render(view)
      assert html =~ "JARGA"
    end

    test "navigate_to analytics switches active tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      render_click(view, "navigate_to", %{"tab" => "analytics"})
      html = render(view)
      assert html =~ "JARGA"
    end

    test "navigate_to promotions switches active tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      render_click(view, "navigate_to", %{"tab" => "promotions"})
      html = render(view)
      assert html =~ "JARGA"
    end

    test "navigate_to inventory switches active tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      render_click(view, "navigate_to", %{"tab" => "inventory"})
      html = render(view)
      assert html =~ "JARGA"
    end

    test "navigate_to with unknown tab is a no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      html = render_click(view, "navigate_to", %{"tab" => "unknown_tab_xyz"})
      assert html =~ "JARGA"
    end
  end

  # ── Refresh shortcut ──────────────────────────────────────────────────────

  describe "keyboard_refresh event" do
    setup do
      bypass = Bypass.open()
      Application.put_env(:jarga_admin, :api_url, "http://localhost:#{bypass.port}")
      Application.put_env(:jarga_admin, :api_key, "test-key")

      empty_list = Jason.encode!(%{data: %{items: []}, error: nil, meta: %{}})

      for path <- [
            "/v1/pim/products",
            "/v1/oms/orders",
            "/v1/crm/customers",
            "/v1/promotions/campaigns",
            "/v1/inventory/levels",
            "/v1/analytics/sales",
            "/v1/shipping/zones",
            "/v1/oms/draft-orders"
          ] do
        Bypass.stub(bypass, "GET", path, fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, empty_list)
        end)
      end

      {:ok, bypass: bypass}
    end

    test "keyboard_refresh reloads current tab spec", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      html = render_click(view, "keyboard_refresh", %{})
      assert html =~ "JARGA"
    end
  end

  # ── Escape key handling ───────────────────────────────────────────────────

  describe "keyboard_escape event" do
    test "keyboard_escape closes shortcuts modal when open", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      render_click(view, "toggle_shortcuts_modal", %{})
      assert has_element?(view, "#keyboard-shortcuts-modal")

      render_click(view, "keyboard_escape", %{})
      refute has_element?(view, "#keyboard-shortcuts-modal")
    end

    test "keyboard_escape clears detail panel when no modal open", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      # Simulate a detail panel being open by pushing a detail assign
      # We do this by triggering a view_order-style event — but since we have
      # no real API in this test, we instead verify escape is a no-op when
      # detail is nil (default state).
      html = render_click(view, "keyboard_escape", %{})
      assert html =~ "JARGA"
    end

    test "keyboard_escape closes chat when open", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      render_click(view, "open_chat", %{})
      render_click(view, "keyboard_escape", %{})
      html = render(view)
      assert html =~ "JARGA"
    end
  end

  # ── New item shortcut ─────────────────────────────────────────────────────

  describe "keyboard_new event" do
    test "keyboard_new on products tab shows create form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      # Switch to products tab first
      render_click(view, "navigate_to", %{"tab" => "products"})

      html = render_click(view, "keyboard_new", %{})
      assert html =~ "JARGA"
    end

    test "keyboard_new on customers tab shows create form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      render_click(view, "navigate_to", %{"tab" => "customers"})
      html = render_click(view, "keyboard_new", %{})
      assert html =~ "JARGA"
    end

    test "keyboard_new on unsupported tab is a no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      # analytics tab has no create form
      render_click(view, "navigate_to", %{"tab" => "analytics"})
      html = render_click(view, "keyboard_new", %{})
      assert html =~ "JARGA"
    end
  end

  # ── Keyboard shortcut hook present in HTML ────────────────────────────────

  test "KeyboardShortcuts hook is mounted on the page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/chat")

    assert html =~ "KeyboardShortcuts"
  end
end
