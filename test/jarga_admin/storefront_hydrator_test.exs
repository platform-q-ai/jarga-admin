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
  end
end
