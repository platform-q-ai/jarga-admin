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
  alias JargaAdminWeb.StorefrontComponents

  @impl true
  def mount(params, _session, socket) do
    slug = resolve_slug(params)

    socket =
      socket
      |> assign(:page_title, "Loading…")
      |> assign(:slug, slug)
      |> assign(:page, nil)
      |> assign(:components, [])
      |> assign(:nav_links, [])
      |> assign(:error, nil)
      |> assign(:cart_open, false)
      |> assign(:cart_items, [])
      |> assign(:cart_count, 0)
      |> assign(:mobile_menu_open, false)
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
    # Search overlay — placeholder for future implementation
    {:noreply, socket}
  end

  @impl true
  def handle_event("add_to_cart", %{"id" => _product_id}, socket) do
    # Cart integration — placeholder for basket API wiring
    {:noreply, socket}
  end

  # ── Render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="sf-page" id="storefront-page">
      <StorefrontComponents.nav_bar
        logo="JARGA"
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
        columns={default_footer_columns()}
        copyright={"© #{Date.utc_today().year} Jarga Commerce — Demo Store"}
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

  defp load_page_data(socket, slug) do
    nav_links = load_navigation()

    case Api.get_storefront_page(slug) do
      {:ok, page} when is_map(page) ->
        content_json = page["content_json"] || %{}
        components = StorefrontRenderer.render_spec(content_json)
        title = page["title"] || "Demo Store"

        socket
        |> assign(:page, page)
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

  defp load_navigation do
    case Api.get_storefront_navigation() do
      {:ok, %{"links" => links}} when is_list(links) -> links
      _ -> []
    end
  end

  defp resolve_slug(%{"slug" => slug_parts}) when is_list(slug_parts) do
    case Enum.join(slug_parts, "/") do
      "" -> "home"
      slug -> slug
    end
  end

  defp resolve_slug(%{"slug" => slug}) when is_binary(slug) and slug != "" do
    slug
  end

  defp resolve_slug(_), do: "home"

  defp default_footer_columns do
    [
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
  end
end
