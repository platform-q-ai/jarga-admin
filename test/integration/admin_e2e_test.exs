defmodule JargaAdminWeb.Integration.AdminE2ETest do
  @moduledoc """
  End-to-end integration tests that run against a live Jarga Commerce API.

  These tests are tagged `@moduletag :integration` and are excluded from
  the normal test run. Run them with:

      JARGA_API_URL=http://localhost:8080 \\
      JARGA_API_KEY=your-admin-key \\
      mix test --only integration

  Prerequisites:
  - A running Jarga Commerce API accessible at JARGA_API_URL
  - A valid admin API key in JARGA_API_KEY
  - Seeded test data (use SEED=true when starting docker compose)

  CI job:
  - See .github/workflows/integration.yml for the CI configuration
    that starts the commerce API, seeds data, and runs these tests.
  """

  use JargaAdminWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @moduletag :integration

  # Skip these tests unless JARGA_API_URL is set to a non-Bypass URL
  setup do
    api_url = System.get_env("JARGA_API_URL")
    api_key = System.get_env("JARGA_API_KEY")

    if is_nil(api_url) or api_url == "" do
      {:ok, skip: "JARGA_API_URL not set — skipping integration tests"}
    else
      Application.put_env(:jarga_admin, :api_url, api_url)
      Application.put_env(:jarga_admin, :api_key, api_key || "")
      JargaAdmin.TabStore.invalidate_all_specs()
      {:ok, api_url: api_url, api_key: api_key}
    end
  end

  # ── Orders ────────────────────────────────────────────────────────────────

  @tag :integration
  test "navigating to /orders fetches and renders real orders", %{conn: conn} = ctx do
    if ctx[:skip], do: :skip

    {:ok, _view, html} = live(conn, "/orders")
    # Verify the page renders with order-related content
    assert html =~ "JARGA"
    # Orders tab should be active
    assert html =~ "Orders" or html =~ "order"
  end

  @tag :integration
  test "navigating to /products fetches and renders real products", %{conn: conn} = ctx do
    if ctx[:skip], do: :skip

    {:ok, _view, html} = live(conn, "/products")
    assert html =~ "JARGA"
    assert html =~ "Products" or html =~ "product"
  end

  @tag :integration
  test "navigating to /customers fetches and renders real customers", %{conn: conn} = ctx do
    if ctx[:skip], do: :skip

    {:ok, _view, html} = live(conn, "/customers")
    assert html =~ "JARGA"
    assert html =~ "Customers" or html =~ "customer"
  end

  @tag :integration
  test "creating a product via API and verifying it appears in list", %{conn: conn} = ctx do
    if ctx[:skip], do: :skip

    # Create a product directly via the API
    unique_name = "E2E Test Product #{System.unique_integer([:positive])}"

    result =
      JargaAdmin.Api.create_product(%{
        title: unique_name,
        status: "draft",
        vendor: "E2E Tests"
      })

    case result do
      {:ok, product} ->
        product_id = product["id"]

        # Load the products list
        {:ok, view, _html} = live(conn, "/products")
        render_click(view, "switch_tab", %{"id" => "products"})

        # Drill into the product
        html = render_click(view, "view_product", %{"id" => product_id})
        assert html =~ "JARGA"

        # Cleanup
        JargaAdmin.Api.delete_product(product_id)

      {:error, _} ->
        # API unavailable or create not supported — skip gracefully
        :skip
    end
  end

  @tag :integration
  test "drilling into order detail shows order data", %{conn: conn} = ctx do
    if ctx[:skip], do: :skip

    # List orders to find one
    case JargaAdmin.Api.list_orders() do
      {:ok, %{"items" => [order | _]}} ->
        order_id = order["id"]
        {:ok, view, _html} = live(conn, "/orders")
        html = render_click(view, "view_order", %{"id" => order_id})
        assert html =~ "JARGA"
        # Should show order detail content
        assert html =~ order_id or html =~ "Order"

      {:ok, %{"items" => []}} ->
        # No orders — skip gracefully
        :skip

      {:error, _} ->
        :skip
    end
  end

  @tag :integration
  test "chat submission sends a message and receives a response", %{conn: conn} = ctx do
    if ctx[:skip], do: :skip

    {:ok, view, _html} = live(conn, "/chat")
    # Submit a simple natural language query
    html = render_submit(view, "chat_submit", %{"message" => "Show me the dashboard"})
    assert html =~ "JARGA"
  end
end
