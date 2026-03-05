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

  scope "/", JargaAdminWeb do
    pipe_through :browser

    get "/", PageController, :home

    live "/chat", ChatLive, :index
  end
end
