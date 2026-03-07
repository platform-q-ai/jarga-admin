defmodule JargaAdmin.Renderer do
  @moduledoc """
  Converts a UI spec (map from Quecto) into component assigns for rendering
  in the ChatLive right pane.

  The renderer is stateless — it just maps spec → component assigns.
  Actual rendering happens in the LiveView via JargaComponents.
  """

  @doc """
  Normalize a UI spec map into a list of renderable component assigns.
  Each element in the returned list has:
    - `:type` — atom component type
    - `:assigns` — map of assigns for the component function

  Returns an empty list if spec is nil or invalid.
  """
  def render_spec(nil), do: []

  def render_spec(%{"components" => components}) when is_list(components) do
    Enum.map(components, &normalize_component/1)
  end

  def render_spec(_), do: []

  defp normalize_component(%{"type" => "metric_grid", "data" => data}) do
    %{type: :metric_grid, assigns: %{metrics: data["metrics"] || []}}
  end

  defp normalize_component(%{"type" => "metric_card", "data" => data}) do
    %{
      type: :metric_card,
      assigns: %{
        label: data["label"] || "",
        value: data["value"] || "—",
        trend: data["trend"],
        subtitle: data["subtitle"]
      }
    }
  end

  defp normalize_component(%{"type" => "detail_card"} = spec) do
    data = spec["data"] || %{}

    %{
      type: :detail_card,
      assigns: %{
        title: spec["title"] || "Details",
        pairs: data["pairs"] || [],
        timeline: data["timeline"] || [],
        actions: data["actions"] || []
      }
    }
  end

  defp normalize_component(%{"type" => "chart"} = spec) do
    data = spec["data"] || %{}

    %{
      type: :chart,
      assigns: %{
        id: "chart-#{:erlang.unique_integer([:positive])}",
        title: spec["title"],
        type: data["type"] || "line",
        labels: data["labels"] || [],
        datasets: data["datasets"] || []
      }
    }
  end

  defp normalize_component(%{"type" => "alert_banner", "data" => data}) do
    kind =
      case data["kind"] do
        "warn" -> :warn
        "error" -> :error
        _ -> :info
      end

    %{
      type: :alert_banner,
      assigns: %{
        kind: kind,
        title: data["title"],
        message: data["message"] || "",
        retry_event: data["retry_event"]
      }
    }
  end

  defp normalize_component(%{"type" => "dynamic_form"} = spec) do
    data = spec["data"] || %{}

    %{
      type: :dynamic_form,
      assigns: %{
        id: "form-#{:erlang.unique_integer([:positive])}",
        title: spec["title"],
        fields: data["fields"] || [],
        values: data["values"] || %{},
        submit_event: data["submit_event"] || "submit_form",
        cancel_event: "cancel_form",
        api_endpoint: data["api_endpoint"]
      }
    }
  end

  defp normalize_component(%{"type" => "empty_state", "data" => data}) do
    %{
      type: :empty_state,
      assigns: %{
        icon: nil,
        title: data["title"] || "Nothing here yet",
        message: data["message"]
      }
    }
  end

  defp normalize_component(%{"type" => "stat_bar", "data" => data}) do
    %{type: :stat_bar, assigns: %{stats: data["stats"] || []}}
  end

  defp normalize_component(%{"type" => "product_grid"} = spec) do
    data = spec["data"] || %{}

    %{
      type: :product_grid,
      assigns: %{
        title: spec["title"],
        products: data["products"] || [],
        on_click: data["on_click"] || "view_product"
      }
    }
  end

  defp normalize_component(%{"type" => "order_detail"} = spec) do
    %{type: :order_detail, assigns: %{order: spec["data"] || %{}}}
  end

  defp normalize_component(%{"type" => "product_detail"} = spec) do
    %{type: :product_detail, assigns: %{product: spec["data"] || %{}}}
  end

  defp normalize_component(%{"type" => "customer_detail"} = spec) do
    data = spec["data"] || %{}

    %{
      type: :customer_detail,
      assigns: %{
        customer: data["customer"] || data,
        recent_orders: data["recent_orders"] || []
      }
    }
  end

  defp normalize_component(%{"type" => "promotion_list"} = spec) do
    data = spec["data"] || %{}

    %{
      type: :promotion_list,
      assigns: %{title: spec["title"] || "Promotions", promotions: data["promotions"] || []}
    }
  end

  defp normalize_component(%{"type" => "inventory_table"} = spec) do
    data = spec["data"] || %{}

    %{
      type: :inventory_table,
      assigns: %{
        title: spec["title"] || "Inventory",
        rows: data["rows"] || [],
        on_restock: data["on_restock"] || "restock_item"
      }
    }
  end

  defp normalize_component(%{"type" => "inventory_detail_table"} = spec) do
    data = spec["data"] || %{}

    %{
      type: :inventory_detail_table,
      assigns: %{
        title: spec["title"] || "Inventory",
        rows: data["rows"] || []
      }
    }
  end

  defp normalize_component(%{"type" => "analytics_revenue"} = spec) do
    data = spec["data"] || %{}

    %{
      type: :analytics_revenue,
      assigns: %{
        title: spec["title"] || "Revenue by month",
        rows: data["rows"] || []
      }
    }
  end

  defp normalize_component(%{"type" => "analytics_breakdown"} = spec) do
    data = spec["data"] || %{}

    %{
      type: :analytics_breakdown,
      assigns: %{
        title: spec["title"] || "Orders by status",
        rows: data["rows"] || []
      }
    }
  end

  defp normalize_component(%{"type" => "shipping_zones_table"} = spec) do
    data = spec["data"] || %{}

    %{
      type: :shipping_zones_table,
      assigns: %{
        title: spec["title"] || "Shipping zones",
        zones: data["zones"] || []
      }
    }
  end

  defp normalize_component(%{"type" => "data_table"} = spec) do
    data = spec["data"] || %{}

    %{
      type: :data_table,
      assigns: %{
        id: "tbl-#{:erlang.unique_integer([:positive])}",
        title: spec["title"],
        columns: normalize_columns(data["columns"] || []),
        rows: data["rows"] || [],
        actions: data["actions"] || [],
        on_row_click: data["on_row_click"],
        sort_key: nil,
        sort_dir: :asc,
        on_sort: nil,
        empty_message: data["empty_message"] || "No data to display"
      }
    }
  end

  defp normalize_component(%{"type" => "pagination", "data" => data}) do
    %{
      type: :pagination,
      assigns: %{
        page: data["page"] || 1,
        per_page: data["per_page"] || 50,
        total: data["total"],
        total_pages: data["total_pages"]
      }
    }
  end

  defp normalize_component(%{"type" => "action_bar", "data" => data}) do
    %{
      type: :action_bar,
      assigns: %{
        actions: data["actions"] || []
      }
    }
  end

  defp normalize_component(unknown) do
    %{type: :unknown, assigns: %{raw: unknown}}
  end

  defp normalize_columns(columns) do
    Enum.map(columns, fn col ->
      %{
        key: String.to_atom(col["key"] || ""),
        label: col["label"] || "",
        type: col["type"] && String.to_atom(col["type"])
      }
    end)
  end
end
