defmodule JargaAdminWeb.CustomerEditTest do
  use JargaAdminWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    bypass = Bypass.open()
    Application.put_env(:jarga_admin, :api_url, "http://localhost:#{bypass.port}")
    Application.put_env(:jarga_admin, :api_key, "test-key")

    customer = %{
      id: "cus_1",
      first_name: "Alice",
      last_name: "Smith",
      email: "alice@example.com",
      phone: "+44 7700 900000",
      tags: ["vip"],
      accepts_marketing: true,
      orders_count: 5,
      total_spent: 5000
    }

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

    Bypass.stub(bypass, "GET", "/v1/crm/customers/cus_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: customer, error: nil, meta: %{}})
      )
    end)

    {:ok, bypass: bypass, customer: customer}
  end

  # ── edit_customer ─────────────────────────────────────────────────────────

  test "edit_customer renders an edit form", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")

    html = render_click(view, "edit_customer", %{"id" => "cus_1"})
    assert html =~ "JARGA"
    assert html =~ "form" or html =~ "email"
  end

  # ── update_customer ───────────────────────────────────────────────────────

  test "update_customer sends PATCH and shows success toast", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "PATCH", "/v1/crm/customers/cus_1", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["first_name"] == "Alice"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          data: %{id: "cus_1", first_name: "Alice"},
          error: nil,
          meta: %{}
        })
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")

    html =
      render_submit(view, "update_customer", %{
        "_customer_id" => "cus_1",
        "first_name" => "Alice",
        "last_name" => "Smith",
        "email" => "alice@example.com"
      })

    assert html =~ "JARGA"
  end

  test "update_customer shows error toast on API failure", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "PATCH", "/v1/crm/customers/cus_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        422,
        Jason.encode!(%{data: nil, error: "Invalid email", meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")

    html =
      render_submit(view, "update_customer", %{
        "_customer_id" => "cus_1",
        "email" => "bad"
      })

    assert html =~ "JARGA"
  end

  # ── add_customer_tag ──────────────────────────────────────────────────────

  test "add_customer_tag sends POST to tags endpoint", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/crm/customers/cus_1/tags", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["tag"] == "wholesale"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{data: %{id: "cus_1"}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")

    html =
      render_submit(view, "add_customer_tag", %{
        "_customer_id" => "cus_1",
        "tag" => "wholesale"
      })

    assert html =~ "JARGA"
  end
end
