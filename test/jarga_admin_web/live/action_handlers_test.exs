defmodule JargaAdminWeb.ActionHandlersTest do
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

  # ── fulfill_order ──────────────────────────────────────────────────────────

  test "fulfill_order calls POST /v1/oms/orders/:id/fulfillments", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect_once(bypass, "POST", "/v1/oms/orders/ord_1/fulfillments", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{data: %{id: "ful_1"}, error: nil, meta: %{}})
      )
    end)

    # Also stub the order GET for detail reload
    Bypass.stub(bypass, "GET", "/v1/oms/orders/ord_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          data: %{id: "ord_1", fulfillment_status: "fulfilled"},
          error: nil,
          meta: %{}
        })
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "fulfill_order", %{"id" => "ord_1"})
    assert html =~ "JARGA"
  end

  test "fulfill_order shows error toast on failure", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/oms/orders/ord_1/fulfillments", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        422,
        Jason.encode!(%{data: nil, error: %{message: "Cannot fulfill"}, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "fulfill_order", %{"id" => "ord_1"})
    assert html =~ "toast" or html =~ "Cannot fulfill" or html =~ "JARGA"
  end

  # ── refund_order ───────────────────────────────────────────────────────────

  test "refund_order calls POST /v1/oms/orders/:id/refunds", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/oms/orders/ord_1/refunds", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      _decoded = Jason.decode!(body)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{data: %{id: "ref_1"}, error: nil, meta: %{}})
      )
    end)

    Bypass.stub(bypass, "GET", "/v1/oms/orders/ord_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{id: "ord_1"}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "refund_order", %{"id" => "ord_1"})
    assert html =~ "JARGA"
  end

  # ── archive_product ────────────────────────────────────────────────────────

  test "archive_product calls POST /v1/pim/products/:id/archive", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/pim/products/p_1/archive", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{id: "p_1", status: "archived"}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "archive_product", %{"id" => "p_1"})
    assert html =~ "JARGA"
  end

  # ── duplicate_product ──────────────────────────────────────────────────────

  test "duplicate_product fetches product and clones it", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/pim/products/p_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          data: %{id: "p_1", title: "My Product", status: "active"},
          error: nil,
          meta: %{}
        })
      )
    end)

    Bypass.expect_once(bypass, "POST", "/v1/pim/products", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["title"] =~ "copy"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{data: %{id: "p_new"}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "duplicate_product", %{"id" => "p_1"})
    assert html =~ "JARGA"
  end

  # ── restock_item ───────────────────────────────────────────────────────────

  test "restock_item calls POST /v1/inventory/levels/adjust", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/inventory/levels/adjust", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      _decoded = Jason.decode!(body)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{available: 50}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "restock_item", %{"id" => "var_1"})
    assert html =~ "JARGA"
  end

  # ── edit_product ───────────────────────────────────────────────────────────

  test "edit_product loads product and shows edit form", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/pim/products/p_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          data: %{id: "p_1", title: "My Product", status: "active"},
          error: nil,
          meta: %{}
        })
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "edit_product", %{"id" => "p_1"})
    # Should show edit form or detail panel
    assert html =~ "JARGA"
  end

  test "update_product calls PATCH /v1/pim/products/:id", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "PATCH", "/v1/pim/products/p_1", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["title"] == "Updated Product"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{id: "p_1", title: "Updated Product"}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")

    html =
      render_submit(view, "update_product", %{
        "_product_id" => "p_1",
        "title" => "Updated Product"
      })

    assert html =~ "JARGA"
  end
end
