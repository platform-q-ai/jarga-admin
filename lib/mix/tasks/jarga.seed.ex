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
      "Seeding orders (direct SQL — draft-order API not yet implemented in Postgres backend)..."
    )

    db_url = System.get_env("DATABASE_URL", "postgres://jarga:jarga@localhost:5432/jarga_dev")
    seed_orders(products, customers, db_url)

    log(:info, "")
    log(:ok, "Seed complete.")
    log(:info, "  #{length(products)} products")
    log(:info, "  #{length(customers)} customers")
    log(:info, "  #{length(campaigns)} promotions  (#{length(coupons)} coupons)")
    log(:info, "  20 orders across multiple statuses")
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
      }
    ]

    Enum.map(products, fn %{product: prod, variants: vars} ->
      case post("/v1/pim/products", prod) do
        {:ok, %{"data" => %{"id" => pid}}} ->
          log(:ok, "  Product: #{prod.title} (#{pid})")

          variant_ids =
            vars
            |> Enum.with_index()
            |> Enum.map(fn {var, _i} ->
              # Small delay to avoid overwhelming the connection pool
              Process.sleep(80)
              var_with_policy = Map.put_new(var, :inventory_policy, "deny")

              case post("/v1/pim/products/#{pid}/variants", var_with_policy) do
                {:ok, %{"data" => %{"id" => vid}}} ->
                  log(:ok, "    Variant: #{var.title} (#{vid})")
                  %{id: vid, title: var.title, sku: var.sku, unit_amount: var.unit_amount}

                {:error, reason} ->
                  log(:warn, "    Variant #{var.title} failed: #{inspect(reason)}")
                  nil
              end
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
          case camp.discount_type do
            "percentage" -> ["SUMMER15", "SAVE15NOW"]
            "fixed_amount" -> ["WELCOME10", "NEWHERE10"]
            _ -> []
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

  # Orders are seeded via direct SQL because the draft-order API is not yet
  # implemented in the Postgres backend (pg_oms_crm_frontend.rs returns Internal stub).
  # This is a dev/seed tool — direct SQL is appropriate here.
  # Once the API is implemented, switch to the draft-order flow.

  defp seed_orders(products, customers, db_url) do
    if customers == [] or products == [] do
      log(:warn, "  Skipping orders — no customers or products seeded")
      nil
    else
      do_seed_orders(products, customers, db_url)
    end
  end

  defp do_seed_orders(products, customers, db_url) do
    flat_variants =
      Enum.flat_map(products, fn p ->
        Enum.map(p.variants, fn v -> Map.put(v, :product_title, p.title) end)
      end)

    find_v = fn sku -> Enum.find(flat_variants, fn v -> v.sku == sku end) end
    n = length(customers)
    cust = fn idx -> Enum.at(customers, rem(idx, n)) end

    orders = [
      {0, [{"LJ-A5-BRN", 1}, {"PEN-BRS-RAW", 1}], "paid", "fulfilled", "RM123456785GB"},
      {1, [{"NB-LIN-NAT", 2}, {"SOP-LAV-OAT", 3}], "paid", "unfulfilled", nil},
      {2, [{"MUG-SLT-320", 2}, {"CND-BWX-MD", 1}], "paid", "partially_fulfilled",
       "RM987654321GB"},
      {3, [{"GFT-WRT-001", 1}], "pending_payment", "unfulfilled", nil},
      {4, [{"KNT-MRN-OAT-M", 1}, {"SHT-LIN-ECR-M", 1}], "paid", "fulfilled", "DPD001122334455"},
      {5, [{"MSG-OLV-001", 1}], "paid", "unfulfilled", nil},
      {6, [{"TOT-NAT-LG", 2}], "refunded", "unfulfilled", nil},
      {7, [{"GFT-HMC-001", 2}, {"SOP-RSE-GER", 4}], "paid", "fulfilled", "RM556677889GB"},
      {8, [{"LJ-A5-TAN", 3}, {"PEN-BRS-COP", 2}, {"NB-LIN-SLT", 5}], "paid", "unfulfilled", nil},
      {9, [{"BRD-OAK-LG", 1}, {"MUG-CRM-320", 4}], "paid", "fulfilled", "DPD998877665544"},
      {0, [{"CND-BWX-LG", 2}, {"SOP-CDR-MNT", 3}], "partially_refunded", "fulfilled",
       "RM112233445GB"},
      {1, [{"KNT-MRN-SLT-M", 1}], "paid", "unfulfilled", nil},
      {2, [{"SHT-LIN-CLY-M", 2}], "cancelled", "unfulfilled", nil},
      {3, [{"GFT-WRT-001", 3}, {"LJ-A5-BLK", 1}], "paid", "fulfilled", "RM667788990GB"},
      {4, [{"MUG-SGE-320", 6}, {"CND-BWX-SM", 4}], "paid", "unfulfilled", nil},
      {5, [{"TOT-NAT-MD", 1}, {"SOP-UNS-SEN", 2}], "paid", "fulfilled", "RM334455667GB"},
      {6, [{"MSG-NVY-001", 1}, {"PEN-BRS-BLK", 1}], "pending_payment", "unfulfilled", nil},
      {7, [{"BRD-OAK-SM", 2}, {"NB-LIN-NAT", 4}], "paid", "fulfilled", "DPD445566778899"},
      {8, [{"KNT-MRN-OAT-S", 1}, {"KNT-MRN-SLT-S", 1}], "paid", "unfulfilled", nil},
      {9, [{"GFT-HMC-001", 1}, {"GFT-WRT-001", 1}, {"SOP-LAV-OAT", 2}], "paid", "fulfilled",
       "RM778899001GB"}
    ]

    orders
    |> Enum.with_index(1)
    |> Enum.each(fn {{cust_idx, line_specs, fin_status, ful_status, tracking}, seq} ->
      c = cust.(cust_idx)

      lines =
        line_specs
        |> Enum.map(fn {sku, qty} ->
          case find_v.(sku) do
            nil ->
              nil

            v ->
              %{
                variant_id: v.id,
                title: "#{v.product_title} — #{v.title}",
                unit_amount: v.unit_amount,
                sku: v.sku,
                qty: qty
              }
          end
        end)
        |> Enum.reject(&is_nil/1)

      if lines == [] do
        log(:warn, "  Order #{seq}: no valid variants, skipping")
      else
        insert_order(seq, c, lines, fin_status, ful_status, tracking, db_url)
      end
    end)
  end

  defp insert_order(seq, customer, lines, fin_status, ful_status, tracking, db_url) do
    order_id = "ord_seed_#{String.pad_leading("#{seq}", 3, "0")}"
    basket_id = "bsk_seed_#{String.pad_leading("#{seq}", 3, "0")}"
    amount = Enum.sum(Enum.map(lines, fn l -> l.unit_amount * l.qty end))
    cancel_at = if fin_status == "cancelled", do: "now()", else: "NULL"
    cancel_rsn = if fin_status == "cancelled", do: "'customer'", else: "NULL"

    # Offset created_at so orders appear spread over the past 60 days
    days_ago = rem(seq * 3, 60)

    # Insert basket (required FK)
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
      '#{customer.id}', '#{customer.email}',
      '#{customer.first_name} #{customer.last_name}',
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
        line_id = "#{order_id}_line_#{i}"

        """
        INSERT INTO oms_order_lines
          (id, order_id, variant_id, title, sku, quantity, unit_amount, currency, fulfillable_quantity)
        VALUES ('#{line_id}', '#{order_id}', '#{l.variant_id}',
                '#{String.replace(l.title, "'", "''")}',
                '#{l.sku}', #{l.qty}, #{l.unit_amount}, 'GBP',
                #{if ful_status == "fulfilled", do: 0, else: l.qty})
        ON CONFLICT (id) DO NOTHING;
        """
      end)
      |> Enum.join("\n")

    refund_sql =
      case fin_status do
        "refunded" ->
          refund_amount = amount

          """
          INSERT INTO oms_refunds (id, order_id, amount, reason, created_at, updated_at)
          VALUES ('ref_#{order_id}', '#{order_id}', #{refund_amount}, 'customer_request', now(), now())
          ON CONFLICT (id) DO NOTHING;
          """

        "partially_refunded" ->
          first = hd(lines)

          """
          INSERT INTO oms_refunds (id, order_id, amount, reason, created_at, updated_at)
          VALUES ('ref_#{order_id}', '#{order_id}', #{first.unit_amount}, 'customer_request', now(), now())
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
        VALUES ('#{ful_id}', '#{order_id}', '#{tracking}', 'Royal Mail', 'shipped', now(), now())
        ON CONFLICT (id) DO NOTHING;
        """
      else
        ""
      end

    full_sql = basket_sql <> order_sql <> lines_sql <> refund_sql <> fulfillment_sql

    case System.cmd("psql", [db_url, "-c", full_sql], stderr_to_stdout: true) do
      {_out, 0} ->
        log(
          :ok,
          "  Order #{seq}: #{order_id} — #{customer.first_name} #{customer.last_name} (#{fin_status}/#{ful_status})"
        )

      {out, code} ->
        log(:warn, "  Order #{seq} SQL failed (exit #{code}): #{String.slice(out, 0, 300)}")
    end
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
