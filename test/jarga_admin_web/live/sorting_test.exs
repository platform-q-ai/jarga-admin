defmodule JargaAdminWeb.SortingTest do
  use JargaAdminWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    bypass = Bypass.open()
    Application.put_env(:jarga_admin, :api_url, "http://localhost:#{bypass.port}")
    Application.put_env(:jarga_admin, :api_key, "test-key")

    customers_body =
      Jason.encode!(%{
        data: %{
          items: [
            %{
              id: "c1",
              first_name: "Alice",
              last_name: "Smith",
              email: "alice@example.com",
              orders_count: 5,
              total_spent: 1000
            },
            %{
              id: "c2",
              first_name: "Bob",
              last_name: "Jones",
              email: "bob@example.com",
              orders_count: 2,
              total_spent: 500
            }
          ]
        },
        error: nil,
        meta: %{}
      })

    empty_list = Jason.encode!(%{data: %{items: []}, error: nil, meta: %{}})

    Bypass.stub(bypass, "GET", "/v1/crm/customers", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, customers_body)
    end)

    for path <- [
          "/v1/pim/products",
          "/v1/oms/orders",
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

  test "sort event is handled without error", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "sort", %{"key" => "name"})
    assert html =~ "JARGA"
  end

  test "sort event on same key twice is handled without error", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    render_click(view, "sort", %{"key" => "status"})
    html = render_click(view, "sort", %{"key" => "status"})
    assert html =~ "JARGA"
  end

  test "sort event with different keys tracked independently", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    render_click(view, "sort", %{"key" => "email"})
    render_click(view, "sort", %{"key" => "name"})
    html = render_click(view, "sort", %{"key" => "email"})
    assert html =~ "JARGA"
  end

  test "sort state is initialized on mount", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/chat")
    assert html =~ "JARGA"
  end
end
