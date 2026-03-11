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
