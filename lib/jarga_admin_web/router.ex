defmodule JargaAdminWeb.Router do
  use JargaAdminWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {JargaAdminWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # ── Storefront routes (demo.jargacommerce.com) ──────────────────────────
  # In dev: /store/* path prefix
  # In prod: hostname-based routing via ChannelResolver plug
  pipeline :storefront_channel do
    plug JargaAdminWeb.Plugs.ChannelResolver, strategy: :single
  end

  scope "/store", JargaAdminWeb do
    pipe_through [:browser, :storefront_channel]

    # Sitemap must be before the catch-all LiveView route
    get "/sitemap.xml", SitemapController, :sitemap

    live_session :storefront,
      root_layout: {JargaAdminWeb.Layouts, :root},
      session: {__MODULE__, :storefront_session, []} do
      live "/", StorefrontLive, :index
      live "/*slug", StorefrontLive, :show
    end
  end

  # ── SEO routes ────────────────────────────────────────────────────────
  scope "/", JargaAdminWeb do
    pipe_through :browser

    get "/robots.txt", SitemapController, :robots
  end

  # ── Admin routes ────────────────────────────────────────────────────────
  scope "/", JargaAdminWeb do
    pipe_through :browser

    get "/", PageController, :home

    live "/login", LoginLive, :index
    live "/chat", ChatLive, :index

    # ── Tab deep links ────────────────────────────────────────────────────
    live "/orders", ChatLive, :orders
    live "/orders/:id", ChatLive, :order_detail
    live "/products", ChatLive, :products
    live "/products/:id", ChatLive, :product_detail
    live "/customers", ChatLive, :customers
    live "/customers/:id", ChatLive, :customer_detail
    live "/promotions", ChatLive, :promotions
    live "/inventory", ChatLive, :inventory
    live "/analytics", ChatLive, :analytics
    live "/shipping", ChatLive, :shipping
    live "/draft-orders", ChatLive, :draft_orders
    live "/flows", ChatLive, :flows
    live "/audit", ChatLive, :audit
    live "/events", ChatLive, :events
    live "/collections", ChatLive, :collections
    live "/categories", ChatLive, :categories
    live "/metaobjects", ChatLive, :metaobjects
    live "/files", ChatLive, :files
    live "/tax", ChatLive, :tax
    live "/channels", ChatLive, :channels
    live "/webhooks", ChatLive, :webhooks
    live "/subscriptions", ChatLive, :subscriptions
  end

  @doc false
  def storefront_session(conn) do
    default = JargaAdminWeb.Plugs.ChannelResolver.default_channel()
    %{"channel_handle" => conn.assigns[:channel_handle] || default}
  end
end
