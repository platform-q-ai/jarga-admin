defmodule JargaAdminWeb.StorefrontComponents do
  @moduledoc """
  Customer-facing storefront HEEx components — Zara Home inspired.

  Luxury-minimal editorial design: Helvetica Neue, thin typography,
  pure white backgrounds, black accents, zero border-radius.
  """
  use Phoenix.Component

  # ── Announcement Bar ──────────────────────────────────────────────────────

  attr :message, :string, required: true
  attr :href, :string, default: nil

  def announcement_bar(assigns) do
    ~H"""
    <div class="sf-announcement" id="sf-announcement">
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
    <nav class="sf-nav" id="sf-nav" phx-hook="StorefrontNav" phx-update="ignore">
      <div class="sf-nav-inner">
        <button class="sf-nav-hamburger" phx-click="toggle_mobile_menu" aria-label="Menu">
          <span class="sf-hamburger-line"></span>
          <span class="sf-hamburger-line"></span>
        </button>

        <a href="/" class="sf-nav-logo">{@logo}</a>

        <div class="sf-nav-links">
          <a :for={link <- @links} href={safe_href(link["href"])} class="sf-nav-link">
            {link["label"]}
          </a>
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

  def editorial_hero(assigns) do
    ~H"""
    <section class="sf-hero" id="sf-hero">
      <div class="sf-hero-image-wrap">
        <img src={@image_url} alt={@title} class="sf-hero-image" loading="eager" />
      </div>
      <div class="sf-hero-overlay">
        <h1 class="sf-hero-title">{@title}</h1>
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

  def editorial_full(assigns) do
    ~H"""
    <section class="sf-editorial-full">
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

  def editorial_split(assigns) do
    ~H"""
    <section class="sf-editorial-split">
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

  def product_scroll(assigns) do
    ~H"""
    <section class="sf-product-scroll">
      <h2 :if={@title != ""} class="sf-section-title">{@title}</h2>
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

  def product_grid(assigns) do
    ~H"""
    <section class="sf-product-grid">
      <h2 :if={@title} class="sf-section-title">{@title}</h2>
      <div class={["sf-grid", safe_grid_class(@columns)]}>
        <.product_card :for={product <- @products} product={product} />
      </div>
    </section>
    """
  end

  # ── Product Card ──────────────────────────────────────────────────────────

  attr :product, :map, required: true

  def product_card(assigns) do
    ~H"""
    <a href={safe_href(@product.href)} class={["sf-product-card", @product.featured && "sf-featured"]}>
      <div
        class="sf-product-card-image-wrap"
        phx-hook="ImageHoverSwap"
        id={"product-#{@product.id}"}
        phx-update="ignore"
      >
        <img
          src={@product.image_url}
          alt={@product.name}
          class="sf-product-card-image"
          loading="lazy"
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
        <span class="sf-product-card-price">{@product.price}</span>
      </div>
    </a>
    """
  end

  # ── Product Detail ────────────────────────────────────────────────────────

  attr :id, :string, default: nil
  attr :name, :string, required: true
  attr :price, :string, required: true
  attr :images, :list, default: []
  attr :description, :string, default: nil
  attr :colours, :list, default: []
  attr :sizes, :list, default: []
  attr :accordion, :list, default: []

  def product_detail(assigns) do
    ~H"""
    <section class="sf-product-detail" id="sf-product-detail">
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
        <h1 class="sf-pdp-name">{@name}</h1>
        <p class="sf-pdp-price">{@price}</p>

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

  def category_nav(assigns) do
    ~H"""
    <nav class="sf-category-nav">
      <a :for={link <- @links} href={safe_href(link["href"])} class="sf-category-nav-link">
        {link["label"]}
      </a>
    </nav>
    """
  end

  # ── Text Block ────────────────────────────────────────────────────────────

  attr :title, :string, default: nil
  attr :content, :string, default: ""

  def text_block(assigns) do
    ~H"""
    <section class="sf-text-block">
      <h2 :if={@title} class="sf-text-block-title">{@title}</h2>
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

  @valid_grid_columns %{2 => "sf-grid-2", 3 => "sf-grid-3", 4 => "sf-grid-4"}

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
