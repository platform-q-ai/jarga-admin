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

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    strategy =
      Keyword.get(opts, :strategy) ||
        Application.get_env(:jarga_admin, :channel_strategy, :single)

    handle = resolve_channel(conn, strategy)
    sanitized = sanitize_handle(handle)
    assign(conn, :channel_handle, sanitized)
  end

  defp resolve_channel(_conn, :single) do
    Application.get_env(:jarga_admin, :default_channel, "online-store")
  end

  defp resolve_channel(conn, :hostname) do
    hostnames = Application.get_env(:jarga_admin, :channel_hostnames, %{})
    default = Application.get_env(:jarga_admin, :default_channel, "online-store")
    Map.get(hostnames, conn.host, default)
  end

  defp resolve_channel(conn, :path_prefix) do
    default = Application.get_env(:jarga_admin, :default_channel, "online-store")

    case conn.path_info do
      [segment | _] when segment != "" -> segment
      _ -> default
    end
  end

  defp resolve_channel(_conn, _), do: "online-store"

  # Strip anything that isn't alphanumeric or hyphen to prevent injection
  defp sanitize_handle(handle) when is_binary(handle) do
    sanitized = Regex.replace(@handle_re, handle, "")
    if sanitized == "", do: "online-store", else: sanitized
  end

  defp sanitize_handle(_), do: "online-store"
end
