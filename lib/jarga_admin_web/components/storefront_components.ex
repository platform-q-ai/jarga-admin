defmodule JargaAdminWeb.StorefrontComponents do
  @moduledoc """
  Customer-facing storefront HEEx components — Zara Home inspired.

  Luxury-minimal editorial design: Helvetica Neue, thin typography,
  pure white backgrounds, black accents, zero border-radius.
  """
  use Phoenix.Component

  alias JargaAdmin.StyleValidator

  # ── Announcement Bar ──────────────────────────────────────────────────────

  attr :message, :string, required: true
  attr :href, :string, default: nil
  attr :style, :map, default: %{}

  def announcement_bar(assigns) do
    assigns = assign(assigns, :inline_style, StyleValidator.to_inline_style(assigns.style))

    ~H"""
    <div class="sf-announcement" id="sf-announcement" style={@inline_style}>
      <%= if @href do %>
        <a href={@href} class="sf-announcement-link">{@message}</a>
      <% else %>
        <span>{@message}</span>
      <% end %>
    </div>
    """
  end

  # ── Nav Bar ───────────────────────────────────────────────────────────────

  attr :logo, :string, default: "JARGA"
  attr :links, :list, default: []
  attr :cart_count, :integer, default: 0

  def nav_bar(assigns) do
    ~H"""
    <nav class="sf-nav" id="sf-nav" phx-hook="StorefrontNav">
      <div class="sf-nav-inner">
        <button class="sf-nav-hamburger" phx-click="toggle_mobile_menu" aria-label="Menu">
          <span class="sf-hamburger-line"></span>
          <span class="sf-hamburger-line"></span>
        </button>

        <a href="/" class="sf-nav-logo">{@logo}</a>

        <div class="sf-nav-links">
          <%= for link <- @links do %>
            <%= if link["children"] do %>
              <div class="sf-nav-dropdown">
                <span class={[
                  "sf-nav-link sf-nav-link-parent",
                  link["highlight"] && "sf-nav-highlight"
                ]}>
                  {link["label"]}
                </span>
                <div class="sf-nav-dropdown-panel">
                  <a
                    :for={child <- link["children"]}
                    href={safe_href(child["href"])}
                    class="sf-nav-dropdown-link"
                  >
                    {child["label"]}
                  </a>
                </div>
              </div>
            <% else %>
              <a
                href={safe_href(link["href"])}
                class={["sf-nav-link", link["highlight"] && "sf-nav-highlight"]}
              >
                {link["label"]}
              </a>
            <% end %>
          <% end %>
        </div>

        <div class="sf-nav-actions">
          <button class="sf-nav-icon" aria-label="Search" phx-click="toggle_search">
            <.search_icon />
          </button>
          <button class="sf-nav-icon sf-cart-btn" aria-label="Basket" phx-click="toggle_cart">
            <.bag_icon />
            <span :if={@cart_count > 0} class="sf-cart-badge">{@cart_count}</span>
          </button>
        </div>
      </div>
    </nav>
    """
  end

  # ── Editorial Hero ────────────────────────────────────────────────────────

  attr :image_url, :string, required: true
  attr :title, :string, default: ""
  attr :subtitle, :string, default: nil
  attr :cta, :map, default: nil
  attr :style, :map, default: %{}

  def editorial_hero(assigns) do
    assigns =
      assigns
      |> assign(:inline_style, StyleValidator.to_inline_style(assigns.style))
      |> assign(:title_style, StyleValidator.title_style(assigns.style))

    ~H"""
    <section class="sf-hero" id="sf-hero" style={@inline_style}>
      <div class="sf-hero-image-wrap">
        <img src={@image_url} alt={@title} class="sf-hero-image" loading="eager" />
      </div>
      <div class="sf-hero-overlay">
        <h1 class="sf-hero-title" style={@title_style}>{@title}</h1>
        <p :if={@subtitle} class="sf-hero-subtitle">{@subtitle}</p>
        <a :if={@cta} href={safe_href(@cta["href"])} class="sf-hero-cta">{@cta["label"]}</a>
      </div>
    </section>
    """
  end

  # ── Editorial Full ────────────────────────────────────────────────────────

  attr :image_url, :string, required: true
  attr :label, :string, default: ""
  attr :href, :string, default: "#"
  attr :style, :map, default: %{}

  def editorial_full(assigns) do
    assigns = assign(assigns, :inline_style, StyleValidator.to_inline_style(assigns.style))

    ~H"""
    <section class="sf-editorial-full" style={@inline_style}>
      <a href={safe_href(@href)} class="sf-editorial-full-link">
        <img src={@image_url} alt={@label} class="sf-editorial-full-image" loading="lazy" />
        <span class="sf-editorial-full-label">{@label}</span>
      </a>
    </section>
    """
  end

  # ── Editorial Split ───────────────────────────────────────────────────────

  attr :left, :map, required: true
  attr :right, :map, required: true
  attr :style, :map, default: %{}

  def editorial_split(assigns) do
    assigns = assign(assigns, :inline_style, StyleValidator.to_inline_style(assigns.style))

    ~H"""
    <section class="sf-editorial-split" style={@inline_style}>
      <a href={safe_href(@left.href)} class="sf-editorial-split-panel">
        <img src={@left.image_url} alt={@left.label} class="sf-editorial-split-image" loading="lazy" />
        <span class="sf-editorial-split-label">{@left.label}</span>
      </a>
      <a href={safe_href(@right.href)} class="sf-editorial-split-panel">
        <img
          src={@right.image_url}
          alt={@right.label}
          class="sf-editorial-split-image"
          loading="lazy"
        />
        <span class="sf-editorial-split-label">{@right.label}</span>
      </a>
    </section>
    """
  end

  # ── Product Scroll ────────────────────────────────────────────────────────

  attr :title, :string, default: ""
  attr :products, :list, default: []
  attr :style, :map, default: %{}

  def product_scroll(assigns) do
    assigns =
      assigns
      |> assign(:inline_style, StyleValidator.to_inline_style(assigns.style))
      |> assign(:title_style, StyleValidator.title_style(assigns.style))

    ~H"""
    <section class="sf-product-scroll" style={@inline_style}>
      <h2 :if={@title != ""} class="sf-section-title" style={@title_style}>{@title}</h2>
      <div class="sf-product-scroll-track">
        <.product_card :for={product <- @products} product={product} />
      </div>
    </section>
    """
  end

  # ── Product Grid ──────────────────────────────────────────────────────────

  attr :title, :string, default: nil
  attr :columns, :integer, default: 3
  attr :products, :list, default: []
  attr :style, :map, default: %{}

  def product_grid(assigns) do
    assigns =
      assigns
      |> assign(:inline_style, StyleValidator.to_inline_style(assigns.style))
      |> assign(:title_style, StyleValidator.title_style(assigns.style))
      |> assign(:card_style, StyleValidator.card_style(assigns.style))

    ~H"""
    <section class="sf-product-grid" style={@inline_style}>
      <h2 :if={@title} class="sf-section-title" style={@title_style}>{@title}</h2>
      <div class={["sf-grid", safe_grid_class(@columns)]}>
        <.product_card :for={product <- @products} product={product} card_style={@card_style} />
      </div>
    </section>
    """
  end

  # ── Product Card ──────────────────────────────────────────────────────────

  attr :product, :map, required: true
  attr :card_style, :string, default: ""

  def product_card(assigns) do
    variant = assigns.product[:variant] || "default"

    variant_class =
      case variant do
        "editorial" -> "sf-card-editorial"
        "minimal" -> "sf-card-minimal"
        "detailed" -> "sf-card-detailed"
        _ -> nil
      end

    assigns = assign(assigns, :variant_class, variant_class)

    ~H"""
    <a
      href={safe_href(@product.href)}
      class={[
        "sf-product-card",
        @product.featured && "sf-featured",
        @variant_class
      ]}
      style={@card_style}
    >
      <div
        class="sf-product-card-image-wrap"
        id={"product-#{@product.id}"}
        data-has-hover={@product.hover_image_url && "true"}
      >
        <span :if={@product[:badge]} class="sf-product-badge">{@product.badge}</span>
        <img
          src={@product.image_url}
          alt={@product.name}
          class="sf-product-card-image"
          loading="eager"
        />
        <img
          :if={@product.hover_image_url}
          src={@product.hover_image_url}
          alt={@product.name}
          class="sf-product-card-image sf-product-card-hover"
          loading="lazy"
        />
      </div>
      <div class="sf-product-card-info">
        <span class="sf-product-card-name">{@product.name}</span>
        <div class="sf-product-card-price-row">
          <span :if={@product[:compare_at_price]} class="sf-product-card-price-was">
            {@product.compare_at_price}
          </span>
          <span class={[
            "sf-product-card-price",
            @product[:compare_at_price] && "sf-product-card-price-sale"
          ]}>
            {@product.price}
          </span>
        </div>
        <p :if={@product[:description]} class="sf-product-card-description">
          {@product.description}
        </p>
        <div :if={@product[:colours] && @product.colours != []} class="sf-product-card-swatches">
          <span
            :for={colour <- Enum.take(@product.colours, 4)}
            class="sf-product-card-swatch"
            style={"background-color: #{sanitize_hex(colour["hex"])}"}
            title={colour["name"]}
          >
          </span>
        </div>
        <button
          :if={(@product[:variant] || "default") == "detailed"}
          class="sf-card-add-btn"
          phx-click="add_to_cart"
          phx-value-id={@product.id}
          phx-value-name={@product.name}
          phx-value-price={@product.price}
          phx-value-image_url={@product.image_url}
        >
          ADD TO BASKET
        </button>
      </div>
    </a>
    """
  end

  # ── Product Detail ────────────────────────────────────────────────────────

  attr :id, :string, default: nil
  attr :name, :string, required: true
  attr :price, :string, required: true
  attr :layout, :string, default: "gallery_sidebar"
  attr :images, :list, default: []
  attr :description, :string, default: nil
  attr :colours, :list, default: []
  attr :sizes, :list, default: []
  attr :accordion, :list, default: []
  attr :style, :map, default: %{}

  @pdp_layout_classes %{
    "gallery_sidebar" => "sf-pdp-gallery-sidebar",
    "centered" => "sf-pdp-centered",
    "full_width" => "sf-pdp-full-width",
    "split" => "sf-pdp-split",
    "stacked" => "sf-pdp-stacked"
  }

  def product_detail(assigns) do
    layout_class = Map.get(@pdp_layout_classes, assigns.layout, "sf-pdp-gallery-sidebar")

    assigns =
      assigns
      |> assign(:inline_style, StyleValidator.to_inline_style(assigns.style))
      |> assign(:title_style, StyleValidator.title_style(assigns.style))
      |> assign(:layout_class, layout_class)

    ~H"""
    <section class={["sf-product-detail", @layout_class]} id="sf-product-detail" style={@inline_style}>
      <div class="sf-pdp-gallery">
        <img
          :for={image <- @images}
          src={image}
          alt={@name}
          class="sf-pdp-gallery-image"
          loading="lazy"
        />
      </div>
      <div class="sf-pdp-info">
        <h1 class="sf-pdp-name" style={@title_style}>{@name}</h1>
        <p class="sf-pdp-price">{@price}</p>

        <p :if={@description} class="sf-pdp-description">{@description}</p>

        <div :if={@colours != []} class="sf-pdp-colours">
          <div
            :for={colour <- @colours}
            class="sf-pdp-colour-swatch"
            style={"background-color: #{sanitize_hex(colour["hex"])}"}
            title={colour["name"]}
          >
          </div>
        </div>

        <div :if={@sizes != []} class="sf-pdp-sizes">
          <button :for={size <- @sizes} class="sf-pdp-size">{size}</button>
        </div>

        <button class="sf-btn-primary sf-pdp-add" phx-click="add_to_cart" phx-value-id={@id}>
          ADD TO BASKET
        </button>

        <div :if={@accordion != []} class="sf-pdp-accordion">
          <details :for={section <- @accordion} class="sf-pdp-accordion-item">
            <summary class="sf-pdp-accordion-title">{section["title"]}</summary>
            <div class="sf-pdp-accordion-content">{section["content"]}</div>
          </details>
        </div>
      </div>
    </section>
    """
  end

  # ── Category Nav ──────────────────────────────────────────────────────────

  attr :links, :list, default: []
  attr :style, :map, default: %{}

  def category_nav(assigns) do
    assigns = assign(assigns, :inline_style, StyleValidator.to_inline_style(assigns.style))

    ~H"""
    <nav class="sf-category-nav" style={@inline_style}>
      <a :for={link <- @links} href={safe_href(link["href"])} class="sf-category-nav-link">
        {link["label"]}
      </a>
    </nav>
    """
  end

  # ── Text Block ────────────────────────────────────────────────────────────

  attr :title, :string, default: nil
  attr :content, :string, default: ""
  attr :style, :map, default: %{}

  def text_block(assigns) do
    assigns =
      assigns
      |> assign(:inline_style, StyleValidator.to_inline_style(assigns.style))
      |> assign(:title_style, StyleValidator.title_style(assigns.style))

    ~H"""
    <section class="sf-text-block" style={@inline_style}>
      <h2 :if={@title} class="sf-text-block-title" style={@title_style}>{@title}</h2>
      <div class="sf-text-block-content">{@content}</div>
    </section>
    """
  end

  # ── Footer ───────────────────────────────────────────────────────────────

  attr :columns, :list, default: []
  attr :copyright, :string, default: ""

  def storefront_footer(assigns) do
    ~H"""
    <footer class="sf-footer" id="sf-footer">
      <div class="sf-footer-inner">
        <div class="sf-newsletter">
          <h3 class="sf-newsletter-title">Subscribe to our newsletter</h3>
          <p class="sf-newsletter-text">
            Be the first to know about new collections, exclusive offers, and design inspiration.
          </p>
          <form class="sf-newsletter-form" phx-submit="newsletter_subscribe">
            <input
              type="email"
              name="email"
              placeholder="Enter your email address"
              class="sf-newsletter-input"
              required
            />
            <button type="submit" class="sf-newsletter-submit">Subscribe</button>
          </form>
        </div>
        <div class="sf-footer-columns">
          <div :for={col <- @columns} class="sf-footer-column">
            <h3 class="sf-footer-column-title">{col["title"]}</h3>
            <ul class="sf-footer-column-links">
              <li :for={link <- col["links"] || []}>
                <a href={safe_href(link["href"])} class="sf-footer-link">{link["label"]}</a>
              </li>
            </ul>
          </div>
        </div>
        <div class="sf-footer-bottom">
          <span class="sf-footer-copyright">{@copyright}</span>
        </div>
      </div>
    </footer>
    """
  end

  # ── Cart Drawer ───────────────────────────────────────────────────────────

  attr :open, :boolean, default: false
  attr :items, :list, default: []
  attr :subtotal, :string, default: "£0.00"

  def cart_drawer(assigns) do
    ~H"""
    <div class={["sf-cart-drawer", @open && "sf-cart-drawer-open"]} id="sf-cart-drawer">
      <div class="sf-cart-drawer-overlay" phx-click="toggle_cart"></div>
      <div class="sf-cart-drawer-panel">
        <div class="sf-cart-drawer-header">
          <h2 class="sf-cart-drawer-title">BASKET</h2>
          <button class="sf-cart-drawer-close" phx-click="toggle_cart" aria-label="Close">×</button>
        </div>
        <div :if={@items == []} class="sf-cart-drawer-empty">
          <p>Your basket is empty</p>
        </div>
        <div :if={@items != []} class="sf-cart-drawer-items">
          <div :for={item <- @items} class="sf-cart-drawer-item">
            <img src={item["image_url"]} alt={item["name"]} class="sf-cart-item-image" />
            <div class="sf-cart-item-info">
              <span class="sf-cart-item-name">{item["name"]}</span>
              <span class="sf-cart-item-price">{item["price"]}</span>
            </div>
          </div>
        </div>
        <div :if={@items != []} class="sf-cart-drawer-footer">
          <div class="sf-cart-subtotal">
            <span>Subtotal</span>
            <span>{@subtotal}</span>
          </div>
          <button class="sf-btn-primary sf-cart-checkout">CHECKOUT</button>
          <button class="sf-btn-secondary" phx-click="toggle_cart">CONTINUE SHOPPING</button>
        </div>
      </div>
    </div>
    """
  end

  # ── Sanitization helpers ──────────────────────────────────────────────────

  @valid_grid_columns %{
    1 => "sf-grid-1",
    2 => "sf-grid-2",
    3 => "sf-grid-3",
    4 => "sf-grid-4",
    5 => "sf-grid-5",
    6 => "sf-grid-6"
  }

  @doc false
  def safe_grid_class(columns) when is_integer(columns) do
    Map.get(@valid_grid_columns, columns, "sf-grid-3")
  end

  def safe_grid_class(_), do: "sf-grid-3"

  def sanitize_hex(nil), do: "transparent"

  def sanitize_hex(hex) when is_binary(hex) do
    # Only allow valid CSS hex colours (#rgb, #rrggbb, #rrggbbaa)
    if Regex.match?(~r/\A#[0-9a-fA-F]{3,8}\z/, hex) do
      hex
    else
      "transparent"
    end
  end

  def sanitize_hex(_), do: "transparent"

  def safe_href(nil), do: "#"

  def safe_href(href) when is_binary(href) do
    # Block javascript:, data:, vbscript: URI schemes
    trimmed = String.trim(href)

    if Regex.match?(~r/\A(javascript|data|vbscript):/i, trimmed) do
      "#"
    else
      trimmed
    end
  end

  def safe_href(_), do: "#"

  # ── Gallery Zoom ──────────────────────────────────────────────────────────

  attr :gallery_zoom_open, :boolean, default: false
  attr :gallery_zoom_index, :integer, default: 0
  attr :gallery_zoom_images, :list, default: []

  def gallery_zoom(assigns) do
    ~H"""
    <div
      :if={@gallery_zoom_open}
      id="gallery-zoom"
      class="sf-gallery-zoom"
      phx-window-keydown="close_gallery_zoom"
      phx-key="Escape"
    >
      <button class="sf-gallery-zoom-close" phx-click="close_gallery_zoom" aria-label="Close">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class="sf-icon"
        >
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>

      <div class="sf-gallery-zoom-body">
        <%= if @gallery_zoom_images != [] do %>
          <button
            :if={@gallery_zoom_index > 0}
            class="sf-gallery-zoom-prev"
            phx-click="gallery_prev"
            aria-label="Previous"
          >
            ‹
          </button>

          <img
            src={Enum.at(@gallery_zoom_images, @gallery_zoom_index)}
            class="sf-gallery-zoom-image"
            alt={"Image #{@gallery_zoom_index + 1}"}
          />

          <button
            :if={@gallery_zoom_index < length(@gallery_zoom_images) - 1}
            class="sf-gallery-zoom-next"
            phx-click="gallery_next"
            aria-label="Next"
          >
            ›
          </button>
        <% end %>
      </div>

      <div :if={length(@gallery_zoom_images) > 1} class="sf-gallery-zoom-counter">
        {@gallery_zoom_index + 1} / {length(@gallery_zoom_images)}
      </div>
    </div>
    """
  end

  # ── Related Products ─────────────────────────────────────────────────────

  attr :title, :string, default: "YOU MAY ALSO LIKE"
  attr :products, :list, default: []
  attr :style, :map, default: %{}

  def related_products(assigns) do
    assigns =
      assigns
      |> assign(:inline_style, StyleValidator.to_inline_style(assigns.style))
      |> assign(:title_style, StyleValidator.title_style(assigns.style))

    ~H"""
    <section
      :if={@products != []}
      class="sf-related-products"
      id="related-products"
      style={@inline_style}
    >
      <h2 class="sf-section-title" style={@title_style}>{@title}</h2>
      <div class="sf-product-scroll">
        <div class="sf-product-scroll-track">
          <.product_card :for={product <- @products} product={product} />
        </div>
      </div>
    </section>
    """
  end

  # ── Filter Drawer ──────────────────────────────────────────────────────────

  attr :filters_open, :boolean, default: false
  attr :active_filters, :map, default: %{}

  def filter_drawer(assigns) do
    ~H"""
    <div
      :if={@filters_open}
      id="filter-drawer"
      class="sf-filter-drawer"
      phx-window-keydown="close_filters"
      phx-key="Escape"
    >
      <div class="sf-filter-backdrop" phx-click="close_filters"></div>
      <div class="sf-filter-panel">
        <div class="sf-filter-header">
          <span class="sf-filter-title">FILTERS</span>
          <button class="sf-filter-close" phx-click="close_filters" aria-label="Close filters">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="sf-icon"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <div class="sf-filter-body">
          <p class="sf-filter-empty">Filter configuration is agent-managed.</p>
        </div>

        <div class="sf-filter-footer">
          <button class="sf-filter-clear" phx-click="clear_filters">CLEAR ALL</button>
        </div>
      </div>
    </div>
    """
  end

  # ── Search Overlay ─────────────────────────────────────────────────────────

  attr :search_open, :boolean, default: false
  attr :search_query, :string, default: ""
  attr :search_results, :list, default: []

  def search_overlay(assigns) do
    ~H"""
    <div
      :if={@search_open}
      id="search-overlay"
      class="sf-search-overlay"
      phx-window-keydown="close_search"
      phx-key="Escape"
    >
      <div class="sf-search-container">
        <div class="sf-search-header">
          <form phx-change="search" phx-submit="search" id="search-form">
            <input
              type="text"
              id="search-input"
              name="query"
              class="sf-search-input"
              placeholder="SEARCH"
              value={@search_query}
              phx-debounce="300"
              autofocus
            />
          </form>
          <button class="sf-search-close" phx-click="close_search" aria-label="Close search">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="sf-icon"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <div :if={@search_results != []} class="sf-search-results" id="search-results">
          <div class="sf-search-results-grid">
            <a
              :for={result <- @search_results}
              href={"/store/products/#{result["slug"]}"}
              class="sf-search-result"
              id={"search-result-#{result["id"]}"}
            >
              <div :if={result["image_url"]} class="sf-search-result-image">
                <img src={result["image_url"]} alt={result["name"]} loading="lazy" />
              </div>
              <div class="sf-search-result-info">
                <span class="sf-search-result-name">{result["name"]}</span>
                <span :if={result["price"]} class="sf-search-result-price">
                  {result["price"]}
                </span>
              </div>
            </a>
          </div>
        </div>

        <div :if={@search_results == [] && @search_query != ""} class="sf-search-empty">
          <p>No results found for "{@search_query}"</p>
        </div>
      </div>
    </div>
    """
  end

  # ── Icon helpers ──────────────────────────────────────────────────────────

  defp search_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      class="sf-icon"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z"
      />
    </svg>
    """
  end

  defp bag_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      class="sf-icon"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M15.75 10.5V6a3.75 3.75 0 10-7.5 0v4.5m11.356-1.993l1.263 12c.07.665-.45 1.243-1.119 1.243H4.25a1.125 1.125 0 01-1.12-1.243l1.264-12A1.125 1.125 0 015.513 7.5h12.974c.576 0 1.059.435 1.119 1.007zM8.625 10.5a.375.375 0 11-.75 0 .375.375 0 01.75 0zm7.5 0a.375.375 0 11-.75 0 .375.375 0 01.75 0z"
      />
    </svg>
    """
  end
end
