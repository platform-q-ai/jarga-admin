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
  @valid_sorts ~w(created_at:desc created_at:asc price:asc price:desc name:asc name:desc featured)

  @doc "Returns true if the component has a data source that needs hydration."
  def needs_hydration?(%{type: type, assigns: %{source: source}})
      when type in @hydratable_types and is_binary(source) and source != "" do
    true
  end

  def needs_hydration?(_), do: false

  @doc "Builds API query params from the component's source configuration."
  def build_api_params(%{source: source} = assigns) do
    base =
      case source do
        "newest" -> %{"sort" => "created_at:desc"}
        "featured" -> %{"featured" => "true"}
        "collection" -> %{"collection_id" => assigns[:collection_id]}
        "category" -> %{"category" => assigns[:category_slug]}
        _ -> nil
      end

    if base do
      base
      |> Map.put("limit", to_string(assigns[:limit] || 12))
      |> maybe_put_offset(assigns)
      |> maybe_put_sort(assigns, source)
      |> apply_filters(assigns)
    else
      %{}
    end
  end

  def build_api_params(_), do: %{}

  defp maybe_put_offset(params, %{offset: offset}) when is_integer(offset) and offset > 0 do
    Map.put(params, "offset", to_string(offset))
  end

  defp maybe_put_offset(params, _), do: params

  defp maybe_put_sort(params, %{sort: sort}, _source) when is_binary(sort) do
    if sort in @valid_sorts, do: Map.put(params, "sort", sort), else: params
  end

  defp maybe_put_sort(params, _, _source), do: params

  defp apply_filters(params, %{filters: filters}) when is_map(filters) do
    params
    |> maybe_put_price(filters, "price_min")
    |> maybe_put_price(filters, "price_max")
    |> maybe_put_tags(filters)
    |> maybe_put_in_stock(filters)
    |> maybe_put_exclude(filters)
  end

  defp apply_filters(params, _), do: params

  defp maybe_put_price(params, filters, key) do
    case filters[key] do
      val when is_number(val) and val >= 0 -> Map.put(params, key, to_string(val))
      _ -> params
    end
  end

  defp maybe_put_tags(params, %{"tags" => tags}) when is_list(tags) and tags != [] do
    safe_tags = tags |> Enum.filter(&is_binary/1) |> Enum.join(",")
    if safe_tags != "", do: Map.put(params, "tags", safe_tags), else: params
  end

  defp maybe_put_tags(params, _), do: params

  defp maybe_put_in_stock(params, %{"in_stock" => true}) do
    Map.put(params, "in_stock", "true")
  end

  defp maybe_put_in_stock(params, _), do: params

  defp maybe_put_exclude(params, %{"exclude_ids" => ids}) when is_list(ids) and ids != [] do
    safe_ids = ids |> Enum.filter(&is_binary/1) |> Enum.join(",")
    if safe_ids != "", do: Map.put(params, "exclude", safe_ids), else: params
  end

  defp maybe_put_exclude(params, _), do: params

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
  Uses parallel fetching for multiple hydratable components.
  """
  def hydrate_all(components) when is_list(components) do
    indexed = Enum.with_index(components)

    {to_hydrate, pass_through} =
      Enum.split_with(indexed, fn {comp, _idx} -> needs_hydration?(comp) end)

    hydrated =
      to_hydrate
      |> Task.async_stream(
        fn {comp, idx} -> {hydrate(comp), idx} end,
        max_concurrency: 4,
        timeout: 10_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    all = hydrated ++ Enum.map(pass_through, fn {comp, idx} -> {comp, idx} end)
    all |> Enum.sort_by(&elem(&1, 1)) |> Enum.map(&elem(&1, 0))
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
