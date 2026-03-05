defmodule Mix.Tasks.Jarga.Seed do
  @moduledoc """
  Seed the local Jarga Commerce database with rich demo data.

  Calls the live REST API (not SQL directly) so all business rules,
  validations and event hooks fire exactly as they would in production.

  ## Usage

      # Full seed (wipes existing data first)
      mix jarga.seed

      # Append only — skip wipe, useful for adding more data
      mix jarga.seed --no-reset

  ## Prerequisites

      export JARGA_API_URL=http://localhost:8080
      export JARGA_API_KEY=dev

  The backend must be running:

      cd ~/Documents/github/jarga-commerce/platform
      DATABASE_URL="postgres://jarga:jarga@localhost:5432/jarga_dev" \\
      JARGA_BOOTSTRAP_KEY="dev" \\
      cargo run --bin commerce-api
  """

  use Mix.Task

  @shortdoc "Seed the local Jarga Commerce database with demo data"

  @base_url System.get_env("JARGA_API_URL", "http://localhost:8080")
  @api_key System.get_env("JARGA_API_KEY", "dev")

  # ── Entry point ────────────────────────────────────────────────────────────

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:req)
    Application.ensure_all_started(:jason)

    reset? = "--no-reset" not in args

    log(:info, "Jarga Commerce — demo seed")
    log(:info, "API: #{@base_url}  key: #{@api_key}")
    log(:info, "")

    check_backend!()

    if reset? do
      log(:step, "Resetting database...")
      reset_database()
      log(:info, "  Waiting for backend to reconnect after reset...")
      wait_for_backend()
    end

    log(:step, "Seeding categories...")
    categories = seed_categories()

    log(:step, "Seeding products...")
    products = seed_products(categories)

    log(:step, "Publishing products...")
    publish_products(products)

    log(:step, "Seeding customers...")
    customers = seed_customers()

    log(:step, "Seeding promotions...")
    {campaigns, coupons} = seed_promotions()

    log(:step, "Seeding shipping zones...")
    seed_shipping()

    log(
      :step,
      "Seeding orders (direct SQL — preserves varied financial/fulfillment statuses for realistic demo data)..."
    )

    db_url = System.get_env("DATABASE_URL", "postgres://jarga:jarga@localhost:5432/jarga_dev")
    seed_orders(products, customers, db_url)

    log(:info, "")
    log(:ok, "Seed complete.")
    log(:info, "  #{length(products)} products")
    log(:info, "  #{length(customers)} customers")
    log(:info, "  #{length(campaigns)} promotions  (#{length(coupons)} coupons)")
    log(:info, "  500 orders across multiple statuses (18 months of history)")
    log(:info, "")
    log(:info, "Re-seed any time:  mix jarga.seed")
  end

  # ── Reset ──────────────────────────────────────────────────────────────────

  defp reset_database do
    db_url = System.get_env("DATABASE_URL", "postgres://jarga:jarga@localhost:5432/jarga_dev")

    # Single SQL statement — TRUNCATE with CASCADE handles all FK deps in one shot.
    # We use psql (already on PATH) to avoid OTP supervision complexity in a Mix task.
    sql = """
    TRUNCATE
      oms_refunds, oms_return_lines, oms_returns,
      oms_fulfillment_lines, oms_fulfillments, oms_order_lines, oms_orders,
      baskets, checkout_sessions,
      crm_addresses, crm_customers,
      promotion_coupons, promotion_campaigns_v2, promotion_campaigns,
      shipping_rates, shipping_zones,
      pim_variant_option_values, pim_option_values, pim_options,
      pim_variants, pim_media, pim_collection_products, pim_collections,
      pim_products, pim_categories
    CASCADE;
    ALTER SEQUENCE oms_order_number_seq RESTART WITH 1001;
    """

    case System.cmd("psql", [db_url, "-c", sql], stderr_to_stdout: true) do
      {_out, 0} -> log(:ok, "  Database reset complete")
      {out, code} -> log(:warn, "  Reset warning (exit #{code}): #{String.slice(out, 0, 200)}")
    end
  end

  # ── Backend health check ───────────────────────────────────────────────────

  defp wait_for_backend(attempts \\ 10) do
    url = @base_url <> "/v1/pim/products"

    Enum.reduce_while(1..attempts, :not_ready, fn attempt, _acc ->
      Process.sleep(800)

      case Req.get(url,
             headers: [{"authorization", "Bearer #{@api_key}"}],
             retry: false,
             receive_timeout: 3_000
           ) do
        {:ok, %{status: s}} when s in 200..299 ->
          log(:ok, "  Backend ready (attempt #{attempt})")
          {:halt, :ready}

        _ ->
          log(:info, "  Waiting... (#{attempt}/#{attempts})")
          {:cont, :not_ready}
      end
    end)
  end

  defp check_backend!(attempts \\ 5) do
    url = @base_url <> "/v1/pim/products"

    result =
      Enum.reduce_while(1..attempts, :error, fn attempt, _acc ->
        if attempt > 1, do: Process.sleep(600)

        case Req.get(url,
               headers: [{"authorization", "Bearer #{@api_key}"}],
               retry: false,
               receive_timeout: 5_000
             ) do
          {:ok, %{status: s}} when s in 200..299 ->
            {:halt, :ok}

          {:ok, %{status: s}} ->
            Mix.raise("Backend returned HTTP #{s} — is JARGA_BOOTSTRAP_KEY=dev set?")

          {:error, %Req.TransportError{reason: :closed}} ->
            # Backend closed idle connection — retry
            {:cont, :error}

          {:error, reason} ->
            Mix.raise("""
            Cannot reach backend at #{@base_url}: #{inspect(reason)}

            Start it first:
              cd ~/Documents/github/jarga-commerce/platform
              DATABASE_URL="postgres://jarga:jarga@localhost:5432/jarga_dev" \\
              JARGA_BOOTSTRAP_KEY="dev" \\
              cargo run --bin commerce-api
            """)
        end
      end)

    case result do
      :ok -> log(:ok, "Backend is up (#{@base_url})")
      :error -> Mix.raise("Backend at #{@base_url} not responding after #{attempts} attempts")
    end
  end

  # ── Categories ─────────────────────────────────────────────────────────────

  defp seed_categories do
    categories = [
      %{
        name: "Stationery",
        slug: "stationery",
        description: "Journals, notebooks and writing tools"
      },
      %{
        name: "Bags & Accessories",
        slug: "bags-accessories",
        description: "Handcrafted leather and canvas bags"
      },
      %{
        name: "Home & Living",
        slug: "home-living",
        description: "Ceramics, candles and home décor"
      },
      %{name: "Apparel", slug: "apparel", description: "Sustainably made clothing and knitwear"},
      %{name: "Wellness", slug: "wellness", description: "Natural soaps, balms and wellbeing"},
      %{name: "Gifts", slug: "gifts", description: "Curated gift sets and bundles"}
    ]

    Enum.map(categories, fn cat ->
      case post("/v1/pim/categories", cat) do
        {:ok, %{"data" => %{"id" => id}}} ->
          log(:ok, "  Category: #{cat.name} (#{id})")
          Map.put(cat, :id, id)

        {:error, reason} ->
          log(:warn, "  Category #{cat.name} skipped: #{inspect(reason)}")
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # ── Products ───────────────────────────────────────────────────────────────

  defp seed_products(categories) do
    cat = fn slug -> Enum.find_value(categories, fn c -> if c.slug == slug, do: c.id end) end

    products = [
      # ── Stationery ──────────────────────────────────────────────────────
      %{
        product: %{
          title: "Leather Journal A5",
          slug: "leather-journal-a5",
          vendor: "Jarga Atelier",
          product_type: "Stationery",
          description_html:
            "<p>Full-grain vegetable-tanned leather journal with 192 pages of 100gsm ivory paper. Closes with a leather strap and brass clasp. Each cover develops a unique patina over time.</p>",
          tags: ["leather", "journal", "stationery", "bestseller"],
          material: "Full-grain vegetable-tanned leather",
          origin: "Made in England",
          category_id: cat.("stationery")
        },
        variants: [
          %{
            title: "Brown / A5",
            sku: "LJ-A5-BRN",
            currency: "GBP",
            unit_amount: 3499,
            inventory_qty: 48,
            weight: 340,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Tan / A5",
            sku: "LJ-A5-TAN",
            currency: "GBP",
            unit_amount: 3499,
            inventory_qty: 24,
            weight: 340,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Black / A5",
            sku: "LJ-A5-BLK",
            currency: "GBP",
            unit_amount: 3499,
            inventory_qty: 8,
            weight: 340,
            weight_unit: "g",
            position: 2
          }
        ]
      },
      %{
        product: %{
          title: "Refillable Brass Pen",
          slug: "refillable-brass-pen",
          vendor: "Jarga Atelier",
          product_type: "Stationery",
          description_html:
            "<p>Solid brass ballpoint pen with a machined grip. Takes standard Parker-compatible refills. Develops a warm patina with use — no two pens age the same way.</p>",
          tags: ["pen", "brass", "stationery", "gift"],
          material: "Solid brass",
          origin: "Made in England",
          category_id: cat.("stationery")
        },
        variants: [
          %{
            title: "Raw Brass",
            sku: "PEN-BRS-RAW",
            currency: "GBP",
            unit_amount: 4500,
            inventory_qty: 30,
            weight: 45,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Aged Copper",
            sku: "PEN-BRS-COP",
            currency: "GBP",
            unit_amount: 4800,
            inventory_qty: 15,
            weight: 45,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Blackened",
            sku: "PEN-BRS-BLK",
            currency: "GBP",
            unit_amount: 4800,
            inventory_qty: 4,
            weight: 45,
            weight_unit: "g",
            position: 2
          }
        ]
      },
      %{
        product: %{
          title: "Linen Notebook — Pocket",
          slug: "linen-notebook-pocket",
          vendor: "Jarga Atelier",
          product_type: "Stationery",
          description_html:
            "<p>Pocket-sized notebook wrapped in natural Belgian linen. 96 pages of fountain-pen-friendly 90gsm paper. Flat-opening sewn binding.</p>",
          tags: ["notebook", "linen", "stationery", "pocket"],
          material: "Belgian linen, 90gsm paper",
          origin: "Made in Belgium",
          category_id: cat.("stationery")
        },
        variants: [
          %{
            title: "Natural",
            sku: "NB-LIN-NAT",
            currency: "GBP",
            unit_amount: 1800,
            compare_at_amount: 2200,
            inventory_qty: 120,
            weight: 95,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Slate",
            sku: "NB-LIN-SLT",
            currency: "GBP",
            unit_amount: 1800,
            compare_at_amount: 2200,
            inventory_qty: 85,
            weight: 95,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Terracotta",
            sku: "NB-LIN-TRC",
            currency: "GBP",
            unit_amount: 1800,
            compare_at_amount: 2200,
            inventory_qty: 3,
            weight: 95,
            weight_unit: "g",
            position: 2
          }
        ]
      },

      # ── Bags & Accessories ───────────────────────────────────────────────
      %{
        product: %{
          title: "Canvas Tote — Natural",
          slug: "canvas-tote-natural",
          vendor: "Jarga Atelier",
          product_type: "Bag",
          description_html:
            "<p>Heavy-duty 12oz natural canvas tote. Reinforced handles, internal zip pocket. Printed with water-based inks. Machine washable at 30°.</p>",
          tags: ["tote", "canvas", "bag", "sustainable"],
          material: "12oz natural canvas",
          origin: "Made in Portugal",
          category_id: cat.("bags-accessories")
        },
        variants: [
          %{
            title: "Natural / Large",
            sku: "TOT-NAT-LG",
            currency: "GBP",
            unit_amount: 2499,
            inventory_qty: 2,
            weight: 280,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Natural / Medium",
            sku: "TOT-NAT-MD",
            currency: "GBP",
            unit_amount: 1999,
            inventory_qty: 60,
            weight: 210,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Black / Large",
            sku: "TOT-BLK-LG",
            currency: "GBP",
            unit_amount: 2499,
            inventory_qty: 38,
            weight: 280,
            weight_unit: "g",
            position: 2
          }
        ]
      },
      %{
        product: %{
          title: "Waxed Messenger Bag",
          slug: "waxed-messenger-bag",
          vendor: "Jarga Atelier",
          product_type: "Bag",
          description_html:
            "<p>Water-resistant waxed canvas messenger bag. Padded laptop sleeve fits up to 15\". Solid brass buckles, leather shoulder pad. Re-waxable for lifetime care.</p>",
          tags: ["messenger", "waxed-canvas", "bag", "laptop"],
          material: "10oz waxed canvas, full-grain leather trim",
          origin: "Made in England",
          category_id: cat.("bags-accessories")
        },
        variants: [
          %{
            title: "Olive",
            sku: "MSG-OLV-001",
            currency: "GBP",
            unit_amount: 14900,
            inventory_qty: 12,
            weight: 980,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Dark Navy",
            sku: "MSG-NVY-001",
            currency: "GBP",
            unit_amount: 14900,
            inventory_qty: 7,
            weight: 980,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Rust",
            sku: "MSG-RST-001",
            currency: "GBP",
            unit_amount: 15900,
            inventory_qty: 0,
            weight: 980,
            weight_unit: "g",
            inventory_policy: "deny",
            position: 2
          }
        ]
      },

      # ── Home & Living ────────────────────────────────────────────────────
      %{
        product: %{
          title: "Ceramic Mug — Slate",
          slug: "ceramic-mug-slate",
          vendor: "Studio Venn",
          product_type: "Ceramics",
          description_html:
            "<p>Hand-thrown stoneware mug with a natural ash glaze. 320ml capacity. Each piece is unique — slight variations in glaze and form are part of the character. Dishwasher safe.</p>",
          tags: ["mug", "ceramic", "handmade", "kitchen"],
          material: "Stoneware clay, ash glaze",
          origin: "Made in Wales",
          category_id: cat.("home-living")
        },
        variants: [
          %{
            title: "Slate / 320ml",
            sku: "MUG-SLT-320",
            currency: "GBP",
            unit_amount: 1800,
            inventory_qty: 200,
            weight: 320,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Cream / 320ml",
            sku: "MUG-CRM-320",
            currency: "GBP",
            unit_amount: 1800,
            inventory_qty: 150,
            weight: 320,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Sage / 320ml",
            sku: "MUG-SGE-320",
            currency: "GBP",
            unit_amount: 2000,
            inventory_qty: 60,
            weight: 320,
            weight_unit: "g",
            position: 2
          }
        ]
      },
      %{
        product: %{
          title: "Beeswax Pillar Candle",
          slug: "beeswax-pillar-candle",
          vendor: "Bield & Bloom",
          product_type: "Candles",
          description_html:
            "<p>100% British beeswax pillar candle. Burns for 40–50 hours with a natural honey scent. No synthetic fragrances, no paraffin. Hand-poured in small batches.</p>",
          tags: ["candle", "beeswax", "natural", "home"],
          material: "100% British beeswax",
          origin: "Made in Scotland",
          category_id: cat.("home-living")
        },
        variants: [
          %{
            title: "Small / 8cm",
            sku: "CND-BWX-SM",
            currency: "GBP",
            unit_amount: 1400,
            inventory_qty: 80,
            weight: 180,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Medium / 12cm",
            sku: "CND-BWX-MD",
            currency: "GBP",
            unit_amount: 2200,
            inventory_qty: 45,
            weight: 320,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Large / 18cm",
            sku: "CND-BWX-LG",
            currency: "GBP",
            unit_amount: 3400,
            inventory_qty: 3,
            weight: 580,
            weight_unit: "g",
            position: 2
          }
        ]
      },
      %{
        product: %{
          title: "Oak Serving Board",
          slug: "oak-serving-board",
          vendor: "Croft Workshop",
          product_type: "Kitchen",
          description_html:
            "<p>Solid English oak serving board, edge-grain construction. Oiled with food-safe Danish oil. Leather hanging loop. Each board has a unique grain pattern.</p>",
          tags: ["chopping-board", "oak", "kitchen", "gift"],
          material: "Solid English oak, Danish oil",
          origin: "Made in England",
          category_id: cat.("home-living")
        },
        variants: [
          %{
            title: "Small 25×15cm",
            sku: "BRD-OAK-SM",
            currency: "GBP",
            unit_amount: 3800,
            inventory_qty: 20,
            weight: 600,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Large 40×25cm",
            sku: "BRD-OAK-LG",
            currency: "GBP",
            unit_amount: 5800,
            inventory_qty: 8,
            weight: 1200,
            weight_unit: "g",
            position: 1
          }
        ]
      },

      # ── Apparel ──────────────────────────────────────────────────────────
      %{
        product: %{
          title: "Merino Wool Crew Knit",
          slug: "merino-wool-crew-knit",
          vendor: "Jarga Atelier",
          product_type: "Knitwear",
          description_html:
            "<p>100% extra-fine merino wool crew-neck knit. Ribbed cuffs and hem. Pre-washed for minimal shrinkage. Knitted in the Scottish Borders.</p>",
          tags: ["knitwear", "merino", "wool", "sustainable"],
          material: "100% extra-fine merino wool",
          origin: "Knitted in Scotland",
          category_id: cat.("apparel")
        },
        variants: [
          %{
            title: "Oat / S",
            sku: "KNT-MRN-OAT-S",
            currency: "GBP",
            unit_amount: 8900,
            inventory_qty: 12,
            weight: 420,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Oat / M",
            sku: "KNT-MRN-OAT-M",
            currency: "GBP",
            unit_amount: 8900,
            inventory_qty: 18,
            weight: 460,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Oat / L",
            sku: "KNT-MRN-OAT-L",
            currency: "GBP",
            unit_amount: 8900,
            inventory_qty: 9,
            weight: 490,
            weight_unit: "g",
            position: 2
          },
          %{
            title: "Slate / S",
            sku: "KNT-MRN-SLT-S",
            currency: "GBP",
            unit_amount: 8900,
            inventory_qty: 6,
            weight: 420,
            weight_unit: "g",
            position: 3
          },
          %{
            title: "Slate / M",
            sku: "KNT-MRN-SLT-M",
            currency: "GBP",
            unit_amount: 8900,
            inventory_qty: 22,
            weight: 460,
            weight_unit: "g",
            position: 4
          },
          %{
            title: "Slate / L",
            sku: "KNT-MRN-SLT-L",
            currency: "GBP",
            unit_amount: 8900,
            inventory_qty: 0,
            weight: 490,
            weight_unit: "g",
            inventory_policy: "deny",
            position: 5
          }
        ]
      },
      %{
        product: %{
          title: "Linen Shirt — Unisex",
          slug: "linen-shirt-unisex",
          vendor: "Jarga Atelier",
          product_type: "Shirts",
          description_html:
            "<p>Relaxed-fit unisex linen shirt. Pre-washed for softness. Shell buttons, single chest pocket. The more you wash it, the better it gets.</p>",
          tags: ["linen", "shirt", "unisex", "sustainable"],
          material: "100% European linen",
          origin: "Made in Portugal",
          category_id: cat.("apparel")
        },
        variants: [
          %{
            title: "Ecru / S",
            sku: "SHT-LIN-ECR-S",
            currency: "GBP",
            unit_amount: 7400,
            inventory_qty: 14,
            weight: 260,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Ecru / M",
            sku: "SHT-LIN-ECR-M",
            currency: "GBP",
            unit_amount: 7400,
            inventory_qty: 20,
            weight: 285,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Ecru / L",
            sku: "SHT-LIN-ECR-L",
            currency: "GBP",
            unit_amount: 7400,
            inventory_qty: 8,
            weight: 310,
            weight_unit: "g",
            position: 2
          },
          %{
            title: "Clay / S",
            sku: "SHT-LIN-CLY-S",
            currency: "GBP",
            unit_amount: 7400,
            inventory_qty: 2,
            weight: 260,
            weight_unit: "g",
            position: 3
          },
          %{
            title: "Clay / M",
            sku: "SHT-LIN-CLY-M",
            currency: "GBP",
            unit_amount: 7400,
            inventory_qty: 16,
            weight: 285,
            weight_unit: "g",
            position: 4
          }
        ]
      },

      # ── Wellness ─────────────────────────────────────────────────────────
      %{
        product: %{
          title: "Cold-Process Soap Bar",
          slug: "cold-process-soap-bar",
          vendor: "Bield & Bloom",
          product_type: "Skincare",
          description_html:
            "<p>Cold-process soap made with British goat milk and organic shea butter. Scented with pure essential oils. Cured for 6 weeks. Suitable for sensitive skin.</p>",
          tags: ["soap", "natural", "skincare", "vegan-option"],
          material: "Goat milk, shea butter, essential oils",
          origin: "Made in Yorkshire",
          category_id: cat.("wellness")
        },
        variants: [
          %{
            title: "Lavender & Oat",
            sku: "SOP-LAV-OAT",
            currency: "GBP",
            unit_amount: 900,
            inventory_qty: 200,
            weight: 110,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Cedarwood & Mint",
            sku: "SOP-CDR-MNT",
            currency: "GBP",
            unit_amount: 900,
            inventory_qty: 150,
            weight: 110,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Rose & Geranium",
            sku: "SOP-RSE-GER",
            currency: "GBP",
            unit_amount: 900,
            inventory_qty: 4,
            weight: 110,
            weight_unit: "g",
            position: 2
          },
          %{
            title: "Unscented / Sensitive",
            sku: "SOP-UNS-SEN",
            currency: "GBP",
            unit_amount: 850,
            inventory_qty: 180,
            weight: 110,
            weight_unit: "g",
            position: 3
          }
        ]
      },

      # ── Gifts ────────────────────────────────────────────────────────────
      %{
        product: %{
          title: "The Writer's Gift Set",
          slug: "writers-gift-set",
          vendor: "Jarga Atelier",
          product_type: "Gift Set",
          description_html:
            "<p>Leather journal (A5, brown), refillable brass pen (raw), and a pocket linen notebook (natural). Presented in a hand-stamped kraft box with tissue paper and a handwritten card.</p>",
          tags: ["gift-set", "writing", "journal", "pen", "bestseller"],
          material: "Leather, brass, linen",
          origin: "Made in England",
          category_id: cat.("gifts")
        },
        variants: [
          %{
            title: "Default",
            sku: "GFT-WRT-001",
            currency: "GBP",
            unit_amount: 8900,
            compare_at_amount: 9800,
            inventory_qty: 15,
            weight: 480,
            weight_unit: "g",
            position: 0
          }
        ]
      },
      %{
        product: %{
          title: "The Home Comfort Set",
          slug: "home-comfort-set",
          vendor: "Jarga Atelier",
          product_type: "Gift Set",
          description_html:
            "<p>Beeswax pillar candle (medium), slate ceramic mug, and lavender & oat soap. Wrapped in reusable linen and tied with jute twine.</p>",
          tags: ["gift-set", "home", "candle", "mug", "soap"],
          material: "Beeswax, stoneware, goat milk soap",
          origin: "Made in Britain",
          category_id: cat.("gifts")
        },
        variants: [
          %{
            title: "Default",
            sku: "GFT-HMC-001",
            currency: "GBP",
            unit_amount: 5600,
            compare_at_amount: 6200,
            inventory_qty: 22,
            weight: 820,
            weight_unit: "g",
            position: 0
          }
        ]
      },

      # ── Extended Stationery ──────────────────────────────────────────────
      %{
        product: %{
          title: "Copper Ruler",
          slug: "copper-ruler-30cm",
          vendor: "Jarga Atelier",
          product_type: "Stationery",
          description_html:
            "<p>Solid copper ruler, 30cm. Laser-etched millimetre markings. Develops a patina over time. Magnetic cork backing to prevent sliding on paper.</p>",
          tags: ["ruler", "copper", "stationery", "desk"],
          material: "Solid copper",
          origin: "Made in England",
          category_id: cat.("stationery")
        },
        variants: [
          %{
            title: "30cm",
            sku: "RUL-COP-30",
            currency: "GBP",
            unit_amount: 2800,
            inventory_qty: 40,
            weight: 180,
            weight_unit: "g",
            position: 0
          }
        ]
      },
      %{
        product: %{
          title: "Fountain Pen Ink — 50ml",
          slug: "fountain-pen-ink-50ml",
          vendor: "Scriptor Inks",
          product_type: "Stationery",
          description_html:
            "<p>Water-based iron gall ink in 50ml glass bottles. Four archival shades. pH-neutral, fade-resistant. Works with all fountain pens.</p>",
          tags: ["ink", "fountain-pen", "stationery", "writing"],
          material: "Iron gall, water-based",
          origin: "Made in Germany",
          category_id: cat.("stationery")
        },
        variants: [
          %{
            title: "Oxford Black",
            sku: "INK-OXB-50",
            currency: "GBP",
            unit_amount: 1400,
            inventory_qty: 60,
            weight: 120,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Forest Green",
            sku: "INK-FGR-50",
            currency: "GBP",
            unit_amount: 1400,
            inventory_qty: 45,
            weight: 120,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Midnight Blue",
            sku: "INK-MNB-50",
            currency: "GBP",
            unit_amount: 1400,
            inventory_qty: 38,
            weight: 120,
            weight_unit: "g",
            position: 2
          },
          %{
            title: "Sepia",
            sku: "INK-SEP-50",
            currency: "GBP",
            unit_amount: 1400,
            inventory_qty: 5,
            weight: 120,
            weight_unit: "g",
            position: 3
          }
        ]
      },
      %{
        product: %{
          title: "Washi Tape Set — Botanical",
          slug: "washi-tape-botanical",
          vendor: "Studio Flora",
          product_type: "Stationery",
          description_html:
            "<p>Set of 6 botanical washi tapes. Rice paper with water-based inks. Repositionable, tear-by-hand. Each roll is 15mm x 10m.</p>",
          tags: ["washi", "tape", "stationery", "journaling"],
          material: "Japanese rice paper",
          origin: "Made in Japan",
          category_id: cat.("stationery")
        },
        variants: [
          %{
            title: "Set of 6",
            sku: "WSH-BOT-6PK",
            currency: "GBP",
            unit_amount: 1600,
            inventory_qty: 80,
            weight: 95,
            weight_unit: "g",
            position: 0
          }
        ]
      },
      %{
        product: %{
          title: "Leather Pencil Roll",
          slug: "leather-pencil-roll",
          vendor: "Jarga Atelier",
          product_type: "Stationery",
          description_html:
            "<p>Holds 16 pencils or pens. Full-grain vegetable-tanned leather with waxed thread stitching. Rolls up and ties with a leather cord.</p>",
          tags: ["pencil-roll", "leather", "stationery", "artist"],
          material: "Full-grain vegetable-tanned leather",
          origin: "Made in England",
          category_id: cat.("stationery")
        },
        variants: [
          %{
            title: "Brown",
            sku: "PCL-ROL-BRN",
            currency: "GBP",
            unit_amount: 5500,
            inventory_qty: 18,
            weight: 200,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Black",
            sku: "PCL-ROL-BLK",
            currency: "GBP",
            unit_amount: 5500,
            inventory_qty: 10,
            weight: 200,
            weight_unit: "g",
            position: 1
          }
        ]
      },

      # ── Extended Bags & Accessories ───────────────────────────────────────
      %{
        product: %{
          title: "Leather Bifold Wallet",
          slug: "leather-bifold-wallet",
          vendor: "Jarga Atelier",
          product_type: "Accessories",
          description_html:
            "<p>Slim bifold wallet in full-grain vegetable-tanned leather. 6 card slots, 2 bill compartments. Stitched with waxed Irish linen thread.</p>",
          tags: ["wallet", "leather", "accessories", "gift"],
          material: "Full-grain vegetable-tanned leather",
          origin: "Made in England",
          category_id: cat.("bags-accessories")
        },
        variants: [
          %{
            title: "Tan",
            sku: "WLT-BIF-TAN",
            currency: "GBP",
            unit_amount: 4900,
            inventory_qty: 30,
            weight: 60,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Brown",
            sku: "WLT-BIF-BRN",
            currency: "GBP",
            unit_amount: 4900,
            inventory_qty: 25,
            weight: 60,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Black",
            sku: "WLT-BIF-BLK",
            currency: "GBP",
            unit_amount: 4900,
            inventory_qty: 15,
            weight: 60,
            weight_unit: "g",
            position: 2
          }
        ]
      },
      %{
        product: %{
          title: "Canvas Backpack",
          slug: "canvas-backpack-25l",
          vendor: "Jarga Atelier",
          product_type: "Bag",
          description_html:
            "<p>25L heavy-duty canvas backpack. Padded laptop sleeve, multiple organiser pockets. Solid brass hardware. Natural or Black.</p>",
          tags: ["backpack", "canvas", "bag", "laptop"],
          material: "14oz waxed canvas, full-grain leather trim",
          origin: "Made in Portugal",
          category_id: cat.("bags-accessories")
        },
        variants: [
          %{
            title: "Natural",
            sku: "BPK-CNV-NAT",
            currency: "GBP",
            unit_amount: 12900,
            inventory_qty: 14,
            weight: 1100,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Black",
            sku: "BPK-CNV-BLK",
            currency: "GBP",
            unit_amount: 12900,
            inventory_qty: 9,
            weight: 1100,
            weight_unit: "g",
            position: 1
          }
        ]
      },
      %{
        product: %{
          title: "Leather Key Fob",
          slug: "leather-key-fob",
          vendor: "Jarga Atelier",
          product_type: "Accessories",
          description_html:
            "<p>Simple, sturdy leather key fob. Hand-stitched, solid brass D-ring. Fits any key ring. Develops a beautiful patina over years of use.</p>",
          tags: ["key-fob", "leather", "accessories", "gift"],
          material: "Vegetable-tanned leather, brass",
          origin: "Made in England",
          category_id: cat.("bags-accessories")
        },
        variants: [
          %{
            title: "Tan",
            sku: "KEY-FOB-TAN",
            currency: "GBP",
            unit_amount: 1800,
            inventory_qty: 55,
            weight: 25,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Black",
            sku: "KEY-FOB-BLK",
            currency: "GBP",
            unit_amount: 1800,
            inventory_qty: 40,
            weight: 25,
            weight_unit: "g",
            position: 1
          }
        ]
      },
      %{
        product: %{
          title: "Waxed Tote — Heritage",
          slug: "waxed-tote-heritage",
          vendor: "Jarga Atelier",
          product_type: "Bag",
          description_html:
            "<p>Heavyweight waxed canvas tote with leather base and handles. Reinforced corners. Can carry up to 15kg. Gets better with every use.</p>",
          tags: ["tote", "waxed-canvas", "bag", "durable"],
          material: "14oz waxed canvas, full-grain leather",
          origin: "Made in England",
          category_id: cat.("bags-accessories")
        },
        variants: [
          %{
            title: "Olive",
            sku: "TOT-WAX-OLV",
            currency: "GBP",
            unit_amount: 5900,
            inventory_qty: 20,
            weight: 650,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Tan",
            sku: "TOT-WAX-TAN",
            currency: "GBP",
            unit_amount: 5900,
            inventory_qty: 12,
            weight: 650,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Black",
            sku: "TOT-WAX-BLK",
            currency: "GBP",
            unit_amount: 5900,
            inventory_qty: 3,
            weight: 650,
            weight_unit: "g",
            position: 2
          }
        ]
      },

      # ── Extended Home & Living ────────────────────────────────────────────
      %{
        product: %{
          title: "Linen Tea Towel Set",
          slug: "linen-tea-towel-set",
          vendor: "Loomen House",
          product_type: "Kitchen",
          description_html:
            "<p>Set of 3 heavyweight linen tea towels. Plain weave, hemstitched edges. Washed for softness. Gets more absorbent with each wash. 70x50cm each.</p>",
          tags: ["tea-towel", "linen", "kitchen", "home"],
          material: "100% European linen",
          origin: "Made in Lithuania",
          category_id: cat.("home-living")
        },
        variants: [
          %{
            title: "Natural / Set of 3",
            sku: "TTW-LIN-NAT",
            currency: "GBP",
            unit_amount: 2800,
            inventory_qty: 40,
            weight: 320,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Slate / Set of 3",
            sku: "TTW-LIN-SLT",
            currency: "GBP",
            unit_amount: 2800,
            inventory_qty: 25,
            weight: 320,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Terracotta / Set of 3",
            sku: "TTW-LIN-TRC",
            currency: "GBP",
            unit_amount: 2800,
            inventory_qty: 8,
            weight: 320,
            weight_unit: "g",
            position: 2
          }
        ]
      },
      %{
        product: %{
          title: "Stoneware Butter Dish",
          slug: "stoneware-butter-dish",
          vendor: "Studio Venn",
          product_type: "Ceramics",
          description_html:
            "<p>Hand-thrown stoneware butter dish with lid. Holds a standard 250g block of butter. Keeps butter at room temperature safely for up to a week. Dishwasher safe.</p>",
          tags: ["butter-dish", "ceramic", "kitchen", "handmade"],
          material: "Stoneware clay, ash glaze",
          origin: "Made in Wales",
          category_id: cat.("home-living")
        },
        variants: [
          %{
            title: "Cream",
            sku: "BUT-DSH-CRM",
            currency: "GBP",
            unit_amount: 2800,
            inventory_qty: 18,
            weight: 480,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Sage",
            sku: "BUT-DSH-SGE",
            currency: "GBP",
            unit_amount: 2800,
            inventory_qty: 12,
            weight: 480,
            weight_unit: "g",
            position: 1
          }
        ]
      },
      %{
        product: %{
          title: "Soy Wax Scented Candle",
          slug: "soy-wax-scented-candle",
          vendor: "Bield & Bloom",
          product_type: "Candles",
          description_html:
            "<p>100% natural soy wax candle in a reusable ceramic pot. Cotton wick. Three signature scents. Burn time 45 hours. Refillable via our workshop.</p>",
          tags: ["candle", "soy", "scented", "home"],
          material: "Natural soy wax, cotton wick",
          origin: "Made in Scotland",
          category_id: cat.("home-living")
        },
        variants: [
          %{
            title: "Larch & Vetiver",
            sku: "CND-SOY-LAR",
            currency: "GBP",
            unit_amount: 2800,
            inventory_qty: 35,
            weight: 280,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Hay & Leather",
            sku: "CND-SOY-HAY",
            currency: "GBP",
            unit_amount: 2800,
            inventory_qty: 28,
            weight: 280,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Juniper & Sea Salt",
            sku: "CND-SOY-JUN",
            currency: "GBP",
            unit_amount: 2800,
            inventory_qty: 0,
            weight: 280,
            weight_unit: "g",
            inventory_policy: "deny",
            position: 2
          }
        ]
      },
      %{
        product: %{
          title: "Walnut Serving Bowl",
          slug: "walnut-serving-bowl",
          vendor: "Croft Workshop",
          product_type: "Kitchen",
          description_html:
            "<p>Hand-turned English walnut serving bowl. Food-safe Danish oil finish. Each bowl is unique — grain patterns and size vary naturally. Approx. 30cm diameter.</p>",
          tags: ["bowl", "walnut", "kitchen", "handmade"],
          material: "English walnut, Danish oil",
          origin: "Made in England",
          category_id: cat.("home-living")
        },
        variants: [
          %{
            title: "Medium ~28cm",
            sku: "BWL-WLN-MD",
            currency: "GBP",
            unit_amount: 8900,
            inventory_qty: 6,
            weight: 800,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Large ~35cm",
            sku: "BWL-WLN-LG",
            currency: "GBP",
            unit_amount: 12900,
            inventory_qty: 3,
            weight: 1200,
            weight_unit: "g",
            position: 1
          }
        ]
      },
      %{
        product: %{
          title: "Beeswax Polish — Furniture",
          slug: "beeswax-furniture-polish",
          vendor: "Bield & Bloom",
          product_type: "Home Care",
          description_html:
            "<p>Traditional beeswax furniture polish with carnauba wax. 200ml tin. Works on wood, leather and cork. Leaves a warm, natural sheen. No silicones or petrochemicals.</p>",
          tags: ["polish", "beeswax", "furniture", "natural"],
          material: "Beeswax, carnauba wax, turpentine",
          origin: "Made in Scotland",
          category_id: cat.("home-living")
        },
        variants: [
          %{
            title: "Clear / 200ml",
            sku: "POL-BWX-CLR",
            currency: "GBP",
            unit_amount: 1400,
            inventory_qty: 65,
            weight: 280,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Dark Brown / 200ml",
            sku: "POL-BWX-DBR",
            currency: "GBP",
            unit_amount: 1400,
            inventory_qty: 40,
            weight: 280,
            weight_unit: "g",
            position: 1
          }
        ]
      },

      # ── Extended Apparel ─────────────────────────────────────────────────
      %{
        product: %{
          title: "Merino Wool Beanie",
          slug: "merino-wool-beanie",
          vendor: "Jarga Atelier",
          product_type: "Accessories",
          description_html:
            "<p>100% extra-fine merino wool beanie. Ribbed knit, cuffed brim. Machine washable at 30°. Knitted in the Scottish Borders.</p>",
          tags: ["beanie", "merino", "wool", "accessories"],
          material: "100% extra-fine merino wool",
          origin: "Knitted in Scotland",
          category_id: cat.("apparel")
        },
        variants: [
          %{
            title: "Oat",
            sku: "BNI-MRN-OAT",
            currency: "GBP",
            unit_amount: 3400,
            inventory_qty: 42,
            weight: 80,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Slate",
            sku: "BNI-MRN-SLT",
            currency: "GBP",
            unit_amount: 3400,
            inventory_qty: 35,
            weight: 80,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Midnight",
            sku: "BNI-MRN-MID",
            currency: "GBP",
            unit_amount: 3400,
            inventory_qty: 28,
            weight: 80,
            weight_unit: "g",
            position: 2
          },
          %{
            title: "Rust",
            sku: "BNI-MRN-RST",
            currency: "GBP",
            unit_amount: 3400,
            inventory_qty: 4,
            weight: 80,
            weight_unit: "g",
            position: 3
          }
        ]
      },
      %{
        product: %{
          title: "Linen Trousers — Relaxed",
          slug: "linen-trousers-relaxed",
          vendor: "Jarga Atelier",
          product_type: "Trousers",
          description_html:
            "<p>Wide-leg relaxed linen trousers. Elasticated waist, two side pockets. Pre-washed for softness. The go-to summer trouser.</p>",
          tags: ["linen", "trousers", "unisex", "sustainable"],
          material: "100% European linen",
          origin: "Made in Portugal",
          category_id: cat.("apparel")
        },
        variants: [
          %{
            title: "Ecru / S",
            sku: "TRS-LIN-ECR-S",
            currency: "GBP",
            unit_amount: 8900,
            inventory_qty: 10,
            weight: 340,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Ecru / M",
            sku: "TRS-LIN-ECR-M",
            currency: "GBP",
            unit_amount: 8900,
            inventory_qty: 16,
            weight: 360,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Ecru / L",
            sku: "TRS-LIN-ECR-L",
            currency: "GBP",
            unit_amount: 8900,
            inventory_qty: 7,
            weight: 380,
            weight_unit: "g",
            position: 2
          },
          %{
            title: "Navy / S",
            sku: "TRS-LIN-NVY-S",
            currency: "GBP",
            unit_amount: 8900,
            inventory_qty: 5,
            weight: 340,
            weight_unit: "g",
            position: 3
          },
          %{
            title: "Navy / M",
            sku: "TRS-LIN-NVY-M",
            currency: "GBP",
            unit_amount: 8900,
            inventory_qty: 12,
            weight: 360,
            weight_unit: "g",
            position: 4
          }
        ]
      },
      %{
        product: %{
          title: "Heavy Cotton Tee",
          slug: "heavy-cotton-tee",
          vendor: "Jarga Atelier",
          product_type: "T-Shirts",
          description_html:
            "<p>230gsm heavy organic cotton t-shirt. Pre-shrunk, boxy fit. Reinforced neck and shoulders. Gets better after every wash.</p>",
          tags: ["t-shirt", "cotton", "organic", "unisex"],
          material: "100% organic ring-spun cotton",
          origin: "Made in Portugal",
          category_id: cat.("apparel")
        },
        variants: [
          %{
            title: "Off-White / S",
            sku: "TEE-HVY-OWH-S",
            currency: "GBP",
            unit_amount: 4500,
            inventory_qty: 20,
            weight: 260,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Off-White / M",
            sku: "TEE-HVY-OWH-M",
            currency: "GBP",
            unit_amount: 4500,
            inventory_qty: 28,
            weight: 280,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Off-White / L",
            sku: "TEE-HVY-OWH-L",
            currency: "GBP",
            unit_amount: 4500,
            inventory_qty: 15,
            weight: 300,
            weight_unit: "g",
            position: 2
          },
          %{
            title: "Clay / M",
            sku: "TEE-HVY-CLY-M",
            currency: "GBP",
            unit_amount: 4500,
            inventory_qty: 9,
            weight: 280,
            weight_unit: "g",
            position: 3
          },
          %{
            title: "Slate / M",
            sku: "TEE-HVY-SLT-M",
            currency: "GBP",
            unit_amount: 4500,
            inventory_qty: 0,
            weight: 280,
            weight_unit: "g",
            inventory_policy: "deny",
            position: 4
          }
        ]
      },
      %{
        product: %{
          title: "Wool Scarf — Brushed",
          slug: "wool-scarf-brushed",
          vendor: "Jarga Atelier",
          product_type: "Accessories",
          description_html:
            "<p>Extra-large brushed lambswool scarf. 220 x 70cm. Fringed ends, hand-stitched. Wraps generously. Machine washable at 30°.</p>",
          tags: ["scarf", "wool", "accessories", "winter"],
          material: "100% lambswool",
          origin: "Made in Scotland",
          category_id: cat.("apparel")
        },
        variants: [
          %{
            title: "Oat",
            sku: "SCF-WOL-OAT",
            currency: "GBP",
            unit_amount: 5400,
            inventory_qty: 18,
            weight: 220,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Slate",
            sku: "SCF-WOL-SLT",
            currency: "GBP",
            unit_amount: 5400,
            inventory_qty: 22,
            weight: 220,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Terracotta",
            sku: "SCF-WOL-TRC",
            currency: "GBP",
            unit_amount: 5400,
            inventory_qty: 7,
            weight: 220,
            weight_unit: "g",
            position: 2
          }
        ]
      },

      # ── Extended Wellness ─────────────────────────────────────────────────
      %{
        product: %{
          title: "Body Oil — Natural",
          slug: "body-oil-natural",
          vendor: "Bield & Bloom",
          product_type: "Skincare",
          description_html:
            "<p>Lightweight body oil with jojoba, sweet almond and rosehip oils. Three scent variants. No parabens, sulphates or mineral oils. 100ml glass bottle.</p>",
          tags: ["body-oil", "natural", "skincare", "vegan"],
          material: "Jojoba oil, sweet almond oil, rosehip oil",
          origin: "Made in Yorkshire",
          category_id: cat.("wellness")
        },
        variants: [
          %{
            title: "Lavender & Chamomile",
            sku: "OIL-BOD-LAV",
            currency: "GBP",
            unit_amount: 2400,
            inventory_qty: 45,
            weight: 130,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Rose & Frankincense",
            sku: "OIL-BOD-RSE",
            currency: "GBP",
            unit_amount: 2400,
            inventory_qty: 32,
            weight: 130,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Unscented",
            sku: "OIL-BOD-UNS",
            currency: "GBP",
            unit_amount: 2200,
            inventory_qty: 60,
            weight: 130,
            weight_unit: "g",
            position: 2
          }
        ]
      },
      %{
        product: %{
          title: "Lip Balm — Natural",
          slug: "lip-balm-natural",
          vendor: "Bield & Bloom",
          product_type: "Skincare",
          description_html:
            "<p>Beeswax and shea butter lip balm in compostable cardboard tubes. SPF 15. Four flavours. Cruelty-free. Vegan option available (carnauba wax).</p>",
          tags: ["lip-balm", "natural", "skincare", "spf"],
          material: "Beeswax, shea butter, almond oil",
          origin: "Made in Yorkshire",
          category_id: cat.("wellness")
        },
        variants: [
          %{
            title: "Unflavoured",
            sku: "LIP-BWX-UNF",
            currency: "GBP",
            unit_amount: 450,
            inventory_qty: 120,
            weight: 15,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Peppermint",
            sku: "LIP-BWX-PPM",
            currency: "GBP",
            unit_amount: 450,
            inventory_qty: 95,
            weight: 15,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Honey & Lemon",
            sku: "LIP-BWX-HNL",
            currency: "GBP",
            unit_amount: 450,
            inventory_qty: 80,
            weight: 15,
            weight_unit: "g",
            position: 2
          },
          %{
            title: "Vegan / Carnauba",
            sku: "LIP-CRN-VGN",
            currency: "GBP",
            unit_amount: 500,
            inventory_qty: 50,
            weight: 15,
            weight_unit: "g",
            position: 3
          }
        ]
      },
      %{
        product: %{
          title: "Bath Soak — Mineral",
          slug: "bath-soak-mineral",
          vendor: "Bield & Bloom",
          product_type: "Bath & Body",
          description_html:
            "<p>Dead Sea mineral bath salts with British botanicals. 400g glass jar. Three therapeutic blends. Vegan. Zero synthetic fragrances.</p>",
          tags: ["bath", "salts", "mineral", "wellness"],
          material: "Dead Sea salt, essential oils, botanicals",
          origin: "Made in Yorkshire",
          category_id: cat.("wellness")
        },
        variants: [
          %{
            title: "Lavender & Eucalyptus",
            sku: "BTH-SLT-LAV",
            currency: "GBP",
            unit_amount: 1800,
            inventory_qty: 55,
            weight: 550,
            weight_unit: "g",
            position: 0
          },
          %{
            title: "Rose & Bergamot",
            sku: "BTH-SLT-RSE",
            currency: "GBP",
            unit_amount: 1800,
            inventory_qty: 38,
            weight: 550,
            weight_unit: "g",
            position: 1
          },
          %{
            title: "Muscle Relief / Arnica",
            sku: "BTH-SLT-ARC",
            currency: "GBP",
            unit_amount: 2000,
            inventory_qty: 22,
            weight: 550,
            weight_unit: "g",
            position: 2
          }
        ]
      },
      %{
        product: %{
          title: "Beard Oil — Woodsman",
          slug: "beard-oil-woodsman",
          vendor: "Bield & Bloom",
          product_type: "Grooming",
          description_html:
            "<p>Conditioning beard oil with cedarwood, sandalwood and black pepper. 30ml amber glass bottle with dropper. Softens coarse hairs, conditions skin underneath.</p>",
          tags: ["beard-oil", "grooming", "natural", "men"],
          material: "Jojoba oil, cedarwood, sandalwood",
          origin: "Made in Yorkshire",
          category_id: cat.("wellness")
        },
        variants: [
          %{
            title: "Woodsman / 30ml",
            sku: "BRD-OIL-WDS",
            currency: "GBP",
            unit_amount: 1800,
            inventory_qty: 42,
            weight: 60,
            weight_unit: "g",
            position: 0
          }
        ]
      },

      # ── Extended Gifts ────────────────────────────────────────────────────
      %{
        product: %{
          title: "The Artist's Toolkit",
          slug: "artists-toolkit",
          vendor: "Jarga Atelier",
          product_type: "Gift Set",
          description_html:
            "<p>Copper ruler, leather pencil roll (brown), and fountain pen ink set (Oxford Black + Forest Green). Presented in a hand-stitched canvas case.</p>",
          tags: ["gift-set", "art", "stationery", "drawing"],
          material: "Copper, leather, iron gall ink",
          origin: "Made in England",
          category_id: cat.("gifts")
        },
        variants: [
          %{
            title: "Default",
            sku: "GFT-ART-001",
            currency: "GBP",
            unit_amount: 7200,
            compare_at_amount: 8100,
            inventory_qty: 10,
            weight: 600,
            weight_unit: "g",
            position: 0
          }
        ]
      },
      %{
        product: %{
          title: "The Wellness Bundle",
          slug: "wellness-bundle",
          vendor: "Bield & Bloom",
          product_type: "Gift Set",
          description_html:
            "<p>Body oil (lavender), bath soak (rose), lip balm (peppermint), and two cold-process soap bars. All in a reusable wicker basket with shredded paper.</p>",
          tags: ["gift-set", "wellness", "spa", "self-care"],
          material: "Natural ingredients",
          origin: "Made in Yorkshire",
          category_id: cat.("gifts")
        },
        variants: [
          %{
            title: "Default",
            sku: "GFT-WEL-001",
            currency: "GBP",
            unit_amount: 7500,
            compare_at_amount: 9100,
            inventory_qty: 12,
            weight: 900,
            weight_unit: "g",
            position: 0
          }
        ]
      },
      %{
        product: %{
          title: "The Traveller's Set",
          slug: "travellers-set",
          vendor: "Jarga Atelier",
          product_type: "Gift Set",
          description_html:
            "<p>Waxed tote (olive), leather key fob (tan), and a linen notebook (natural). Everything a traveller needs, nothing they don't.</p>",
          tags: ["gift-set", "travel", "leather", "linen"],
          material: "Waxed canvas, leather, linen",
          origin: "Made in England",
          category_id: cat.("gifts")
        },
        variants: [
          %{
            title: "Default",
            sku: "GFT-TRV-001",
            currency: "GBP",
            unit_amount: 8900,
            compare_at_amount: 10200,
            inventory_qty: 8,
            weight: 780,
            weight_unit: "g",
            position: 0
          }
        ]
      },
      %{
        product: %{
          title: "The Desk Essentials Set",
          slug: "desk-essentials-set",
          vendor: "Jarga Atelier",
          product_type: "Gift Set",
          description_html:
            "<p>Leather journal (A5, tan), copper ruler, and fountain pen ink (midnight blue). The perfect desk trio for writers, architects and designers.</p>",
          tags: ["gift-set", "desk", "stationery", "office"],
          material: "Leather, copper, iron gall ink",
          origin: "Made in England",
          category_id: cat.("gifts")
        },
        variants: [
          %{
            title: "Default",
            sku: "GFT-DSK-001",
            currency: "GBP",
            unit_amount: 7800,
            compare_at_amount: 9100,
            inventory_qty: 14,
            weight: 600,
            weight_unit: "g",
            position: 0
          }
        ]
      }
    ]

    Enum.map(products, fn %{product: prod, variants: vars} ->
      case post("/v1/pim/products", prod) do
        {:ok, %{"data" => %{"id" => pid}}} ->
          log(:ok, "  Product: #{prod.title} (#{pid})")

          # Use concurrent variant creation — max_concurrency 3 avoids overwhelming
          # the backend connection pool while still being ~3x faster than sequential.
          variant_ids =
            vars
            |> Task.async_stream(
              fn var ->
                var_with_policy = Map.put_new(var, :inventory_policy, "deny")

                case post("/v1/pim/products/#{pid}/variants", var_with_policy) do
                  {:ok, %{"data" => %{"id" => vid}}} ->
                    log(:ok, "    Variant: #{var.title} (#{vid})")
                    %{id: vid, title: var.title, sku: var.sku, unit_amount: var.unit_amount}

                  {:error, reason} ->
                    log(:warn, "    Variant #{var.title} failed: #{inspect(reason)}")
                    nil
                end
              end,
              max_concurrency: 3,
              timeout: 15_000
            )
            |> Enum.map(fn
              {:ok, result} ->
                result

              {:exit, reason} ->
                log(:warn, "    Variant task exited: #{inspect(reason)}")
                nil
            end)
            |> Enum.reject(&is_nil/1)

          %{id: pid, title: prod.title, variants: variant_ids}

        {:error, reason} ->
          log(:warn, "  Product #{prod.title} failed: #{inspect(reason)}")
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp publish_products(products) do
    Enum.each(products, fn %{id: pid, title: title} ->
      case post("/v1/pim/products/#{pid}/publish", %{}) do
        {:ok, _} -> log(:ok, "  Published: #{title}")
        {:error, reason} -> log(:warn, "  Publish #{title} failed: #{inspect(reason)}")
      end
    end)
  end

  # ── Customers ──────────────────────────────────────────────────────────────

  defp seed_customers do
    customers = [
      %{
        customer: %{
          email: "alice.pemberton@example.com",
          first_name: "Alice",
          last_name: "Pemberton",
          phone: "+44 7700 900001",
          verified_email: true,
          note: "Prefers gift wrapping. VIP since 2022.",
          email_marketing_consent: %{status: "subscribed", opt_in_level: "confirmed_opt_in"}
        },
        address: %{
          first_name: "Alice",
          last_name: "Pemberton",
          address1: "14 Marlowe Street",
          city: "London",
          zip: "SE1 7PQ",
          country: "United Kingdom",
          country_code: "GB",
          default: true
        },
        tags: ["vip", "gift-buyer", "repeat-customer"]
      },
      %{
        customer: %{
          email: "ben.hargreaves@example.com",
          first_name: "Ben",
          last_name: "Hargreaves",
          phone: "+44 7700 900002",
          verified_email: true,
          email_marketing_consent: %{status: "subscribed", opt_in_level: "single_opt_in"}
        },
        address: %{
          first_name: "Ben",
          last_name: "Hargreaves",
          address1: "7 Chapel Lane",
          city: "Edinburgh",
          zip: "EH1 1JQ",
          country: "United Kingdom",
          country_code: "GB",
          default: true
        },
        tags: ["wholesale-inquiry", "stationery-buyer"]
      },
      %{
        customer: %{
          email: "cleo.martens@example.com",
          first_name: "Cleo",
          last_name: "Martens",
          phone: "+31 20 900 0003",
          verified_email: true,
          locale: "nl",
          email_marketing_consent: %{status: "subscribed", opt_in_level: "confirmed_opt_in"}
        },
        address: %{
          first_name: "Cleo",
          last_name: "Martens",
          address1: "Keizersgracht 221",
          city: "Amsterdam",
          zip: "1016 DV",
          country: "Netherlands",
          country_code: "NL",
          default: true
        },
        tags: ["eu-customer", "gift-buyer"]
      },
      %{
        customer: %{
          email: "david.okoro@example.com",
          first_name: "David",
          last_name: "Okoro",
          phone: "+44 7700 900004",
          verified_email: true,
          email_marketing_consent: %{status: "not_subscribed", opt_in_level: "single_opt_in"}
        },
        address: %{
          first_name: "David",
          last_name: "Okoro",
          address1: "32 Queen Victoria Street",
          city: "Manchester",
          zip: "M2 3AU",
          country: "United Kingdom",
          country_code: "GB",
          default: true
        },
        tags: ["repeat-customer"]
      },
      %{
        customer: %{
          email: "elena.vasquez@example.com",
          first_name: "Elena",
          last_name: "Vasquez",
          phone: "+34 91 900 0005",
          verified_email: true,
          locale: "es",
          email_marketing_consent: %{status: "subscribed", opt_in_level: "confirmed_opt_in"}
        },
        address: %{
          first_name: "Elena",
          last_name: "Vasquez",
          address1: "Calle Gran Via 45",
          city: "Madrid",
          zip: "28013",
          country: "Spain",
          country_code: "ES",
          default: true
        },
        tags: ["eu-customer", "apparel-buyer"]
      },
      %{
        customer: %{
          email: "finn.callahan@example.com",
          first_name: "Finn",
          last_name: "Callahan",
          phone: "+353 1 900 0006",
          verified_email: true,
          email_marketing_consent: %{status: "subscribed", opt_in_level: "single_opt_in"}
        },
        address: %{
          first_name: "Finn",
          last_name: "Callahan",
          address1: "18 Grafton Street",
          city: "Dublin",
          zip: "D02 XY47",
          country: "Ireland",
          country_code: "IE",
          default: true
        },
        tags: ["first-time-buyer"]
      },
      %{
        customer: %{
          email: "grace.liu@example.com",
          first_name: "Grace",
          last_name: "Liu",
          phone: "+44 7700 900007",
          verified_email: true,
          email_marketing_consent: %{status: "subscribed", opt_in_level: "confirmed_opt_in"}
        },
        address: %{
          first_name: "Grace",
          last_name: "Liu",
          address1: "5 Parkside Avenue",
          city: "Cambridge",
          zip: "CB1 1EG",
          country: "United Kingdom",
          country_code: "GB",
          default: true
        },
        tags: ["vip", "wholesale-inquiry", "home-buyer"]
      },
      %{
        customer: %{
          email: "hugo.brennan@example.com",
          first_name: "Hugo",
          last_name: "Brennan",
          phone: "+44 7700 900008",
          verified_email: false,
          email_marketing_consent: %{status: "not_subscribed", opt_in_level: "single_opt_in"}
        },
        address: %{
          first_name: "Hugo",
          last_name: "Brennan",
          address1: "23 The Shambles",
          city: "York",
          zip: "YO1 7LX",
          country: "United Kingdom",
          country_code: "GB",
          default: true
        },
        tags: []
      },
      %{
        customer: %{
          email: "isabelle.marchand@example.com",
          first_name: "Isabelle",
          last_name: "Marchand",
          phone: "+33 1 90 00 00 09",
          verified_email: true,
          locale: "fr",
          email_marketing_consent: %{status: "subscribed", opt_in_level: "confirmed_opt_in"}
        },
        address: %{
          first_name: "Isabelle",
          last_name: "Marchand",
          address1: "12 Rue du Faubourg Saint-Honoré",
          city: "Paris",
          zip: "75008",
          country: "France",
          country_code: "FR",
          default: true
        },
        tags: ["eu-customer", "vip", "gift-buyer"]
      },
      %{
        customer: %{
          email: "james.whitfield@example.com",
          first_name: "James",
          last_name: "Whitfield",
          phone: "+44 7700 900010",
          verified_email: true,
          email_marketing_consent: %{status: "subscribed", opt_in_level: "confirmed_opt_in"}
        },
        address: %{
          first_name: "James",
          last_name: "Whitfield",
          address1: "1 Royal Crescent",
          city: "Bath",
          zip: "BA1 2LR",
          country: "United Kingdom",
          country_code: "GB",
          default: true
        },
        tags: ["repeat-customer", "stationery-buyer"]
      }
      | extra_customers()
    ]

    Enum.map(customers, fn %{customer: c, address: addr, tags: tags} ->
      case post("/v1/crm/customers", c) do
        {:ok, %{"data" => %{"id" => cid}}} ->
          log(:ok, "  Customer: #{c.first_name} #{c.last_name} (#{cid})")

          # Add address
          post("/v1/crm/customers/#{cid}/addresses", addr)

          # Add tags
          Enum.each(tags, fn tag ->
            post("/v1/crm/customers/#{cid}/tags", %{tag: tag})
          end)

          Map.merge(c, %{id: cid})

        {:error, reason} ->
          log(:warn, "  Customer #{c.email} failed: #{inspect(reason)}")
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extra_customers do
    # 90 additional customers — varied UK/EU locations, marketing consent, names
    base = [
      {"kate.morrison", "Kate", "Morrison", "+44 7700 900011", "London", "W1A 1AA", "GB",
       "subscribed"},
      {"liam.oconnor", "Liam", "O'Connor", "+353 1 900 0012", "Cork", "T12 XH15", "IE",
       "subscribed"},
      {"mia.schneider", "Mia", "Schneider", "+49 30 900 0013", "Berlin", "10115", "DE",
       "subscribed"},
      {"noah.davies", "Noah", "Davies", "+44 7700 900014", "Cardiff", "CF10 1AF", "GB",
       "not_subscribed"},
      {"olivia.jensen", "Olivia", "Jensen", "+45 70 900 015", "Copenhagen", "1050", "DK",
       "subscribed"},
      {"pedro.silva", "Pedro", "Silva", "+351 21 900 0016", "Lisbon", "1100-150", "PT",
       "subscribed"},
      {"quinn.taylor", "Quinn", "Taylor", "+44 7700 900017", "Bristol", "BS1 4DJ", "GB",
       "subscribed"},
      {"rosa.ferrari", "Rosa", "Ferrari", "+39 02 900 0018", "Milan", "20121", "IT",
       "not_subscribed"},
      {"sam.brown", "Sam", "Brown", "+44 7700 900019", "Leeds", "LS1 1BA", "GB", "subscribed"},
      {"tara.patel", "Tara", "Patel", "+44 7700 900020", "Leicester", "LE1 1SH", "GB",
       "subscribed"},
      {"ulrich.bauer", "Ulrich", "Bauer", "+43 1 900 0021", "Vienna", "1010", "AT", "subscribed"},
      {"vera.novak", "Vera", "Novak", "+48 22 900 0022", "Warsaw", "00-001", "PL",
       "not_subscribed"},
      {"will.hassan", "Will", "Hassan", "+44 7700 900023", "Birmingham", "B1 1BB", "GB",
       "subscribed"},
      {"xiuying.zhang", "Xiuying", "Zhang", "+44 7700 900024", "Manchester", "M1 1AE", "GB",
       "subscribed"},
      {"yasmin.ali", "Yasmin", "Ali", "+44 7700 900025", "Liverpool", "L1 1JA", "GB",
       "subscribed"},
      {"zara.williams", "Zara", "Williams", "+44 7700 900026", "Nottingham", "NG1 1AA", "GB",
       "not_subscribed"},
      {"adam.campbell", "Adam", "Campbell", "+44 7700 900027", "Glasgow", "G1 1DD", "GB",
       "subscribed"},
      {"bella.rossi", "Bella", "Rossi", "+39 06 900 0028", "Rome", "00100", "IT", "subscribed"},
      {"carlos.garcia", "Carlos", "Garcia", "+34 91 900 0029", "Barcelona", "08001", "ES",
       "subscribed"},
      {"diana.wright", "Diana", "Wright", "+44 7700 900030", "Sheffield", "S1 1DA", "GB",
       "subscribed"},
      {"ethan.james", "Ethan", "James", "+44 7700 900031", "Southampton", "SO14 0AA", "GB",
       "not_subscribed"},
      {"fiona.miller", "Fiona", "Miller", "+44 7700 900032", "Edinburgh", "EH2 1JB", "GB",
       "subscribed"},
      {"george.clark", "George", "Clark", "+44 7700 900033", "Oxford", "OX1 1BA", "GB",
       "subscribed"},
      {"hannah.anderson", "Hannah", "Anderson", "+44 7700 900034", "Brighton", "BN1 1AA", "GB",
       "subscribed"},
      {"ivan.petrov", "Ivan", "Petrov", "+359 2 900 0035", "Sofia", "1000", "BG",
       "not_subscribed"},
      {"julia.klein", "Julia", "Klein", "+49 89 900 0036", "Munich", "80331", "DE", "subscribed"},
      {"kevin.murphy", "Kevin", "Murphy", "+353 1 900 0037", "Dublin", "D01 X2P2", "IE",
       "subscribed"},
      {"laura.thomas", "Laura", "Thomas", "+44 7700 900038", "Exeter", "EX1 1AA", "GB",
       "subscribed"},
      {"marco.de_luca", "Marco", "De Luca", "+39 11 900 0039", "Turin", "10121", "IT",
       "subscribed"},
      {"nadia.leblanc", "Nadia", "Leblanc", "+33 4 90 00 04", "Lyon", "69001", "FR",
       "not_subscribed"},
      {"oscar.holm", "Oscar", "Holm", "+46 8 900 0041", "Stockholm", "111 27", "SE",
       "subscribed"},
      {"priya.sharma", "Priya", "Sharma", "+44 7700 900042", "Coventry", "CV1 1JN", "GB",
       "subscribed"},
      {"rachel.green", "Rachel", "Green", "+44 7700 900043", "Norwich", "NR1 1EE", "GB",
       "subscribed"},
      {"stefan.wolf", "Stefan", "Wolf", "+49 40 900 0044", "Hamburg", "20095", "DE",
       "subscribed"},
      {"thea.christensen", "Thea", "Christensen", "+45 33 900 045", "Aarhus", "8000", "DK",
       "not_subscribed"},
      {"uma.patel", "Uma", "Patel", "+44 7700 900046", "Bradford", "BD1 1AA", "GB", "subscribed"},
      {"victor.dumont", "Victor", "Dumont", "+32 2 900 0047", "Brussels", "1000", "BE",
       "subscribed"},
      {"wendy.jones", "Wendy", "Jones", "+44 7700 900048", "Swansea", "SA1 1AA", "GB",
       "subscribed"},
      {"xander.berg", "Xander", "Berg", "+47 22 900 049", "Oslo", "0150", "NO", "not_subscribed"},
      {"yuki.tanaka", "Yuki", "Tanaka", "+44 7700 900050", "London", "E1 6RF", "GB",
       "subscribed"},
      {"zoe.wilson", "Zoe", "Wilson", "+44 7700 900051", "Plymouth", "PL1 1AA", "GB",
       "subscribed"},
      {"aaron.scott", "Aaron", "Scott", "+44 7700 900052", "Stoke-on-Trent", "ST1 1AA", "GB",
       "not_subscribed"},
      {"beth.turner", "Beth", "Turner", "+44 7700 900053", "Worcester", "WR1 1AA", "GB",
       "subscribed"},
      {"charlie.white", "Charlie", "White", "+44 7700 900054", "Gloucester", "GL1 1AA", "GB",
       "subscribed"},
      {"daisy.hall", "Daisy", "Hall", "+44 7700 900055", "Hereford", "HR1 1AA", "GB",
       "subscribed"},
      {"edward.king", "Edward", "King", "+44 7700 900056", "Canterbury", "CT1 2EH", "GB",
       "not_subscribed"},
      {"florence.cook", "Florence", "Cook", "+44 7700 900057", "Winchester", "SO23 9LJ", "GB",
       "subscribed"},
      {"giles.young", "Giles", "Young", "+44 7700 900058", "Chichester", "PO19 1LQ", "GB",
       "subscribed"},
      {"harriet.owen", "Harriet", "Owen", "+44 7700 900059", "Shrewsbury", "SY1 1QJ", "GB",
       "subscribed"},
      {"ian.roberts", "Ian", "Roberts", "+44 7700 900060", "Carlisle", "CA3 8JH", "GB",
       "not_subscribed"},
      {"jasmine.lewis", "Jasmine", "Lewis", "+44 7700 900061", "Chester", "CH1 1SN", "GB",
       "subscribed"},
      {"kieran.walker", "Kieran", "Walker", "+44 7700 900062", "Preston", "PR1 1HT", "GB",
       "subscribed"},
      {"lily.watson", "Lily", "Watson", "+44 7700 900063", "Blackpool", "FY1 1AA", "GB",
       "subscribed"},
      {"marcus.hill", "Marcus", "Hill", "+44 7700 900064", "Bolton", "BL1 1AA", "GB",
       "not_subscribed"},
      {"natalie.ford", "Natalie", "Ford", "+44 7700 900065", "Wigan", "WN1 1AA", "GB",
       "subscribed"},
      {"ollie.price", "Ollie", "Price", "+44 7700 900066", "Bury", "BL9 0BJ", "GB", "subscribed"},
      {"penny.gray", "Penny", "Gray", "+44 7700 900067", "Salford", "M3 6AA", "GB", "subscribed"},
      {"rupert.cox", "Rupert", "Cox", "+44 7700 900068", "Warrington", "WA1 1AA", "GB",
       "not_subscribed"},
      {"sarah.reed", "Sarah", "Reed", "+44 7700 900069", "Stockport", "SK1 1AA", "GB",
       "subscribed"},
      {"tom.hughes", "Tom", "Hughes", "+44 7700 900070", "Oldham", "OL1 1AA", "GB", "subscribed"},
      {"ursula.wood", "Ursula", "Wood", "+44 7700 900071", "Rochdale", "OL16 1AA", "GB",
       "subscribed"},
      {"vincent.morgan", "Vincent", "Morgan", "+44 7700 900072", "Huddersfield", "HD1 2AA", "GB",
       "not_subscribed"},
      {"wren.butler", "Wren", "Butler", "+44 7700 900073", "Halifax", "HX1 1AA", "GB",
       "subscribed"},
      {"xavier.bell", "Xavier", "Bell", "+44 7700 900074", "Wakefield", "WF1 1AA", "GB",
       "subscribed"},
      {"yvette.shaw", "Yvette", "Shaw", "+44 7700 900075", "Doncaster", "DN1 1AA", "GB",
       "subscribed"},
      {"zachary.ward", "Zachary", "Ward", "+44 7700 900076", "Rotherham", "S60 1AA", "GB",
       "not_subscribed"},
      {"amelia.stone", "Amelia", "Stone", "+44 7700 900077", "Hull", "HU1 1AA", "GB",
       "subscribed"},
      {"bobby.nash", "Bobby", "Nash", "+44 7700 900078", "York", "YO1 9DW", "GB", "subscribed"},
      {"chloe.fisher", "Chloe", "Fisher", "+44 7700 900079", "Scarborough", "YO11 1AA", "GB",
       "subscribed"},
      {"daniel.cooper", "Daniel", "Cooper", "+44 7700 900080", "Middlesbrough", "TS1 1AA", "GB",
       "not_subscribed"},
      {"ellie.richardson", "Ellie", "Richardson", "+44 7700 900081", "Sunderland", "SR1 1AA",
       "GB", "subscribed"},
      {"freddie.cox", "Freddie", "Cox", "+44 7700 900082", "Newcastle", "NE1 1AA", "GB",
       "subscribed"},
      {"georgia.brooks", "Georgia", "Brooks", "+44 7700 900083", "Durham", "DH1 3LE", "GB",
       "subscribed"},
      {"harry.bennett", "Harry", "Bennett", "+44 7700 900084", "Hartlepool", "TS24 7JP", "GB",
       "not_subscribed"},
      {"ivy.long", "Ivy", "Long", "+44 7700 900085", "Darlington", "DL1 1AA", "GB", "subscribed"},
      {"jack.henderson", "Jack", "Henderson", "+44 7700 900086", "Gateshead", "NE8 1AA", "GB",
       "subscribed"},
      {"katie.barker", "Katie", "Barker", "+44 7700 900087", "South Shields", "NE33 1AA", "GB",
       "subscribed"},
      {"louis.knight", "Louis", "Knight", "+44 7700 900088", "Peterborough", "PE1 1AA", "GB",
       "not_subscribed"},
      {"molly.foster", "Molly", "Foster", "+44 7700 900089", "Ipswich", "IP1 1AA", "GB",
       "subscribed"},
      {"nathan.powell", "Nathan", "Powell", "+44 7700 900090", "Colchester", "CO1 1AA", "GB",
       "subscribed"},
      {"ophelia.cole", "Ophelia", "Cole", "+44 7700 900091", "Cambridge", "CB2 1AA", "GB",
       "subscribed"},
      {"peter.simmons", "Peter", "Simmons", "+44 7700 900092", "Luton", "LU1 1AA", "GB",
       "not_subscribed"},
      {"queenie.ford", "Queenie", "Ford", "+44 7700 900093", "Milton Keynes", "MK1 1AA", "GB",
       "subscribed"},
      {"rex.grant", "Rex", "Grant", "+44 7700 900094", "Reading", "RG1 1AA", "GB", "subscribed"},
      {"stella.archer", "Stella", "Archer", "+44 7700 900095", "Guildford", "GU1 1AA", "GB",
       "subscribed"},
      {"theo.baker", "Theo", "Baker", "+44 7700 900096", "Maidstone", "ME14 1AA", "GB",
       "not_subscribed"},
      {"unity.sutton", "Unity", "Sutton", "+44 7700 900097", "Chelmsford", "CM1 1AA", "GB",
       "subscribed"},
      {"valeria.ruiz", "Valeria", "Ruiz", "+34 93 900 0098", "Seville", "41001", "ES",
       "subscribed"},
      {"w_s.black", "W.S.", "Black", "+31 20 900 0099", "Utrecht", "3512 AA", "NL", "subscribed"},
      {"xavier.dupont", "Xavier", "Dupont", "+33 3 90 00 10", "Strasbourg", "67000", "FR",
       "not_subscribed"}
    ]

    Enum.map(
      base,
      fn {email_prefix, first, last, phone, city, zip, country_code, mkt} ->
        country = country_map(country_code)

        %{
          customer: %{
            email: "#{email_prefix}@example.com",
            first_name: first,
            last_name: last,
            phone: phone,
            verified_email: true,
            email_marketing_consent: %{
              status: mkt,
              opt_in_level: if(mkt == "subscribed", do: "confirmed_opt_in", else: "single_opt_in")
            }
          },
          address: %{
            first_name: first,
            last_name: last,
            address1: "1 Main Street",
            city: city,
            zip: zip,
            country: country,
            country_code: country_code,
            default: true
          },
          tags: []
        }
      end
    )
  end

  defp country_map("GB"), do: "United Kingdom"
  defp country_map("IE"), do: "Ireland"
  defp country_map("DE"), do: "Germany"
  defp country_map("FR"), do: "France"
  defp country_map("IT"), do: "Italy"
  defp country_map("ES"), do: "Spain"
  defp country_map("NL"), do: "Netherlands"
  defp country_map("PT"), do: "Portugal"
  defp country_map("AT"), do: "Austria"
  defp country_map("BE"), do: "Belgium"
  defp country_map("DK"), do: "Denmark"
  defp country_map("SE"), do: "Sweden"
  defp country_map("PL"), do: "Poland"
  defp country_map("NO"), do: "Norway"
  defp country_map("BG"), do: "Bulgaria"
  defp country_map(_), do: "United Kingdom"

  # ── Promotions ─────────────────────────────────────────────────────────────

  defp seed_promotions do
    campaigns = [
      %{
        name: "Summer Sale — 15% off everything",
        discount_type: "percentage",
        value: 15,
        requires_code: true,
        usage_limit: 500,
        usage_limit_per_customer: 1
      },
      %{
        name: "New customer welcome — £10 off",
        discount_type: "fixed_amount",
        value: 1000,
        requires_code: true,
        usage_limit_per_customer: 1
      },
      %{
        name: "Buy 2 get 1 free — Soap",
        discount_type: "buy_x_get_y",
        buy_quantity: 2,
        get_quantity: 1,
        get_discount_percent: 100,
        requires_code: false
      },
      %{
        name: "Free shipping on orders over £75",
        discount_type: "free_shipping",
        value: 0,
        requires_code: false
      },
      %{
        name: "VIP members — 20% off",
        discount_type: "percentage",
        value: 20,
        requires_code: true,
        usage_limit: 100,
        usage_limit_per_customer: 1
      },
      %{
        name: "Winter clearance — £5 off orders over £30",
        discount_type: "fixed_amount",
        value: 500,
        requires_code: true,
        usage_limit: 200
      }
    ]

    created_campaigns =
      Enum.map(campaigns, fn camp ->
        case post("/v1/promotions/campaigns", camp) do
          {:ok, %{"data" => %{"id" => cid}}} ->
            log(:ok, "  Campaign: #{camp.name} (#{cid})")
            # Publish it
            post("/v1/promotions/campaigns/#{cid}/publish", %{})
            Map.put(camp, :id, cid)

          {:error, reason} ->
            log(:warn, "  Campaign #{camp.name} failed: #{inspect(reason)}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Generate coupons for code-required campaigns
    coupons =
      created_campaigns
      |> Enum.filter(fn c -> Map.get(c, :requires_code, false) end)
      |> Enum.flat_map(fn camp ->
        codes =
          cond do
            camp.name =~ "Summer" -> ["SUMMER15", "SAVE15NOW"]
            camp.name =~ "welcome" -> ["WELCOME10", "NEWHERE10"]
            camp.name =~ "VIP" -> ["VIP20", "MEMBERSONLY"]
            camp.name =~ "Winter" -> ["WINTER5", "CLEARANCE5"]
            true -> []
          end

        Enum.map(codes, fn code ->
          case post("/v1/promotions/coupons/generate", %{campaign_id: camp.id, code: code}) do
            {:ok, %{"data" => %{"code" => c}}} ->
              log(:ok, "    Coupon: #{c}")
              c

            {:error, reason} ->
              log(:warn, "    Coupon #{code} failed: #{inspect(reason)}")
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)
      end)

    {created_campaigns, coupons}
  end

  # ── Shipping ───────────────────────────────────────────────────────────────

  defp seed_shipping do
    zones = [
      %{
        zone: %{name: "United Kingdom", countries: ["GB"], active: true},
        rates: [
          %{
            title: "Royal Mail 2nd Class",
            rate_type: "flat_rate",
            price: 350,
            estimated_days_min: 2,
            estimated_days_max: 5,
            active: true,
            position: 0
          },
          %{
            title: "Royal Mail 1st Class",
            rate_type: "flat_rate",
            price: 550,
            estimated_days_min: 1,
            estimated_days_max: 2,
            active: true,
            position: 1
          },
          %{
            title: "DPD Next Day",
            rate_type: "flat_rate",
            price: 895,
            estimated_days_min: 1,
            estimated_days_max: 1,
            active: true,
            position: 2
          },
          %{
            title: "Free Shipping (orders over £75)",
            rate_type: "flat_rate",
            price: 0,
            free_above_order_value: 7500,
            estimated_days_min: 2,
            estimated_days_max: 5,
            active: true,
            position: 3
          }
        ]
      },
      %{
        zone: %{
          name: "Europe",
          countries: ["DE", "FR", "NL", "ES", "IT", "BE", "PT", "IE", "AT", "SE", "DK", "PL"],
          active: true
        },
        rates: [
          %{
            title: "Standard International",
            rate_type: "flat_rate",
            price: 895,
            estimated_days_min: 5,
            estimated_days_max: 10,
            active: true,
            position: 0
          },
          %{
            title: "Tracked International",
            rate_type: "flat_rate",
            price: 1295,
            estimated_days_min: 3,
            estimated_days_max: 7,
            active: true,
            position: 1
          }
        ]
      },
      %{
        zone: %{
          name: "Rest of World",
          countries: ["US", "CA", "AU", "NZ", "JP", "SG"],
          active: true
        },
        rates: [
          %{
            title: "International Standard",
            rate_type: "flat_rate",
            price: 1495,
            estimated_days_min: 7,
            estimated_days_max: 21,
            active: true,
            position: 0
          },
          %{
            title: "International Tracked",
            rate_type: "flat_rate",
            price: 1995,
            estimated_days_min: 5,
            estimated_days_max: 10,
            active: true,
            position: 1
          }
        ]
      }
    ]

    Enum.each(zones, fn %{zone: z, rates: rates} ->
      case post("/v1/shipping/zones", z) do
        {:ok, %{"data" => %{"id" => zid}}} ->
          log(:ok, "  Zone: #{z.name} (#{zid})")

          Enum.each(rates, fn rate ->
            case post("/v1/shipping/zones/#{zid}/rates", rate) do
              {:ok, _} -> log(:ok, "    Rate: #{rate.title}")
              {:error, reason} -> log(:warn, "    Rate #{rate.title} failed: #{inspect(reason)}")
            end
          end)

        {:error, reason} ->
          log(:warn, "  Zone #{z.name} failed: #{inspect(reason)}")
      end
    end)
  end

  # ── Orders ─────────────────────────────────────────────────────────────────
  # Each order goes through: create basket → add lines → create checkout → complete.
  # Financial/fulfillment status is then transitioned via the OMS API.

  # Orders are seeded via direct SQL to preserve varied financial_status and
  # fulfillment_status values (cancelled, refunded, partially_fulfilled, etc.)
  # that are not achievable via the draft-order API alone.
  #
  # The draft-order API is fully implemented at POST /v1/oms/draft-orders
  # (note: hyphen, not underscore) and could be used for simpler seed scenarios,
  # but direct SQL remains appropriate here for demo data fidelity.
  # See jargacommerce issue #175 and #189 for context.

  defp seed_orders(products, customers, db_url) do
    if customers == [] or products == [] do
      log(:warn, "  Skipping orders — no customers or products seeded")
      nil
    else
      do_seed_orders(products, customers, db_url)
    end
  end

  # ── Bulk order seeder (500 orders across 18 months) ─────────────────────────

  # All 500 orders inserted as one large batched SQL transaction for speed.
  # Each batch of ~50 is a separate psql call to avoid argument-length limits.

  @order_skus [
    {"LJ-A5-BRN", 3499},
    {"LJ-A5-TAN", 3499},
    {"LJ-A5-BLK", 3499},
    {"PEN-BRS-RAW", 4500},
    {"PEN-BRS-COP", 4800},
    {"PEN-BRS-BLK", 4800},
    {"NB-LIN-NAT", 1800},
    {"NB-LIN-SLT", 1800},
    {"NB-LIN-TRC", 1800},
    {"TOT-NAT-LG", 2499},
    {"TOT-NAT-MD", 1999},
    {"TOT-BLK-LG", 2499},
    {"MSG-OLV-001", 14900},
    {"MSG-NVY-001", 14900},
    {"MUG-SLT-320", 1800},
    {"MUG-CRM-320", 1800},
    {"MUG-SGE-320", 2000},
    {"CND-BWX-SM", 1400},
    {"CND-BWX-MD", 2200},
    {"CND-BWX-LG", 3400},
    {"BRD-OAK-SM", 3800},
    {"BRD-OAK-LG", 5800},
    {"KNT-MRN-OAT-S", 8900},
    {"KNT-MRN-OAT-M", 8900},
    {"KNT-MRN-OAT-L", 8900},
    {"KNT-MRN-SLT-M", 8900},
    {"SHT-LIN-ECR-S", 7400},
    {"SHT-LIN-ECR-M", 7400},
    {"SHT-LIN-ECR-L", 7400},
    {"SHT-LIN-CLY-M", 7400},
    {"SOP-LAV-OAT", 900},
    {"SOP-CDR-MNT", 900},
    {"SOP-RSE-GER", 900},
    {"SOP-UNS-SEN", 850},
    {"GFT-WRT-001", 8900},
    {"GFT-HMC-001", 5600},
    {"RUL-COP-30", 2800},
    {"INK-OXB-50", 1400},
    {"INK-FGR-50", 1400},
    {"WSH-BOT-6PK", 1600},
    {"PCL-ROL-BRN", 5500},
    {"WLT-BIF-TAN", 4900},
    {"WLT-BIF-BRN", 4900},
    {"BPK-CNV-NAT", 12900},
    {"KEY-FOB-TAN", 1800},
    {"TOT-WAX-OLV", 5900},
    {"TTW-LIN-NAT", 2800},
    {"BUT-DSH-CRM", 2800},
    {"CND-SOY-LAR", 2800},
    {"BWL-WLN-MD", 8900},
    {"POL-BWX-CLR", 1400},
    {"BNI-MRN-OAT", 3400},
    {"BNI-MRN-SLT", 3400},
    {"TRS-LIN-ECR-M", 8900},
    {"TEE-HVY-OWH-M", 4500},
    {"SCF-WOL-OAT", 5400},
    {"OIL-BOD-LAV", 2400},
    {"LIP-BWX-PPM", 450},
    {"BTH-SLT-LAV", 1800},
    {"BRD-OIL-WDS", 1800},
    {"GFT-ART-001", 7200},
    {"GFT-WEL-001", 7500},
    {"GFT-TRV-001", 8900},
    {"GFT-DSK-001", 7800}
  ]

  @financial_statuses [
    "paid",
    "paid",
    "paid",
    "paid",
    "paid",
    "paid",
    "paid",
    "paid",
    "partially_refunded",
    "refunded",
    "pending_payment",
    "cancelled"
  ]

  @fulfillment_statuses [
    "fulfilled",
    "fulfilled",
    "fulfilled",
    "partially_fulfilled",
    "unfulfilled",
    "unfulfilled"
  ]

  @tracking_numbers [
    "RM100000001GB",
    "RM100000002GB",
    "RM100000003GB",
    "RM100000004GB",
    "RM100000005GB",
    "DPD10000000001",
    "DPD10000000002",
    "DPD10000000003",
    "DPD10000000004",
    "DPD10000000005",
    nil
  ]

  defp do_seed_orders(products, customers, db_url) do
    flat_variants =
      Enum.flat_map(products, fn p ->
        Enum.map(p.variants, fn v -> Map.put(v, :product_title, p.title) end)
      end)

    # Build a fast lookup: sku -> variant
    variant_map =
      Map.new(flat_variants, fn v -> {v.sku, v} end)

    n_cust = length(customers)
    n_sku = length(@order_skus)
    n_fin = length(@financial_statuses)
    n_ful = length(@fulfillment_statuses)
    n_track = length(@tracking_numbers)

    total_orders = 500
    log(:info, "  Generating #{total_orders} orders in batches of 50...")

    1..total_orders
    |> Enum.chunk_every(50)
    |> Enum.each(fn batch ->
      sqls =
        Enum.map(batch, fn seq ->
          # Deterministic but varied selections via modular arithmetic
          customer = Enum.at(customers, rem(seq * 7, n_cust))
          fin_status = Enum.at(@financial_statuses, rem(seq * 3, n_fin))
          ful_status = choose_fulfillment(fin_status, seq, n_ful)
          tracking = choose_tracking(ful_status, seq, n_track)

          # 1 to 3 line items per order
          n_lines = rem(seq, 3) + 1

          lines =
            Enum.map(1..n_lines, fn li ->
              {sku, fallback_amount} = Enum.at(@order_skus, rem(seq * li * 13, n_sku))
              qty = rem(seq * li, 3) + 1

              case Map.get(variant_map, sku) do
                nil ->
                  %{
                    variant_id: "var_unknown",
                    title: sku,
                    sku: sku,
                    unit_amount: fallback_amount,
                    qty: qty
                  }

                v ->
                  %{
                    variant_id: v.id,
                    title: "#{v.product_title} — #{v.title}",
                    sku: v.sku,
                    unit_amount: v.unit_amount,
                    qty: qty
                  }
              end
            end)

          # Days ago — spread orders across 18 months (540 days)
          days_ago = rem(seq * 367, 540)

          build_order_sql(seq, customer, lines, fin_status, ful_status, tracking, days_ago)
        end)
        |> Enum.join("\n")

      case System.cmd("psql", [db_url, "-c", sqls], stderr_to_stdout: true) do
        {_out, 0} ->
          log(:ok, "  Inserted orders #{hd(batch)}-#{List.last(batch)}")

        {out, code} ->
          log(
            :warn,
            "  Batch #{hd(batch)}-#{List.last(batch)} failed (exit #{code}): #{String.slice(out, 0, 200)}"
          )
      end
    end)

    log(:ok, "  #{total_orders} orders seeded")
  end

  defp choose_fulfillment(fin_status, _seq, _n)
       when fin_status in ["refunded", "cancelled", "pending_payment"],
       do: "unfulfilled"

  defp choose_fulfillment(_fin, seq, n_ful),
    do: Enum.at(@fulfillment_statuses, rem(seq * 5, n_ful))

  defp choose_tracking(ful_status, seq, n_track)
       when ful_status in ["fulfilled", "partially_fulfilled"] do
    Enum.at(@tracking_numbers, rem(seq * 11, n_track)) ||
      Enum.at(@tracking_numbers, rem(seq * 11, n_track - 1))
  end

  defp choose_tracking(_ful, _seq, _n), do: nil

  defp build_order_sql(seq, customer, lines, fin_status, ful_status, tracking, days_ago) do
    order_id = "ord_s#{String.pad_leading("#{seq}", 4, "0")}"
    basket_id = "bsk_s#{String.pad_leading("#{seq}", 4, "0")}"
    amount = Enum.sum(Enum.map(lines, fn l -> l.unit_amount * l.qty end))

    cancel_at =
      if fin_status == "cancelled", do: "now() - interval '#{days_ago} days'", else: "NULL"

    cancel_rsn = if fin_status == "cancelled", do: "'customer'", else: "NULL"

    # NOTE: String.replace-based escaping is intentional here.
    # This seed task runs against a LOCAL dev database only, with data defined
    # in this file. It must NEVER be extended to accept untrusted user input —
    # use parameterised queries (Postgrex, Ecto) for any production code path.
    escaped_email = String.replace(customer.email || "guest@example.com", "'", "''")
    first = String.replace(customer[:first_name] || "Guest", "'", "''")
    last = String.replace(customer[:last_name] || "", "'", "''")
    cust_id = String.replace(customer.id || "", "'", "''")

    basket_sql = """
    INSERT INTO baskets (id, currency, created_at, updated_at)
    VALUES ('#{basket_id}', 'GBP',
            now() - interval '#{days_ago} days',
            now() - interval '#{days_ago} days')
    ON CONFLICT (id) DO NOTHING;
    """

    order_sql = """
    INSERT INTO oms_orders
      (id, basket_id, amount_total, currency, status, financial_status,
       fulfillment_status, customer_id, email,
       shipping_name, shipping_line1, shipping_city, shipping_zip, shipping_country,
       cancel_reason, cancelled_at, created_at, updated_at)
    VALUES (
      '#{order_id}', '#{basket_id}', #{amount}, 'GBP',
      '#{oms_status(fin_status)}',
      '#{fin_status}', '#{ful_status}',
      '#{cust_id}', '#{escaped_email}',
      '#{first} #{last}',
      '1 Demo Street', 'London', 'EC1A 1BB', 'GB',
      #{cancel_rsn}, #{cancel_at},
      now() - interval '#{days_ago} days',
      now() - interval '#{days_ago} days'
    )
    ON CONFLICT (id) DO NOTHING;
    """

    lines_sql =
      lines
      |> Enum.with_index(1)
      |> Enum.map(fn {l, i} ->
        line_id = "#{order_id}_ln#{i}"
        escaped_title = String.replace(l.title || l.sku, "'", "''")

        """
        INSERT INTO oms_order_lines
          (id, order_id, variant_id, title, sku, quantity, unit_amount, currency, fulfillable_quantity)
        VALUES ('#{line_id}', '#{order_id}', '#{l.variant_id}',
                '#{escaped_title}',
                '#{l.sku}', #{l.qty}, #{l.unit_amount}, 'GBP',
                #{if ful_status == "fulfilled", do: 0, else: l.qty})
        ON CONFLICT (id) DO NOTHING;
        """
      end)
      |> Enum.join("\n")

    refund_sql =
      case fin_status do
        "refunded" ->
          """
          INSERT INTO oms_refunds (id, order_id, amount, reason, created_at, updated_at)
          VALUES ('ref_#{order_id}', '#{order_id}', #{amount}, 'customer_request', now() - interval '#{max(0, days_ago - 3)} days', now())
          ON CONFLICT (id) DO NOTHING;
          """

        "partially_refunded" ->
          first_line = hd(lines)

          """
          INSERT INTO oms_refunds (id, order_id, amount, reason, created_at, updated_at)
          VALUES ('ref_#{order_id}', '#{order_id}', #{first_line.unit_amount}, 'not_as_described', now() - interval '#{max(0, days_ago - 2)} days', now())
          ON CONFLICT (id) DO NOTHING;
          """

        _ ->
          ""
      end

    fulfillment_sql =
      if tracking && ful_status in ["fulfilled", "partially_fulfilled"] do
        ful_id = "ful_#{order_id}"

        """
        INSERT INTO oms_fulfillments (id, order_id, tracking_number, carrier, status, created_at, updated_at)
        VALUES ('#{ful_id}', '#{order_id}', '#{tracking}', 'Royal Mail', 'shipped', now() - interval '#{max(0, days_ago - 1)} days', now())
        ON CONFLICT (id) DO NOTHING;
        """
      else
        ""
      end

    basket_sql <> order_sql <> lines_sql <> refund_sql <> fulfillment_sql
  end

  # Map financial status to the legacy oms_orders.status column
  defp oms_status("paid"), do: "paid"
  defp oms_status("pending_payment"), do: "pending_payment"
  defp oms_status("refunded"), do: "refunded"
  defp oms_status("partially_refunded"), do: "paid"
  defp oms_status("cancelled"), do: "cancelled"
  defp oms_status(_), do: "pending_payment"

  # ── HTTP helpers ───────────────────────────────────────────────────────────

  defp post(path, body, attempt \\ 1) do
    url = @base_url <> path

    case Req.post(url,
           json: body,
           headers: [
             {"authorization", "Bearer #{@api_key}"},
             {"content-type", "application/json"}
           ],
           receive_timeout: 15_000,
           retry: false
         ) do
      {:ok, %{status: status, body: resp}} when status in 200..299 ->
        {:ok, resp}

      {:ok, %{status: status, body: resp}} ->
        {:error, "HTTP #{status}: #{inspect(resp)}"}

      {:error, %Req.TransportError{reason: :closed}} when attempt < 3 ->
        # Backend closed idle connection — wait briefly and retry
        Process.sleep(300)
        post(path, body, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Logging ────────────────────────────────────────────────────────────────

  defp log(:step, msg), do: IO.puts("\n==> #{msg}")
  defp log(:ok, msg), do: IO.puts("  [+] #{msg}")
  defp log(:warn, msg), do: IO.puts("  [!] #{msg}")
  defp log(:info, msg), do: IO.puts(msg)
end
