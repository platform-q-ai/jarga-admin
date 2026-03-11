defmodule JargaAdminWeb.Plugs.ChannelResolver do
  @moduledoc """
  Resolves the current sales channel from the request context.

  Sets `conn.assigns.channel_handle` to a sanitized channel handle string.

  ## Strategies

  - `:single` (default) — uses a single configured channel for all requests
  - `:hostname` — maps the request hostname to a channel via config
  - `:path_prefix` — uses the first path segment as the channel handle

  ## Configuration

      config :jarga_admin,
        channel_strategy: :hostname,
        channel_hostnames: %{
          "shop.example.com" => "online-store",
          "wholesale.example.com" => "b2b-portal"
        },
        default_channel: "online-store"
  """

  import Plug.Conn

  @behaviour Plug

  @handle_re ~r/[^a-zA-Z0-9\-]/
  @max_handle_length 64

  @doc "Returns the configured default channel handle."
  def default_channel do
    Application.get_env(:jarga_admin, :default_channel, "online-store")
  end

  @impl true
  def init(opts) do
    # Resolve config once at compile/boot time, not per request
    strategy =
      Keyword.get(opts, :strategy) ||
        Application.get_env(:jarga_admin, :channel_strategy, :single)

    default = Application.get_env(:jarga_admin, :default_channel, "online-store")
    hostnames = Application.get_env(:jarga_admin, :channel_hostnames, %{})

    %{strategy: strategy, default: default, hostnames: hostnames}
  end

  @impl true
  def call(conn, %{strategy: strategy} = config) do
    handle = resolve_channel(conn, strategy, config)
    sanitized = sanitize_handle(handle, config.default)
    assign(conn, :channel_handle, sanitized)
  end

  defp resolve_channel(_conn, :single, config), do: config.default

  defp resolve_channel(conn, :hostname, config) do
    Map.get(config.hostnames, conn.host, config.default)
  end

  defp resolve_channel(conn, :path_prefix, config) do
    # Note: when running inside a /store scope, conn.path_info includes
    # the scope prefix. The first segment will be "store", not the channel.
    # This strategy works best when mounted at root or with explicit
    # channel path segments like /store/b2b-portal/...
    case conn.path_info do
      [segment | _] when segment != "" -> segment
      _ -> config.default
    end
  end

  defp resolve_channel(_conn, _, config), do: config.default

  # Strip non-alphanumeric/hyphen chars, enforce max length, fall back to default
  defp sanitize_handle(handle, default) when is_binary(handle) do
    sanitized =
      handle
      |> String.slice(0, @max_handle_length)
      |> then(&Regex.replace(@handle_re, &1, ""))

    if sanitized == "", do: default, else: sanitized
  end

  defp sanitize_handle(_, default), do: default
end
