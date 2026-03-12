defmodule JargaAdmin.PageRegistryTest do
  use ExUnit.Case, async: true

  alias JargaAdmin.PageRegistry

  @registry_data %{
    "pages" => [
      %{
        "slug" => "home",
        "title" => "Home",
        "position" => 0,
        "show_in_nav" => false,
        "seo_priority" => "1.0"
      },
      %{
        "slug" => "bedroom",
        "title" => "Bedroom",
        "position" => 1,
        "show_in_nav" => true,
        "seo_priority" => "0.8"
      },
      %{
        "slug" => "kitchen",
        "title" => "Kitchen & Dining",
        "position" => 2,
        "show_in_nav" => true,
        "seo_priority" => "0.8"
      },
      %{
        "slug" => "products/linen-duvet",
        "title" => "Linen Duvet Cover",
        "position" => 10,
        "show_in_nav" => false,
        "seo_priority" => "0.6"
      }
    ]
  }

  describe "parse/1" do
    test "parses registry data into ordered page list" do
      pages = PageRegistry.parse(@registry_data)
      assert length(pages) == 4
      assert Enum.at(pages, 0).slug == "home"
      assert Enum.at(pages, 1).slug == "bedroom"
      assert Enum.at(pages, 2).slug == "kitchen"
      assert Enum.at(pages, 3).slug == "products/linen-duvet"
    end

    test "normalizes page fields" do
      [home | _] = PageRegistry.parse(@registry_data)
      assert home.slug == "home"
      assert home.title == "Home"
      assert home.position == 0
      assert home.show_in_nav == false
      assert home.seo_priority == "1.0"
    end

    test "returns empty list for nil input" do
      assert PageRegistry.parse(nil) == []
    end

    test "returns empty list for empty map" do
      assert PageRegistry.parse(%{}) == []
    end

    test "returns empty list for missing pages key" do
      assert PageRegistry.parse(%{"other" => "data"}) == []
    end

    test "handles string payload (JSON encoded)" do
      json = Jason.encode!(@registry_data)
      pages = PageRegistry.parse(json)
      assert length(pages) == 4
    end

    test "defaults missing fields" do
      data = %{"pages" => [%{"slug" => "test"}]}
      [page] = PageRegistry.parse(data)
      assert page.title == "test"
      assert page.position == 0
      assert page.show_in_nav == false
      assert page.seo_priority == "0.5"
    end

    test "sorts by position" do
      data = %{
        "pages" => [
          %{"slug" => "c", "position" => 3},
          %{"slug" => "a", "position" => 1},
          %{"slug" => "b", "position" => 2}
        ]
      }

      pages = PageRegistry.parse(data)
      assert Enum.map(pages, & &1.slug) == ["a", "b", "c"]
    end

    test "sanitizes slugs" do
      data = %{"pages" => [%{"slug" => "../../../etc/passwd"}]}
      [page] = PageRegistry.parse(data)
      # Path traversal dots stripped, result is a valid slug segment
      assert page.slug == "etc/passwd"
      refute page.slug =~ ".."
    end
  end

  describe "nav_pages/1" do
    test "returns only pages with show_in_nav: true" do
      pages = PageRegistry.parse(@registry_data)
      nav = PageRegistry.nav_pages(pages)
      assert length(nav) == 2
      assert Enum.map(nav, & &1.slug) == ["bedroom", "kitchen"]
    end

    test "returns empty list when no nav pages" do
      data = %{"pages" => [%{"slug" => "home", "show_in_nav" => false}]}
      pages = PageRegistry.parse(data)
      assert PageRegistry.nav_pages(pages) == []
    end
  end

  describe "sitemap_pages/1" do
    test "returns all pages with slug and priority" do
      pages = PageRegistry.parse(@registry_data)
      sitemap = PageRegistry.sitemap_pages(pages)
      assert length(sitemap) == 4
      assert Enum.at(sitemap, 0).seo_priority == "1.0"
      assert Enum.at(sitemap, 3).seo_priority == "0.6"
    end
  end

  describe "nav_links/1" do
    test "converts nav pages to link format" do
      pages = PageRegistry.parse(@registry_data)
      links = PageRegistry.nav_links(pages)
      assert length(links) == 2

      assert Enum.at(links, 0) == %{
               "label" => "BEDROOM",
               "href" => "/store/bedroom"
             }

      assert Enum.at(links, 1) == %{
               "label" => "KITCHEN & DINING",
               "href" => "/store/kitchen"
             }
    end
  end
end
