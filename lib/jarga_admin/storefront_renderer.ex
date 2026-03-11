defmodule JargaAdmin.StorefrontRenderer do
  @moduledoc """
  Converts a storefront UI spec (JSON from the Frontend API) into component
  assigns for rendering in StorefrontLive.

  Parallels `JargaAdmin.Renderer` for the admin panel but handles
  storefront-specific component types: editorial_hero, editorial_full,
  editorial_split, product_grid, product_card, product_scroll, product_detail,
  nav_bar, footer, announcement_bar, category_nav, text_block, etc.

  The spec is the `content_json` field from a Frontend API page:

      %{
        "layout" => "storefront",
        "components" => [
          %{"type" => "editorial_hero", "data" => %{...}},
          ...
        ]
      }
  """

  alias JargaAdmin.StyleValidator

  @doc """
  Parse a storefront spec into a list of renderable component assigns.

  Each element has:
    - `:type` — atom component type (e.g. `:editorial_hero`)
    - `:assigns` — map of assigns for the component function, including
      a validated `:style` map from the component's `data.style` field

  Returns an empty list for nil, missing components, or invalid input.
  """
  def render_spec(spec, opts \\ [])

  def render_spec(nil, _opts), do: []

  def render_spec(%{"components" => components}, opts) when is_list(components) do
    preview = Keyword.get(opts, :preview, false)
    now = DateTime.utc_now()

    components
    |> Enum.reduce([], fn raw, acc ->
      conditions = if is_map(raw), do: raw["conditions"], else: nil

      if evaluate_conditions(conditions, now, preview) do
        comp = normalize_component(raw)
        comp = apply_viewport_class(comp, conditions)
        [comp | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  def render_spec(_, _opts), do: []

  # ── Conditions evaluation ─────────────────────────────────────────────────

  defp evaluate_conditions(nil, _now, _preview), do: true

  defp evaluate_conditions(conditions, now, preview) when is_map(conditions) do
    Enum.all?(conditions, fn {key, val} -> evaluate_condition(key, val, now, preview) end)
  end

  defp evaluate_conditions(_, _now, _preview), do: true

  defp evaluate_condition("before", val, now, _preview) when is_binary(val) do
    case DateTime.from_iso8601(val) do
      {:ok, dt, _} -> DateTime.compare(now, dt) == :lt
      _ -> true
    end
  end

  defp evaluate_condition("after", val, now, _preview) when is_binary(val) do
    case DateTime.from_iso8601(val) do
      {:ok, dt, _} -> DateTime.compare(now, dt) in [:gt, :eq]
      _ -> true
    end
  end

  defp evaluate_condition("preview_only", true, _now, preview), do: preview == true

  # Viewport conditions are handled client-side via CSS, not filtered
  defp evaluate_condition("min_width", _val, _now, _preview), do: true
  defp evaluate_condition("max_width", _val, _now, _preview), do: true

  # Unknown conditions pass through
  defp evaluate_condition(_key, _val, _now, _preview), do: true

  defp apply_viewport_class(comp, nil), do: comp

  defp apply_viewport_class(comp, conditions) when is_map(conditions) do
    cond do
      Map.has_key?(conditions, "min_width") and is_integer(conditions["min_width"]) ->
        put_in(comp, [:assigns, :responsive_class], "sf-show-min-#{conditions["min_width"]}")

      Map.has_key?(conditions, "max_width") and is_integer(conditions["max_width"]) ->
        put_in(comp, [:assigns, :responsive_class], "sf-show-max-#{conditions["max_width"]}")

      true ->
        comp
    end
  end

  defp apply_viewport_class(comp, _), do: comp

  @valid_layouts ~w(storefront landing storefront-sidebar minimal overlay-nav)

  @doc "Extract page layout from content_json, validated against allowlist."
  def extract_layout(%{"layout" => layout}) when is_binary(layout) do
    if layout in @valid_layouts, do: layout, else: "storefront"
  end

  def extract_layout(_), do: "storefront"

  @doc "Extract sidebar config from content_json for storefront-sidebar layout."
  def extract_sidebar(%{"sidebar" => sidebar}) when is_map(sidebar) do
    components = render_spec(%{"components" => sidebar["components"] || []})

    %{
      position: sidebar["position"] || "left",
      width: sidebar["width"] || "280px",
      sticky: sidebar["sticky"] == true,
      components: components
    }
  end

  def extract_sidebar(_), do: nil

  @valid_filter_types ~w(checkbox swatch range toggle)

  @doc "Extract and normalize filter facets from page spec."
  def extract_filters(%{"filters" => filters}) when is_list(filters) do
    filters
    |> Enum.filter(fn f -> is_map(f) and f["type"] in @valid_filter_types end)
    |> Enum.map(&normalize_filter/1)
  end

  def extract_filters(_), do: []

  defp normalize_filter(%{"type" => "checkbox"} = f) do
    %{
      type: "checkbox",
      key: f["key"] || "",
      label: f["label"] || "",
      options: normalize_filter_options(f["options"])
    }
  end

  defp normalize_filter(%{"type" => "swatch"} = f) do
    %{
      type: "swatch",
      key: f["key"] || "",
      label: f["label"] || "",
      options:
        (f["options"] || [])
        |> Enum.map(fn o ->
          %{value: o["value"] || "", label: o["label"] || "", hex: o["hex"] || "#000000"}
        end)
    }
  end

  defp normalize_filter(%{"type" => "range"} = f) do
    %{
      type: "range",
      key: f["key"] || "",
      label: f["label"] || "",
      min: f["min"] || 0,
      max: f["max"] || 1000,
      step: f["step"] || 1,
      currency: f["currency"] || ""
    }
  end

  defp normalize_filter(%{"type" => "toggle"} = f) do
    %{
      type: "toggle",
      key: f["key"] || "",
      label: f["label"] || ""
    }
  end

  defp normalize_filter_options(nil), do: []

  defp normalize_filter_options(options) when is_list(options) do
    Enum.map(options, fn o -> %{value: o["value"] || "", label: o["label"] || ""} end)
  end

  # ── Editorial / Layout ──────────────────────────────────────────────────

  defp normalize_component(%{"type" => "editorial_hero", "data" => data}) do
    %{
      type: :editorial_hero,
      assigns: %{
        image_url: data["image_url"] || "",
        title: data["title"] || "",
        subtitle: data["subtitle"],
        cta: data["cta"],
        style: extract_style(data)
      }
    }
  end

  defp normalize_component(%{"type" => "editorial_full", "data" => data}) do
    %{
      type: :editorial_full,
      assigns: %{
        image_url: data["image_url"] || "",
        label: data["label"] || "",
        href: data["href"] || "#",
        style: extract_style(data)
      }
    }
  end

  defp normalize_component(%{"type" => "editorial_split", "data" => data}) do
    %{
      type: :editorial_split,
      assigns: %{
        left: normalize_split_panel(data["left"] || %{}),
        right: normalize_split_panel(data["right"] || %{}),
        style: extract_style(data)
      }
    }
  end

  defp normalize_component(%{"type" => "announcement_bar", "data" => data}) do
    %{
      type: :announcement_bar,
      assigns: %{
        message: data["message"] || "",
        href: data["href"],
        style: extract_style(data)
      }
    }
  end

  defp normalize_component(%{"type" => "nav_bar", "data" => data}) do
    %{
      type: :nav_bar,
      assigns: %{
        logo: data["logo"] || "JARGA",
        links: data["links"] || [],
        style: extract_style(data)
      }
    }
  end

  defp normalize_component(%{"type" => "footer", "data" => data}) do
    %{
      type: :footer,
      assigns: %{
        columns: data["columns"] || [],
        copyright: data["copyright"] || "© #{Date.utc_today().year} Jarga Commerce",
        style: extract_style(data)
      }
    }
  end

  defp normalize_component(%{"type" => "category_nav", "data" => data}) do
    %{
      type: :category_nav,
      assigns: %{
        links: data["links"] || [],
        style: extract_style(data)
      }
    }
  end

  defp normalize_component(%{"type" => "text_block", "data" => data}) do
    %{
      type: :text_block,
      assigns: %{
        title: data["title"],
        content: data["content"] || "",
        style: extract_style(data)
      }
    }
  end

  # ── New component types ─────────────────────────────────────────────────

  defp normalize_component(%{"type" => "video_hero", "data" => data}) do
    %{
      type: :video_hero,
      assigns: %{
        video_url: data["video_url"] || "",
        poster_url: data["poster_url"],
        title: data["title"],
        subtitle: data["subtitle"],
        cta: data["cta"],
        autoplay: data["autoplay"] == true,
        loop: data["loop"] == true,
        muted: data["muted"] != false,
        style: extract_style(data)
      }
    }
  end

  defp normalize_component(%{"type" => "banner", "data" => data}) do
    %{
      type: :banner,
      assigns: %{
        message: data["message"] || "",
        background_color: data["background_color"],
        text_color: data["text_color"],
        cta: data["cta"],
        countdown_to: data["countdown_to"],
        style: extract_style(data)
      }
    }
  end

  defp normalize_component(%{"type" => "spacer", "data" => data}) do
    %{
      type: :spacer,
      assigns: %{
        height: data["height"] || "48px",
        style: extract_style(data)
      }
    }
  end

  defp normalize_component(%{"type" => "divider", "data" => data}) do
    %{
      type: :divider,
      assigns: %{
        thickness: data["thickness"] || "1px",
        color: data["color"],
        max_width: data["max_width"],
        style: extract_style(data)
      }
    }
  end

  defp normalize_component(%{"type" => "image_grid", "data" => data}) do
    images =
      (data["images"] || [])
      |> Enum.map(fn img ->
        %{url: img["url"] || "", alt: img["alt"] || "", href: img["href"]}
      end)

    %{
      type: :image_grid,
      assigns: %{
        columns: data["columns"] || 3,
        images: images,
        gap: data["gap"] || "4px",
        style: extract_style(data)
      }
    }
  end

  defp normalize_component(%{"type" => "testimonials", "data" => data}) do
    items =
      (data["items"] || [])
      |> Enum.map(fn t ->
        %{
          quote: t["quote"] || "",
          author: t["author"] || "",
          role: t["role"],
          avatar_url: t["avatar_url"],
          rating: t["rating"]
        }
      end)

    %{
      type: :testimonials,
      assigns: %{
        title: data["title"],
        items: items,
        style: extract_style(data)
      }
    }
  end

  defp normalize_component(%{"type" => "feature_list", "data" => data}) do
    features =
      (data["features"] || [])
      |> Enum.map(fn f ->
        %{
          icon: f["icon"],
          title: f["title"] || "",
          description: f["description"] || ""
        }
      end)

    %{
      type: :feature_list,
      assigns: %{
        features: features,
        layout: data["layout"] || "horizontal",
        style: extract_style(data)
      }
    }
  end

  # ── Product components ─────────────────────────────────────────────────

  defp normalize_component(%{"type" => "product_scroll", "data" => data}) do
    assigns =
      %{
        title: data["title"] || "",
        products: normalize_products(data["products"] || []),
        style: extract_style(data)
      }
      |> maybe_add_source(data)

    %{type: :product_scroll, assigns: assigns}
  end

  defp normalize_component(%{"type" => "product_grid", "data" => data}) do
    assigns =
      %{
        title: data["title"],
        columns: data["columns"] || 3,
        products: normalize_products(data["products"] || []),
        style: extract_style(data)
      }
      |> maybe_add_source(data)

    %{type: :product_grid, assigns: assigns}
  end

  @valid_pdp_layouts ~w(gallery_sidebar centered full_width split stacked)

  defp normalize_component(%{"type" => "product_detail", "data" => data}) do
    layout = if data["layout"] in @valid_pdp_layouts, do: data["layout"], else: "gallery_sidebar"

    variants =
      (data["variants"] || [])
      |> Enum.map(fn v ->
        %{
          id: v["id"],
          colour: v["colour"],
          colour_hex: v["colour_hex"],
          size: v["size"],
          price: v["price"],
          compare_at_price: v["compare_at_price"],
          sku: v["sku"],
          in_stock: v["in_stock"] != false,
          stock_count: v["stock_count"],
          image_index: v["image_index"]
        }
      end)

    breadcrumbs =
      (data["breadcrumbs"] || [])
      |> Enum.map(fn b ->
        %{label: b["label"] || "", href: b["href"]}
      end)

    %{
      type: :product_detail,
      assigns: %{
        id: data["id"],
        name: data["name"] || "",
        price: data["price"] || "",
        compare_at_price: data["compare_at_price"],
        layout: layout,
        images: data["images"] || [],
        description: data["description"],
        colours: data["colours"] || [],
        sizes: data["sizes"] || [],
        variants: variants,
        breadcrumbs: breadcrumbs,
        in_stock: data["in_stock"] != false,
        stock_count: data["stock_count"],
        quantity_max: data["quantity_max"] || 10,
        accordion: data["accordion"] || [],
        style: extract_style(data)
      }
    }
  end

  # ── Catch-all ──────────────────────────────────────────────────────────

  defp normalize_component(%{"type" => "related_products", "data" => data}) do
    assigns =
      %{
        title: data["title"] || "YOU MAY ALSO LIKE",
        products: normalize_products(data["products"] || []),
        style: extract_style(data)
      }
      |> maybe_add_source(data)

    %{type: :related_products, assigns: assigns}
  end

  defp normalize_component(unknown) do
    %{type: :unknown, assigns: %{raw: unknown}}
  end

  # ── Helpers ────────────────────────────────────────────────────────────

  defp extract_style(data) when is_map(data) do
    StyleValidator.validate(data["style"])
  end

  defp extract_style(_), do: %{}

  defp normalize_split_panel(panel) do
    %{
      image_url: panel["image_url"] || "",
      label: panel["label"] || "",
      href: panel["href"] || "#"
    }
  end

  defp maybe_add_source(assigns, %{"source" => source} = data)
       when is_binary(source) and source != "" do
    assigns
    |> Map.put(:source, source)
    |> Map.put(:limit, data["limit"])
    |> Map.put(:offset, data["offset"])
    |> Map.put(:sort, data["sort"])
    |> Map.put(:filters, data["filters"])
    |> Map.put(:collection_id, data["collection_id"])
    |> Map.put(:category_slug, data["category_slug"])
  end

  defp maybe_add_source(assigns, _data), do: assigns

  defp normalize_products(products) when is_list(products) do
    Enum.map(products, fn p ->
      %{
        id: p["id"],
        name: p["name"] || "",
        price: p["price"] || "",
        compare_at_price: p["compare_at_price"],
        image_url: p["image_url"] || "",
        hover_image_url: p["hover_image_url"],
        href: p["href"] || "#",
        featured: p["featured"] == true,
        variant: p["variant"] || "default",
        badge: p["badge"],
        description: p["description"],
        colours: p["colours"] || []
      }
    end)
  end

  defp normalize_products(_), do: []
end
