defmodule JargaAdmin.Quecto.MockBridge do
  @moduledoc """
  Mock Quecto bridge for development/testing when the quecto binary is unavailable.
  Simulates realistic commerce-aware responses with UI specs.
  """

  alias Phoenix.PubSub

  @pubsub JargaAdmin.PubSub

  @doc """
  Simulate sending a message and streaming a response back via PubSub.
  """
  def send_message(session_id, message) do
    Task.start(fn ->
      # Simulate thinking
      broadcast_activity(session_id, %{
        kind: :thinking,
        model: "claude-3-5-sonnet",
        tokens: 1024,
        time: current_time()
      })

      Process.sleep(400)

      response = generate_response(message)

      # Stream the text response
      chunks = chunk_text(response.text)

      Enum.each(chunks, fn chunk ->
        PubSub.broadcast(@pubsub, "quecto:#{session_id}:response", {:chunk, chunk})
        Process.sleep(30)
      end)

      # Broadcast UI spec if present
      if response.ui_spec do
        PubSub.broadcast(@pubsub, "quecto:#{session_id}:ui_spec", {:ui_spec, response.ui_spec})
      end

      # Done
      PubSub.broadcast(@pubsub, "quecto:#{session_id}:response", :done)
    end)

    :ok
  end

  defp generate_response(message) do
    msg = String.downcase(message)

    cond do
      contains_any(msg, ["order", "orders"]) ->
        %{
          text: "Here are your recent orders. You have 3 orders pending dispatch.",
          ui_spec: %{
            "layout" => "full",
            "components" => [
              %{
                "type" => "data_table",
                "title" => "Recent Orders",
                "data" => %{
                  "columns" => [
                    %{"key" => "id", "label" => "Order"},
                    %{"key" => "customer", "label" => "Customer"},
                    %{"key" => "total", "label" => "Total"},
                    %{"key" => "status", "label" => "Status"},
                    %{"key" => "date", "label" => "Date"}
                  ],
                  "rows" => [
                    %{
                      "id" => "#1042",
                      "customer" => "Sarah Mitchell",
                      "total" => "£89.00",
                      "status" => "pending",
                      "date" => "4 Mar 2026"
                    },
                    %{
                      "id" => "#1041",
                      "customer" => "James Cooper",
                      "total" => "£234.50",
                      "status" => "fulfilled",
                      "date" => "3 Mar 2026"
                    },
                    %{
                      "id" => "#1040",
                      "customer" => "Emma Walsh",
                      "total" => "£45.00",
                      "status" => "pending",
                      "date" => "3 Mar 2026"
                    },
                    %{
                      "id" => "#1039",
                      "customer" => "Oliver Park",
                      "total" => "£178.00",
                      "status" => "fulfilled",
                      "date" => "2 Mar 2026"
                    },
                    %{
                      "id" => "#1038",
                      "customer" => "Lily Chen",
                      "total" => "£67.00",
                      "status" => "pending",
                      "date" => "2 Mar 2026"
                    }
                  ],
                  "actions" => [%{"label" => "View", "event" => "view_order"}]
                }
              }
            ]
          }
        }

      contains_any(msg, ["revenue", "sales", "analytics", "how are we doing", "performance"]) ->
        %{
          text:
            "Here's your store performance for today. Revenue is up 12.4% compared to yesterday.",
          ui_spec: %{
            "layout" => "full",
            "components" => [
              %{
                "type" => "metric_grid",
                "data" => %{
                  "metrics" => [
                    %{
                      "label" => "Revenue",
                      "value" => "£1,247",
                      "trend" => 12.4,
                      "subtitle" => "Today"
                    },
                    %{
                      "label" => "Orders",
                      "value" => "14",
                      "trend" => 7.7,
                      "subtitle" => "Today"
                    },
                    %{
                      "label" => "Avg Order Value",
                      "value" => "£89.07",
                      "trend" => 4.2,
                      "subtitle" => "Today"
                    },
                    %{
                      "label" => "Returns",
                      "value" => "1",
                      "trend" => -50.0,
                      "subtitle" => "Today"
                    }
                  ]
                }
              },
              %{
                "type" => "chart",
                "title" => "Daily Revenue (Last 7 Days)",
                "data" => %{
                  "type" => "line",
                  "labels" => ["26 Feb", "27 Feb", "28 Feb", "1 Mar", "2 Mar", "3 Mar", "4 Mar"],
                  "datasets" => [
                    %{"label" => "Revenue (£)", "data" => [890, 1120, 760, 1340, 980, 1105, 1247]}
                  ]
                }
              }
            ]
          }
        }

      contains_any(msg, ["product", "products", "catalogue", "catalog"]) ->
        %{
          text: "You have 47 products in your catalogue. 3 are low on stock.",
          ui_spec: %{
            "layout" => "full",
            "components" => [
              %{
                "type" => "data_table",
                "title" => "Products",
                "data" => %{
                  "columns" => [
                    %{"key" => "name", "label" => "Product"},
                    %{"key" => "sku", "label" => "SKU"},
                    %{"key" => "price", "label" => "Price"},
                    %{"key" => "stock", "label" => "Stock"},
                    %{"key" => "status", "label" => "Status"}
                  ],
                  "rows" => [
                    %{
                      "name" => "Leather Journal A5",
                      "sku" => "LJ-A5-001",
                      "price" => "£34.99",
                      "stock" => 40,
                      "status" => "published"
                    },
                    %{
                      "name" => "Canvas Tote Bag",
                      "sku" => "CTB-NAT-001",
                      "price" => "£24.99",
                      "stock" => 3,
                      "status" => "published"
                    },
                    %{
                      "name" => "Ceramic Mug — Slate",
                      "sku" => "MUG-SL-001",
                      "price" => "£18.00",
                      "stock" => 120,
                      "status" => "published"
                    },
                    %{
                      "name" => "Oak Serving Board",
                      "sku" => "OSB-001",
                      "price" => "£42.00",
                      "stock" => 2,
                      "status" => "published"
                    },
                    %{
                      "name" => "Beeswax Candle Set",
                      "sku" => "BWC-SET-001",
                      "price" => "£28.00",
                      "stock" => 0,
                      "status" => "draft"
                    }
                  ],
                  "actions" => [%{"label" => "Edit", "event" => "edit_product"}]
                }
              }
            ]
          }
        }

      contains_any(msg, ["stock", "inventory", "low stock", "restock"]) ->
        %{
          text: "You have 3 products with low or zero stock that need attention.",
          ui_spec: %{
            "layout" => "full",
            "components" => [
              %{
                "type" => "alert_banner",
                "data" => %{
                  "kind" => "warn",
                  "title" => "Low Stock Alert",
                  "message" => "3 products need restocking"
                }
              },
              %{
                "type" => "data_table",
                "title" => "Low Stock Items",
                "data" => %{
                  "columns" => [
                    %{"key" => "name", "label" => "Product"},
                    %{"key" => "stock", "label" => "Stock"},
                    %{"key" => "reorder_at", "label" => "Reorder Point"}
                  ],
                  "rows" => [
                    %{"name" => "Beeswax Candle Set", "stock" => 0, "reorder_at" => 10},
                    %{"name" => "Canvas Tote Bag", "stock" => 3, "reorder_at" => 15},
                    %{"name" => "Oak Serving Board", "stock" => 2, "reorder_at" => 5}
                  ]
                }
              }
            ]
          }
        }

      contains_any(msg, ["customer", "customers", "buyer", "buyers"]) ->
        %{
          text: "You have 128 customers. Here are your top buyers this month.",
          ui_spec: %{
            "layout" => "full",
            "components" => [
              %{
                "type" => "data_table",
                "title" => "Top Customers — March",
                "data" => %{
                  "columns" => [
                    %{"key" => "name", "label" => "Customer"},
                    %{"key" => "orders", "label" => "Orders"},
                    %{"key" => "spent", "label" => "Total Spent"},
                    %{"key" => "last_order", "label" => "Last Order"}
                  ],
                  "rows" => [
                    %{
                      "name" => "Sarah Mitchell",
                      "orders" => 8,
                      "spent" => "£1,840",
                      "last_order" => "4 Mar"
                    },
                    %{
                      "name" => "James Cooper",
                      "orders" => 5,
                      "spent" => "£1,120",
                      "last_order" => "3 Mar"
                    },
                    %{
                      "name" => "Emma Walsh",
                      "orders" => 4,
                      "spent" => "£876",
                      "last_order" => "3 Mar"
                    },
                    %{
                      "name" => "Oliver Park",
                      "orders" => 3,
                      "spent" => "£534",
                      "last_order" => "2 Mar"
                    }
                  ]
                }
              }
            ]
          }
        }

      contains_any(msg, ["create product", "add product", "new product"]) ->
        %{
          text: "I'll open a form for you to create a new product.",
          ui_spec: %{
            "layout" => "full",
            "components" => [
              %{
                "type" => "dynamic_form",
                "title" => "Create Product",
                "data" => %{
                  "fields" => [
                    %{
                      "key" => "name",
                      "label" => "Product Name",
                      "type" => "text",
                      "required" => true
                    },
                    %{"key" => "description", "label" => "Description", "type" => "textarea"},
                    %{
                      "key" => "price",
                      "label" => "Price (£)",
                      "type" => "number",
                      "required" => true
                    },
                    %{"key" => "sku", "label" => "SKU", "type" => "text"},
                    %{"key" => "stock", "label" => "Initial Stock", "type" => "number"},
                    %{
                      "key" => "status",
                      "label" => "Status",
                      "type" => "select",
                      "options" => ["draft", "published"]
                    }
                  ],
                  "submit_event" => "create_product"
                }
              }
            ]
          }
        }

      contains_any(msg, ["promotion", "discount", "sale", "coupon"]) ->
        %{
          text: "I'll help you create a promotion. Fill in the details below.",
          ui_spec: %{
            "layout" => "full",
            "components" => [
              %{
                "type" => "dynamic_form",
                "title" => "Create Promotion",
                "data" => %{
                  "fields" => [
                    %{
                      "key" => "name",
                      "label" => "Campaign Name",
                      "type" => "text",
                      "required" => true
                    },
                    %{
                      "key" => "discount_type",
                      "label" => "Discount Type",
                      "type" => "select",
                      "options" => ["percentage", "fixed_amount"]
                    },
                    %{
                      "key" => "discount_value",
                      "label" => "Discount Value",
                      "type" => "number",
                      "required" => true
                    },
                    %{"key" => "starts_at", "label" => "Start Date", "type" => "date"},
                    %{"key" => "ends_at", "label" => "End Date", "type" => "date"},
                    %{
                      "key" => "coupon_code",
                      "label" => "Coupon Code (optional)",
                      "type" => "text"
                    }
                  ],
                  "submit_event" => "create_promotion"
                }
              }
            ]
          }
        }

      contains_any(msg, ["dashboard", "overview", "summary"]) ->
        build_dashboard_response()

      true ->
        %{
          text:
            "I'm here to help you manage your Jarga Commerce store. You can ask me about:\n\n- **Orders** — view, fulfil, or refund orders\n- **Products** — manage your catalogue\n- **Customers** — view customer profiles and history\n- **Analytics** — revenue, trends, and performance\n- **Inventory** — stock levels and alerts\n- **Promotions** — discounts and campaigns\n\nWhat would you like to do?",
          ui_spec: nil
        }
    end
  end

  defp build_dashboard_response do
    %{
      text: "Here's your store dashboard. Revenue is up 12.4% today.",
      ui_spec: %{
        "layout" => "full",
        "components" => [
          %{
            "type" => "metric_grid",
            "data" => %{
              "metrics" => [
                %{
                  "label" => "Revenue",
                  "value" => "£1,247",
                  "trend" => 12.4,
                  "subtitle" => "Today"
                },
                %{"label" => "Orders", "value" => "14", "trend" => 7.7, "subtitle" => "Today"},
                %{
                  "label" => "Avg Order Value",
                  "value" => "£89.07",
                  "trend" => 4.2,
                  "subtitle" => "Today"
                },
                %{"label" => "Returns", "value" => "1", "trend" => -50.0, "subtitle" => "Today"}
              ]
            }
          },
          %{
            "type" => "data_table",
            "title" => "Recent Orders",
            "data" => %{
              "columns" => [
                %{"key" => "id", "label" => "Order"},
                %{"key" => "customer", "label" => "Customer"},
                %{"key" => "total", "label" => "Total"},
                %{"key" => "status", "label" => "Status"}
              ],
              "rows" => [
                %{
                  "id" => "#1042",
                  "customer" => "Sarah Mitchell",
                  "total" => "£89.00",
                  "status" => "pending"
                },
                %{
                  "id" => "#1041",
                  "customer" => "James Cooper",
                  "total" => "£234.50",
                  "status" => "fulfilled"
                },
                %{
                  "id" => "#1040",
                  "customer" => "Emma Walsh",
                  "total" => "£45.00",
                  "status" => "pending"
                }
              ]
            }
          },
          %{
            "type" => "data_table",
            "title" => "Low Stock Items",
            "data" => %{
              "columns" => [
                %{"key" => "name", "label" => "Product"},
                %{"key" => "stock", "label" => "Stock"}
              ],
              "rows" => [
                %{"name" => "Beeswax Candle Set", "stock" => 0},
                %{"name" => "Canvas Tote Bag", "stock" => 3},
                %{"name" => "Oak Serving Board", "stock" => 2}
              ]
            }
          }
        ]
      }
    }
  end

  defp contains_any(str, keywords) do
    Enum.any?(keywords, &String.contains?(str, &1))
  end

  defp chunk_text(text) do
    # Split into ~5 char chunks for streaming effect
    text
    |> String.graphemes()
    |> Enum.chunk_every(5)
    |> Enum.map(&Enum.join/1)
  end

  defp broadcast_activity(session_id, event) do
    PubSub.broadcast(@pubsub, "quecto:#{session_id}:activity", {:activity, event})
  end

  defp current_time do
    DateTime.utc_now() |> Calendar.strftime("%H:%M:%S")
  end
end
