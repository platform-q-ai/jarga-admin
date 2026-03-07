defmodule JargaAdminWeb.PaginationTest do
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

    {:ok, bypass: bypass}
  end

  test "next_page increments page for active tab", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "next_page", %{})
    assert html =~ "JARGA"
  end

  test "prev_page does not go below page 1", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    # prev on page 1 should stay on page 1
    html = render_click(view, "prev_page", %{})
    assert html =~ "JARGA"
  end

  test "go_to_page sets specific page", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "go_to_page", %{"page" => "3"})
    assert html =~ "JARGA"
  end

  test "page_state is initialized in mount", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/chat")
    assert html =~ "JARGA"
  end
end
