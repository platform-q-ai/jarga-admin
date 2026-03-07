defmodule JargaAdminWeb.ContentSectionTest do
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
          "/v1/dam/files"
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

  test "collections tab exists in TabStore", _ctx do
    {:ok, tab} = JargaAdmin.TabStore.get("collections")
    assert tab.label == "Collections"
  end

  test "categories tab exists in TabStore", _ctx do
    {:ok, tab} = JargaAdmin.TabStore.get("categories")
    assert tab.label == "Categories"
  end

  test "metaobjects tab exists in TabStore", _ctx do
    {:ok, tab} = JargaAdmin.TabStore.get("metaobjects")
    assert tab.label == "Metaobjects"
  end

  test "files tab exists in TabStore", _ctx do
    {:ok, tab} = JargaAdmin.TabStore.get("files")
    assert tab.label == "Files"
  end

  # ── TabSpecBuilder.build_spec ─────────────────────────────────────────────

  test "build_spec('collections') returns a spec", _ctx do
    result = JargaAdmin.TabSpecBuilder.build_spec("collections")
    assert is_map(result)
  end

  test "build_spec('categories') returns a spec", _ctx do
    result = JargaAdmin.TabSpecBuilder.build_spec("categories")
    assert is_map(result)
  end

  test "build_spec('metaobjects') returns a spec", _ctx do
    result = JargaAdmin.TabSpecBuilder.build_spec("metaobjects")
    assert is_map(result)
  end

  test "build_spec('files') returns a spec", _ctx do
    result = JargaAdmin.TabSpecBuilder.build_spec("files")
    assert is_map(result)
  end

  # ── LiveView navigation ───────────────────────────────────────────────────

  test "switch_tab to 'collections' renders without error", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "switch_tab", %{"id" => "collections"})
    assert html =~ "JARGA"
  end
end
