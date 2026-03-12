defmodule JargaAdmin.StorefrontSearchTest do
  use ExUnit.Case, async: true

  alias JargaAdmin.StorefrontSearch

  @products [
    %{
      "id" => "prod_1",
      "title" => "Linen Shirt — Unisex",
      "slug" => "linen-shirt",
      "description_html" => "<p>A relaxed-fit linen shirt for warm days.</p>",
      "tags" => ["linen", "clothing", "summer"],
      "vendor" => "Jarga Atelier",
      "product_type" => "Clothing"
    },
    %{
      "id" => "prod_2",
      "title" => "Ceramic Mug — Slate",
      "slug" => "ceramic-mug-slate",
      "description_html" => "<p>Handmade ceramic mug in a matte slate finish.</p>",
      "tags" => ["ceramics", "kitchen", "handmade"],
      "vendor" => "Clay Studio",
      "product_type" => "Kitchenware"
    },
    %{
      "id" => "prod_3",
      "title" => "Linen Tea Towel Set",
      "slug" => "linen-tea-towel-set",
      "description_html" => "<p>Set of 3 stonewashed linen tea towels.</p>",
      "tags" => ["linen", "kitchen", "textile"],
      "vendor" => "Jarga Atelier",
      "product_type" => "Kitchenware"
    },
    %{
      "id" => "prod_4",
      "title" => "Soy Wax Scented Candle",
      "slug" => "soy-candle",
      "description_html" => "<p>Hand-poured soy wax candle with notes of cedar and vanilla.</p>",
      "tags" => ["candle", "fragrance", "home"],
      "vendor" => "Scent Co",
      "product_type" => "Fragrance"
    }
  ]

  describe "filter/2" do
    test "returns matching products by title" do
      results = StorefrontSearch.filter(@products, "linen")
      ids = Enum.map(results, & &1["id"])
      assert "prod_1" in ids
      assert "prod_3" in ids
      refute "prod_2" in ids
      refute "prod_4" in ids
    end

    test "matches case-insensitively" do
      results = StorefrontSearch.filter(@products, "CERAMIC")
      assert length(results) == 1
      assert hd(results)["id"] == "prod_2"
    end

    test "matches against tags" do
      results = StorefrontSearch.filter(@products, "handmade")
      assert length(results) == 1
      assert hd(results)["id"] == "prod_2"
    end

    test "matches against vendor" do
      results = StorefrontSearch.filter(@products, "clay studio")
      assert length(results) == 1
      assert hd(results)["id"] == "prod_2"
    end

    test "matches against product_type" do
      results = StorefrontSearch.filter(@products, "kitchenware")
      ids = Enum.map(results, & &1["id"])
      assert "prod_2" in ids
      assert "prod_3" in ids
    end

    test "matches against description (HTML stripped)" do
      results = StorefrontSearch.filter(@products, "cedar")
      assert length(results) == 1
      assert hd(results)["id"] == "prod_4"
    end

    test "matches partial words" do
      results = StorefrontSearch.filter(@products, "ceram")
      assert length(results) == 1
      assert hd(results)["id"] == "prod_2"
    end

    test "returns empty list for no matches" do
      results = StorefrontSearch.filter(@products, "xyznothing")
      assert results == []
    end

    test "handles empty query by returning all products" do
      results = StorefrontSearch.filter(@products, "")
      assert length(results) == 4
    end

    test "handles nil query by returning all products" do
      results = StorefrontSearch.filter(@products, nil)
      assert length(results) == 4
    end

    test "handles nil products gracefully" do
      assert StorefrontSearch.filter(nil, "test") == []
    end

    test "handles empty products list" do
      assert StorefrontSearch.filter([], "test") == []
    end

    test "handles products with missing fields" do
      products = [%{"id" => "prod_x", "title" => nil, "tags" => nil}]
      results = StorefrontSearch.filter(products, "anything")
      assert results == []
    end

    test "multi-word query matches all terms" do
      results = StorefrontSearch.filter(@products, "linen shirt")
      assert length(results) == 1
      assert hd(results)["id"] == "prod_1"
    end

    test "multi-word query across different fields" do
      # "linen kitchen" matches prod_3 (title: linen, tags: kitchen)
      results = StorefrontSearch.filter(@products, "linen kitchen")
      assert length(results) == 1
      assert hd(results)["id"] == "prod_3"
    end

    test "respects limit option" do
      results = StorefrontSearch.filter(@products, "linen", limit: 1)
      assert length(results) == 1
    end

    test "ranks title matches higher than description matches" do
      results = StorefrontSearch.filter(@products, "linen")
      # prod_1 and prod_3 both have "linen" in title — they should come first
      ids = Enum.map(results, & &1["id"])
      assert ids == ["prod_1", "prod_3"]
    end
  end
end
