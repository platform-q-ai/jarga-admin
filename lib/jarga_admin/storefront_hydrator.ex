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
        "category" -> %{"category_id" => assigns[:category_id]}
        _ -> nil
      end

    if base do
      base
      |> Map.put("limit", to_string(assigns[:limit] || 12))
      |> Map.put("status", "published")
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
          {:ok, %{"items" => items}} when is_list(items) ->
            Enum.map(items, &normalize_product/1)

          {:ok, items} when is_list(items) ->
            Enum.map(items, &normalize_product/1)

          {:error, reason} ->
            Logger.warning("StorefrontHydrator: failed to fetch products: #{inspect(reason)}")
            assigns[:products] || []

          _ ->
            assigns[:products] || []
        end

      # Apply display overrides from page spec (span, card_height, images, position)
      overrides = assigns[:display_overrides] || %{}
      products = apply_display_overrides(products, overrides)

      put_in(component, [:assigns, :products], products)
    end
  end

  @doc """
  Applies display overrides from the page spec onto hydrated products.

  Overrides are keyed by product slug and can set:
  - `span` — grid column span (1-4)
  - `card_height` — "flush" | "hero" | "auto"
  - `images` — multi-image layout [{url, alt, span}]
  - `position` — forced position in the grid (1-indexed)
  - `badge` — badge text (e.g. "NEW", "SALE")
  - `featured` — mark as featured
  """
  def apply_display_overrides(products, overrides) when overrides == %{}, do: products

  def apply_display_overrides(products, overrides) when is_map(overrides) do
    # First pass: merge overrides onto matching products
    products =
      Enum.map(products, fn product ->
        slug = extract_slug(product)

        case Map.get(overrides, slug) do
          nil -> product
          override when is_map(override) -> Map.merge(product, override)
        end
      end)

    # Second pass: reorder by position if any overrides specify position
    has_positions = Enum.any?(Map.values(overrides), &Map.has_key?(&1, :position))

    if has_positions do
      reorder_by_position(products, overrides)
    else
      products
    end
  end

  defp extract_slug(%{href: "/store/products/" <> slug}), do: slug
  defp extract_slug(%{id: "prod_" <> rest}), do: String.replace(rest, "_", "-")
  defp extract_slug(%{id: id}) when is_binary(id), do: id
  defp extract_slug(_), do: ""

  defp reorder_by_position(products, overrides) do
    # Build slug→position map
    positions =
      overrides
      |> Enum.filter(fn {_slug, o} -> Map.has_key?(o, :position) end)
      |> Map.new(fn {slug, o} -> {slug, o.position} end)

    # Split into positioned and unpositioned
    {positioned, unpositioned} =
      Enum.split_with(products, fn p -> Map.has_key?(positions, extract_slug(p)) end)

    # Sort positioned by their target position
    positioned = Enum.sort_by(positioned, fn p -> Map.get(positions, extract_slug(p), 999) end)

    # Interleave: insert positioned products at their target indices
    merge_at_positions(unpositioned, positioned, positions)
  end

  defp merge_at_positions(base, [], _positions), do: base

  defp merge_at_positions(base, positioned, positions) do
    # Insert each positioned product at its target 0-indexed position
    Enum.reduce(positioned, base, fn product, acc ->
      slug = extract_slug(product)
      pos = Map.get(positions, slug, length(acc)) - 1
      pos = max(0, min(pos, length(acc)))
      List.insert_at(acc, pos, product)
    end)
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
      |> Enum.zip(to_hydrate)
      |> Enum.map(fn
        {{:ok, result}, _original} ->
          result

        {{:exit, reason}, {comp, idx}} ->
          Logger.warning(
            "StorefrontHydrator: task failed for component #{idx}: #{inspect(reason)}"
          )

          {comp, idx}
      end)

    all = hydrated ++ Enum.map(pass_through, fn {comp, idx} -> {comp, idx} end)
    all |> Enum.sort_by(&elem(&1, 1)) |> Enum.map(&elem(&1, 0))
  end

  def hydrate_all(other), do: other

  @doc """
  Normalizes a PIM product into the storefront card format.

  PIM API returns products with these fields:
    - id, title, slug, vendor, product_type, description_html
    - tags, material, origin, category_id, status
    - variants: [{id, title, sku, currency, unit_amount, compare_at_amount, available, inventory_qty, ...}]
    - media: [{id, url, alt, position, media_type, ...}]

  The storefront card format uses:
    - id, name, price, price_cents, compare_at_price, image_url, hover_image_url
    - href, featured, variant, badge, description, colours, collection, tags
  """
  def normalize_product(product) when is_map(product) do
    slug = product["slug"] || ""
    variants = product["variants"] || []
    default_variant = List.first(variants)
    media = product["media"] || []
    tags = product["tags"] || []

    # Price from default variant
    {price, price_cents, compare_at_price} = extract_pricing(default_variant)

    # Images: try PIM media first, then fall back to slug-based convention
    {image_url, hover_image_url} = extract_images(media, slug)

    %{
      id: product["id"] || "",
      name: product["title"] || "",
      price: price,
      price_cents: price_cents,
      compare_at_price: compare_at_price,
      image_url: image_url,
      hover_image_url: hover_image_url,
      href: "/store/products/#{slug}",
      featured: "featured" in tags,
      variant: "default",
      badge: nil,
      description: strip_html(product["description_html"]),
      colours: [],
      collection: Enum.find(tags, fn t -> t not in ["featured"] end) || "",
      tags: tags,
      material: product["material"] || "",
      span: 1,
      card_height: "flush",
      images: []
    }
  end

  defp extract_pricing(nil), do: {"", 0, nil}

  defp extract_pricing(variant) do
    unit_amount = variant["unit_amount"] || 0
    currency = variant["currency"] || "GBP"
    compare_at = variant["compare_at_amount"]

    price = format_amount(unit_amount, currency)
    compare_at_price = if compare_at && compare_at > unit_amount, do: format_amount(compare_at, currency)

    {price, unit_amount, compare_at_price}
  end

  defp extract_images(media, _slug) when is_list(media) and media != [] do
    sorted = Enum.sort_by(media, & &1["position"])
    first = List.first(sorted)
    second = Enum.at(sorted, 1)
    {first["url"] || "", if(second, do: second["url"])}
  end

  defp extract_images(_media, slug) do
    # Fall back to slug-based image convention: /images/kinto/{slug}_{variant}.jpg
    angle = "/images/kinto/#{slug}_angle.jpg"
    coffee_shop = "/images/kinto/#{slug}_coffee_shop.jpg"
    {angle, coffee_shop}
  end

  defp format_amount(amount_cents, currency) when is_integer(amount_cents) do
    symbol =
      case currency do
        "GBP" -> "£"
        "USD" -> "$"
        "EUR" -> "€"
        _ -> currency <> " "
      end

    pounds = amount_cents / 100
    "#{symbol}#{:erlang.float_to_binary(pounds / 1, [{:decimals, 2}])}"
  end

  defp format_amount(_, _), do: ""

  defp strip_html(nil), do: ""
  defp strip_html(""), do: ""

  defp strip_html(html) when is_binary(html) do
    html
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
