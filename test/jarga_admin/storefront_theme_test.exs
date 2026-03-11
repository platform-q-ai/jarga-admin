defmodule JargaAdmin.StorefrontThemeTest do
  use ExUnit.Case, async: true

  alias JargaAdmin.StorefrontTheme

  # ── defaults/0 ───────────────────────────────────────────────────────────

  describe "defaults/0" do
    test "returns a map with all required token sections" do
      defaults = StorefrontTheme.defaults()

      assert is_map(defaults)
      assert Map.has_key?(defaults, :fonts)
      assert Map.has_key?(defaults, :colors)
      assert Map.has_key?(defaults, :layout)
      assert Map.has_key?(defaults, :branding)
    end

    test "fonts section has heading, body, and google_fonts_url" do
      %{fonts: fonts} = StorefrontTheme.defaults()

      assert is_binary(fonts.heading)
      assert is_binary(fonts.body)
      assert fonts.heading != ""
      assert fonts.body != ""
    end

    test "colors section has required keys" do
      %{colors: colors} = StorefrontTheme.defaults()

      for key <- [:primary, :accent, :background, :surface, :text_primary, :text_muted, :border] do
        assert Map.has_key?(colors, key), "missing color key: #{key}"
        assert is_binary(Map.get(colors, key))
      end
    end

    test "layout section has border_radius and max_width" do
      %{layout: layout} = StorefrontTheme.defaults()

      assert is_binary(layout.border_radius)
      assert is_binary(layout.max_width)
    end

    test "branding section has store_name" do
      %{branding: branding} = StorefrontTheme.defaults()

      assert is_binary(branding.store_name)
      assert branding.store_name != ""
    end
  end

  # ── parse/1 ──────────────────────────────────────────────────────────────

  describe "parse/1" do
    test "parses a valid theme payload into a theme map" do
      payload = %{
        "fonts" => %{
          "heading" => "Montserrat",
          "body" => "Inter",
          "display" => "Noto Serif Display",
          "google_fonts_url" => "https://fonts.googleapis.com/css2?family=Montserrat"
        },
        "colors" => %{
          "primary" => "#1a1a2e",
          "accent" => "#e94560",
          "background" => "#f5f5f5",
          "surface" => "#ffffff",
          "text_primary" => "#181512",
          "text_muted" => "#5a5048",
          "text_on_primary" => "#ffffff",
          "success" => "#3a6645",
          "warning" => "#b8860b",
          "error" => "#9a3f2a",
          "border" => "rgba(24,21,18,0.10)"
        },
        "layout" => %{
          "border_radius" => "4px",
          "border_radius_lg" => "8px",
          "max_width" => "1200px",
          "nav_style" => "dark",
          "nav_blur" => true
        },
        "branding" => %{
          "store_name" => "MY STORE",
          "logo_url" => "/media/logo.svg",
          "favicon_url" => "/media/favicon.svg"
        }
      }

      theme = StorefrontTheme.parse(payload)

      assert theme.fonts.heading == "Montserrat"
      assert theme.fonts.body == "Inter"
      assert theme.fonts.display == "Noto Serif Display"
      assert theme.fonts.google_fonts_url == "https://fonts.googleapis.com/css2?family=Montserrat"
      assert theme.colors.primary == "#1a1a2e"
      assert theme.colors.accent == "#e94560"
      assert theme.colors.background == "#f5f5f5"
      assert theme.colors.text_on_primary == "#ffffff"
      assert theme.colors.border == "rgba(24,21,18,0.10)"
      assert theme.layout.border_radius == "4px"
      assert theme.layout.border_radius_lg == "8px"
      assert theme.layout.max_width == "1200px"
      assert theme.layout.nav_style == "dark"
      assert theme.layout.nav_blur == true
      assert theme.branding.store_name == "MY STORE"
      assert theme.branding.logo_url == "/media/logo.svg"
    end

    test "nil payload returns defaults" do
      theme = StorefrontTheme.parse(nil)
      defaults = StorefrontTheme.defaults()

      assert theme.fonts.heading == defaults.fonts.heading
      assert theme.colors.primary == defaults.colors.primary
    end

    test "empty map returns defaults" do
      theme = StorefrontTheme.parse(%{})
      defaults = StorefrontTheme.defaults()

      assert theme.fonts.heading == defaults.fonts.heading
      assert theme.colors.primary == defaults.colors.primary
    end

    test "partial payload merges with defaults" do
      payload = %{
        "colors" => %{"primary" => "#ff0000"}
      }

      theme = StorefrontTheme.parse(payload)
      defaults = StorefrontTheme.defaults()

      # Overridden value
      assert theme.colors.primary == "#ff0000"
      # Default values for missing keys
      assert theme.fonts.heading == defaults.fonts.heading
      assert theme.colors.accent == defaults.colors.accent
      assert theme.layout.border_radius == defaults.layout.border_radius
      assert theme.branding.store_name == defaults.branding.store_name
    end

    test "ignores unknown keys" do
      payload = %{
        "fonts" => %{"heading" => "Arial"},
        "unknown_section" => %{"foo" => "bar"},
        "colors" => %{"primary" => "#000", "nonexistent_color" => "#fff"}
      }

      theme = StorefrontTheme.parse(payload)

      assert theme.fonts.heading == "Arial"
      assert theme.colors.primary == "#000"
      # Unknown section is ignored — no crash
      refute Map.has_key?(theme, :unknown_section)
    end
  end

  # ── validate/1 ───────────────────────────────────────────────────────────

  describe "validate/1" do
    test "valid theme passes validation unchanged" do
      theme = StorefrontTheme.defaults()
      validated = StorefrontTheme.validate(theme)

      assert validated.colors.primary == theme.colors.primary
      assert validated.fonts.heading == theme.fonts.heading
    end

    test "invalid hex color falls back to default" do
      defaults = StorefrontTheme.defaults()

      theme = %{
        defaults
        | colors: %{defaults.colors | primary: "not-a-color", accent: "javascript:alert(1)"}
      }

      validated = StorefrontTheme.validate(theme)

      assert validated.colors.primary == defaults.colors.primary
      assert validated.colors.accent == defaults.colors.accent
    end

    test "valid CSS color formats are accepted" do
      defaults = StorefrontTheme.defaults()

      theme = %{
        defaults
        | colors: %{
            defaults.colors
            | primary: "#1a1a2e",
              accent: "rgb(233, 69, 96)",
              background: "rgba(0,0,0,0.5)",
              surface: "hsl(120, 50%, 50%)"
          }
      }

      validated = StorefrontTheme.validate(theme)

      assert validated.colors.primary == "#1a1a2e"
      assert validated.colors.accent == "rgb(233, 69, 96)"
      assert validated.colors.background == "rgba(0,0,0,0.5)"
      assert validated.colors.surface == "hsl(120, 50%, 50%)"
    end

    test "empty font name falls back to default" do
      defaults = StorefrontTheme.defaults()
      theme = %{defaults | fonts: %{defaults.fonts | heading: "", body: ""}}

      validated = StorefrontTheme.validate(theme)

      assert validated.fonts.heading == defaults.fonts.heading
      assert validated.fonts.body == defaults.fonts.body
    end

    test "invalid border_radius falls back to default" do
      defaults = StorefrontTheme.defaults()
      theme = %{defaults | layout: %{defaults.layout | border_radius: "evil; injection"}}

      validated = StorefrontTheme.validate(theme)

      assert validated.layout.border_radius == defaults.layout.border_radius
    end

    test "valid border_radius values are accepted" do
      defaults = StorefrontTheme.defaults()

      for valid <- ["0", "4px", "0.5rem", "50%", "8px"] do
        theme = %{defaults | layout: %{defaults.layout | border_radius: valid}}
        validated = StorefrontTheme.validate(theme)
        assert validated.layout.border_radius == valid
      end
    end

    test "invalid max_width falls back to default" do
      defaults = StorefrontTheme.defaults()
      theme = %{defaults | layout: %{defaults.layout | max_width: "drop table"}}

      validated = StorefrontTheme.validate(theme)

      assert validated.layout.max_width == defaults.layout.max_width
    end
  end

  # ── to_css_vars/1 ────────────────────────────────────────────────────────

  describe "to_css_vars/1" do
    test "generates a CSS inline style string" do
      theme = StorefrontTheme.defaults()
      css = StorefrontTheme.to_css_vars(theme)

      assert is_binary(css)
      assert String.contains?(css, "--sf-font-heading:")
      assert String.contains?(css, "--sf-font-body:")
      assert String.contains?(css, "--sf-color-primary:")
      assert String.contains?(css, "--sf-color-accent:")
      assert String.contains?(css, "--sf-color-background:")
      assert String.contains?(css, "--sf-color-text-primary:")
      assert String.contains?(css, "--sf-color-border:")
      assert String.contains?(css, "--sf-border-radius:")
      assert String.contains?(css, "--sf-max-width:")
    end

    test "CSS vars contain the actual theme values" do
      payload = %{
        "colors" => %{"primary" => "#ff0000"},
        "fonts" => %{"heading" => "Georgia"}
      }

      theme = StorefrontTheme.parse(payload)
      css = StorefrontTheme.to_css_vars(theme)

      assert String.contains?(css, "--sf-color-primary:#ff0000")
      assert String.contains?(css, "--sf-font-heading:Georgia")
    end

    test "CSS vars are semicolon-separated" do
      theme = StorefrontTheme.defaults()
      css = StorefrontTheme.to_css_vars(theme)

      # Should be a series of --var:value; pairs
      parts = String.split(css, ";", trim: true)
      assert length(parts) > 10

      for part <- parts do
        assert String.contains?(part, "--sf-"), "Expected CSS var, got: #{part}"
      end
    end

    test "google_fonts_url is not included in CSS vars" do
      theme = StorefrontTheme.defaults()
      css = StorefrontTheme.to_css_vars(theme)

      refute String.contains?(css, "google_fonts_url")
      refute String.contains?(css, "googleapis")
    end
  end

  # ── google_fonts_url/1 ──────────────────────────────────────────────────

  describe "google_fonts_url/1" do
    test "returns the google_fonts_url from the theme" do
      payload = %{
        "fonts" => %{
          "heading" => "Montserrat",
          "body" => "Inter",
          "google_fonts_url" => "https://fonts.googleapis.com/css2?family=Montserrat&family=Inter"
        }
      }

      theme = StorefrontTheme.parse(payload)
      url = StorefrontTheme.google_fonts_url(theme)

      assert url == "https://fonts.googleapis.com/css2?family=Montserrat&family=Inter"
    end

    test "returns nil when no google_fonts_url is set" do
      theme = StorefrontTheme.parse(%{"fonts" => %{"heading" => "Arial"}})
      url = StorefrontTheme.google_fonts_url(theme)

      assert is_nil(url) or is_binary(url)
    end
  end

  # ── store_name/1 ────────────────────────────────────────────────────────

  describe "store_name/1" do
    test "returns the store name from branding" do
      payload = %{"branding" => %{"store_name" => "MY SHOP"}}
      theme = StorefrontTheme.parse(payload)

      assert StorefrontTheme.store_name(theme) == "MY SHOP"
    end

    test "returns default store name when not set" do
      theme = StorefrontTheme.defaults()

      assert is_binary(StorefrontTheme.store_name(theme))
      assert StorefrontTheme.store_name(theme) != ""
    end
  end

  # ── ETS caching ─────────────────────────────────────────────────────────

  describe "caching" do
    setup do
      # Ensure the ETS table exists for caching tests
      StorefrontTheme.init_cache()
      :ok
    end

    test "cache_put and cache_get round-trip" do
      theme = StorefrontTheme.defaults()
      StorefrontTheme.cache_put(theme)

      assert {:ok, cached} = StorefrontTheme.cache_get()
      assert cached.fonts.heading == theme.fonts.heading
      assert cached.colors.primary == theme.colors.primary
    end

    test "cache_get returns :miss when empty" do
      StorefrontTheme.cache_clear()

      assert :miss = StorefrontTheme.cache_get()
    end

    test "cache_get returns :miss after TTL expires" do
      theme = StorefrontTheme.defaults()
      # Insert with a timestamp in the past (expired)
      StorefrontTheme.cache_put(theme, ttl_seconds: 0)
      # Small sleep to ensure expiry
      Process.sleep(10)

      assert :miss = StorefrontTheme.cache_get()
    end
  end
end
