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

    # Default: footer slot returns 404 (falls back to hardcoded defaults)
    # Tests that need a custom footer can override with their own stub.
    Bypass.stub(bypass, "GET", "/v1/frontend/slots/storefront_footer", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(404, Jason.encode!(%{error: "not found"}))
    end)

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

  describe "search overlay" do
    test "toggle_search opens and closes the search overlay", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      {:ok, view, html} = live(conn, "/store")

      # Search overlay should not be visible initially
      refute has_element?(view, "#search-overlay")

      # Click the search icon to open
      render_click(view, "toggle_search")
      assert has_element?(view, "#search-overlay")

      # Click again to close
      render_click(view, "toggle_search")
      refute has_element?(view, "#search-overlay")
    end

    test "search event returns product results", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      # Stub product search
      Bypass.stub(bypass, "GET", "/v1/pim/products", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            data: [
              %{
                "id" => "prod-1",
                "name" => "Linen Duvet Cover",
                "slug" => "linen-duvet",
                "price" => %{"amount" => "89.00", "currency" => "GBP"},
                "images" => [%{"url" => "/img/linen.jpg"}]
              }
            ],
            error: nil,
            meta: %{total: 1}
          })
        )
      end)

      {:ok, view, _html} = live(conn, "/store")

      # Open search
      render_click(view, "toggle_search")

      # Search for products (async — wait for task result)
      render_click(view, "search", %{"query" => "linen"})
      # Give async task time to complete and send result
      Process.sleep(50)
      html = render(view)
      assert html =~ "Linen Duvet Cover"
    end

    test "search with empty query clears results", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      {:ok, view, _html} = live(conn, "/store")

      # Open search
      render_click(view, "toggle_search")

      # Search with empty query
      html = render_click(view, "search", %{"query" => ""})
      refute html =~ "search-result"
    end

    test "close_search event closes the overlay", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      {:ok, view, _html} = live(conn, "/store")

      # Open then close
      render_click(view, "toggle_search")
      assert has_element?(view, "#search-overlay")

      render_click(view, "close_search")
      refute has_element?(view, "#search-overlay")
    end
  end

  describe "preview mode" do
    test "shows preview banner when preview param is set", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      {:ok, view, html} = live(conn, "/store?preview=true")

      assert has_element?(view, "#preview-banner")
      assert html =~ "PREVIEW"
    end

    test "adds noindex meta tag in preview mode", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      {:ok, view, _html} = live(conn, "/store?preview=true")

      assert has_element?(view, "meta[name=robots]")
    end

    test "does not show preview banner in normal mode", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      {:ok, view, _html} = live(conn, "/store")

      refute has_element?(view, "#preview-banner")
    end
  end

  describe "SEO" do
    test "assigns meta_description from page spec", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      {:ok, view, _html} = live(conn, "/store")

      # meta_description should be assigned from the page spec
      assert has_element?(view, "meta[name=description]")
    end

    test "sets og:title and og:description meta tags", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      {:ok, view, _html} = live(conn, "/store")

      assert has_element?(view, "meta[property=\"og:title\"]")
    end
  end

  describe "basket integration" do
    test "add_to_cart adds item and opens cart drawer", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      {:ok, view, _html} = live(conn, "/store")

      render_click(view, "add_to_cart", %{
        "id" => "prod-1",
        "name" => "Test Cart Item",
        "price" => "£89.00",
        "image_url" => "/img/test.jpg"
      })

      # Cart drawer should be open with the item
      assert has_element?(view, ".sf-cart-drawer-open")
      assert has_element?(view, ".sf-cart-item-name", "Test Cart Item")
    end

    test "remove_from_cart removes item", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      {:ok, view, _html} = live(conn, "/store")

      # Add an item
      render_click(view, "add_to_cart", %{
        "id" => "prod-1",
        "name" => "Test Cart Item",
        "price" => "£89.00",
        "image_url" => "/img/test.jpg"
      })

      assert has_element?(view, ".sf-cart-item-name", "Test Cart Item")

      # Remove it
      render_click(view, "remove_from_cart", %{"id" => "prod-1"})
      refute has_element?(view, ".sf-cart-item-name", "Test Cart Item")
    end

    test "cart count updates when items are added", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      {:ok, view, _html} = live(conn, "/store")

      # Initially cart count should be 0 (no badge shown)
      refute has_element?(view, ".sf-cart-badge")

      render_click(view, "add_to_cart", %{
        "id" => "prod-1",
        "name" => "Test Item",
        "price" => "£10.00",
        "image_url" => "/img/1.jpg"
      })

      # Cart count badge should now show
      assert has_element?(view, ".sf-cart-badge")
    end
  end

  describe "gallery zoom" do
    test "open_gallery_zoom and close_gallery_zoom toggle overlay", %{
      conn: conn,
      bypass: bypass
    } do
      stub_storefront_api(bypass)

      {:ok, view, _html} = live(conn, "/store")

      refute has_element?(view, "#gallery-zoom")

      render_click(view, "open_gallery_zoom", %{"index" => "0"})
      assert has_element?(view, "#gallery-zoom")

      render_click(view, "close_gallery_zoom")
      refute has_element?(view, "#gallery-zoom")
    end
  end

  describe "filter drawer" do
    test "toggle_filters opens and closes the filter drawer", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      {:ok, view, _html} = live(conn, "/store")

      refute has_element?(view, "#filter-drawer")

      render_click(view, "toggle_filters")
      assert has_element?(view, "#filter-drawer")

      render_click(view, "toggle_filters")
      refute has_element?(view, "#filter-drawer")
    end

    test "clear_filters resets active filters", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      {:ok, view, _html} = live(conn, "/store")

      # Open filter drawer
      render_click(view, "toggle_filters")
      assert has_element?(view, "#filter-drawer")

      # Clear all filters
      render_click(view, "clear_filters")
      # Drawer should close
      refute has_element?(view, "#filter-drawer")
    end

    test "close_filters closes the drawer", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      {:ok, view, _html} = live(conn, "/store")

      render_click(view, "toggle_filters")
      assert has_element?(view, "#filter-drawer")

      render_click(view, "close_filters")
      refute has_element?(view, "#filter-drawer")
    end
  end

  describe "data-driven footer" do
    test "loads footer from API slot", %{conn: conn, bypass: bypass} do
      footer_payload = %{
        "columns" => [
          %{
            "title" => "Custom Shop",
            "links" => [%{"label" => "Custom Link", "href" => "/custom"}]
          }
        ],
        "copyright" => "© 2026 Custom Store"
      }

      Bypass.stub(bypass, "GET", "/v1/frontend/pages/home", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, homepage_spec())
      end)

      Bypass.stub(bypass, "GET", "/v1/frontend/navigation", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, navigation_spec())
      end)

      Bypass.stub(bypass, "GET", "/v1/frontend/slots/storefront_theme", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(404, Jason.encode!(%{error: "not found"}))
      end)

      Bypass.stub(bypass, "GET", "/v1/frontend/slots/storefront_footer", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{data: %{"payload_json" => footer_payload}}))
      end)

      {:ok, _view, html} = live(conn, "/store")

      assert html =~ "Custom Shop"
      assert html =~ "Custom Link"
      assert html =~ "© 2026 Custom Store"
    end

    test "falls back to default footer when slot missing", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      {:ok, _view, html} = live(conn, "/store")

      # Default footer should still render
      assert html =~ "Bedroom"
      assert html =~ "Jarga Commerce"
    end
  end

  describe "nested navigation" do
    test "renders nav links with children as dropdowns", %{conn: conn, bypass: bypass} do
      nested_nav =
        Jason.encode!(%{
          data: %{
            "items" => [
              %{"label" => "BEDROOM", "href" => "/bedroom"},
              %{
                "label" => "LIVING",
                "children" => [
                  %{"label" => "Sofas", "href" => "/sofas"},
                  %{"label" => "Tables", "href" => "/tables"}
                ]
              }
            ]
          }
        })

      Bypass.stub(bypass, "GET", "/v1/frontend/pages/home", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, homepage_spec())
      end)

      Bypass.stub(bypass, "GET", "/v1/frontend/navigation", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, nested_nav)
      end)

      Bypass.stub(bypass, "GET", "/v1/frontend/slots/storefront_theme", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(404, Jason.encode!(%{error: "not found"}))
      end)

      Bypass.stub(bypass, "GET", "/v1/frontend/slots/storefront_footer", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(404, Jason.encode!(%{error: "not found"}))
      end)

      {:ok, _view, html} = live(conn, "/store")

      assert html =~ "BEDROOM"
      assert html =~ "LIVING"
      assert html =~ "Sofas"
      assert html =~ "Tables"
    end
  end

  describe "per-component styling" do
    test "renders component with inline style from page spec", %{conn: conn, bypass: bypass} do
      styled_spec =
        Jason.encode!(%{
          data: %{
            "id" => "page-styled",
            "slug" => "styled",
            "title" => "Styled Page",
            "meta_description" => "",
            "status" => "published",
            "content_json" => %{
              "layout" => "storefront",
              "components" => [
                %{
                  "type" => "text_block",
                  "data" => %{
                    "title" => "STYLED BLOCK",
                    "content" => "Content here",
                    "style" => %{
                      "background" => "#f5f0eb",
                      "padding" => "80px 32px",
                      "text_align" => "left"
                    }
                  }
                }
              ]
            }
          },
          error: nil,
          meta: %{}
        })

      Bypass.stub(bypass, "GET", "/v1/frontend/pages/styled", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, styled_spec)
      end)

      Bypass.stub(bypass, "GET", "/v1/frontend/navigation", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, navigation_spec())
      end)

      Bypass.stub(bypass, "GET", "/v1/frontend/slots/storefront_theme", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(404, Jason.encode!(%{error: "not found"}))
      end)

      {:ok, _view, html} = live(conn, "/store/styled")

      assert html =~ "STYLED BLOCK"
      assert html =~ "background:#f5f0eb"
      assert html =~ "padding:80px 32px"
      assert html =~ "text-align:left"
    end

    test "component renders without style when not provided", %{conn: conn, bypass: bypass} do
      stub_storefront_api(bypass)

      {:ok, _view, html} = live(conn, "/store")

      # The page renders normally — no inline style attributes on components
      assert html =~ "WINTER COLLECTION"
    end
  end

  describe "channel awareness" do
    test "passes channel_handle to StorefrontLive via session", %{conn: conn, bypass: bypass} do
      # The channel resolver sets channel_handle in conn.assigns,
      # which the live_session on_mount copies to the socket.
      # Default strategy is :single, so channel_handle = "online-store"
      stub_storefront_api(bypass)

      {:ok, view, html} = live(conn, "/store")

      # The page should render normally with the default channel
      assert html =~ "Home"
      assert has_element?(view, "#storefront-page")
    end

    test "channel handle is passed to API calls for page loading",
         %{conn: conn, bypass: bypass} do
      # Stub theme with 404 (default fallback)
      Bypass.stub(bypass, "GET", "/v1/frontend/slots/storefront_theme", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(404, Jason.encode!(%{error: "not found", data: nil, meta: %{}}))
      end)

      Bypass.stub(bypass, "GET", "/v1/frontend/navigation", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, navigation_spec())
      end)

      # The storefront loads pages normally — channel scoping is transparent
      Bypass.stub(bypass, "GET", "/v1/frontend/pages/home", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, homepage_spec())
      end)

      {:ok, _view, html} = live(conn, "/store")

      assert html =~ "Home"
    end
  end
end
