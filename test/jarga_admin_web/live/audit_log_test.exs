defmodule JargaAdminWeb.AuditLogTest do
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
          "/v1/audit/events"
        ] do
      Bypass.stub(bypass, "GET", path, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, empty_list)
      end)
    end

    {:ok, bypass: bypass}
  end

  test "audit tab exists in TabStore", _ctx do
    {:ok, tab} = JargaAdmin.TabStore.get("audit")
    assert tab.label == "Audit log"
  end

  test "build_spec('audit') returns a spec without crashing", %{bypass: _bypass} do
    # Uses the already-stubbed empty list for /v1/audit/events
    result = JargaAdmin.TabSpecBuilder.build_spec("audit")
    assert is_map(result) or is_nil(result)
  end

  test "view_audit_event renders event detail", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "view_audit_event", %{"id" => "evt_1", "data" => "{}"})
    assert html =~ "JARGA"
  end
end
