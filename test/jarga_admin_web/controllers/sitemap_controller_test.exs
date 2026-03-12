defmodule JargaAdminWeb.SitemapControllerTest do
  use JargaAdminWeb.ConnCase

  setup %{conn: conn} do
    bypass = Bypass.open()
    original_url = Application.get_env(:jarga_admin, :api_url)
    Application.put_env(:jarga_admin, :api_url, "http://localhost:#{bypass.port}")

    on_exit(fn ->
      Application.put_env(:jarga_admin, :api_url, original_url)
    end)

    {:ok, conn: conn, bypass: bypass}
  end

  describe "GET /store/sitemap.xml" do
    test "returns XML sitemap with pages from registry", %{conn: conn, bypass: bypass} do
      registry = %{
        "pages" => [
          %{"slug" => "home", "title" => "Home", "position" => 0, "seo_priority" => "1.0"},
          %{
            "slug" => "bedroom",
            "title" => "Bedroom",
            "position" => 1,
            "seo_priority" => "0.8"
          },
          %{
            "slug" => "products/linen-duvet",
            "title" => "Linen Duvet",
            "position" => 10,
            "seo_priority" => "0.6"
          }
        ]
      }

      Bypass.stub(bypass, "GET", "/v1/frontend/slots/page_registry", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{data: %{payload_json: Jason.encode!(registry)}, error: nil, meta: %{}})
        )
      end)

      conn = get(conn, "/store/sitemap.xml")
      assert response_content_type(conn, :xml)
      body = response(conn, 200)

      assert body =~ "<?xml"
      assert body =~ "<urlset"
      assert body =~ "<loc>http://localhost:4002/store</loc>"
      assert body =~ "<loc>http://localhost:4002/store/bedroom</loc>"
      assert body =~ "<loc>http://localhost:4002/store/products/linen-duvet</loc>"
      assert body =~ "<priority>1.0</priority>"
      assert body =~ "<priority>0.8</priority>"
      assert body =~ "<priority>0.6</priority>"
    end

    test "returns empty sitemap when registry is empty", %{conn: conn, bypass: bypass} do
      Bypass.stub(bypass, "GET", "/v1/frontend/slots/page_registry", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{data: %{payload_json: "{}"}, error: nil, meta: %{}})
        )
      end)

      conn = get(conn, "/store/sitemap.xml")
      body = response(conn, 200)
      assert body =~ "<urlset"
      refute body =~ "<url>"
    end

    test "returns empty sitemap when registry slot not found", %{conn: conn, bypass: bypass} do
      Bypass.stub(bypass, "GET", "/v1/frontend/slots/page_registry", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(404, Jason.encode!(%{error: "not found", data: nil, meta: %{}}))
      end)

      conn = get(conn, "/store/sitemap.xml")
      body = response(conn, 200)
      assert body =~ "<urlset"
    end
  end

  describe "GET /robots.txt" do
    test "returns robots.txt with sitemap reference", %{conn: conn} do
      conn = get(conn, "/robots.txt")
      body = response(conn, 200)
      assert body =~ "User-agent: *"
      assert body =~ "Sitemap:"
      assert body =~ "/store/sitemap.xml"
    end
  end
end
