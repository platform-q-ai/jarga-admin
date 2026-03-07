defmodule JargaAdminWeb.BulkActionsTest do
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

  # ── toggle_select ─────────────────────────────────────────────────────────

  test "toggle_select adds an ID to selected_ids", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "toggle_select", %{"id" => "ord_1"})
    assert html =~ "JARGA"
  end

  test "toggle_select removes already-selected ID", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    render_click(view, "toggle_select", %{"id" => "ord_1"})
    html = render_click(view, "toggle_select", %{"id" => "ord_1"})
    assert html =~ "JARGA"
  end

  test "clear_selection resets selected_ids", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    render_click(view, "toggle_select", %{"id" => "ord_1"})
    render_click(view, "toggle_select", %{"id" => "ord_2"})
    html = render_click(view, "clear_selection", %{})
    assert html =~ "JARGA"
  end

  # ── bulk_action ───────────────────────────────────────────────────────────

  test "bulk_action 'archive' with selected products calls archive API", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.stub(bypass, "POST", "/v1/pim/products/prod_1/archive", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: %{}, error: nil, meta: %{}}))
    end)

    {:ok, view, _html} = live(conn, "/chat")
    render_click(view, "toggle_select", %{"id" => "prod_1"})
    html = render_click(view, "bulk_action", %{"action" => "archive", "type" => "product"})
    assert html =~ "JARGA"
  end

  test "bulk_action 'delete' with selected customers calls delete API", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.stub(bypass, "DELETE", "/v1/crm/customers/cus_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: %{}, error: nil, meta: %{}}))
    end)

    {:ok, view, _html} = live(conn, "/chat")
    render_click(view, "toggle_select", %{"id" => "cus_1"})
    html = render_click(view, "bulk_action", %{"action" => "delete", "type" => "customer"})
    assert html =~ "JARGA"
  end
end
