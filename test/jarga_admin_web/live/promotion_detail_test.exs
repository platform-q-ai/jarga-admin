defmodule JargaAdminWeb.PromotionDetailTest do
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

    promo = %{
      id: "promo_1",
      name: "Summer Sale",
      discount_type: "percentage",
      discount_value: 20,
      status: "active",
      starts_at: "2026-06-01",
      ends_at: "2026-08-31",
      use_count: 142
    }

    Bypass.stub(bypass, "GET", "/v1/promotions/campaigns/promo_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: promo, error: nil, meta: %{}}))
    end)

    Bypass.stub(bypass, "GET", "/v1/promotions/campaigns/promo_1/coupons", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          data: %{items: [%{code: "SUMMER20", uses: 10}]},
          error: nil,
          meta: %{}
        })
      )
    end)

    {:ok, bypass: bypass, promo: promo}
  end

  # ── view_promotion ────────────────────────────────────────────────────────

  test "view_promotion fetches and shows promotion detail", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "view_promotion", %{"id" => "promo_1"})
    assert html =~ "JARGA"
    assert html =~ "Summer Sale" or html =~ "promo_1"
  end

  # ── generate_coupons ──────────────────────────────────────────────────────

  test "generate_coupons calls POST /v1/promotions/coupons/generate", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect_once(bypass, "POST", "/v1/promotions/coupons/generate", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["campaign_id"] == "promo_1"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{data: %{codes: ["SUMMER20A", "SUMMER20B"]}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")

    html =
      render_submit(view, "generate_coupons", %{
        "_campaign_id" => "promo_1",
        "count" => "10",
        "prefix" => "SUMMER"
      })

    assert html =~ "JARGA"
  end

  # ── publish_promotion ─────────────────────────────────────────────────────

  test "publish_promotion calls POST /v1/promotions/campaigns/:id/publish", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect_once(bypass, "POST", "/v1/promotions/campaigns/promo_1/publish", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          data: %{id: "promo_1", status: "active"},
          error: nil,
          meta: %{}
        })
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "publish_promotion", %{"id" => "promo_1"})
    assert html =~ "JARGA"
  end
end
