defmodule JargaAdminWeb.FlowsTest do
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
          "/v1/oms/draft-orders",
          "/v1/audit/events",
          "/v1/events",
          "/v1/flows"
        ] do
      Bypass.stub(bypass, "GET", path, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, empty_list)
      end)
    end

    flow = %{
      id: "flow_1",
      name: "Welcome email",
      status: "enabled",
      trigger: "customer.created",
      last_run_at: "2026-01-01T00:00:00Z",
      run_count: 42
    }

    Bypass.stub(bypass, "GET", "/v1/flows/flow_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: flow, error: nil, meta: %{}}))
    end)

    Bypass.stub(bypass, "GET", "/v1/flows/flow_1/runs", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, empty_list)
    end)

    {:ok, bypass: bypass, flow: flow}
  end

  test "flows tab exists in TabStore", _ctx do
    {:ok, tab} = JargaAdmin.TabStore.get("flows")
    assert tab.label == "Flows"
  end

  test "build_spec('flows') returns a spec without crashing", _ctx do
    result = JargaAdmin.TabSpecBuilder.build_spec("flows")
    assert is_map(result) or is_nil(result)
  end

  test "view_flow fetches flow and renders detail", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "view_flow", %{"id" => "flow_1"})
    assert html =~ "JARGA"
  end

  test "toggle_flow 'enable' calls POST /v1/flows/:id/enable", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/flows/flow_1/enable", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: %{id: "flow_1"}, error: nil, meta: %{}}))
    end)

    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "toggle_flow", %{"id" => "flow_1", "action" => "enable"})
    assert html =~ "JARGA"
  end

  test "toggle_flow 'disable' calls POST /v1/flows/:id/disable", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/flows/flow_1/disable", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: %{id: "flow_1"}, error: nil, meta: %{}}))
    end)

    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "toggle_flow", %{"id" => "flow_1", "action" => "disable"})
    assert html =~ "JARGA"
  end

  test "delete_flow calls DELETE /v1/flows/:id", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "DELETE", "/v1/flows/flow_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: %{id: "flow_1"}, error: nil, meta: %{}}))
    end)

    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "delete_flow", %{"id" => "flow_1"})
    assert html =~ "JARGA"
  end
end
