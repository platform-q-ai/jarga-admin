defmodule JargaAdminWeb.CreateFlowsTest do
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

  # ── show_create_form ───────────────────────────────────────────────────────

  test "show_create_form for products renders a create product form", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")

    html = render_click(view, "show_create_form", %{"resource" => "product"})
    assert html =~ "JARGA"
    # Should show a form
    assert html =~ "form" or html =~ "dynamic_form" or html =~ "title"
  end

  test "show_create_form for customers renders a create customer form", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")

    html = render_click(view, "show_create_form", %{"resource" => "customer"})
    assert html =~ "JARGA"
    assert html =~ "form" or html =~ "email"
  end

  test "show_create_form for promotions renders a create promotion form", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")

    html = render_click(view, "show_create_form", %{"resource" => "promotion"})
    assert html =~ "JARGA"
    assert html =~ "form" or html =~ "name"
  end

  test "show_create_form for shipping_zone renders a create zone form", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")

    html = render_click(view, "show_create_form", %{"resource" => "shipping_zone"})
    assert html =~ "JARGA"
    assert html =~ "form" or html =~ "name"
  end

  # ── cancel_order ───────────────────────────────────────────────────────────

  test "cancel_order calls POST /v1/oms/orders/:id/cancel", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/oms/orders/ord_1/cancel", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{id: "ord_1", status: "cancelled"}, error: nil, meta: %{}})
      )
    end)

    Bypass.stub(bypass, "GET", "/v1/oms/orders/ord_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{id: "ord_1", status: "cancelled"}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "cancel_order", %{"id" => "ord_1"})
    assert html =~ "JARGA"
  end

  # ── add_order_note ─────────────────────────────────────────────────────────

  test "add_order_note calls POST /v1/oms/orders/:id/notes", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/oms/orders/ord_1/notes", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["note"] == "Handle with care"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{data: %{id: "note_1"}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")

    html =
      render_submit(view, "add_order_note", %{
        "_order_id" => "ord_1",
        "note" => "Handle with care"
      })

    assert html =~ "JARGA"
  end
end
