defmodule JargaAdminWeb.SettingsSectionTest do
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
          "/v1/flows",
          "/v1/pim/collections",
          "/v1/pim/categories",
          "/v1/metaobjects/definitions",
          "/v1/dam/files",
          "/v1/tax/rates",
          "/v1/channels",
          "/v1/webhooks",
          "/v1/subscriptions/plan-groups"
        ] do
      Bypass.stub(bypass, "GET", path, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, empty_list)
      end)
    end

    {:ok, bypass: bypass}
  end

  # ── TabStore tabs ─────────────────────────────────────────────────────────

  test "tax tab exists in TabStore", _ctx do
    {:ok, tab} = JargaAdmin.TabStore.get("tax")
    assert tab.label == "Tax"
  end

  test "channels tab exists in TabStore", _ctx do
    {:ok, tab} = JargaAdmin.TabStore.get("channels")
    assert tab.label == "Channels"
  end

  test "webhooks tab exists in TabStore", _ctx do
    {:ok, tab} = JargaAdmin.TabStore.get("webhooks")
    assert tab.label == "Webhooks"
  end

  test "subscriptions tab exists in TabStore", _ctx do
    {:ok, tab} = JargaAdmin.TabStore.get("subscriptions")
    assert tab.label == "Subscriptions"
  end

  # ── TabSpecBuilder.build_spec ─────────────────────────────────────────────

  test "build_spec('tax') returns a spec", _ctx do
    result = JargaAdmin.TabSpecBuilder.build_spec("tax")
    assert is_map(result)
  end

  test "build_spec('channels') returns a spec", _ctx do
    result = JargaAdmin.TabSpecBuilder.build_spec("channels")
    assert is_map(result)
  end

  test "build_spec('webhooks') returns a spec", _ctx do
    result = JargaAdmin.TabSpecBuilder.build_spec("webhooks")
    assert is_map(result)
  end

  test "build_spec('subscriptions') returns a spec", _ctx do
    result = JargaAdmin.TabSpecBuilder.build_spec("subscriptions")
    assert is_map(result)
  end

  # ── LiveView navigation ───────────────────────────────────────────────────

  test "switch_tab to 'tax' renders without error", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "switch_tab", %{"id" => "tax"})
    assert html =~ "JARGA"
  end

  test "switch_tab to 'webhooks' renders without error", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "switch_tab", %{"id" => "webhooks"})
    assert html =~ "JARGA"
  end
end
