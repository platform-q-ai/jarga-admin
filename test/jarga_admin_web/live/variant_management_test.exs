defmodule JargaAdminWeb.VariantManagementTest do
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

    Bypass.stub(bypass, "GET", "/v1/pim/products/prod_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          data: %{
            id: "prod_1",
            title: "Blue T-Shirt",
            variants: [%{id: "var_1", sku: "TS-BLUE-M", title: "Blue / M", price: 1999}]
          },
          error: nil,
          meta: %{}
        })
      )
    end)

    {:ok, bypass: bypass}
  end

  # ── add_variant ───────────────────────────────────────────────────────────

  test "add_variant calls POST /v1/pim/products/:id/variants", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/pim/products/prod_1/variants", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["sku"] == "TS-RED-M"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{data: %{id: "var_2", sku: "TS-RED-M"}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")

    html =
      render_submit(view, "add_variant", %{
        "_product_id" => "prod_1",
        "sku" => "TS-RED-M",
        "title" => "Red / M",
        "price" => "1999"
      })

    assert html =~ "JARGA"
  end

  # ── update_variant ────────────────────────────────────────────────────────

  test "update_variant calls PATCH /v1/pim/variants/:id", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "PATCH", "/v1/pim/variants/var_1", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["price"] == "2499"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{id: "var_1", price: 2499}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")

    html =
      render_submit(view, "update_variant", %{
        "_variant_id" => "var_1",
        "price" => "2499"
      })

    assert html =~ "JARGA"
  end

  # ── delete_variant ────────────────────────────────────────────────────────

  test "delete_variant calls DELETE /v1/pim/variants/:id", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "DELETE", "/v1/pim/variants/var_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{id: "var_1"}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "delete_variant", %{"id" => "var_1"})
    assert html =~ "JARGA"
  end

  # ── generate_variants ─────────────────────────────────────────────────────

  test "generate_variants calls POST /v1/pim/products/:id/options/generate-variants", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect_once(
      bypass,
      "POST",
      "/v1/pim/products/prod_1/options/generate-variants",
      fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          201,
          Jason.encode!(%{data: %{variants_created: 4}, error: nil, meta: %{}})
        )
      end
    )

    {:ok, view, _html} = live(conn, "/chat")

    html =
      render_click(view, "generate_variants", %{"product_id" => "prod_1"})

    assert html =~ "JARGA"
  end
end
