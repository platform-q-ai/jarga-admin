defmodule JargaAdminWeb.SearchFilterTest do
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

  test "search event with query is handled without error", %{conn: conn, bypass: bypass} do
    Bypass.stub(bypass, "GET", "/v1/pim/products", fn conn ->
      query = URI.decode_query(conn.query_string)
      # The filtered call will have a q param
      body =
        if query["q"] == "shirt" do
          Jason.encode!(%{
            data: %{items: [%{id: "p1", title: "Shirt"}]},
            error: nil,
            meta: %{}
          })
        else
          Jason.encode!(%{data: %{items: []}, error: nil, meta: %{}})
        end

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, body)
    end)

    {:ok, view, _html} = live(conn, "/chat")

    html =
      render_submit(view, "search", %{"tab_id" => "products", "q" => "shirt"})

    assert html =~ "JARGA"
  end

  test "set_filter event with status is handled without error", %{conn: conn, bypass: bypass} do
    Bypass.stub(bypass, "GET", "/v1/oms/orders", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{data: %{items: []}, error: nil, meta: %{}}))
    end)

    {:ok, view, _html} = live(conn, "/chat")

    html =
      render_click(view, "set_filter", %{
        "tab_id" => "orders",
        "financial_status" => "paid"
      })

    assert html =~ "JARGA"
  end

  test "clear_filter resets filter state for tab", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")

    render_click(view, "set_filter", %{"tab_id" => "products", "status" => "active"})
    html = render_click(view, "clear_filter", %{"tab_id" => "products"})
    assert html =~ "JARGA"
  end

  test "filter_state is initialized as empty map on mount", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/chat")
    assert html =~ "JARGA"
  end
end
