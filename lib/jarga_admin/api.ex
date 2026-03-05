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
        error = get_in(resp_body, ["error", "message"]) || inspect(resp_body)
        Logger.warning("Jarga API #{status} on #{method} #{path}: #{error}")
        {:error, %{status: status, body: resp_body}}

      {:error, reason} ->
        Logger.error("Jarga API request failed #{method} #{path}: #{inspect(reason)}")
        {:error, reason}
    end
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
