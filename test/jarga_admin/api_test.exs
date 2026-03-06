defmodule JargaAdmin.ApiTest do
  use ExUnit.Case, async: true

  alias JargaAdmin.Api

  setup do
    bypass = Bypass.open()
    Application.put_env(:jarga_admin, :api_url, "http://localhost:#{bypass.port}")
    Application.put_env(:jarga_admin, :api_key, "test-key-secret")
    {:ok, bypass: bypass}
  end

  # ── Envelope unwrapping ────────────────────────────────────────────────────

  test "get/2 unwraps the {data: ...} envelope on 200", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/pim/products", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{items: [], count: 0}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, %{"items" => [], "count" => 0}} = Api.get("/v1/pim/products")
  end

  test "get/2 passes through non-enveloped response", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/pim/products", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{items: [], total: 0}))
    end)

    assert {:ok, %{"items" => [], "total" => 0}} = Api.get("/v1/pim/products")
  end

  test "get/2 returns {:error, reason} on 404", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/pim/products/999", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        404,
        Jason.encode!(%{data: nil, error: %{code: "not_found", message: "not found"}, meta: %{}})
      )
    end)

    assert {:error, %{status: 404}} = Api.get("/v1/pim/products/999")
  end

  # ── Bearer auth header ─────────────────────────────────────────────────────

  test "get/2 sends Authorization: Bearer header", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/pim/products", fn conn ->
      headers = Enum.into(conn.req_headers, %{})
      assert headers["authorization"] == "Bearer test-key-secret"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{items: []}))
    end)

    Api.get("/v1/pim/products")
  end

  test "post/3 sends JSON body with bearer auth", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/pim/products", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["name"] == "Test Product"

      headers = Enum.into(conn.req_headers, %{})
      assert headers["authorization"] == "Bearer test-key-secret"
      assert headers["content-type"] =~ "application/json"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{data: %{id: "p_001", name: "Test Product"}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, %{"id" => "p_001"}} = Api.post("/v1/pim/products", %{name: "Test Product"})
  end

  test "put/3 sends JSON body", %{bypass: bypass} do
    Bypass.expect_once(bypass, "PUT", "/v1/pim/products/p_001", fn conn ->
      {:ok, _body, conn} = Plug.Conn.read_body(conn)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{id: "p_001", name: "Updated"}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, %{"id" => "p_001"}} = Api.put("/v1/pim/products/p_001", %{name: "Updated"})
  end

  test "delete/2 returns {:ok, data} on 200", %{bypass: bypass} do
    Bypass.expect_once(bypass, "DELETE", "/v1/pim/products/p_001", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: %{deleted: true}, error: nil, meta: %{}}))
    end)

    assert {:ok, _} = Api.delete("/v1/pim/products/p_001")
  end

  test "returns {:error, reason} on network failure", %{bypass: bypass} do
    Bypass.down(bypass)

    assert {:error, _} = Api.get("/v1/pim/products")
  end

  # ── Convenience wrappers ───────────────────────────────────────────────────

  test "agent_context/0 calls GET /v1/agent/context", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/agent/context", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          data: %{store: %{name: "My Store"}, summary: %{total_orders: 42}},
          error: nil,
          meta: %{}
        })
      )
    end)

    assert {:ok, %{"store" => %{"name" => "My Store"}}} = Api.agent_context()
  end

  test "list_products/1 calls GET /v1/pim/products with params", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/pim/products", fn conn ->
      query = URI.decode_query(conn.query_string)
      assert query["status"] == "published"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: %{items: []}, error: nil, meta: %{}}))
    end)

    assert {:ok, _} = Api.list_products(%{status: "published"})
  end

  test "list_orders/1 calls GET /v1/oms/orders", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/oms/orders", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{items: [], count: 0}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, _} = Api.list_orders()
  end

  test "get_analytics/1 calls GET /v1/analytics/sales", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/analytics/sales", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{revenue: 1234_56, orders: 14}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, %{"revenue" => 1234_56}} = Api.get_analytics()
  end

  # ── Products (PIM) — new wrappers ──────────────────────────────────────────

  test "update_product/2 sends PATCH /v1/pim/products/:id", %{bypass: bypass} do
    Bypass.expect_once(bypass, "PATCH", "/v1/pim/products/p_001", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["title"] == "New Title"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{id: "p_001", title: "New Title"}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, %{"id" => "p_001"}} = Api.update_product("p_001", %{title: "New Title"})
  end

  test "delete_product/1 sends DELETE /v1/pim/products/:id", %{bypass: bypass} do
    Bypass.expect_once(bypass, "DELETE", "/v1/pim/products/p_001", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: %{deleted: true}, error: nil, meta: %{}}))
    end)

    assert {:ok, _} = Api.delete_product("p_001")
  end

  test "publish_product/1 sends POST /v1/pim/products/:id/publish", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/pim/products/p_001/publish", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{id: "p_001", status: "published"}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, %{"status" => "published"}} = Api.publish_product("p_001")
  end

  test "archive_product/1 sends POST /v1/pim/products/:id/archive", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/pim/products/p_001/archive", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{id: "p_001", status: "archived"}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, %{"status" => "archived"}} = Api.archive_product("p_001")
  end

  test "list_collections/0 calls GET /v1/pim/collections", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/pim/collections", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: %{items: []}, error: nil, meta: %{}}))
    end)

    assert {:ok, _} = Api.list_collections()
  end

  test "list_categories/0 calls GET /v1/pim/categories", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/pim/categories", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: %{items: []}, error: nil, meta: %{}}))
    end)

    assert {:ok, _} = Api.list_categories()
  end

  # ── Orders (OMS) — new wrappers ────────────────────────────────────────────

  test "create_fulfillment/2 sends POST /v1/oms/orders/:id/fulfillments", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/oms/orders/ord_1/fulfillments", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["tracking_number"] == "TRK123"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{data: %{id: "ful_1"}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, %{"id" => "ful_1"}} =
             Api.create_fulfillment("ord_1", %{tracking_number: "TRK123"})
  end

  test "create_refund/2 sends POST /v1/oms/orders/:id/refunds", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/oms/orders/ord_1/refunds", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["amount"] == 1000

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{data: %{id: "ref_1", amount: 1000}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, %{"id" => "ref_1"}} = Api.create_refund("ord_1", %{amount: 1000})
  end

  test "cancel_order/1 sends POST /v1/oms/orders/:id/cancel", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/oms/orders/ord_1/cancel", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{id: "ord_1", status: "cancelled"}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, %{"status" => "cancelled"}} = Api.cancel_order("ord_1")
  end

  test "transition_order_status/2 sends POST /v1/oms/orders/:id/status", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/oms/orders/ord_1/status", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["status"] == "fulfilled"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{id: "ord_1", status: "fulfilled"}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, %{"status" => "fulfilled"}} = Api.transition_order_status("ord_1", "fulfilled")
  end

  test "add_order_note/2 sends POST /v1/oms/orders/:id/notes", %{bypass: bypass} do
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

    assert {:ok, _} = Api.add_order_note("ord_1", "Handle with care")
  end

  # ── Customers (CRM) — new wrappers ────────────────────────────────────────

  test "create_customer/1 sends POST /v1/crm/customers", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/crm/customers", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["email"] == "test@example.com"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{data: %{id: "cus_1", email: "test@example.com"}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, %{"id" => "cus_1"}} = Api.create_customer(%{email: "test@example.com"})
  end

  test "update_customer/2 sends PATCH /v1/crm/customers/:id", %{bypass: bypass} do
    Bypass.expect_once(bypass, "PATCH", "/v1/crm/customers/cus_1", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["first_name"] == "Jane"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{id: "cus_1", first_name: "Jane"}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, %{"id" => "cus_1"}} = Api.update_customer("cus_1", %{first_name: "Jane"})
  end

  test "delete_customer/1 sends DELETE /v1/crm/customers/:id", %{bypass: bypass} do
    Bypass.expect_once(bypass, "DELETE", "/v1/crm/customers/cus_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: %{deleted: true}, error: nil, meta: %{}}))
    end)

    assert {:ok, _} = Api.delete_customer("cus_1")
  end

  # ── Promotions — new wrappers ──────────────────────────────────────────────

  test "update_promotion/2 sends PATCH /v1/promotions/campaigns/:id", %{bypass: bypass} do
    Bypass.expect_once(bypass, "PATCH", "/v1/promotions/campaigns/promo_1", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["name"] == "Summer Sale"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{id: "promo_1", name: "Summer Sale"}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, %{"id" => "promo_1"}} =
             Api.update_promotion("promo_1", %{name: "Summer Sale"})
  end

  test "publish_promotion/1 sends POST /v1/promotions/campaigns/:id/publish", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/promotions/campaigns/promo_1/publish", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{id: "promo_1", status: "active"}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, %{"status" => "active"}} = Api.publish_promotion("promo_1")
  end

  # ── Inventory — new wrappers ───────────────────────────────────────────────

  test "adjust_inventory/1 sends POST /v1/inventory/levels/adjust", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/inventory/levels/adjust", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["adjustment"] == 5

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{available: 15}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, _} =
             Api.adjust_inventory(%{variant_id: "var_1", location_id: "loc_1", adjustment: 5})
  end

  test "set_inventory/1 sends POST /v1/inventory/levels/set", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/inventory/levels/set", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["available"] == 20

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{available: 20}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, _} =
             Api.set_inventory(%{variant_id: "var_1", location_id: "loc_1", available: 20})
  end

  test "list_locations/0 calls GET /v1/inventory/locations", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/inventory/locations", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: %{items: []}, error: nil, meta: %{}}))
    end)

    assert {:ok, _} = Api.list_locations()
  end

  # ── Shipping — new wrappers ────────────────────────────────────────────────

  test "create_shipping_zone/1 sends POST /v1/shipping/zones", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/shipping/zones", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["name"] == "UK"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{data: %{id: "zone_1", name: "UK"}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, %{"id" => "zone_1"}} = Api.create_shipping_zone(%{name: "UK"})
  end

  test "update_shipping_zone/2 sends PATCH /v1/shipping/zones/:id", %{bypass: bypass} do
    Bypass.expect_once(bypass, "PATCH", "/v1/shipping/zones/zone_1", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["name"] == "UK Zone"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{id: "zone_1", name: "UK Zone"}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, %{"id" => "zone_1"}} = Api.update_shipping_zone("zone_1", %{name: "UK Zone"})
  end

  test "delete_shipping_zone/1 sends DELETE /v1/shipping/zones/:id", %{bypass: bypass} do
    Bypass.expect_once(bypass, "DELETE", "/v1/shipping/zones/zone_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: %{deleted: true}, error: nil, meta: %{}}))
    end)

    assert {:ok, _} = Api.delete_shipping_zone("zone_1")
  end

  test "create_shipping_rate/2 sends POST /v1/shipping/zones/:id/rates", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/shipping/zones/zone_1/rates", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["name"] == "Standard"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{data: %{id: "rate_1", name: "Standard"}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, %{"id" => "rate_1"}} = Api.create_shipping_rate("zone_1", %{name: "Standard"})
  end

  # ── Tax — new wrappers ────────────────────────────────────────────────────

  test "list_tax_rates/0 calls GET /v1/tax/rates", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/tax/rates", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: %{items: []}, error: nil, meta: %{}}))
    end)

    assert {:ok, _} = Api.list_tax_rates()
  end

  test "create_tax_rate/1 sends POST /v1/tax/rates", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/tax/rates", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["rate"] == 20

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{data: %{id: "tax_1", rate: 20}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, %{"id" => "tax_1"}} = Api.create_tax_rate(%{rate: 20, name: "VAT"})
  end

  # ── Webhooks — new wrappers ───────────────────────────────────────────────

  test "list_webhooks/0 calls GET /v1/webhooks", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/webhooks", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: %{items: []}, error: nil, meta: %{}}))
    end)

    assert {:ok, _} = Api.list_webhooks()
  end

  test "create_webhook/1 sends POST /v1/webhooks", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/webhooks", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["url"] == "https://example.com/hook"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{data: %{id: "wh_1"}, error: nil, meta: %{}})
      )
    end)

    assert {:ok, %{"id" => "wh_1"}} =
             Api.create_webhook(%{url: "https://example.com/hook", topic: "order.created"})
  end

  # ── Channels — new wrappers ───────────────────────────────────────────────

  test "list_channels/0 calls GET /v1/channels", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/channels", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: %{items: []}, error: nil, meta: %{}}))
    end)

    assert {:ok, _} = Api.list_channels()
  end

  # ── Metaobjects — new wrappers ────────────────────────────────────────────

  test "list_metaobject_definitions/0 calls GET /v1/metaobjects/definitions", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/metaobjects/definitions", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: %{items: []}, error: nil, meta: %{}}))
    end)

    assert {:ok, _} = Api.list_metaobject_definitions()
  end

  # ── Subscriptions — new wrappers ──────────────────────────────────────────

  test "list_subscription_contracts/0 calls GET /v1/subscriptions/contracts", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/subscriptions/contracts", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: %{items: []}, error: nil, meta: %{}}))
    end)

    assert {:ok, _} = Api.list_subscription_contracts()
  end
end
