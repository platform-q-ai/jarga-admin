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
  alias JargaAdmin.StorefrontAnalytics
  alias JargaAdmin.StorefrontRenderer
  alias JargaAdmin.StorefrontTheme
  alias JargaAdminWeb.StorefrontComponents

  @default_footer_columns [
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
      |> assign(:cart_subtotal, "£0.00")
      |> assign(:mobile_menu_open, false)
      |> assign(:search_open, false)
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:search_ref, nil)
      |> assign(:filters_open, false)
      |> assign(:active_filters, %{})
      |> assign(:filter_config, [])
      |> assign(:layout_variant, "storefront")
      |> assign(:sidebar, nil)
      |> assign(:gallery_zoom_open, false)
      |> assign(:gallery_zoom_index, 0)
      |> assign(:gallery_zoom_images, [])
      |> assign(:meta_description, "")
      |> assign(:og_title, "")
      |> assign(:og_description, "")
      |> assign(:og_image, nil)
      |> assign(:canonical_url, nil)
      |> assign(:preview_mode, false)
      |> assign(:footer_columns, @default_footer_columns)
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
    preview = params["preview"] == "true"

    slug_changed = slug != socket.assigns.slug
    preview_changed = preview != socket.assigns.preview_mode

    socket =
      socket
      |> assign(:preview_mode, preview)
      |> then(fn s ->
        if slug_changed or preview_changed do
          s = s |> assign(:slug, slug) |> load_page_data(slug)

          if slug_changed do
            StorefrontAnalytics.track(:page_view, %{
              slug: slug,
              page_title: s.assigns[:page_title],
              channel: s.assigns[:channel_handle]
            })
          end

          s
        else
          s
        end
      end)

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
  def handle_event("toggle_filters", _params, socket) do
    {:noreply, assign(socket, :filters_open, !socket.assigns.filters_open)}
  end

  @impl true
  def handle_event("close_filters", _params, socket) do
    {:noreply, assign(socket, :filters_open, false)}
  end

  @impl true
  def handle_event("apply_filter", %{"key" => key, "value" => value}, socket) do
    StorefrontAnalytics.track(:filter_applied, %{
      filter_key: key,
      filter_value: value,
      page_slug: socket.assigns.slug
    })

    active = socket.assigns.active_filters
    current = Map.get(active, key, [])

    updated =
      if value in current do
        List.delete(current, value)
      else
        [value | current]
      end

    new_filters =
      if updated == [] do
        Map.delete(active, key)
      else
        Map.put(active, key, updated)
      end

    {:noreply, assign(socket, :active_filters, new_filters)}
  end

  def handle_event("remove_filter", %{"key" => key}, socket) do
    {:noreply, assign(socket, :active_filters, Map.delete(socket.assigns.active_filters, key))}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:filters_open, false)
     |> assign(:active_filters, %{})}
  end

  @impl true
  def handle_event("open_gallery_zoom", %{"index" => index}, socket) do
    idx =
      case Integer.parse(to_string(index)) do
        {n, _} when n >= 0 -> n
        _ -> 0
      end

    {:noreply,
     socket
     |> assign(:gallery_zoom_open, true)
     |> assign(:gallery_zoom_index, idx)}
  end

  @impl true
  def handle_event("close_gallery_zoom", _params, socket) do
    {:noreply, assign(socket, :gallery_zoom_open, false)}
  end

  @impl true
  def handle_event("gallery_prev", _params, socket) do
    idx = max(0, socket.assigns.gallery_zoom_index - 1)
    {:noreply, assign(socket, :gallery_zoom_index, idx)}
  end

  @impl true
  def handle_event("gallery_next", _params, socket) do
    images = socket.assigns.gallery_zoom_images
    max_idx = max(0, length(images) - 1)
    idx = min(max_idx, socket.assigns.gallery_zoom_index + 1)
    {:noreply, assign(socket, :gallery_zoom_index, idx)}
  end

  @max_search_query_length 200

  @impl true
  def handle_event("search", %{"query" => query}, socket) when byte_size(query) < 2 do
    {:noreply,
     assign(socket,
       search_query: String.slice(query, 0, @max_search_query_length),
       search_results: []
     )}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    query = String.slice(query, 0, @max_search_query_length)

    # Cancel any previous in-flight search task
    cancel_search_task(socket)

    task = Task.async(fn -> Api.list_products(%{"search" => query, "limit" => "12"}) end)

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_ref, task.ref)}
  end

  @impl true
  def handle_info({ref, result}, %{assigns: %{search_ref: ref}} = socket) do
    Process.demonitor(ref, [:flush])

    results =
      case result do
        {:ok, products} when is_list(products) ->
          Enum.map(products, &normalize_search_result/1)

        _ ->
          []
      end

    StorefrontAnalytics.track(:search, %{
      query: socket.assigns.search_query,
      result_count: length(results)
    })

    {:noreply, assign(socket, search_results: results, search_ref: nil)}
  end

  # Handle task DOWN messages
  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, socket}
  end

  defp cancel_search_task(socket) do
    if ref = socket.assigns[:search_ref] do
      Process.demonitor(ref, [:flush])
    end
  end

  @impl true
  def handle_event("add_to_cart", params, socket) do
    # TODO: look up product by ID from server; don't trust client-sent price/name
    item = %{
      "id" => params["id"],
      "name" => params["name"] || "Product",
      "price" => params["price"] || "",
      "image_url" => sanitize_cart_image_url(params["image_url"]),
      "quantity" => 1
    }

    updated = add_or_increment(socket.assigns.cart_items, item)

    StorefrontAnalytics.track(:add_to_cart, %{
      product_id: params["id"],
      quantity: 1,
      price: params["price"]
    })

    {:noreply,
     socket
     |> update_cart(updated)
     |> assign(:cart_open, true)}
  end

  @impl true
  def handle_event("remove_from_cart", %{"id" => id}, socket) do
    StorefrontAnalytics.track(:remove_from_cart, %{product_id: id})
    updated = Enum.reject(socket.assigns.cart_items, &(&1["id"] == id))
    {:noreply, update_cart(socket, updated)}
  end

  @impl true
  def handle_event("update_cart_quantity", %{"id" => id, "delta" => delta}, socket) do
    delta_int =
      case Integer.parse(to_string(delta)) do
        {n, _} -> n
        _ -> 0
      end

    updated =
      socket.assigns.cart_items
      |> Enum.map(fn item ->
        if item["id"] == id do
          new_qty = max(1, (item["quantity"] || 1) + delta_int)
          Map.put(item, "quantity", new_qty)
        else
          item
        end
      end)

    {:noreply, update_cart(socket, updated)}
  end

  defp update_cart(socket, items) do
    total_qty = Enum.reduce(items, 0, fn item, acc -> acc + (item["quantity"] || 1) end)
    subtotal = compute_subtotal(items)

    socket
    |> assign(:cart_items, items)
    |> assign(:cart_count, total_qty)
    |> assign(:cart_subtotal, subtotal)
  end

  defp compute_subtotal(items) do
    # Use integer cents to avoid floating point rounding errors
    total_cents =
      Enum.reduce(items, 0, fn item, acc ->
        price_str = item["price"] || "0"
        qty = item["quantity"] || 1

        cents =
          case Regex.run(~r/[\d.]+/, price_str) do
            [num] ->
              case Float.parse(num) do
                {val, _} -> round(val * 100)
                _ -> 0
              end

            _ ->
              0
          end

        acc + cents * qty
      end)

    # Determine currency symbol from first item
    symbol =
      case items do
        [first | _] ->
          case Regex.run(~r/^([£$€])/u, first["price"] || "") do
            [_, s] -> s
            _ -> "£"
          end

        _ ->
          "£"
      end

    pounds = div(total_cents, 100)
    pence = rem(total_cents, 100)
    "#{symbol}#{pounds}.#{String.pad_leading(to_string(pence), 2, "0")}"
  end

  defp sanitize_cart_image_url(nil), do: nil

  defp sanitize_cart_image_url(url) when is_binary(url) do
    trimmed = String.trim(url)

    cond do
      String.starts_with?(trimmed, "/") -> trimmed
      String.starts_with?(trimmed, "https://") -> trimmed
      true -> nil
    end
  end

  defp sanitize_cart_image_url(_), do: nil

  defp add_or_increment(items, new_item) do
    case Enum.find_index(items, &(&1["id"] == new_item["id"])) do
      nil ->
        items ++ [new_item]

      idx ->
        List.update_at(items, idx, fn existing ->
          Map.update(existing, "quantity", 1, &(&1 + 1))
        end)
    end
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
    <meta :if={@preview_mode} name="robots" content="noindex, nofollow" />
    <meta :if={@meta_description != ""} name="description" content={@meta_description} />
    <meta :if={@og_title != ""} property="og:title" content={@og_title} />
    <meta :if={@og_description != ""} property="og:description" content={@og_description} />
    <meta :if={@og_image} property="og:image" content={@og_image} />
    <link :if={@canonical_url} rel="canonical" href={@canonical_url} />
    <link
      :if={@theme_google_fonts_url}
      rel="stylesheet"
      href={@theme_google_fonts_url}
    />
    <div class="sf-page" id="storefront-page" style={@theme_css_vars}>
      <div :if={@preview_mode} id="preview-banner" class="sf-preview-banner">
        <span class="sf-preview-banner-text">PREVIEW MODE</span>
        <span class="sf-preview-banner-label">This page is not published</span>
      </div>
      <StorefrontComponents.gallery_zoom
        gallery_zoom_open={@gallery_zoom_open}
        gallery_zoom_index={@gallery_zoom_index}
        gallery_zoom_images={@gallery_zoom_images}
      />
      <StorefrontComponents.filter_drawer
        filters_open={@filters_open}
        active_filters={@active_filters}
        filter_config={@filter_config}
      />
      <StorefrontComponents.search_overlay
        search_open={@search_open}
        search_query={@search_query}
        search_results={@search_results}
      />
      <StorefrontComponents.nav_bar
        :if={@layout_variant != "landing"}
        logo={@store_name}
        links={@nav_links}
        cart_count={@cart_count}
      />

      <main class={["sf-main", @layout_variant == "storefront-sidebar" && "sf-main-with-sidebar"]}>
        <%= if @error do %>
          <div class="sf-error" id="sf-error">
            <h1 class="sf-error-title">Page not found</h1>
            <p class="sf-error-message">
              The page you're looking for doesn't exist or has been moved.
            </p>
            <a href="/" class="sf-btn-primary">BACK TO HOME</a>
          </div>
        <% else %>
          <aside
            :if={@sidebar}
            class={[
              "sf-sidebar",
              @sidebar.position == "right" && "sf-sidebar-right",
              @sidebar.sticky && "sf-sidebar-sticky"
            ]}
            style={"width: #{JargaAdmin.StyleValidator.sanitize_css_dimension(@sidebar.width)}"}
          >
            <%= for comp <- @sidebar.components do %>
              <.render_component component={comp} />
            <% end %>
          </aside>
          <div class={["sf-content", @sidebar && "sf-content-with-sidebar"]}>
            <%= for comp <- @components do %>
              <%= if comp.assigns[:responsive_class] do %>
                <div class={comp.assigns.responsive_class}>
                  <.render_component component={comp} />
                </div>
              <% else %>
                <.render_component component={comp} />
              <% end %>
            <% end %>
          </div>
        <% end %>
      </main>

      <StorefrontComponents.storefront_footer
        :if={@layout_variant not in ["landing", "minimal"]}
        columns={@footer_columns}
        copyright={@footer_copyright}
      />

      <StorefrontComponents.cart_drawer
        open={@cart_open}
        items={@cart_items}
        subtotal={@cart_subtotal}
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
      style={@a.style}
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
      style={@a.style}
    />
    """
  end

  defp render_component(%{component: %{type: :editorial_split, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.editorial_split left={@a.left} right={@a.right} style={@a.style} />
    """
  end

  defp render_component(%{component: %{type: :announcement_bar, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.announcement_bar message={@a.message} href={@a.href} style={@a.style} />
    """
  end

  defp render_component(%{component: %{type: :product_scroll, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.product_scroll title={@a.title} products={@a.products} style={@a.style} />
    """
  end

  defp render_component(%{component: %{type: :product_grid, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.product_grid
      title={@a.title}
      columns={@a.columns}
      products={@a.products}
      style={@a.style}
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
      compare_at_price={@a.compare_at_price}
      layout={@a.layout}
      images={@a.images}
      description={@a.description}
      colours={@a.colours}
      sizes={@a.sizes}
      variants={@a.variants}
      breadcrumbs={@a.breadcrumbs}
      in_stock={@a.in_stock}
      stock_count={@a.stock_count}
      quantity_max={@a.quantity_max}
      accordion={@a.accordion}
      style={@a.style}
    />
    """
  end

  defp render_component(%{component: %{type: :category_nav, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.category_nav links={@a.links} style={@a.style} />
    """
  end

  defp render_component(%{component: %{type: :text_block, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.text_block title={@a.title} content={@a.content} style={@a.style} />
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

  defp render_component(%{component: %{type: :related_products, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.related_products title={@a.title} products={@a.products} style={@a.style} />
    """
  end

  defp render_component(%{component: %{type: :video_hero, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.video_hero
      video_url={@a.video_url}
      poster_url={@a.poster_url}
      title={@a.title}
      subtitle={@a.subtitle}
      cta={@a.cta}
      autoplay={@a.autoplay}
      loop={@a.loop}
      muted={@a.muted}
      style={@a.style}
    />
    """
  end

  defp render_component(%{component: %{type: :banner, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.banner
      message={@a.message}
      background_color={@a.background_color}
      text_color={@a.text_color}
      cta={@a.cta}
      countdown_to={@a.countdown_to}
      style={@a.style}
    />
    """
  end

  defp render_component(%{component: %{type: :spacer, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.spacer height={@a.height} style={@a.style} />
    """
  end

  defp render_component(%{component: %{type: :divider, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.divider
      thickness={@a.thickness}
      color={@a.color}
      max_width={@a.max_width}
      style={@a.style}
    />
    """
  end

  defp render_component(%{component: %{type: :image_grid, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.image_grid
      columns={@a.columns}
      images={@a.images}
      gap={@a.gap}
      style={@a.style}
    />
    """
  end

  defp render_component(%{component: %{type: :testimonials, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.testimonials
      title={@a.title}
      items={@a.items}
      style={@a.style}
    />
    """
  end

  defp render_component(%{component: %{type: :feature_list, assigns: a}} = assigns) do
    assigns = assign(assigns, :a, a)

    ~H"""
    <StorefrontComponents.feature_list
      features={@a.features}
      layout={@a.layout}
      style={@a.style}
    />
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

    # Parallel fetch: page content + navigation + theme + footer are independent
    # TODO(multi-storefront): pass channel to page/nav API calls
    # when the backend supports per-channel content scoping
    page_task = Task.async(fn -> Api.get_storefront_page(slug) end)
    nav_task = Task.async(fn -> Api.get_storefront_navigation() end)
    theme_task = Task.async(fn -> StorefrontTheme.load(channel) end)
    footer_task = Task.async(fn -> Api.get_storefront_slot("storefront_footer") end)

    page_result = Task.await(page_task, 10_000)
    nav_result = Task.await(nav_task, 10_000)
    theme_result = Task.await(theme_task, 10_000)
    footer_result = Task.await(footer_task, 10_000)

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

    # Apply footer from API slot (falls back to hardcoded defaults)
    socket = apply_footer_data(socket, footer_result)

    case page_result do
      {:ok, page} when is_map(page) ->
        content_json = parse_content_json(page["content_json"])

        components =
          StorefrontRenderer.render_spec(content_json, preview: socket.assigns.preview_mode)

        title = page["title"] || "Demo Store"
        meta_desc = page["meta_description"] || ""
        seo = if is_map(content_json), do: content_json["seo"] || %{}, else: %{}

        socket
        |> assign(:page_title, seo["title"] || title)
        |> assign(:meta_description, seo["description"] || meta_desc)
        |> assign(:og_title, seo["title"] || title)
        |> assign(:og_description, seo["description"] || meta_desc)
        |> assign(:og_image, sanitize_cart_image_url(seo["og_image"]))
        |> assign(:canonical_url, sanitize_cart_image_url(seo["canonical"]))
        |> assign(:components, components)
        |> assign(:filter_config, StorefrontRenderer.extract_filters(content_json))
        |> assign(:active_filters, %{})
        |> assign(:layout_variant, StorefrontRenderer.extract_layout(content_json))
        |> assign(:sidebar, StorefrontRenderer.extract_sidebar(content_json))
        |> assign(:gallery_zoom_images, extract_pdp_images(components))
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

  defp extract_pdp_images(components) do
    case Enum.find(components, fn c -> c.type == :product_detail end) do
      %{assigns: %{images: images}} when is_list(images) -> images
      _ -> []
    end
  end

  defp apply_footer_data(socket, {:ok, %{"payload_json" => payload}}) when is_map(payload) do
    apply_footer_payload(socket, payload)
  end

  defp apply_footer_data(socket, {:ok, %{"payload_json" => payload}}) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, map} when is_map(map) -> apply_footer_payload(socket, map)
      _ -> socket
    end
  end

  defp apply_footer_data(socket, _), do: socket

  defp apply_footer_payload(socket, payload) when is_map(payload) do
    columns = payload["columns"] || socket.assigns.footer_columns
    copyright = payload["copyright"] || socket.assigns.footer_copyright

    socket
    |> assign(:footer_columns, columns)
    |> assign(:footer_copyright, copyright)
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
