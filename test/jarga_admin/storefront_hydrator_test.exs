defmodule JargaAdmin.StorefrontHydratorTest do
  use ExUnit.Case, async: true

  alias JargaAdmin.StorefrontHydrator

  describe "needs_hydration?/1" do
    test "returns true for components with a source field" do
      component = %{
        type: :product_grid,
        assigns: %{source: "newest", limit: 12, columns: 4, products: []}
      }

      assert StorefrontHydrator.needs_hydration?(component)
    end

    test "returns false for components without a source field" do
      component = %{
        type: :product_grid,
        assigns: %{products: [%{name: "Static Product"}], columns: 4}
      }

      refute StorefrontHydrator.needs_hydration?(component)
    end

    test "returns false for non-product components" do
      component = %{
        type: :editorial_hero,
        assigns: %{title: "Hero"}
      }

      refute StorefrontHydrator.needs_hydration?(component)
    end
  end

  describe "build_api_params/1" do
    test "builds params for newest source" do
      assigns = %{source: "newest", limit: 8}

      params = StorefrontHydrator.build_api_params(assigns)

      assert params["sort"] == "created_at:desc"
      assert params["limit"] == "8"
    end

    test "builds params for featured source" do
      assigns = %{source: "featured", limit: 4}

      params = StorefrontHydrator.build_api_params(assigns)

      assert params["featured"] == "true"
      assert params["limit"] == "4"
    end

    test "returns empty params for unknown source" do
      assigns = %{source: "unknown"}

      params = StorefrontHydrator.build_api_params(assigns)

      assert params == %{}
    end

    test "defaults limit to 12" do
      assigns = %{source: "newest"}

      params = StorefrontHydrator.build_api_params(assigns)

      assert params["limit"] == "12"
    end

    test "includes sort param when provided" do
      assigns = %{source: "category", category_slug: "bedroom", sort: "price:asc"}

      params = StorefrontHydrator.build_api_params(assigns)

      assert params["sort"] == "price:asc"
      assert params["category"] == "bedroom"
    end

    test "rejects invalid sort value and uses default" do
      assigns = %{source: "newest", sort: "invalid:sort"}

      params = StorefrontHydrator.build_api_params(assigns)

      # Should fall back to the source default sort
      assert params["sort"] == "created_at:desc"
    end

    test "includes price filter params" do
      assigns = %{
        source: "category",
        category_slug: "bedroom",
        filters: %{"price_min" => 20, "price_max" => 100}
      }

      params = StorefrontHydrator.build_api_params(assigns)

      assert params["price_min"] == "20"
      assert params["price_max"] == "100"
    end

    test "includes tag filter params" do
      assigns = %{
        source: "category",
        category_slug: "bedroom",
        filters: %{"tags" => ["organic", "linen"]}
      }

      params = StorefrontHydrator.build_api_params(assigns)

      assert params["tags"] == "organic,linen"
    end

    test "includes in_stock filter" do
      assigns = %{
        source: "category",
        category_slug: "bedroom",
        filters: %{"in_stock" => true}
      }

      params = StorefrontHydrator.build_api_params(assigns)

      assert params["in_stock"] == "true"
    end

    test "includes exclude_ids filter" do
      assigns = %{
        source: "newest",
        filters: %{"exclude_ids" => ["prod_123", "prod_456"]}
      }

      params = StorefrontHydrator.build_api_params(assigns)

      assert params["exclude"] == "prod_123,prod_456"
    end

    test "rejects negative price values" do
      assigns = %{
        source: "newest",
        filters: %{"price_min" => -10, "price_max" => 100}
      }

      params = StorefrontHydrator.build_api_params(assigns)

      refute Map.has_key?(params, "price_min")
      assert params["price_max"] == "100"
    end

    test "includes offset param" do
      assigns = %{source: "newest", offset: 24}

      params = StorefrontHydrator.build_api_params(assigns)

      assert params["offset"] == "24"
    end
  end

  describe "hydrate_all/1 ordering" do
    test "preserves component order with non-hydratable components" do
      components = [
        %{type: :editorial_hero, assigns: %{title: "Hero"}},
        %{type: :text_block, assigns: %{heading: "Text"}},
        %{type: :category_nav, assigns: %{categories: []}}
      ]

      result = StorefrontHydrator.hydrate_all(components)

      assert length(result) == 3
      assert Enum.at(result, 0).type == :editorial_hero
      assert Enum.at(result, 1).type == :text_block
      assert Enum.at(result, 2).type == :category_nav
    end
  end
end
