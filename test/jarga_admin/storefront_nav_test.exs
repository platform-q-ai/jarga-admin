defmodule JargaAdmin.StorefrontNavTest do
  use ExUnit.Case, async: true

  alias JargaAdmin.StorefrontNav

  @nav_data %{
    "items" => [
      %{
        "label" => "BEDROOM",
        "href" => "/store/bedroom",
        "highlight" => false,
        "children" => [
          %{"label" => "Bedding", "href" => "/store/bedroom?c=bedding"},
          %{"label" => "Furniture", "href" => "/store/bedroom?c=furniture"},
          %{"label" => "Lighting", "href" => "/store/bedroom?c=lighting"}
        ]
      },
      %{
        "label" => "KITCHEN",
        "href" => "/store/kitchen"
      },
      %{
        "label" => "SALE",
        "href" => "/store/sale",
        "highlight" => true
      }
    ]
  }

  describe "parse/1" do
    test "parses navigation items from map" do
      items = StorefrontNav.parse(@nav_data)
      assert length(items) == 3
    end

    test "preserves children" do
      [bedroom | _] = StorefrontNav.parse(@nav_data)
      assert length(bedroom["children"]) == 3
      assert hd(bedroom["children"])["label"] == "Bedding"
    end

    test "preserves highlight flag" do
      items = StorefrontNav.parse(@nav_data)
      sale = Enum.find(items, &(&1["label"] == "SALE"))
      assert sale["highlight"] == true
    end

    test "items without children have nil children" do
      items = StorefrontNav.parse(@nav_data)
      kitchen = Enum.find(items, &(&1["label"] == "KITCHEN"))
      assert kitchen["children"] == nil
    end

    test "parses from JSON string" do
      json = Jason.encode!(@nav_data)
      items = StorefrontNav.parse(json)
      assert length(items) == 3
    end

    test "returns empty list for nil" do
      assert StorefrontNav.parse(nil) == []
    end

    test "returns empty list for empty map" do
      assert StorefrontNav.parse(%{}) == []
    end

    test "sanitizes href values" do
      data = %{
        "items" => [
          %{"label" => "Evil", "href" => "javascript:alert(1)"}
        ]
      }

      items = StorefrontNav.parse(data)
      assert hd(items)["href"] == "#"
    end

    test "sanitizes children href values" do
      data = %{
        "items" => [
          %{
            "label" => "Parent",
            "href" => "/store/ok",
            "children" => [
              %{"label" => "Evil Child", "href" => "data:text/html,<script>alert(1)</script>"}
            ]
          }
        ]
      }

      items = StorefrontNav.parse(data)
      assert hd(hd(items)["children"])["href"] == "#"
    end

    test "limits label length" do
      data = %{
        "items" => [
          %{"label" => String.duplicate("A", 300), "href" => "/store/test"}
        ]
      }

      items = StorefrontNav.parse(data)
      assert String.length(hd(items)["label"]) <= 100
    end

    test "limits nesting depth to 1 level" do
      data = %{
        "items" => [
          %{
            "label" => "L1",
            "href" => "/store/l1",
            "children" => [
              %{
                "label" => "L2",
                "href" => "/store/l2",
                "children" => [%{"label" => "L3", "href" => "/store/l3"}]
              }
            ]
          }
        ]
      }

      items = StorefrontNav.parse(data)
      child = hd(hd(items)["children"])
      # L3 children should be stripped (max 1 level of nesting)
      refute Map.has_key?(child, "children")
    end
  end

  describe "mega_menu?/1" do
    test "returns true for items with 4+ children" do
      item = %{"children" => [%{}, %{}, %{}, %{}]}
      assert StorefrontNav.mega_menu?(item)
    end

    test "returns false for items with fewer than 4 children" do
      item = %{"children" => [%{}, %{}]}
      refute StorefrontNav.mega_menu?(item)
    end

    test "returns false for items with no children" do
      refute StorefrontNav.mega_menu?(%{"label" => "Test"})
    end
  end
end
