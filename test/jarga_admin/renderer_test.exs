defmodule JargaAdmin.RendererTest do
  use ExUnit.Case, async: true

  alias JargaAdmin.Renderer

  describe "render_spec/1" do
    test "returns empty list for nil" do
      assert [] = Renderer.render_spec(nil)
    end

    test "returns empty list for empty components" do
      assert [] = Renderer.render_spec(%{"components" => []})
    end

    test "normalizes metric_grid component" do
      spec = %{
        "components" => [
          %{
            "type" => "metric_grid",
            "data" => %{
              "metrics" => [
                %{"label" => "Revenue", "value" => "£1,200", "trend" => 12.5}
              ]
            }
          }
        ]
      }

      [comp] = Renderer.render_spec(spec)
      assert comp.type == :metric_grid
      assert length(comp.assigns.metrics) == 1
    end

    test "normalizes data_table component with columns" do
      spec = %{
        "components" => [
          %{
            "type" => "data_table",
            "title" => "Orders",
            "data" => %{
              "columns" => [
                %{"key" => "id", "label" => "Order ID"},
                %{"key" => "status", "label" => "Status", "type" => "status"}
              ],
              "rows" => [%{"id" => "#001", "status" => "fulfilled"}]
            }
          }
        ]
      }

      [comp] = Renderer.render_spec(spec)
      assert comp.type == :data_table
      assert comp.assigns.title == "Orders"
      assert length(comp.assigns.columns) == 2
      assert length(comp.assigns.rows) == 1
      assert hd(comp.assigns.columns).key == :id
      assert hd(comp.assigns.columns).label == "Order ID"
    end

    test "normalizes detail_card component" do
      spec = %{
        "components" => [
          %{
            "type" => "detail_card",
            "title" => "Order #1234",
            "data" => %{
              "pairs" => [%{"label" => "Customer", "value" => "Sarah"}],
              "timeline" => [%{"title" => "Placed", "time" => "12:00"}]
            }
          }
        ]
      }

      [comp] = Renderer.render_spec(spec)
      assert comp.type == :detail_card
      assert comp.assigns.title == "Order #1234"
      assert length(comp.assigns.pairs) == 1
      assert length(comp.assigns.timeline) == 1
    end

    test "normalizes chart component" do
      spec = %{
        "components" => [
          %{
            "type" => "chart",
            "title" => "Revenue",
            "data" => %{
              "type" => "line",
              "labels" => ["Mon", "Tue"],
              "datasets" => [%{"label" => "Rev", "data" => [100, 200]}]
            }
          }
        ]
      }

      [comp] = Renderer.render_spec(spec)
      assert comp.type == :chart
      assert comp.assigns.type == "line"
      assert comp.assigns.labels == ["Mon", "Tue"]
    end

    test "normalizes alert_banner component" do
      spec = %{
        "components" => [
          %{
            "type" => "alert_banner",
            "data" => %{"kind" => "warn", "message" => "Low stock!"}
          }
        ]
      }

      [comp] = Renderer.render_spec(spec)
      assert comp.type == :alert_banner
      assert comp.assigns.kind == :warn
      assert comp.assigns.message == "Low stock!"
    end

    test "normalizes dynamic_form component" do
      spec = %{
        "components" => [
          %{
            "type" => "dynamic_form",
            "title" => "New Product",
            "data" => %{
              "fields" => [%{"key" => "name", "label" => "Name", "type" => "text"}],
              "submit_event" => "create_product"
            }
          }
        ]
      }

      [comp] = Renderer.render_spec(spec)
      assert comp.type == :dynamic_form
      assert comp.assigns.submit_event == "create_product"
      assert length(comp.assigns.fields) == 1
    end

    test "handles multiple components" do
      spec = %{
        "components" => [
          %{"type" => "metric_grid", "data" => %{"metrics" => []}},
          %{"type" => "data_table", "data" => %{"columns" => [], "rows" => []}}
        ]
      }

      comps = Renderer.render_spec(spec)
      assert length(comps) == 2
    end

    test "marks unknown types with :unknown" do
      spec = %{
        "components" => [
          %{"type" => "wizard_widget", "data" => %{}}
        ]
      }

      [comp] = Renderer.render_spec(spec)
      assert comp.type == :unknown
    end

    test "normalizes inventory_detail_table component" do
      spec = %{
        "components" => [
          %{
            "type" => "inventory_detail_table",
            "title" => "All inventory",
            "data" => %{
              "rows" => [%{"product" => "Leather Journal", "variant" => "Brown", "sku" => "LJ-A5-BRN", "available" => 48, "status" => "in_stock"}]
            }
          }
        ]
      }

      [comp] = Renderer.render_spec(spec)
      assert comp.type == :inventory_detail_table
      assert comp.assigns.title == "All inventory"
      assert length(comp.assigns.rows) == 1
    end

    test "normalizes analytics_revenue component" do
      spec = %{
        "components" => [
          %{
            "type" => "analytics_revenue",
            "title" => "Revenue by month",
            "data" => %{
              "rows" => [%{"month" => "2025-01", "revenue" => 12_000, "count" => 8}]
            }
          }
        ]
      }

      [comp] = Renderer.render_spec(spec)
      assert comp.type == :analytics_revenue
      assert comp.assigns.title == "Revenue by month"
      assert [%{"month" => "2025-01"}] = comp.assigns.rows
    end

    test "normalizes analytics_breakdown component" do
      spec = %{
        "components" => [
          %{
            "type" => "analytics_breakdown",
            "title" => "Orders by status",
            "data" => %{
              "rows" => [%{"status" => "Paid", "count" => 42, "revenue" => 50_000}]
            }
          }
        ]
      }

      [comp] = Renderer.render_spec(spec)
      assert comp.type == :analytics_breakdown
      assert comp.assigns.title == "Orders by status"
      assert [%{"status" => "Paid", "count" => 42}] = comp.assigns.rows
    end

    test "normalizes shipping_zones_table component" do
      spec = %{
        "components" => [
          %{
            "type" => "shipping_zones_table",
            "title" => "Shipping zones",
            "data" => %{
              "zones" => [%{"name" => "United Kingdom", "countries" => "GB", "active" => "Active"}]
            }
          }
        ]
      }

      [comp] = Renderer.render_spec(spec)
      assert comp.type == :shipping_zones_table
      assert comp.assigns.title == "Shipping zones"
      assert length(comp.assigns.zones) == 1
    end
  end
end
