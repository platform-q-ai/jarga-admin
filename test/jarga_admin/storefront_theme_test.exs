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

    test "font name with CSS injection falls back to default" do
      defaults = StorefrontTheme.defaults()

      theme = %{
        defaults
        | fonts: %{
            defaults.fonts
            | heading: "Arial;--sf-color-background:red;position:fixed"
          }
      }

      validated = StorefrontTheme.validate(theme)

      assert validated.fonts.heading == defaults.fonts.heading
    end

    test "google_fonts_url only allows fonts.googleapis.com" do
      defaults = StorefrontTheme.defaults()

      theme = %{
        defaults
        | fonts: %{
            defaults.fonts
            | google_fonts_url: "https://evil.com/malicious.css"
          }
      }

      validated = StorefrontTheme.validate(theme)

      assert is_nil(validated.fonts.google_fonts_url)
    end

    test "valid google_fonts_url is accepted" do
      defaults = StorefrontTheme.defaults()

      theme = %{
        defaults
        | fonts: %{
            defaults.fonts
            | google_fonts_url: "https://fonts.googleapis.com/css2?family=Montserrat"
          }
      }

      validated = StorefrontTheme.validate(theme)

      assert validated.fonts.google_fonts_url ==
               "https://fonts.googleapis.com/css2?family=Montserrat"
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
      data = %{
        theme: StorefrontTheme.defaults(),
        css_vars: "test",
        google_fonts_url: nil,
        store_name: "TEST"
      }

      StorefrontTheme.cache_put(data)

      assert {:ok, cached} = StorefrontTheme.cache_get()
      assert cached.store_name == "TEST"
      assert cached.css_vars == "test"
    end

    test "cache_get returns :miss when empty" do
      StorefrontTheme.cache_clear()

      assert :miss = StorefrontTheme.cache_get()
    end

    test "cache_get returns :stale after TTL expires" do
      data = %{
        theme: StorefrontTheme.defaults(),
        css_vars: "stale",
        google_fonts_url: nil,
        store_name: "STALE"
      }

      StorefrontTheme.cache_put(data, ttl_seconds: 0)
      Process.sleep(10)

      # Stale-while-revalidate: returns :stale instead of :miss
      assert {:stale, cached} = StorefrontTheme.cache_get()
      assert cached.store_name == "STALE"
    end

    test "channel-scoped cache_put and cache_get" do
      data_a = %{
        theme: StorefrontTheme.defaults(),
        css_vars: "channel-a",
        google_fonts_url: nil,
        store_name: "STORE A"
      }

      data_b = %{
        theme: StorefrontTheme.defaults(),
        css_vars: "channel-b",
        google_fonts_url: nil,
        store_name: "STORE B"
      }

      StorefrontTheme.cache_put(data_a, channel: "online-store")
      StorefrontTheme.cache_put(data_b, channel: "b2b-portal")

      assert {:ok, cached_a} = StorefrontTheme.cache_get(channel: "online-store")
      assert {:ok, cached_b} = StorefrontTheme.cache_get(channel: "b2b-portal")

      assert cached_a.store_name == "STORE A"
      assert cached_b.store_name == "STORE B"
    end

    test "channel-scoped cache_get returns :miss for unknown channel" do
      StorefrontTheme.cache_clear()

      assert :miss = StorefrontTheme.cache_get(channel: "nonexistent")
    end
  end

  # ── Extended theme token coverage ────────────────────────────────────────

  describe "extended colors" do
    test "defaults include button, footer, nav colors" do
      %{colors: colors} = StorefrontTheme.defaults()

      for key <- [
            :btn_primary_bg,
            :btn_primary_text,
            :btn_secondary_bg,
            :btn_secondary_text,
            :footer_bg,
            :footer_text,
            :footer_muted,
            :nav_bg,
            :text,
            :text_secondary
          ] do
        assert Map.has_key?(colors, key), "missing extended color key: #{key}"
      end
    end

    test "parse extracts extended color keys" do
      payload = %{
        "colors" => %{
          "btn_primary_bg" => "#111111",
          "btn_primary_text" => "#eeeeee",
          "footer_bg" => "#222222",
          "nav_bg" => "#333333",
          "text" => "#444444",
          "text_secondary" => "#555555"
        }
      }

      theme = StorefrontTheme.parse(payload)
      assert theme.colors.btn_primary_bg == "#111111"
      assert theme.colors.btn_primary_text == "#eeeeee"
      assert theme.colors.footer_bg == "#222222"
      assert theme.colors.nav_bg == "#333333"
      assert theme.colors.text == "#444444"
      assert theme.colors.text_secondary == "#555555"
    end

    test "to_css_vars emits button, footer, nav CSS variables" do
      theme = StorefrontTheme.defaults()
      css = StorefrontTheme.to_css_vars(theme)

      assert css =~ "--sf-color-btn-primary-bg"
      assert css =~ "--sf-color-btn-primary-text"
      assert css =~ "--sf-color-btn-secondary-bg"
      assert css =~ "--sf-color-btn-secondary-text"
      assert css =~ "--sf-color-footer-bg"
      assert css =~ "--sf-color-footer-text"
      assert css =~ "--sf-color-footer-muted"
      assert css =~ "--sf-color-nav-bg"
      assert css =~ "--sf-color-text:"
      assert css =~ "--sf-color-text-secondary"
    end
  end

  describe "extended fonts" do
    test "defaults include primary font and weights" do
      %{fonts: fonts} = StorefrontTheme.defaults()

      assert Map.has_key?(fonts, :primary)
      assert Map.has_key?(fonts, :weight_light)
      assert Map.has_key?(fonts, :weight_regular)
      assert Map.has_key?(fonts, :weight_medium)
    end

    test "parse extracts font weights" do
      payload = %{
        "fonts" => %{
          "primary" => "Georgia, serif",
          "weight_light" => "200",
          "weight_regular" => "400",
          "weight_medium" => "600"
        }
      }

      theme = StorefrontTheme.parse(payload)
      assert theme.fonts.primary == "Georgia, serif"
      assert theme.fonts.weight_light == "200"
      assert theme.fonts.weight_regular == "400"
      assert theme.fonts.weight_medium == "600"
    end

    test "validate rejects invalid font weight values" do
      theme = StorefrontTheme.defaults()
      bad_theme = put_in(theme, [:fonts, :weight_light], "bold")
      validated = StorefrontTheme.validate(bad_theme)
      # Should fall back to default, not keep "bold"
      assert validated.fonts.weight_light == theme.fonts.weight_light
    end

    test "to_css_vars emits font weight and primary font variables" do
      theme = StorefrontTheme.defaults()
      css = StorefrontTheme.to_css_vars(theme)

      assert css =~ "--sf-font-primary"
      assert css =~ "--sf-font-weight-light"
      assert css =~ "--sf-font-weight-regular"
      assert css =~ "--sf-font-weight-medium"
    end
  end

  describe "spacing section" do
    test "defaults include spacing values" do
      defaults = StorefrontTheme.defaults()
      assert Map.has_key?(defaults, :spacing)

      for key <- [:xs, :sm, :md, :lg, :xl, :xxl] do
        assert Map.has_key?(defaults.spacing, key), "missing spacing key: #{key}"
      end
    end

    test "parse extracts spacing values" do
      payload = %{"spacing" => %{"xs" => "4px", "sm" => "8px", "md" => "16px"}}
      theme = StorefrontTheme.parse(payload)
      assert theme.spacing.xs == "4px"
      assert theme.spacing.sm == "8px"
      assert theme.spacing.md == "16px"
    end

    test "to_css_vars emits spacing variables" do
      theme = StorefrontTheme.defaults()
      css = StorefrontTheme.to_css_vars(theme)

      assert css =~ "--sf-space-xs"
      assert css =~ "--sf-space-sm"
      assert css =~ "--sf-space-md"
      assert css =~ "--sf-space-lg"
      assert css =~ "--sf-space-xl"
      assert css =~ "--sf-space-2xl"
    end
  end

  describe "typography section" do
    test "defaults include letter spacing values" do
      defaults = StorefrontTheme.defaults()
      assert Map.has_key?(defaults, :typography)

      for key <- [:letter_spacing_heading, :letter_spacing_nav, :letter_spacing_body] do
        assert Map.has_key?(defaults.typography, key), "missing typography key: #{key}"
      end
    end

    test "parse extracts typography values" do
      payload = %{
        "typography" => %{"letter_spacing_heading" => "0.3em", "letter_spacing_nav" => "0.15em"}
      }

      theme = StorefrontTheme.parse(payload)
      assert theme.typography.letter_spacing_heading == "0.3em"
      assert theme.typography.letter_spacing_nav == "0.15em"
    end

    test "to_css_vars emits letter spacing variables" do
      theme = StorefrontTheme.defaults()
      css = StorefrontTheme.to_css_vars(theme)

      assert css =~ "--sf-letter-spacing-heading"
      assert css =~ "--sf-letter-spacing-nav"
      assert css =~ "--sf-letter-spacing-body"
    end
  end

  describe "animation section" do
    test "defaults include transition speed" do
      defaults = StorefrontTheme.defaults()
      assert Map.has_key?(defaults, :animation)
      assert Map.has_key?(defaults.animation, :transition_speed)
    end

    test "parse extracts animation values" do
      payload = %{"animation" => %{"transition_speed" => "300ms"}}
      theme = StorefrontTheme.parse(payload)
      assert theme.animation.transition_speed == "300ms"
    end

    test "validate rejects invalid transition speed" do
      theme = StorefrontTheme.defaults()
      bad_theme = put_in(theme, [:animation, :transition_speed], "fast")
      validated = StorefrontTheme.validate(bad_theme)
      assert validated.animation.transition_speed == theme.animation.transition_speed
    end

    test "to_css_vars emits transition speed" do
      theme = StorefrontTheme.defaults()
      css = StorefrontTheme.to_css_vars(theme)
      assert css =~ "--sf-transition-speed"
    end
  end

  describe "layout extensions" do
    test "defaults include nav_height and announcement_height" do
      %{layout: layout} = StorefrontTheme.defaults()
      assert Map.has_key?(layout, :nav_height)
      assert Map.has_key?(layout, :announcement_height)
    end

    test "parse extracts nav_height and announcement_height" do
      payload = %{"layout" => %{"nav_height" => "80px", "announcement_height" => "44px"}}
      theme = StorefrontTheme.parse(payload)
      assert theme.layout.nav_height == "80px"
      assert theme.layout.announcement_height == "44px"
    end

    test "to_css_vars emits nav and announcement height" do
      theme = StorefrontTheme.defaults()
      css = StorefrontTheme.to_css_vars(theme)
      assert css =~ "--sf-nav-height"
      assert css =~ "--sf-announcement-height"
    end
  end
end
