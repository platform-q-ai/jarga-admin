defmodule JargaAdmin.StorefrontHydrator do
  @moduledoc """
  Hydrates storefront components with live product data from the PIM API.

  Page specs can define data sources (`source` field) instead of inline product data.
  The hydrator detects these and fetches current data at render time, keeping
  prices, stock, and images fresh without republishing pages.

  ## Supported Sources

  - `"newest"` — products sorted by creation date (descending)
  - `"featured"` — products flagged as featured
  - `"collection"` — products in a specific collection
  - `"category"` — products in a specific category
  """

  alias JargaAdmin.Api

  require Logger

  @hydratable_types [:product_grid, :product_scroll, :related_products]

  @doc "Returns true if the component has a data source that needs hydration."
  def needs_hydration?(%{type: type, assigns: %{source: source}})
      when type in @hydratable_types and is_binary(source) and source != "" do
    true
  end

  def needs_hydration?(_), do: false

  @doc "Builds API query params from the component's source configuration."
  def build_api_params(%{source: "newest"} = assigns) do
    %{
      "sort" => "created_at:desc",
      "limit" => to_string(assigns[:limit] || 12)
    }
  end

  def build_api_params(%{source: "featured"} = assigns) do
    %{
      "featured" => "true",
      "limit" => to_string(assigns[:limit] || 12)
    }
  end

  def build_api_params(%{source: "collection", collection_id: id} = assigns) do
    %{
      "collection_id" => id,
      "limit" => to_string(assigns[:limit] || 12)
    }
  end

  def build_api_params(%{source: "category", category_slug: slug} = assigns) do
    %{
      "category" => slug,
      "limit" => to_string(assigns[:limit] || 12)
    }
  end

  def build_api_params(_), do: %{}

  @doc """
  Hydrates a single component with live product data.

  Fetches products from the PIM API based on the source configuration
  and replaces the component's product list.
  """
  def hydrate(%{assigns: assigns} = component) do
    params = build_api_params(assigns)

    if params == %{} do
      component
    else
      # TODO: batch/parallelize hydration when multiple components need data
      products =
        case Api.list_products(params) do
          {:ok, products} when is_list(products) ->
            Enum.map(products, &normalize_product/1)

          {:error, reason} ->
            Logger.warning("StorefrontHydrator: failed to fetch products: #{inspect(reason)}")
            assigns[:products] || []

          _ ->
            assigns[:products] || []
        end

      put_in(component, [:assigns, :products], products)
    end
  end

  @doc """
  Hydrates all components in a list that need hydration.

  Components without a source field are passed through unchanged.
  """
  def hydrate_all(components) when is_list(components) do
    Enum.map(components, fn component ->
      if needs_hydration?(component) do
        hydrate(component)
      else
        component
      end
    end)
  end

  def hydrate_all(other), do: other

  defp normalize_product(product) when is_map(product) do
    images = product["images"] || []
    first_image = List.first(images)

    %{
      id: product["id"],
      name: product["name"] || "",
      price: format_price(product["price"]),
      image_url: if(first_image, do: first_image["url"], else: ""),
      hover_image_url: nil,
      href: "/store/products/#{product["slug"]}",
      featured: product["featured"] == true,
      colours: []
    }
  end

  defp format_price(%{"amount" => amount, "currency" => currency}) do
    symbol =
      case currency do
        "GBP" -> "£"
        "USD" -> "$"
        "EUR" -> "€"
        _ -> currency <> " "
      end

    "#{symbol}#{amount}"
  end

  defp format_price(_), do: ""
end
