defmodule JargaAdminWeb.ShippingZoneDetailTest do
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

    zone = %{id: "zone_1", name: "Europe", countries: ["GB", "DE", "FR"], active: true}
    rates = [%{id: "rate_1", name: "Standard", price: 599, type: "flat"}]

    Bypass.stub(bypass, "GET", "/v1/shipping/zones/zone_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: zone, error: nil, meta: %{}}))
    end)

    Bypass.stub(bypass, "GET", "/v1/shipping/zones/zone_1/rates", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{items: rates}, error: nil, meta: %{}})
      )
    end)

    {:ok, bypass: bypass, zone: zone, rates: rates}
  end

  # ── view_shipping_zone ────────────────────────────────────────────────────

  test "view_shipping_zone renders zone detail with rates", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "view_shipping_zone", %{"id" => "zone_1"})
    assert html =~ "JARGA"
    assert html =~ "Europe" or html =~ "zone_1"
  end

  # ── add_shipping_rate ─────────────────────────────────────────────────────

  test "add_shipping_rate POSTs to /v1/shipping/zones/:id/rates", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/shipping/zones/zone_1/rates", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["name"] == "Express"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{data: %{id: "rate_2", name: "Express"}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")

    html =
      render_submit(view, "add_shipping_rate", %{
        "_zone_id" => "zone_1",
        "name" => "Express",
        "price" => "999",
        "type" => "flat"
      })

    assert html =~ "JARGA"
  end

  # ── delete_shipping_zone ──────────────────────────────────────────────────

  test "delete_shipping_zone DELETEs the zone", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "DELETE", "/v1/shipping/zones/zone_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{id: "zone_1"}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "delete_shipping_zone", %{"id" => "zone_1"})
    assert html =~ "JARGA"
  end
end
