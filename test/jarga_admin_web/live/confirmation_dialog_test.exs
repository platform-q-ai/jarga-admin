defmodule JargaAdminWeb.ConfirmationDialogTest do
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

  # ── request_confirm ────────────────────────────────────────────────────────

  test "request_confirm renders confirmation dialog", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")

    html =
      render_click(view, "request_confirm", %{
        "action" => "delete_product",
        "id" => "p_1",
        "title" => "Delete product?",
        "message" => "This cannot be undone."
      })

    assert has_element?(view, "#confirmation-dialog")
    assert html =~ "Delete product?"
    assert html =~ "This cannot be undone."
  end

  test "cancel_confirm clears the confirmation dialog", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")

    render_click(view, "request_confirm", %{
      "action" => "delete_product",
      "id" => "p_1",
      "title" => "Delete product?",
      "message" => "This cannot be undone."
    })

    assert has_element?(view, "#confirmation-dialog")

    render_click(view, "cancel_confirm", %{})
    refute has_element?(view, "#confirmation-dialog")
  end

  test "confirm_action executes the pending action and clears dialog", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect_once(bypass, "DELETE", "/v1/pim/products/p_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{id: "p_1"}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")

    render_click(view, "request_confirm", %{
      "action" => "delete_product",
      "id" => "p_1",
      "title" => "Delete product?",
      "message" => "This cannot be undone."
    })

    assert has_element?(view, "#confirmation-dialog")

    render_click(view, "confirm_action", %{})
    refute has_element?(view, "#confirmation-dialog")
  end

  test "confirmation dialog is not shown on mount", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    refute has_element?(view, "#confirmation-dialog")
  end
end
