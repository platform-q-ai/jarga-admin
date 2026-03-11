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
  def render_spec(nil), do: []

  def render_spec(%{"components" => components}) when is_list(components) do
    Enum.map(components, &normalize_component/1)
  end

  def render_spec(_), do: []

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

    %{
      type: :product_detail,
      assigns: %{
        id: data["id"],
        name: data["name"] || "",
        price: data["price"] || "",
        layout: layout,
        images: data["images"] || [],
        description: data["description"],
        colours: data["colours"] || [],
        sizes: data["sizes"] || [],
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
