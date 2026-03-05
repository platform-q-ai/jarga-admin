defmodule JargaAdmin.Api do
  @moduledoc """
  HTTP client for the Jarga Commerce REST API.

  Configuration (env vars or application config):
  - `JARGA_API_URL`  — base URL (default: http://localhost:3000)
  - `JARGA_API_KEY`  — API key for HMAC signing

  All functions return `{:ok, data}` or `{:error, reason}`.

  ## HMAC signing
  Each request includes:
    - `X-Jarga-Timestamp` — Unix epoch seconds
    - `X-Jarga-Signature` — HMAC-SHA256 hex of "TIMESTAMP:METHOD:PATH:BODY_SHA256"
  """

  require Logger

  @default_timeout 10_000

  # ──────────────────────────────────────────────────────────────────────────
  # Configuration
  # ──────────────────────────────────────────────────────────────────────────

  defp base_url do
    System.get_env("JARGA_API_URL") ||
      Application.get_env(:jarga_admin, :api_url, "http://localhost:3000")
  end

  defp api_key do
    System.get_env("JARGA_API_KEY") ||
      Application.get_env(:jarga_admin, :api_key, "")
  end

  defp timeout do
    Application.get_env(:jarga_admin, :api_timeout, @default_timeout)
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Core HTTP verbs
  # ──────────────────────────────────────────────────────────────────────────

  @doc "HTTP GET"
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

  @doc "HTTP DELETE"
  def delete(path, opts \\ []) do
    request(:delete, path, nil, opts)
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Convenience wrappers
  # ──────────────────────────────────────────────────────────────────────────

  @doc "GET /v1/agent/context — full store snapshot"
  def agent_context do
    get("/v1/agent/context")
  end

  @doc "GET /v1/pim/products — list products"
  def list_products(params \\ %{}) do
    get("/v1/pim/products?" <> URI.encode_query(params))
  end

  @doc "GET /v1/oms/orders — list orders"
  def list_orders(params \\ %{}) do
    get("/v1/oms/orders?" <> URI.encode_query(params))
  end

  @doc "GET /v1/analytics/sales — get sales analytics"
  def get_analytics(params \\ %{}) do
    get("/v1/analytics/sales?" <> URI.encode_query(params))
  end

  @doc "GET /v1/crm/customers — list customers"
  def list_customers(params \\ %{}) do
    get("/v1/crm/customers?" <> URI.encode_query(params))
  end

  @doc "GET /v1/inventory/levels — inventory levels"
  def get_inventory_levels(params \\ %{}) do
    get("/v1/inventory/levels?" <> URI.encode_query(params))
  end

  @doc "POST /v1/promotions/campaigns — create promotion"
  def create_promotion(attrs) do
    post("/v1/promotions/campaigns", attrs)
  end

  @doc "POST /v1/pim/products — create product"
  def create_product(attrs) do
    post("/v1/pim/products", attrs)
  end

  @doc "GET /v1/oms/orders/:id"
  def get_order(id) do
    get("/v1/oms/orders/#{id}")
  end

  @doc "GET /v1/pim/products/:id"
  def get_product(id) do
    get("/v1/pim/products/#{id}")
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Internal request builder
  # ──────────────────────────────────────────────────────────────────────────

  defp request(method, path, body, opts) do
    url = base_url() <> path
    body_json = if body, do: Jason.encode!(body), else: ""
    headers = build_headers(method, path, body_json)

    req_opts =
      [
        method: method,
        url: url,
        headers: headers,
        receive_timeout: Keyword.get(opts, :timeout, timeout()),
        retry: false
      ]
      |> then(fn opts ->
        if body_json != "" do
          Keyword.put(opts, :body, body_json)
        else
          opts
        end
      end)

    case Req.request(req_opts) do
      {:ok, %{status: status, body: resp_body}} when status in 200..299 ->
        {:ok, resp_body}

      {:ok, %{status: status, body: resp_body}} ->
        Logger.warning("Jarga API error #{status}: #{inspect(resp_body)}")
        {:error, %{status: status, body: resp_body}}

      {:error, reason} ->
        Logger.error("Jarga API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_headers(method, path, body_json) do
    timestamp = System.system_time(:second) |> to_string()
    body_hash = :crypto.hash(:sha256, body_json) |> Base.encode16(case: :lower)
    method_str = method |> to_string() |> String.upcase()

    message = "#{timestamp}:#{method_str}:#{path}:#{body_hash}"

    signature =
      :crypto.mac(:hmac, :sha256, api_key(), message)
      |> Base.encode16(case: :lower)

    [
      {"content-type", "application/json"},
      {"accept", "application/json"},
      {"x-jarga-timestamp", timestamp},
      {"x-jarga-signature", signature}
    ]
  end
end
