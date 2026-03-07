defmodule JargaAdminWeb.ChatLiveTest do
  use JargaAdminWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the chat interface", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/chat")

    assert html =~ "JARGA"
    assert html =~ "chat-messages"
    assert html =~ "What would you like to do?"
  end

  test "shows suggestion buttons on empty chat", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/chat")

    assert html =~ "Show me today&#39;s orders" or html =~ "Show me today's orders"
    assert html =~ "How are sales trending?"
  end

  test "renders nav with Shopify-style sections", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/chat")

    assert html =~ "j-nav-items"
    assert html =~ "Orders"
    assert html =~ "Products"
    assert html =~ "Customers"
  end

  test "can switch to orders via nav link", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")

    html = view |> element("button.j-nav-dropdown-item[phx-value-id='orders']") |> render_click()
    assert html =~ "JARGA"
  end

  test "chat input form exists", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/chat")

    assert html =~ "chat-form"
    assert html =~ "chat-input"
  end

  test "redirects / to /chat", %{conn: conn} do
    conn = get(conn, "/")
    assert redirected_to(conn) == "/chat"
  end

  describe "retry_tab event" do
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

    test "retry_tab invalidates spec and rebuilds", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      # Fire retry_tab event — should not crash and return valid HTML
      html = render_click(view, "retry_tab", %{})
      assert html =~ "JARGA"
    end
  end

  # ── submit_form routing ──────────────────────────────────────────────────────

  describe "submit_form routing" do
    setup do
      bypass = Bypass.open()
      Application.put_env(:jarga_admin, :api_url, "http://localhost:#{bypass.port}")
      Application.put_env(:jarga_admin, :api_key, "test-key")

      # Stub all common GET endpoints so LiveView mount and tab reloads don't fail
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

    test "routes create_product to POST /v1/pim/products", %{conn: conn, bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/pim/products", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["name"] == "Test Product"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          201,
          Jason.encode!(%{data: %{id: "p_new"}, error: nil, meta: %{}})
        )
      end)

      {:ok, view, _html} = live(conn, "/chat")

      html =
        render_submit(view, "create_product", %{
          "name" => "Test Product",
          "price" => "9.99"
        })

      assert html =~ "JARGA"
    end

    test "routes create_customer to POST /v1/crm/customers", %{conn: conn, bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/crm/customers", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["email"] == "jane@example.com"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          201,
          Jason.encode!(%{data: %{id: "c_new"}, error: nil, meta: %{}})
        )
      end)

      {:ok, view, _html} = live(conn, "/chat")

      html =
        render_submit(view, "create_customer", %{
          "email" => "jane@example.com",
          "first_name" => "Jane"
        })

      assert html =~ "JARGA"
    end

    test "routes create_promotion to POST /v1/promotions/campaigns", %{
      conn: conn,
      bypass: bypass
    } do
      Bypass.expect_once(bypass, "POST", "/v1/promotions/campaigns", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["name"] == "Summer Sale"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          201,
          Jason.encode!(%{data: %{id: "promo_new"}, error: nil, meta: %{}})
        )
      end)

      {:ok, view, _html} = live(conn, "/chat")

      html =
        render_submit(view, "create_promotion", %{
          "name" => "Summer Sale",
          "type" => "percentage"
        })

      assert html =~ "JARGA"
    end

    test "routes create_order to POST /v1/oms/orders", %{conn: conn, bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/oms/orders", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          201,
          Jason.encode!(%{data: %{id: "ord_new"}, error: nil, meta: %{}})
        )
      end)

      {:ok, view, _html} = live(conn, "/chat")

      html = render_submit(view, "create_order", %{"customer_id" => "c_1"})
      assert html =~ "JARGA"
    end

    test "routes create_shipping_zone to POST /v1/shipping/zones", %{conn: conn, bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/shipping/zones", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          201,
          Jason.encode!(%{data: %{id: "zone_new"}, error: nil, meta: %{}})
        )
      end)

      {:ok, view, _html} = live(conn, "/chat")

      html = render_submit(view, "create_shipping_zone", %{"name" => "UK"})
      assert html =~ "JARGA"
    end

    test "shows error flash on API failure for create_product", %{conn: conn, bypass: bypass} do
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
      assert html =~ "error" or html =~ "failed" or html =~ "Error"
    end
  end
end
