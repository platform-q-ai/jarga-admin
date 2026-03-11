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
  # In prod: hostname-based routing via StorefrontPlug
  scope "/store", JargaAdminWeb do
    pipe_through :browser

    live_session :storefront, root_layout: {JargaAdminWeb.Layouts, :root} do
      live "/", StorefrontLive, :index
      live "/*slug", StorefrontLive, :show
    end
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
end
