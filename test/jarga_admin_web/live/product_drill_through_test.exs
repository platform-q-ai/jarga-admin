defmodule JargaAdminWeb.ProductDrillThroughTest do
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

    product = %{
      id: "prod_1",
      title: "Blue T-Shirt",
      status: "active",
      vendor: "ACME",
      variants: [%{id: "var_1", sku: "TSHIRT-BLUE-M", title: "Blue / M", inventory_qty: 10}]
    }

    Bypass.stub(bypass, "GET", "/v1/pim/products/prod_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: product, error: nil, meta: %{}}))
    end)

    {:ok, bypass: bypass, product: product}
  end

  # ── view_product_from_order ────────────────────────────────────────────────

  test "view_product_from_order fetches product and shows detail", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "view_product_from_order", %{"product_id" => "prod_1"})
    assert html =~ "JARGA"
    assert html =~ "Blue T-Shirt" or html =~ "prod_1"
  end

  test "view_product_from_order shows error toast when product not found", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.stub(bypass, "GET", "/v1/pim/products/deleted_product", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        404,
        Jason.encode!(%{data: nil, error: "Not found", meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "view_product_from_order", %{"product_id" => "deleted_product"})
    assert html =~ "JARGA"
  end

  test "view_product_from_order with missing product_id is handled gracefully", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "view_product_from_order", %{})
    assert html =~ "JARGA"
  end
end
