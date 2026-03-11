defmodule JargaAdmin.StorefrontAnalyticsTest do
  use ExUnit.Case, async: true

  alias JargaAdmin.StorefrontAnalytics

  import ExUnit.CaptureLog

  describe "track/2" do
    test "logs page_view event" do
      log =
        capture_log(fn ->
          StorefrontAnalytics.track(:page_view, %{
            slug: "home",
            page_title: "Home",
            channel: "online-store"
          })
        end)

      assert log =~ "page_view"
      assert log =~ "home"
    end

    test "logs add_to_cart event" do
      log =
        capture_log(fn ->
          StorefrontAnalytics.track(:add_to_cart, %{
            product_id: "prod-1",
            quantity: 1,
            price: "£89.00"
          })
        end)

      assert log =~ "add_to_cart"
      assert log =~ "prod-1"
    end

    test "logs search event with query and result count" do
      log =
        capture_log(fn ->
          StorefrontAnalytics.track(:search, %{
            query: "linen",
            result_count: 5
          })
        end)

      assert log =~ "search"
      assert log =~ "linen"
    end

    test "includes timestamp in event" do
      log =
        capture_log(fn ->
          StorefrontAnalytics.track(:page_view, %{slug: "bedroom"})
        end)

      assert log =~ "timestamp"
    end

    test "handles unknown event types gracefully" do
      log =
        capture_log(fn ->
          StorefrontAnalytics.track(:unknown_event, %{data: "test"})
        end)

      assert log =~ "unknown_event"
    end

    test "does not crash on nil data" do
      assert :ok == StorefrontAnalytics.track(:page_view, nil)
    end
  end
end
