defmodule JargaAdmin.ApiTest do
  use ExUnit.Case, async: true

  alias JargaAdmin.Api

  setup do
    bypass = Bypass.open()
    Application.put_env(:jarga_admin, :api_url, "http://localhost:#{bypass.port}")
    Application.put_env(:jarga_admin, :api_key, "test-key-secret")
    {:ok, bypass: bypass}
  end

  test "get/2 returns {:ok, data} on 200", %{bypass: bypass} do
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
      |> Plug.Conn.send_resp(404, Jason.encode!(%{error: "not found"}))
    end)

    assert {:error, %{status: 404}} = Api.get("/v1/pim/products/999")
  end

  test "post/3 sends JSON body with HMAC headers", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/pim/products", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)

      assert decoded["name"] == "Test Product"

      # Verify HMAC headers present
      headers = Enum.into(conn.req_headers, %{})
      assert Map.has_key?(headers, "x-jarga-timestamp")
      assert Map.has_key?(headers, "x-jarga-signature")

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(201, Jason.encode!(%{id: "p_001", name: "Test Product"}))
    end)

    assert {:ok, %{"id" => "p_001"}} = Api.post("/v1/pim/products", %{name: "Test Product"})
  end

  test "put/3 sends JSON body", %{bypass: bypass} do
    Bypass.expect_once(bypass, "PUT", "/v1/pim/products/p_001", fn conn ->
      {:ok, _body, conn} = Plug.Conn.read_body(conn)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{id: "p_001", name: "Updated"}))
    end)

    assert {:ok, %{"id" => "p_001"}} = Api.put("/v1/pim/products/p_001", %{name: "Updated"})
  end

  test "delete/2 returns :ok on 200", %{bypass: bypass} do
    Bypass.expect_once(bypass, "DELETE", "/v1/pim/products/p_001", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{deleted: true}))
    end)

    assert {:ok, _} = Api.delete("/v1/pim/products/p_001")
  end

  test "agent_context/0 calls GET /v1/agent/context", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/agent/context", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          store: %{name: "My Store"},
          summary: %{total_orders: 42, total_revenue: 1234.56}
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
      |> Plug.Conn.send_resp(200, Jason.encode!(%{items: []}))
    end)

    assert {:ok, _} = Api.list_products(%{status: "published"})
  end

  test "list_orders/1 calls GET /v1/oms/orders", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/oms/orders", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{items: [], total: 0}))
    end)

    assert {:ok, _} = Api.list_orders()
  end

  test "get_analytics/1 calls GET /v1/analytics/sales", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/analytics/sales", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{revenue: 1234.56, orders: 14}))
    end)

    assert {:ok, %{"revenue" => 1234.56}} = Api.get_analytics()
  end

  test "returns {:error, reason} on network failure", %{bypass: bypass} do
    Bypass.down(bypass)

    assert {:error, _} = Api.get("/v1/pim/products")
  end

  test "HMAC signature is HMAC-SHA256 of timestamp:METHOD:path:body_hash", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/test", fn conn ->
      headers = Enum.into(conn.req_headers, %{})
      timestamp = headers["x-jarga-timestamp"]
      signature = headers["x-jarga-signature"]

      # Reconstruct expected signature
      api_key = "test-key-secret"
      body_hash = :crypto.hash(:sha256, "") |> Base.encode16(case: :lower)
      message = "#{timestamp}:GET:/v1/test:#{body_hash}"

      expected =
        :crypto.mac(:hmac, :sha256, api_key, message)
        |> Base.encode16(case: :lower)

      assert signature == expected

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{ok: true}))
    end)

    Api.get("/v1/test")
  end
end
