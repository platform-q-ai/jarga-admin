defmodule JargaAdminWeb.StorefrontLive do
  @moduledoc """
  Public-facing storefront LiveView.

  Loads page content from the Frontend API (`GET /v1/frontend/pages/{slug}`)
  and renders it using StorefrontComponents. This serves the demo store at
  `demo.jargacommerce.com`.

  The storefront uses the same UI spec → renderer → HEEx pipeline as the
  admin panel, but with storefront-specific component types optimised for
  customer-facing editorial ecommerce (Zara Home aesthetic).
  """
  use JargaAdminWeb, :live_view

  alias JargaAdmin.Api
  alias JargaAdmin.StorefrontRenderer
  alias JargaAdmin.StorefrontTheme
  alias JargaAdminWeb.StorefrontComponents

  @footer_columns [
    %{
      "title" => "Shop",
      "links" => [
        %{"label" => "Bedroom", "href" => "/store/bedroom"},
        %{"label" => "Kitchen & Dining", "href" => "/store/kitchen"},
        %{"label" => "Bathroom", "href" => "/store/bathroom"},
        %{"label" => "Home Decor", "href" => "/store/decor"},
        %{"label" => "Fragrances", "href" => "/store/fragrances"}
      ]
    },
    %{
      "title" => "Help",
      "links" => [
        %{"label" => "Delivery & Returns", "href" => "/store/delivery"},
        %{"label" => "Contact Us", "href" => "/store/contact"},
        %{"label" => "FAQ", "href" => "/store/faq"}
      ]
    },
    %{
      "title" => "Company",
      "links" => [
        %{"label" => "About", "href" => "/store/about"},
        %{"label" => "Careers", "href" => "/store/careers"},
        %{"label" => "Terms", "href" => "/store/terms"},
        %{"label" => "Privacy", "href" => "/store/privacy"}
      ]
    }
  ]

  @impl true
  def mount(params, session, socket) do
    slug = resolve_slug(params)
    channel = session["channel_handle"] || JargaAdminWeb.Plugs.ChannelResolver.default_channel()

    socket =
      socket
      |> assign(:page_title, "Loading…")
      |> assign(:slug, slug)
      |> assign(:channel_handle, channel)
      |> assign(:components, [])
      |> assign(:nav_links, [])
      |> assign(:error, nil)
      |> assign(:cart_open, false)
      |> assign(:cart_items, [])
      |> assign(:cart_count, 0)
      |> assign(:mobile_menu_open, false)
      |> assign(:search_open, false)
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:footer_columns, @footer_columns)
      |> assign(:footer_copyright, "© #{Date.utc_today().year} Jarga Commerce — Demo Store")
      |> assign(:theme_css_vars, "")
      |> assign(:theme_google_fonts_url, nil)
      |> assign(:store_name, "JARGA")
      |> load_page_data(slug)

    {:ok, socket, layout: {JargaAdminWeb.Layouts, :storefront}}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    slug = resolve_slug(params)

    socket =
      if slug != socket.assigns.slug do
        socket
        |> assign(:slug, slug)
        |> load_page_data(slug)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_cart", _params, socket) do
    {:noreply, assign(socket, :cart_open, !socket.assigns.cart_open)}
  end

  @impl true
  def handle_event("toggle_mobile_menu", _params, socket) do
    {:noreply, assign(socket, :mobile_menu_open, !socket.assigns.mobile_menu_open)}
  end

  @impl true
  def handle_event("toggle_search", _params, socket) do
    {:noreply, assign(socket, :search_open, !socket.assigns.search_open)}
  end

  @impl true
  def handle_event("close_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:search_open, false)
     |> assign(:search_query, "")
     |> assign(:search_results, [])}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) when byte_size(query) < 2 do
    {:noreply, assign(socket, search_query: query, search_results: [])}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    results =
      case Api.list_products(%{"search" => query, "limit" => "12"}) do
        {:ok, products} when is_list(products) ->
          Enum.map(products, &normalize_search_result/1)

        _ ->
          []
      end

    {:noreply, assign(socket, search_query: query, search_results: results)}
  end

  @impl true
  def handle_event("add_to_cart", %{"id" => _product_id}, socket) do
    # Cart integration — placeholder for basket API wiring
    {:noreply, socket}
  end

  @impl true
  def handle_event("newsletter_subscribe", %{"email" => _email}, socket) do
    # Newsletter — placeholder for future implementation
    {:noreply, put_flash(socket, :info, "Thank you for subscribing!")}
  end

  # ── Render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <link
      :if={@theme_google_fonts_url}
      rel="stylesheet"
      href={@theme_google_fonts_url}
    />
    <div class="sf-page" id="storefront-page" style={@theme_css_vars}>
      <StorefrontComponents.search_overlay
        search_open={@search_open}
        search_query={@search_query}
        search_results={@search_results}
      />
      <StorefrontComponents.nav_bar
        logo={@store_name}
        links={@nav_links}
        cart_count={@cart_count}
      />

      <main class="sf-main">
        <%= if @error do %>
          <div class="sf-error" id="sf-error">
            <h1 class="sf-error-title">Page not found</h1>
            <p class="sf-error-message">
              The page you're looking for doesn't exist or has been moved.
            </p>
            <a href="/" class="sf-btn-primary">BACK TO HOME</a>
          </div>
        <% else %>
          <%= for comp <- @components do %>
            <.render_component component={comp} />
          <% end %>
        <% end %>
      </main>

      <StorefrontComponents.storefront_footer
        columns={@footer_columns}
        copyright={@footer_copyright}
      />

      <StorefrontComponents.cart_drawer
        open={@cart_open}
        items={@cart_items}
      />
    </div>
    """
  end

  # ── Component dispatch ────────────────────────────────────────────────────

  attr :component, :map, required: true

  defp render_component(%{component: %{type: :editorial_hero, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.editorial_hero
      image_url={@a.image_url}
      title={@a.title}
      subtitle={@a.subtitle}
      cta={@a.cta}
    />
    """
  end

  defp render_component(%{component: %{type: :editorial_full, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.editorial_full
      image_url={@a.image_url}
      label={@a.label}
      href={@a.href}
    />
    """
  end

  defp render_component(%{component: %{type: :editorial_split, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.editorial_split left={@a.left} right={@a.right} />
    """
  end

  defp render_component(%{component: %{type: :announcement_bar, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.announcement_bar message={@a.message} href={@a.href} />
    """
  end

  defp render_component(%{component: %{type: :product_scroll, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.product_scroll title={@a.title} products={@a.products} />
    """
  end

  defp render_component(%{component: %{type: :product_grid, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.product_grid
      title={@a.title}
      columns={@a.columns}
      products={@a.products}
    />
    """
  end

  defp render_component(%{component: %{type: :product_detail, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.product_detail
      id={@a.id}
      name={@a.name}
      price={@a.price}
      images={@a.images}
      description={@a.description}
      colours={@a.colours}
      sizes={@a.sizes}
      accordion={@a.accordion}
    />
    """
  end

  defp render_component(%{component: %{type: :category_nav, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.category_nav links={@a.links} />
    """
  end

  defp render_component(%{component: %{type: :text_block, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.text_block title={@a.title} content={@a.content} />
    """
  end

  defp render_component(%{component: %{type: :nav_bar}} = assigns) do
    # Nav bar is rendered at the top of the page already
    ~H"""
    """
  end

  defp render_component(%{component: %{type: :footer}} = assigns) do
    # Footer is rendered at the bottom of the page already
    ~H"""
    """
  end

  defp render_component(%{component: %{type: :unknown}} = assigns) do
    ~H"""
    """
  end

  # ── Data loading ──────────────────────────────────────────────────────────

  defp normalize_search_result(product) when is_map(product) do
    images = product["images"] || []
    first_image = List.first(images)

    %{
      "id" => product["id"],
      "name" => product["name"] || "Product",
      "slug" => product["slug"],
      "price" => format_price(product["price"]),
      "image_url" => if(first_image, do: first_image["url"], else: nil)
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

  defp format_price(_), do: nil

  defp load_page_data(socket, slug) do
    channel = socket.assigns[:channel_handle]

    # Parallel fetch: page content + navigation + theme are independent
    # TODO(multi-storefront): pass channel to page/nav API calls
    # when the backend supports per-channel content scoping
    page_task = Task.async(fn -> Api.get_storefront_page(slug) end)
    nav_task = Task.async(fn -> Api.get_storefront_navigation() end)
    theme_task = Task.async(fn -> StorefrontTheme.load(channel) end)

    page_result = Task.await(page_task, 10_000)
    nav_result = Task.await(nav_task, 10_000)
    theme_result = Task.await(theme_task, 10_000)

    nav_links =
      case nav_result do
        {:ok, %{"items" => items}} when is_list(items) -> items
        {:ok, %{"links" => links}} when is_list(links) -> links
        _ -> []
      end

    # Apply pre-computed theme values (css_vars, google_fonts_url, store_name)
    socket =
      socket
      |> assign(:theme_css_vars, theme_result.css_vars)
      |> assign(:theme_google_fonts_url, theme_result.google_fonts_url)
      |> assign(:store_name, theme_result.store_name)

    case page_result do
      {:ok, page} when is_map(page) ->
        content_json = parse_content_json(page["content_json"])
        components = StorefrontRenderer.render_spec(content_json)
        title = page["title"] || "Demo Store"

        socket
        |> assign(:page_title, title)
        |> assign(:components, components)
        |> assign(:nav_links, nav_links)
        |> assign(:error, nil)

      {:error, _reason} ->
        socket
        |> assign(:page_title, "Page not found")
        |> assign(:error, :not_found)
        |> assign(:nav_links, nav_links)

      _ ->
        socket
        |> assign(:page_title, "Page not found")
        |> assign(:error, :not_found)
        |> assign(:nav_links, nav_links)
    end
  end

  # content_json may be a JSON string (from the backend) or an already-decoded map (from tests)
  defp parse_content_json(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp parse_content_json(map) when is_map(map), do: map
  defp parse_content_json(_), do: %{}

  defp resolve_slug(%{"slug" => slug_parts}) when is_list(slug_parts) do
    case slug_parts |> Enum.map(&sanitize_slug_segment/1) |> Enum.join("/") do
      "" -> "home"
      slug -> slug
    end
  end

  defp resolve_slug(%{"slug" => slug}) when is_binary(slug) and slug != "" do
    sanitize_slug_segment(slug)
  end

  defp resolve_slug(_), do: "home"

  # Only allow URL-safe characters in slug segments (alphanumeric, hyphens, underscores)
  defp sanitize_slug_segment(segment) when is_binary(segment) do
    segment
    |> String.replace(~r/[^a-zA-Z0-9\-_]/, "")
    |> case do
      "" -> "home"
      clean -> clean
    end
  end

  defp sanitize_slug_segment(_), do: "home"
end
