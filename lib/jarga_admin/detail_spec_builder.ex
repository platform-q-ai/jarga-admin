defmodule JargaAdmin.DetailSpecBuilder do
  @moduledoc """
  Builds detail-panel UI specs for individual entity views
  (shipping zones, promotions, etc.).

  These functions are extracted from ChatLive to reduce the size of
  that module and centralise spec-building logic in the domain layer.
  """

  # ── Shipping zone ─────────────────────────────────────────────────────────

  @doc "Build a UI spec for a shipping zone detail view."
  def build_shipping_zone_spec(zone, rates) do
    zone_id = zone["id"]
    countries = zone["countries"] || []

    rate_rows =
      Enum.map(rates, fn r ->
        %{
          "id" => r["id"] || "",
          "name" => r["name"] || "—",
          "type" => r["type"] || "flat",
          "price" => "£#{(r["price"] || 0) / 100}",
          "min_weight" => "#{r["min_weight"] || "—"}",
          "max_weight" => "#{r["max_weight"] || "—"}"
        }
      end)

    %{
      "components" => [
        %{
          "type" => "action_bar",
          "data" => %{
            "back_event" => "cancel_form",
            "back_label" => "Back to shipping",
            "actions" => [
              %{"label" => "Delete zone", "event" => "delete_shipping_zone", "value" => zone_id}
            ]
          }
        },
        %{
          "type" => "detail_card",
          "title" => zone["name"] || "Shipping zone",
          "data" => %{
            "fields" => [
              %{
                "label" => "Status",
                "value" => if(zone["active"], do: "Active", else: "Inactive")
              },
              %{"label" => "Countries", "value" => Enum.join(countries, ", ")},
              %{"label" => "Total rates", "value" => "#{length(rates)}"}
            ]
          }
        },
        %{
          "type" => "data_table",
          "title" => "Shipping rates",
          "data" => %{
            "columns" => [
              %{"key" => "name", "label" => "Rate name"},
              %{"key" => "type", "label" => "Type"},
              %{"key" => "price", "label" => "Price"},
              %{"key" => "min_weight", "label" => "Min weight"},
              %{"key" => "max_weight", "label" => "Max weight"}
            ],
            "rows" => rate_rows,
            "on_row_click" => nil
          }
        },
        %{
          "type" => "dynamic_form",
          "title" => "Add shipping rate",
          "data" => %{
            "fields" => [
              %{"key" => "_zone_id", "label" => "Zone ID", "type" => "hidden"},
              %{"key" => "name", "label" => "Rate name", "type" => "text", "required" => true},
              %{
                "key" => "type",
                "label" => "Rate type",
                "type" => "select",
                "options" => ["flat", "weight_based", "price_based", "free"]
              },
              %{"key" => "price", "label" => "Price (pence)", "type" => "number"},
              %{"key" => "min_weight", "label" => "Min weight (g)", "type" => "number"},
              %{"key" => "max_weight", "label" => "Max weight (g)", "type" => "number"}
            ],
            "values" => %{"_zone_id" => zone_id},
            "submit_event" => "add_shipping_rate"
          }
        }
      ]
    }
  end

  # ── Promotion ─────────────────────────────────────────────────────────────

  @doc "Build a UI spec for a promotion detail view."
  def build_promotion_spec(promo, coupons) do
    coupon_rows =
      Enum.map(coupons, fn c ->
        %{
          "code" => c["code"] || "",
          "uses" => "#{c["uses"] || 0}",
          "max_uses" => "#{c["max_uses"] || "∞"}",
          "expires_at" => c["expires_at"] || "—"
        }
      end)

    %{
      "components" => [
        %{
          "type" => "action_bar",
          "data" => %{
            "back_event" => "cancel_form",
            "back_label" => "Back to promotions",
            "actions" =>
              [
                if(promo["status"] == "draft",
                  do: %{
                    "label" => "Publish",
                    "event" => "publish_promotion",
                    "value" => promo["id"],
                    "style" => "solid"
                  },
                  else: nil
                ),
                %{
                  "label" => "Generate coupons",
                  "event" => "show_generate_coupons_form",
                  "value" => promo["id"]
                }
              ]
              |> Enum.reject(&is_nil/1)
          }
        },
        %{
          "type" => "detail_card",
          "title" => promo["name"] || "Promotion",
          "data" => %{
            "fields" => [
              %{"label" => "Status", "value" => promo["status"] || "—"},
              %{"label" => "Type", "value" => promo["discount_type"] || "—"},
              %{
                "label" => "Value",
                "value" =>
                  "#{promo["discount_value"] || 0}#{if promo["discount_type"] == "percentage", do: "%", else: ""}"
              },
              %{"label" => "Start date", "value" => promo["starts_at"] || "—"},
              %{"label" => "End date", "value" => promo["ends_at"] || "—"},
              %{"label" => "Uses", "value" => "#{promo["use_count"] || 0}"}
            ]
          }
        },
        %{
          "type" => "data_table",
          "title" => "Coupon codes",
          "data" => %{
            "columns" => [
              %{"key" => "code", "label" => "Code"},
              %{"key" => "uses", "label" => "Uses"},
              %{"key" => "max_uses", "label" => "Max uses"},
              %{"key" => "expires_at", "label" => "Expires"}
            ],
            "rows" => coupon_rows,
            "on_row_click" => nil
          }
        },
        %{
          "type" => "dynamic_form",
          "title" => "Generate coupon codes",
          "data" => %{
            "fields" => [
              %{"key" => "_campaign_id", "label" => "Campaign ID", "type" => "hidden"},
              %{
                "key" => "count",
                "label" => "Number of codes",
                "type" => "number",
                "placeholder" => "10"
              },
              %{"key" => "prefix", "label" => "Code prefix (optional)", "type" => "text"}
            ],
            "values" => %{"_campaign_id" => promo["id"]},
            "submit_event" => "generate_coupons"
          }
        }
      ]
    }
  end
end
