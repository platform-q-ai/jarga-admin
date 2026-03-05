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
  end
end
