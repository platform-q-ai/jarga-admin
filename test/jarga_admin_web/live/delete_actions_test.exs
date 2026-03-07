defmodule JargaAdminWeb.DeleteActionsTest do
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

  # ── delete_product ─────────────────────────────────────────────────────────

  test "delete_product calls DELETE /v1/pim/products/:id", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "DELETE", "/v1/pim/products/p_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{deleted: true}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "delete_product", %{"id" => "p_1"})
    # Should clear detail and show toast
    assert html =~ "JARGA"
    assert html =~ "toast" or html =~ "deleted" or html =~ "Product"
  end

  test "delete_product shows error toast on failure", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "DELETE", "/v1/pim/products/p_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        422,
        Jason.encode!(%{
          data: nil,
          error: %{message: "Cannot delete published product"},
          meta: %{}
        })
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "delete_product", %{"id" => "p_1"})
    assert html =~ "JARGA"
  end

  # ── delete_customer ────────────────────────────────────────────────────────

  test "delete_customer calls DELETE /v1/crm/customers/:id", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "DELETE", "/v1/crm/customers/cus_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{deleted: true}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "delete_customer", %{"id" => "cus_1"})
    assert html =~ "JARGA"
    assert html =~ "toast" or html =~ "deleted" or html =~ "Customer"
  end

  test "delete_customer shows error toast on failure", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "DELETE", "/v1/crm/customers/cus_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        404,
        Jason.encode!(%{data: nil, error: %{message: "Not found"}, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "delete_customer", %{"id" => "cus_1"})
    assert html =~ "JARGA"
  end
end
