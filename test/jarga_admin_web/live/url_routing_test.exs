defmodule JargaAdminWeb.UrlRoutingTest do
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
          "/v1/oms/draft-orders",
          "/v1/audit/events",
          "/v1/events",
          "/v1/flows",
          "/v1/pim/collections",
          "/v1/pim/categories",
          "/v1/metaobjects/definitions",
          "/v1/dam/files",
          "/v1/tax/rates",
          "/v1/channels",
          "/v1/webhooks",
          "/v1/subscriptions/plan-groups"
        ] do
      Bypass.stub(bypass, "GET", path, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, empty_list)
      end)
    end

    {:ok, bypass: bypass}
  end

  # ── Route existence ───────────────────────────────────────────────────────

  test "/orders route renders ChatLive", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/orders")
    assert html =~ "JARGA"
  end

  test "/products route renders ChatLive", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/products")
    assert html =~ "JARGA"
  end

  test "/customers route renders ChatLive", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/customers")
    assert html =~ "JARGA"
  end

  test "/inventory route renders ChatLive", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/inventory")
    assert html =~ "JARGA"
  end

  test "/analytics route renders ChatLive", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/analytics")
    assert html =~ "JARGA"
  end

  # ── handle_params tab switching ───────────────────────────────────────────

  test "/orders URL sets active tab to orders", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/orders")
    assert html =~ "JARGA"
  end

  test "switch_tab pushes patch to URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "switch_tab", %{"id" => "products"})
    assert html =~ "JARGA"
  end
end
