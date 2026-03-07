defmodule JargaAdminWeb.MediaUploadTest do
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
          "/v1/flows"
        ] do
      Bypass.stub(bypass, "GET", path, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, empty_list)
      end)
    end

    {:ok, bypass: bypass}
  end

  # ── request_upload_url ────────────────────────────────────────────────────

  test "request_upload_url calls POST /v1/pim/media/upload-url", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/pim/media/upload-url", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          data: %{upload_url: "https://s3.example.com/upload", media_id: "media_1"},
          error: nil,
          meta: %{}
        })
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")

    html =
      render_click(view, "request_upload_url", %{
        "product_id" => "prod_1",
        "filename" => "photo.jpg",
        "content_type" => "image/jpeg"
      })

    assert html =~ "JARGA"
  end

  # ── delete_media ──────────────────────────────────────────────────────────

  test "delete_media calls DELETE /v1/pim/media/:id", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "DELETE", "/v1/pim/media/media_1", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{id: "media_1"}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")
    html = render_click(view, "delete_media", %{"id" => "media_1"})
    assert html =~ "JARGA"
  end

  # ── update_media_alt_text ─────────────────────────────────────────────────

  test "update_media_alt_text calls PATCH /v1/pim/media/:id", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "PATCH", "/v1/pim/media/media_1", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["alt"] == "A blue t-shirt"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{id: "media_1"}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")

    html =
      render_submit(view, "update_media_alt_text", %{
        "_media_id" => "media_1",
        "alt" => "A blue t-shirt"
      })

    assert html =~ "JARGA"
  end

  # ── reorder_media ─────────────────────────────────────────────────────────

  test "reorder_media calls POST /v1/pim/products/:id/media/reorder", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect_once(bypass, "POST", "/v1/pim/products/prod_1/media/reorder", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{data: %{}, error: nil, meta: %{}})
      )
    end)

    {:ok, view, _html} = live(conn, "/chat")

    html =
      render_click(view, "reorder_media", %{
        "product_id" => "prod_1",
        "order" => Jason.encode!(["media_2", "media_1"])
      })

    assert html =~ "JARGA"
  end
end
