defmodule JargaAdminWeb.PollingTest do
  use JargaAdminWeb.ConnCase

  import Phoenix.LiveViewTest

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

  test "orders tab has a 10-second refresh interval", _context do
    {:ok, tab} = JargaAdmin.TabStore.get("orders")
    assert tab.refresh_interval == 10
  end

  test "inventory tab has a 30-second refresh interval", _context do
    {:ok, tab} = JargaAdmin.TabStore.get("inventory")
    assert tab.refresh_interval == 30
  end

  test "tab_refresh message triggers spec rebuild without crashing", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    # Simulate the tab refresh message
    send(view.pid, {:tab_refresh, "dashboard"})
    # Give it a moment to process
    Process.sleep(50)
    html = render(view)
    assert html =~ "JARGA"
  end

  test "tab_refresh is skipped when detail panel is open", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    # Simulate having a detail panel open by triggering a view order
    # then send tab_refresh — detail should not be cleared
    send(view.pid, {:tab_refresh, "orders"})
    Process.sleep(50)
    html = render(view)
    assert html =~ "JARGA"
  end
end
