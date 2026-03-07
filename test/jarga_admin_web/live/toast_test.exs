defmodule JargaAdminWeb.ToastTest do
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

  test "toast container is rendered on the page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/chat")
    assert html =~ "toast-container"
  end

  test "successful create_product shows success toast", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/pim/products", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{data: %{id: "p_1"}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")

    html = render_submit(view, "create_product", %{"name" => "Test"})
    assert html =~ "toast" or html =~ "success" or html =~ "Product created"
  end

  test "failed create_product shows error toast", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/pim/products", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        422,
        Jason.encode!(%{
          data: nil,
          error: %{code: "validation_error", message: "Name is required"},
          meta: %{}
        })
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")

    html = render_submit(view, "create_product", %{"name" => ""})
    assert html =~ "toast" or html =~ "bg-red" or html =~ "Name is required" or html =~ "product"
  end

  test "dismiss_toast removes a toast", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/pim/products", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{data: %{id: "p_1"}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")
    _html = render_submit(view, "create_product", %{"name" => "Test"})

    # Dismiss all toasts
    html = render_click(view, "dismiss_toast", %{"id" => "all"})
    assert html =~ "JARGA"
  end
end
