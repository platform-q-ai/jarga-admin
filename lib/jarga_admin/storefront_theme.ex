defmodule JargaAdmin.StorefrontTheme do
  @moduledoc """
  Loads, validates, caches, and converts storefront theme tokens.

  Theme tokens are stored as JSON in the `storefront_theme` Frontend API slot
  and applied as CSS custom properties on the `.sf-page` wrapper. This enables
  agent-driven visual customisation without code changes.

  ## Usage

      # Load theme (cached, falls back to defaults)
      theme = StorefrontTheme.load()

      # Convert to inline CSS style string
      css_vars = StorefrontTheme.to_css_vars(theme)

      # Get Google Fonts URL for <head>
      fonts_url = StorefrontTheme.google_fonts_url(theme)
  """

  require Logger

  alias JargaAdmin.Api

  @cache_table :storefront_theme_cache
  @cache_key :theme
  @default_ttl_seconds 60

  # ── Default Theme ────────────────────────────────────────────────────────

  @default_fonts %{
    heading: "Helvetica Neue",
    body: "Helvetica Neue",
    display: "Helvetica Neue",
    primary: "Helvetica Neue, Helvetica, Arial, sans-serif",
    weight_light: "300",
    weight_regular: "400",
    weight_medium: "500",
    google_fonts_url: nil
  }

  @default_colors %{
    primary: "#1a1a1a",
    accent: "#000000",
    background: "#ffffff",
    surface: "#ffffff",
    text: "#1a1a1a",
    text_primary: "#1a1a1a",
    text_secondary: "#666666",
    text_muted: "#999999",
    text_on_primary: "#ffffff",
    btn_primary_bg: "#000000",
    btn_primary_text: "#ffffff",
    btn_secondary_bg: "#ffffff",
    btn_secondary_text: "#000000",
    nav_bg: "#ffffff",
    footer_bg: "#1a1a1a",
    footer_text: "#ffffff",
    footer_muted: "#999999",
    success: "#3a6645",
    warning: "#b8860b",
    error: "#9a3f2a",
    border: "rgba(0,0,0,0.08)"
  }

  @default_layout %{
    border_radius: "0",
    border_radius_lg: "0",
    max_width: "1440px",
    nav_style: "light",
    nav_blur: false,
    nav_height: "60px",
    announcement_height: "36px"
  }

  @default_branding %{
    store_name: "JARGA",
    logo_url: nil,
    favicon_url: nil
  }

  @default_spacing %{
    xs: "8px",
    sm: "16px",
    md: "32px",
    lg: "64px",
    xl: "96px",
    xxl: "128px"
  }

  @default_typography %{
    letter_spacing_heading: "0.2em",
    letter_spacing_nav: "0.25em",
    letter_spacing_body: "0.03em"
  }

  @default_animation %{
    transition_speed: "200ms"
  }

  @doc "Returns the default theme with Zara Home aesthetic values."
  def defaults do
    %{
      fonts: @default_fonts,
      colors: @default_colors,
      layout: @default_layout,
      branding: @default_branding,
      spacing: @default_spacing,
      typography: @default_typography,
      animation: @default_animation
    }
  end

  # ── Parse ────────────────────────────────────────────────────────────────

  @doc """
  Parses a raw JSON payload (string-keyed map from the API) into a theme map.

  Missing sections or keys are filled from defaults. Unknown keys are ignored.
  Returns the full default theme for nil or empty input.
  """
  def parse(nil), do: defaults()
  def parse(payload) when payload == %{}, do: defaults()

  def parse(payload) when is_map(payload) do
    %{
      fonts: parse_fonts(payload["fonts"]),
      colors: parse_colors(payload["colors"]),
      layout: parse_layout(payload["layout"]),
      branding: parse_branding(payload["branding"]),
      spacing: parse_spacing(payload["spacing"]),
      typography: parse_typography(payload["typography"]),
      animation: parse_animation(payload["animation"])
    }
  end

  def parse(_), do: defaults()

  defp parse_fonts(nil), do: @default_fonts

  defp parse_fonts(raw) when is_map(raw) do
    %{
      heading: raw["heading"] || @default_fonts.heading,
      body: raw["body"] || @default_fonts.body,
      display: raw["display"] || @default_fonts.display,
      primary: raw["primary"] || @default_fonts.primary,
      weight_light: raw["weight_light"] || @default_fonts.weight_light,
      weight_regular: raw["weight_regular"] || @default_fonts.weight_regular,
      weight_medium: raw["weight_medium"] || @default_fonts.weight_medium,
      google_fonts_url: raw["google_fonts_url"] || @default_fonts.google_fonts_url
    }
  end

  defp parse_fonts(_), do: @default_fonts

  defp parse_colors(nil), do: @default_colors

  defp parse_colors(raw) when is_map(raw) do
    %{
      primary: raw["primary"] || @default_colors.primary,
      accent: raw["accent"] || @default_colors.accent,
      background: raw["background"] || @default_colors.background,
      surface: raw["surface"] || @default_colors.surface,
      text: raw["text"] || @default_colors.text,
      text_primary: raw["text_primary"] || @default_colors.text_primary,
      text_secondary: raw["text_secondary"] || @default_colors.text_secondary,
      text_muted: raw["text_muted"] || @default_colors.text_muted,
      text_on_primary: raw["text_on_primary"] || @default_colors.text_on_primary,
      btn_primary_bg: raw["btn_primary_bg"] || @default_colors.btn_primary_bg,
      btn_primary_text: raw["btn_primary_text"] || @default_colors.btn_primary_text,
      btn_secondary_bg: raw["btn_secondary_bg"] || @default_colors.btn_secondary_bg,
      btn_secondary_text: raw["btn_secondary_text"] || @default_colors.btn_secondary_text,
      nav_bg: raw["nav_bg"] || @default_colors.nav_bg,
      footer_bg: raw["footer_bg"] || @default_colors.footer_bg,
      footer_text: raw["footer_text"] || @default_colors.footer_text,
      footer_muted: raw["footer_muted"] || @default_colors.footer_muted,
      success: raw["success"] || @default_colors.success,
      warning: raw["warning"] || @default_colors.warning,
      error: raw["error"] || @default_colors.error,
      border: raw["border"] || @default_colors.border
    }
  end

  defp parse_colors(_), do: @default_colors

  defp parse_layout(nil), do: @default_layout

  defp parse_layout(raw) when is_map(raw) do
    %{
      border_radius: raw["border_radius"] || @default_layout.border_radius,
      border_radius_lg: raw["border_radius_lg"] || @default_layout.border_radius_lg,
      max_width: raw["max_width"] || @default_layout.max_width,
      nav_style: raw["nav_style"] || @default_layout.nav_style,
      nav_blur:
        if(is_boolean(raw["nav_blur"]), do: raw["nav_blur"], else: @default_layout.nav_blur),
      nav_height: raw["nav_height"] || @default_layout.nav_height,
      announcement_height: raw["announcement_height"] || @default_layout.announcement_height
    }
  end

  defp parse_layout(_), do: @default_layout

  defp parse_spacing(nil), do: @default_spacing

  defp parse_spacing(raw) when is_map(raw) do
    %{
      xs: raw["xs"] || @default_spacing.xs,
      sm: raw["sm"] || @default_spacing.sm,
      md: raw["md"] || @default_spacing.md,
      lg: raw["lg"] || @default_spacing.lg,
      xl: raw["xl"] || @default_spacing.xl,
      xxl: raw["2xl"] || raw["xxl"] || @default_spacing.xxl
    }
  end

  defp parse_spacing(_), do: @default_spacing

  defp parse_typography(nil), do: @default_typography

  defp parse_typography(raw) when is_map(raw) do
    %{
      letter_spacing_heading:
        raw["letter_spacing_heading"] || @default_typography.letter_spacing_heading,
      letter_spacing_nav: raw["letter_spacing_nav"] || @default_typography.letter_spacing_nav,
      letter_spacing_body: raw["letter_spacing_body"] || @default_typography.letter_spacing_body
    }
  end

  defp parse_typography(_), do: @default_typography

  defp parse_animation(nil), do: @default_animation

  defp parse_animation(raw) when is_map(raw) do
    %{
      transition_speed: raw["transition_speed"] || @default_animation.transition_speed
    }
  end

  defp parse_animation(_), do: @default_animation

  defp parse_branding(nil), do: @default_branding

  defp parse_branding(raw) when is_map(raw) do
    %{
      store_name: raw["store_name"] || @default_branding.store_name,
      logo_url: raw["logo_url"] || @default_branding.logo_url,
      favicon_url: raw["favicon_url"] || @default_branding.favicon_url
    }
  end

  defp parse_branding(_), do: @default_branding

  # ── Validate ─────────────────────────────────────────────────────────────

  @doc """
  Validates theme tokens. Invalid values are replaced with defaults.

  - Colours must be valid CSS colour values (hex, rgb, rgba, hsl, hsla)
  - Font names must be non-empty strings
  - Border radius and max_width must be valid CSS lengths
  """
  def validate(theme) do
    d = defaults()

    %{
      fonts: validate_fonts(theme.fonts, d.fonts),
      colors: validate_colors(theme.colors, d.colors),
      layout: validate_layout(theme.layout, d.layout),
      branding: validate_branding(theme.branding, d.branding),
      spacing: validate_spacing(theme.spacing, d.spacing),
      typography: validate_typography(theme.typography, d.typography),
      animation: validate_animation(theme.animation, d.animation)
    }
  end

  defp validate_fonts(fonts, defaults) do
    %{
      fonts
      | heading: validate_font_name(fonts.heading, defaults.heading),
        body: validate_font_name(fonts.body, defaults.body),
        display: validate_font_name(fonts.display, defaults.display),
        primary: validate_font_family(fonts.primary, defaults.primary),
        weight_light: validate_font_weight(fonts.weight_light, defaults.weight_light),
        weight_regular: validate_font_weight(fonts.weight_regular, defaults.weight_regular),
        weight_medium: validate_font_weight(fonts.weight_medium, defaults.weight_medium),
        google_fonts_url: validate_google_fonts_url(fonts.google_fonts_url)
    }
  end

  @google_fonts_re ~r|\Ahttps://fonts\.googleapis\.com/|
  defp validate_google_fonts_url(url) when is_binary(url) do
    if Regex.match?(@google_fonts_re, url), do: url, else: nil
  end

  defp validate_google_fonts_url(_), do: nil

  defp validate_branding(branding, defaults) do
    %{
      store_name: validate_store_name(branding.store_name, defaults.store_name),
      logo_url: validate_asset_url(branding.logo_url),
      favicon_url: validate_asset_url(branding.favicon_url)
    }
  end

  defp validate_store_name(name, _default) when is_binary(name) and byte_size(name) in 1..100 do
    name
  end

  defp validate_store_name(_, default), do: default

  # Only allow relative paths or https:// URLs (block javascript:/data: URIs)
  defp validate_asset_url(nil), do: nil

  defp validate_asset_url(url) when is_binary(url) do
    trimmed = String.trim(url)

    cond do
      String.starts_with?(trimmed, "/") -> trimmed
      String.starts_with?(trimmed, "https://") -> trimmed
      true -> nil
    end
  end

  defp validate_asset_url(_), do: nil

  # Only allow alphanumeric, spaces, hyphens (no semicolons/special chars)
  @font_name_re ~r/\A[a-zA-Z0-9 \-]+\z/
  defp validate_font_name(name, default) when is_binary(name) and name != "" do
    if Regex.match?(@font_name_re, name), do: name, else: default
  end

  defp validate_font_name(_, default), do: default

  defp validate_colors(colors, defaults) do
    color_keys = [
      :primary,
      :accent,
      :background,
      :surface,
      :text,
      :text_primary,
      :text_secondary,
      :text_muted,
      :text_on_primary,
      :btn_primary_bg,
      :btn_primary_text,
      :btn_secondary_bg,
      :btn_secondary_text,
      :nav_bg,
      :footer_bg,
      :footer_text,
      :footer_muted,
      :success,
      :warning,
      :error,
      :border
    ]

    Enum.reduce(color_keys, colors, fn key, acc ->
      value = Map.get(acc, key)
      default = Map.get(defaults, key)

      if valid_css_color?(value) do
        acc
      else
        Map.put(acc, key, default)
      end
    end)
  end

  @valid_nav_styles ~w(light dark transparent)
  defp validate_layout(layout, defaults) do
    %{
      layout
      | border_radius: validate_css_length(layout.border_radius, defaults.border_radius),
        border_radius_lg: validate_css_length(layout.border_radius_lg, defaults.border_radius_lg),
        max_width: validate_css_length(layout.max_width, defaults.max_width),
        nav_style:
          if(layout.nav_style in @valid_nav_styles,
            do: layout.nav_style,
            else: defaults.nav_style
          ),
        nav_height: validate_css_length(layout.nav_height, defaults.nav_height),
        announcement_height:
          validate_css_length(layout.announcement_height, defaults.announcement_height)
    }
  end

  defp validate_spacing(spacing, defaults) do
    spacing_keys = [:xs, :sm, :md, :lg, :xl, :xxl]

    Enum.reduce(spacing_keys, spacing, fn key, acc ->
      value = Map.get(acc, key)
      default = Map.get(defaults, key)
      Map.put(acc, key, validate_css_length(value, default))
    end)
  end

  defp validate_typography(typography, defaults) do
    typo_keys = [:letter_spacing_heading, :letter_spacing_nav, :letter_spacing_body]

    Enum.reduce(typo_keys, typography, fn key, acc ->
      value = Map.get(acc, key)
      default = Map.get(defaults, key)
      Map.put(acc, key, validate_css_length(value, default))
    end)
  end

  @transition_speed_re ~r/\A[0-9]+(\.[0-9]+)?(ms|s)\z/
  defp validate_animation(animation, defaults) do
    speed = animation.transition_speed

    validated_speed =
      if is_binary(speed) and Regex.match?(@transition_speed_re, String.trim(speed)) do
        String.trim(speed)
      else
        defaults.transition_speed
      end

    %{animation | transition_speed: validated_speed}
  end

  # Font family allows commas and quotes for fallback stacks like "Georgia, serif"
  @font_family_re ~r/\A[a-zA-Z0-9 \-,'"]+\z/
  defp validate_font_family(name, default) when is_binary(name) and name != "" do
    if Regex.match?(@font_family_re, name), do: name, else: default
  end

  defp validate_font_family(_, default), do: default

  # Font weight must be 100-900 in increments of 100
  @valid_font_weights ~w(100 200 300 400 500 600 700 800 900)
  defp validate_font_weight(weight, default) when is_binary(weight) do
    if weight in @valid_font_weights, do: weight, else: default
  end

  defp validate_font_weight(_, default), do: default

  # Restrict chars inside parens to valid CSS color characters only (no semicolons/colons)
  @css_color_re ~r/\A(#[0-9a-fA-F]{3,8}|rgba?\([0-9., %]+\)|hsla?\([0-9., %deg]+\))\z/
  defp valid_css_color?(value) when is_binary(value) do
    Regex.match?(@css_color_re, String.trim(value))
  end

  defp valid_css_color?(_), do: false

  @css_length_re ~r/\A[0-9]+(\.[0-9]+)?(px|rem|em|%|vw|vh)?\z/
  defp validate_css_length(value, default) when is_binary(value) do
    if Regex.match?(@css_length_re, String.trim(value)) do
      value
    else
      default
    end
  end

  defp validate_css_length(_, default), do: default

  # ── CSS Variable Generation ──────────────────────────────────────────────

  @doc """
  Converts a theme map into a CSS inline style string of custom properties.

  Returns a string like `"--sf-font-heading:Montserrat;--sf-color-primary:#1a1a2e;..."`.
  """
  def to_css_vars(theme) do
    [
      # Fonts
      {"--sf-font-heading", theme.fonts.heading},
      {"--sf-font-body", theme.fonts.body},
      {"--sf-font-display", theme.fonts.display},
      {"--sf-font-primary", theme.fonts.primary},
      {"--sf-font-weight-light", theme.fonts.weight_light},
      {"--sf-font-weight-regular", theme.fonts.weight_regular},
      {"--sf-font-weight-medium", theme.fonts.weight_medium},
      # Colors
      {"--sf-color-primary", theme.colors.primary},
      {"--sf-color-accent", theme.colors.accent},
      # --sf-color-bg is the canonical CSS variable used in storefront.css (~30 refs).
      # --sf-color-background is emitted for backward compatibility with early theme consumers.
      {"--sf-color-bg", theme.colors.background},
      {"--sf-color-background", theme.colors.background},
      {"--sf-color-surface", theme.colors.surface},
      {"--sf-color-text", theme.colors.text},
      {"--sf-color-text-primary", theme.colors.text_primary},
      {"--sf-color-text-secondary", theme.colors.text_secondary},
      {"--sf-color-text-muted", theme.colors.text_muted},
      {"--sf-color-text-on-primary", theme.colors.text_on_primary},
      {"--sf-color-btn-primary-bg", theme.colors.btn_primary_bg},
      {"--sf-color-btn-primary-text", theme.colors.btn_primary_text},
      {"--sf-color-btn-secondary-bg", theme.colors.btn_secondary_bg},
      {"--sf-color-btn-secondary-text", theme.colors.btn_secondary_text},
      {"--sf-color-nav-bg", theme.colors.nav_bg},
      {"--sf-color-footer-bg", theme.colors.footer_bg},
      {"--sf-color-footer-text", theme.colors.footer_text},
      {"--sf-color-footer-muted", theme.colors.footer_muted},
      {"--sf-color-success", theme.colors.success},
      {"--sf-color-warning", theme.colors.warning},
      {"--sf-color-error", theme.colors.error},
      {"--sf-color-border", theme.colors.border},
      # Layout
      {"--sf-border-radius", theme.layout.border_radius},
      {"--sf-border-radius-lg", theme.layout.border_radius_lg},
      {"--sf-max-width", theme.layout.max_width},
      {"--sf-nav-height", theme.layout.nav_height},
      {"--sf-announcement-height", theme.layout.announcement_height},
      # Spacing
      {"--sf-space-xs", theme.spacing.xs},
      {"--sf-space-sm", theme.spacing.sm},
      {"--sf-space-md", theme.spacing.md},
      {"--sf-space-lg", theme.spacing.lg},
      {"--sf-space-xl", theme.spacing.xl},
      {"--sf-space-2xl", theme.spacing.xxl},
      # Typography
      {"--sf-letter-spacing-heading", theme.typography.letter_spacing_heading},
      {"--sf-letter-spacing-nav", theme.typography.letter_spacing_nav},
      {"--sf-letter-spacing-body", theme.typography.letter_spacing_body},
      # Animation
      {"--sf-transition-speed", theme.animation.transition_speed}
    ]
    |> Enum.map(fn {var, val} -> "#{var}:#{val}" end)
    |> Enum.join(";")
  end

  # ── Accessors ────────────────────────────────────────────────────────────

  @doc "Returns the Google Fonts URL from the theme, or nil."
  def google_fonts_url(%{fonts: %{google_fonts_url: url}}), do: url
  def google_fonts_url(_), do: nil

  @doc "Returns the store name from branding."
  def store_name(%{branding: %{store_name: name}}), do: name
  def store_name(_), do: @default_branding.store_name

  # ── Loading (API + Cache) ────────────────────────────────────────────────

  @doc """
  Loads the theme from cache or API. Falls back to defaults on error.

  Accepts an optional `channel` parameter to scope the theme to a channel.
  When `channel` is nil or not provided, uses the global theme slot.

  Uses stale-while-revalidate: on TTL expiry, returns the stale cached theme
  immediately while spawning a background refresh. This prevents cache stampede
  and keeps mount latency low.

  Returns a map with pre-computed derived values:
  `%{theme: theme, css_vars: "...", google_fonts_url: "...", store_name: "..."}`.
  """
  def load(channel \\ nil) do
    cache_opts = if channel, do: [channel: channel], else: []

    case cache_get(cache_opts) do
      {:ok, cached} ->
        cached

      {:stale, cached} ->
        # Only one process refreshes per channel — prevent stampede
        refresh_key = {:refreshing, channel}

        if ets_insert_new(refresh_key) do
          Task.start(fn ->
            refresh_cache(channel)
            ets_delete(refresh_key)
          end)
        end

        cached

      :miss ->
        result = fetch_and_derive(channel)
        cache_put(result, cache_opts)
        result
    end
  end

  defp ets_insert_new(key) do
    :ets.insert_new(@cache_table, {key, true})
  rescue
    ArgumentError -> false
  end

  defp ets_delete(key) do
    :ets.delete(@cache_table, key)
  rescue
    ArgumentError -> :ok
  end

  defp refresh_cache(channel) do
    cache_opts = if channel, do: [channel: channel], else: []
    result = fetch_and_derive(channel)
    cache_put(result, cache_opts)
    :ok
  end

  defp fetch_and_derive(channel) do
    theme = fetch_and_parse(channel)

    %{
      theme: theme,
      css_vars: to_css_vars(theme),
      google_fonts_url: google_fonts_url(theme),
      store_name: store_name(theme)
    }
  end

  defp fetch_and_parse(channel) do
    slot_key = theme_slot_key(channel)

    case Api.get_storefront_slot(slot_key) do
      {:ok, %{"payload_json" => payload}} when is_map(payload) ->
        payload |> parse() |> validate()

      {:ok, %{"payload_json" => payload}} when is_binary(payload) ->
        case Jason.decode(payload) do
          {:ok, map} ->
            map |> parse() |> validate()

          {:error, reason} ->
            Logger.warning("StorefrontTheme: failed to decode payload_json: #{inspect(reason)}")
            defaults()
        end

      {:error, reason} ->
        Logger.warning("StorefrontTheme: failed to load slot: #{inspect(reason)}")
        defaults()

      _ ->
        defaults()
    end
  end

  @doc """
  Returns the slot key for the given channel.

  - `nil` → `"storefront_theme"` (backward compatible)
  - default channel → `"storefront_theme"` (backward compatible)
  - other channel → `"storefront_theme--{channel}"` (scoped)
  """
  def theme_slot_key(nil), do: "storefront_theme"

  def theme_slot_key(channel) when is_binary(channel) do
    default = Application.get_env(:jarga_admin, :default_channel, "online-store")

    if channel == default do
      "storefront_theme"
    else
      sanitized = Regex.replace(~r/[^a-zA-Z0-9\-]/, channel, "")

      if sanitized == "" do
        "storefront_theme"
      else
        "storefront_theme--#{String.slice(sanitized, 0, 64)}"
      end
    end
  end

  # ── ETS Cache ────────────────────────────────────────────────────────────

  @doc "Initialize the ETS cache table. Called from application.ex."
  def init_cache do
    :ets.new(@cache_table, [:set, :public, :named_table, {:read_concurrency, true}])
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc false
  def cache_get(opts \\ []) do
    key = cache_key(opts)

    case :ets.lookup(@cache_table, key) do
      [{^key, data, expires_at}] ->
        now = System.monotonic_time(:second)

        cond do
          now < expires_at -> {:ok, data}
          # Stale but usable — serve while refreshing in background
          true -> {:stale, data}
        end

      _ ->
        :miss
    end
  end

  @doc false
  def cache_put(data, opts \\ []) do
    key = cache_key(opts)
    ttl = Keyword.get(opts, :ttl_seconds, @default_ttl_seconds)
    expires_at = System.monotonic_time(:second) + ttl
    :ets.insert(@cache_table, {key, data, expires_at})
    :ok
  end

  defp cache_key(opts) do
    default = Application.get_env(:jarga_admin, :default_channel, "online-store")

    case Keyword.get(opts, :channel) do
      nil -> @cache_key
      ^default -> @cache_key
      channel -> {:theme, channel}
    end
  end

  @doc false
  def cache_clear do
    :ets.delete_all_objects(@cache_table)
    :ok
  rescue
    ArgumentError -> :ok
  end
end
