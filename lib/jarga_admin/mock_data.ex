defmodule JargaAdmin.MockData do
  @moduledoc """
  Rich mock data for the generative admin UI demo.
  Mimics a real Jarga Commerce store — handmade/artisan goods.
  """

  # ── Products ──────────────────────────────────────────────────────────────

  def products do
    [
      %{
        "id" => "prod_001",
        "name" => "Leather Journal A5",
        "sku" => "LJ-A5-BRN",
        "price" => "£34.99",
        "price_raw" => 3499,
        "compare_at" => nil,
        "stock" => 40,
        "reorder_at" => 10,
        "status" => "published",
        "description" =>
          "Full-grain vegetable-tanned leather journal with 192 pages of 100gsm ivory paper. Closes with a leather strap and brass clasp. Each cover develops a unique patina with use.",
        "weight" => "340g",
        "tags" => ["stationery", "leather", "journal", "bestseller"],
        "revenue_30d" => "£1,259.64",
        "units_sold_30d" => 36,
        "variants" => [
          %{"name" => "Brown", "sku" => "LJ-A5-BRN", "stock" => 24},
          %{"name" => "Tan", "sku" => "LJ-A5-TAN", "stock" => 12},
          %{"name" => "Black", "sku" => "LJ-A5-BLK", "stock" => 4}
        ]
      },
      %{
        "id" => "prod_002",
        "name" => "Canvas Tote Bag",
        "sku" => "CTB-NAT-001",
        "price" => "£24.99",
        "price_raw" => 2499,
        "compare_at" => "£34.99",
        "stock" => 3,
        "reorder_at" => 20,
        "status" => "published",
        "description" =>
          "Heavy-duty 12oz natural canvas tote. Reinforced handles, internal zip pocket. Printed with water-based inks. Machine washable at 30°.",
        "weight" => "280g",
        "tags" => ["bags", "canvas", "sustainable", "low-stock"],
        "revenue_30d" => "£374.85",
        "units_sold_30d" => 15,
        "variants" => [
          %{"name" => "Natural", "sku" => "CTB-NAT-001", "stock" => 3}
        ]
      },
      %{
        "id" => "prod_003",
        "name" => "Ceramic Mug — Slate",
        "sku" => "MUG-SL-001",
        "price" => "£18.00",
        "price_raw" => 1800,
        "compare_at" => nil,
        "stock" => 120,
        "reorder_at" => 30,
        "status" => "published",
        "description" =>
          "Wheel-thrown stoneware mug with a slate grey glaze and matte exterior. 350ml capacity. Dishwasher safe. Each piece varies slightly — handmade in Sheffield.",
        "weight" => "320g",
        "tags" => ["ceramics", "kitchen", "handmade"],
        "revenue_30d" => "£918.00",
        "units_sold_30d" => 51,
        "variants" => [
          %{"name" => "Slate", "sku" => "MUG-SL-001", "stock" => 60},
          %{"name" => "Chalk", "sku" => "MUG-CH-001", "stock" => 38},
          %{"name" => "Terracotta", "sku" => "MUG-TC-001", "stock" => 22}
        ]
      },
      %{
        "id" => "prod_004",
        "name" => "Oak Serving Board",
        "sku" => "OSB-LRG-001",
        "price" => "£42.00",
        "price_raw" => 4200,
        "compare_at" => nil,
        "stock" => 2,
        "reorder_at" => 8,
        "status" => "published",
        "description" =>
          "Solid English oak serving board with juice groove. Oiled with food-safe linseed. 40cm × 25cm × 2cm. Ideal for cheese, charcuterie, or bread.",
        "weight" => "890g",
        "tags" => ["kitchen", "oak", "serving", "low-stock"],
        "revenue_30d" => "£294.00",
        "units_sold_30d" => 7,
        "variants" => [
          %{"name" => "Large (40cm)", "sku" => "OSB-LRG-001", "stock" => 2},
          %{"name" => "Small (28cm)", "sku" => "OSB-SML-001", "stock" => 0}
        ]
      },
      %{
        "id" => "prod_005",
        "name" => "Beeswax Candle Set",
        "sku" => "BWC-SET-3",
        "price" => "£28.00",
        "price_raw" => 2800,
        "compare_at" => nil,
        "stock" => 0,
        "reorder_at" => 15,
        "status" => "draft",
        "description" =>
          "Set of three hand-poured beeswax pillar candles. Natural honey scent. Burns for 40+ hours each. Lead-free cotton wick. Wrapped in recycled kraft paper.",
        "weight" => "620g",
        "tags" => ["candles", "beeswax", "gift", "out-of-stock"],
        "revenue_30d" => "£0.00",
        "units_sold_30d" => 0,
        "variants" => [
          %{"name" => "Set of 3", "sku" => "BWC-SET-3", "stock" => 0}
        ]
      },
      %{
        "id" => "prod_006",
        "name" => "Wool Throw — Natural",
        "sku" => "WTH-NAT-001",
        "price" => "£89.00",
        "price_raw" => 8900,
        "compare_at" => nil,
        "stock" => 15,
        "reorder_at" => 5,
        "status" => "published",
        "description" =>
          "Undyed pure wool throw, woven in Wales. 150cm × 200cm. Machine washable on wool cycle. Each throw is individually numbered. Warm, heavy, and incredibly soft.",
        "weight" => "1100g",
        "tags" => ["textiles", "wool", "welsh", "premium"],
        "revenue_30d" => "£1,335.00",
        "units_sold_30d" => 15,
        "variants" => [
          %{"name" => "Natural", "sku" => "WTH-NAT-001", "stock" => 15}
        ]
      },
      %{
        "id" => "prod_007",
        "name" => "Brass Pen Set",
        "sku" => "BPS-3-001",
        "price" => "£19.99",
        "price_raw" => 1999,
        "compare_at" => "£24.99",
        "stock" => 67,
        "reorder_at" => 20,
        "status" => "published",
        "description" =>
          "Set of three brass-finish ballpoint pens with black ink refills. Weighted for comfortable writing. Gift-boxed. Refillable with standard Parker-style cartridges.",
        "weight" => "180g",
        "tags" => ["stationery", "brass", "pens", "gift"],
        "revenue_30d" => "£659.67",
        "units_sold_30d" => 33,
        "variants" => [
          %{"name" => "Set of 3", "sku" => "BPS-3-001", "stock" => 67}
        ]
      },
      %{
        "id" => "prod_008",
        "name" => "Linen Notebook Cover",
        "sku" => "LNC-A5-001",
        "price" => "£22.00",
        "price_raw" => 2200,
        "compare_at" => nil,
        "stock" => 8,
        "reorder_at" => 12,
        "status" => "published",
        "description" =>
          "Natural linen notebook cover, fits A5. Pen loop, card slot, and bookmark ribbon. Fits standard Leuchtturm1917 or Moleskine notebooks. Wipe clean.",
        "weight" => "95g",
        "tags" => ["stationery", "linen", "cover", "low-stock"],
        "revenue_30d" => "£352.00",
        "units_sold_30d" => 16,
        "variants" => [
          %{"name" => "Natural", "sku" => "LNC-A5-NAT", "stock" => 5},
          %{"name" => "Sage", "sku" => "LNC-A5-SGE", "stock" => 3}
        ]
      }
    ]
  end

  def product(id), do: Enum.find(products(), &(&1["id"] == id))

  # ── Orders ────────────────────────────────────────────────────────────────

  def orders do
    [
      %{
        "id" => "#1042",
        "ref" => "ord_1042",
        "customer" => "Sarah Mitchell",
        "customer_id" => "cust_001",
        "email" => "sarah.mitchell@example.com",
        "date" => "4 Mar 2026",
        "status" => "pending",
        "fulfillment" => "unfulfilled",
        "payment" => "paid",
        "subtotal" => "£77.98",
        "shipping" => "£4.95",
        "tax" => "£16.59",
        "total" => "£89.00",
        "items" => [
          %{
            "name" => "Leather Journal A5",
            "variant" => "Brown",
            "sku" => "LJ-A5-BRN",
            "qty" => 1,
            "price" => "£34.99"
          },
          %{
            "name" => "Canvas Tote Bag",
            "variant" => "Natural",
            "sku" => "CTB-NAT-001",
            "qty" => 1,
            "price" => "£24.99"
          },
          %{
            "name" => "Ceramic Mug — Slate",
            "variant" => "Slate",
            "sku" => "MUG-SL-001",
            "qty" => 1,
            "price" => "£18.00"
          }
        ],
        "address" => "14 Elm Street, Bristol, BS1 4RQ",
        "timeline" => [
          %{"event" => "Order placed", "time" => "4 Mar 2026, 09:14"},
          %{"event" => "Payment confirmed — Visa ending 4242", "time" => "4 Mar 2026, 09:14"},
          %{"event" => "Awaiting fulfilment", "time" => "4 Mar 2026, 09:15"}
        ]
      },
      %{
        "id" => "#1041",
        "ref" => "ord_1041",
        "customer" => "James Cooper",
        "customer_id" => "cust_002",
        "email" => "james.cooper@example.com",
        "date" => "3 Mar 2026",
        "status" => "fulfilled",
        "fulfillment" => "fulfilled",
        "payment" => "paid",
        "subtotal" => "£200.00",
        "shipping" => "£0.00",
        "tax" => "£34.50",
        "total" => "£234.50",
        "items" => [
          %{
            "name" => "Wool Throw — Natural",
            "variant" => "Natural",
            "sku" => "WTH-NAT-001",
            "qty" => 1,
            "price" => "£89.00"
          },
          %{
            "name" => "Oak Serving Board",
            "variant" => "Large (40cm)",
            "sku" => "OSB-LRG-001",
            "qty" => 2,
            "price" => "£84.00"
          },
          %{
            "name" => "Brass Pen Set",
            "variant" => "Set of 3",
            "sku" => "BPS-3-001",
            "qty" => 1,
            "price" => "£19.99"
          }
        ],
        "address" => "7 Harbour View, Edinburgh, EH6 6JJ",
        "timeline" => [
          %{"event" => "Order placed", "time" => "3 Mar 2026, 14:02"},
          %{
            "event" => "Payment confirmed — Mastercard ending 1234",
            "time" => "3 Mar 2026, 14:02"
          },
          %{"event" => "Order packed", "time" => "3 Mar 2026, 16:30"},
          %{"event" => "Dispatched — Royal Mail Tracked 48", "time" => "3 Mar 2026, 17:45"},
          %{"event" => "Delivered", "time" => "5 Mar 2026, 11:20"}
        ]
      },
      %{
        "id" => "#1040",
        "ref" => "ord_1040",
        "customer" => "Emma Walsh",
        "customer_id" => "cust_003",
        "email" => "emma.walsh@example.com",
        "date" => "3 Mar 2026",
        "status" => "pending",
        "fulfillment" => "unfulfilled",
        "payment" => "paid",
        "subtotal" => "£37.50",
        "shipping" => "£4.95",
        "tax" => "£7.98",
        "total" => "£45.00",
        "items" => [
          %{
            "name" => "Ceramic Mug — Slate",
            "variant" => "Chalk",
            "sku" => "MUG-CH-001",
            "qty" => 1,
            "price" => "£18.00"
          },
          %{
            "name" => "Linen Notebook Cover",
            "variant" => "Sage",
            "sku" => "LNC-A5-SGE",
            "qty" => 1,
            "price" => "£22.00"
          }
        ],
        "address" => "22 Rose Lane, Oxford, OX1 3DP",
        "timeline" => [
          %{"event" => "Order placed", "time" => "3 Mar 2026, 11:33"},
          %{"event" => "Payment confirmed — Visa ending 9012", "time" => "3 Mar 2026, 11:33"},
          %{"event" => "Awaiting fulfilment", "time" => "3 Mar 2026, 11:34"}
        ]
      },
      %{
        "id" => "#1039",
        "ref" => "ord_1039",
        "customer" => "Oliver Park",
        "customer_id" => "cust_004",
        "email" => "o.park@example.com",
        "date" => "2 Mar 2026",
        "status" => "fulfilled",
        "fulfillment" => "fulfilled",
        "payment" => "paid",
        "subtotal" => "£148.00",
        "shipping" => "£0.00",
        "tax" => "£29.60",
        "total" => "£178.00",
        "items" => [
          %{
            "name" => "Wool Throw — Natural",
            "variant" => "Natural",
            "sku" => "WTH-NAT-001",
            "qty" => 1,
            "price" => "£89.00"
          },
          %{
            "name" => "Leather Journal A5",
            "variant" => "Black",
            "sku" => "LJ-A5-BLK",
            "qty" => 1,
            "price" => "£34.99"
          },
          %{
            "name" => "Brass Pen Set",
            "variant" => "Set of 3",
            "sku" => "BPS-3-001",
            "qty" => 1,
            "price" => "£19.99"
          }
        ],
        "address" => "9 King Street, Manchester, M2 4LQ",
        "timeline" => [
          %{"event" => "Order placed", "time" => "2 Mar 2026, 18:09"},
          %{"event" => "Payment confirmed", "time" => "2 Mar 2026, 18:09"},
          %{"event" => "Packed", "time" => "3 Mar 2026, 09:15"},
          %{"event" => "Dispatched — DPD Next Day", "time" => "3 Mar 2026, 10:00"},
          %{"event" => "Delivered", "time" => "4 Mar 2026, 09:42"}
        ]
      },
      %{
        "id" => "#1038",
        "ref" => "ord_1038",
        "customer" => "Lily Chen",
        "customer_id" => "cust_005",
        "email" => "lily.chen@example.com",
        "date" => "2 Mar 2026",
        "status" => "pending",
        "fulfillment" => "unfulfilled",
        "payment" => "paid",
        "subtotal" => "£55.99",
        "shipping" => "£4.95",
        "tax" => "£11.00",
        "total" => "£67.00",
        "items" => [
          %{
            "name" => "Leather Journal A5",
            "variant" => "Tan",
            "sku" => "LJ-A5-TAN",
            "qty" => 1,
            "price" => "£34.99"
          },
          %{
            "name" => "Brass Pen Set",
            "variant" => "Set of 3",
            "sku" => "BPS-3-001",
            "qty" => 1,
            "price" => "£19.99"
          }
        ],
        "address" => "3 Canary Wharf, London, E14 5AB",
        "timeline" => [
          %{"event" => "Order placed", "time" => "2 Mar 2026, 08:22"},
          %{"event" => "Payment confirmed — Amex ending 0005", "time" => "2 Mar 2026, 08:22"},
          %{"event" => "Awaiting fulfilment", "time" => "2 Mar 2026, 08:23"}
        ]
      },
      %{
        "id" => "#1037",
        "ref" => "ord_1037",
        "customer" => "Tom Hassan",
        "customer_id" => "cust_002",
        "email" => "t.hassan@example.com",
        "date" => "1 Mar 2026",
        "status" => "refunded",
        "fulfillment" => "fulfilled",
        "payment" => "refunded",
        "subtotal" => "£42.00",
        "shipping" => "£4.95",
        "tax" => "£9.39",
        "total" => "£42.00",
        "items" => [
          %{
            "name" => "Oak Serving Board",
            "variant" => "Large (40cm)",
            "sku" => "OSB-LRG-001",
            "qty" => 1,
            "price" => "£42.00"
          }
        ],
        "address" => "18 Park Avenue, Leeds, LS1 3DL",
        "timeline" => [
          %{"event" => "Order placed", "time" => "1 Mar 2026, 13:00"},
          %{"event" => "Payment confirmed", "time" => "1 Mar 2026, 13:00"},
          %{"event" => "Dispatched", "time" => "2 Mar 2026, 10:30"},
          %{"event" => "Delivered", "time" => "3 Mar 2026, 14:00"},
          %{"event" => "Return requested — damaged in transit", "time" => "3 Mar 2026, 18:45"},
          %{"event" => "Refund issued — £42.00", "time" => "4 Mar 2026, 09:00"}
        ]
      },
      %{
        "id" => "#1036",
        "ref" => "ord_1036",
        "customer" => "Priya Nair",
        "customer_id" => "cust_006",
        "email" => "priya.nair@example.com",
        "date" => "28 Feb 2026",
        "status" => "fulfilled",
        "fulfillment" => "fulfilled",
        "payment" => "paid",
        "subtotal" => "£106.99",
        "shipping" => "£0.00",
        "tax" => "£21.40",
        "total" => "£128.00",
        "items" => [
          %{
            "name" => "Leather Journal A5",
            "variant" => "Brown",
            "sku" => "LJ-A5-BRN",
            "qty" => 1,
            "price" => "£34.99"
          },
          %{
            "name" => "Ceramic Mug — Slate",
            "variant" => "Terracotta",
            "sku" => "MUG-TC-001",
            "qty" => 2,
            "price" => "£36.00"
          },
          %{
            "name" => "Linen Notebook Cover",
            "variant" => "Natural",
            "sku" => "LNC-A5-NAT",
            "qty" => 1,
            "price" => "£22.00"
          }
        ],
        "address" => "55 Victoria Road, Birmingham, B16 9LA",
        "timeline" => [
          %{"event" => "Order placed", "time" => "28 Feb 2026, 20:14"},
          %{"event" => "Payment confirmed", "time" => "28 Feb 2026, 20:14"},
          %{"event" => "Packed", "time" => "1 Mar 2026, 11:00"},
          %{"event" => "Dispatched — Royal Mail Tracked 24", "time" => "1 Mar 2026, 11:30"},
          %{"event" => "Delivered", "time" => "2 Mar 2026, 10:05"}
        ]
      },
      %{
        "id" => "#1035",
        "ref" => "ord_1035",
        "customer" => "Sarah Mitchell",
        "customer_id" => "cust_001",
        "email" => "sarah.mitchell@example.com",
        "date" => "25 Feb 2026",
        "status" => "fulfilled",
        "fulfillment" => "fulfilled",
        "payment" => "paid",
        "subtotal" => "£89.00",
        "shipping" => "£4.95",
        "tax" => "£18.80",
        "total" => "£112.00",
        "items" => [
          %{
            "name" => "Wool Throw — Natural",
            "variant" => "Natural",
            "sku" => "WTH-NAT-001",
            "qty" => 1,
            "price" => "£89.00"
          }
        ],
        "address" => "14 Elm Street, Bristol, BS1 4RQ",
        "timeline" => [
          %{"event" => "Order placed", "time" => "25 Feb 2026, 16:44"},
          %{"event" => "Payment confirmed", "time" => "25 Feb 2026, 16:44"},
          %{"event" => "Packed", "time" => "26 Feb 2026, 09:30"},
          %{"event" => "Dispatched — Royal Mail Tracked 48", "time" => "26 Feb 2026, 10:00"},
          %{"event" => "Delivered", "time" => "28 Feb 2026, 12:15"}
        ]
      }
    ]
  end

  def order(id), do: Enum.find(orders(), &(&1["id"] == id || &1["ref"] == id))

  # ── Customers ─────────────────────────────────────────────────────────────

  def customers do
    [
      %{
        "id" => "cust_001",
        "name" => "Sarah Mitchell",
        "email" => "sarah.mitchell@example.com",
        "joined" => "14 Jan 2026",
        "ltv" => "£340.00",
        "order_count" => 4,
        "avg_order" => "£85.00",
        "return_rate" => "0%",
        "location" => "Bristol, UK",
        "segment" => "Loyal",
        "recent_orders" => ["#1042", "#1035"]
      },
      %{
        "id" => "cust_002",
        "name" => "James Cooper",
        "email" => "james.cooper@example.com",
        "joined" => "3 Sep 2025",
        "ltv" => "£1,204.50",
        "order_count" => 9,
        "avg_order" => "£133.83",
        "return_rate" => "0%",
        "location" => "Edinburgh, UK",
        "segment" => "VIP",
        "recent_orders" => ["#1041", "#1037"]
      },
      %{
        "id" => "cust_003",
        "name" => "Emma Walsh",
        "email" => "emma.walsh@example.com",
        "joined" => "22 Feb 2026",
        "ltv" => "£45.00",
        "order_count" => 1,
        "avg_order" => "£45.00",
        "return_rate" => "0%",
        "location" => "Oxford, UK",
        "segment" => "New",
        "recent_orders" => ["#1040"]
      },
      %{
        "id" => "cust_004",
        "name" => "Oliver Park",
        "email" => "o.park@example.com",
        "joined" => "8 Nov 2025",
        "ltv" => "£612.00",
        "order_count" => 5,
        "avg_order" => "£122.40",
        "return_rate" => "0%",
        "location" => "Manchester, UK",
        "segment" => "Loyal",
        "recent_orders" => ["#1039"]
      },
      %{
        "id" => "cust_005",
        "name" => "Lily Chen",
        "email" => "lily.chen@example.com",
        "joined" => "19 Jan 2026",
        "ltv" => "£189.00",
        "order_count" => 3,
        "avg_order" => "£63.00",
        "return_rate" => "0%",
        "location" => "London, UK",
        "segment" => "Regular",
        "recent_orders" => ["#1038"]
      },
      %{
        "id" => "cust_006",
        "name" => "Priya Nair",
        "email" => "priya.nair@example.com",
        "joined" => "1 Feb 2026",
        "ltv" => "£256.00",
        "order_count" => 2,
        "avg_order" => "£128.00",
        "return_rate" => "0%",
        "location" => "Birmingham, UK",
        "segment" => "Regular",
        "recent_orders" => ["#1036"]
      }
    ]
  end

  def customer(id), do: Enum.find(customers(), &(&1["id"] == id))

  # ── Promotions ────────────────────────────────────────────────────────────

  def promotions do
    [
      %{
        "id" => "promo_001",
        "code" => "SUMMER20",
        "description" => "20% off sitewide",
        "type" => "percentage",
        "value" => "20%",
        "uses" => 145,
        "max_uses" => nil,
        "revenue_impact" => "£1,204.40",
        "expires" => "30 Jun 2026",
        "status" => "active",
        "conditions" => "No minimum order"
      },
      %{
        "id" => "promo_002",
        "code" => "WELCOME10",
        "description" => "£10 off first order",
        "type" => "fixed",
        "value" => "£10",
        "uses" => 892,
        "max_uses" => nil,
        "revenue_impact" => "£8,920.00",
        "expires" => nil,
        "status" => "active",
        "conditions" => "First order only, min. £30"
      },
      %{
        "id" => "promo_003",
        "code" => "FLASH50",
        "description" => "50% off sale items",
        "type" => "percentage",
        "value" => "50%",
        "uses" => 0,
        "max_uses" => 100,
        "revenue_impact" => "£0",
        "expires" => "31 Jan 2026",
        "status" => "expired",
        "conditions" => "Sale items only"
      }
    ]
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  def initials(name) do
    name
    |> String.split()
    |> Enum.map(&String.first/1)
    |> Enum.take(2)
    |> Enum.join()
    |> String.upcase()
  end

  def stock_pct(stock, reorder_at) when reorder_at > 0 do
    min(round(stock / (reorder_at * 3) * 100), 100)
  end

  def stock_pct(_, _), do: 100

  def stock_class(stock, _reorder_at) when stock == 0, do: "low"
  def stock_class(stock, reorder_at) when stock <= reorder_at, do: "low"
  def stock_class(_, _), do: "ok"

  def status_badge("published"), do: {"Published", "j-badge-green"}
  def status_badge("active"), do: {"Active", "j-badge-green"}
  def status_badge("fulfilled"), do: {"Fulfilled", "j-badge-green"}
  def status_badge("pending"), do: {"Pending", "j-badge-amber"}
  def status_badge("draft"), do: {"Draft", "j-badge-muted"}
  def status_badge("unfulfilled"), do: {"Unfulfilled", "j-badge-amber"}
  def status_badge("refunded"), do: {"Refunded", "j-badge-red"}
  def status_badge("expired"), do: {"Expired", "j-badge-muted"}
  def status_badge("out_of_stock"), do: {"Out of stock", "j-badge-red"}
  def status_badge(s), do: {String.capitalize(s || ""), "j-badge-muted"}
end
