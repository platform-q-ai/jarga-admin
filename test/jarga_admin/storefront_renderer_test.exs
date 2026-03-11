defmodule JargaAdmin.StorefrontRendererTest do
  use ExUnit.Case, async: true

  alias JargaAdmin.StorefrontRenderer

  describe "render_spec/1" do
    test "returns empty list for nil" do
      assert [] = StorefrontRenderer.render_spec(nil)
    end

    test "returns empty list for empty components" do
      assert [] = StorefrontRenderer.render_spec(%{"components" => []})
    end

    test "returns empty list for invalid spec" do
      assert [] = StorefrontRenderer.render_spec(%{"invalid" => true})
    end

    test "normalizes editorial_hero component" do
      spec = %{
        "layout" => "storefront",
        "components" => [
          %{
            "type" => "editorial_hero",
            "data" => %{
              "image_url" => "/media/hero.jpg",
              "title" => "WINTER COLLECTION",
              "subtitle" => "Warmth meets elegance",
              "cta" => %{"label" => "SHOP NOW", "href" => "/bedroom"}
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.type == :editorial_hero
      assert comp.assigns.image_url == "/media/hero.jpg"
      assert comp.assigns.title == "WINTER COLLECTION"
      assert comp.assigns.subtitle == "Warmth meets elegance"
      assert comp.assigns.cta == %{"label" => "SHOP NOW", "href" => "/bedroom"}
    end

    test "normalizes editorial_full component" do
      spec = %{
        "layout" => "storefront",
        "components" => [
          %{
            "type" => "editorial_full",
            "data" => %{
              "image_url" => "/media/fragrances.jpg",
              "label" => "FRAGRANCES",
              "href" => "/fragrances"
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.type == :editorial_full
      assert comp.assigns.image_url == "/media/fragrances.jpg"
      assert comp.assigns.label == "FRAGRANCES"
      assert comp.assigns.href == "/fragrances"
    end

    test "normalizes editorial_split component" do
      spec = %{
        "layout" => "storefront",
        "components" => [
          %{
            "type" => "editorial_split",
            "data" => %{
              "left" => %{
                "image_url" => "/media/kitchen.jpg",
                "label" => "KITCHEN",
                "href" => "/kitchen"
              },
              "right" => %{
                "image_url" => "/media/bathroom.jpg",
                "label" => "BATHROOM",
                "href" => "/bathroom"
              }
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.type == :editorial_split
      assert comp.assigns.left.image_url == "/media/kitchen.jpg"
      assert comp.assigns.left.label == "KITCHEN"
      assert comp.assigns.right.image_url == "/media/bathroom.jpg"
      assert comp.assigns.right.label == "BATHROOM"
    end

    test "normalizes product_scroll component" do
      spec = %{
        "layout" => "storefront",
        "components" => [
          %{
            "type" => "product_scroll",
            "data" => %{
              "title" => "NEW ARRIVALS",
              "products" => [
                %{
                  "id" => "p1",
                  "name" => "Linen Duvet",
                  "price" => "£89.00",
                  "image_url" => "/media/duvet.jpg"
                }
              ]
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.type == :product_scroll
      assert comp.assigns.title == "NEW ARRIVALS"
      assert length(comp.assigns.products) == 1
    end

    test "normalizes product_grid component" do
      spec = %{
        "layout" => "storefront",
        "components" => [
          %{
            "type" => "product_grid",
            "data" => %{
              "title" => "BEDROOM",
              "columns" => 3,
              "products" => [
                %{
                  "id" => "p1",
                  "name" => "Linen Sheet Set",
                  "price" => "£45.00",
                  "image_url" => "/media/sheets.jpg",
                  "hover_image_url" => "/media/sheets-hover.jpg",
                  "featured" => true
                }
              ]
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.type == :product_grid
      assert comp.assigns.title == "BEDROOM"
      assert comp.assigns.columns == 3
      assert length(comp.assigns.products) == 1
      assert hd(comp.assigns.products).featured == true
    end

    test "normalizes nav_bar component" do
      spec = %{
        "layout" => "storefront",
        "components" => [
          %{
            "type" => "nav_bar",
            "data" => %{
              "logo" => "JARGA",
              "links" => [
                %{"label" => "BEDROOM", "href" => "/bedroom"},
                %{"label" => "KITCHEN", "href" => "/kitchen"}
              ]
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.type == :nav_bar
      assert comp.assigns.logo == "JARGA"
      assert length(comp.assigns.links) == 2
    end

    test "normalizes footer component" do
      spec = %{
        "layout" => "storefront",
        "components" => [
          %{
            "type" => "footer",
            "data" => %{
              "columns" => [
                %{"title" => "Shop", "links" => [%{"label" => "Bedroom", "href" => "/bedroom"}]},
                %{"title" => "Help", "links" => [%{"label" => "Returns", "href" => "/returns"}]}
              ],
              "copyright" => "© 2026 Jarga Commerce"
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.type == :footer
      assert length(comp.assigns.columns) == 2
      assert comp.assigns.copyright == "© 2026 Jarga Commerce"
    end

    test "normalizes announcement_bar component" do
      spec = %{
        "layout" => "storefront",
        "components" => [
          %{
            "type" => "announcement_bar",
            "data" => %{
              "message" => "FREE SHIPPING ON ORDERS OVER £50",
              "href" => "/shipping"
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.type == :announcement_bar
      assert comp.assigns.message == "FREE SHIPPING ON ORDERS OVER £50"
    end

    test "normalizes product_detail component" do
      spec = %{
        "layout" => "storefront",
        "components" => [
          %{
            "type" => "product_detail",
            "data" => %{
              "id" => "p1",
              "name" => "Linen Duvet Cover",
              "price" => "£89.00",
              "images" => ["/media/duvet1.jpg", "/media/duvet2.jpg"],
              "description" => "Premium stonewashed linen",
              "colours" => [%{"name" => "White", "hex" => "#ffffff"}],
              "sizes" => ["Single", "Double", "King"],
              "accordion" => [
                %{"title" => "DESCRIPTION", "content" => "Made from..."},
                %{"title" => "CARE", "content" => "Machine wash..."}
              ]
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.type == :product_detail
      assert comp.assigns.name == "Linen Duvet Cover"
      assert comp.assigns.price == "£89.00"
      assert length(comp.assigns.images) == 2
      assert length(comp.assigns.colours) == 1
      assert length(comp.assigns.sizes) == 3
      assert length(comp.assigns.accordion) == 2
    end

    test "normalizes category_nav component" do
      spec = %{
        "layout" => "storefront",
        "components" => [
          %{
            "type" => "category_nav",
            "data" => %{
              "links" => [
                %{"label" => "DUVET COVERS", "href" => "/bedroom/duvets"},
                %{"label" => "PILLOWCASES", "href" => "/bedroom/pillows"}
              ]
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.type == :category_nav
      assert length(comp.assigns.links) == 2
    end

    test "normalizes text_block component" do
      spec = %{
        "layout" => "storefront",
        "components" => [
          %{
            "type" => "text_block",
            "data" => %{
              "title" => "About Us",
              "content" => "We are a premium home brand."
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.type == :text_block
      assert comp.assigns.title == "About Us"
      assert comp.assigns.content == "We are a premium home brand."
    end

    test "handles multiple components in order" do
      spec = %{
        "layout" => "storefront",
        "components" => [
          %{
            "type" => "announcement_bar",
            "data" => %{"message" => "Free shipping"}
          },
          %{
            "type" => "editorial_hero",
            "data" => %{
              "image_url" => "/hero.jpg",
              "title" => "COLLECTION"
            }
          },
          %{
            "type" => "product_scroll",
            "data" => %{"title" => "New", "products" => []}
          }
        ]
      }

      components = StorefrontRenderer.render_spec(spec)
      assert length(components) == 3
      assert Enum.at(components, 0).type == :announcement_bar
      assert Enum.at(components, 1).type == :editorial_hero
      assert Enum.at(components, 2).type == :product_scroll
    end

    test "normalizes related_products component" do
      spec = %{
        "layout" => "storefront",
        "components" => [
          %{
            "type" => "related_products",
            "data" => %{
              "title" => "YOU MAY ALSO LIKE",
              "products" => [
                %{
                  "name" => "Wool Throw",
                  "slug" => "wool-throw",
                  "price" => "£65.00",
                  "image_url" => "/img/wool.jpg"
                }
              ]
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.type == :related_products
      assert comp.assigns.title == "YOU MAY ALSO LIKE"
      assert length(comp.assigns.products) == 1
      assert hd(comp.assigns.products).name == "Wool Throw"
    end

    test "unknown component types are passed through as :unknown" do
      spec = %{
        "layout" => "storefront",
        "components" => [
          %{"type" => "futuristic_widget", "data" => %{"foo" => "bar"}}
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.type == :unknown
    end
  end

  describe "style passthrough" do
    test "components pass through validated style map in assigns" do
      spec = %{
        "components" => [
          %{
            "type" => "product_grid",
            "data" => %{
              "title" => "SALE",
              "columns" => 3,
              "products" => [],
              "style" => %{
                "background" => "#f5f0eb",
                "padding" => "80px 32px"
              }
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.assigns.style["background"] == "#f5f0eb"
      assert comp.assigns.style["padding"] == "80px 32px"
    end

    test "style is empty map when not provided" do
      spec = %{
        "components" => [
          %{
            "type" => "text_block",
            "data" => %{"title" => "Hello", "content" => "World"}
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.assigns.style == %{}
    end

    test "style rejects invalid properties" do
      spec = %{
        "components" => [
          %{
            "type" => "editorial_hero",
            "data" => %{
              "image_url" => "/hero.jpg",
              "title" => "HERO",
              "style" => %{
                "background" => "#ffffff",
                "position" => "absolute",
                "z_index" => "9999"
              }
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.assigns.style["background"] == "#ffffff"
      refute Map.has_key?(comp.assigns.style, "position")
      refute Map.has_key?(comp.assigns.style, "z_index")
    end

    test "product normalisation passes through variant, badge, compare_at_price, description" do
      spec = %{
        "components" => [
          %{
            "type" => "product_grid",
            "data" => %{
              "columns" => 4,
              "products" => [
                %{
                  "id" => "p1",
                  "name" => "Linen Duvet",
                  "price" => "£89.00",
                  "compare_at_price" => "£129.00",
                  "image_url" => "/img/duvet.jpg",
                  "variant" => "editorial",
                  "badge" => "SALE",
                  "description" => "Stonewashed Belgian linen"
                }
              ]
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      product = hd(comp.assigns.products)
      assert product.variant == "editorial"
      assert product.badge == "SALE"
      assert product.compare_at_price == "£129.00"
      assert product.description == "Stonewashed Belgian linen"
    end

    test "extracts filters from content_json" do
      spec = %{
        "filters" => [
          %{
            "key" => "category",
            "label" => "Category",
            "type" => "checkbox",
            "options" => [%{"value" => "bedding", "label" => "Bedding"}]
          },
          %{
            "key" => "colour",
            "label" => "Colour",
            "type" => "swatch",
            "options" => [%{"value" => "white", "label" => "White", "hex" => "#ffffff"}]
          },
          %{
            "key" => "price",
            "label" => "Price",
            "type" => "range",
            "min" => 0,
            "max" => 500,
            "step" => 10,
            "currency" => "£"
          },
          %{
            "key" => "in_stock",
            "label" => "In Stock Only",
            "type" => "toggle"
          }
        ],
        "components" => []
      }

      filters = StorefrontRenderer.extract_filters(spec)
      assert length(filters) == 4
      [checkbox, swatch, range, toggle] = filters
      assert checkbox.type == "checkbox"
      assert checkbox.key == "category"
      assert length(checkbox.options) == 1
      assert swatch.type == "swatch"
      assert hd(swatch.options).hex == "#ffffff"
      assert range.type == "range"
      assert range.min == 0
      assert range.max == 500
      assert toggle.type == "toggle"
    end

    test "conditions: filters out component with before in the past" do
      spec = %{
        "components" => [
          %{
            "type" => "text_block",
            "data" => %{"title" => "Expired", "content" => "Gone"},
            "conditions" => %{"before" => "2020-01-01T00:00:00Z"}
          },
          %{
            "type" => "text_block",
            "data" => %{"title" => "Current", "content" => "Here"}
          }
        ]
      }

      comps = StorefrontRenderer.render_spec(spec)
      assert length(comps) == 1
      assert hd(comps).assigns.title == "Current"
    end

    test "conditions: keeps component with before in the future" do
      future = DateTime.utc_now() |> DateTime.add(86400) |> DateTime.to_iso8601()

      spec = %{
        "components" => [
          %{
            "type" => "text_block",
            "data" => %{"title" => "Active", "content" => "Here"},
            "conditions" => %{"before" => future}
          }
        ]
      }

      comps = StorefrontRenderer.render_spec(spec)
      assert length(comps) == 1
    end

    test "conditions: filters out component with after in the future" do
      future = DateTime.utc_now() |> DateTime.add(86400) |> DateTime.to_iso8601()

      spec = %{
        "components" => [
          %{
            "type" => "text_block",
            "data" => %{"title" => "NotYet", "content" => "Waiting"},
            "conditions" => %{"after" => future}
          }
        ]
      }

      comps = StorefrontRenderer.render_spec(spec)
      assert length(comps) == 0
    end

    test "conditions: viewport adds responsive_class to component assigns" do
      spec = %{
        "components" => [
          %{
            "type" => "text_block",
            "data" => %{"title" => "Desktop", "content" => "Only"},
            "conditions" => %{"min_width" => 768}
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.assigns.responsive_class == "sf-show-min-768"
    end

    test "conditions: viewport rejects non-integer min_width" do
      spec = %{
        "components" => [
          %{
            "type" => "text_block",
            "data" => %{"title" => "Bad", "content" => "Viewport"},
            "conditions" => %{"min_width" => "768\" onclick=\"alert(1)"}
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      refute Map.has_key?(comp.assigns, :responsive_class)
    end

    test "conditions: preview_only filters when not in preview" do
      spec = %{
        "components" => [
          %{
            "type" => "text_block",
            "data" => %{"title" => "Preview", "content" => "Only"},
            "conditions" => %{"preview_only" => true}
          }
        ]
      }

      comps = StorefrontRenderer.render_spec(spec)
      assert length(comps) == 0

      comps_preview = StorefrontRenderer.render_spec(spec, preview: true)
      assert length(comps_preview) == 1
    end

    test "product_detail normalizes variants" do
      spec = %{
        "components" => [
          %{
            "type" => "product_detail",
            "data" => %{
              "name" => "Duvet",
              "price" => "£89",
              "variants" => [
                %{
                  "id" => "var_1",
                  "colour" => "Natural",
                  "size" => "Double",
                  "price" => "£89",
                  "in_stock" => true
                }
              ]
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert length(comp.assigns.variants) == 1
      variant = hd(comp.assigns.variants)
      assert variant.id == "var_1"
      assert variant.colour == "Natural"
      assert variant.in_stock == true
    end

    test "product_detail normalizes breadcrumbs" do
      spec = %{
        "components" => [
          %{
            "type" => "product_detail",
            "data" => %{
              "name" => "Candle",
              "price" => "£32",
              "breadcrumbs" => [
                %{"label" => "Home", "href" => "/store"},
                %{"label" => "Fragrances", "href" => "/store/fragrances"},
                %{"label" => "Candle"}
              ]
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert length(comp.assigns.breadcrumbs) == 3
    end

    test "product_detail defaults quantity_max and stock_count" do
      spec = %{
        "components" => [
          %{
            "type" => "product_detail",
            "data" => %{"name" => "Item", "price" => "£10"}
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.assigns.variants == []
      assert comp.assigns.breadcrumbs == []
      assert comp.assigns.stock_count == nil
      assert comp.assigns.in_stock == true
    end

    test "normalizes video_hero component" do
      spec = %{
        "components" => [
          %{
            "type" => "video_hero",
            "data" => %{
              "video_url" => "/vid/story.mp4",
              "poster_url" => "/img/poster.jpg",
              "title" => "OUR STORY",
              "subtitle" => "Since 2020",
              "autoplay" => true,
              "loop" => true,
              "muted" => true
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.type == :video_hero
      assert comp.assigns.video_url == "/vid/story.mp4"
      assert comp.assigns.title == "OUR STORY"
      assert comp.assigns.autoplay == true
    end

    test "normalizes banner component" do
      spec = %{
        "components" => [
          %{
            "type" => "banner",
            "data" => %{
              "message" => "SPRING SALE",
              "background_color" => "#1a1a1a",
              "text_color" => "#ffffff"
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.type == :banner
      assert comp.assigns.message == "SPRING SALE"
    end

    test "normalizes spacer component" do
      spec = %{"components" => [%{"type" => "spacer", "data" => %{"height" => "64px"}}]}
      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.type == :spacer
      assert comp.assigns.height == "64px"
    end

    test "normalizes divider component" do
      spec = %{"components" => [%{"type" => "divider", "data" => %{"thickness" => "2px"}}]}
      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.type == :divider
    end

    test "normalizes image_grid component" do
      spec = %{
        "components" => [
          %{
            "type" => "image_grid",
            "data" => %{
              "columns" => 3,
              "images" => [
                %{"url" => "/img/1.jpg", "alt" => "Image 1"},
                %{"url" => "/img/2.jpg", "alt" => "Image 2"}
              ]
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.type == :image_grid
      assert length(comp.assigns.images) == 2
    end

    test "normalizes testimonials component" do
      spec = %{
        "components" => [
          %{
            "type" => "testimonials",
            "data" => %{
              "title" => "REVIEWS",
              "items" => [
                %{"quote" => "Amazing quality", "author" => "Jane", "rating" => 5}
              ]
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.type == :testimonials
      assert hd(comp.assigns.items).quote == "Amazing quality"
    end

    test "normalizes feature_list component" do
      spec = %{
        "components" => [
          %{
            "type" => "feature_list",
            "data" => %{
              "features" => [
                %{"icon" => "truck", "title" => "Free Shipping", "description" => "Over £50"}
              ]
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.type == :feature_list
      assert hd(comp.assigns.features).title == "Free Shipping"
    end

    test "extract_layout returns layout from content_json" do
      spec = %{"layout" => "landing", "components" => []}
      assert StorefrontRenderer.extract_layout(spec) == "landing"
    end

    test "extract_layout defaults to storefront" do
      spec = %{"components" => []}
      assert StorefrontRenderer.extract_layout(spec) == "storefront"
    end

    test "extract_layout rejects invalid layout" do
      spec = %{"layout" => "evil_layout", "components" => []}
      assert StorefrontRenderer.extract_layout(spec) == "storefront"
    end

    test "extract_sidebar returns sidebar config" do
      spec = %{
        "layout" => "storefront-sidebar",
        "sidebar" => %{
          "position" => "left",
          "width" => "280px",
          "sticky" => true,
          "components" => [
            %{"type" => "text_block", "data" => %{"heading" => "Side", "body" => "bar"}}
          ]
        },
        "components" => []
      }

      sidebar = StorefrontRenderer.extract_sidebar(spec)
      assert sidebar.position == "left"
      assert sidebar.width == "280px"
      assert sidebar.sticky == true
      assert length(sidebar.components) == 1
    end

    test "extract_sidebar returns nil when no sidebar" do
      spec = %{"components" => []}
      assert StorefrontRenderer.extract_sidebar(spec) == nil
    end

    test "extract_filters returns empty list when no filters" do
      spec = %{"components" => []}
      assert StorefrontRenderer.extract_filters(spec) == []
    end

    test "product_detail passes through layout field" do
      spec = %{
        "components" => [
          %{
            "type" => "product_detail",
            "data" => %{
              "name" => "Candle",
              "price" => "£32.00",
              "layout" => "centered"
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.assigns.layout == "centered"
    end

    test "product_detail defaults layout to gallery_sidebar" do
      spec = %{
        "components" => [
          %{
            "type" => "product_detail",
            "data" => %{"name" => "Item", "price" => "£10"}
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      assert comp.assigns.layout == "gallery_sidebar"
    end

    test "product defaults variant to default, badge to nil, compare_at_price to nil" do
      spec = %{
        "components" => [
          %{
            "type" => "product_grid",
            "data" => %{
              "products" => [
                %{"id" => "p1", "name" => "Item", "price" => "£10", "image_url" => "/x.jpg"}
              ]
            }
          }
        ]
      }

      [comp] = StorefrontRenderer.render_spec(spec)
      product = hd(comp.assigns.products)
      assert product.variant == "default"
      assert product.badge == nil
      assert product.compare_at_price == nil
      assert product.description == nil
    end

    test "style works on all component types" do
      style = %{"background" => "#f0f0f0", "padding" => "40px"}

      types = [
        {"announcement_bar", %{"message" => "Hi"}},
        {"editorial_hero", %{"image_url" => "/x.jpg", "title" => "T"}},
        {"editorial_full", %{"image_url" => "/x.jpg", "label" => "L"}},
        {"editorial_split",
         %{"left" => %{"image_url" => "/a.jpg"}, "right" => %{"image_url" => "/b.jpg"}}},
        {"product_grid", %{"products" => []}},
        {"product_scroll", %{"products" => []}},
        {"text_block", %{"content" => "text"}},
        {"category_nav", %{"links" => []}},
        {"product_detail", %{"name" => "X", "price" => "£1"}},
        {"related_products", %{"products" => []}}
      ]

      for {type, data} <- types do
        spec = %{"components" => [%{"type" => type, "data" => Map.put(data, "style", style)}]}
        [comp] = StorefrontRenderer.render_spec(spec)
        assert comp.assigns.style["background"] == "#f0f0f0", "#{type} should pass through style"
      end
    end
  end
end
