defmodule JargaAdmin.StorefrontAnalytics do
  @moduledoc """
  Tracks storefront analytics events.

  Events are logged and broadcast via PubSub for downstream consumers.
  No PII is collected — only product IDs, page slugs, and interaction types.

  ## Supported Events

  - `:page_view` — page mount/navigation
  - `:product_impression` — product card enters viewport
  - `:product_click` — product card clicked
  - `:add_to_cart` — item added to basket
  - `:remove_from_cart` — item removed from basket
  - `:search` — search query submitted
  - `:search_click` — search result clicked
  - `:filter_applied` — filter selection changed
  """

  require Logger

  @doc """
  Track an analytics event.

  ## Examples

      StorefrontAnalytics.track(:page_view, %{slug: "home", channel: "online-store"})
      StorefrontAnalytics.track(:add_to_cart, %{product_id: "prod-1", quantity: 1})
  """
  def track(event_type, data \\ %{})

  def track(event_type, nil), do: track(event_type, %{})

  def track(event_type, data) when is_atom(event_type) and is_map(data) do
    event = %{
      event: event_type,
      data: data,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Logger.info(
      "[StorefrontAnalytics] #{event_type}: #{inspect(data)} timestamp=#{event.timestamp}"
    )

    # Broadcast to PubSub for downstream consumers (GenServer batching, etc.)
    try do
      Phoenix.PubSub.broadcast(
        JargaAdmin.PubSub,
        "storefront:analytics",
        {:analytics_event, event}
      )
    rescue
      _ -> :ok
    end

    :ok
  end

  def track(_event_type, _data), do: :ok
end
