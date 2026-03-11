defmodule JargaAdminWeb.StorefrontLiveTest do
  use JargaAdminWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    bypass = Bypass.open()
    Application.put_env(:jarga_admin, :api_url, "http://localhost:#{bypass.port}")
    Application.put_env(:jarga_admin, :api_key, "test-key")

    # Clear theme cache between tests to ensure fresh API calls
    JargaAdmin.StorefrontTheme.init_cache()
    JargaAdmin.StorefrontTheme.cache_clear()

    {:ok, bypass: bypass}
  end

  defp homepage_spec do
    Jason.encode!(%{
      data: %{
        "id" => "page-home",
        "slug" => "home",
        "title" => "Home",
        "meta_description" => "Welcome to the demo store",
        "status" => "published",
        "content_json" => %{
          "layout" => "storefront",
          "components" => [
            %{
              "type" => "announcement_bar",
              "data" => %{
                "message" => "FREE SHIPPING ON ORDERS OVER £50"
              }
            },
            %{
              "type" => "editorial_hero",
              "data" => %{
                "image_url" => "https://images.unsplash.com/photo-hero",
                "title" => "WINTER COLLECTION",
                "subtitle" => "Warmth meets elegance",
                "cta" => %{"label" => "SHOP NOW", "href" => "/bedroom"}
              }
            },
            %{
              "type" => "editorial_split",
              "data" => %{
                "left" => %{
                  "image_url" => "https://images.unsplash.com/photo-kitchen",
                  "label" => "KITCHEN & DINING",
                  "href" => "/kitchen"
                },
                "right" => %{
                  "image_url" => "https://images.unsplash.com/photo-bathroom",
                  "label" => "BATHROOM",
                  "href" => "/bathroom"
                }
              }
            },
            %{
              "type" => "product_scroll",
              "data" => %{
                "title" => "NEW ARRIVALS",
                "products" => [
                  %{
                    "id" => "p1",
                    "name" => "Linen Duvet Cover",
                    "price" => "£89.00",
                    "image_url" => "https://images.unsplash.com/photo-duvet",
                    "href" => "/products/linen-duvet"
                  }
                ]
              }
            }
          ]
        }
      },
      error: nil,
      meta: %{}
    })
  end

  defp navigation_spec do
    Jason.encode!(%{
      data: %{
        "links" => [
          %{"label" => "BEDROOM", "href" => "/bedroom"},
          %{"label" => "KITCHEN & DINING", "href" => "/kitchen"},
          %{"label" => "BATHROOM", "href" => "/bathroom"}
        ]
      },
      error: nil,
      meta: %{}
    })
  end

  defp stub_storefront_api(bypass, slug \\ "home") do
    Bypass.stub(bypass, "GET", "/v1/frontend/pages/#{slug}", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, homepage_spec())
    end)

    Bypass.stub(bypass, "GET", "/v1/frontend/navigation", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, navigation_spec())
    end)

    # Default: no custom theme (falls back to defaults)
    Bypass.stub(bypass, "GET", "/v1/frontend/slots/storefront_theme", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(404, Jason.encode!(%{error: "not found", data: nil, meta: %{}}))
    end)
  end

  describe "storefront pages at /store path" do
    test "renders the storefront homepage with editorial hero", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      {:ok, _view, html} = live(conn, "/store")

      assert html =~ "WINTER COLLECTION"
      assert html =~ "Warmth meets elegance"
      assert html =~ "SHOP NOW"
    end

    test "renders announcement bar", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      {:ok, _view, html} = live(conn, "/store")

      assert html =~ "FREE SHIPPING ON ORDERS OVER £50"
    end

    test "renders editorial split blocks", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      {:ok, _view, html} = live(conn, "/store")

      assert html =~ "KITCHEN &amp; DINING" or html =~ "KITCHEN &amp;amp; DINING" or
               html =~ "KITCHEN"
    end

    test "renders product scroll section", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      {:ok, _view, html} = live(conn, "/store")

      assert html =~ "NEW ARRIVALS"
      assert html =~ "Linen Duvet Cover"
      assert html =~ "£89.00"
    end

    test "sets page title from spec", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      {:ok, _view, html} = live(conn, "/store")

      assert html =~ "Home"
    end
  end

  describe "slug routing" do
    test "loads page by slug from URL path", %{conn: conn, bypass: bypass} do
      bedroom_spec =
        Jason.encode!(%{
          data: %{
            "id" => "page-bedroom",
            "slug" => "bedroom",
            "title" => "Bedroom",
            "meta_description" => "Bedroom collection",
            "status" => "published",
            "content_json" => %{
              "layout" => "storefront",
              "components" => [
                %{
                  "type" => "editorial_hero",
                  "data" => %{
                    "image_url" => "/media/bedroom.jpg",
                    "title" => "BEDROOM"
                  }
                }
              ]
            }
          },
          error: nil,
          meta: %{}
        })

      Bypass.stub(bypass, "GET", "/v1/frontend/pages/bedroom", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, bedroom_spec)
      end)

      Bypass.stub(bypass, "GET", "/v1/frontend/navigation", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, navigation_spec())
      end)

      Bypass.stub(bypass, "GET", "/v1/frontend/slots/storefront_theme", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(404, Jason.encode!(%{error: "not found", data: nil, meta: %{}}))
      end)

      {:ok, _view, html} = live(conn, "/store/bedroom")

      assert html =~ "BEDROOM"
    end
  end

  describe "theme injection" do
    test "injects theme CSS vars on the sf-page wrapper", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      # Stub the theme slot endpoint
      Bypass.stub(bypass, "GET", "/v1/frontend/slots/storefront_theme", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            data: %{
              "slot_key" => "storefront_theme",
              "payload_json" => %{
                "colors" => %{"primary" => "#ff0000", "accent" => "#00ff00"},
                "fonts" => %{"heading" => "Georgia", "body" => "Verdana"}
              }
            },
            error: nil,
            meta: %{}
          })
        )
      end)

      {:ok, _view, html} = live(conn, "/store")

      assert html =~ "--sf-color-primary:#ff0000"
      assert html =~ "--sf-color-accent:#00ff00"
      assert html =~ "--sf-font-heading:Georgia"
      assert html =~ "--sf-font-body:Verdana"
    end

    test "falls back to defaults when theme slot returns 404", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      Bypass.stub(bypass, "GET", "/v1/frontend/slots/storefront_theme", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(404, Jason.encode!(%{error: "not found", data: nil, meta: %{}}))
      end)

      {:ok, _view, html} = live(conn, "/store")

      # Should still have CSS vars from defaults
      assert html =~ "--sf-color-primary:"
      assert html =~ "--sf-font-heading:"
    end

    test "uses store_name from theme branding for the logo", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      Bypass.stub(bypass, "GET", "/v1/frontend/slots/storefront_theme", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            data: %{
              "slot_key" => "storefront_theme",
              "payload_json" => %{
                "branding" => %{"store_name" => "LUXE HOME"}
              }
            },
            error: nil,
            meta: %{}
          })
        )
      end)

      {:ok, _view, html} = live(conn, "/store")

      assert html =~ "LUXE HOME"
    end

    test "injects google_fonts_url link tag when present", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      fonts_url = "https://fonts.googleapis.com/css2?family=Montserrat&amp;family=Inter"

      Bypass.stub(bypass, "GET", "/v1/frontend/slots/storefront_theme", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            data: %{
              "slot_key" => "storefront_theme",
              "payload_json" => %{
                "fonts" => %{
                  "heading" => "Montserrat",
                  "body" => "Inter",
                  "google_fonts_url" =>
                    "https://fonts.googleapis.com/css2?family=Montserrat&family=Inter"
                }
              }
            },
            error: nil,
            meta: %{}
          })
        )
      end)

      {:ok, _view, html} = live(conn, "/store")

      assert html =~ "family=Montserrat"
    end
  end

  describe "error handling" do
    test "shows error state when API returns 404", %{conn: conn, bypass: bypass} do
      Bypass.stub(bypass, "GET", "/v1/frontend/pages/nonexistent", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(404, Jason.encode!(%{error: "not found", data: nil, meta: %{}}))
      end)

      Bypass.stub(bypass, "GET", "/v1/frontend/navigation", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, navigation_spec())
      end)

      Bypass.stub(bypass, "GET", "/v1/frontend/slots/storefront_theme", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(404, Jason.encode!(%{error: "not found", data: nil, meta: %{}}))
      end)

      {:ok, _view, html} = live(conn, "/store/nonexistent")

      assert html =~ "Page not found"
    end
  end
end
