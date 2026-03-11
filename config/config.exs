# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :jarga_admin,
  generators: [timestamp_type: :utc_datetime],
  # Multi-storefront channel resolution strategy.
  # :single (default) — all requests use default_channel
  # :hostname — map request hostname to channel via channel_hostnames
  # :path_prefix — use first path segment as channel handle
  channel_strategy: :single,
  default_channel: "online-store",
  channel_hostnames: %{}

# Configures the endpoint
config :jarga_admin, JargaAdminWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: JargaAdminWeb.ErrorHTML, json: JargaAdminWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: JargaAdmin.PubSub,
  live_view: [signing_salt: "mRhOihCF"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  jarga_admin: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  jarga_admin: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
