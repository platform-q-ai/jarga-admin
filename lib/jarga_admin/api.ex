defmodule JargaAdmin.Api do
  @moduledoc """
  HTTP client for the Jarga Commerce REST API.

  Configuration (env vars or application config):
  - `JARGA_API_URL` — base URL (default: http://localhost:8080)
  - `JARGA_API_KEY` — bearer token (default: "dev" for local bootstrap)

  All functions return `{:ok, data}` or `{:error, reason}`.
  The API envelope `{"data": ..., "error": ..., "meta": ...}` is unwrapped
  automatically — callers receive the inner `data` value directly.
  """

  require Logger

  @default_timeout 10_000

  # ── Configuration ─────────────────────────────────────────────────────────

  defp base_url do
    System.get_env("JARGA_API_URL") ||
      Application.get_env(:jarga_admin, :api_url, "http://localhost:8080")
  end

  defp api_key do
    System.get_env("JARGA_API_KEY") ||
      Application.get_env(:jarga_admin, :api_key, "dev")
  end

  defp timeout do
    Application.get_env(:jarga_admin, :api_timeout, @default_timeout)
  end

  # ── Core HTTP verbs ───────────────────────────────────────────────────────

  @doc "HTTP GET — returns `{:ok, data}` with envelope unwrapped"
  def get(path, opts \\ []) do
    request(:get, path, nil, opts)
  end

  @doc "HTTP POST with JSON body"
  def post(path, body, opts \\ []) do
    request(:post, path, body, opts)
  end

  @doc "HTTP PUT with JSON body"
  def put(path, body, opts \\ []) do
    request(:put, path, body, opts)
  end

  @doc "HTTP PATCH with JSON body"
  def patch(path, body, opts \\ []) do
    request(:patch, path, body, opts)
  end

  @doc "HTTP DELETE"
  def delete(path, opts \\ []) do
    request(:delete, path, nil, opts)
  end

  # ── Convenience wrappers ──────────────────────────────────────────────────

  @doc "GET /v1/agent/context — full store snapshot for agent prompts"
  def agent_context do
    get("/v1/agent/context")
  end

  @doc "GET /v1/pim/products"
  def list_products(params \\ %{}) do
    get("/v1/pim/products?" <> URI.encode_query(params))
  end

  @doc "GET /v1/pim/products/:id"
  def get_product(id) do
    get("/v1/pim/products/#{id}")
  end

  @doc "POST /v1/pim/products"
  def create_product(attrs) do
    post("/v1/pim/products", attrs)
  end

  @doc "GET /v1/oms/orders"
  def list_orders(params \\ %{}) do
    get("/v1/oms/orders?" <> URI.encode_query(params))
  end

  @doc "GET /v1/oms/orders/:id"
  def get_order(id) do
    get("/v1/oms/orders/#{id}")
  end

  @doc "GET /v1/crm/customers"
  def list_customers(params \\ %{}) do
    get("/v1/crm/customers?" <> URI.encode_query(params))
  end

  @doc "GET /v1/promotions/campaigns"
  def list_promotions(params \\ %{}) do
    get("/v1/promotions/campaigns?" <> URI.encode_query(params))
  end

  @doc "GET /v1/promotions/campaigns/:id"
  def get_promotion(id) do
    get("/v1/promotions/campaigns/#{id}")
  end

  @doc "GET /v1/promotions/campaigns/:id/coupons"
  def list_promotion_coupons(id) do
    get("/v1/promotions/campaigns/#{id}/coupons")
  end

  @doc "POST /v1/promotions/coupons/generate"
  def generate_coupons(attrs) do
    post("/v1/promotions/coupons/generate", attrs)
  end

  @doc "POST /v1/promotions/campaigns/:id/publish"
  def publish_promotion(id) do
    post("/v1/promotions/campaigns/#{id}/publish", %{})
  end

  @doc "POST /v1/promotions/campaigns"
  def create_promotion(attrs) do
    post("/v1/promotions/campaigns", attrs)
  end

  @doc "GET /v1/inventory/levels"
  def get_inventory_levels(params \\ %{}) do
    get("/v1/inventory/levels?" <> URI.encode_query(params))
  end

  @doc "GET /v1/analytics/sales"
  def get_analytics(params \\ %{}) do
    get("/v1/analytics/sales?" <> URI.encode_query(params))
  end

  @doc "GET /v1/oms/orders/:id"
  def get_customer(id) do
    get("/v1/crm/customers/#{id}")
  end

  @doc "GET /v1/shipping/zones"
  def list_shipping_zones do
    get("/v1/shipping/zones")
  end

  @doc "GET /v1/shipping/zones/:id"
  def get_shipping_zone(id) do
    get("/v1/shipping/zones/#{id}")
  end

  @doc "GET /v1/shipping/zones/:id/rates"
  def list_shipping_rates(zone_id) do
    get("/v1/shipping/zones/#{zone_id}/rates")
  end

  @doc "GET /v1/oms/draft-orders"
  def list_draft_orders(params \\ %{}) do
    get("/v1/oms/draft-orders?" <> URI.encode_query(params))
  end

  @doc "GET /v1/pim/variants/:id"
  def get_variant(id) do
    get("/v1/pim/variants/#{id}")
  end

  @doc "POST /v1/pim/products/:id/variants"
  def create_variant(product_id, attrs) do
    post("/v1/pim/products/#{product_id}/variants", attrs)
  end

  @doc "PATCH /v1/pim/variants/:id"
  def update_variant(id, attrs) do
    patch("/v1/pim/variants/#{id}", attrs)
  end

  @doc "DELETE /v1/pim/variants/:id"
  def delete_variant(id) do
    delete("/v1/pim/variants/#{id}")
  end

  @doc "PATCH /v1/pim/variants/:id/price"
  def update_variant_price(id, price) do
    patch("/v1/pim/variants/#{id}/price", %{price: price})
  end

  @doc "POST /v1/pim/products/:id/options/generate-variants"
  def generate_variants(product_id, opts \\ %{}) do
    post("/v1/pim/products/#{product_id}/options/generate-variants", opts)
  end

  @doc "PATCH /v1/pim/products/:id"
  def update_product(id, attrs) do
    patch("/v1/pim/products/#{id}", attrs)
  end

  @doc "DELETE /v1/pim/products/:id"
  def delete_product(id) do
    delete("/v1/pim/products/#{id}")
  end

  @doc "POST /v1/pim/products/:id/publish"
  def publish_product(id) do
    post("/v1/pim/products/#{id}/publish", %{})
  end

  @doc "POST /v1/pim/products/:id/archive"
  def archive_product(id) do
    post("/v1/pim/products/#{id}/archive", %{})
  end

  @doc "GET /v1/pim/collections"
  def list_collections do
    get("/v1/pim/collections")
  end

  @doc "GET /v1/pim/categories"
  def list_categories do
    get("/v1/pim/categories")
  end

  @doc "POST /v1/oms/orders/:id/fulfillments"
  def create_fulfillment(order_id, attrs) do
    post("/v1/oms/orders/#{order_id}/fulfillments", attrs)
  end

  @doc "POST /v1/oms/orders/:id/refunds"
  def create_refund(order_id, attrs) do
    post("/v1/oms/orders/#{order_id}/refunds", attrs)
  end

  @doc "POST /v1/oms/orders/:id/cancel"
  def cancel_order(order_id) do
    post("/v1/oms/orders/#{order_id}/cancel", %{})
  end

  @doc "POST /v1/oms/orders/:id/status"
  def transition_order_status(order_id, status) do
    post("/v1/oms/orders/#{order_id}/status", %{status: status})
  end

  @doc "POST /v1/oms/orders/:id/notes"
  def add_order_note(order_id, note) do
    post("/v1/oms/orders/#{order_id}/notes", %{note: note})
  end

  @doc "POST /v1/crm/customers"
  def create_customer(attrs) do
    post("/v1/crm/customers", attrs)
  end

  @doc "PATCH /v1/crm/customers/:id"
  def update_customer(id, attrs) do
    patch("/v1/crm/customers/#{id}", attrs)
  end

  @doc "POST /v1/crm/customers/:id/tags"
  def add_customer_tag(id, tag) do
    post("/v1/crm/customers/#{id}/tags", %{tag: tag})
  end

  @doc "DELETE /v1/crm/customers/:id"
  def delete_customer(id) do
    delete("/v1/crm/customers/#{id}")
  end

  @doc "PATCH /v1/promotions/campaigns/:id"
  def update_promotion(id, attrs) do
    patch("/v1/promotions/campaigns/#{id}", attrs)
  end

  @doc "POST /v1/inventory/levels/adjust"
  def adjust_inventory(attrs) do
    post("/v1/inventory/levels/adjust", attrs)
  end

  @doc "POST /v1/inventory/levels/set"
  def set_inventory(attrs) do
    post("/v1/inventory/levels/set", attrs)
  end

  @doc "GET /v1/inventory/locations"
  def list_locations do
    get("/v1/inventory/locations")
  end

  @doc "POST /v1/shipping/zones"
  def create_shipping_zone(attrs) do
    post("/v1/shipping/zones", attrs)
  end

  @doc "PATCH /v1/shipping/zones/:id"
  def update_shipping_zone(id, attrs) do
    patch("/v1/shipping/zones/#{id}", attrs)
  end

  @doc "DELETE /v1/shipping/zones/:id"
  def delete_shipping_zone(id) do
    delete("/v1/shipping/zones/#{id}")
  end

  @doc "POST /v1/shipping/zones/:id/rates"
  def create_shipping_rate(zone_id, attrs) do
    post("/v1/shipping/zones/#{zone_id}/rates", attrs)
  end

  @doc "GET /v1/tax/rates"
  def list_tax_rates do
    get("/v1/tax/rates")
  end

  @doc "POST /v1/tax/rates"
  def create_tax_rate(attrs) do
    post("/v1/tax/rates", attrs)
  end

  @doc "GET /v1/webhooks"
  def list_webhooks do
    get("/v1/webhooks")
  end

  @doc "POST /v1/webhooks"
  def create_webhook(attrs) do
    post("/v1/webhooks", attrs)
  end

  @doc "GET /v1/channels"
  def list_channels do
    get("/v1/channels")
  end

  @doc "GET /v1/metaobjects/definitions"
  def list_metaobject_definitions do
    get("/v1/metaobjects/definitions")
  end

  @doc "GET /v1/subscriptions/contracts"
  def list_subscription_contracts do
    get("/v1/subscriptions/contracts")
  end

  # ── Internal request builder ──────────────────────────────────────────────

  defp request(method, path, body, opts) do
    url = base_url() <> path
    headers = build_headers()

    req_opts =
      [
        method: method,
        url: url,
        headers: headers,
        receive_timeout: Keyword.get(opts, :timeout, timeout()),
        retry: false
      ]
      |> then(fn o ->
        if body, do: Keyword.merge(o, json: body), else: o
      end)

    case Req.request(req_opts) do
      {:ok, %{status: status, body: resp_body}} when status in 200..299 ->
        {:ok, unwrap(resp_body)}

      {:ok, %{status: status, body: resp_body}} ->
        error =
          case resp_body do
            %{"error" => %{"message" => msg}} when is_binary(msg) -> msg
            %{"error" => msg} when is_binary(msg) -> msg
            %{} -> inspect(resp_body)
            other -> inspect(other)
          end

        Logger.warning("Jarga API #{status} on #{method} #{path}: #{error}")
        {:error, %{status: status, body: resp_body}}

      {:error, reason} ->
        Logger.error("Jarga API request failed #{method} #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ── Content section ────────────────────────────────────────────────────────

  @doc "GET /v1/pim/collections"
  def list_collections(params \\ %{}) do
    get("/v1/pim/collections?" <> URI.encode_query(params))
  end

  @doc "GET /v1/pim/categories"
  def list_categories(params \\ %{}) do
    get("/v1/pim/categories?" <> URI.encode_query(params))
  end

  @doc "GET /v1/metaobjects/definitions"
  def list_metaobject_definitions(params \\ %{}) do
    get("/v1/metaobjects/definitions?" <> URI.encode_query(params))
  end

  @doc "GET /v1/dam/files"
  def list_dam_files(params \\ %{}) do
    get("/v1/dam/files?" <> URI.encode_query(params))
  end

  # ── Media ──────────────────────────────────────────────────────────────────

  @doc "POST /v1/pim/media/upload-url"
  def get_upload_url(attrs) do
    post("/v1/pim/media/upload-url", attrs)
  end

  @doc "POST /v1/pim/media/staged-uploads/complete"
  def complete_upload(attrs) do
    post("/v1/pim/media/staged-uploads/complete", attrs)
  end

  @doc "POST /v1/pim/media/attach"
  def attach_media(attrs) do
    post("/v1/pim/media/attach", attrs)
  end

  @doc "GET /v1/pim/media/:id"
  def get_media(id) do
    get("/v1/pim/media/#{id}")
  end

  @doc "PATCH /v1/pim/media/:id"
  def update_media(id, attrs) do
    patch("/v1/pim/media/#{id}", attrs)
  end

  @doc "DELETE /v1/pim/media/:id"
  def delete_media(id) do
    delete("/v1/pim/media/#{id}")
  end

  @doc "POST /v1/pim/products/:id/media/reorder"
  def reorder_media(product_id, order) do
    post("/v1/pim/products/#{product_id}/media/reorder", %{order: order})
  end

  # ── Flow engine ────────────────────────────────────────────────────────────

  @doc "GET /v1/flows"
  def list_flows(params \\ %{}) do
    get("/v1/flows?" <> URI.encode_query(params))
  end

  @doc "GET /v1/flows/:id"
  def get_flow(id) do
    get("/v1/flows/#{id}")
  end

  @doc "POST /v1/flows"
  def create_flow(attrs) do
    post("/v1/flows", attrs)
  end

  @doc "PATCH /v1/flows/:id"
  def update_flow(id, attrs) do
    patch("/v1/flows/#{id}", attrs)
  end

  @doc "DELETE /v1/flows/:id"
  def delete_flow(id) do
    delete("/v1/flows/#{id}")
  end

  @doc "POST /v1/flows/:id/enable or /disable or /test"
  def toggle_flow(id, action) when action in ["enable", "disable", "test"] do
    post("/v1/flows/#{id}/#{action}", %{})
  end

  @doc "GET /v1/flows/:id/runs"
  def list_flow_runs(flow_id) do
    get("/v1/flows/#{flow_id}/runs")
  end

  @doc "GET /v1/audit/events"
  def list_audit_events(params \\ %{}) do
    get("/v1/audit/events?" <> URI.encode_query(params))
  end

  @doc "GET /v1/events"
  def list_commerce_events(params \\ %{}) do
    get("/v1/events?" <> URI.encode_query(params))
  end

  # Unwrap the `{"data": ..., "error": null, "meta": ...}` envelope.
  # If the response is already a plain map (e.g. test stub), return as-is.
  defp unwrap(%{"data" => data}) when not is_nil(data), do: data
  defp unwrap(other), do: other

  defp build_headers do
    [
      {"authorization", "Bearer #{api_key()}"},
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ]
  end
end
