defmodule JargaAdmin.TabSpecBuilderTest do
  use ExUnit.Case, async: true

  alias JargaAdmin.TabSpecBuilder

  setup do
    bypass = Bypass.open()
    Application.put_env(:jarga_admin, :api_url, "http://localhost:#{bypass.port}")
    Application.put_env(:jarga_admin, :api_key, "test-key")
    {:ok, bypass: bypass}
  end

  # ── Successful builds ──────────────────────────────────────────────────────

  test "build_spec/1 for orders returns a data_table spec on success", %{bypass: bypass} do
    Bypass.stub(bypass, "GET", "/v1/oms/orders", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          data: %{
            items: [
              %{
                id: "ord_1",
                order_number: 1001,
                email: "test@example.com",
                amount_total: 9999,
                financial_status: "paid",
                fulfillment_status: "unfulfilled",
                line_items: []
              }
            ]
          },
          error: nil,
          meta: %{}
        })
      )
    end)

    spec = TabSpecBuilder.build_spec("orders")
    assert is_map(spec)
    assert spec["components"] != nil

    component_types = Enum.map(spec["components"], & &1["type"])
    assert "data_table" in component_types
  end

  # ── Error handling — API failures produce alert_banner ────────────────────

  test "build_spec/1 for orders shows alert_banner when API returns error", %{bypass: bypass} do
    Bypass.stub(bypass, "GET", "/v1/oms/orders", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        500,
        Jason.encode!(%{data: nil, error: %{message: "Internal error"}, meta: %{}})
      )
    end)

    spec = TabSpecBuilder.build_spec("orders")
    assert is_map(spec)

    component_types = Enum.map(spec["components"], & &1["type"])
    assert "alert_banner" in component_types

    alert = Enum.find(spec["components"], &(&1["type"] == "alert_banner"))
    assert alert["data"]["kind"] == "error"
    assert is_binary(alert["data"]["message"])
  end

  test "build_spec/1 for products shows alert_banner when API is unreachable", %{bypass: bypass} do
    Bypass.down(bypass)

    spec = TabSpecBuilder.build_spec("products")
    assert is_map(spec)

    component_types = Enum.map(spec["components"], & &1["type"])
    assert "alert_banner" in component_types

    alert = Enum.find(spec["components"], &(&1["type"] == "alert_banner"))
    assert alert["data"]["kind"] == "error"

    assert alert["data"]["message"] =~ "not responding" or
             alert["data"]["message"] =~ "unavailable"
  end

  test "build_spec/1 for customers shows alert_banner when API fails", %{bypass: bypass} do
    Bypass.stub(bypass, "GET", "/v1/crm/customers", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(503, Jason.encode!(%{error: "Service Unavailable"}))
    end)

    spec = TabSpecBuilder.build_spec("customers")
    component_types = Enum.map(spec["components"], & &1["type"])
    assert "alert_banner" in component_types
  end

  test "build_spec/1 alert_banner includes retry action", %{bypass: bypass} do
    Bypass.stub(bypass, "GET", "/v1/oms/orders", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(503, Jason.encode!(%{error: "unavailable"}))
    end)

    spec = TabSpecBuilder.build_spec("orders")
    alert = Enum.find(spec["components"], &(&1["type"] == "alert_banner"))

    refute is_nil(alert)
    assert alert["data"]["retry_event"] == "retry_tab"
  end

  test "build_spec/1 for dashboard degrades gracefully when API fails", %{bypass: bypass} do
    Bypass.stub(bypass, "GET", "/v1/oms/orders", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(500, Jason.encode!(%{error: "Internal error"}))
    end)

    Bypass.stub(bypass, "GET", "/v1/pim/products", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(500, Jason.encode!(%{error: "Internal error"}))
    end)

    spec = TabSpecBuilder.build_spec("dashboard")
    assert is_map(spec)
    # Dashboard uses multiple APIs — should still render with partial data or error state
    assert spec["components"] != nil
  end
end
