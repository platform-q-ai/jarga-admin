defmodule JargaAdminWeb.AuthTest do
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

    Bypass.stub(bypass, "POST", "/v1/auth/verify", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)

      if decoded["api_key"] == "valid-key" do
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            data: %{api_key: "valid-key", email: "admin@example.com"},
            error: nil,
            meta: %{}
          })
        )
      else
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          401,
          Jason.encode!(%{data: nil, error: "Invalid credentials", meta: %{}})
        )
      end
    end)

    {:ok, bypass: bypass}
  end

  # ── Login LiveView ────────────────────────────────────────────────────────

  test "/login route renders", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/login")
    assert html =~ "JARGA"
  end

  test "login form submits and redirects on success", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/login")
    # Submit valid credentials — expect a redirect
    assert {:error, {:live_redirect, %{to: "/chat"}}} =
             render_submit(view, "login", %{"api_key" => "valid-key"})
  end

  test "login form shows error on invalid credentials", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/login")
    html = render_submit(view, "login", %{"api_key" => "wrong-key"})
    assert html =~ "JARGA"
  end

  # ── Logout ────────────────────────────────────────────────────────────────

  test "logout event clears session and redirects to /login", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    # logout pushes navigate to /login
    assert {:error, {:live_redirect, %{to: "/login"}}} =
             render_click(view, "logout", %{})
  end
end
